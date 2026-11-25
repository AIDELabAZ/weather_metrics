"""
Thesis figures for the GPT-4.1 SFT iteration only.

  sankey   sankey_final.{png,eps,csv}: rainfall IV -> endogenous-variable
           Sankey on the FULL SFT output (output/gpt/sft/full_sft_gpt_output.csv,
           3,755 papers) stacked with ALL human-labelled papers
           (training/training_new_labels/training_all_new.xlsx, 439 papers).
           Categorised with the same classifier setting as analysis/classifier/8b/
           (qwen3-8b, concept gate). Every within-paper IV x endogenous pair with
           both ends coded is one link; the CSV lists each link.

  metrics  Full validation-metric set for SFT on the 88-paper held-out test
           set, read from merged_data_gpt_finetune.csv (written by
           model_eval.R, so numbers match model_comparison.tex):
             - binary metrics (accuracy, sensitivity, specificity, precision,
               F1, balanced accuracy) + confusion counts per binary field
             - cross-encoder similarity summaries per text field
           -> CSVs, a LaTeX table, and a composite figure.

Everything is written to <OneDrive>/weather_iv_lit/writing/thesis/.

Usage (from lit_review/):
  DYLD_FALLBACK_LIBRARY_PATH=/opt/homebrew/lib python3 analysis/sft_thesis_figures.py [sankey] [metrics]
"""

import os
import sys

import numpy as np
import pandas as pd

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

ROOT = "/Users/kieran/Library/CloudStorage/OneDrive-UniversityofArizona/weather_iv_lit"
OUT = os.path.join(ROOT, "writing", "thesis")

SFT_FULL = os.path.join(ROOT, "output", "gpt", "sft", "full_sft_gpt_output.csv")
HUMAN_XLSX = os.path.join(ROOT, "training", "training_new_labels", "training_all_new.xlsx")
SFT_MERGED_TEST = os.path.join(ROOT, "output", "gpt", "sft", "merged_data_gpt_finetune.csv")

HUMAN_TO_MODEL = {
    "filename": "File Name", "title": "Title", "doi": "DOI",
    "emp_bin": "Empirical Analysis", "dep_var": "Dependent Variable(s)",
    "end_bin": "Endogeneity Problem", "end_var": "Endogenous Variable(s)",
    "iv_bin": "Instrumental Variable Used", "iv_var": "Instrumental Variable(s)",
    "rain_bin": "Instrumental Variable Rainfall", "rain_var": "Rainfall Instrument",
}


# ─── Sankey ──────────────────────────────────────────────────────────────────

def build_sankey_input(path: str) -> pd.DataFrame:
    """Full SFT output stacked with all human-labelled papers, written to `path`."""
    model = pd.read_csv(SFT_FULL)
    human = pd.read_excel(HUMAN_XLSX)[list(HUMAN_TO_MODEL)].rename(columns=HUMAN_TO_MODEL)
    model.insert(0, "source", "sft_model")
    human.insert(0, "source", "human")
    overlap = set(model["File Name"].str.strip().str.lower()) & set(human["File Name"].str.strip().str.lower())
    assert not overlap, f"SFT and human files overlap: {sorted(overlap)[:5]}"
    both = pd.concat([model, human[model.columns]], ignore_index=True)
    both.to_csv(path, index=False)
    rain = both["Instrumental Variable Rainfall"] == 1
    print(f"Sankey input: {len(model)} SFT + {len(human)} human papers = {len(both)}; "
          f"rainfall-IV papers: {int(rain[both.source == 'sft_model'].sum())} SFT + "
          f"{int(rain[both.source == 'human'].sum())} human")
    return both


