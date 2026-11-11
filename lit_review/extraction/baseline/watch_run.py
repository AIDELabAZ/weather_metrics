"""
watch_run.py

Live feed of a running baseline extraction: follows the run's log and prints
one compact block per finished paper (progress count, key answers, failures).

Usage: python3 watch_run.py <log file> [total papers]
  e.g. python3 watch_run.py ../../logs/full_baseline_sol.log 3755
Ctrl-C to stop watching; the run itself keeps going.
"""

import ast
import os
import sys
import time

FIELDS = [
    ("Empirical", "Empirical Analysis"),
    ("Dep var", "Dependent Variable(s)"),
    ("Endog", "Endogeneity Problem"),
    ("Endog var", "Endogenous Variable(s)"),
    ("IV", "Instrumental Variable Used"),
    ("IVs", "Instrumental Variable(s)"),
    ("Rain IV", "Instrumental Variable Rainfall"),
    ("Rain inst", "Rainfall Instrument"),
]
PREFIX = "Final extracted info for "


def follow(path):
    """Yield (line, caught_up): caught_up turns True once the existing log has
    been replayed, so only papers finishing after that are timed."""
    caught_up = False
    with open(path, encoding="utf-8", errors="replace") as f:
        while True:
            line = f.readline()
            if line:
                yield line, caught_up
            else:
                caught_up = True
                time.sleep(1)


def main():
    path = sys.argv[1]
    total = sys.argv[2] if len(sys.argv) > 2 else "?"
    n = n_iv = n_rain = n_live = 0
    t0 = None
    for line, caught_up in follow(path):
        if caught_up and t0 is None:
            t0 = time.time()
        if "[FAILED]" in line:
            print(f"  !! {line.strip()}", flush=True)
        if not line.startswith(PREFIX):
            continue
        _, _, payload = line[len(PREFIX):].partition(": ")
        try:
            info = ast.literal_eval(payload.strip())
        except (ValueError, SyntaxError):
            continue
        n += 1
        n_iv += info.get("Instrumental Variable Used") == "1"
        n_rain += info.get("Instrumental Variable Rainfall") == "1"
        speed = ""
        if t0 is not None:
            n_live += 1
            speed = f"{(time.time() - t0) / n_live:.0f}s/paper; "
        print(f"\n[{n}/{total}] {info.get('File Name')}  ({speed}"
              f"IV {n_iv}, rainfall IV {n_rain})", flush=True)
        print(f"  Title: {info.get('Title')}", flush=True)
        for label, key in FIELDS:
            val = info.get(key, "n/a")
            if val != "n/a":
                print(f"  {label:9s} {val}", flush=True)


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        pass
