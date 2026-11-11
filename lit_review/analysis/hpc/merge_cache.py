"""
Run LOCALLY after copying the HPC cache back. Merges its namespaces/entries
into analysis/.sankey_fixed_label_cache.json (existing local entries are kept;
HPC entries only add to them).

Usage: python3 analysis/hpc/merge_cache.py analysis/hpc/hpc_cache.json
"""

import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
LOCAL = os.path.join(os.path.dirname(HERE), ".sankey_fixed_label_cache.json")


def main():
    with open(sys.argv[1], encoding="utf-8") as f:
        incoming = json.load(f)
    local = {}
    if os.path.exists(LOCAL):
        with open(LOCAL, encoding="utf-8") as f:
            local = json.load(f)
    added = 0
    for ns, entries in incoming.items():
        dest = local.setdefault(ns, {})
        for entry, result in entries.items():
            if entry not in dest:
                dest[entry] = result
                added += 1
    with open(LOCAL, "w", encoding="utf-8") as f:
        json.dump(local, f)
    print(f"Merged {added} new entries from {len(incoming)} namespace(s) into {LOCAL}")


if __name__ == "__main__":
    main()
