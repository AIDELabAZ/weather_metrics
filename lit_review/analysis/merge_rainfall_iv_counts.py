"""
merge_rainfall_iv_counts.py

Outer-joins the FULL GPT model output CSV and the FULL human label workbook
(training_all_new.xlsx) on a normalized filename key — one row per distinct
paper, whether it appears in one source or both — and adds numeric columns
counting how many rainfall instruments each source lists for that paper.

Nothing is filtered to rainfall-IV papers: every row of both input files is
carried through. `gpt_iv_rainfall_flag` (== "Instrumental Variable Rainfall")
and `human_rain_bin` (== "rain_bin") are kept so you can filter afterwards.

Count columns
-------------
gpt_rain_iv_count          ;-split non-empty entries in GPT  "Rainfall Instrument"
human_rain_iv_count        ;-split non-empty entries in human "rain_var"
gpt_rain_iv_count_clean    of those, how many survive the Sankey noise filter
human_rain_iv_count_clean  (clean_entry(..., requires_rainfall=True))
rain_iv_count_combined     # DISTINCT cleaned instrument strings across GPT ∪ human
                           for the paper — mirrors how the Sankey dedupes a
                           paper's instruments before categorizing.

"non-empty" drops "", "n/a", "na", "none" (case-insensitive) before counting,
so a paper whose Rainfall Instrument cell is "N/A" counts 0, not 1.

The clean_entry / normalize_filename logic below is mirrored verbatim from
sankey_iv_clustering.py so the *_clean and combined counts match what that
script actually feeds into the diagram.
"""
import re
import unicodedata
import pandas as pd

# ─── Paths ────────────────────────────────────────────────────────────────
# GPT input is the full fine-tuned (sft) corpus run; output sits with the
# other sft-derived Sankey artifacts. HUMAN_XLSX is a training/ input.
GPT_CSV     = "/Users/kieran/Library/CloudStorage/OneDrive-UniversityofArizona/weather_iv_lit/output/gpt/sft/full_sft_gpt_output.csv"
HUMAN_XLSX  = "/Users/kieran/Library/CloudStorage/OneDrive-UniversityofArizona/weather_iv_lit/training/training_new_labels/training_all_new.xlsx"
OUTPUT_CSV  = "/Users/kieran/Library/CloudStorage/OneDrive-UniversityofArizona/weather_iv_lit/output/gpt/sft/merged_gpt_human_rainfall_iv_counts.csv"

_BLANKS = {"", "n/a", "na", "none", "nan"}

# ─── cleaning logic mirrored from sankey_iv_clustering.py ─────────────────
MAX_WORDS = 8
MIN_CHARS = 5
GENERIC_TERMS = {
    "rainfall", "precipitation", "rain", "weather", "climate",
    "precip", "ppt", "instrument", "variable", "endogenous",
    "data", "index", "measure", "level", "value", "total", "which",
    "particularly", "proxy", "quarterly", "monthly", "annual",
}
RAINFALL_CORE_TERMS = {"rainfall", "precipitation", "rain", "precip", "ppt"}
RAINFALL_REQUIRED_TERMS = {
    "rain", "rainfall", "precipitation", "precip", "ppt", "monsoon",
    "drought", "wet", "dry", "flood", "storm", "snow", "snowfall",
    "snowpack", "swe", "humidity", "moisture", "cumulative", "seasonal",
    "annual", "monthly", "weekly", "daily", "spi", "spei", "pdsi",
    "humidity", "wind", "sunshine", "cloud", "runoff", "river",
    "streamflow", "waterlog",
}
_EQUATION_CHARS = re.compile(r"[=<>{}\|\\^~`]|\\[a-zA-Z]+")
_MOSTLY_NUMBERS = re.compile(r"^\s*[\d\s\.\,\-\*\[\]\(\)]+\s*$")
_YEAR_ONLY = re.compile(r"^\s*(19|20)\d{2}[\s\)\.,]*$")
_SUBSCRIPT_BLOCK = re.compile(r"[^\x00-\x7F]{3,}")
_SUBSCRIPT_VAR = re.compile(r"\b[a-z]{1,6}[0-9]{0,2}(it|jt|ij|ijt|ilt|kt|ibt|abt)\b")
_SLASH_LIST = re.compile(r"\w+/\w+/\w+")
_FUNCTION_WORDS = {
    "the", "a", "an", "is", "are", "was", "were", "be", "been",
    "we", "our", "this", "that", "these", "those", "in", "of",
    "to", "and", "or", "for", "with", "as", "by", "at", "on",
    "also", "have", "has", "not", "but", "if", "do", "from",
    "which", "who", "they", "their", "its", "it", "such",
}
_TRIVIAL = {"n/a", "na", "none", "", "x", "y", "z", "i", "t",
            "0", "1", "a", "b", "c", "d", "e", "f"}
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
_NORMALIZATIONS = [
    (re.compile(r"\bln\b"), "log"),
    (re.compile(r"\blog\s*\(?\s*"), "log "),
    (re.compile(r"\bprecip\b"), "precipitation"),
    (re.compile(r"\bppt\b"), "precipitation"),
    (re.compile(r"\brain(?:fall)?\b"), "rainfall"),
    (re.compile(r"\bann(?:ual)?\b"), "annual"),
    (re.compile(r"\bseas(?:onal)?\b"), "seasonal"),
    (re.compile(r"\bmon(?:thly)?\b"), "monthly"),
    (re.compile(r"\bwk|week(?:ly)?\b"), "weekly"),
    (re.compile(r"\bgdp\b"), "gdp per capita"),
    (re.compile(r"\bcpi\b"), "consumer price index"),
    (re.compile(r"\bres\b"), "renewable energy sources"),
]


