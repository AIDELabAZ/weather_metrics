"""
sankey_iv_clustering.py

Reads the model output CSV, clusters endogenous variables and rainfall metrics
using sentence embeddings + UMAP + HDBSCAN, then generates an interactive
Sankey diagram connecting rainfall instrument types to endogenous variable
categories.

Workflow:
  1. Filter to rainfall IV papers
  2. Aggressively clean + normalize entries (remove noise, equations, generics)
  3. Embed with sentence-transformers, reduce with UMAP, cluster with HDBSCAN
  4. Merge near-duplicate clusters by centroid similarity
  5. Export cluster_summary.csv so you can review/rename clusters
  6. Build Plotly Sankey: left = rainfall metric clusters, right = endog clusters
  7. Save interactive HTML

After first run: review cluster_summary.csv, then add overrides to
ENDOG_LABEL_OVERRIDES / RAIN_LABEL_OVERRIDES below and rerun — the
embeddings are cached so reruns are fast.
"""

import re
import unicodedata
from collections import defaultdict
import numpy as np
import pandas as pd
import hdbscan
import umap
import plotly.graph_objects as go
from sentence_transformers import SentenceTransformer
from sklearn.metrics.pairwise import cosine_similarity

# ─── Paths ─────────────────────────────────────────────────────────────────
INPUT_CSV              = "/Users/kieran/Library/CloudStorage/OneDrive-UniversityofArizona/weather_iv_lit/training/models/output/allpapers_output.csv"
OUTPUT_HTML            = "/Users/kieran/Library/CloudStorage/OneDrive-UniversityofArizona/weather_iv_lit/training/models/output/sankey_rainfall_iv.html"
OUTPUT_HTML_DEPVAR     = "/Users/kieran/Library/CloudStorage/OneDrive-UniversityofArizona/weather_iv_lit/training/models/output/sankey_rainfall_depvar.html"
CLUSTER_SUMMARY        = "/Users/kieran/Library/CloudStorage/OneDrive-UniversityofArizona/weather_iv_lit/training/models/output/cluster_summary.csv"
CLUSTER_SUMMARY_DEPVAR = "/Users/kieran/Library/CloudStorage/OneDrive-UniversityofArizona/weather_iv_lit/training/models/output/cluster_summary_depvar.csv"

# ─── HDBSCAN / UMAP params ─────────────────────────────────────────────────
MIN_CLUSTER_SIZE_ENDOG  = 6    # raise to get fewer, broader clusters
MIN_CLUSTER_SIZE_RAIN   = 5
MIN_CLUSTER_SIZE_DEPVAR = 6
MIN_SAMPLES            = 2    # lower = more points pulled from noise
UMAP_N_COMPONENTS      = 10   # dims to reduce to before HDBSCAN
UMAP_N_NEIGHBORS       = 15
UMAP_MIN_DIST          = 0.0  # 0.0 keeps tight clusters

# After clustering, merge any two clusters whose centroids have cosine sim
# above this threshold (handles near-duplicate clusters like "cumulative
# rainfall" appearing twice).
MERGE_THRESHOLD = 0.92

