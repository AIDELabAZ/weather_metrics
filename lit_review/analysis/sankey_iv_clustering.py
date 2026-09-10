"""
sankey_iv_clustering.py

Reads the model output CSV, categorizes endogenous variables and rainfall
metrics using an LLM (taxonomy discovery + classification in one call per
side), then generates an interactive Sankey diagram connecting rainfall
instrument types to endogenous variable categories.

Workflow:
  1. Filter to rainfall IV papers (model output ∪ human-labeled papers)
  2. Aggressively clean + normalize entries (remove noise, equations, generics)
  3. One LLM call per side: propose a topical taxonomy over all unique cleaned
     entries and classify every entry into it (or an "Other" noise bucket)
  4. Merge guardrail: collapse near-duplicate category names the LLM didn't
     consolidate itself (plural/singular variants, embedding-similar names)
  5. Export cluster_summary.csv so you can review/rename categories
  6. Build Plotly Sankey: left = rainfall metric categories, right = endog categories
  7. Save interactive HTML

After first run: review cluster_summary.csv, then add overrides to
ENDOG_LABEL_OVERRIDES / RAIN_LABEL_OVERRIDES below and rerun — LLM
classifications are cached by entry text so reruns are fast.
"""

import hashlib
import json
import os
import re
import unicodedata
from collections import Counter, defaultdict
import numpy as np
import pandas as pd
import plotly.graph_objects as go
from openai import OpenAI
from sentence_transformers import SentenceTransformer
from sklearn.metrics.pairwise import cosine_similarity

client = OpenAI(api_key=os.environ.get("OPENAI_API_KEY"))

# ─── Paths ─────────────────────────────────────────────────────────────────
INPUT_CSV              = "/Users/kieran/Library/CloudStorage/OneDrive-UniversityofArizona/weather_iv_lit/training/models/output/gpt/finetune/full_finetune_gpt_output.csv"
# Human-reviewed papers (train_80 + removed_20 combined) — unioned with the
# model output below so papers only the model saw and papers only a human
# reviewed both make it into the Sankey.
HUMAN_LABELED_XLSX     = "/Users/kieran/Library/CloudStorage/OneDrive-UniversityofArizona/weather_iv_lit/training/training_new_labels/training_all_new.xlsx"
OUTPUT_HTML            = "/Users/kieran/Library/CloudStorage/OneDrive-UniversityofArizona/weather_iv_lit/training/models/output/gpt/finetune/sankey_finetune_gpt_rainfall_iv.html"
OUTPUT_HTML_DEPVAR     = "/Users/kieran/Library/CloudStorage/OneDrive-UniversityofArizona/weather_iv_lit/training/models/output/gpt/finetune/sankey_finetune_gpt_rainfall_depvar.html"
OUTPUT_PNG             = "/Users/kieran/Library/CloudStorage/OneDrive-UniversityofArizona/weather_iv_lit/training/models/output/gpt/finetune/sankey_finetune_gpt_rainfall_iv.png"
OUTPUT_PNG_DEPVAR      = "/Users/kieran/Library/CloudStorage/OneDrive-UniversityofArizona/weather_iv_lit/training/models/output/gpt/finetune/sankey_finetune_gpt_rainfall_depvar.png"
CLUSTER_SUMMARY        = "/Users/kieran/Library/CloudStorage/OneDrive-UniversityofArizona/weather_iv_lit/training/models/output/cluster_finetune_gpt_summary.csv"
CLUSTER_SUMMARY_DEPVAR = "/Users/kieran/Library/CloudStorage/OneDrive-UniversityofArizona/weather_iv_lit/training/models/output/cluster_finetune_gpt_summary_depvar.csv"

# ─── LLM categorization params ──────────────────────────────────────────────
# Used by the broadening/consolidation pass only (_broaden_categories_once).
CATEGORY_MODEL = "gpt-4.1-2025-04-14"

# Trial: the initial taxonomy-discovery + classification call
# (classify_into_categories) uses its own model, independent of CATEGORY_MODEL,
# so this can be swapped back to a non-reasoning model (set CLASSIFY_IS_REASONING
# = False, drop CLASSIFY_REASONING_EFFORT) without touching the broadening pass.
# Reasoning models reject temperature/max_tokens — see the branch in
# classify_into_categories() below.
CLASSIFY_MODEL = "gpt-5"
CLASSIFY_IS_REASONING = True
CLASSIFY_REASONING_EFFORT = "high"  # only used when CLASSIFY_IS_REASONING
# Reasoning tokens count against this budget but never appear in the response,
# so this needs far more headroom than a non-reasoning call's max_tokens would.
CLASSIFY_MAX_COMPLETION_TOKENS = 32000

# Guardrail: after the LLM proposes/assigns categories, merge any two whose
# name embeddings have cosine similarity >= this threshold (catches
# near-duplicates the LLM itself didn't consolidate, e.g. "Labor Market"
# vs "Employment", on top of the plural/singular pass).
CATEGORY_MERGE_SIM_THRESHOLD = 0.88

CATEGORY_CACHE_PATH = os.path.join(os.path.dirname(__file__), ".sankey_category_cache.json")

# ─── Manual label overrides (optional; edit after reviewing cluster_summary.csv) ──
# Format: {"Category name the LLM/merge guardrail produced": "Desired final name"}
# Applied as a final rename pass — use only for edge cases the merge guardrail
# didn't catch (e.g. two categories that mean the same thing but aren't close
# enough in embedding space to auto-merge). Merging two categories into the
# same string combines their flows.
ENDOG_LABEL_OVERRIDES: dict[str, str] = {}
RAIN_LABEL_OVERRIDES: dict[str, str] = {}
DEPVAR_LABEL_OVERRIDES: dict[str, str] = {}

