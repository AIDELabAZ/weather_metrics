"""
Fixed-label classifier for the Sankey categories: assigns each cleaned entry
to one label of the fixed taxonomy in sankey_taxonomy.py, so every extraction
model's Sankey uses the same categories.

Two stages:
  1. Embedding retrieval — embed the entry (as an instructed query) and every
     "<label>: <definition>" string; keep the RERANK_TOP_K most similar labels.
  2. Reranking — score each (entry, candidate label) pair with a reranker and
     take the highest. The Other label (sankey_taxonomy.OTHER_DEFINITIONS) is
     always one of the candidates, so "fits nothing" is decided by the same
     comparison rather than by a score threshold.

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

from sankey_taxonomy import OTHER_DEFINITIONS, SIDE_DESCRIPTIONS, TAXONOMIES

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
RERANK_TOP_K = 5        # candidate labels per entry passed to the reranker
RERANK_BATCH_SIZE = 16

CACHE_PATH = os.path.join(os.path.dirname(__file__), ".sankey_fixed_label_cache.json")

DEVICE = "mps" if torch.backends.mps.is_available() else ("cuda" if torch.cuda.is_available() else "cpu")
# fp16 on MPS/CUDA (M1 has no native bf16); fp32 on CPU.
DTYPE = torch.float32 if DEVICE == "cpu" else torch.float16


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
    # Stricter than the retrieval instruction: a "does this doc meet the
    # requirements" framing let the reranker say yes to most candidates
    # (scores saturated near 1.0), so ask whether it is THE right category.
    return (f"The Query is the name of {SIDE_DESCRIPTIONS[side_name]} extracted from an "
            f"economics paper. Answer yes only if the Document is the single most accurate "
            f"category for what the Query measures, and no if another category would fit better "
            f"or if the Query is not a meaningful variable name")


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
    return q @ d.T


# ─── Stage 2: reranking ───────────────────────────────────────────────────
_QWEN3_RERANK_PREFIX = (
    "<|im_start|>system\nJudge whether the Document meets the requirements based on the "
    "Query and the Instruct provided. Note that the answer can only be \"yes\" or \"no\"."
    "<|im_end|>\n<|im_start|>user\n"
)
_QWEN3_RERANK_SUFFIX = "<|im_end|>\n<|im_start|>assistant\n<think>\n\n</think>\n\n"


def _qwen3_rerank(model_name: str, pairs: list[tuple[str, str]], instruction: str) -> np.ndarray:
    from transformers import AutoModelForCausalLM, AutoTokenizer

    tok = AutoTokenizer.from_pretrained(model_name, padding_side="left")
    model = AutoModelForCausalLM.from_pretrained(model_name, dtype=DTYPE).to(DEVICE).eval()
    yes_id = tok.convert_tokens_to_ids("yes")
    no_id = tok.convert_tokens_to_ids("no")

    scores = []
    with torch.no_grad():
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
    del model
    _free_device_memory()

    out = np.concatenate(scores) if scores else np.array([])
    if np.isnan(out).any():
        raise RuntimeError("Reranker produced NaN scores — likely fp16 overflow; set DTYPE = torch.float32.")
    return out


def _cross_encoder_rerank(model_name: str, pairs: list[tuple[str, str]]) -> np.ndarray:
    from sentence_transformers import CrossEncoder

    model = CrossEncoder(model_name, device=DEVICE, model_kwargs={"dtype": DTYPE})
    out = model.predict(pairs, batch_size=RERANK_BATCH_SIZE, show_progress_bar=True)
    del model
    _free_device_memory()
    return np.asarray(out, dtype=float)


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
    key = json.dumps([backbone, spec, side_name, docs, RERANK_TOP_K,
                      _embed_instruction(side_name), _rerank_instruction(side_name)], sort_keys=True)
    return hashlib.sha256(key.encode("utf-8")).hexdigest()


# ─── Public entry point ───────────────────────────────────────────────────
def classify(
    entries: list[str],
    side_name: str,
    other_label: str,
    backbone: str | None = None,
) -> tuple[dict[str, str], pd.DataFrame]:
    """
    Returns ({entry: label}, audit) where audit has one row per entry with the
    chosen label, its reranker score, the runner-up, and the embedding top-1 —
    low scores / small margins are the entries worth eyeballing.
    """
    backbone = backbone or BACKBONE
    spec = BACKBONES[backbone]
    labels, docs = _label_docs(side_name, other_label)
    other_idx = len(labels) - 1

    cache = _load_cache()
    ns = _cache_namespace(backbone, side_name, docs)
    side_cache = cache.setdefault(ns, {})
    todo = [e for e in entries if e not in side_cache]

    if todo:
        print(f"  [{backbone}] scoring {len(todo)} new entries "
              f"({len(entries) - len(todo)} cached) on {DEVICE}...")
        sims = _embed_similarities(spec, todo, docs[:other_idx], _embed_instruction(side_name))
        k = min(RERANK_TOP_K, other_idx)
        top_idx = np.argsort(-sims, axis=1)[:, :k]
        top_idx = np.hstack([top_idx, np.full((len(todo), 1), other_idx)])
        k += 1

        pairs = [(e, docs[j]) for e, row in zip(todo, top_idx) for j in row]
        if spec["rerank_kind"] == "qwen3":
            flat = _qwen3_rerank(spec["rerank_model"], pairs, _rerank_instruction(side_name))
        else:
            flat = _cross_encoder_rerank(spec["rerank_model"], pairs)
        rr = flat.reshape(len(todo), k)

        for e, cand, s, sim_row in zip(todo, top_idx, rr, sims):
            order = np.argsort(-s)
            side_cache[e] = {
                "top1": labels[cand[order[0]]],
                "top1_score": float(s[order[0]]),
                "top2": labels[cand[order[1]]],
                "top2_score": float(s[order[1]]),
                "embed_top1": labels[int(np.argmax(sim_row))],
                "embed_top1_sim": float(np.max(sim_row)),
            }
        _save_cache(cache)

    mapping, rows = {}, []
    for e in entries:
        r = side_cache[e]
        mapping[e] = r["top1"]
        rows.append({"side": side_name, "backbone": backbone, "entry": e, "label": r["top1"], **r})
    return mapping, pd.DataFrame(rows)