def normalize_text(txt: str) -> str:
    for pattern, replacement in _NORMALIZATIONS:
        txt = pattern.sub(replacement, txt)
    return re.sub(r"\s+", " ", txt).strip()


def proportion_ascii(txt: str) -> float:
    if not txt:
        return 0.0
    return sum(1 for c in txt if ord(c) < 128) / len(txt)


def is_sentence_like(txt: str) -> bool:
    words = txt.split()
    if len(words) < 4:
        return False
    return (sum(1 for w in words if w in _FUNCTION_WORDS) / len(words)) > 0.45


def clean_entry(txt, requires_rainfall: bool = False):
    if not txt or not isinstance(txt, str):
        return None
    try:
        txt = unicodedata.normalize("NFKC", txt)
    except Exception:
        pass
    is_acronym = bool(re.fullmatch(r"[A-Z][A-Z0-9]{1,5}", txt.strip()))
    txt = txt.strip().lower()
    if txt in _TRIVIAL:
        return None
    if proportion_ascii(txt) < 0.75:
        return None
    if _SUBSCRIPT_BLOCK.search(txt):
        return None
    if _EQUATION_CHARS.search(txt):
        return None
    if _SLASH_LIST.search(txt):
        return None
    if _MOSTLY_NUMBERS.match(txt):
        return None
    if _YEAR_ONLY.match(txt):
        return None
    for phrase in _STOP_PHRASES:
        if phrase in txt:
            return None
    if is_sentence_like(txt):
        return None
    tokens = txt.split()
    long_tokens = [tok for tok in tokens if len(tok) > 2]
    if long_tokens and all(_SUBSCRIPT_VAR.match(tok) for tok in long_tokens):
        return None
    txt = re.sub(r"\(\s*(?:19|20)\d{2}\s*\)", "", txt)
    txt = re.sub(r"\s+", " ", txt).strip()
    if len(txt) < MIN_CHARS and not is_acronym and not (requires_rainfall and txt.strip() in RAINFALL_CORE_TERMS):
        return None
    words = txt.split()
    if len(words) > MAX_WORDS:
        txt = " ".join(words[:MAX_WORDS])
    if txt.strip() in GENERIC_TERMS and not (requires_rainfall and txt.strip() in RAINFALL_CORE_TERMS):
        return None
    if requires_rainfall:
        if not any(term in txt for term in RAINFALL_REQUIRED_TERMS):
            return None
        true_rain_terms = RAINFALL_REQUIRED_TERMS - {
            "cumulative", "seasonal", "annual", "monthly", "weekly", "daily"
        }
        if "temperature" in txt and not any(term in txt for term in true_rain_terms):
            return None
    txt = normalize_text(txt)
    if len(txt) < MIN_CHARS and not is_acronym and not (requires_rainfall and txt.strip() in RAINFALL_CORE_TERMS):
        return None
    return txt


def normalize_filename(fn) -> str:
    s = str(fn).lower()
    s = re.sub(r"\.pdf$", "", s)
    s = re.sub(r"[^a-z0-9]", "", s)
    return s


# ─── per-cell helpers ────────────────────────────────────────────────────
def raw_pieces(val) -> list[str]:
    if not isinstance(val, str):
        return []
    out = []
    for part in val.split(";"):
        p = part.strip()
        if p and p.lower() not in _BLANKS:
            out.append(p)
    return out


def clean_pieces(val, requires_rainfall: bool = False) -> list[str]:
    if not isinstance(val, str):
        return []
    return [c for part in val.split(";")
            if (c := clean_entry(part, requires_rainfall=requires_rainfall))]


