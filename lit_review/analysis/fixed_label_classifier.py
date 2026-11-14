"""
Fixed-label classifier for the Sankey categories: assigns each cleaned entry
to one label of the fixed taxonomy in sankey_taxonomy.py (loaded from
taxonomies/*.json), so every extraction model's Sankey uses the same
categories. Each entry ends up in a real category, Other, or Unclassifiable.

Two independent questions are asked of every entry:

  Category (shared by both gates): embed the entry and every
     "<label>: <definition>" string (embed_only, for comparison only), then
     score every real category AND Other with the reranker and take the
     argmax. Other is a candidate because the taxonomy defines it positively
     (a legible variable that fits no category).

  Gate: can the entry be interpreted at all? If not -> Unclassifiable,
     whatever the category step chose. Two interchangeable gates (GATE):
       "reranker" — the reranker answers yes/no against a positive definition
                    (sankey_taxonomy.INTERPRETABLE_DEFINITIONS). Nov 2026
                    probe: separates junk from real entries no better than
                    chance (it scores topical resemblance, so "quantity" passes
                    and "mother's adult height (cm)" fails).
       "judge"    — rules first (corrupted text, short / letter-digit codes,
                    see unclassifiable_rule), then a general Qwen3 chat model
                    of the same size is asked whether the name identifies a
                    specific measure, given the taxonomy's Unclassifiable
                    definition. P(yes) from its first-token logits. Too
                    strict: rejects single concepts such as "income".
       "concept"  — same rules, plus bare_rainfall_rule on the rainfall side
                    (the only rainfall names too vague to interpret are the
                    bare word and its square, a fixed list), then the chat
                    model is asked a field-neutral question: does the name
                    refer to a recognizable concept or measure? Nothing in
                    the prompt names a field or lists in-domain examples, so
                    off-list topics (pollution, temperature, institutions)
                    are not penalised.
     Both use P(yes) >= GATE_THRESHOLD = 0.5, a yes/no probability's natural
     cut-off, not a tuned score threshold.

This follows the taxonomy notes: "First assess whether the variable can be
interpreted; then assess category fit." (The two are computed independently
and combined afterwards.)

History: before Nov 2026 Other was defined negatively and judged with a
strict "is this THE single best category" instruction, which sent 60-77% of
endogenous entries to Other.

Backbones are swappable (BACKBONES below) so the categorization itself can be
checked for robustness. Only the argmax over candidates is used for the
category, never an absolute score.

Results are cached per entry in separate namespaces for the category step and
each gate, keyed by everything that affects the scores (models, taxonomy,
prompts), so switching gate never re-scores categories and editing the
taxonomy never returns a stale label.
"""

import gc
import hashlib
import json
import os
import re

import numpy as np
import pandas as pd
import torch

from sankey_taxonomy import (INTERPRETABLE_DEFINITIONS, OTHER_DEFINITIONS, SIDE_DESCRIPTIONS, TAXONOMIES,
                            UNCLASSIFIABLE_CUES, UNCLASSIFIABLE_DEFINITIONS, other_label, unclassifiable_label)

# ─── Backbones ────────────────────────────────────────────────────────────
# rerank_kind:
#   "qwen3"         — Qwen3-Reranker: causal LM, score = P("yes") from the
#                     final-token logits (format from the model card).
#   "cross-encoder" — sentence-transformers CrossEncoder (sigmoid score).
# embed_instruct: Qwen3-Embedding expects queries prefixed with
#   "Instruct: ...\nQuery:"; bge-m3 takes raw text.
# judge_model: general chat model for the "judge" gate, same size as the pair.
# Models are loaded one at a time; the 8B ones need ~16 GB each in fp16.
BACKBONES: dict[str, dict] = {
    "qwen3-4b": dict(
        embed_model="Qwen/Qwen3-Embedding-4B",
        embed_instruct=True,
        rerank_model="Qwen/Qwen3-Reranker-4B",
        rerank_kind="qwen3",
        judge_model="Qwen/Qwen3-4B",
    ),
    "qwen3-8b": dict(
        embed_model="Qwen/Qwen3-Embedding-8B",
        embed_instruct=True,
        rerank_model="Qwen/Qwen3-Reranker-8B",
        rerank_kind="qwen3",
        judge_model="Qwen/Qwen3-8B",
    ),
        "qwen3-0.6b": dict(
        embed_model="Qwen/Qwen3-Embedding-0.6B",
        embed_instruct=True,
        rerank_model="Qwen/Qwen3-Reranker-0.6B",
        rerank_kind="qwen3",
        judge_model="Qwen/Qwen3-0.6B",
    ),
    # Non-Qwen robustness check.
    "bge": dict(
        embed_model="BAAI/bge-m3",
        embed_instruct=False,
        rerank_model="BAAI/bge-reranker-v2-m3",
        rerank_kind="cross-encoder",
        judge_model="Qwen/Qwen3-8B",   # no bge chat model; judge is shared with qwen3-8b
    ),
}

