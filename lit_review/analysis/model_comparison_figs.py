#!/usr/bin/env python3
"""Composite model-comparison figures, one per model family.

For each family (GPT today; Gemini/Gemma/Llama when their merged CSVs exist)
renders a single three-panel figure comparing the extraction approaches
(Zero-shot, RAG, Fine-tuned) on the 88-paper held-out test set:

  a. Confusion mosaics      — area-proportional 2x2 mosaics per binary field
  b. Classification dots    — Accuracy/Sensitivity/Specificity/Precision/F1/
                              Balanced accuracy per binary field
  c. Similarity summaries   — min-max span, mean dot, median tick of the
                              cross-encoder STS scores per text field

Inputs are the merged_data_{approach}.csv files written by analysis/model_eval.R;
this script computes nothing new, so its numbers match the LaTeX tables exactly.

Run with: /Users/kieran/.virtualenvs/bert_env/bin/python3 analysis/model_comparison_figs.py
"""

import os

import numpy as np
import pandas as pd
import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.lines import Line2D
from matplotlib.patches import Patch, Rectangle
from sklearn.metrics import (
    accuracy_score,
    balanced_accuracy_score,
    confusion_matrix,
    f1_score,
    precision_score,
    recall_score,
)

# ─── Paths ───────────────────────────────────────────────────────────────────

OUTPUT_ROOT = (
    "/Users/kieran/Library/CloudStorage/OneDrive-UniversityofArizona/"
    "weather_iv_lit/output"
)

# Per-approach directory holding merged_data_{key}.csv (written by
# analysis/model_eval.R). Keys match FAMILIES[...]["approaches"]:
# gpt_finetune's folder is "sft", agentic sits outside gpt/.
MERGED_DIRS = {
    "gpt_baseline": os.path.join(OUTPUT_ROOT, "gpt", "baseline"),
    "gpt_rag":      os.path.join(OUTPUT_ROOT, "gpt", "rag"),
    "gpt_finetune": os.path.join(OUTPUT_ROOT, "gpt", "sft"),
    "agentic":      os.path.join(OUTPUT_ROOT, "agentic"),
}

# Composite figures: OUTPUT_ROOT/<family>/<family>_figs/ (e.g. output/gpt/gpt_figs).
OUTPUT_DIR = OUTPUT_ROOT

# ─── Families and approaches ─────────────────────────────────────────────────
# Approach order is fixed and doubles as the color order; each approach's merged
# CSV is MERGED_DIRS[key]/merged_data_{key}.csv. Missing files are skipped with
# a warning so pending families can be listed here ahead of their data.

FAMILIES = {
    "gpt": {
        "display": "GPT",
        "approaches": {
            "gpt_baseline": "Zero-shot",
            "gpt_rag": "RAG",
            "gpt_finetune": "SFT",
            "agentic": "Agentic",
        },
        "footer": (
            "Zero-shot: gpt-4.1-2025-04-14  ·  RAG: gpt-4.1-2025-04-14 + "
            "text-embedding-3-small  ·  SFT: ft:gpt-4.1-2025-04-14 (aide-lab)  ·  "
            "Agentic: claude-sonnet-5 (section-router + reader/adversary + verifier + judge)"
        ),
    },
    # "gemini": {"display": "Gemini", "approaches": {"gemini_finetune": "SFT"}, "footer": ""},
    # "gemma":  {"display": "Gemma",  "approaches": {"gemma_finetune": "SFT"},  "footer": ""},
    # "llama":  {"display": "Llama",  "approaches": {"llama_finetune": "SFT"},  "footer": ""},
}

# ─── Field and metric orderings (mirror model_eval.R) ────────────────────────

BINARY_FIELDS = {
    "emp": ("Empirical Analysis", "Empirical\nAnalysis"),
    "end": ("Endogeneity Problem", "Endogeneity\nProblem"),
    "iv": ("Has IV", "Has IV"),
    "rain": ("Is Rainfall IV", "Is Rainfall\nIV"),
}

METRICS = [
    "Accuracy",
    "Sensitivity",
    "Specificity",
    "Precision",
    "F1",
    "Balanced accuracy",
]

SIM_FIELDS = {
    "ptitle": "Title",
    "doi": "DOI",
    "depen": "Dependent Variable(s)",
    "endog": "Endogenous Variable(s)",
    "iv": "Instrument(s)",
    "rainmet": "Rainfall Instrument",
}