# ─── Cleaning config ───────────────────────────────────────────────────────
MAX_WORDS = 8     # truncate entries longer than this
MIN_CHARS = 5     # discard entries shorter than this after cleaning

# Entries that are ONLY these terms (after normalization) are too generic
GENERIC_TERMS = {
    "rainfall", "precipitation", "rain", "weather", "climate",
    "precip", "ppt", "instrument", "variable", "endogenous",
    "data", "index", "measure", "level", "value", "total", "which",
    "particularly", "proxy", "quarterly", "monthly", "annual",
}

# Subset of GENERIC_TERMS that IS the topic on the rainfall side (not noise
# there, unlike on the endog/depvar sides) — see the exception in clean_entry.
RAINFALL_CORE_TERMS = {"rainfall", "precipitation", "rain", "precip", "ppt"}

# For the rainfall side only: entry must contain at least one of these terms.
# "temperature"/"climate"/"weather" are deliberately excluded — they let pure
# temperature entries (e.g. "average maximum temperature") through with zero
# rainfall/precipitation content. A genuine joint rainfall+temperature
# instrument entry still passes since it also mentions rain/precip/drought/etc.
RAINFALL_REQUIRED_TERMS = {
    "rain", "rainfall", "precipitation", "precip", "ppt", "monsoon",
    "drought", "wet", "dry", "flood", "storm", "snow", "snowfall",
    "snowpack", "swe", "humidity", "moisture", "cumulative", "seasonal",
    "annual", "monthly", "weekly", "daily", "spi", "spei", "pdsi",
    "humidity", "wind", "sunshine", "cloud", "runoff", "river",
    "streamflow", "waterlog",
}

# Regex patterns that flag an entry as noise
_EQUATION_CHARS  = re.compile(r"[=<>{}\|\\^~`]|\\[a-zA-Z]+")
_MOSTLY_NUMBERS  = re.compile(r"^\s*[\d\s\.\,\-\*\[\]\(\)]+\s*$")
_YEAR_ONLY       = re.compile(r"^\s*(19|20)\d{2}[\s\)\.,]*$")
_SUBSCRIPT_BLOCK = re.compile(r"[^\x00-\x7F]{3,}")  # 3+ consecutive non-ASCII

# Variable codes: short tokens ending in common panel subscripts (lnnetit, soeit, btmit)
_SUBSCRIPT_VAR   = re.compile(r"\b[a-z]{1,6}[0-9]{0,2}(it|jt|ij|ijt|ilt|kt|ibt|abt)\b")

# Slash-separated option lists from prompts (e.g. "a/b/c/d" with 3+ slashes)
_SLASH_LIST      = re.compile(r"\w+/\w+/\w+")

# High density of English function words → likely a sentence, not a variable name
_FUNCTION_WORDS  = {
    "the", "a", "an", "is", "are", "was", "were", "be", "been",
    "we", "our", "this", "that", "these", "those", "in", "of",
    "to", "and", "or", "for", "with", "as", "by", "at", "on",
    "also", "have", "has", "not", "but", "if", "do", "from",
    "which", "who", "they", "their", "its", "it", "such",
}

_TRIVIAL = {"n/a", "na", "none", "", "x", "y", "z", "i", "t",
            "0", "1", "a", "b", "c", "d", "e", "f"}

# Stop-phrases: if entry contains any of these it's a sentence/noise
_STOP_PHRASES = [
    "the error term", "error terms", "we assume", "the paper", "we find",
    "we estimate", "we use", "panel regression", "fixed effect", "2sls",
    "we can control", "we start", "also snowfall", "do not count",
    "arguing", "the analysis", "please note", "first stage", "second stage",
    "such that", "that is", "therefore", "in order to", "do not infer",
    "output format", "keep names", "remove units", "transformation",
    "only proceed", "answer using", "output exactly", "output one",
    "the resulting term", "is endogenous", "have to proceed",
    "significant in some", "t post is a dummy", "t represent",
    "parameters to be estimated", "despite the discussion",
    "age of ministers", "the instrument to demonstrate",
    "fb mva can be accounted", "possibly unique",
    "expected productivity gain", "differences with respect",
    "low-spending counties",
]

# ─── Text normalization map ─────────────────────────────────────────────────
# Applied before embedding so "ln rainfall" and "log rainfall" land near each other
_NORMALIZATIONS = [
    # log/ln unification
    (re.compile(r"\bln\b"),             "log"),
    (re.compile(r"\blog\s*\(?\s*"),     "log "),
    # precipitation synonyms → single term
    (re.compile(r"\bprecip\b"),         "precipitation"),
    (re.compile(r"\bppt\b"),            "precipitation"),
    (re.compile(r"\brain(?:fall)?\b"),  "rainfall"),
    # time-scale normalization
    (re.compile(r"\bann(?:ual)?\b"),    "annual"),
    (re.compile(r"\bseas(?:onal)?\b"),  "seasonal"),
    (re.compile(r"\bmon(?:thly)?\b"),   "monthly"),
    (re.compile(r"\bwk|week(?:ly)?\b"), "weekly"),
    # common abbrevs
    (re.compile(r"\bgdp\b"),            "gdp per capita"),
    (re.compile(r"\bcpi\b"),            "consumer price index"),
    (re.compile(r"\bres\b"),            "renewable energy sources"),
]


def normalize_text(txt: str) -> str:
    for pattern, replacement in _NORMALIZATIONS:
        txt = pattern.sub(replacement, txt)
    return re.sub(r"\s+", " ", txt).strip()


