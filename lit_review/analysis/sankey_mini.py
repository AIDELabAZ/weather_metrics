"""
sankey_mini.py

Mini preview Sankey diagrams built from fine-tuned model outputs (training run).
Replicates the logic of sankey_iv_clustering.py but reads model inference CSVs
instead of allpapers_output.csv.

Column mapping (finetune output → clustering script equivalents):
  "Rainfall Instrument"   → rainfall metric side
  "Endogenous Variable(s)"→ endogenous variable side
  "Dependent Variable(s)" → dependent variable side
  "Instrumental Variable Rainfall" → filter (keep == 1.0 or "1")

Usage: set INPUT_CSV and output paths, then run.
"""

import re
import unicodedata
from collections import defaultdict, Counter
import numpy as np
import pandas as pd
import hdbscan
import umap
import plotly.graph_objects as go
from sentence_transformers import SentenceTransformer
from sklearn.metrics.pairwise import cosine_similarity

# ─── Paths — edit to switch models ─────────────────────────────────────────
MODEL_LABEL = "Gemini Fine-Tuned"

INPUT_CSV = "/Users/kieran/Library/CloudStorage/OneDrive-UniversityofArizona/weather_iv_lit/training/models/output/finetune_gemini_aistudio_output.csv"

OUTPUT_DIR = "/Users/kieran/Library/CloudStorage/OneDrive-UniversityofArizona/weather_iv_lit/training/models/output"
OUTPUT_HTML_IV     = f"{OUTPUT_DIR}/sankey_mini_gemini_iv.html"
OUTPUT_HTML_DEPVAR = f"{OUTPUT_DIR}/sankey_mini_gemini_depvar.html"

# Column names in the input CSV
COL_RAIN_FILTER = "Instrumental Variable Rainfall"
COL_RAIN_METRIC = "Rainfall Instrument"
COL_ENDOG       = "Endogenous Variable(s)"
COL_DEPVAR      = "Dependent Variable(s)"

# ─── Clustering params (smaller than main script — training set is smaller) ─
MIN_CLUSTER_SIZE_ENDOG  = 3
MIN_CLUSTER_SIZE_RAIN   = 3
MIN_CLUSTER_SIZE_DEPVAR = 3
MIN_SAMPLES             = 2
UMAP_N_COMPONENTS       = 5
UMAP_N_NEIGHBORS        = 10
UMAP_MIN_DIST           = 0.0
MERGE_THRESHOLD         = 0.92

# ─── Cleaning config ────────────────────────────────────────────────────────
MAX_WORDS = 8
MIN_CHARS = 5

GENERIC_TERMS = {
    "rainfall", "precipitation", "rain", "weather", "climate",
    "precip", "ppt", "instrument", "variable", "endogenous",
    "data", "index", "measure", "level", "value", "total", "which",
    "particularly", "proxy", "quarterly", "monthly", "annual",
}

RAINFALL_REQUIRED_TERMS = {
    "rain", "rainfall", "precipitation", "precip", "ppt", "monsoon",
    "drought", "wet", "dry", "flood", "storm", "snow", "snowfall",
    "snowpack", "swe", "humidity", "moisture", "cumulative", "seasonal",
    "annual", "monthly", "weekly", "daily", "temperature", "climate",
    "weather", "spi", "spei", "pdsi", "wind", "sunshine",
    "cloud", "runoff", "river", "streamflow", "waterlog",
}

_EQUATION_CHARS  = re.compile(r"[=<>{}\|\\^~`]|\\[a-zA-Z]+")
_MOSTLY_NUMBERS  = re.compile(r"^\s*[\d\s\.\,\-\*\[\]\(\)]+\s*$")
_YEAR_ONLY       = re.compile(r"^\s*(19|20)\d{2}[\s\)\.,]*$")
_SUBSCRIPT_BLOCK = re.compile(r"[^\x00-\x7F]{3,}")
_SUBSCRIPT_VAR   = re.compile(r"\b[a-z]{1,6}[0-9]{0,2}(it|jt|ij|ijt|ilt|kt|ibt|abt)\b")
_SLASH_LIST      = re.compile(r"\w+/\w+/\w+")

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
    "we can control", "first stage", "second stage", "such that", "therefore",
    "in order to", "output format", "keep names", "only proceed", "answer using",
    "output exactly", "output one", "is endogenous", "have to proceed",
]

_NORMALIZATIONS = [
    (re.compile(r"\bln\b"),             "log"),
    (re.compile(r"\blog\s*\(?\s*"),     "log "),
    (re.compile(r"\bprecip\b"),         "precipitation"),
    (re.compile(r"\bppt\b"),            "precipitation"),
    (re.compile(r"\brain(?:fall)?\b"),  "rainfall"),
    (re.compile(r"\bann(?:ual)?\b"),    "annual"),
    (re.compile(r"\bseas(?:onal)?\b"),  "seasonal"),
    (re.compile(r"\bmon(?:thly)?\b"),   "monthly"),
    (re.compile(r"\bgdp\b"),            "gdp per capita"),
    (re.compile(r"\bcpi\b"),            "consumer price index"),
]