# ─── Style tokens (dataviz palette, validated on white) ──────────────────────

INK = "#0b0b0b"
INK2 = "#52514e"
MUTED = "#898781"
GRID = "#e1e0d9"
AXIS = "#c3c2b7"
SURFACE = "#ffffff"

# Approach colors in config order — matches the trio used in analysis/model_eval.R
# (cyan/slate/green) so this script's figures read as the same series as the
# existing R-generated ones. Note: the slate #484D6D is low-chroma and reads
# close to gray, so it doesn't clear the dataviz skill's CVD-safety validator
# the way the skill's reference trio does — kept anyway for cross-figure consistency.
APPROACH_COLORS = ["#08B2E3", "#484D6D", "#57A773", "#C1666B"]

MOSAIC_COLORS = {"TN": "#08B2E3", "FP": "#e34948", "FN": "#eda100", "TP": "#57A773"}

plt.rcParams.update(
    {
        "font.family": "sans-serif",
        "font.sans-serif": ["Helvetica Neue", "Helvetica", "Arial", "DejaVu Sans"],
        "text.color": INK,
        "axes.edgecolor": AXIS,
        "axes.labelcolor": INK2,
        "xtick.color": MUTED,
        "ytick.color": INK2,
        "figure.facecolor": SURFACE,
        "axes.facecolor": SURFACE,
        "savefig.facecolor": SURFACE,
    }
)


def _darken(hex_color, factor=0.72):
    r, g, b = (int(hex_color[i : i + 2], 16) for i in (1, 3, 5))
    return "#%02x%02x%02x" % tuple(int(v * factor) for v in (r, g, b))


def _lighten(hex_color, factor=0.6):
    r, g, b = (int(hex_color[i : i + 2], 16) for i in (1, 3, 5))
    return "#%02x%02x%02x" % tuple(int(v + (255 - v) * factor) for v in (r, g, b))


# ─── Metric computation ──────────────────────────────────────────────────────


def binary_confusion(df, field):
    """Return (tn, fp, fn, tp) for one field, positive class = 1."""
    cm = confusion_matrix(df[f"{field}_bin_human"], df[f"{field}_bin_model"], labels=[0, 1])
    return cm[0, 0], cm[0, 1], cm[1, 0], cm[1, 1]


def binary_metrics(df, field):
    """Metric name -> value in percent (NaN when undefined), matching caret."""
    human = df[f"{field}_bin_human"]
    model = df[f"{field}_bin_model"]
    tn, fp, _, _ = binary_confusion(df, field)
    specificity = tn / (tn + fp) if (tn + fp) > 0 else np.nan
    vals = {
        "Accuracy": accuracy_score(human, model),
        "Sensitivity": recall_score(human, model, pos_label=1, zero_division=np.nan),
        "Specificity": specificity,
        "Precision": precision_score(human, model, pos_label=1, zero_division=np.nan),
        "F1": f1_score(human, model, pos_label=1, zero_division=np.nan),
        "Balanced accuracy": balanced_accuracy_score(human, model),
    }
    return {k: v * 100 for k, v in vals.items()}


def sim_stats(df, field):
    """Nan-safe summary of one similarity column, or None if absent/empty."""
    col = f"{field}_similarity"
    if col not in df.columns:
        return None
    s = df[col].dropna()
    if s.empty:
        return None
    return {
        "n": len(s),
        "min": s.min(),
        "max": s.max(),
        "mean": s.mean(),
        "median": s.median(),
        "std": s.std(),
    }


# ─── Layout helpers ──────────────────────────────────────────────────────────


def grid_axes(fig, x0, x1, y0, y1, nrows, ncols, wgap, hgap):
    """Axes grid in figure fractions, row-major, top row first."""
    w = (x1 - x0 - (ncols - 1) * wgap) / ncols
    h = (y1 - y0 - (nrows - 1) * hgap) / nrows
    rows = []
    for r in range(nrows):
        top = y1 - r * (h + hgap)
        rows.append(
            [fig.add_axes([x0 + c * (w + wgap), top - h, w, h]) for c in range(ncols)]
        )
    return rows


