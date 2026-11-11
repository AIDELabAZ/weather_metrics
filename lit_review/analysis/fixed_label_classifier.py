"""
Fixed-label classifier for the Sankey categories: assigns each cleaned entry
to one label of the fixed taxonomy in sankey_taxonomy.py, so every extraction
model's Sankey uses the same categories.

Stages (METHOD = "two-stage-v1"):
  1. Validity — the reranker answers "is this entry a meaningful variable of
     this side?" against a positive definition (sankey_taxonomy.
     VALID_DEFINITIONS). P(yes) < VALID_THRESHOLD -> Other. This is a yes/no
     probability, so 0.5 is its natural cut-off, not a tuned score threshold.
  2. Category — embed the entry and every "<label>: <definition>" string, keep
     the RERANK_TOP_K most similar real labels (None = all of them), score each
     (entry, label) pair with the reranker and take the argmax.

Before Nov 2026 the Other label (OTHER_DEFINITIONS, phrased negatively: "not a
meaningful ...") was just one more reranker candidate, judged with a strict
"is this THE single best category" instruction. That sent 60-77% of
endogenous entries to Other even with the 8B models, including clearly
classifiable ones ("change in consumption", "carbon monoxide"), so validity
and category choice are now separate questions.

Backbones are swappable (BACKBONES below) so the categorization itself can be
checked for robustness — the default is Qwen3; "bge" is a non-Qwen
alternative. Only the argmax over candidates is used, never an absolute
score, since reranker scores aren't on a common scale across model families.

Results are cached per entry, keyed by (backbone, side, taxonomy), so entries
shared across extraction models are only scored once, and editing the
taxonomy or switching backbone never returns a stale label.
"""

import gc
import hashlib
import json
import os

import numpy as np
import pandas as pd
import torch

from sankey_taxonomy import OTHER_DEFINITIONS, SIDE_DESCRIPTIONS, TAXONOMIES, VALID_DEFINITIONS

# ─── Backbones ────────────────────────────────────────────────────────────
# rerank_kind:
#   "qwen3"         — Qwen3-Reranker: causal LM, score = P("yes") from the
#                     final-token logits (format from the model card).
#   "cross-encoder" — sentence-transformers CrossEncoder (sigmoid score).
# embed_instruct: Qwen3-Embedding expects queries prefixed with
#   "Instruct: ...\nQuery:"; bge-m3 takes raw text.
# The 8B Qwen3 models need ~16 GB each in fp16 — too much for a 16 GB M1;
# the 4B pair fits when loaded one at a time (which classify() does).
BACKBONES: dict[str, dict] = {
    "qwen3-4b": dict(
        embed_model="Qwen/Qwen3-Embedding-4B",
        embed_instruct=True,
        rerank_model="Qwen/Qwen3-Reranker-4B",
        rerank_kind="qwen3",
    ),
    "qwen3-8b": dict(
        embed_model="Qwen/Qwen3-Embedding-8B",
        embed_instruct=True,
        rerank_model="Qwen/Qwen3-Reranker-8B",
        rerank_kind="qwen3",
    ),
    # Small pair for smoke-testing the pipeline only.
    "qwen3-0.6b": dict(
        embed_model="Qwen/Qwen3-Embedding-0.6B",
        embed_instruct=True,
        rerank_model="Qwen/Qwen3-Reranker-0.6B",
        rerank_kind="qwen3",
    ),
    # Non-Qwen robustness check.
    "bge": dict(
        embed_model="BAAI/bge-m3",
        embed_instruct=False,
        rerank_model="BAAI/bge-reranker-v2-m3",
        rerank_kind="cross-encoder",
    ),
}

BACKBONE = "qwen3-4b"
METHOD = "two-stage-v1"  # part of the cache key; bump when the scoring logic changes
# Candidate labels per entry passed to the reranker; None = every real label.
# All 23 are cheap to score, and the embedding top-1 looked biased (many
# unrelated entries -> "Household Income & Consumption"), so don't let
# retrieval prune the right label.
RERANK_TOP_K: int | None = None
VALID_THRESHOLD = 0.5    # P(yes) for the stage-1 "is this a real variable?" question
RERANK_BATCH_SIZE = 16

