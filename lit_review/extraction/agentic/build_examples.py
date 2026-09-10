"""
Build reference/examples.jsonl for the agentic extractor from the human-labeled
train_80.csv (never removed_20.csv — that is the hold-out being evaluated).

Each line: {"field", "value", "section", "quote", "title"} — a worked example the
reader/judge prompts show for format/style guidance.

Run once:  python extraction/agentic/build_examples.py
"""
import csv
import json
import os
import random
import re

TRAIN_CSV = "/Users/kieran/Library/CloudStorage/OneDrive-UniversityofArizona/weather_iv_lit/training/models/finetune_data/train_80.csv"
OUT = os.path.join(os.path.dirname(__file__), "reference", "examples.jsonl")

PER_FIELD = 14          # positive examples per free-text field
PER_BINARY = 8          # examples per binary value (1 and 0)
MAX_QUOTE = 500
SEED = 42


def _clean(s):
    return re.sub(r"\s+", " ", (s or "").strip())


def _norm_bin(v):
    return "1" if str(v).strip() in ("1", "1.0") else ("0" if str(v).strip() in ("0", "0.0") else "")


def load_rows(path):
    for enc in ("utf-8-sig", "utf-16", "cp1252", "latin1"):
        try:
            with open(path, newline="", encoding=enc) as f:
                return list(csv.DictReader(f))
        except (UnicodeDecodeError, UnicodeError):
            continue
    raise RuntimeError(f"could not decode {path}")


def main():
    rows = load_rows(TRAIN_CSV)
    rnd = random.Random(SEED)
    rnd.shuffle(rows)
    out = []

    # ---- free-text fields: (field, var_col, sec_col, txt_col, gate_col) ----
    free = [
        ("dependent_variables", "dep_var", "dep_sec", "dep_txt", "emp_bin"),
        ("endogenous_variables", "end_var", "end_sec", "end_txt", "end_bin"),
        ("instruments", "iv_var", "iv_sec", "iv_txt", "iv_bin"),
        ("rainfall_instrument", "rain_var", "rain_sec", "rain_txt", "rain_bin"),
    ]
    for field, vc, sc, tc, gc in free:
        n = 0
        for r in rows:
            if _norm_bin(r.get(gc)) != "1":
                continue
            val, sec, txt = _clean(r.get(vc)), _clean(r.get(sc)), _clean(r.get(tc))
            if not val or not txt:
                continue
            out.append({
                "field": field, "value": val, "section": sec or "n/a",
                "quote": txt[:MAX_QUOTE], "title": _clean(r.get("title"))[:160],
            })
            n += 1
            if n >= PER_FIELD:
                break

    # ---- binaries: show both labels, with a nearby quote for context when available ----
    binaries = [
        ("empirical_analysis", "emp_bin", "dep_txt"),
        ("endogeneity_problem", "end_bin", "end_txt"),
        ("iv_used", "iv_bin", "iv_txt"),
        ("rainfall_iv", "rain_bin", "rain_txt"),
    ]
    for field, bc, tc in binaries:
        for label in ("1", "0"):
            n = 0
            for r in rows:
                if _norm_bin(r.get(bc)) != label:
                    continue
                # context quote: prefer this field's own _txt, else the endogeneity/iv quote
                ctx = _clean(r.get(tc)) or _clean(r.get("iv_txt")) or _clean(r.get("end_txt"))
                out.append({
                    "field": field, "value": label,
                    "section": _clean(r.get(tc.replace("_txt", "_sec"))) or "n/a",
                    "quote": ctx[:MAX_QUOTE] if ctx else "",
                    "title": _clean(r.get("title"))[:160],
                })
                n += 1
                if n >= PER_BINARY:
                    break

    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    with open(OUT, "w", encoding="utf-8") as f:
        for rec in out:
            f.write(json.dumps(rec, ensure_ascii=False) + "\n")

    by_field = {}
    for rec in out:
        by_field.setdefault(rec["field"], []).append(rec["value"] if rec["field"].endswith(("_iv", "_problem", "_used", "_analysis")) else 1)
    print(f"wrote {len(out)} examples -> {OUT}")
    for k in ("empirical_analysis", "dependent_variables", "endogeneity_problem",
              "endogenous_variables", "iv_used", "instruments", "rainfall_iv", "rainfall_instrument"):
        print(f"  {k:22} {sum(1 for r in out if r['field']==k)}")


if __name__ == "__main__":
    main()