def panel_header(fig, x, y, letter, title, subcaption):
    fig.text(x, y, letter, size=10.5, weight="bold", color=INK)
    fig.text(x + 0.013, y, title, size=10.5, weight="bold", color=INK)
    fig.text(x, y - 0.024, subcaption, size=7.5, color=MUTED)


# ─── Panel a: confusion mosaics ──────────────────────────────────────────────


def draw_mosaic(ax, tn, fp, fn, tp):
    """2x2 mosaic: rows = actual (0 top), widths within row = predicted split."""
    ax.set_xlim(0, 1)
    ax.set_ylim(0, 1)
    ax.axis("off")
    n = tn + fp + fn + tp
    if n == 0:
        return
    h_top = (tn + fp) / n  # actual 0
    h_bot = (fn + tp) / n  # actual 1
    cells = []
    if h_top > 0:
        w = tn / (tn + fp)
        cells += [
            ("TN", tn, 0, h_bot, w, h_top),
            ("FP", fp, w, h_bot, 1 - w, h_top),
        ]
    if h_bot > 0:
        w = fn / (fn + tp)
        cells += [
            ("FN", fn, 0, 0, w, h_bot),
            ("TP", tp, w, 0, 1 - w, h_bot),
        ]
    for name, count, x, y, cw, ch in cells:
        in_top_band = name in ("TN", "FP")
        if count == 0:
            continue
        ax.add_patch(
            Rectangle((x, y), cw, ch, facecolor=MOSAIC_COLORS[name],
                      edgecolor=SURFACE, linewidth=1.5)
        )
        cx = x + cw / 2
        if cw > 0.14 and ch > 0.16:
            ax.text(cx, y + ch / 2, str(count), ha="center", va="center",
                    size=7.5, weight="bold", color=INK)
        elif in_top_band:  # sliver in the top (actual-0) band: label above
            ax.text(min(max(cx, 0.03), 0.97), 1.03, str(count),
                    ha="center", va="bottom", size=6.5, color=INK2)
        else:  # sliver in the bottom band: label below
            ax.text(min(max(cx, 0.03), 0.97), -0.03, str(count),
                    ha="center", va="top", size=6.5, color=INK2)


# ─── Panel b: classification dot plots ───────────────────────────────────────


def draw_perf_column(ax, metric_values, colors, offsets, first):
    """One binary field: 6 metric rows of unconnected per-approach dots."""
    ax.set_xlim(0, 100)
    ax.set_ylim(len(METRICS) - 0.5, -0.5)  # inverted: Accuracy on top
    ax.set_xticks([0, 50, 100])
    ax.tick_params(axis="x", labelsize=7, length=0, pad=3)
    ax.set_yticks(range(len(METRICS)))
    if first:
        ax.set_yticklabels(METRICS, size=8, color=INK2)
        ax.tick_params(axis="y", length=0, pad=4)
    else:
        ax.set_yticklabels([])
        ax.tick_params(axis="y", length=0)
    ax.spines["top"].set_visible(False)
    for side in ("bottom", "left", "right"):
        ax.spines[side].set_color(INK2)
        ax.spines[side].set_linewidth(0.25)
    ax.grid(axis="x", color=GRID, linewidth=0.25)
    ax.set_axisbelow(True)
    for vals, color, off in zip(metric_values, colors, offsets):
        for j, name in enumerate(METRICS):
            v = vals[name]
            if np.isnan(v):
                continue
            ax.plot(v, j + off, "o", ms=5.5, mfc=color,
                    mec=_darken(color), mew=0.4, zorder=3, clip_on=False)


# ─── Panel c: similarity summaries ───────────────────────────────────────────