BACKBONE = "qwen3-4b"
GATE = os.environ.get("SANKEY_GATE", "reranker")   # "reranker" or "judge", see module docstring
GATES = ("reranker", "judge", "concept")
# Part of the cache keys; bump when the scoring logic changes.
CATEGORY_METHOD = "category-v1"
GATE_METHOD = {"reranker": "reranker-gate-v1", "judge": "judge-gate-v1", "concept": "concept-gate-v1"}
# Real-category candidates per entry passed to the reranker (Other is always
# added); None = every category. All ~22 are cheap to score, and the
# embedding top-1 looked biased under the old taxonomy, so don't let
# retrieval prune the right label.
RERANK_TOP_K: int | None = None
GATE_THRESHOLD = 0.5     # P(yes) for the gate's "can this entry be interpreted?" question
RERANK_BATCH_SIZE = 16
JUDGE_BATCH_SIZE = 8

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


def _label_docs(side_name: str) -> tuple[list[str], list[str]]:
    """Real labels first, Other last (it is always among the reranker's
    candidates, whatever RERANK_TOP_K retrieval keeps). The document text
    uses the bare category name "Other"; the label returned is
    "Other (<side>)"."""
    taxonomy = {**TAXONOMIES[side_name], "Other": OTHER_DEFINITIONS[side_name]}
    labels = list(TAXONOMIES[side_name]) + [other_label(side_name)]
    return labels, [f"{name}: {definition}" for name, definition in taxonomy.items()]


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
            f"{SIDE_DESCRIPTIONS[side_name]}. Judge whether the Query identifies a measure of the "
            f"kind the Document describes. Answer no only if its meaning cannot be determined from "
            f"the text: an unexplained code or abbreviation, a generic label, an incomplete "
            f"fragment, corrupted or uninterpretable text{UNCLASSIFIABLE_CUES[side_name]}")


# ─── Judge gate ───────────────────────────────────────────────────────────
# Examples of names that DO identify a measure, from the taxonomy notes and
# category examples (kept out of the evaluation entries).
_JUDGE_YES_EXAMPLES: dict[str, str] = {
    "Rainfall Metrics": '"total annual rainfall", "number of rainy days", "monsoon onset", "wind speed"',
    "Endogenous Variables": '"farm income", "agricultural employment", "agricultural exports", '
                            '"government health expenditure"',
}


def _judge_prompt(side_name: str, entry: str) -> str:
    return (
        f"You are screening variable names that a language model extracted from economics papers. "
        f"Each name is supposed to be {SIDE_DESCRIPTIONS[side_name]}. Before the name is assigned to a "
        f"category, decide whether it is interpretable: does the name, on its own, identify a specific "
        f"measure, so that a reader knows what was measured?\n\n"
        f"Answer no (not interpretable) for: {UNCLASSIFIABLE_DEFINITIONS[side_name]}.\n\n"
        f"Answer yes for any name that identifies a specific measure, even if it is unusual, outside "
        f"economics, or fits no standard category, for example {_JUDGE_YES_EXAMPLES[side_name]}. "
        f"Familiar economics vocabulary is not enough: a generic word that names no specific measure "
        f"is not interpretable.\n\n"
        f"Name: \"{entry}\"\n"
        f"Is this name interpretable? Answer with one word: yes or no."
    )


