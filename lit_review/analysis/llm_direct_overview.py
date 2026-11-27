"""
Overview for the direct LLM classifier (llm_direct_classifier.py: Qwen3-32B
reads the taxonomy JSONs and picks a category per entry in one step), laid
out like classifier_overview.py so it can be set beside classifier/8b/.

Same input as 8b/: the full-corpus extraction runs (claude included), rainfall and
endogenous columns only, cleaned and split into entries by
sankey_iv_clustering.expand_column.

Writes to <OneDrive>/weather_iv_lit/analysis/classifier/32b_direct/:
  README.md
  entries_rainfall.csv, entries_endogenous.csv  one row per unique entry
  summary.csv            category shares (occurrence-weighted) per side, LLM vs 8b pipeline
  sankeys/               one Sankey per run (+ details/)

Steps (from lit_review/), default all:
  DYLD_FALLBACK_LIBRARY_PATH=/opt/homebrew/lib python3 analysis/llm_direct_overview.py [classify] [tables] [sankeys]
"""

import json
import os
import subprocess
import sys

import pandas as pd

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import classifier_overview as co
import fixed_label_classifier as flc
import sankey_iv_clustering as sic
from sankey_taxonomy import OTHER, UNCLASSIFIABLE, other_label, unclassifiable_label

MLX_PYTHON = os.path.expanduser("~/venvs/mlx/bin/python")
MODEL = os.environ.get("LLM_DIRECT_MODEL", "mlx-community/Qwen3-32B-4bit")
CACHE = os.path.join(HERE, ".llm_direct_cache.json")
ENTRIES_JSON = os.path.join(HERE, ".llm_direct_entries.json")
CLASSIFIER_ROOT = os.path.dirname(co.OUT_DIR)
OUT_DIR = os.path.join(CLASSIFIER_ROOT, "32b_direct")
PIPELINE_DIR = os.path.join(CLASSIFIER_ROOT, "8b")
RUNS = co.RUNS


def export(occ) -> None:
    with open(ENTRIES_JSON, "w", encoding="utf-8") as f:
        json.dump({side: sorted(occ[side]) for side in occ}, f, ensure_ascii=False)


def classify() -> None:
    subprocess.run([MLX_PYTHON, os.path.join(HERE, "llm_direct_classifier.py"),
                    "--entries", ENTRIES_JSON, "--cache", CACHE, "--model", MODEL], check=True)


def results(side: str) -> dict:
    """{entry: result} for the current taxonomy/prompt namespace of this side (newest wins)."""
    with open(CACHE, encoding="utf-8") as f:
        db = json.load(f)
    out = {}
    for ns, block in db.items():
        if block["side"] == side and block["model"] == MODEL:
            out = block["results"]  # namespaces are appended in order; last = current prompt
    return out


def side_label(cat: str, side: str) -> str:
    return {OTHER: other_label(side), UNCLASSIFIABLE: unclassifiable_label(side)}.get(cat, cat)


def rule_for(entry: str, side: str) -> str:
    """Same bare-rainfall rule as the 8b pipeline (fixed_label_classifier.BARE_RAINFALL): vague names like
    "rainfall" / "precipitation" / "rainfall squared" are Unclassifiable whatever the LLM said."""
    return flc.bare_rainfall_rule(entry) if side == "Rainfall Metrics" else ""


def final_label(entry: str, r: dict, side: str) -> str:
    if rule_for(entry, side) or not r["category"]:
        return unclassifiable_label(side)
    return side_label(r["category"], side)


def labels(side: str) -> dict[str, str]:
    return {e: final_label(e, r, side) for e, r in results(side).items()}


