"""
Score the six classifier implementations against the hand-labelled subset of
placements_by_iteration_with-human-valid.csv.

Adds to that CSV (in place):
  human_category      the human label mapped onto the taxonomy's exact category name
  match_<impl>        1 if <impl> placed the entry in human_category, else 0
                      (blank for rows without a human label)

An entry the context arms placed differently in different papers
("A (2 papers); B (1 papers)") is scored on its most common placement; a tie
for most common scores 0.

Writes to classifier/human_validation/:
  accuracy_summary.csv                       share correct per side x implementation
  confusion_<side>_<impl>.csv                rows = human category, columns = model category
  confusion_<side>.png / .pdf                the six matrices for one side

Usage (from lit_review/):  /opt/anaconda3/bin/python3 analysis/human_validation.py
"""

import difflib
import io
import json
import os
import re
import time

import matplotlib.pyplot as plt
import numpy as np
import pandas as pd

BASE = "/Users/kieran/Library/CloudStorage/OneDrive-UniversityofArizona/weather_iv_lit/analysis/classifier"
CSV = os.path.join(BASE, "placements_by_iteration_with-human-valid.csv")
OUT = os.path.join(BASE, "human_validation")
IMPLS = ["8b_pipeline", "32b_direct", "32b_solo", "32b_pipeline", "32b_solo_context", "32b_pipeline_context"]
TAXONOMIES = os.path.join(os.path.dirname(os.path.abspath(__file__)), "taxonomies")
TAXONOMY_FILES = {"Rainfall Metrics": "rainfall_measures_taxonomy.json",
                  "Endogenous Variables": "economic_concepts_taxonomy.json"}
SIDE_SLUG = {"Rainfall Metrics": "rainfall", "Endogenous Variables": "endogenous"}
_MULTI = re.compile(r"^(.*) \((\d+) papers\)$")


def key(label: str) -> str:
    s = label.lower().replace("&", " and ").replace(",", " ")
    s = re.sub(r"\((rainfall metrics|endogenous variables)\)", "", s)
    return " ".join(s.split())


def plurality(cell: str) -> str | None:
    """Model label for a cell; mixed placements -> most common, tie -> None."""
    parts = [_MULTI.match(p.strip()) for p in cell.split(";")]
    if len(parts) == 1 and parts[0] is None:
        return cell
    counts = sorted(((int(m.group(2)), m.group(1)) for m in parts), reverse=True)
    return None if len(counts) > 1 and counts[0][0] == counts[1][0] else counts[0][1]


def canonical_human(df: pd.DataFrame) -> pd.Series:
    out = pd.Series(np.nan, index=df.index, dtype=object)
    for side, g in df.groupby("side"):
        cats = {plurality(c) for col in IMPLS for c in g[col] if ";" not in c} - {None}
        tax = json.load(open(os.path.join(TAXONOMIES, TAXONOMY_FILES[side])))["categories"]
        cats |= {c["category"] for c in tax if c["category"] not in ("Other", "Unclassifiable")}
        cats |= {f"Other ({side})", f"Unclassifiable ({side})"}
        by_key = {key(c): c for c in cats}
        for i, h in g["human_label"].dropna().items():
            k = key(h)
            hit = by_key.get(k) or next(iter(difflib.get_close_matches(k, by_key, n=1, cutoff=0.85)), None)
            if hit is None:
                raise ValueError(f"Can't map human label {h!r} ({side})")
            if key(hit) != k:
                print(f"  fuzzy: {h!r} -> {hit!r}")
            out[i] = by_key[key(hit)]
    return out


_MINOR = {"a", "an", "the", "and", "or", "nor", "but", "of", "in", "on", "at", "to", "for", "by", "from", "with",
          "as", "per", "vs", "via"}
RENAMES = {"Infrastructure, transport & urban/spatial development": "Infrastructure, transport, & spatial development",
           "Social capital, networks, norms & attitudes": "Social capital, networks, & norms"}


def display(label: str) -> str:
    """Figure style: renames, Oxford comma, title case, side suffix dropped."""
    s = RENAMES.get(label, re.sub(r" \((Rainfall Metrics|Endogenous Variables)\)$", "", label))
    if "," in s:
        s = re.sub(r"(?<!,) & ", ", & ", s)
    words = s.split(" ")
    return " ".join(w if (w.lower() in _MINOR and i) else "-".join(
        "/".join(q[:1].upper() + q[1:] for q in p.split("/")) for p in w.split("-")) for i, w in enumerate(words))