# ─── Manual label overrides (edit after reviewing cluster_summary.csv) ─────
# Format: {cluster_id (int): "Your Label"}
# Note: if you merge two clusters via same label string, their flows combine.
ENDOG_LABEL_OVERRIDES: dict[int, str] = {
    0:  "Other (Endogenous Variables)",   # exogenous — weather phenomenon
    1:  "Agricultural Production",
    2:  "Other (Endogenous Variables)",   # exogenous — weather phenomenon
    3:  "Health",
    4:  "Other (Endogenous Variables)",   # exogenous — weather-derived index
    5:  "Other (Endogenous Variables)",   # sentence noise
    6:  "Other (Endogenous Variables)",   # sentence noise
    7:  "Financial Access & Credit",
    8:  "Economic Growth & GDP",
    9:  "Financial Access & Credit",      # merge with 7
    10: "Other (Endogenous Variables)",   # sentence noise
    11: "Other (Endogenous Variables)",   # unicode variable code
    12: "Other (Endogenous Variables)",   # sentence noise
    13: "Trade Openness",
    14: "Other (Endogenous Variables)",   # methodology label
    15: "Capital & Investment",
    16: "Capital & Investment",           # merge with 15
    17: "Inflation & Prices",
    18: "Energy Prices",
    19: "Other (Endogenous Variables)",   # noise
    20: "Taxation",
    21: "Other (Endogenous Variables)",   # sentence noise
    22: "Government Spending",
    23: "Land Policy",
    24: "Labor",
    25: "Crime",
    26: "Inequality & Welfare",
    27: "Economic Growth & GDP",          # merge with 8
    28: "CO2 Emissions",
    29: "Population & Urbanization",
    30: "Population & Urbanization",      # merge with 29
    31: "Other (Endogenous Variables)",   # variable code
    32: "Energy & Electricity",
    33: "Other (Endogenous Variables)",   # variable code
    34: "Other (Endogenous Variables)",   # variable code
    35: "Other (Endogenous Variables)",   # variable code
    36: "Other (Endogenous Variables)",   # equation noise
    37: "Air Pollution",
    38: "Air Transport",
    39: "Air Transport",                  # merge with 38
    40: "Institutional Quality",
    41: "Other (Endogenous Variables)",   # noise
    42: "Institutional Quality",          # merge with 40
}
RAIN_LABEL_OVERRIDES: dict[int, str] = {
    1:  "Cumulative Rainfall",            # merge with cluster 3
    4:  "Other (Rainfall Metrics)",       # noise (non-rainfall content)
    5:  "Temperature Deviation",
    6:  "Seasonal Rainfall",
    7:  "Extreme Weather & Snow",
    8:  "Daily Rainfall",
    10: "Other (Rainfall Metrics)",       # prompt text leakage
    12: "Local Rainfall",
    14: "Other (Rainfall Metrics)",       # noise
    15: "Rainfall Shocks",
}
DEPVAR_LABEL_OVERRIDES: dict[int, str] = {
    13: "Business Registration",           # merge with 14
    14: "Business Registration",           # merge with 13
    15: "GDP Per Capita",                  # redundant "per capita per capita" wording
    16: "GDP Per Capita Growth",           # merge with 20 and 21
    18: "Housing & Rents",                 # panel subscript noise in auto-label
    20: "GDP Per Capita Growth",           # log-change sentence noise; variable is gdp growth
    21: "GDP Per Capita Growth",           # canonical
    24: "Air Pollution",                   # rename Local Pollutants
    28: "Green Innovation",                # auto-label "White (%)" is noise; entries are green tech
    29: "Other (Dependent Variables)",     # fragment noise
    31: "Other (Dependent Variables)",     # methodology label, not a variable
    32: "Other (Dependent Variables)",     # price/variable code noise
    33: "Political Institutions",          # entries are about contracts and institutions
    37: "Institutional Quality",           # merge with positive framing
    38: "Other (Dependent Variables)",     # variable code
    43: "Foreign Direct Investment",       # sentence noise; variable is FDI
    47: "Air Pollution",                   # merge with 24
    49: "Food Prices",                     # sentence noise; variable is food prices
    57: "Economic Growth",                 # canonical
    62: "Economic Growth",                 # too generic; merge with 57
    72: "Total Factor Productivity",       # user fix: Tfp_Lpit
    77: "Other (Dependent Variables)",     # variable code noise
    78: "Other (Dependent Variables)",     # equation fragment
}

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