def proportion_ascii(txt: str) -> float:
    if not txt:
        return 0.0
    ascii_chars = sum(1 for c in txt if ord(c) < 128)
    return ascii_chars / len(txt)


def is_sentence_like(txt: str) -> bool:
    """Return True if the text looks like a sentence fragment rather than a variable name."""
    words = txt.split()
    if len(words) < 4:
        return False
    func_count = sum(1 for w in words if w in _FUNCTION_WORDS)
    return (func_count / len(words)) > 0.45


def clean_entry(txt: str, requires_rainfall: bool = False) -> str | None:
    if not txt or not isinstance(txt, str):
        return None

    try:
        txt = unicodedata.normalize("NFKC", txt)
    except Exception:
        pass

    # Acronym exception: short ALL-CAPS/alnum tokens (TFP, M1, M2, CO2, GDP)
    # are real economics shorthand, not noise — MIN_CHARS would otherwise
    # discard them. Must check original case before lowercasing below, since
    # that's the only signal separating an acronym from ordinary short junk.
    is_acronym = bool(re.fullmatch(r"[A-Z][A-Z0-9]{1,5}", txt.strip()))

    txt = txt.strip().lower()

    if txt in _TRIVIAL:
        return None

    # Drop if mostly non-ASCII (unicode math, Arabic, Chinese, etc.)
    if proportion_ascii(txt) < 0.75:
        return None

    # Drop if contains 3+ consecutive non-ASCII chars (subscript blocks, etc.)
    if _SUBSCRIPT_BLOCK.search(txt):
        return None

    # Drop if looks like an equation
    if _EQUATION_CHARS.search(txt):
        return None

    # Drop slash-separated option lists (prompt text leakage: "a/b/c/d")
    if _SLASH_LIST.search(txt):
        return None

    # Drop if mostly numbers/punctuation
    if _MOSTLY_NUMBERS.match(txt):
        return None

    # Drop if just a year
    if _YEAR_ONLY.match(txt):
        return None

    # Drop if contains a stop-phrase (model captured a sentence, not a name)
    for phrase in _STOP_PHRASES:
        if phrase in txt:
            return None

    # Drop if it reads like a sentence (high function-word density)
    if is_sentence_like(txt):
        return None

    # Drop if it's a subscript variable code (lnnetit, soeit, btmit, etc.).
    # Only judge tokens long enough to plausibly BE a subscript code — with
    # none (e.g. short acronyms like "m1", "gi"), `all()` on an empty
    # generator is vacuously True, which was wrongly rejecting every short
    # entry regardless of content.
    tokens = txt.split()
    long_tokens = [tok for tok in tokens if len(tok) > 2]
    if long_tokens and all(_SUBSCRIPT_VAR.match(tok) for tok in long_tokens):
        return None

    # Remove parenthetical citations like (2020)
    txt = re.sub(r"\(\s*(?:19|20)\d{2}\s*\)", "", txt)
    txt = re.sub(r"\s+", " ", txt).strip()

    if len(txt) < MIN_CHARS and not is_acronym and not (requires_rainfall and txt.strip() in RAINFALL_CORE_TERMS):
        return None

    # Truncate to MAX_WORDS
    words = txt.split()
    if len(words) > MAX_WORDS:
        txt = " ".join(words[:MAX_WORDS])

    # After truncation, check if it reduces to a single generic term. On the
    # rainfall side, bare "rainfall"/"precipitation"/"rain" IS the topic, not
    # noise — don't discard it here; let the LLM decide whether it deserves
    # its own general/unspecified category instead of silently vanishing.
    if txt.strip() in GENERIC_TERMS and not (requires_rainfall and txt.strip() in RAINFALL_CORE_TERMS):
        return None

    # For rainfall side: require at least one weather/precip-related term.
    # Reject pure-temperature entries outright even if they also match a
    # generic time-scale word (daily/monthly/annual/etc.) — those words alone
    # don't make an entry rainfall-related, and "temperature" entries like
    # "daily high temperature" would otherwise slip through via "daily".
    if requires_rainfall:
        if not any(term in txt for term in RAINFALL_REQUIRED_TERMS):
            return None
        true_rain_terms = RAINFALL_REQUIRED_TERMS - {
            "cumulative", "seasonal", "annual", "monthly", "weekly", "daily"
        }
        if "temperature" in txt and not any(term in txt for term in true_rain_terms):
            return None

    # Normalize for embedding
    txt = normalize_text(txt)

    if len(txt) < MIN_CHARS and not is_acronym and not (requires_rainfall and txt.strip() in RAINFALL_CORE_TERMS):
        return None

    return txt


# ─── Expand semicolon-separated column, keeping paper index ────────────────
def expand_column(df: pd.DataFrame, col: str, requires_rainfall: bool = False) -> pd.DataFrame:
    records = []
    for idx, row in df.iterrows():
        val = row[col]
        if pd.isna(val):
            continue
        for part in str(val).split(";"):
            cleaned = clean_entry(part, requires_rainfall=requires_rainfall)
            if cleaned:
                records.append({"paper_idx": idx, "entry": cleaned})
    return pd.DataFrame(records)


# ─── Embed ─────────────────────────────────────────────────────────────────
def embed_texts(texts: list[str]) -> np.ndarray:
    model = SentenceTransformer("all-MiniLM-L6-v2")
    return model.encode(texts, show_progress_bar=True, normalize_embeddings=True)


# ─── LLM taxonomy discovery + classification (one call per side) ───────────
def _load_category_cache() -> dict:
    if os.path.exists(CATEGORY_CACHE_PATH):
        try:
            with open(CATEGORY_CACHE_PATH, "r", encoding="utf-8") as f:
                return json.load(f)
        except Exception:
            return {}
    return {}