def plot_side(side: str, mats: dict[str, pd.DataFrame], acc: dict[str, float], n: int) -> None:
    rows_, cols_ = list(next(iter(mats.values())).index), list(next(iter(mats.values())).columns)
    k, kc = len(rows_), len(cols_)
    cell = 0.32
    fig, axes = plt.subplots(2, 3, figsize=(3 * kc * cell + 4.5, 2 * k * cell + 4.5), sharex=True, sharey=True)
    vmax = max(m.values.max() for m in mats.values())
    for ax, impl in zip(axes.ravel(), IMPLS):
        m = mats[impl].values
        ax.imshow(m, cmap="Blues", vmin=0, vmax=vmax, aspect="equal")
        for r in range(k):
            for c in range(kc):
                if m[r, c]:
                    ax.text(c, r, int(m[r, c]), ha="center", va="center", fontsize=7,
                            color="white" if m[r, c] > vmax * 0.55 else "#1f2937")
        ax.set_title(f"{impl.replace('_', ' ').title()} ({acc[impl]:.0%} Correct)", fontsize=9)
        ax.set_xticks(range(kc), [display(l) for l in cols_], rotation=90, fontsize=7)
        ax.set_yticks(range(k), [display(l) for l in rows_], fontsize=7)
        ax.tick_params(length=0)
        for s in ax.spines.values():
            s.set_visible(False)
        ax.set_xticks(np.arange(kc + 1) - 0.5, minor=True)
        ax.set_yticks(np.arange(k + 1) - 0.5, minor=True)
        ax.grid(which="minor", color="#e5e7eb", linewidth=0.5)
        ax.tick_params(which="minor", length=0)
    fig.supxlabel("Model Category", fontsize=9)
    fig.supylabel("Human Category", fontsize=9)
    fig.suptitle(f"{side}: Human vs. Model Classification (n = {n})", fontsize=11)
    fig.tight_layout(rect=(0, 0, 1, 0.975))
    for ext in ("png", "pdf"):
        buf = io.BytesIO()  # render in memory: OneDrive can break matplotlib's streamed file writes
        fig.savefig(buf, format=ext, dpi=200, bbox_inches="tight", pad_inches=0.05)
        path = os.path.join(OUT, f"confusion_{SIDE_SLUG[side]}.{ext}")
        for attempt in range(5):
            try:
                with open(path, "wb") as f:
                    f.write(buf.getvalue())
                break
            except OSError:
                if attempt == 4:
                    raise
                time.sleep(3)
    plt.close(fig)


def main():
    df = pd.read_csv(CSV)
    df = df.drop(columns=[c for c in df.columns if c.startswith("match_") or c == "human_category"])
    df.insert(df.columns.get_loc("human_label") + 1, "human_category", canonical_human(df))
    labelled = df["human_category"].notna()
    for impl in IMPLS:
        pred = df[impl].map(plurality)
        df[f"match_{impl}"] = pd.Series(pd.NA, index=df.index, dtype="Int64")
        df.loc[labelled, f"match_{impl}"] = (pred[labelled] == df.loc[labelled, "human_category"]).astype(int)
    df.to_csv(CSV, index=False)
    print(f"Updated {CSV}: {labelled.sum()} labelled rows")

    os.makedirs(OUT, exist_ok=True)
    rows = []
    for side, g in df[labelled].groupby("side"):
        preds = {impl: g[impl].map(plurality).fillna("Tie (no single placement)") for impl in IMPLS}
        labels = sorted(set(g["human_category"]).union(*map(set, preds.values())),
                        key=lambda l: (l.startswith(("Other", "Unclassifiable", "Tie")), l))
        mats, acc = {}, {}
        for impl in IMPLS:
            m = pd.crosstab(g["human_category"], preds[impl]).reindex(
                index=[l for l in labels if not l.startswith("Tie")], columns=labels, fill_value=0)
            m.index.name, m.columns.name = "human_category", "model_category"
            m.to_csv(os.path.join(OUT, f"confusion_{SIDE_SLUG[side]}_{impl}.csv"))
            mats[impl], acc[impl] = m, g[f"match_{impl}"].mean()
            rows.append({"side": side, "implementation": impl, "n_labelled": len(g),
                         "n_correct": int(g[f"match_{impl}"].sum()), "accuracy": round(acc[impl], 3)})
        plot_side(side, mats, acc, len(g))
    summary = pd.DataFrame(rows)
    summary.to_csv(os.path.join(OUT, "accuracy_summary.csv"), index=False)
    print(summary.pivot(index="implementation", columns="side", values="accuracy").loc[IMPLS].to_string())
    metrics, outcomes = performance_tables(df[labelled])
    metrics.to_csv(os.path.join(OUT, "performance_metrics.csv"), index=False)
    outcomes.to_csv(os.path.join(OUT, "outcome_counts.csv"), index=False)
    draw_performance(metrics, outcomes, df[labelled]["side"].value_counts().to_dict())
    print(metrics.round(3).to_string(index=False))
    print(f"Outputs -> {OUT}; figure -> {FIG_DIR}")