def draw_sim_panel(ax, stats_by_approach, colors, labels):
    """6 field groups x one row per approach: min-max line, mean+/-SD bar, mean ring, median tick."""
    n_groups = len(SIM_FIELDS)
    n_app = len(labels)
    offsets = np.linspace(-0.26, 0.26, n_app) if n_app > 1 else [0.0]
    ax.set_xlim(0, 1)
    ax.set_ylim(n_groups - 0.45, -0.55)
    ax.set_xticks([0, 0.25, 0.5, 0.75, 1.0])
    ax.set_xticklabels(["0", "0.25", "0.5", "0.75", "1"], size=7)
    ax.tick_params(axis="x", length=0, pad=3)
    ax.set_yticks(range(n_groups))
    ax.set_yticklabels(SIM_FIELDS.values(), size=8, color=INK2)
    ax.tick_params(axis="y", length=0, pad=4)
    for side in ("top", "right", "left"):
        ax.spines[side].set_visible(False)
    ax.spines["bottom"].set_linewidth(0.8)
    ax.grid(axis="x", color=GRID, linewidth=0.6)
    ax.set_axisbelow(True)
    for b in range(n_groups - 1):
        ax.axhline(b + 0.5, color=GRID, linewidth=0.6, xmax=1, zorder=0)
    unscored = []
    for a, (stats_by_field, color, label, off) in enumerate(
        zip(stats_by_approach, colors, labels, offsets)
    ):
        if stats_by_field is None:
            unscored.append(label)
            continue
        light = _lighten(color)
        for i, field in enumerate(SIM_FIELDS):
            st = stats_by_field.get(field)
            if st is None:
                continue
            y = i + off
            # thin min-max line, lightened tint
            ax.plot([st["min"], st["max"]], [y, y], color=light, lw=1.0,
                    solid_capstyle="round", zorder=1)
            # thicker mean +/- SD bar, full color, clipped to the [0, 1] domain
            if not np.isnan(st["std"]):
                lo = max(0.0, st["mean"] - st["std"])
                hi = min(1.0, st["mean"] + st["std"])
                ax.plot([lo, hi], [y, y], color=color, lw=4, solid_capstyle="round", zorder=2)
            # mean: open ring
            ax.plot(st["mean"], y, "o", ms=6, mfc=SURFACE, mec=color, mew=1.6, zorder=3)
            # median: black tick
            ax.plot(st["median"], y, "|", color=INK, ms=6.5, mew=1.3, zorder=4)
            ax.text(1.04, y, f"n={st['n']}", size=6.5, color=MUTED,
                    ha="left", va="center", clip_on=False)
    if unscored:
        ax.text(0.5, n_groups - 0.1, f"similarity not yet scored: {', '.join(unscored)}",
                ha="center", va="top", size=7, color=MUTED, style="italic")
    ax.set_xlabel("Semantic similarity (cross-encoder score)", size=8)


# ─── Figure assembly ─────────────────────────────────────────────────────────

PANEL_TOP = 0.805
PANEL_BOT = 0.115


