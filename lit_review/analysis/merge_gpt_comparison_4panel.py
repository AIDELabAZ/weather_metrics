#!/usr/bin/env python3
"""Four-panel GPT model-comparison figure.

Reuses panels a-c (confusion mosaics, classification performance, similarity
summary) from analysis/model_comparison_figs.py, re-laid-out 2x2, with the
similarity-KDE grid from analysis/model_eval.R (writing/figures/
similarity_kdensities.png) embedded as panel d:

    a  b
    c  d

Agentic is excluded from every panel: panel d (model_eval.R's
density_model_keys) already drops it, so a/b/c are rebuilt here from the same
three approaches (Zero-shot, RAG, SFT) to keep the shared legend consistent
across all four panels.

Note: analysis/model_comparison_figs.py's MERGED_DIRS points at
output/gpt/{baseline,rag,sft}, which is currently empty -- the merged_data_*
CSVs actually live under training/gpt/ (pre-dating the "update file structure
and pathnames" commit). This script reads them from there directly.

Run with: /Users/kieran/.virtualenvs/bert_env/bin/python3 analysis/merge_gpt_comparison_4panel.py
"""

import os
import sys

import pandas as pd
import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt
import matplotlib.image as mpimg
from matplotlib.lines import Line2D
from matplotlib.patches import Patch

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import model_comparison_figs as mcf

# ─── Paths ───────────────────────────────────────────────────────────────────

TRAINING_GPT_DIR = (
    "/Users/kieran/Library/CloudStorage/OneDrive-UniversityofArizona/"
    "weather_iv_lit/training/gpt"
)
KDENSITIES_PNG = (
    "/Users/kieran/Library/CloudStorage/OneDrive-UniversityofArizona/"
    "weather_iv_lit/writing/figures/similarity_kdensities.png"
)
FIGURES_DIR = (
    "/Users/kieran/Library/CloudStorage/OneDrive-UniversityofArizona/"
    "weather_iv_lit/writing/figures"
)
# (figsize, output filename) for each orientation -- row/column fractions
# below are shared by both; only the canvas dimensions and output path differ.
VARIANTS = [
    ((15, 17.75), os.path.join(FIGURES_DIR, "gpt_model_comparison_4panel.png")),
    ((19, 13.5), os.path.join(FIGURES_DIR, "gpt_model_comparison_4panel_wide.png")),
]

# Agentic excluded — matches model_eval.R's density_model_keys for panel d.
APPROACHES = {
    "gpt_baseline": "Zero-shot",
    "gpt_rag": "RAG",
    "gpt_finetune": "SFT",
}


def load_data():
    dfs, approaches = [], []
    for key, label in APPROACHES.items():
        path = os.path.join(TRAINING_GPT_DIR, f"merged_data_{key}.csv")
        if not os.path.exists(path):
            raise FileNotFoundError(f"missing merged data: {path}")
        dfs.append(pd.read_csv(path))
        approaches.append(label)
    return dfs, approaches