# ─── Performance figure (style of the paper's model-comparison figure) ──────
FIG_DIR = "/Users/kieran/Library/CloudStorage/OneDrive-UniversityofArizona/weather_iv_lit/writing/figures"
IMPL_LABELS = {"8b_pipeline": "8B Pipeline", "32b_direct": "32B Direct", "32b_solo": "32B Solo",
               "32b_pipeline": "32B Pipeline", "32b_solo_context": "32B Solo + Context",
               "32b_pipeline_context": "32B Pipeline + Context"}
# dataviz reference categorical palette, slots 1-6 in order (blue, orange, aqua, yellow, magenta, green)
IMPL_COLORS = ["#2a78d6", "#eb6834", "#1baf7a", "#eda100", "#e87ba4", "#008300"]
PERF_METRICS = ["Accuracy", "Balanced Accuracy", "Macro Precision", "Macro F1", "Cohen's Kappa"]
OUTCOMES = {"Correct": "#57A773", "Wrong Category": "#e34948",
            "Category Sent to Other/Unclassifiable": "#eda100",
            "Other/Unclassifiable Given a Category": "#08B2E3"}
SIDE_TITLES = {"Rainfall Metrics": "Rainfall Metrics", "Endogenous Variables": "Endogenous Variables"}


def _residual(label: str) -> bool:
    return label.startswith(("Other", "Unclassifiable"))


def performance_tables(lab: pd.DataFrame):
    from sklearn.metrics import cohen_kappa_score, f1_score, precision_score
    mrows, orows = [], []
    for side, g in lab.groupby("side"):
        y = g["human_category"]
        cats = sorted(set(y))
        for impl in IMPLS:
            p = g[impl].map(plurality).fillna("Tie")
            mrows.append({"side": side, "implementation": impl, "n": len(g),
                          "Accuracy": (p == y).mean(),
                          # mean recall over the human categories
                          "Balanced Accuracy": np.mean([(p[y == c] == c).mean() for c in cats]),
                          "Macro Precision": precision_score(y, p, labels=cats, average="macro", zero_division=0),
                          "Macro F1": f1_score(y, p, labels=cats, average="macro", zero_division=0),
                          "Cohen's Kappa": cohen_kappa_score(y, p)})
            res_h, res_p = y.map(_residual), p.map(_residual)
            wrong = p != y
            orows.append({"side": side, "implementation": impl,
                          "Correct": int((~wrong).sum()),
                          "Wrong Category": int((wrong & (res_h == res_p)).sum()),
                          "Category Sent to Other/Unclassifiable": int((wrong & ~res_h & res_p).sum()),
                          "Other/Unclassifiable Given a Category": int((wrong & res_h & ~res_p).sum())})
    return pd.DataFrame(mrows), pd.DataFrame(orows)


