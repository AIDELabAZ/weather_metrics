"""
Run ON HPC (GPU node). Scores every entry in classifier_entries.json with the
fixed-label classifier for each requested backbone, writing results to the
cache file named by $SANKEY_CLASSIFIER_CACHE (set in classify.slurm).

Needs only analysis/fixed_label_classifier.py, analysis/sankey_taxonomy.py and
this folder — no OneDrive data, OpenAI key, plotly or cairo. Results are keyed
exactly as on the Mac, so after merge_cache.py the local Sankey drivers
read them from cache and never load the models.

Usage: python classify_on_hpc.py [backbone ...]      (default: qwen3-0.6b qwen3-4b qwen3-8b)
"""

import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(HERE))
import fixed_label_classifier as flc

ENTRIES_PATH = os.path.join(HERE, "classifier_entries.json")


def main():
    # 0.6b is included only to fill entries missing from the local 0.6b cache
    # (merge_cache.py never overwrites existing local labels), so all three
    # backbones are compared on the same entries.
    backbones = sys.argv[1:] or ["qwen3-0.6b", "qwen3-4b", "qwen3-8b"]
    with open(ENTRIES_PATH, encoding="utf-8") as f:
        entries = json.load(f)

    print(f"device={flc.DEVICE} dtype={flc.DTYPE} cache={flc.CACHE_PATH}")
    for backbone in backbones:
        for side_name, side_entries in entries.items():
            print(f"\n[{backbone}] {side_name}: {len(side_entries)} entries")
            mapping, _ = flc.classify(side_entries, side_name, f"Other ({side_name})", backbone=backbone)
            n_other = sum(v.startswith("Other (") for v in mapping.values())
            print(f"  -> Other: {n_other}/{len(mapping)} ({n_other / max(len(mapping), 1):.0%})")


if __name__ == "__main__":
    main()