def render(figsize, out_png, dfs, approaches, colors):
    fig = plt.figure(figsize=figsize)

    # ── Shared approach legend (bottom center — a, b, c all use these colors) ──
    handles = [
        Line2D([0], [0], marker="o", ls="none", ms=6, mfc=c, mec=mcf._darken(c), mew=0.6)
        for c in colors
    ]
    fig.legend(
        handles, approaches, loc="lower center", bbox_to_anchor=(0.5, 0.012),
        ncol=len(approaches), frameon=False, fontsize=9.5,
        handletextpad=0.3, columnspacing=1.4,
    )

    # ── Row / column geometry (figure fractions) ──
    # Row heights (in figure fractions) are unchanged from before; the gap
    # between ROW1_BOT and ROW2_TOP is just wider now, and the figure grew
    # taller to absorb it so panel content keeps the same absolute scale.
    ROW1_TOP, ROW1_BOT = 0.938, 0.555
    ROW2_TOP, ROW2_BOT = 0.465, 0.053

    A_X0, A_X1 = 0.055, 0.47
    B_X0, B_X1 = 0.565, 0.975
    # C's left edge sits well clear of the figure boundary -- its y-tick labels
    # (e.g. "Endogenous Variable(s)") extend left of the axes and get clipped
    # at x=0 otherwise.
    C_X0, C_X1 = 0.15, 0.38
    D_X0, D_X1 = 0.50, 0.975

    # ─── Panel a: confusion mosaics ───
    mcf.panel_header(fig, A_X0, ROW1_TOP + 0.02, "a", "   Confusion mosaics",
                      "Area encodes each cell's share of n=88")
    cell_handles = [Patch(facecolor=mcf.MOSAIC_COLORS[k], edgecolor="none", label=k)
                    for k in ("TN", "FP", "FN", "TP")]
    fig.legend(cell_handles, ["TN", "FP", "FN", "TP"], loc="lower left",
               bbox_to_anchor=(A_X0, ROW1_TOP - 0.028), ncol=4, frameon=False, fontsize=7.5,
               handlelength=1.0, handleheight=1.0, columnspacing=1.0, handletextpad=1.0)
    mosaic_top = ROW1_TOP - 0.058
    mosaic_rows = mcf.grid_axes(fig, A_X0 + 0.025, A_X1, ROW1_BOT, mosaic_top,
                                nrows=len(mcf.BINARY_FIELDS), ncols=len(approaches),
                                wgap=0.014, hgap=0.05)
    for c, label in enumerate(approaches):
        pos = mosaic_rows[0][c].get_position()
        fig.text((pos.x0 + pos.x1) / 2, mosaic_top + 0.014, label,
                 ha="center", va="bottom", size=8.5, weight="bold", color=mcf.INK2)
    for r, (field, (_, wrapped)) in enumerate(mcf.BINARY_FIELDS.items()):
        pos = mosaic_rows[r][0].get_position()
        fig.text(A_X0 + 0.018, (pos.y0 + pos.y1) / 2, wrapped, ha="right", va="center",
                 size=8.5, weight="bold", color=mcf.INK2)
        for c, df in enumerate(dfs):
            mcf.draw_mosaic(mosaic_rows[r][c], *mcf.binary_confusion(df, field))

    # ─── Panel b: classification performance ───
    mcf.panel_header(fig, B_X0, ROW1_TOP + 0.02, "b", "   Classification performance",
                      "Dots compare the approaches within binary fields.")
    perf_top = ROW1_TOP - 0.058
    perf_axes = mcf.grid_axes(fig, B_X0, B_X1, ROW1_BOT, perf_top,
                              nrows=1, ncols=len(mcf.BINARY_FIELDS), wgap=0.016, hgap=0)[0]
    offsets = [-0.22, 0.0, 0.22][: len(approaches)]
    for i, (field, (display, _)) in enumerate(mcf.BINARY_FIELDS.items()):
        ax = perf_axes[i]
        ax.set_title(display, size=9, weight="bold", color=mcf.INK, pad=8)
        mcf.draw_perf_column(ax, [mcf.binary_metrics(df, field) for df in dfs],
                             colors, offsets, first=(i == 0))
    fig.text((B_X0 + B_X1) / 2, ROW1_BOT - 0.028, "Performance (%)",
              ha="center", size=8.5, color=mcf.INK2)

    # ─── Panel c: similarity summary ───
    mcf.panel_header(fig, C_X0, ROW2_TOP + 0.02, "c", "   Semantic similarity summary",
                      "Min-max, mean ± SD, mean, and median per field/approach.")
    sim_legend_handles = [
        Line2D([0], [0], color=mcf.MUTED, lw=1.0, solid_capstyle="round"),
        Line2D([0], [0], color=mcf.INK2, lw=4, solid_capstyle="round"),
        Line2D([0], [0], marker="o", ls="none", ms=6, mfc=mcf.SURFACE, mec=mcf.INK2, mew=1.6),
        Line2D([0], [0], marker="|", ls="none", ms=7, mew=1.3, color=mcf.INK),
    ]
    fig.legend(sim_legend_handles, ["Min-max", "Mean ± SD", "Mean", "Median"],
               loc="lower left", bbox_to_anchor=(C_X0, ROW2_TOP - 0.036), ncol=4, frameon=False,
               fontsize=7.5, handlelength=1.6, columnspacing=1.6, handletextpad=0.8)
    sim_top = ROW2_TOP - 0.075
    sim_ax = fig.add_axes([C_X0, ROW2_BOT, C_X1 - C_X0, sim_top - ROW2_BOT])
    stats_by_approach = [{f: mcf.sim_stats(df, f) for f in mcf.SIM_FIELDS} for df in dfs]
    mcf.draw_sim_panel(sim_ax, stats_by_approach, colors, approaches)

    # ─── Panel d: similarity-KDE grid (embedded raster from model_eval.R) ───
    mcf.panel_header(fig, D_X0, ROW2_TOP + 0.02, "d", "   Similarity density by field",
                      "Per-paper cross-encoder scores (analysis/model_eval.R).")
    d_ax = fig.add_axes([D_X0, ROW2_BOT, D_X1 - D_X0, ROW2_TOP - 0.05 - ROW2_BOT])
    d_ax.imshow(mpimg.imread(KDENSITIES_PNG))
    d_ax.axis("off")

    os.makedirs(os.path.dirname(out_png), exist_ok=True)
    fig.savefig(out_png, dpi=200)
    plt.close(fig)
    print(f"saved {out_png}")


def main():
    dfs, approaches = load_data()
    colors = mcf.APPROACH_COLORS[: len(approaches)]
    for figsize, out_png in VARIANTS:
        render(figsize, out_png, dfs, approaches, colors)


if __name__ == "__main__":
    main()