def write_tables(occ) -> None:
    summary = []
    for side, _, _ in co.ect.SIDES:
        res = results(side)
        entries = sorted(occ[side])
        missing = [e for e in entries if e not in res]
        if missing:
            raise SystemExit(f"{side}: {len(missing)} entries not classified yet; run the classify step")
        pipe_path = os.path.join(PIPELINE_DIR, co.SIDE_FILES[side])
        pipe = pd.read_csv(pipe_path).set_index("entry")["category"] if os.path.exists(pipe_path) else pd.Series()
        df = pd.DataFrame({
            "entry": entries,
            "category": [final_label(e, res[e], side) for e in entries],
            "32b_category": [side_label(res[e]["category"], side) for e in entries],
            "8b_category": [pipe.get(e, "") for e in entries],
            "rule": [rule_for(e, side) for e in entries],
            "category_prob": [res[e]["category_prob"] for e in entries],
            "runner_up": [side_label(res[e]["runner_up"], side) for e in entries],
            "reason": [res[e]["reason"] for e in entries],
            "n_occurrences": [sum(occ[side][e].values()) for e in entries],
            "runs": ["; ".join(f"{r}:{n}" for r, n in sorted(occ[side][e].items(), key=lambda x: -x[1]))
                     for e in entries],
        })
        df["agrees_with_8b"] = df["category"] == df["8b_category"]
        df = df.sort_values(["n_occurrences", "entry"], ascending=[False, True])
        df.to_csv(os.path.join(OUT_DIR, co.SIDE_FILES[side]), index=False)

        w = df["n_occurrences"]
        for col, who in (("category", "32b_direct"), ("8b_category", "8b_pipeline")):
            share = w.groupby(df[col]).sum() / w.sum()
            n = df.groupby(col).size()
            for cat in share.index:
                summary.append({"side": side, "classifier": who, "category": cat,
                                "unique_entries": int(n[cat]), "share_of_occurrences": round(share[cat], 4)})
        agree = (df["agrees_with_8b"] * w).sum() / w.sum()
        print(f"  {side}: {len(df)} entries -> {co.SIDE_FILES[side]}; agreement with 8b: "
              f"{df['agrees_with_8b'].mean():.0%} of entries, {agree:.0%} of occurrences")
    s = pd.DataFrame(summary).pivot_table(index=["side", "category"], columns="classifier",
                                          values=["share_of_occurrences", "unique_entries"], fill_value=0)
    s.columns = [f"{b}_{a}" for a, b in s.columns]
    s.sort_values(["side", "32b_direct_share_of_occurrences"], ascending=[True, False]).to_csv(
        os.path.join(OUT_DIR, "summary.csv"))


def run_sankeys() -> None:
    """Reuse classifier_overview's Sankey loop with the classifier swapped for the cached LLM labels."""
    lab = {side: labels(side) for side, _, _ in co.ect.SIDES}

    def lookup(unique_entries, side_name, *a, **k):
        m = {e: lab[side_name].get(e, unclassifiable_label(side_name)) for e in unique_entries}
        audit = pd.DataFrame({"side": side_name, "entry": list(m), "label": list(m.values())})
        return m, audit

    sic.fixed_label_classifier.classify = lookup
    # co.run_sankeys removes each EPS just before rewriting it (OneDrive "dataless" placeholder issue).
    co.OUT_DIR, co.BACKBONE, co.GATE = OUT_DIR, "qwen3-32b-direct", "none"
    co.run_sankeys()


README = f"""# Direct LLM classifier: Qwen3-32B, full-corpus runs

Generated by `analysis/llm_direct_classifier.py` + `analysis/llm_direct_overview.py`.
Runs: {", ".join(RUNS)}. Same unique entries as `../8b/`.

## Method
One step per unique entry. Qwen3-32B (4-bit MLX, run locally, thinking off, greedy) gets the entire taxonomy JSON
(guidance note, every category's description, examples and JEL anchors, Other and Unclassifiable included) and
the entry name, and answers with a short reason, a category and a runner-up. No embedding, reranker, gate or
rule lists. The taxonomy is `analysis/taxonomies/*.json`.

One rule overrides the LLM, the same one the 8b pipeline uses: on the rainfall side, bare names with no
construction ("rainfall", "precipitation", "rainfall squared", "rainfall (mm)", ...; list in
`fixed_label_classifier.BARE_RAINFALL`) are Unclassifiable. Logged, lagged, dummy and period-specific rainfall
are kept. (The taxonomy note says such names default to Total rainfall; this rule deliberately departs from it.)
The LLM's own answer is in `32b_category`; `rule` says when the override fired.

## Entry files
| Column | Meaning |
|---|---|
| entry | Cleaned entry as extracted |
| category | Final category (Other / Unclassifiable carry the side suffix, as in 8b/) |
| 32b_category | Qwen3-32B's own choice, before the bare-rainfall rule |
| 8b_category | Final label from the 8b pipeline (`../8b/`) |
| rule | "bare rainfall" when the rule overrode the LLM, else blank |
| category_prob | Model's probability of the category it wrote (product of its token probabilities); low = close call |
| runner_up | Next most plausible category, per the model |
| reason | The model's one-sentence justification |
| n_occurrences, runs | As in 8b/ |
| agrees_with_8b | category == 8b_category |

`summary.csv`: unique entries and occurrence shares per category, both classifiers side by side.

## Sankeys
`sankeys/sankey_full_<run>.png` (+ `_wide.png`): Other shown, Unclassifiable excluded (share in
`sankeys/details/residual_shares_full_<run>.csv`).
"""


def main():
    steps = sys.argv[1:] or ["classify", "tables", "sankeys"]
    os.makedirs(OUT_DIR, exist_ok=True)
    with open(os.path.join(OUT_DIR, "README.md"), "w", encoding="utf-8") as f:
        f.write(README)
    occ = co.occurrences()
    export(occ)
    if "classify" in steps:
        classify()
    if "tables" in steps:
        write_tables(occ)
    if "sankeys" in steps:
        run_sankeys()
    print(f"\nOutputs -> {OUT_DIR}")


if __name__ == "__main__":
    main()