def draw_performance(metrics: pd.DataFrame, outcomes: pd.DataFrame, n_by_side: dict) -> None:
    from matplotlib.lines import Line2D
    from matplotlib.patches import Patch
    import model_comparison_figs as mcf

    INK, INK2, MUTED, GRID = mcf.INK, mcf.INK2, mcf.MUTED, mcf.GRID
    sides = list(SIDE_TITLES)
    fig = plt.figure(figsize=(15, 7.6))
    top, bot = 0.79, 0.13

    def header(x, letter, title, sub):
        fig.text(x, 0.92, letter, size=10.5, weight="bold", color=INK)
        fig.text(x + 0.016, 0.92, title, size=10.5, weight="bold", color=INK)
        fig.text(x, 0.893, sub, size=7.5, color=MUTED)

    # a. outcome bars: one stacked bar per implementation, one block per side
    header(0.03, "a", "Classification Outcomes", "Share of hand-labeled entries; counts in segments")
    fig.legend([Patch(facecolor=c, edgecolor="none") for c in OUTCOMES.values()], list(OUTCOMES),
               loc="lower left", bbox_to_anchor=(0.025, 0.815), ncol=2, frameon=False, fontsize=7,
               handlelength=1.0, handleheight=1.0, columnspacing=1.2)
    gap = 0.07
    h = (top - bot - gap) / 2
    for s_i, side in enumerate(sides):
        ax = fig.add_axes([0.15, top - (s_i + 1) * h - s_i * gap, 0.26, h])
        o = outcomes[outcomes.side == side].set_index("implementation").loc[IMPLS]
        n = n_by_side[side]
        for i, impl in enumerate(IMPLS):
            left = 0
            for name, color in OUTCOMES.items():
                v = o.loc[impl, name]
                w = v / n
                if v:
                    ax.barh(i, w, left=left, height=0.72, color=color, edgecolor="white", linewidth=1.2)
                    if w > 0.045:
                        ax.text(left + w / 2, i, str(v), ha="center", va="center", size=7, weight="bold",
                                color=INK)
                left += w
        ax.set_xlim(0, 1)
        ax.set_ylim(len(IMPLS) - 0.4, -0.6)
        ax.set_yticks(range(len(IMPLS)), [IMPL_LABELS[i] for i in IMPLS], size=8, color=INK2)
        ax.set_xticks([0, 0.25, 0.5, 0.75, 1], ["0", "25", "50", "75", "100"], size=7)
        ax.tick_params(length=0)
        for sp in ax.spines.values():
            sp.set_visible(False)
        ax.set_title(f"{SIDE_TITLES[side]} (n = {n})", size=8.5, weight="bold", color=INK, loc="left", pad=6)
        if s_i == 1:
            ax.set_xlabel("Share of Entries (%)", size=8, color=INK2)

    # b. metric dot plot: one column per side, one row per metric, one dot per implementation
    header(0.49, "b", "Classification Performance", "Dots compare the implementations within each side; "
           "macro scores average over the human categories")
    offsets = np.linspace(-0.27, 0.27, len(IMPLS))
    width = 0.2
    for s_i, side in enumerate(sides):
        ax = fig.add_axes([0.62 + s_i * (width + 0.015), bot, width, top - bot])
        m = metrics[metrics.side == side].set_index("implementation")
        ax.set_xlim(0, 100)
        ax.set_ylim(len(PERF_METRICS) - 0.5, -0.5)
        ax.set_xticks([0, 25, 50, 75, 100])
        ax.tick_params(axis="x", labelsize=7, length=0, pad=3)
        ax.set_yticks(range(len(PERF_METRICS)))
        ax.set_yticklabels(PERF_METRICS if s_i == 0 else [], size=8, color=INK2)
        ax.tick_params(axis="y", length=0, pad=4)
        ax.spines["top"].set_visible(False)
        for sp in ("bottom", "left", "right"):
            ax.spines[sp].set_color(INK2)
            ax.spines[sp].set_linewidth(0.25)
        ax.grid(axis="x", color=GRID, linewidth=0.25)
        ax.set_axisbelow(True)
        for j in range(len(PERF_METRICS) - 1):
            ax.axhline(j + 0.5, color=GRID, linewidth=0.5)
        for impl, color, off in zip(IMPLS, IMPL_COLORS, offsets):
            for j, name in enumerate(PERF_METRICS):
                ax.plot(m.loc[impl, name] * 100, j + off, "o", ms=5.5, mfc=color, mec=mcf._darken(color),
                        mew=0.4, zorder=3, clip_on=False)
        ax.set_title(f"{SIDE_TITLES[side]} (n = {n_by_side[side]})", size=8.5, weight="bold", color=INK, pad=8)
    fig.text(0.62 + width + 0.0075, bot - 0.06, "Performance (%)", ha="center", size=8, color=INK2)

    fig.legend([Line2D([0], [0], marker="o", ls="none", ms=6, mfc=c, mec=mcf._darken(c), mew=0.6)
                for c in IMPL_COLORS], [IMPL_LABELS[i] for i in IMPLS], loc="lower center",
               bbox_to_anchor=(0.5, 0.0), ncol=len(IMPLS), frameon=False, fontsize=8.5,
               handletextpad=0.3, columnspacing=1.4)
    for ext, kw in (("png", {"dpi": 250}), ("pdf", {})):
        buf = io.BytesIO()
        fig.savefig(buf, format=ext, bbox_inches="tight", pad_inches=0.05, **kw)
        with open(os.path.join(FIG_DIR, f"classifier_validation_metrics.{ext}"), "wb") as f:
            f.write(buf.getvalue())
    plt.close(fig)


if __name__ == "__main__":
    main()
