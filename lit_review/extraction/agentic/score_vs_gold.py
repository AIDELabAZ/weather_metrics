"""
Quick Python check of an extraction CSV against removed_20.csv (the 88-paper gold),
replicating analysis/model_eval.R's binary treatment (as.numeric, NA -> 0, join on
cleaned filename). Free-text fields are shown as exact/near-miss counts only — the
real free-text metric is the R cross-encoder.

  python extraction/agentic/score_vs_gold.py [path/to/output.csv]
"""
import csv
import re
import sys
import unicodedata

GOLD = "/Users/kieran/Library/CloudStorage/OneDrive-UniversityofArizona/weather_iv_lit/training/models/finetune_data/removed_20.csv"
DEFAULT = "/Users/kieran/Library/CloudStorage/OneDrive-UniversityofArizona/weather_iv_lit/training/models/output/agentic/agentic_output.csv"

BIN = [("Empirical Analysis", "emp_bin"), ("Endogeneity Problem", "end_bin"),
       ("Instrumental Variable Used", "iv_bin"), ("Instrumental Variable Rainfall", "rain_bin")]
TXT = [("Dependent Variable(s)", "dep_var"), ("Endogenous Variable(s)", "end_var"),
       ("Instrumental Variable(s)", "iv_var"), ("Rainfall Instrument", "rain_var")]


def key(s):
    s = unicodedata.normalize("NFKD", str(s or "")).encode("ascii", "ignore").decode().lower()
    s = re.sub(r"\.pdf$", "", s.strip())
    return re.sub(r"[^a-z0-9]", "", s)


def to01(v):
    v = str(v or "").strip().lower()
    try:
        return 1 if float(v) == 1 else 0
    except ValueError:
        return 1 if v in ("1", "yes", "true") else 0


def load(path):
    for enc in ("utf-8-sig", "utf-8", "utf-16", "cp1252", "latin1"):
        try:
            with open(path, newline="", encoding=enc) as f:
                return list(csv.DictReader(f))
        except (UnicodeDecodeError, UnicodeError):
            continue
    raise RuntimeError(path)


def main():
    mpath = sys.argv[1] if len(sys.argv) > 1 else DEFAULT
    gold = {key(r["filename"]): r for r in load(GOLD)}
    model = {key(r["File Name"]): r for r in load(mpath)}
    common = sorted(set(gold) & set(model))
    print(f"model rows: {len(model)}   gold rows: {len(gold)}   joined: {len(common)}\n")

    for mcol, gcol in BIN:
        tp = fp = fn = tn = 0
        for k in common:
            h, m = to01(gold[k].get(gcol)), to01(model[k].get(mcol))
            tp += h and m
            fp += (not h) and m
            fn += h and (not m)
            tn += (not h) and (not m)
        acc = (tp + tn) / len(common) if common else 0
        rec = tp / (tp + fn) if tp + fn else float("nan")
        pre = tp / (tp + fp) if tp + fp else float("nan")
        spec = tn / (tn + fp) if tn + fp else float("nan")
        f1 = 2 * pre * rec / (pre + rec) if (pre == pre and rec == rec and pre + rec) else float("nan")
        print(f"{mcol:30} acc={acc:.3f} rec={rec:.3f} prec={pre:.3f} spec={spec:.3f} f1={f1:.3f}"
              f"   [TP {tp} FP {fp} FN {fn} TN {tn}]")

    print()
    for mcol, gcol in TXT:
        both = exact = near = 0
        for k in common:
            g = str(gold[k].get(gcol) or "").strip().lower()
            m = str(model[k].get(mcol) or "").strip().lower()
            gp = g not in ("", "n/a", "na", "none")
            mp = m not in ("", "n/a", "na", "none")
            if gp and mp:
                both += 1
                gk, mk = re.sub(r"[^a-z0-9]", "", g), re.sub(r"[^a-z0-9]", "", m)
                if gk == mk:
                    exact += 1
                elif gk and mk and (gk in mk or mk in gk):
                    near += 1
        print(f"{mcol:30} both-populated={both:2}  exact={exact}  substr-near={near}")


if __name__ == "__main__":
    main()