def _save_category_cache(cache: dict) -> None:
    with open(CATEGORY_CACHE_PATH, "w", encoding="utf-8") as f:
        json.dump(cache, f)


_category_cache = _load_category_cache()


def classify_into_categories(entries: list[str], side_name: str, other_label: str) -> dict[str, str]:
    """
    One LLM call: given every unique cleaned entry for this side, propose a
    concise topical taxonomy (merging synonyms/plurals itself where obvious)
    and assign each entry to exactly one category, or to `other_label` if it
    doesn't fit any real category (noise, unclassifiable fragments, etc.).
    Uses CLASSIFY_MODEL (independent of CATEGORY_MODEL, which only governs the
    later broadening pass). Cached on disk keyed by (model, side_name, entries)
    so unchanged reruns are free and swapping CLASSIFY_MODEL never returns a
    stale result cached under a different model.
    Returns {entry: category}.
    """
    cache_key = hashlib.sha256(
        (CLASSIFY_MODEL + "|" + side_name + "|" + "|".join(entries)).encode("utf-8")
    ).hexdigest()
    if cache_key in _category_cache:
        return _category_cache[cache_key]

    numbered = "\n".join(f"{i}: {e}" for i, e in enumerate(entries))
    prompt = (
        f"You are categorizing short variable-name strings extracted from economics "
        f"papers, for the '{side_name}' side of a Sankey diagram.\n\n"
        f"Here are {len(entries)} unique entries (one per line, numbered):\n{numbered}\n\n"
        "Task: design a concise topical taxonomy (aim for roughly 15-30 categories) "
        "that groups these entries by economic/topical theme, then assign every "
        "entry to exactly one category.\n"
        "Rules:\n"
        "- Category names: 2-4 words, Title Case, describing the general theme "
        "(e.g. 'Agricultural Production', 'Financial Access & Credit').\n"
        "- Merge synonyms, singular/plural variants, and near-duplicate themes into "
        "ONE category yourself — do not create both 'Labor Market' and 'Labor Markets'.\n"
        f"- If an entry is noise, a sentence fragment, a variable code, or otherwise "
        f"doesn't fit any real category, assign it exactly '{other_label}'.\n"
        "- Every one of the numbered entries must appear exactly once in your answer.\n\n"
        'Respond with ONLY a JSON object: {"assignments": {"<entry index as string>": "<category>", ...}}'
    )

    if CLASSIFY_IS_REASONING:
        # Reasoning models reject temperature and the legacy max_tokens param.
        response = client.chat.completions.create(
            model=CLASSIFY_MODEL,
            messages=[{"role": "user", "content": prompt}],
            reasoning_effort=CLASSIFY_REASONING_EFFORT,
            max_completion_tokens=CLASSIFY_MAX_COMPLETION_TOKENS,
            response_format={"type": "json_object"},
        )
    else:
        response = client.chat.completions.create(
            model=CLASSIFY_MODEL,
            messages=[{"role": "user", "content": prompt}],
            temperature=0.0,
            max_tokens=8000,
            response_format={"type": "json_object"},
        )
    assignments = json.loads(response.choices[0].message.content).get("assignments", {})

    result = {}
    for i, entry in enumerate(entries):
        cat = assignments.get(str(i))
        result[entry] = cat.strip() if cat else other_label

    _category_cache[cache_key] = result
    _save_category_cache(_category_cache)
    return result


def _plural_signature(name: str) -> str:
    """Bag-of-singularized-words signature used to catch simple plural/singular
    duplicates ('Labor Market' vs 'Labor Markets') that survive the LLM pass."""
    words = re.sub(r"[^a-z0-9\s]", "", name.lower()).split()
    singularized = sorted(w[:-1] if w.endswith("s") and not w.endswith("ss") else w for w in words)
    return " ".join(singularized)


def merge_similar_category_names(
    category_counts: dict[str, int],
    other_label: str,
    threshold: float,
) -> dict[str, str]:
    """
    Guardrail over LLM-proposed category names: merge any two whose
    plural-insensitive signature matches, then merge any two whose name
    embeddings have cosine similarity >= threshold. The canonical name for a
    merged group is whichever original name has the most entries (ties broken
    alphabetically), so the more heavily-used name wins.
    """
    uniq = sorted(c for c in category_counts if c != other_label)
    if len(uniq) <= 1:
        return {c: c for c in list(category_counts) + [other_label]}

    parent = {c: c for c in uniq}

    def find(x):
        while parent[x] != x:
            parent[x] = parent[parent[x]]
            x = parent[x]
        return x

    def union(a, b):
        ra, rb = find(a), find(b)
        if ra != rb:
            parent[rb] = ra

    # Pass 1: plural/singular + word-order-insensitive signature match
    by_signature: dict[str, list[str]] = defaultdict(list)
    for c in uniq:
        by_signature[_plural_signature(c)].append(c)
    for group in by_signature.values():
        for c in group[1:]:
            union(group[0], c)

    # Pass 2: embedding cosine similarity
    embeddings = embed_texts(uniq)
    norms = np.linalg.norm(embeddings, axis=1, keepdims=True)
    norms[norms == 0] = 1
    normed = embeddings / norms
    sim = cosine_similarity(normed)
    np.fill_diagonal(sim, 0)
    for i, ci in enumerate(uniq):
        for j, cj in enumerate(uniq):
            if j <= i:
                continue
            if sim[i, j] >= threshold:
                union(ci, cj)

    groups: dict[str, list[str]] = defaultdict(list)
    for c in uniq:
        groups[find(c)].append(c)

    canonical_map = {other_label: other_label}
    for members in groups.values():
        canonical = sorted(members, key=lambda m: (-category_counts.get(m, 0), m))[0]
        for m in members:
            canonical_map[m] = canonical

    return canonical_map