def make_family_figure(family_key, cfg):
    approaches, dfs = [], []
    for key, label in cfg["approaches"].items():
        merged_dir = MERGED_DIRS.get(key)
        if merged_dir is None:
            print(f"  WARNING: no MERGED_DIRS entry for '{key}' — skipping approach '{label}'")
            continue
        path = os.path.join(merged_dir, f"merged_data_{key}.csv")
        if not os.path.exists(path):
            print(f"  WARNING: {path} not found — skipping approach '{label}'")
            continue
        approaches.append(label)
        dfs.append(pd.read_csv(path))
    if not dfs:
        print(f"  WARNING: no merged data for family '{family_key}' — skipping")
        return None

    colors = APPROACH_COLORS[: len(approaches)]

    fig = plt.figure(figsize=(18, 9.5))

    # Shared approach legend (bottom center, colors mean the same in every panel)
    handles = [Line2D([0], [0], marker="o", ls="none", ms=6, mfc=c,
                      mec=_darken(c), mew=0.6) for c in colors]
    fig.legend(handles, approaches, loc="lower center", bbox_to_anchor=(0.5, 0.02),
               ncol=len(approaches), frameon=False, fontsize=8.5,
               handletextpad=0.3, columnspacing=1.2)

    # Panel headers
    panel_header(fig, 0.055, 0.888, "a", "   Confusion mosaics",
                 "Area encodes each cell's share of n=88")
    panel_header(fig, 0.345, 0.888, "b", "   Classification performance",
                 "Dots compare the approaches within binary fields.")
    panel_header(fig, 0.756, 0.888, "c", "   Semantic similarity summaries",
                 "Min-max, mean ± SD, mean, and median are shown for each field and approach.")

    # Panel c: encoding key (generic swatches; color meaning comes from the approach legend above)
    sim_legend_handles = [
        Line2D([0], [0], color=MUTED, lw=1.0, solid_capstyle="round"),
        Line2D([0], [0], color=INK2, lw=4, solid_capstyle="round"),
        Line2D([0], [0], marker="o", ls="none", ms=6, mfc=SURFACE, mec=INK2, mew=1.6),
        Line2D([0], [0], marker="|", ls="none", ms=7, mew=1.3, color=INK),
    ]
    fig.legend(sim_legend_handles, ["Min-max", "Mean ± SD", "Mean", "Median"],
               loc="lower left", bbox_to_anchor=(0.752, 0.835), ncol=4, frameon=False,
               fontsize=7, handlelength=1.6, columnspacing=1.6, handletextpad=0.8)

    # Panel a: mosaic legend, column headers, 4 fields x N approaches
    cell_handles = [Patch(facecolor=MOSAIC_COLORS[k], edgecolor="none", label=k)
                    for k in ("TN", "FP", "FN", "TP")]
    fig.legend(cell_handles, ["TN", "FP", "FN", "TP"], loc="lower left",
               bbox_to_anchor=(0.05, 0.838), ncol=4, frameon=False, fontsize=7,
               handlelength=1.0, handleheight=1.0, columnspacing=1.0,
               handletextpad=1.0)
    mosaic_rows = grid_axes(fig, 0.075, 0.30, PANEL_BOT, PANEL_TOP,
                            nrows=len(BINARY_FIELDS), ncols=len(approaches),
                            wgap=0.012, hgap=0.045)
    for c, label in enumerate(approaches):
        pos = mosaic_rows[0][c].get_position()
        fig.text((pos.x0 + pos.x1) / 2, PANEL_TOP + 0.017, label,
                 ha="center", va="bottom", size=7.5, weight="bold", color=INK2)
    for r, (field, (_, wrapped)) in enumerate(BINARY_FIELDS.items()):
        pos = mosaic_rows[r][0].get_position()
        fig.text(0.070, (pos.y0 + pos.y1) / 2, wrapped, ha="right", va="center",
                 size=8, weight="bold", color=INK2)
        for c, df in enumerate(dfs):
            draw_mosaic(mosaic_rows[r][c], *binary_confusion(df, field))

    # Panel b: one sub-column per binary field
    perf_axes = grid_axes(fig, 0.38, 0.68, PANEL_BOT, PANEL_TOP,
                          nrows=1, ncols=len(BINARY_FIELDS), wgap=0.012, hgap=0)[0]
    offsets = np.linspace(-0.22, 0.22, len(approaches)) if len(approaches) > 1 else [0.0]
    for i, (field, (display, _)) in enumerate(BINARY_FIELDS.items()):
        ax = perf_axes[i]
        ax.set_title(display, size=8.5, weight="bold", color=INK, pad=8)
        draw_perf_column(ax, [binary_metrics(df, field) for df in dfs],
                         colors, offsets, first=(i == 0))
    fig.text(0.56, 0.075, "Performance (%)", ha="center", size=8, color=INK2)

    # Panel c: similarity summaries
    sim_ax = fig.add_axes([0.77, PANEL_BOT, 0.18, PANEL_TOP - PANEL_BOT])
    stats_by_approach = []
    for df in dfs:
        if not any(f"{f}_similarity" in df.columns for f in SIM_FIELDS):
            stats_by_approach.append(None)
        else:
            stats_by_approach.append({f: sim_stats(df, f) for f in SIM_FIELDS})
    draw_sim_panel(sim_ax, stats_by_approach, colors, approaches)

    out_dir = os.path.join(OUTPUT_DIR, family_key, f"{family_key}_figs")
    os.makedirs(out_dir, exist_ok=True)
    png_path = os.path.join(out_dir, f"{family_key}_model_comparison.png")
    eps_path = os.path.join(out_dir, f"{family_key}_model_comparison.eps")
    fig.savefig(png_path, dpi=200)
    fig.savefig(eps_path)
    plt.close(fig)
    return png_path, eps_path


# ─── Main ────────────────────────────────────────────────────────────────────

if __name__ == "__main__":
    for family_key, cfg in FAMILIES.items():
        print(f"Building composite for {cfg['display']} ...")
        result = make_family_figure(family_key, cfg)
        if result:
            png_path, eps_path = result
            print(f"  saved {png_path}")
            print(f"  saved {eps_path}")
