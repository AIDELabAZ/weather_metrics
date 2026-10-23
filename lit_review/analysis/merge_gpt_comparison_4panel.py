#!/usr/bin/env python3
"""Four-panel model-comparison figures, one per comparison set.

Reuses panels a-c (confusion mosaics, classification performance, similarity
summary) from analysis/model_comparison_figs.py, re-laid-out 2x2, with the
similarity-KDE grid from analysis/model_eval.R embedded as panel d:

    a  b
    c  d

Two comparison sets (see COMPARISONS), approaches taken from
model_comparison_figs.FAMILIES:
  gpt      -- main text: Zero-shot / RAG / SFT within GPT-4.1. Agentic is
              excluded from every panel: panel d (model_eval.R's
              density_model_keys) already drops it.
  frontier -- appendix / robustness: SFT (GPT-4.1) against the newest
              zero-shot model in each family. Approaches whose merged CSV
              doesn't exist yet (Llama, Claude) are skipped with a warning.

merged_data_* CSVs are read from analysis/model_comparison_figs.py's
MERGED_DIRS, where model_eval.R writes them. Panel d's KDE PNGs are read from
writing/figures/, so copy model_eval.R's fresh similarity_kdensities*.png
(from output/gpt/ and output/frontier/) there before running this.

Run with: /Users/kieran/.virtualenvs/bert_env/bin/python3 analysis/merge_gpt_comparison_4panel.py
"""

import os
import sys
import textwrap

import numpy as np
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

FIGURES_DIR = (
    "/Users/kieran/Library/CloudStorage/OneDrive-UniversityofArizona/"
    "weather_iv_lit/writing/figures"
)

# Per comparison set: panel d's KDE source images (regular 3 x 2 grid and the
# wide 2 x 3 one, both written by model_eval.R's build_similarity_density_plot)
# and whether a missing merged CSV is an error (gpt) or a pending run that is
# skipped (frontier). Output filenames are prefixed with the set's key.
COMPARISONS = {
    "gpt": {
        "kde": os.path.join(FIGURES_DIR, "similarity_kdensities.png"),
        "kde_wide": os.path.join(FIGURES_DIR, "similarity_kdensities_wide.png"),
        "required": True,
    },
    "frontier": {
        "kde": os.path.join(FIGURES_DIR, "similarity_kdensities_frontier.png"),
        "kde_wide": os.path.join(FIGURES_DIR, "similarity_kdensities_frontier_wide.png"),
        "required": False,
    },
}


def variants(prefix):
    """(figsize, output filename, wide) for each orientation -- row/column
    fractions in render() are shared by both; canvas dimensions and output
    path differ, and `wide` also transposes panel a's mosaic grid (approaches
    as rows instead of columns) and swaps panel d to the wide KDE source image.
    Each PNG is saved alongside a same-named .eps (vector, no dpi needed)."""
    return [
        ((15, 17.75), os.path.join(FIGURES_DIR, f"{prefix}_model_comparison_4panel.png"), False),
        ((19, 13.5), os.path.join(FIGURES_DIR, f"{prefix}_model_comparison_4panel_wide.png"), True),
    ]


def panel_pngs(prefix):
    """Standalone per-panel PNGs -- one self-contained render per panel (own
    header, and its own copy of whichever legend that panel needs to be read
    without the other three), independent of the merged variants() above.
    a_wide is transposed: rows = approaches, cols = binary fields."""
    names = {
        "a": "panel_a_confusion_mosaics",
        "a_wide": "panel_a_confusion_mosaics_wide",
        "b": "panel_b_classification_performance",
        "c": "panel_c_similarity_summary",
        "d": "panel_d_similarity_density",
        "d_wide": "panel_d_similarity_density_wide",
    }
    return {k: os.path.join(FIGURES_DIR, f"{prefix}_model_comparison_{v}.png")
            for k, v in names.items()}


def load_data(approach_labels, required):
    keys, dfs, approaches = [], [], []
    for key, label in approach_labels.items():
        path = os.path.join(mcf.MERGED_DIRS[key], f"merged_data_{key}.csv")
        if not os.path.exists(path):
            if required:
                raise FileNotFoundError(f"missing merged data: {path}")
            print(f"  WARNING: {path} not found — skipping approach '{label}'")
            continue
        keys.append(key)
        dfs.append(pd.read_csv(path))
        approaches.append(label)
    return keys, dfs, approaches