# For the rainfall side only: entry must contain at least one of these terms
RAINFALL_REQUIRED_TERMS = {
    "rain", "rainfall", "precipitation", "precip", "ppt", "monsoon",
    "drought", "wet", "dry", "flood", "storm", "snow", "snowfall",
    "snowpack", "swe", "humidity", "moisture", "cumulative", "seasonal",
    "annual", "monthly", "weekly", "daily", "temperature", "climate",
    "weather", "spi", "spei", "pdsi", "humidity", "wind", "sunshine",
    "cloud", "runoff", "river", "streamflow", "waterlog",
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

    # Drop if it's a subscript variable code (lnnetit, soeit, btmit, etc.)
    tokens = txt.split()
    if all(_SUBSCRIPT_VAR.match(tok) for tok in tokens if len(tok) > 2):
        return None

    # Remove parenthetical citations like (2020)
    txt = re.sub(r"\(\s*(?:19|20)\d{2}\s*\)", "", txt)
    txt = re.sub(r"\s+", " ", txt).strip()

    if len(txt) < MIN_CHARS:
        return None

    # Truncate to MAX_WORDS
    words = txt.split()
    if len(words) > MAX_WORDS:
        txt = " ".join(words[:MAX_WORDS])

    # After truncation, check if it reduces to a single generic term
    if txt.strip() in GENERIC_TERMS:
        return None

    # For rainfall side: require at least one weather/precip-related term
    if requires_rainfall:
        if not any(term in txt for term in RAINFALL_REQUIRED_TERMS):
            return None

    # Normalize for embedding
    txt = normalize_text(txt)

    if len(txt) < MIN_CHARS:
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


# ─── UMAP + HDBSCAN ────────────────────────────────────────────────────────
def cluster_embeddings(embeddings: np.ndarray, min_cluster_size: int) -> np.ndarray:
    print(f"  UMAP: {embeddings.shape[1]}d → {UMAP_N_COMPONENTS}d ...")
    reducer = umap.UMAP(
        n_components=UMAP_N_COMPONENTS,
        n_neighbors=UMAP_N_NEIGHBORS,
        min_dist=UMAP_MIN_DIST,
        metric="cosine",
        random_state=42,
    )
    reduced = reducer.fit_transform(embeddings)

    print(f"  HDBSCAN (min_cluster_size={min_cluster_size}) ...")
    clusterer = hdbscan.HDBSCAN(
        min_cluster_size=min_cluster_size,
        min_samples=MIN_SAMPLES,
        metric="euclidean",
        cluster_selection_method="eom",
    )
    return clusterer.fit_predict(reduced)


# ─── Merge near-duplicate clusters ─────────────────────────────────────────
def merge_duplicate_clusters(
    cluster_ids: np.ndarray,
    embeddings: np.ndarray,
    threshold: float,
) -> np.ndarray:
    """
    Compute per-cluster centroid (mean embedding), then merge any two clusters
    whose centroids have cosine similarity > threshold.
    Returns a new cluster_ids array with merged labels.
    """
    unique = sorted(c for c in set(cluster_ids) if c != -1)
    if len(unique) <= 1:
        return cluster_ids

    centroids = np.array([
        embeddings[cluster_ids == cid].mean(axis=0) for cid in unique
    ])
    # Normalize centroids
    norms = np.linalg.norm(centroids, axis=1, keepdims=True)
    norms[norms == 0] = 1
    centroids_normed = centroids / norms

    sim = cosine_similarity(centroids_normed)
    np.fill_diagonal(sim, 0)

    # Union-find merge
    parent = {cid: cid for cid in unique}

    def find(x):
        while parent[x] != x:
            parent[x] = parent[parent[x]]
            x = parent[x]
        return x

    for i, ci in enumerate(unique):
        for j, cj in enumerate(unique):
            if j <= i:
                continue
            if sim[i, j] >= threshold:
                ri, rj = find(ci), find(cj)
                if ri != rj:
                    parent[rj] = ri

    # Remap cluster ids to their root
    remap = {cid: find(cid) for cid in unique}
    # Re-index roots to 0..N-1
    roots = sorted(set(remap.values()))
    root_to_new = {r: i for i, r in enumerate(roots)}
    remap = {cid: root_to_new[find(cid)] for cid in unique}

    new_ids = np.array([remap.get(c, -1) if c != -1 else -1 for c in cluster_ids])
    return new_ids


# ─── Auto-label via most frequent entry ────────────────────────────────────
def auto_label_clusters(texts: list[str], cluster_ids: np.ndarray) -> dict[int, str]:
    unique_ids = sorted(c for c in set(cluster_ids) if c != -1)
    result = {}
    for cid in unique_ids:
        members = [t for t, c in zip(texts, cluster_ids) if c == cid]
        # Most common entry is the label
        from collections import Counter
        counts = Counter(members)
        result[cid] = counts.most_common(1)[0][0].title()
    return result


# ─── Build cluster summary for review ──────────────────────────────────────
def build_summary(*sides) -> pd.DataFrame:
    """
    Each element of sides is a tuple: (side_name, df, id_col, label_col).
    """
    rows = []
    for side_name, df, id_col, label_col in sides:
        for (cid, label), grp in df.groupby([id_col, label_col]):
            from collections import Counter
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


# ─── Labels to exclude from the Sankey entirely ────────────────────────────
# Entries mapped to these labels are dropped from flows (not shown as a node).
# This covers: noise, model hallucinations, and variables that cannot be
# endogenous (e.g. weather phenomena that are quasi-random by nature).
ENDOG_EXCLUDE  = {"Other (Endogenous Variables)"}
RAIN_EXCLUDE   = {"Other (Rainfall Metrics)"}
DEPVAR_EXCLUDE = {"Other (Dependent Variables)"}


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
    left_colours  = [f"hsl({int(200 + 120*i/max(n_left-1,1))},60%,55%)"  for i in range(n_left)]
    right_colours = [f"hsl({int(20  + 40 *i/max(n_right-1,1))},70%,55%)" for i in range(n_right)]

    fig = go.Figure(go.Sankey(
        arrangement="snap",
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
            color="rgba(160,160,160,0.25)",
        ),
    ))

    fig.update_layout(
        title_text=title,
        title_font_size=18,
        font_size=13,
        height=900,
        margin=dict(l=20, r=20, t=60, b=20),
    )
    return fig, left_nodes