# Overridable so the HPC job (analysis/hpc/) can write a separate cache that
# is merged back into the local one afterwards.
CACHE_PATH = os.environ.get(
    "SANKEY_CLASSIFIER_CACHE",
    os.path.join(os.path.dirname(__file__), ".sankey_fixed_label_cache.json"),
)

DEVICE = "mps" if torch.backends.mps.is_available() else ("cuda" if torch.cuda.is_available() else "cpu")
# fp16 on MPS (M1 has no native bf16); bf16 on CUDA GPUs that support it
# (A100 — no fp16 overflow risk), else fp16; fp32 on CPU. Precision is not
# part of the cache key: it only changes scores in the last few digits.
if DEVICE == "cpu":
    DTYPE = torch.float32
# Native bf16 needs compute capability >= 8 (A100); is_bf16_supported() can
# report True on a V100 via slow emulation, so check the hardware directly.
elif DEVICE == "cuda" and torch.cuda.get_device_capability()[0] >= 8:
    DTYPE = torch.bfloat16
else:
    DTYPE = torch.float16


def _label_docs(side_name: str, other_label: str) -> tuple[list[str], list[str]]:
    """Real labels first, Other last (it is excluded from embedding retrieval
    and appended to every entry's reranker candidates instead)."""
    taxonomy = {**TAXONOMIES[side_name], other_label: OTHER_DEFINITIONS[side_name]}
    labels = list(taxonomy)
    return labels, [f"{label}: {taxonomy[label]}" for label in labels]


def _embed_instruction(side_name: str) -> str:
    return (f"Given the name of {SIDE_DESCRIPTIONS[side_name]} extracted from an economics "
            f"paper, retrieve the category that best describes what it measures")


def _rerank_instruction(side_name: str) -> str:
    # Plain relevance: the argmax over candidates does the comparison, so the
    # instruction needn't ask for "the single best" (which depressed every
    # real label's score and let Other win — see module docstring).
    return (f"Given the name of {SIDE_DESCRIPTIONS[side_name]} extracted from an economics "
            f"paper, judge whether the Document is a category that describes what the Query measures")


def _validity_instruction(side_name: str) -> str:
    return (f"The Query was extracted from an economics paper as the name of "
            f"{SIDE_DESCRIPTIONS[side_name]}. Judge whether the Query names a variable of the kind "
            f"the Document describes. Answer no only if it names no such variable: it is just a "
            f"lag or time-window specification on its own, a unit, a location name, an "
            f"uninterpretable code or abbreviation, a different kind of variable, or a sentence "
            f"fragment")


def _free_device_memory() -> None:
    # Callers `del` their model first — the 4B embedder and reranker only fit
    # in 16 GB unified memory one at a time.
    gc.collect()
    if DEVICE == "mps":
        torch.mps.empty_cache()
    elif DEVICE == "cuda":
        torch.cuda.empty_cache()


# ─── Stage 1: embedding retrieval ─────────────────────────────────────────
def _embed_similarities(spec: dict, entries: list[str], docs: list[str], instruction: str) -> np.ndarray:
    from sentence_transformers import SentenceTransformer

    model = SentenceTransformer(
        spec["embed_model"],
        device=DEVICE,
        model_kwargs={"dtype": DTYPE},
        processor_kwargs={"padding_side": "left"},
    )
    prompt = f"Instruct: {instruction}\nQuery:" if spec["embed_instruct"] else None
    q = model.encode(entries, prompt=prompt, normalize_embeddings=True, show_progress_bar=True)
    d = model.encode(docs, normalize_embeddings=True)
    del model
    _free_device_memory()
    if np.isnan(q).any() or np.isnan(d).any():
        raise RuntimeError("Embedder produced NaN — likely fp16 overflow; set DTYPE = torch.float32.")
    return q @ d.T


# ─── Stage 2: reranking ───────────────────────────────────────────────────
_QWEN3_RERANK_PREFIX = (
    "<|im_start|>system\nJudge whether the Document meets the requirements based on the "
    "Query and the Instruct provided. Note that the answer can only be \"yes\" or \"no\"."
    "<|im_end|>\n<|im_start|>user\n"
)
_QWEN3_RERANK_SUFFIX = "<|im_end|>\n<|im_start|>assistant\n<think>\n\n</think>\n\n"