def render(figsize, out_png, dfs, approaches, colors, kde_png, wide=False):
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
    if wide:
        # Transposed: rows = approaches, cols = binary fields (3x4 instead of
        # 4x3) -- column headers become the (2-line) field names, so they need
        # more headroom below the legend than the single-line approach headers.
        mosaic_top = ROW1_TOP - 0.09
        n_rows, n_cols = len(approaches), len(mcf.BINARY_FIELDS)
        # One row per approach: keep the total gap space what it was at 3
        # approaches (2 x 0.05), or 6+ rows get squashed to slivers.
        hgap = min(0.05, 0.10 / max(n_rows - 1, 1))
    else:
        mosaic_top = ROW1_TOP - 0.058
        n_rows, n_cols = len(mcf.BINARY_FIELDS), len(approaches)
        hgap = 0.05
    mosaic_rows = mcf.grid_axes(fig, A_X0 + 0.025, A_X1, ROW1_BOT, mosaic_top,
                                nrows=n_rows, ncols=n_cols, wgap=0.014, hgap=hgap)
    if wide:
        for c, (field, (_, wrapped)) in enumerate(mcf.BINARY_FIELDS.items()):
            pos = mosaic_rows[0][c].get_position()
            fig.text((pos.x0 + pos.x1) / 2, mosaic_top + 0.014, wrapped,
                     ha="center", va="bottom", size=7.5, weight="bold", color=mcf.INK2)
        for r, label in enumerate(approaches):
            pos = mosaic_rows[r][0].get_position()
            fig.text(A_X0 + 0.018, (pos.y0 + pos.y1) / 2, label, ha="right", va="center",
                     size=8.5, weight="bold", color=mcf.INK2)
            for c, field in enumerate(mcf.BINARY_FIELDS):
                mcf.draw_mosaic(mosaic_rows[r][c], *mcf.binary_confusion(dfs[r], field))
    else:
        for c, label in enumerate(approaches):
            pos = mosaic_rows[0][c].get_position()
            # Wrapped so adjacent narrow columns' headers don't run together.
            fig.text((pos.x0 + pos.x1) / 2, mosaic_top + 0.014, textwrap.fill(label, 10),
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
    offsets = np.linspace(-0.27, 0.27, len(approaches))
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
    d_ax.imshow(mpimg.imread(kde_png))
    d_ax.axis("off")

    os.makedirs(os.path.dirname(out_png), exist_ok=True)
    fig.savefig(out_png, dpi=200)
    print(f"saved {out_png}")
    out_eps = os.path.splitext(out_png)[0] + ".eps"
    fig.savefig(out_eps)
    print(f"saved {out_eps}")
    plt.close(fig)


def _save(fig, out_png):
    os.makedirs(os.path.dirname(out_png), exist_ok=True)
    fig.savefig(out_png, dpi=200)
    print(f"saved {out_png}")
    plt.close(fig)


def render_panel_a(dfs, approaches, colors, out_png):
    """Confusion mosaics -- no approach-color legend needed (columns are text-labeled)."""
    n_rows, n_cols = len(mcf.BINARY_FIELDS), len(approaches)
    fig = plt.figure(figsize=(2.05 * n_cols + 1.4, 1.75 * n_rows + 1.5))

    # No standalone_header -- the legend moves up into the space it used to
    # reserve, keeping the same gap to the grid below it.
    cell_handles = [Patch(facecolor=mcf.MOSAIC_COLORS[k], edgecolor="none", label=k)
                    for k in ("TN", "FP", "FN", "TP")]
    fig.legend(cell_handles, ["TN", "FP", "FN", "TP"], loc="lower left",
               bbox_to_anchor=(0.06, 0.96), ncol=4, frameon=False, fontsize=9,
               handlelength=1.0, handleheight=1.0, columnspacing=1.0, handletextpad=1.0)

    mosaic_top, mosaic_bot = 0.91, 0.055
    mosaic_rows = mcf.grid_axes(fig, 0.13, 0.98, mosaic_bot, mosaic_top,
                                nrows=n_rows, ncols=n_cols, wgap=0.022, hgap=0.06)
    for c, label in enumerate(approaches):
        pos = mosaic_rows[0][c].get_position()
        fig.text((pos.x0 + pos.x1) / 2, mosaic_top + 0.018, textwrap.fill(label, 10),
                 ha="center", va="bottom", size=10, weight="bold", color=mcf.INK2)
    for r, (field, (_, wrapped)) in enumerate(mcf.BINARY_FIELDS.items()):
        pos = mosaic_rows[r][0].get_position()
        fig.text(0.11, (pos.y0 + pos.y1) / 2, wrapped, ha="right", va="center",
                 size=9.5, weight="bold", color=mcf.INK2)
        for c, df in enumerate(dfs):
            mcf.draw_mosaic(mosaic_rows[r][c], *mcf.binary_confusion(df, field))

    _save(fig, out_png)


def render_panel_a_wide(dfs, approaches, colors, out_png):
    """Confusion mosaics, transposed for a landscape layout: rows = approaches,
    cols = binary fields (3 x 4 here vs. render_panel_a's 4 x 3)."""
    n_rows, n_cols = len(approaches), len(mcf.BINARY_FIELDS)
    fig = plt.figure(figsize=(2.05 * n_cols + 1.4, 1.9 * n_rows + 1.6))

    # No standalone_header -- legend and grid both move up into the freed space.
    cell_handles = [Patch(facecolor=mcf.MOSAIC_COLORS[k], edgecolor="none", label=k)
                    for k in ("TN", "FP", "FN", "TP")]
    fig.legend(cell_handles, ["TN", "FP", "FN", "TP"], loc="lower left",
               bbox_to_anchor=(0.06, 0.96), ncol=4, frameon=False, fontsize=9,
               handlelength=1.0, handleheight=1.0, columnspacing=1.0, handletextpad=1.0)

    # Column headers are the (2-line) field names, so the grid needs more
    # headroom above it than render_panel_a's single-line approach headers did.
    mosaic_top, mosaic_bot = 0.865, 0.055
    mosaic_rows = mcf.grid_axes(fig, 0.13, 0.98, mosaic_bot, mosaic_top,
                                nrows=n_rows, ncols=n_cols, wgap=0.022, hgap=0.06)
    for c, (field, (_, wrapped)) in enumerate(mcf.BINARY_FIELDS.items()):
        pos = mosaic_rows[0][c].get_position()
        fig.text((pos.x0 + pos.x1) / 2, mosaic_top + 0.018, wrapped,
                 ha="center", va="bottom", size=9.5, weight="bold", color=mcf.INK2)
    for r, label in enumerate(approaches):
        pos = mosaic_rows[r][0].get_position()
        fig.text(0.11, (pos.y0 + pos.y1) / 2, label, ha="right", va="center",
                 size=10, weight="bold", color=mcf.INK2)
        for c, field in enumerate(mcf.BINARY_FIELDS):
            mcf.draw_mosaic(mosaic_rows[r][c], *mcf.binary_confusion(dfs[r], field))

    _save(fig, out_png)


def render_panel_b(dfs, approaches, colors, out_png):
    """Classification performance -- carries its own approach-color legend."""
    fig = plt.figure(figsize=(2.35 * len(mcf.BINARY_FIELDS) + 1.3, 5.3))

    handles = [Line2D([0], [0], marker="o", ls="none", ms=7, mfc=c, mec=mcf._darken(c), mew=0.7)
               for c in colors]
    fig.legend(handles, approaches, loc="lower center", bbox_to_anchor=(0.5, 0.012),
               ncol=len(approaches), frameon=False, fontsize=10,
               handletextpad=0.4, columnspacing=1.6)

    # No standalone_header -- the grid (and each field's own ax.set_title
    # above it) moves up into the freed space.
    perf_top, perf_bot = 0.93, 0.165
    perf_axes = mcf.grid_axes(fig, 0.155, 0.98, perf_bot, perf_top,
                              nrows=1, ncols=len(mcf.BINARY_FIELDS), wgap=0.022, hgap=0)[0]
    offsets = np.linspace(-0.27, 0.27, len(approaches))
    for i, (field, (display, _)) in enumerate(mcf.BINARY_FIELDS.items()):
        ax = perf_axes[i]
        ax.set_title(display, size=10, weight="bold", color=mcf.INK, pad=10)
        mcf.draw_perf_column(ax, [mcf.binary_metrics(df, field) for df in dfs],
                             colors, offsets, first=(i == 0))
    fig.text((0.155 + 0.98) / 2, perf_bot - 0.065, "Performance (%)", ha="center", size=9.5,
              color=mcf.INK2)

    _save(fig, out_png)


def render_panel_c(dfs, approaches, colors, out_png):
    """Similarity summary -- carries its own approach-color legend + encoding key."""
    fig = plt.figure(figsize=(9.6, 5.6))

    # No standalone_header -- both legends and the axes below move up into
    # the freed space.
    handles = [Line2D([0], [0], marker="o", ls="none", ms=7, mfc=c, mec=mcf._darken(c), mew=0.7)
               for c in colors]
    fig.legend(handles, approaches, loc="upper right", bbox_to_anchor=(0.98, 0.98),
               frameon=False, fontsize=9.5, handletextpad=0.4, columnspacing=1.2)
    sim_legend_handles = [
        Line2D([0], [0], color=mcf.MUTED, lw=1.0, solid_capstyle="round"),
        Line2D([0], [0], color=mcf.INK2, lw=4, solid_capstyle="round"),
        Line2D([0], [0], marker="o", ls="none", ms=6, mfc=mcf.SURFACE, mec=mcf.INK2, mew=1.6),
        Line2D([0], [0], marker="|", ls="none", ms=7, mew=1.3, color=mcf.INK),
    ]
    fig.legend(sim_legend_handles, ["Min-max", "Mean ± SD", "Mean", "Median"],
               loc="lower left", bbox_to_anchor=(0.06, 0.95), ncol=4, frameon=False,
               fontsize=8.5, handlelength=1.6, columnspacing=1.6, handletextpad=0.8)

    sim_ax = fig.add_axes([0.24, 0.11, 0.60, 0.79])
    stats_by_approach = [{f: mcf.sim_stats(df, f) for f in mcf.SIM_FIELDS} for df in dfs]
    mcf.draw_sim_panel(sim_ax, stats_by_approach, colors, approaches)

    _save(fig, out_png)


def render_panel_d(out_png, img_path):
    """Similarity-KDE grid -- re-embeds the same external raster, no header, so
    no reserved header height either -- the image just fills the canvas.
    img_path's own aspect ratio drives fig_h, so the regular (3x2) and wide
    (2x3, see COMPARISONS' kde_wide) source grids each land at a sensible size."""
    img = mpimg.imread(img_path)
    img_h, img_w = img.shape[0], img.shape[1]

    fig_w = 7.5
    fig_h = fig_w * img_h / img_w
    fig = plt.figure(figsize=(fig_w, fig_h))

    d_ax = fig.add_axes([0.01, 0.01, 0.98, 0.98])
    d_ax.imshow(img)
    d_ax.axis("off")

    _save(fig, out_png)


def render_panels(dfs, approaches, colors, pngs, kde_png, kde_wide_png):
    render_panel_a(dfs, approaches, colors, pngs["a"])
    render_panel_a_wide(dfs, approaches, colors, pngs["a_wide"])
    render_panel_b(dfs, approaches, colors, pngs["b"])
    render_panel_c(dfs, approaches, colors, pngs["c"])
    if os.path.exists(kde_png):
        render_panel_d(pngs["d"], kde_png)
    else:
        print(f"  WARNING: {kde_png} not found — skipping panel d")
    if os.path.exists(kde_wide_png):
        render_panel_d(pngs["d_wide"], kde_wide_png)
    else:
        print(f"  WARNING: {kde_wide_png} not found — run the updated "
              f"model_eval.R (ncol=3 call) first, then rerun this script to get panel d's wide version")


def main():
    for prefix, cfg in COMPARISONS.items():
        print(f"Building {prefix} comparison ...")
        keys, dfs, approaches = load_data(mcf.FAMILIES[prefix]["approaches"], cfg["required"])
        # By position in MERGED_DIRS (= model_eval.R's model_paths order), not
        # in the approach list, so each approach matches its color in the
        # R-rendered panel d (and SFT is the same green in both sets).
        colors = [mcf.APPROACH_COLORS[list(mcf.MERGED_DIRS).index(k)] for k in keys]
        for figsize, out_png, wide in variants(prefix):
            kde_png = cfg["kde_wide"] if wide else cfg["kde"]
            if not os.path.exists(kde_png):
                print(f"  WARNING: {kde_png} not found — skipping {out_png} "
                      f"(copy the KDE grid from model_eval.R's output into writing/figures/ first, then rerun)")
                continue
            render(figsize, out_png, dfs, approaches, colors, kde_png, wide=wide)
        render_panels(dfs, approaches, colors, panel_pngs(prefix), cfg["kde"], cfg["kde_wide"])


if __name__ == "__main__":
    main()
