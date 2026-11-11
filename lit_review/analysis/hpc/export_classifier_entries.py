"""
Run LOCALLY (needs the OneDrive output CSVs). Collects every unique cleaned
entry that the Sankey drivers would send to fixed_label_classifier.classify(),
for both the full-corpus (sankey_full_corpus_baselines.py) and 88-paper test
set (sankey_frontier_baselines.py) baselines, and writes them to
analysis/hpc/classifier_entries.json:

    {"Rainfall Metrics": [...], "Endogenous Variables": [...]}

That file is the only data the HPC job needs. The cleaning is the same
expand_column() that process_side() uses, so the entries match the cache keys
exactly.

Run with: python3 analysis/hpc/export_classifier_entries.py
"""

import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(HERE))
import sankey_frontier_baselines as frontier
import sankey_full_corpus_baselines as full
import sankey_iv_clustering as sic

OUT_PATH = os.path.join(HERE, "classifier_entries.json")

# (side_name, column, requires_rainfall) — mirrors the process_side() calls in sic.main()
SIDES = [
    ("Rainfall Metrics", "Rainfall Instrument", True),
    ("Endogenous Variables", "Endogenous Variable(s)", False),
]


def main():
    entries = {side: set() for side, _, _ in SIDES}
    runs = [(full, k, d) for k, d in full.BASELINES.items()] + \
           [(frontier, k, d) for k, d in frontier.BASELINES.items()]
    for driver, key, subdir in runs:
        driver.set_paths(key, subdir)
        if not os.path.exists(sic.MERGED_CSV):
            print(f"  skip (missing): {sic.MERGED_CSV}")
            continue
        rain_df_raw = sic.load_rainfall_papers(sic.MERGED_CSV)
        for side, col, requires_rainfall in SIDES:
            exp, _ = sic.expand_column(rain_df_raw, col, requires_rainfall=requires_rainfall)
            if len(exp):
                entries[side].update(exp["entry"].unique())
        print(f"  {os.path.basename(sic.MERGED_CSV)}: "
              + ", ".join(f"{s}={len(e)}" for s, e in entries.items()) + " (cumulative)")

    with open(OUT_PATH, "w", encoding="utf-8") as f:
        json.dump({s: sorted(e) for s, e in entries.items()}, f, indent=1)
    print(f"\nWrote {OUT_PATH}")


if __name__ == "__main__":
    main()
