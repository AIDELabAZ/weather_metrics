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
INPUT_CSV       = "/Users/kieran/Library/CloudStorage/OneDrive-UniversityofArizona/weather_iv_lit/training/models/output/allpapers_output.csv"
OUTPUT_HTML     = "/Users/kieran/Library/CloudStorage/OneDrive-UniversityofArizona/weather_iv_lit/training/models/output/sankey_rainfall_iv.html"
CLUSTER_SUMMARY = "/Users/kieran/Library/CloudStorage/OneDrive-UniversityofArizona/weather_iv_lit/training/models/output/cluster_summary.csv"

# ─── HDBSCAN / UMAP params ─────────────────────────────────────────────────
MIN_CLUSTER_SIZE_ENDOG = 6    # raise to get fewer, broader clusters
MIN_CLUSTER_SIZE_RAIN  = 5
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
def build_summary(endog_df: pd.DataFrame, rain_df: pd.DataFrame) -> pd.DataFrame:
    rows = []
    for side, df, id_col, label_col in [
        ("endog", endog_df, "endog_cluster_id", "endog_cluster_label"),
        ("rain",  rain_df,  "rain_cluster_id",  "rain_cluster_label"),
    ]:
        for (cid, label), grp in df.groupby([id_col, label_col]):
            from collections import Counter
            sample = [e for e, _ in Counter(grp["entry"]).most_common(8)]
            rows.append({
                "side": side,
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
ENDOG_EXCLUDE = {"Other (Endogenous Variables)"}
RAIN_EXCLUDE  = {"Other (Rainfall Metrics)"}


# ─── Sankey ────────────────────────────────────────────────────────────────
def build_sankey(endog_df: pd.DataFrame, rain_df: pd.DataFrame, paper_index) -> go.Figure:
    # Per-paper label sets, with excluded labels stripped out
    rain_map = (
        rain_df[~rain_df["rain_cluster_label"].isin(RAIN_EXCLUDE)]
        .groupby("paper_idx")["rain_cluster_label"].apply(set).to_dict()
    )
    endog_map = (
        endog_df[~endog_df["endog_cluster_label"].isin(ENDOG_EXCLUDE)]
        .groupby("paper_idx")["endog_cluster_label"].apply(set).to_dict()
    )

    flows: dict[tuple[str, str], int] = defaultdict(int)
    for paper_idx in paper_index:
        r_labels = rain_map.get(paper_idx, set())
        e_labels = endog_map.get(paper_idx, set())
        if not r_labels or not e_labels:
            continue
        for r in r_labels:
            for e in e_labels:
                flows[(r, e)] += 1

    if not flows:
        raise ValueError("No flows found — check that both columns have overlapping papers.")

    # Sort nodes by total flow for a cleaner diagram
    rain_totals  = defaultdict(int)
    endog_totals = defaultdict(int)
    for (r, e), v in flows.items():
        rain_totals[r]  += v
        endog_totals[e] += v

    rain_nodes  = sorted(rain_totals,  key=lambda x: -rain_totals[x])
    endog_nodes = sorted(endog_totals, key=lambda x: -endog_totals[x])
    all_nodes   = rain_nodes + endog_nodes
    node_idx    = {n: i for i, n in enumerate(all_nodes)}

    sources = [node_idx[r] for r, _ in flows]
    targets = [node_idx[e] for _, e in flows]
    values  = list(flows.values())

    n_rain  = len(rain_nodes)
    n_endog = len(endog_nodes)
    rain_colours  = [f"hsl({int(200 + 120*i/max(n_rain-1,1))},60%,55%)"  for i in range(n_rain)]
    endog_colours = [f"hsl({int(20  + 40 *i/max(n_endog-1,1))},70%,55%)" for i in range(n_endog)]

    fig = go.Figure(go.Sankey(
        arrangement="snap",
        node=dict(
            pad=20,
            thickness=18,
            line=dict(color="white", width=0.5),
            label=all_nodes,
            color=rain_colours + endog_colours,
        ),
        link=dict(
            source=sources,
            target=targets,
            value=values,
            color="rgba(160,160,160,0.25)",
        ),
    ))

    fig.update_layout(
        title_text="Rainfall Instruments → Endogenous Variables",
        title_font_size=18,
        font_size=13,
        height=900,
        margin=dict(l=20, r=20, t=60, b=20),
    )
    return fig


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

    summary = build_summary(endog_exp, rain_exp)
    summary.to_csv(CLUSTER_SUMMARY, index=False)
    print(f"\nCluster summary → {CLUSTER_SUMMARY}")
    print("Review it, add label overrides above, and rerun.")

    print("\nBuilding Sankey...")
    fig = build_sankey(endog_exp, rain_exp, rain_df_raw.index)
    fig.write_html(OUTPUT_HTML)
    print(f"Sankey → {OUTPUT_HTML}")


if __name__ == "__main__":
    main()