def _broaden_categories_once(
    category_counts: dict[str, int],
    category_samples: dict[str, list[str]],
    side_name: str,
    other_label: str,
    target_lo: int,
    target_hi: int,
) -> dict[str, str]:
    """
    Single LLM consolidation pass. Embedding similarity only catches
    near-duplicate wording — it routinely misses categories that are the same
    broad theme but lexically different (e.g. "Agricultural Revenue" and
    "Agricultural Productivity" are both Agricultural Production, but aren't
    close enough in embedding space to auto-merge). An LLM can reason about
    topical relatedness directly — but only if it can actually see what's in
    each category, not just its name, which is why sample entries are
    included: a name like "Quality & Standards" is unjudgeable on its own.
    Returns {category: broadened_category}.
    """
    cats = sorted(c for c in category_counts if c != other_label)
    if len(cats) <= 1:
        return {c: c for c in category_counts}

    cache_key = hashlib.sha256(
        (f"{CATEGORY_MODEL}|broaden|{side_name}|{target_lo}-{target_hi}|"
         + "|".join(f"{c}:{category_counts[c]}" for c in cats)).encode("utf-8")
    ).hexdigest()
    if cache_key in _category_cache:
        return _category_cache[cache_key]

    listing = "\n".join(
        f"- {c} ({category_counts[c]} entries) — e.g. {', '.join(category_samples.get(c, [])[:3])}"
        for c in cats
    )
    prompt = (
        f"You are consolidating a topical taxonomy of {len(cats)} categories used to label "
        f"'{side_name}' entries extracted from economics papers, for a Sankey diagram.\n\n"
        f"Categories (with entry counts and example entries):\n{listing}\n\n"
        "Task: aggressively merge categories into fewer, broader themes. Merge any two that "
        "represent the SAME broad economic/topical theme even if their wording differs "
        "entirely — e.g. 'Agricultural Revenue' and 'Agricultural Productivity' should both "
        "merge into one broader 'Agricultural Production' category; 'GDP Growth' and "
        "'Economic Growth' should merge into one; 'Exchange Rates & Prices' and 'Inflation & "
        "Price Levels' should merge into one 'Macroeconomic Indicators' or similar category.\n"
        f"Target: roughly {target_lo}-{target_hi} final categories — this is a hard reduction "
        "target, not a suggestion. If your first pass leaves more than that, keep merging "
        "before answering.\n"
        "Rules:\n"
        "- Any category with only 1-3 entries should almost always be folded into a larger "
        "related category — a standalone small category is only acceptable if it is a truly "
        "distinct major theme with no reasonable broader home.\n"
        "- Every category in the input list must map to exactly one output category.\n"
        "- The output name should be the clearest, most general label for the group (reuse "
        "one of the input names if it fits, or write a new short 2-4 word Title Case name).\n"
        "- Do not merge categories that are genuinely different themes just because they "
        "share a word.\n\n"
        'Respond with ONLY a JSON object: {"mapping": {"<input category>": "<final category>", ...}}'
    )

    response = client.chat.completions.create(
        model=CATEGORY_MODEL,
        messages=[{"role": "user", "content": prompt}],
        temperature=0.0,
        max_tokens=4000,
        response_format={"type": "json_object"},
    )
    mapping = json.loads(response.choices[0].message.content).get("mapping", {})

    result = {other_label: other_label}
    for c in cats:
        result[c] = mapping.get(c, c).strip() if mapping.get(c) else c

    _category_cache[cache_key] = result
    _save_category_cache(_category_cache)
    return result


def broaden_categories(
    category_counts: dict[str, int],
    category_samples: dict[str, list[str]],
    side_name: str,
    other_label: str,
    max_rounds: int = 3,
) -> dict[str, str]:
    """
    Repeatedly applies _broaden_categories_once() to its own output until the
    category count falls within a fixed target range, stops shrinking, or
    max_rounds is hit. The target is computed ONCE from the starting count and
    reused across rounds — recomputing it from the current (already-shrunk)
    count each round compounds geometrically (verified empirically: 59 raw
    categories collapsed to 8 after 3 rounds chasing a shrinking target,
    losing meaningful distinctions). A single pass also reliably undershoots
    a fixed target on its own (59 only reached 39 against a 19-29 target),
    which is why this iterates at all.
    Returns {original_category: final_broadened_category}.
    """
    n_start = len({c for c in category_counts if c != other_label})
    target_lo = max(10, round(n_start * 0.25))
    target_hi = max(18, round(n_start * 0.40))

    total_map: dict[str, str] = {c: c for c in category_counts}
    counts = dict(category_counts)
    samples = {c: list(v) for c, v in category_samples.items()}

    for _ in range(max_rounds):
        n_before = len({v for k, v in total_map.items() if k != other_label})
        if n_before <= target_hi:
            break

        round_map = _broaden_categories_once(counts, samples, side_name, other_label, target_lo, target_hi)

        total_map = {orig: round_map.get(cur, cur) for orig, cur in total_map.items()}

        counts = defaultdict(int)
        new_samples: dict[str, list[str]] = defaultdict(list)
        for orig, cnt in category_counts.items():
            final = total_map[orig]
            counts[final] += cnt
            for s in category_samples.get(orig, []):
                if len(new_samples[final]) < 3 and s not in new_samples[final]:
                    new_samples[final].append(s)
        samples = new_samples

        n_after = len({v for k, v in total_map.items() if k != other_label})
        if n_after >= n_before:
            break

    return total_map