def _qwen3_rerank(model_name: str, jobs: list[tuple[list[tuple[str, str]], str]]) -> list[np.ndarray]:
    """Scores each (pairs, instruction) job with one model load."""
    from transformers import AutoModelForCausalLM, AutoTokenizer

    tok = AutoTokenizer.from_pretrained(model_name, padding_side="left")
    model = AutoModelForCausalLM.from_pretrained(model_name, dtype=DTYPE).to(DEVICE).eval()
    yes_id = tok.convert_tokens_to_ids("yes")
    no_id = tok.convert_tokens_to_ids("no")

    results = []
    with torch.no_grad():
        for pairs, instruction in jobs:
            scores = []
            for i in range(0, len(pairs), RERANK_BATCH_SIZE):
                batch = pairs[i:i + RERANK_BATCH_SIZE]
                texts = [
                    f"{_QWEN3_RERANK_PREFIX}<Instruct>: {instruction}\n<Query>: {q}\n<Document>: {d}"
                    f"{_QWEN3_RERANK_SUFFIX}"
                    for q, d in batch
                ]
                enc = tok(texts, padding=True, return_tensors="pt").to(DEVICE)
                logits = model(**enc).logits[:, -1, :]
                yes_no = torch.stack([logits[:, no_id], logits[:, yes_id]], dim=1).float()
                scores.append(torch.softmax(yes_no, dim=1)[:, 1].cpu().numpy())
            out = np.concatenate(scores) if scores else np.array([])
            if np.isnan(out).any():
                raise RuntimeError("Reranker produced NaN scores — likely fp16 overflow; "
                                   "set DTYPE = torch.float32.")
            results.append(out)
    del model
    _free_device_memory()
    return results


def _cross_encoder_rerank(model_name: str, jobs: list[tuple[list[tuple[str, str]], str]]) -> list[np.ndarray]:
    """Same interface as _qwen3_rerank; cross-encoders take no instruction."""
    from sentence_transformers import CrossEncoder

    model = CrossEncoder(model_name, device=DEVICE, model_kwargs={"dtype": DTYPE})
    # bge-reranker has one output logit, which sentence-transformers passes
    # through a sigmoid, so the validity score is a probability like Qwen3's.
    results = [np.asarray(model.predict(pairs, batch_size=RERANK_BATCH_SIZE, show_progress_bar=True),
                          dtype=float) for pairs, _ in jobs]
    del model
    _free_device_memory()
    return results


# ─── Cache ────────────────────────────────────────────────────────────────
def _load_cache() -> dict:
    if os.path.exists(CACHE_PATH):
        try:
            with open(CACHE_PATH, "r", encoding="utf-8") as f:
                return json.load(f)
        except Exception:
            return {}
    return {}


def _save_cache(cache: dict) -> None:
    with open(CACHE_PATH, "w", encoding="utf-8") as f:
        json.dump(cache, f)


def _cache_namespace(backbone: str, side_name: str, docs: list[str]) -> str:
    spec = BACKBONES[backbone]
    key = json.dumps([METHOD, backbone, spec, side_name, docs, RERANK_TOP_K, VALID_THRESHOLD,
                      VALID_DEFINITIONS[side_name], _validity_instruction(side_name),
                      _embed_instruction(side_name), _rerank_instruction(side_name)], sort_keys=True)
    return hashlib.sha256(key.encode("utf-8")).hexdigest()


# ─── Manual review ────────────────────────────────────────────────────────
# Hand-checked decisions for entries the models can't judge without the
# paper: uninterpretable variable codes and econometric terms (-> Other), and
# clear category mistakes (category_override). Applied after the cache, so
# editing the CSV never requires re-scoring. The validity scores of the 8B
# models don't separate junk codes ("pr", "r20", "h3") from real variables,
# which is why this step exists. Columns: side, entry, model_label,
# model_best_category, decision (keep/other), category_override, reason.
MANUAL_REVIEW_PATH = os.path.join(os.path.dirname(__file__), "classifier_manual_review.csv")
APPLY_MANUAL_REVIEW = True