def normalize_text(txt):
    for pattern, replacement in _NORMALIZATIONS:
        txt = pattern.sub(replacement, txt)
    return re.sub(r"\s+", " ", txt).strip()


def proportion_ascii(txt):
    if not txt:
        return 0.0
    return sum(1 for c in txt if ord(c) < 128) / len(txt)


def is_sentence_like(txt):
    words = txt.split()
    if len(words) < 4:
        return False
    func_count = sum(1 for w in words if w in _FUNCTION_WORDS)
    return (func_count / len(words)) > 0.45


def clean_entry(txt, requires_rainfall=False):
    if not txt or not isinstance(txt, str):
        return None
    try:
        txt = unicodedata.normalize("NFKC", txt)
    except Exception:
        pass
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
    if all(_SUBSCRIPT_VAR.match(tok) for tok in tokens if len(tok) > 2):
        return None
    txt = re.sub(r"\(\s*(?:19|20)\d{2}\s*\)", "", txt)
    txt = re.sub(r"\s+", " ", txt).strip()
    if len(txt) < MIN_CHARS:
        return None
    words = txt.split()
    if len(words) > MAX_WORDS:
        txt = " ".join(words[:MAX_WORDS])
    if txt.strip() in GENERIC_TERMS:
        return None
    if requires_rainfall:
        if not any(term in txt for term in RAINFALL_REQUIRED_TERMS):
            return None
    txt = normalize_text(txt)
    if len(txt) < MIN_CHARS:
        return None
    return txt


def expand_column(df, col, requires_rainfall=False):
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


def embed_texts(texts):
    model = SentenceTransformer("all-MiniLM-L6-v2")
    return model.encode(texts, show_progress_bar=True, normalize_embeddings=True)


def cluster_embeddings(embeddings, min_cluster_size):
    n = len(embeddings)
    n_components = min(UMAP_N_COMPONENTS, n - 2)
    n_neighbors  = min(UMAP_N_NEIGHBORS, n - 1)
    print(f"  UMAP: {embeddings.shape[1]}d → {n_components}d (n_neighbors={n_neighbors})...")
    reducer = umap.UMAP(
        n_components=n_components,
        n_neighbors=n_neighbors,
        min_dist=UMAP_MIN_DIST,
        metric="cosine",
        random_state=42,
    )
    reduced = reducer.fit_transform(embeddings)
    print(f"  HDBSCAN (min_cluster_size={min_cluster_size})...")
    clusterer = hdbscan.HDBSCAN(
        min_cluster_size=min_cluster_size,
        min_samples=MIN_SAMPLES,
        metric="euclidean",
        cluster_selection_method="eom",
    )
    return clusterer.fit_predict(reduced)


def merge_duplicate_clusters(cluster_ids, embeddings, threshold):
    unique = sorted(c for c in set(cluster_ids) if c != -1)
    if len(unique) <= 1:
        return cluster_ids
    centroids = np.array([embeddings[cluster_ids == cid].mean(axis=0) for cid in unique])
    norms = np.linalg.norm(centroids, axis=1, keepdims=True)
    norms[norms == 0] = 1
    centroids_normed = centroids / norms
    sim = cosine_similarity(centroids_normed)
    np.fill_diagonal(sim, 0)
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

    remap = {cid: find(cid) for cid in unique}
    roots = sorted(set(remap.values()))
    root_to_new = {r: i for i, r in enumerate(roots)}
    remap = {cid: root_to_new[find(cid)] for cid in unique}
    return np.array([remap.get(c, -1) if c != -1 else -1 for c in cluster_ids])


def auto_label_clusters(texts, cluster_ids):
    result = {}
    for cid in sorted(c for c in set(cluster_ids) if c != -1):
        members = [t for t, c in zip(texts, cluster_ids) if c == cid]
        result[cid] = Counter(members).most_common(1)[0][0].title()
    return result


def process_side(df, col, min_cluster_size, side_name, id_col, label_col,
                 requires_rainfall=False):
    print(f"\n[{side_name}]")
    exp = expand_column(df, col, requires_rainfall=requires_rainfall)
    print(f"  Entries after cleaning: {len(exp)}")

    if len(exp) == 0:
        raise ValueError(f"No clean entries found in column '{col}'.")

    texts = exp["entry"].tolist()
    print(f"  Embedding {len(texts)} entries...")
    embeddings = embed_texts(texts)

    cluster_ids = cluster_embeddings(embeddings, min_cluster_size)
    cluster_ids = merge_duplicate_clusters(cluster_ids, embeddings, MERGE_THRESHOLD)

    n_clusters = len(set(cluster_ids) - {-1})
    n_noise    = (cluster_ids == -1).sum()
    print(f"  Clusters: {n_clusters}  |  Noise: {n_noise} ({100*n_noise/len(cluster_ids):.0f}%)")

    auto = auto_label_clusters(texts, cluster_ids)
    final = {**auto, -1: f"Other ({side_name})"}
    for cid in sorted(final):
        n = int((cluster_ids == cid).sum())
        if n > 0:
            print(f"    {cid:3d}: {final[cid]}  ({n} entries)")

    exp[id_col]    = cluster_ids
    exp[label_col] = [final.get(c, f"Cluster {c}") for c in cluster_ids]
    return exp