def main() -> None:
    # ── GPT full output ──────────────────────────────────────────────────
    gpt = pd.read_csv(GPT_CSV)
    gpt["paper_key"] = gpt["File Name"].map(normalize_filename)
    n_gpt_dupe = len(gpt) - gpt["paper_key"].nunique()
    gpt = gpt.drop_duplicates("paper_key", keep="first").set_index("paper_key")
    gpt = gpt.add_prefix("gpt_")

    # ── Human label workbook ────────────────────────────────────────────
    hum = pd.read_excel(HUMAN_XLSX)
    hum["paper_key"] = hum["filename"].map(normalize_filename)
    n_hum_dupe = len(hum) - hum["paper_key"].nunique()
    hum = hum.drop_duplicates("paper_key", keep="first").set_index("paper_key")
    hum = hum.add_prefix("human_")

    # ── Outer join: union of every paper in either file ─────────────────
    merged = gpt.join(hum, how="outer")
    merged.insert(0, "in_gpt", merged["gpt_File Name"].notna().astype(int))
    merged.insert(1, "in_human", merged["human_filename"].notna().astype(int))

    # ── Coalesced identity columns ─────────────────────────────────────
    merged["file_name"] = merged["gpt_File Name"].fillna(merged["human_filename"])
    merged["title"]     = merged["gpt_Title"].fillna(merged["human_title"])
    merged["doi"]       = merged["gpt_DOI"].fillna(merged["human_doi"])

    # ── Rainfall-IV counts ────────────────────────────────────────────
    g_raw   = merged["gpt_Rainfall Instrument"].map(raw_pieces)
    h_raw   = merged["human_rain_var"].map(raw_pieces)
    g_clean = merged["gpt_Rainfall Instrument"].map(lambda v: clean_pieces(v, True))
    h_clean = merged["human_rain_var"].map(lambda v: clean_pieces(v, True))

    merged["gpt_rain_iv_count"]         = g_raw.map(len)
    merged["human_rain_iv_count"]       = h_raw.map(len)
    merged["gpt_rain_iv_count_clean"]   = g_clean.map(len)
    merged["human_rain_iv_count_clean"] = h_clean.map(len)
    merged["rain_iv_count_combined"]    = [
        len(set(a) | set(b)) for a, b in zip(g_clean, h_clean)
    ]

    # rainfall-IV flags kept for post-hoc filtering
    merged["gpt_iv_rainfall_flag"] = merged["gpt_Instrumental Variable Rainfall"]
    merged["human_rain_bin"]       = merged["human_rain_bin"]

    front = [
        "file_name", "title", "doi", "in_gpt", "in_human",
        "gpt_iv_rainfall_flag", "human_rain_bin",
        "gpt_rain_iv_count", "human_rain_iv_count",
        "gpt_rain_iv_count_clean", "human_rain_iv_count_clean",
        "rain_iv_count_combined",
        "gpt_Rainfall Instrument", "human_rain_var",
    ]
    rest = [c for c in merged.columns if c not in front]
    merged = merged.reset_index()[["paper_key"] + front + rest]

    merged.to_csv(OUTPUT_CSV, index=False)

    both = int((merged["in_gpt"] & merged["in_human"]).sum())
    print(f"GPT rows {len(gpt) + n_gpt_dupe} ({n_gpt_dupe} dup paper_key rows collapsed)")
    print(f"Human rows {len(hum) + n_hum_dupe} ({n_hum_dupe} dup paper_key rows collapsed)")
    print(f"Merged distinct papers: {len(merged)}  "
          f"(gpt-only {int((merged['in_gpt'] & ~merged['in_human'].astype(bool)).sum())}, "
          f"human-only {int((~merged['in_gpt'].astype(bool) & merged['in_human']).sum())}, "
          f"both {both})")
    print(f"Papers with >=1 rainfall IV (gpt)   : {(merged['gpt_rain_iv_count'] > 0).sum()}")
    print(f"Papers with >=1 rainfall IV (human) : {(merged['human_rain_iv_count'] > 0).sum()}")
    print(f"Papers with >=1 rainfall IV (either): {((merged['gpt_rain_iv_count'] + merged['human_rain_iv_count']) > 0).sum()}")
    print(f"Total rainfall IVs  gpt raw={int(merged['gpt_rain_iv_count'].sum())} "
          f"clean={int(merged['gpt_rain_iv_count_clean'].sum())} | "
          f"human raw={int(merged['human_rain_iv_count'].sum())} "
          f"clean={int(merged['human_rain_iv_count_clean'].sum())} | "
          f"combined distinct={int(merged['rain_iv_count_combined'].sum())}")
    print(f"\nWrote {OUTPUT_CSV}")


if __name__ == "__main__":
    main()