def _load_manual_review(side_name: str) -> dict[str, dict]:
    if not (APPLY_MANUAL_REVIEW and os.path.exists(MANUAL_REVIEW_PATH)):
        return {}
    df = pd.read_csv(MANUAL_REVIEW_PATH, dtype=str, keep_default_na=False)
    df = df[df["side"] == side_name]
    bad_dec = set(df["decision"].str.strip().str.lower()) - {"keep", "other"}
    bad_cat = set(df["category_override"].str.strip()) - set(TAXONOMIES[side_name]) - {""}
    if bad_dec or bad_cat:
        raise ValueError(f"{MANUAL_REVIEW_PATH}: unknown decision(s) {bad_dec or ''} "
                         f"/ category_override(s) {bad_cat or ''} for {side_name}")
    return {r["entry"]: r for r in df.to_dict("records")}


# ─── Public entry point ───────────────────────────────────────────────────
def classify(
    entries: list[str],
    side_name: str,
    other_label: str,
    backbone: str | None = None,
) -> tuple[dict[str, str], pd.DataFrame]:
    """
    Returns ({entry: label}, audit) where audit has one row per entry with the
    final label, the stage-1 validity probability, the best real category and
    its score (kept even when the entry went to Other), the runner-up, and the
    embedding top-1 — low validity / small margins are worth eyeballing.
    """
    backbone = backbone or BACKBONE
    spec = BACKBONES[backbone]
    labels, docs = _label_docs(side_name, other_label)
    n_real = len(labels) - 1          # Other is last and is not a category candidate

    cache = _load_cache()
    ns = _cache_namespace(backbone, side_name, docs)
    side_cache = cache.setdefault(ns, {})
    todo = [e for e in entries if e not in side_cache]

    if todo:
        print(f"  [{backbone}] scoring {len(todo)} new entries "
              f"({len(entries) - len(todo)} cached) on {DEVICE}...")
        sims = _embed_similarities(spec, todo, docs[:n_real], _embed_instruction(side_name))
        k = n_real if RERANK_TOP_K is None else min(RERANK_TOP_K, n_real)
        top_idx = np.argsort(-sims, axis=1)[:, :k]

        valid_pairs = [(e, VALID_DEFINITIONS[side_name]) for e in todo]
        cat_pairs = [(e, docs[j]) for e, row in zip(todo, top_idx) for j in row]
        jobs = [(valid_pairs, _validity_instruction(side_name)),
                (cat_pairs, _rerank_instruction(side_name))]
        rerank = _qwen3_rerank if spec["rerank_kind"] == "qwen3" else _cross_encoder_rerank
        valid, flat = rerank(spec["rerank_model"], jobs)
        rr = flat.reshape(len(todo), k)

        for e, v, cand, s, sim_row in zip(todo, valid, top_idx, rr, sims):
            order = np.argsort(-s)
            best = labels[cand[order[0]]]
            is_valid = bool(v >= VALID_THRESHOLD)
            side_cache[e] = {
                "top1": best if is_valid else other_label,
                "valid_score": float(v),
                "best_category": best,
                "best_score": float(s[order[0]]),
                "top2": labels[cand[order[1]]] if k > 1 else None,
                "top2_score": float(s[order[1]]) if k > 1 else None,
                "embed_top1": labels[int(np.argmax(sim_row))],
                "embed_top1_sim": float(np.max(sim_row)),
            }
        _save_cache(cache)

    review = _load_manual_review(side_name)
    mapping, rows = {}, []
    for e in entries:
        r = side_cache[e]
        label, manual = r["top1"], ""
        if e in review:
            m = review[e]
            if m["decision"].strip().lower() == "other":
                label, manual = other_label, "other"
            else:
                label = m["category_override"].strip() or r["best_category"]
                manual = "override" if m["category_override"].strip() else "keep"
        mapping[e] = label
        rows.append({"side": side_name, "backbone": backbone, "entry": e, "label": label,
                     "manual_review": manual, "model_label": r["top1"], **r})
    return mapping, pd.DataFrame(rows)