# ─── Build cluster summary for review ──────────────────────────────────────
def build_summary(*sides) -> pd.DataFrame:
    """
    Each element of sides is a tuple: (side_name, df, id_col, label_col).
    """
    rows = []
    for side_name, df, id_col, label_col in sides:
        for (cid, label), grp in df.groupby([id_col, label_col]):
            sample = [e for e, _ in Counter(grp["entry"]).most_common(8)]
            rows.append({
                "side": side_name,
                "cluster_id": cid,
                "label": label,
                "n_entries": len(grp),
                "n_papers": grp["paper_idx"].nunique(),
                "sample_entries": " | ".join(sample),
            })
    return (
        pd.DataFrame(rows)
        .sort_values(["side", "n_entries"], ascending=[True, False])
        .reset_index(drop=True)
    )


# ─── Labels to exclude from the Sankey entirely (opt-in) ───────────────────
# Empty by default — every paper with a rainfall IV should appear in the
# diagram, including ones whose only entries are noise ("Other (...)") or
# missing text ("Not Specified (...)"). Add a label here only if you want to
# deliberately hide a specific category (its flows are dropped, not shown).
ENDOG_EXCLUDE:  set[str] = {"Not Specified (Endogenous Variables)"}
RAIN_EXCLUDE:   set[str] = set()
DEPVAR_EXCLUDE: set[str] = set()


# ─── Sankey ────────────────────────────────────────────────────────────────
def build_sankey(
    left_df: pd.DataFrame,
    right_df: pd.DataFrame,
    paper_index,
    left_label_col: str,
    right_label_col: str,
    left_exclude: set,
    right_exclude: set,
    title: str,
    node_pad: int = 20,
    left_node_order: list[str] | None = None,
    show_title: bool = True,
) -> tuple[go.Figure, list[str]]:
    # Per-paper label sets, with excluded labels stripped out
    left_map = (
        left_df[~left_df[left_label_col].isin(left_exclude)]
        .groupby("paper_idx")[left_label_col].apply(set).to_dict()
    )
    right_map = (
        right_df[~right_df[right_label_col].isin(right_exclude)]
        .groupby("paper_idx")[right_label_col].apply(set).to_dict()
    )

    flows: dict[tuple[str, str], int] = defaultdict(int)
    for paper_idx in paper_index:
        l_labels = left_map.get(paper_idx, set())
        r_labels = right_map.get(paper_idx, set())
        if not l_labels or not r_labels:
            continue
        for l in l_labels:
            for r in r_labels:
                flows[(l, r)] += 1

    if not flows:
        raise ValueError("No flows found — check that both columns have overlapping papers.")

    # Sort nodes by total flow for a cleaner diagram
    left_totals  = defaultdict(int)
    right_totals = defaultdict(int)
    for (l, r), v in flows.items():
        left_totals[l]  += v
        right_totals[r] += v

    if left_node_order is not None:
        # Use provided order, appending any new nodes not in it at the end
        known = set(left_node_order)
        left_nodes = [n for n in left_node_order if n in left_totals] + \
                     sorted((n for n in left_totals if n not in known), key=lambda x: -left_totals[x])
    else:
        left_nodes = sorted(left_totals, key=lambda x: -left_totals[x])
    right_nodes = sorted(right_totals, key=lambda x: -right_totals[x])
    all_nodes   = left_nodes + right_nodes
    node_idx    = {n: i for i, n in enumerate(all_nodes)}
    labeled_nodes = (
        [f"{n} ({left_totals[n]})"  for n in left_nodes] +
        [f"{n} ({right_totals[n]})" for n in right_nodes]
    )

    sources = [node_idx[l] for l, _ in flows]
    targets = [node_idx[r] for _, r in flows]
    values  = list(flows.values())

    n_left  = len(left_nodes)
    n_right = len(right_nodes)

    # Node count on each side is dynamic (15-24+ categories after the LLM
    # broadening pass) — too many for a fixed ≤8-slot categorical palette, so
    # hues are spread evenly across a range instead. This is safe here
    # specifically because identity is never color-alone: every node already
    # carries its own text label, so color is a secondary flow-tracing aid,
    # not the only way to tell categories apart (unlike a legend-bound chart).
    #
    # Left = a cool gradient (teal → blue → violet), right = a warm gradient
    # (red → orange → yellow) — intuitively distinct at a glance, and the two
    # ranges are disjoint by construction, so no left node can coincidentally
    # land on the same hue as a right node (which would read as "these are
    # related" when they aren't).
    # Saturation/lightness cycle through 3 tiers as hue steps forward, instead
    # of staying flat — with many nodes packed into one warm/cool band, hue
    # steps get small enough that flat S/L made neighbors blur together, even
    # though the overall gradient still reads as a coherent warm/cool sweep.
    _SAT_TIERS   = (60, 78, 68)
    _LIGHT_TIERS = (50, 63, 42)

    def spread_hues(n: int, hue_start: float, hue_end: float) -> list[tuple[float, int, int]]:
        if n <= 0:
            return []
        if n == 1:
            return [((hue_start + hue_end) / 2, _SAT_TIERS[0], _LIGHT_TIERS[0])]
        step = (hue_end - hue_start) / (n - 1)
        return [
            (hue_start + i * step, _SAT_TIERS[i % 3], _LIGHT_TIERS[i % 3])
            for i in range(n)
        ]

    left_hsl  = spread_hues(n_left,  hue_start=175, hue_end=290)  # cool: teal -> blue -> violet
    right_hsl = spread_hues(n_right, hue_start=0,   hue_end=55)   # warm: red -> orange -> yellow

    left_colours  = [f"hsl({h:.0f},{s}%,{l}%)" for h, s, l in left_hsl]
    right_colours = [f"hsl({h:.0f},{s}%,{l}%)" for h, s, l in right_hsl]

    # Links take their source node's hue at reduced opacity, so each flow
    # visually traces back to the rainfall-metric category it came from.
    left_node_hsl = dict(zip(left_nodes, left_hsl))
    link_colours = [
        "hsla({:.0f},{}%,{}%,0.35)".format(*left_node_hsl[l])
        for l, _ in flows
    ]

    fig = go.Figure(go.Sankey(
        arrangement="snap",
        # Leave a gap below the title so top nodes can't overlap it; with no
        # title there's nothing to leave room for, so use the full height.
        domain=dict(x=[0, 1], y=[0, 0.94] if show_title else [0, 1]),
        node=dict(
            pad=node_pad,
            thickness=18,
            line=dict(color="white", width=0.5),
            label=labeled_nodes,
            color=left_colours + right_colours,
        ),
        link=dict(
            source=sources,
            target=targets,
            value=values,
            color=link_colours,
        ),
    ))

    layout_kwargs = dict(
        font_size=13,
        width=770,
        height=950,
    )
    if show_title:
        layout_kwargs["title"] = dict(text=title, font=dict(size=18), y=0.99, yanchor="top")
        layout_kwargs["margin"] = dict(l=20, r=20, t=110, b=20)
    else:
        layout_kwargs["margin"] = dict(l=20, r=20, t=20, b=20)
    fig.update_layout(**layout_kwargs)
    return fig, left_nodes