# "concept" gate: field-neutral. Every example below is absent from the
# extracted entries, so the prompt doesn't hand the answer for any entry.
# v1 passed generic labels ("quantity", "driving factor", "lagged dependent
# variable") and rejected truncated but clear descriptions; v2 fixes both.
# v2 overshot: its "the dummy" / "lagged term" / "interaction term" examples
# made it reject any entry containing those words ("log rainfall * price up",
# "lagged gdp per capita"), plus single nouns like "trade" and "output". v3 =
# v1 + refusals only for generic words / roles / periods STANDING ALONE.
CONCEPT_PROMPT = os.environ.get("SANKEY_CONCEPT_PROMPT", "v3")
_CONCEPT_PROMPTS = {}   # filled below


def _concept_prompt(side_name: str, entry: str) -> str:
    return _CONCEPT_PROMPTS[CONCEPT_PROMPT](side_name, entry)


def _concept_prompt_v3(side_name: str, entry: str) -> str:
    return (
        f"Below is a variable name that a language model extracted from a research paper. Decide "
        f"whether the name refers to a recognizable concept or measure: something a researcher could "
        f"identify from the name alone, in any field (economics, health, education, environment, "
        f"climate, politics, law, demography, etc.), even if the exact construction, units or timing "
        f"are not stated.\n\n"
        f"Answer no only if the name is:\n"
        f"- a code or unexplained abbreviation (e.g. \"ab12\", \"kx\");\n"
        f"- a piece of a sentence that names no measure (e.g. \"results suggest that the\");\n"
        f"- corrupted or garbled text;\n"
        f"- nothing but a generic word that could stand for almost any variable (e.g. \"amount\", "
        f"\"magnitude\", \"main determinant\", \"key variable\");\n"
        f"- nothing but a statistical or methodological role (e.g. \"control variables\", \"the "
        f"instrument\", \"explanatory variable\", \"error term\");\n"
        f"- nothing but a time period or lag (e.g. \"time period\", \"three-month lag\").\n"
        f"These no-cases apply only when the name contains NOTHING else. If a measure is named "
        f"anywhere in it, the answer is yes.\n\n"
        f"Answer yes for everything else, including:\n"
        f"- single common concepts, even one word (e.g. \"tourism\", \"savings\", \"capital stock\");\n"
        f"- environmental or physical measures (e.g. \"ozone levels\", \"mean wave height\");\n"
        f"- policies, laws and institutions (e.g. \"press freedom\", \"judicial independence\");\n"
        f"- a measure with a modifier: logged, lagged, squared, a dummy, an interaction, a "
        f"difference, symbols or subscripts (e.g. \"lagged tourism revenue\", \"snowfall squared\", "
        f"\"drought dummy interacted with distance\");\n"
        f"- names with repeated words, typos or standard abbreviations whose meaning is still clear "
        f"(e.g. \"school enrolment rate rate\");\n"
        f"- descriptions cut off mid-sentence that already say what was measured (e.g. \"average "
        f"daily temperature in the district where the\").\n\n"
        f"Name: \"{entry}\"\n"
        f"Answer with one word: yes or no."
    )


def _concept_prompt_v2(side_name: str, entry: str) -> str:
    return (
        f"Below is a variable name that a language model extracted from a research paper. Decide "
        f"whether the name, on its own, tells a reader WHAT was measured: a recognizable concept or "
        f"measure, in any field (economics, health, education, environment, climate, politics, law, "
        f"demography, etc.). The exact construction, units or timing need not be stated.\n\n"
        f"Answer no if the name is:\n"
        f"- a code or unexplained abbreviation (e.g. \"ab12\", \"kx\");\n"
        f"- a piece of a sentence that names no measure (e.g. \"results suggest that the\");\n"
        f"- corrupted or garbled text;\n"
        f"- a generic word or placeholder that could stand for almost any variable, so the reader "
        f"still cannot tell what was measured (e.g. \"amount\", \"magnitude\", \"the indicator\", "
        f"\"main determinant\", \"key variable\");\n"
        f"- a statistical or methodological role rather than a measure (e.g. \"control variables\", "
        f"\"the instrument\", \"explanatory variable\", \"interaction term\", \"the dummy\", "
        f"\"lagged term\", \"fixed effects\");\n"
        f"- only a time period, date range or lag with no measured quantity (e.g. \"time period\", "
        f"\"three-month lag\").\n\n"
        f"Answer yes for everything else, including:\n"
        f"- single common concepts (e.g. \"literacy\", \"savings\") and environmental or physical "
        f"measures (e.g. \"ozone levels\", \"mean wave height\");\n"
        f"- policies, laws and institutions (e.g. \"press freedom\", \"judicial independence\");\n"
        f"- names with symbols, subscripts or standard abbreviations whose meaning is still clear;\n"
        f"- descriptions that are cut off mid-sentence but already say what was measured (e.g. "
        f"\"average daily temperature in the district where the\").\n\n"
        f"Name: \"{entry}\"\n"
        f"Answer with one word: yes or no."
    )