def run_sankey() -> None:
    """sankey_final.{png,eps,csv}: every within-paper rainfall-IV x endogenous
    pair with both ends coded is one link (sic.COUNT_RELATIONSHIPS), labels
    outside the diagram. The CSV has one row per drawn link."""
    import tempfile

    import fixed_label_classifier as flc
    import sankey_iv_clustering as sic
    flc.BACKBONE, flc.GATE = "qwen3-8b", "concept"
    sic.CATEGORIZER = "fixed"
    sic.COUNT_RELATIONSHIPS = True
    sic.ONE_TO_ONE_ONLY = sic.PAIR_BY_POSITION = False
    sic.OUTSIDE_LABELS = True
    sic.OUTPUT_PNG_ENDOG = os.path.join(OUT, "sankey_final.png")
    sic.OUTPUT_EPS_ENDOG = os.path.join(OUT, "sankey_final.eps")
    # Everything else the pipeline can write is switched off.
    sic.OUTPUT_PNG_WIDE_ENDOG = sic.OUTPUT_HTML_ENDOG = sic.CLUSTER_SUMMARY_ENDOG = None
    sic.REJECTED_ENTRIES_CSV = sic.CLASSIFIER_AUDIT_CSV = None
    with tempfile.TemporaryDirectory() as tmp:
        sic.MERGED_CSV = os.path.join(tmp, "sft_full_plus_human_input.csv")
        both = build_sankey_input(sic.MERGED_CSV)
        sic.main()

    links = pd.DataFrame(sic.LAST_LINKS)
    both["paper_key"] = both["File Name"].map(sic.normalize_filename)
    rain = both[both["Instrumental Variable Rainfall"] == 1]
    meta = rain.groupby("paper_key").agg(
        file_name=("File Name", "first"), title=("Title", "first"),
        source=("source", lambda s: "+".join(sorted(set(s)))))
    links = links.join(meta, on="paper_key")
    cols = ["paper_key", "file_name", "title", "source", "rainfall_iv", "rainfall_category",
            "endogenous_variable", "endogenous_category"]
    csv = os.path.join(OUT, "sankey_final.csv")
    links[cols].to_csv(csv, index=False)
    print(f"Sankey data -> {csv} ({len(links)} links from {links.paper_key.nunique()} papers)")


# ─── Metrics ─────────────────────────────────────────────────────────────────

BINARY_FIELDS = {"emp": "Empirical Analysis", "end": "Endogeneity Problem",
                 "iv": "Has IV", "rain": "Is Rainfall IV"}
SIM_FIELDS = {"ptitle": "Title", "doi": "DOI", "depen": "Dependent Variable(s)",
              "endog": "Endogenous Variable(s)", "iv": "Instrument(s)",
              "rainmet": "Rainfall Instrument"}
METRICS = ["Accuracy", "Sensitivity", "Specificity", "Precision", "F1", "Balanced accuracy"]


def _div(a, b):
    return a / b if b else np.nan


def binary_table(df) -> pd.DataFrame:
    rows = []
    for key, name in BINARY_FIELDS.items():
        h, m = df[f"{key}_bin_human"].astype(int), df[f"{key}_bin_model"].astype(int)
        tp, tn = int(((h == 1) & (m == 1)).sum()), int(((h == 0) & (m == 0)).sum())
        fp, fn = int(((h == 0) & (m == 1)).sum()), int(((h == 1) & (m == 0)).sum())
        sens, spec, prec = _div(tp, tp + fn), _div(tn, tn + fp), _div(tp, tp + fp)
        rows.append({
            "field": name, "n": len(df), "TP": tp, "FP": fp, "FN": fn, "TN": tn,
            "Accuracy": (tp + tn) / len(df), "Sensitivity": sens, "Specificity": spec,
            "Precision": prec, "F1": _div(2 * prec * sens, prec + sens),
            "Balanced accuracy": (sens + spec) / 2,
        })
    return pd.DataFrame(rows)


def similarity_table(df) -> pd.DataFrame:
    rows = []
    for key, name in SIM_FIELDS.items():
        s = df[f"{key}_similarity"].dropna()
        rows.append({"field": name, "n": len(s), "mean": s.mean(), "sd": s.std(),
                     "median": s.median(), "q25": s.quantile(.25), "q75": s.quantile(.75),
                     "min": s.min(), "max": s.max()})
    return pd.DataFrame(rows)