def build_sankey(left_df, right_df, paper_index,
                 left_label_col, right_label_col,
                 left_exclude, right_exclude,
                 title, node_pad=20):
    left_map = (
        left_df[~left_df[left_label_col].isin(left_exclude)]
        .groupby("paper_idx")[left_label_col].apply(set).to_dict()
    )
    right_map = (
        right_df[~right_df[right_label_col].isin(right_exclude)]
        .groupby("paper_idx")[right_label_col].apply(set).to_dict()
    )

    flows = defaultdict(int)
    for paper_idx in paper_index:
        for l in left_map.get(paper_idx, set()):
            for r in right_map.get(paper_idx, set()):
                flows[(l, r)] += 1

    if not flows:
        raise ValueError("No flows — check that both columns have overlapping papers.")

    left_totals  = defaultdict(int)
    right_totals = defaultdict(int)
    for (l, r), v in flows.items():
        left_totals[l]  += v
        right_totals[r] += v

    left_nodes  = sorted(left_totals,  key=lambda x: -left_totals[x])
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
    return fig


def main():
    print(f"Loading {MODEL_LABEL} output: {INPUT_CSV}")
    df = pd.read_csv(INPUT_CSV)

    # Normalise the rainfall filter column — handles 1.0, "1", "1.0"
    def is_rain_iv(val):
        try:
            return float(val) == 1.0
        except (ValueError, TypeError):
            return str(val).strip() == "1"

    rain_df = df[df[COL_RAIN_FILTER].apply(is_rain_iv)].copy()
    print(f"Rainfall IV papers: {len(rain_df)} / {len(df)}")

    if len(rain_df) < 5:
        print("Too few rainfall IV papers to cluster — exiting.")
        return

    rain_exp = process_side(
        rain_df, COL_RAIN_METRIC,
        min_cluster_size=MIN_CLUSTER_SIZE_RAIN,
        side_name="Rainfall Metrics",
        id_col="rain_cluster_id",
        label_col="rain_cluster_label",
        requires_rainfall=True,
    )

    endog_exp = process_side(
        rain_df, COL_ENDOG,
        min_cluster_size=MIN_CLUSTER_SIZE_ENDOG,
        side_name="Endogenous Variables",
        id_col="endog_cluster_id",
        label_col="endog_cluster_label",
    )

    depvar_exp = process_side(
        rain_df, COL_DEPVAR,
        min_cluster_size=MIN_CLUSTER_SIZE_DEPVAR,
        side_name="Dependent Variables",
        id_col="depvar_cluster_id",
        label_col="depvar_cluster_label",
    )

    RAIN_EXCLUDE   = {"Other (Rainfall Metrics)"}
    ENDOG_EXCLUDE  = {"Other (Endogenous Variables)"}
    DEPVAR_EXCLUDE = {"Other (Dependent Variables)"}

    print(f"\nBuilding Sankey: Rainfall Instruments → Endogenous Variables ({MODEL_LABEL})...")
    fig_iv = build_sankey(
        rain_exp, endog_exp, rain_df.index,
        left_label_col="rain_cluster_label",
        right_label_col="endog_cluster_label",
        left_exclude=RAIN_EXCLUDE,
        right_exclude=ENDOG_EXCLUDE,
        title=f"Rainfall Instruments → Endogenous Variables ({MODEL_LABEL})",
    )
    fig_iv.write_html(OUTPUT_HTML_IV)
    print(f"Saved → {OUTPUT_HTML_IV}")

    print(f"\nBuilding Sankey: Rainfall Instruments → Dependent Variables ({MODEL_LABEL})...")
    fig_dv = build_sankey(
        rain_exp, depvar_exp, rain_df.index,
        left_label_col="rain_cluster_label",
        right_label_col="depvar_cluster_label",
        left_exclude=RAIN_EXCLUDE,
        right_exclude=DEPVAR_EXCLUDE,
        title=f"Rainfall Instruments → Dependent Variables ({MODEL_LABEL})",
        node_pad=50,
    )
    fig_dv.write_html(OUTPUT_HTML_DEPVAR)
    print(f"Saved → {OUTPUT_HTML_DEPVAR}")

    print("\nDone.")


if __name__ == "__main__":
    main()