def _concept_prompt_v1(side_name: str, entry: str) -> str:
    return (
        f"Below is a variable name that a language model extracted from a research paper. Decide "
        f"whether the name refers to a recognizable concept or measure: something a researcher could "
        f"identify from the name alone, in any field (economics, health, education, environment, "
        f"climate, politics, law, demography, etc.), even if the exact construction, units or timing "
        f"are not stated.\n\n"
        f"Answer no only if the name is:\n"
        f"- a code or unexplained abbreviation (e.g. \"ab12\", \"kx\");\n"
        f"- an incomplete fragment or piece of a sentence (e.g. \"results suggest that the\");\n"
        f"- corrupted or garbled text;\n"
        f"- or a label so generic it could mean almost anything (e.g. \"outcome\", \"factor\", "
        f"\"the variable\", \"value\").\n\n"
        f"Answer yes for everything else, including single common concepts (e.g. \"literacy\", "
        f"\"savings\"), environmental or physical measures (e.g. \"ozone levels\", \"snow cover\"), "
        f"policies, laws and institutions (e.g. \"press freedom\", \"judicial independence\"), and "
        f"names with symbols or subscripts whose meaning is still clear.\n\n"
        f"Name: \"{entry}\"\n"
        f"Answer with one word: yes or no."
    )


_CONCEPT_PROMPTS.update(v1=_concept_prompt_v1, v2=_concept_prompt_v2, v3=_concept_prompt_v3)


# Rainfall names that state no construction at all (user decision, Nov 2026):
# the bare word, optionally squared. "log rainfall", "rainfall dummy", "lags
# of rainfall" etc. are interpretable (log of the total, rained / didn't
# rain, ...) and are NOT listed. Matched after lower-casing and trimming.
BARE_RAINFALL = {
    "rainfall", "rainfalls", "rain", "precipitation",
    "rainfall squared", "rainfall square", "precipitation squared", "precipitation square",
}


def bare_rainfall_rule(entry: str) -> str:
    return "bare rainfall" if entry.strip().lower() in BARE_RAINFALL else ""


# Names that say nothing about what was measured: generic words, statistical
# roles, bare periods/lags, and sentence fragments. No single judge prompt
# separated these from real one-word concepts ("trade", "output") — v2
# rejected both, v1/v3 passed both — so they are a fixed, editable list
# (Nov 2026, from the 8B v1-v3 runs). Ambiguous names (delays, mafia,
# density, revenues, quality, efficiency) are deliberately left to the judge.
GENERIC_LABELS = {
    # generic words
    "quantity", "driving factor", "factor", "factors", "economic outcomes", "their derivatives",
    "anticipated", "other cities",
    # statistical / methodological roles
    "dummy", "constant", "mediator", "lagged", "instrumental variables", "endogenous regressor",
    "endogenous dummy variable", "lagged endogenous variables", "lagged dependent variable",
    "lagged dependent variables", "lagged dependent variable (yit-1)", "spatial lag of dependent variable",
    "spatially lagged dependent variable", "spatially-lagged dependent variable",
    "the rainfall variables",
    # bare periods / lags
    "1960–98", "previous 14 days", "2-weekly lag", "1-weekly lag", "second weeks",
    # sentence fragments
    "another example is the allocation of new deal", "other variables like the severity of rioting are",
}


def generic_label_rule(entry: str) -> str:
    return "generic label" if entry.strip().lower() in GENERIC_LABELS else ""