def write_latex(b: pd.DataFrame, s: pd.DataFrame, n: int, path: str) -> None:
    f3 = lambda x: "--" if pd.isna(x) else f"{x:.3f}"
    L = [r"\begin{table}[htbp]", r"\centering",
         r"\caption{Validation performance of the fine-tuned (SFT) GPT-4.1 extractor on the held-out test set}",
         r"\label{tab:sft_validation}", r"\small"]
    L += [r"\begin{tabular}{lcccccccccc}", r"\toprule",
          r"\multicolumn{11}{l}{\textit{Panel A. Binary classification (positive class = 1)}} \\",
          r"Field & TP & FP & FN & TN & Accuracy & Sensitivity & Specificity & Precision & F1 & Bal.\ acc. \\",
          r"\midrule"]
    for _, r in b.iterrows():
        L.append(f"{r['field']} & {r.TP} & {r.FP} & {r.FN} & {r.TN} & "
                 + " & ".join(f3(r[m]) for m in METRICS) + r" \\")
    L += [r"\midrule",
          r"\multicolumn{11}{l}{\textit{Panel B. Semantic similarity to human labels (cross-encoder score, 0--1)}} \\",
          r"Field & $n$ & Mean & SD & Median & Q1 & Q3 & Min & Max & & \\", r"\midrule"]
    for _, r in s.iterrows():
        L.append(f"{r['field']} & {r.n} & " + " & ".join(f3(r[c]) for c in
                 ["mean", "sd", "median", "q25", "q75", "min", "max"]) + r" & & \\")
    L += [r"\bottomrule", r"\end{tabular}",
          rf"\par\smallskip\footnotesize Notes: $n={n}$ held-out papers excluded from fine-tuning, compared with "
          r"human labels. Model: ft:gpt-4.1-2025-04-14. Similarity is scored on papers where both entries are present.",
          r"\end{table}"]
    with open(path, "w") as f:
        f.write("\n".join(L) + "\n")