# ─── Main ──────────────────────────────────────────────────────────────────
def process_side(
    rain_df_raw: pd.DataFrame,
    col: str,
    label_overrides: dict[str, str],
    id_col: str,
    label_col: str,
    side_name: str,
    requires_rainfall: bool = False,
    skip_broadening: bool = False,
) -> pd.DataFrame:
    print(f"\n[{side_name}]")
    exp = expand_column(rain_df_raw, col, requires_rainfall=requires_rainfall)
    print(f"  Entries after cleaning: {len(exp)} (from {rain_df_raw[col].notna().sum()} non-null rows)")

    other_label        = f"Other ({side_name})"
    not_specified_label = f"Not Specified ({side_name})"
    unique_entries = sorted(exp["entry"].unique()) if len(exp) else []

    print(f"  Classifying {len(unique_entries)} unique entries via LLM...")
    entry_to_category = classify_into_categories(unique_entries, side_name, other_label) if unique_entries else {}

    category_counts = Counter(entry_to_category.values())
    n_raw = len(category_counts) - (1 if other_label in category_counts else 0)
    print(f"  LLM proposed {n_raw} categories "
          f"(+ {other_label}: {category_counts.get(other_label, 0)} entries)")

    canonical_map = merge_similar_category_names(category_counts, other_label, CATEGORY_MERGE_SIM_THRESHOLD)
    n_merged = len({v for k, v in canonical_map.items() if k != other_label})
    if n_merged < n_raw:
        print(f"  Merge guardrail: {n_raw} → {n_merged} categories after collapsing near-duplicates")

    canonical_counts = Counter()
    canonical_samples: dict[str, list[str]] = defaultdict(list)
    for entry, raw_cat in entry_to_category.items():
        canon = canonical_map.get(raw_cat, raw_cat)
        canonical_counts[canon] += 1
        if len(canonical_samples[canon]) < 3 and entry not in canonical_samples[canon]:
            canonical_samples[canon].append(entry)

    if skip_broadening:
        broad_map = {c: c for c in canonical_counts}
        print(f"  Broadening pass: skipped — keeping {n_merged} categories from the merge guardrail")
    else:
        broad_map = broaden_categories(canonical_counts, canonical_samples, side_name, other_label)
        n_broad = len({v for k, v in broad_map.items() if k != other_label})
        if n_broad < n_merged:
            print(f"  Broadening pass: {n_merged} → {n_broad} categories after consolidating same-theme categories")

    exp[label_col] = (
        exp["entry"]
        .map(entry_to_category)
        .map(lambda c: canonical_map.get(c, c))
        .map(lambda c: broad_map.get(c, c))
        .map(lambda c: label_overrides.get(c, c))
    )
    exp[id_col] = exp[label_col]

    # Every paper in rain_df_raw is here *because* it has a rainfall IV — so a
    # paper missing from this side isn't "no data," it's raw text that was
    # blank or that every candidate entry failed cleaning on. Give each such
    # paper an explicit fallback node instead of silently dropping it from
    # the Sankey.
    covered = set(exp["paper_idx"])
    fallback_rows = []
    for paper_idx in rain_df_raw.index.unique():
        if paper_idx in covered:
            continue
        raw_vals = rain_df_raw.loc[[paper_idx], col]
        has_raw = any(str(v).strip().lower() not in ("", "n/a", "na") for v in raw_vals.dropna())
        label = other_label if has_raw else not_specified_label
        fallback_rows.append({"paper_idx": paper_idx, "entry": label.lower(), label_col: label, id_col: label})
    if fallback_rows:
        print(f"  +{len(fallback_rows)} papers with no surviving entry added as fallback nodes")
        exp = pd.concat([exp, pd.DataFrame(fallback_rows)], ignore_index=True)

    for label, n in exp[label_col].value_counts().items():
        print(f"    {label}  ({n} entries)")

    return exp