# ─── Main ──────────────────────────────────────────────────────────────────
def process_side(
    rain_df_raw: pd.DataFrame,
    col: str,
    min_cluster_size: int,
    label_overrides: dict[int, str],
    id_col: str,
    label_col: str,
    side_name: str,
    requires_rainfall: bool = False,
) -> pd.DataFrame:
    print(f"\n[{side_name}]")
    exp = expand_column(rain_df_raw, col, requires_rainfall=requires_rainfall)
    print(f"  Entries after cleaning: {len(exp)} (from {rain_df_raw[col].notna().sum()} non-null rows)")

    if len(exp) == 0:
        raise ValueError(f"No clean entries found in column '{col}'.")

    texts = exp["entry"].tolist()

    print(f"  Embedding {len(texts)} entries...")
    embeddings = embed_texts(texts)

    cluster_ids = cluster_embeddings(embeddings, min_cluster_size)
    cluster_ids = merge_duplicate_clusters(cluster_ids, embeddings, MERGE_THRESHOLD)

    n_clusters = len(set(cluster_ids) - {-1})
    n_noise    = (cluster_ids == -1).sum()
    print(f"  Clusters after merging: {n_clusters}  |  Noise points: {n_noise} ({100*n_noise/len(cluster_ids):.0f}%)")

    auto = auto_label_clusters(texts, cluster_ids)
    final = {**auto, **label_overrides, -1: f"Other ({side_name})"}

    exp[id_col]    = cluster_ids
    exp[label_col] = [final.get(c, f"Cluster {c}") for c in cluster_ids]

    for cid in sorted(final):
        n = int((cluster_ids == cid).sum())
        if n > 0:
            print(f"    {cid:3d}: {final[cid]}  ({n} entries)")

    return exp


def main():
    print("Loading data...")
    df = pd.read_csv(INPUT_CSV)
    rain_df_raw = df[df["Instrumental Variable Rainfall"] == 1.0].copy()
    print(f"Rainfall IV papers: {len(rain_df_raw)}")

    endog_exp = process_side(
        rain_df_raw,
        col="Endogenous Variable(s)",
        min_cluster_size=MIN_CLUSTER_SIZE_ENDOG,
        label_overrides=ENDOG_LABEL_OVERRIDES,
        id_col="endog_cluster_id",
        label_col="endog_cluster_label",
        side_name="Endogenous Variables",
    )

    rain_exp = process_side(
        rain_df_raw,
        col="Rainfall Metric",
        min_cluster_size=MIN_CLUSTER_SIZE_RAIN,
        label_overrides=RAIN_LABEL_OVERRIDES,
        id_col="rain_cluster_id",
        label_col="rain_cluster_label",
        side_name="Rainfall Metrics",
        requires_rainfall=True,
    )

    depvar_exp = process_side(
        rain_df_raw,
        col="Dependent Variables",
        min_cluster_size=MIN_CLUSTER_SIZE_DEPVAR,
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
        rain_exp, endog_exp, rain_df_raw.index,
        left_label_col="rain_cluster_label",
        right_label_col="endog_cluster_label",
        left_exclude=RAIN_EXCLUDE,
        right_exclude=ENDOG_EXCLUDE,
        title="Rainfall Instruments → Endogenous Variables",
    )
    fig.write_html(OUTPUT_HTML)
    print(f"Sankey → {OUTPUT_HTML}")

    print("\nBuilding Sankey: Rainfall → Dependent Variables...")
    fig_depvar, _ = build_sankey(
        rain_exp, depvar_exp, rain_df_raw.index,
        left_label_col="rain_cluster_label",
        right_label_col="depvar_cluster_label",
        left_exclude=RAIN_EXCLUDE,
        right_exclude=DEPVAR_EXCLUDE,
        title="Rainfall Instruments → Dependent Variables",
        node_pad=50,
        left_node_order=rain_node_order,
    )
    fig_depvar.write_html(OUTPUT_HTML_DEPVAR)
    print(f"Sankey → {OUTPUT_HTML_DEPVAR}")


if __name__ == "__main__":
    main()