# Rules that send obvious junk to Unclassifiable before the judge is asked.
# Entries are already lower-cased by clean_entry(). Edit the allow-list when a
# real short abbreviation gets caught.
RULES_VERSION = "rules-v1"
KNOWN_ABBREVIATIONS = {
    # rainfall / climate / pollution (tx10p etc. are ETCCDI temperature-extremes indices)
    "spi", "spei", "pdsi", "ndvi", "evi", "enso", "nao", "iod", "rain", "co", "co2", "no2", "so2", "pm10",
    "pm2.5", "aqi", "tx10p", "tx90p", "tn10p", "tn90p",
    # economic
    "gdp", "gnp", "gni", "cpi", "fdi", "tfp", "tot", "oda", "hiv", "bmi", "imr", "waz", "haz", "whz",
    # short real words
    "age", "aid", "gas", "oil", "tax", "war", "sex", "rice", "corn",
}
_CORRUPTED = re.compile(r"[âãÃ�]|ëœ|â€")
_LETTER_DIGIT_CODE = re.compile(r"[a-z]{1,4}\d+[a-z]?")
# Rules must be near-certain: math notation is NOT a rule, because
# "δln(gdpi,t)" or "transferi,t" are interpretable names with subscripts.


def unclassifiable_rule(entry: str) -> str:
    """Name of the rule that marks `entry` Unclassifiable, or "" if none does."""
    e = entry.strip().lower()
    if _CORRUPTED.search(e):
        return "corrupted text"
    if e in KNOWN_ABBREVIATIONS or " " in e:
        return ""
    if len(e) <= 3:
        return "short code"
    if _LETTER_DIGIT_CODE.fullmatch(e):
        return "letter-digit code"
    return ""


def gate_rule(entry: str, side_name: str, gate: str) -> str:
    """The rule that sends `entry` to Unclassifiable under `gate`, or ""."""
    if gate == "reranker":
        return ""
    rule = unclassifiable_rule(entry)
    if not rule and gate == "concept":
        rule = generic_label_rule(entry)
        if not rule and side_name == "Rainfall Metrics":
            rule = bare_rainfall_rule(entry)
    return rule


def _judge_scores(model_name: str, side_name: str, entries: list[str], prompt_fn=None) -> np.ndarray:
    """P(yes) that each entry is interpretable, from a Qwen3 chat model's
    first answer token (thinking disabled); yes/no case variants summed.
    prompt_fn(side_name, entry) builds the question (default _judge_prompt)."""
    prompt_fn = prompt_fn or _judge_prompt
    from transformers import AutoModelForCausalLM, AutoTokenizer

    tok = AutoTokenizer.from_pretrained(model_name, padding_side="left")
    model = AutoModelForCausalLM.from_pretrained(model_name, dtype=DTYPE).to(DEVICE).eval()

    def single_token_ids(words):
        ids = {tok.encode(w, add_special_tokens=False)[0] for w in words
               if len(tok.encode(w, add_special_tokens=False)) == 1}
        return torch.tensor(sorted(ids), device=DEVICE)
    yes_ids = single_token_ids(["yes", "Yes", " yes", " Yes", "YES"])
    no_ids = single_token_ids(["no", "No", " no", " No", "NO"])

    prompts = [tok.apply_chat_template([{"role": "user", "content": prompt_fn(side_name, e)}],
                                       tokenize=False, add_generation_prompt=True, enable_thinking=False)
               for e in entries]
    scores = []
    with torch.no_grad():
        for i in range(0, len(prompts), JUDGE_BATCH_SIZE):
            enc = tok(prompts[i:i + JUDGE_BATCH_SIZE], padding=True, return_tensors="pt").to(DEVICE)
            logp = torch.log_softmax(model(**enc).logits[:, -1, :].float(), dim=-1)
            diff = torch.logsumexp(logp[:, yes_ids], dim=1) - torch.logsumexp(logp[:, no_ids], dim=1)
            scores.append(torch.sigmoid(diff).cpu().numpy())
    del model
    _free_device_memory()
    out = np.concatenate(scores) if scores else np.array([])
    if np.isnan(out).any():
        raise RuntimeError("Judge produced NaN scores — likely fp16 overflow; set DTYPE = torch.float32.")
    return out


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


def _hash(parts: list) -> str:
    return hashlib.sha256(json.dumps(parts, sort_keys=True).encode("utf-8")).hexdigest()