def draw_figure(df, b, s, png, pdf) -> None:
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt
    from matplotlib.patches import Patch
    import model_comparison_figs as mcf

    INK, INK2, MUTED, GRID = mcf.INK, mcf.INK2, mcf.MUTED, mcf.GRID
    SFT = "#57A773"  # SFT colour used across the GPT comparison figures
    n = len(df)
    fig = plt.figure(figsize=(14, 7.2))
    gs = fig.add_gridspec(2, 3, width_ratios=[0.8, 1.25, 1.15], height_ratios=[1, 1],
                          left=0.06, right=0.95, top=0.84, bottom=0.10, wspace=0.62, hspace=0.45)

    def header(x, letter, title, sub):
        fig.text(x, 0.94, letter, size=12, weight="bold", color=INK)
        fig.text(x + 0.016, 0.94, title, size=12, weight="bold", color=INK)
        fig.text(x, 0.905, sub, size=8.5, color=MUTED)

    # a. confusion mosaics, 2x2 grid of fields inside the first column
    header(0.03, "a", "Confusion mosaics", f"Area = share of n={n}; counts in cells")
    sub = gs[:, 0].subgridspec(4, 1, hspace=0.55)
    for i, (key, name) in enumerate(BINARY_FIELDS.items()):
        ax = fig.add_subplot(sub[i])
        r = b.iloc[i]
        mcf.draw_mosaic(ax, r.TN, r.FP, r.FN, r.TP)
        ax.set_title(name, size=9, weight="bold", color=INK2, loc="left", pad=11)
    fig.legend([Patch(facecolor=mcf.MOSAIC_COLORS[k]) for k in ("TN", "FP", "FN", "TP")],
               ["TN", "FP", "FN", "TP"], loc="lower left", bbox_to_anchor=(0.03, 0.015),
               ncol=4, frameon=False, fontsize=8, handlelength=1, handleheight=1)

    # b. metric heat-free dot plot: metrics x fields, value labels
    header(0.33, "b", "Classification performance", "Percent; dashed line = 50% (chance)")
    ax = fig.add_subplot(gs[:, 1])
    fields = list(BINARY_FIELDS.values())
    for j, m in enumerate(METRICS):
        for i, fname in enumerate(fields):
            y = j * (len(fields) + 1.2) + i
            v = b.loc[b.field == fname, m].iloc[0] * 100
            ax.plot([0, v], [y, y], color=GRID, lw=2, solid_capstyle="round", zorder=1)
            ax.plot(v, y, "o", ms=7, mfc=SFT, mec=mcf._darken(SFT), mew=0.7, zorder=3, clip_on=False)
            ax.text(105, y, f"{v:.1f}", va="center", ha="left", size=7.5, color=INK2)
            ax.text(-1.5, y, fname, va="center", ha="right", size=7.5, color=INK2)
        ax.text(-1.5, j * (len(fields) + 1.2) - 0.95, m, ha="right", va="center",
                size=8.5, weight="bold", color=INK)
    ax.axvline(50, color=MUTED, lw=0.8, ls=(0, (3, 3)), zorder=0)
    ax.set_xlim(0, 103); ax.invert_yaxis(); ax.set_yticks([])
    ax.set_xticks([0, 25, 50, 75, 100]); ax.tick_params(axis="x", labelsize=8, length=0)
    ax.grid(axis="x", color=GRID, lw=0.6); ax.set_axisbelow(True)
    for sp in ("top", "right", "left"):
        ax.spines[sp].set_visible(False)
    ax.set_xlabel("Performance (%)", size=8.5, color=INK2)

    # c. similarity distributions: strip of per-paper scores + box summary
    header(0.665, "c", "Semantic similarity to human labels",
           "Dots = papers; gray bar = IQR; tick = median; diamond = mean")
    ax = fig.add_subplot(gs[:, 2])
    rng = np.random.default_rng(0)
    for i, (key, name) in enumerate(SIM_FIELDS.items()):
        v = df[f"{key}_similarity"].dropna().values
        r = s.iloc[i]
        ax.scatter(v, i + rng.uniform(-0.22, 0.22, len(v)), s=9, color=SFT, alpha=0.45, lw=0, zorder=2)
        ax.plot([r.q25, r.q75], [i + 0.36, i + 0.36], color=mcf.AXIS, lw=2, solid_capstyle="round", zorder=3)
        ax.plot(r["median"], i + 0.36, "|", ms=8, mew=1.2, color=INK2, zorder=4)
        ax.plot(r["mean"], i + 0.36, "D", ms=5, mfc="white", mec=mcf._darken(SFT), mew=1, zorder=5)
        ax.text(1.03, i, f"{r['mean']:.2f}\n(n={r.n})", va="center", size=7.5, color=INK2,
                transform=ax.get_yaxis_transform())
    ax.set_yticks(range(len(SIM_FIELDS)), list(SIM_FIELDS.values()), size=8.5, color=INK2)
    ax.set_ylim(len(SIM_FIELDS) - 0.4, -0.6); ax.set_xlim(-0.02, 1.02)
    ax.tick_params(axis="both", length=0, labelsize=8)
    ax.grid(axis="x", color=GRID, lw=0.6); ax.set_axisbelow(True)
    for sp in ("top", "right", "left"):
        ax.spines[sp].set_visible(False)
    ax.set_xlabel("Cross-encoder similarity (0–1)", size=8.5, color=INK2)

    fig.text(0.97, 0.015, "SFT: ft:gpt-4.1-2025-04-14 (aide-lab) · held-out test set",
             ha="right", size=7.5, color=MUTED)
    fig.savefig(png, dpi=250)
    fig.savefig(pdf)
    plt.close(fig)


def run_metrics() -> None:
    df = pd.read_csv(SFT_MERGED_TEST)
    b, s = binary_table(df), similarity_table(df)
    b.to_csv(os.path.join(OUT, "sft_gpt_binary_metrics.csv"), index=False)
    s.to_csv(os.path.join(OUT, "sft_gpt_similarity_metrics.csv"), index=False)
    write_latex(b, s, len(df), os.path.join(OUT, "sft_gpt_validation_metrics.tex"))
    draw_figure(df, b, s, os.path.join(OUT, "sft_gpt_validation_metrics.png"),
                os.path.join(OUT, "sft_gpt_validation_metrics.pdf"))
    with pd.option_context("display.width", 200, "display.precision", 3):
        print(b); print(s)


if __name__ == "__main__":
    steps = sys.argv[1:] or ["metrics", "sankey"]
    os.makedirs(OUT, exist_ok=True)
    if "metrics" in steps:
        run_metrics()
    if "sankey" in steps:
        run_sankey()
    print(f"Outputs -> {OUT}")