# ─── Combine model output + human-labeled rainfall IV papers ───────────────
def normalize_filename(fn) -> str:
    """Alphanumeric-only, lowercased join key. Model output and the human xlsx
    render the same DOI with different punctuation (10.1002/x vs 10.1002_x vs
    10.1002x), so this is the only reliable way to match papers across them."""
    s = str(fn).lower()
    s = re.sub(r"\.pdf$", "", s)
    s = re.sub(r"[^a-z0-9]", "", s)
    return s


def load_combined_rainfall_papers(model_csv_path: str, human_xlsx_path: str) -> pd.DataFrame:
    """
    Union of every paper either source identified as having a rainfall IV:
      - model output: Instrumental Variable Rainfall == 1
      - human labels:  rain_bin == 1
    Indexed by normalized filename so a paper present in both sources shares
    one identity downstream (expand_column/build_sankey group by this index),
    merging rather than double-counting its entries.
    """
    model_df = pd.read_csv(model_csv_path)
    model_rain = model_df[model_df["Instrumental Variable Rainfall"] == 1.0].copy()
    model_rain["paper_key"] = model_rain["File Name"].map(normalize_filename)
    model_rain = model_rain[
        ["paper_key", "Rainfall Instrument", "Endogenous Variable(s)", "Dependent Variable(s)"]
    ]

    human_df = pd.read_excel(human_xlsx_path)
    human_rain = human_df[human_df["rain_bin"] == 1.0].copy()
    human_rain["paper_key"] = human_rain["filename"].map(normalize_filename)
    human_rain = human_rain.rename(columns={
        "rain_var": "Rainfall Instrument",
        "end_var":  "Endogenous Variable(s)",
        "dep_var":  "Dependent Variable(s)",
    })[["paper_key", "Rainfall Instrument", "Endogenous Variable(s)", "Dependent Variable(s)"]]

    both  = set(model_rain["paper_key"]) & set(human_rain["paper_key"])
    union = set(model_rain["paper_key"]) | set(human_rain["paper_key"])
    print(f"Rainfall IV papers — model: {len(model_rain)}, human: {len(human_rain)}, "
          f"overlap: {len(both)}, combined unique: {len(union)}")

    combined = pd.concat([model_rain, human_rain], ignore_index=True)
    return combined.set_index("paper_key")


def main():
    print("Loading data...")
    rain_df_raw = load_combined_rainfall_papers(INPUT_CSV, HUMAN_LABELED_XLSX)
    print(f"Rainfall IV papers (combined, deduped): {rain_df_raw.index.nunique()}")

    endog_exp = process_side(
        rain_df_raw,
        col="Endogenous Variable(s)",
        label_overrides=ENDOG_LABEL_OVERRIDES,
        id_col="endog_cluster_id",
        label_col="endog_cluster_label",
        side_name="Endogenous Variables",
    )

    rain_exp = process_side(
        rain_df_raw,
        col="Rainfall Instrument",
        label_overrides=RAIN_LABEL_OVERRIDES,
        id_col="rain_cluster_id",
        label_col="rain_cluster_label",
        side_name="Rainfall Metrics",
        requires_rainfall=True,
    )

    depvar_exp = process_side(
        rain_df_raw,
        col="Dependent Variable(s)",
        label_overrides=DEPVAR_LABEL_OVERRIDES,
        id_col="depvar_cluster_id",
        label_col="depvar_cluster_label",
        side_name="Dependent Variables",
    )

    summary = build_summary(
        ("endog", endog_exp, "endog_cluster_id", "endog_cluster_label"),
        ("rain",  rain_exp,  "rain_cluster_id",  "rain_cluster_label"),
    )
    summary.to_csv(CLUSTER_SUMMARY, index=False)
    print(f"\nCluster summary → {CLUSTER_SUMMARY}")

    summary_depvar = build_summary(
        ("depvar", depvar_exp, "depvar_cluster_id", "depvar_cluster_label"),
        ("rain",   rain_exp,  "rain_cluster_id",   "rain_cluster_label"),
    )
    summary_depvar.to_csv(CLUSTER_SUMMARY_DEPVAR, index=False)
    print(f"Dependent variable cluster summary → {CLUSTER_SUMMARY_DEPVAR}")
    print("Review it, add label overrides above, and rerun.")

    print("\nBuilding Sankey: Rainfall → Endogenous Variables...")
    fig, rain_node_order = build_sankey(
        rain_exp, endog_exp, rain_df_raw.index.unique(),
        left_label_col="rain_cluster_label",
        right_label_col="endog_cluster_label",
        left_exclude=RAIN_EXCLUDE,
        right_exclude=ENDOG_EXCLUDE,
        title="Rainfall Instruments → Endogenous Variables",
        show_title=False,
    )
    fig.write_html(OUTPUT_HTML)
    print(f"Sankey → {OUTPUT_HTML}")
    fig.write_image(OUTPUT_PNG, scale=2)
    print(f"Sankey → {OUTPUT_PNG}")

    print("\nBuilding Sankey: Rainfall → Dependent Variables...")
    fig_depvar, _ = build_sankey(
        rain_exp, depvar_exp, rain_df_raw.index.unique(),
        left_label_col="rain_cluster_label",
        right_label_col="depvar_cluster_label",
        left_exclude=RAIN_EXCLUDE,
        right_exclude=DEPVAR_EXCLUDE,
        title="Rainfall Instruments → Dependent Variables",
        node_pad=50,
        left_node_order=rain_node_order,
        show_title=False,
    )
    fig_depvar.write_html(OUTPUT_HTML_DEPVAR)
    print(f"Sankey → {OUTPUT_HTML_DEPVAR}")
    fig_depvar.write_image(OUTPUT_PNG_DEPVAR, scale=2)
    print(f"Sankey → {OUTPUT_PNG_DEPVAR}")


if __name__ == "__main__":
    main()