def _category_namespace(backbone: str, side_name: str, docs: list[str]) -> str:
    spec = BACKBONES[backbone]
    return _hash([CATEGORY_METHOD, spec["embed_model"], spec["embed_instruct"], spec["rerank_model"],
                  spec["rerank_kind"], side_name, docs, RERANK_TOP_K,
                  _embed_instruction(side_name), _rerank_instruction(side_name)])


def _gate_namespace(gate: str, backbone: str, side_name: str) -> str:
    spec = BACKBONES[backbone]
    if gate == "reranker":
        return _hash([GATE_METHOD[gate], spec["rerank_model"], spec["rerank_kind"], side_name,
                      INTERPRETABLE_DEFINITIONS[side_name], _validity_instruction(side_name)])
    # The rules are cheap and applied at classify() time, so they are not part of the key.
    prompt_fn = _concept_prompt if gate == "concept" else _judge_prompt
    return _hash([GATE_METHOD[gate], spec["judge_model"], side_name, prompt_fn(side_name, "{entry}")])


# ─── Manual review ────────────────────────────────────────────────────────
# Hand-checked decisions for entries the models can't judge without the
# paper. Applied after the cache, so editing the CSV never requires
# re-scoring. Columns: side, entry, model_label, model_best_category,
# decision, category_override, reason. decision is one of
#   keep           — entry is interpretable: use category_override if given,
#                    else the classifier's best stage-2 label (may be Other)
#   other          — identified measure that fits no category -> Other
#   unclassifiable — can't be interpreted -> Unclassifiable
# category_override must be a real category name from the current taxonomy.
# The review done against the pre-Nov-2026 taxonomy is kept, unapplied, in
# classifier_manual_review_old_taxonomy.csv (its overrides name old
# categories and its "other" mostly meant what is now Unclassifiable).
MANUAL_REVIEW_PATH = os.path.join(os.path.dirname(__file__), "classifier_manual_review.csv")
APPLY_MANUAL_REVIEW = True
MANUAL_DECISIONS = {"keep", "other", "unclassifiable"}


def _load_manual_review(side_name: str) -> dict[str, dict]:
    if not (APPLY_MANUAL_REVIEW and os.path.exists(MANUAL_REVIEW_PATH)):
        return {}
    df = pd.read_csv(MANUAL_REVIEW_PATH, dtype=str, keep_default_na=False)
    df = df[df["side"] == side_name]
    bad_dec = set(df["decision"].str.strip().str.lower()) - MANUAL_DECISIONS
    bad_cat = set(df["category_override"].str.strip()) - set(TAXONOMIES[side_name]) - {""}
    if bad_dec or bad_cat:
        raise ValueError(f"{MANUAL_REVIEW_PATH}: unknown decision(s) {bad_dec or ''} "
                         f"/ category_override(s) {bad_cat or ''} for {side_name}")
    return {r["entry"]: r for r in df.to_dict("records")}


# ─── Scoring (cached) ─────────────────────────────────────────────────────
def _score_categories(spec: dict, side_name: str, todo: list[str], labels: list[str],
                      docs: list[str]) -> dict[str, dict]:
    n_real = len(labels) - 1          # Other is last and always a candidate
    sims = _embed_similarities(spec, todo, docs, _embed_instruction(side_name))
    k = n_real if RERANK_TOP_K is None else min(RERANK_TOP_K, n_real)
    top_real = np.argsort(-sims[:, :n_real], axis=1)[:, :k]
    cand_idx = np.hstack([top_real, np.full((len(todo), 1), n_real)])   # + Other
    cat_pairs = [(e, docs[j]) for e, row in zip(todo, cand_idx) for j in row]
    rerank = _qwen3_rerank if spec["rerank_kind"] == "qwen3" else _cross_encoder_rerank
    (flat,) = rerank(spec["rerank_model"], [(cat_pairs, _rerank_instruction(side_name))])
    rr = flat.reshape(len(todo), k + 1)

    out = {}
    for e, cand, s, sim_row in zip(todo, cand_idx, rr, sims):
        order = np.argsort(-s)
        real_order = [o for o in order if cand[o] != n_real]
        out[e] = {
            "best_category": labels[cand[order[0]]],
            "best_score": float(s[order[0]]),
            "top2": labels[cand[order[1]]],
            "top2_score": float(s[order[1]]),
            "best_real_category": labels[cand[real_order[0]]],
            "best_real_score": float(s[real_order[0]]),
            "other_score": float(s[-1]),
            "embed_top1": labels[int(np.argmax(sim_row))],
            "embed_top1_sim": float(np.max(sim_row)),
        }
    return out


