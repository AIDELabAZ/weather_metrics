"""
Run LOCALLY after merge_cache.py. Compares classifier backbones on the entries
in classifier_entries.json (from the local cache; models load only for
entries not yet scored):
  - share of unique entries labelled Other / Unclassifiable, per side and backbone
  - pairwise agreement (% same label) between backbones
  - entries whose label differs between backbones, written to
    backbone_comparison_<side>.csv for review

Usage: python3 analysis/hpc/compare_backbones.py [backbone ...]
       (default: qwen3-0.6b qwen3-4b qwen3-8b)
"""

import itertools
import json
import os
import sys

import pandas as pd

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(HERE))
import fixed_label_classifier as flc
from sankey_taxonomy import other_label, unclassifiable_label


def main():
    backbones = sys.argv[1:] or ["qwen3-0.6b", "qwen3-4b", "qwen3-8b"]
    with open(os.path.join(HERE, "classifier_entries.json"), encoding="utf-8") as f:
        entries = json.load(f)

    for side, side_entries in entries.items():
        other, unclassifiable = other_label(side), unclassifiable_label(side)
        df = pd.DataFrame({"entry": side_entries})
        for b in backbones:
            # Scores any entry missing from the cache (loads the models).
            mapping, _ = flc.classify(side_entries, side, backbone=b)
            df[b] = df["entry"].map(mapping)

        print(f"\n=== {side} ({len(df)} unique entries) ===")
        for b in backbones:
            have = df[b].notna()
            n = max(have.sum(), 1)
            n_other = (df.loc[have, b] == other).sum()
            n_uncl = (df.loc[have, b] == unclassifiable).sum()
            print(f"  {b:12s} labelled {have.sum():4d}/{len(df)}   Other: {n_other:4d} ({n_other / n:.0%})"
                  f"   Unclassifiable: {n_uncl:4d} ({n_uncl / n:.0%})")
        for a, b in itertools.combinations(backbones, 2):
            both = df[a].notna() & df[b].notna()
            agree = (df.loc[both, a] == df.loc[both, b]).mean() if both.any() else float("nan")
            print(f"  agreement {a} vs {b}: {agree:.0%} (n={both.sum()})")

        differs = df[df[backbones].nunique(axis=1, dropna=False) > 1]
        out = os.path.join(HERE, f"backbone_comparison_{side.split()[0].lower()}.csv")
        differs.to_csv(out, index=False)
        print(f"  {len(differs)} entries with differing labels -> {out}")


if __name__ == "__main__":
    main()
