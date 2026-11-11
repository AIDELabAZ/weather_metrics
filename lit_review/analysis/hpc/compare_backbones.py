"""
Run LOCALLY after merge_cache.py. Compares classifier backbones on the entries
in classifier_entries.json, read straight from the local cache (no models
loaded):
  - share of unique entries labelled Other, per side and backbone
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


def main():
    backbones = sys.argv[1:] or ["qwen3-0.6b", "qwen3-4b", "qwen3-8b"]
    with open(os.path.join(HERE, "classifier_entries.json"), encoding="utf-8") as f:
        entries = json.load(f)
    cache = flc._load_cache()

    for side, side_entries in entries.items():
        other = f"Other ({side})"
        _, docs = flc._label_docs(side, other)
        df = pd.DataFrame({"entry": side_entries})
        for b in backbones:
            ns = cache.get(flc._cache_namespace(b, side, docs), {})
            df[b] = df["entry"].map(lambda e: ns.get(e, {}).get("top1"))

        print(f"\n=== {side} ({len(df)} unique entries) ===")
        for b in backbones:
            have = df[b].notna()
            n_other = (df.loc[have, b] == other).sum()
            print(f"  {b:12s} labelled {have.sum():4d}/{len(df)}   Other: {n_other:4d} "
                  f"({n_other / max(have.sum(), 1):.0%})")
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