def _score_gate(gate: str, spec: dict, side_name: str, todo: list[str]) -> dict[str, float]:
    if gate == "reranker":
        pairs = [(e, INTERPRETABLE_DEFINITIONS[side_name]) for e in todo]
        rerank = _qwen3_rerank if spec["rerank_kind"] == "qwen3" else _cross_encoder_rerank
        (scores,) = rerank(spec["rerank_model"], [(pairs, _validity_instruction(side_name))])
    else:
        scores = _judge_scores(spec["judge_model"], side_name, todo,
                               _concept_prompt if gate == "concept" else _judge_prompt)
    return {e: float(v) for e, v in zip(todo, scores)}


# ─── Public entry point ───────────────────────────────────────────────────
def classify(
    entries: list[str],
    side_name: str,
    backbone: str | None = None,
    gate: str | None = None,
) -> tuple[dict[str, str], pd.DataFrame]:
    """
    Returns ({entry: label}, audit). Labels are a real category,
    "Other (<side>)" or "Unclassifiable (<side>)". The audit has one row per
    entry with the final label, the gate's P(yes) (valid_score) and, for the
    judge gate, the rule that fired (unclassifiable_rule), the category step's
    argmax (best_category, may be Other), the best real category (kept even
    when the entry went to Other or Unclassifiable), the runner-up, and the
    embedding top-1. Low valid_score and small margins are worth eyeballing.
    """
    backbone = backbone or BACKBONE
    gate = gate or GATE
    if gate not in GATES:
        raise ValueError(f"gate must be one of {GATES}, not {gate!r}")
    spec = BACKBONES[backbone]
    labels, docs = _label_docs(side_name)
    other, unclassifiable = other_label(side_name), unclassifiable_label(side_name)

    cache = _load_cache()
    cat_cache = cache.setdefault(_category_namespace(backbone, side_name, docs), {})
    gate_cache = cache.setdefault(_gate_namespace(gate, backbone, side_name), {})

    todo = [e for e in entries if e not in cat_cache]
    if todo:
        print(f"  [{backbone}] scoring categories for {len(todo)} new entries "
              f"({len(entries) - len(todo)} cached) on {DEVICE}...")
        cat_cache.update(_score_categories(spec, side_name, todo, labels, docs))
        _save_cache(cache)
    todo = [e for e in entries if e not in gate_cache]
    if todo:
        print(f"  [{backbone}] scoring the {gate} gate for {len(todo)} new entries "
              f"({len(entries) - len(todo)} cached) on {DEVICE}...")
        gate_cache.update(_score_gate(gate, spec, side_name, todo))
        _save_cache(cache)

    review = _load_manual_review(side_name)
    mapping, rows = {}, []
    for e in entries:
        r = cat_cache[e]
        valid = gate_cache[e]
        rule = gate_rule(e, side_name, gate)
        # Allow-listed abbreviations (co, tx10p, gdp...) are known measures: the
        # concept gate passes them whatever the judge says.
        known = gate == "concept" and e.strip().lower() in KNOWN_ABBREVIATIONS
        model_label = r["best_category"] if (known or valid >= GATE_THRESHOLD) and not rule else unclassifiable
        label, manual = model_label, ""
        if e in review:
            m = review[e]
            decision = m["decision"].strip().lower()
            if decision == "other":
                label, manual = other, "other"
            elif decision == "unclassifiable":
                label, manual = unclassifiable, "unclassifiable"
            else:
                label = m["category_override"].strip() or r["best_category"]
                manual = "override" if m["category_override"].strip() else "keep"
        mapping[e] = label
        rows.append({"side": side_name, "backbone": backbone, "gate": gate, "entry": e, "label": label,
                     "manual_review": manual, "model_label": model_label, "valid_score": valid,
                     "unclassifiable_rule": rule, **r})
    return mapping, pd.DataFrame(rows)
