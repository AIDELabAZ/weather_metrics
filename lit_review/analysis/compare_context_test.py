"""
Scores the input-cap / cleaner test runs (extraction/baseline/run_context_test.py)
against the original published runs, for GPT-4.1 and GPT-6.1 Sol.

Conditions per model:
  old            — original published output (40k cap, legacy cleaner)
  cap40k_legacy  — new run, 40k cap, raw answers re-cleaned with the legacy
                   cleaner. vs old ≈ run-to-run noise (same settings, new run).
  cap40k         — new run, 40k cap, new cleaner. vs cap40k_legacy = cleaner effect
                   (same answers, only cleaning differs).
  full           — new run, no cap, new cleaner. vs cap40k = cap effect
                   (plus run-to-run noise).

Scoring mirrors model_eval.R so numbers are comparable to the paper tables:
same cross-encoder (cross-encoder/stsb-roberta-large), lowercasing, n/a → NA,
filename join. model_eval.R drops pairs where either side is NA from the
similarity mean, so a model answering n/a when the human has an answer is
never penalized — the "_miss0" columns score those pairs as 0 instead.
Every condition is scored here (including old), rather than reusing
model_eval.R's numbers, so all conditions share exactly one implementation;
"old" is checked against merged_data_*.csv to confirm it reproduces them.

Run with: /Users/kieran/.virtualenvs/bert_env/bin/python3 analysis/compare_context_test.py
"""

import importlib
import json
import os
import re
import sys
import unicodedata

import numpy as np
import pandas as pd
from sentence_transformers import CrossEncoder

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "extraction", "baseline"))

ROOT = "/Users/kieran/Library/CloudStorage/OneDrive-UniversityofArizona/weather_iv_lit"
OUT = os.path.join(ROOT, "output")
HUMAN_CSV = os.path.join(ROOT, "training", "data_prep_all_models", "removed_20.csv")
RESULTS_CSV = os.path.join(OUT, "gpt", "context_test_comparison.csv")

MODELS = {
    "gpt41": dict(
        module="baseline_gpt",
        old=os.path.join(OUT, "gpt", "baseline", "baseline_gpt_output.csv"),
        old_merged=os.path.join(OUT, "gpt", "baseline", "merged_data_gpt_baseline.csv"),
        new_dir=os.path.join(OUT, "gpt", "baseline_context_test"),
        csv="test_baseline_gpt_output.csv",
    ),
    "sol": dict(
        module="baseline_sol",
        old=os.path.join(OUT, "gpt", "baseline_sol", "test_baseline_sol_output.csv"),
        old_merged=os.path.join(OUT, "gpt", "baseline_sol", "merged_data_gpt_sol.csv"),
        new_dir=os.path.join(OUT, "gpt", "baseline_sol_context_test"),
        csv="test_baseline_sol_output.csv",
    ),
}

# model_eval.R short name -> (human column, model column)
TEXT_FIELDS = {
    "rainmet": ("rain_var", "Rainfall Instrument"),
    "endog":   ("end_var",  "Endogenous Variable(s)"),
    "depen":   ("dep_var",  "Dependent Variable(s)"),
    "iv":      ("iv_var",   "Instrumental Variable(s)"),
    "ptitle":  ("title",    "Title"),
}
BINARY_FIELDS = {
    "rain_bin": ("rain_bin", "Instrumental Variable Rainfall"),
    "iv_bin":   ("iv_bin",   "Instrumental Variable Used"),
    "end_bin":  ("end_bin",  "Endogeneity Problem"),
    "emp_bin":  ("emp_bin",  "Empirical Analysis"),
}
VAR_LIST_COLS = ["Dependent Variable(s)", "Endogenous Variable(s)", "Instrumental Variable(s)", "Rainfall Instrument"]
NA_STRINGS = ["n/a", "NA", ""]


def clean_filename(fn: str) -> str:
    # model_eval.R: tolower, drop .pdf and " copy N", iconv ASCII//TRANSLIT, squish
    s = str(fn).lower()
    s = re.sub(r"\.pdf$", "", s)
    s = re.sub(r" copy( \d+)?$", "", s)
    s = unicodedata.normalize("NFKD", s).encode("ascii", "ignore").decode()
    return re.sub(r"\s+", " ", s).strip()


def load_model_csv(path: str) -> pd.DataFrame:
    df = pd.read_csv(path, na_values=NA_STRINGS, keep_default_na=True)
    # Same rule as model_eval.R: rows with a failed model call aren't answers.
    if "Extraction Error" in df:
        failed = df["Extraction Error"].notna()
        if failed.any():
            print(f"  [warn] {os.path.basename(path)}: dropping {failed.sum()} failed paper(s): "
                  f"{', '.join(df.loc[failed, 'File Name'])}")
        df = df[~failed]
    return df


def legacy_reclean(new_csv: str, raw_jsonl: str, module_name: str) -> pd.DataFrame:
    """Rebuild the new run's variable-list columns from its raw answers using
    the legacy cleaner. Fields the run left n/a (dependency gates) stay n/a."""
    mod = importlib.import_module(module_name)
    df = load_model_csv(new_csv)
    raw = {}
    with open(raw_jsonl, encoding="utf-8") as f:
        for line in f:
            r = json.loads(line)
            raw[r["File Name"]] = r["raw_answers"]

    new_cleaner = mod.clean_variable_list
    mod.clean_variable_list = mod.clean_variable_list_legacy  # parse_prefixed_lines looks it up at call time
    try:
        for i, row in df.iterrows():
            answers = raw.get(row["File Name"], {})
            legacy = {}
            for q in mod.questions:
                if q["key"] in answers and "field_map" in q:
                    parsed, _ = mod.parse_prefixed_lines(answers[q["key"]], q["field_map"])
                    legacy.update(parsed)
            if "Dependent Variable(s)" in answers:
                legacy["Dependent Variable(s)"] = mod.clean_variable_list_legacy(answers["Dependent Variable(s)"])
            if "Rainfall Instrument Reask" in answers:
                parsed, _ = mod.parse_prefixed_lines(
                    answers["Rainfall Instrument Reask"], {"RAINFALL_INSTRUMENT": ("Rainfall Instrument", "var_list")}
                )
                legacy.update(parsed)
            for col in VAR_LIST_COLS:
                if pd.notna(row[col]) and col in legacy:
                    df.at[i, col] = np.nan if legacy[col] == "n/a" else legacy[col]
    finally:
        mod.clean_variable_list = new_cleaner
    return df


_ce = None


def ce_scores(a: list[str], b: list[str]) -> np.ndarray:
    global _ce
    if _ce is None:
        _ce = CrossEncoder("cross-encoder/stsb-roberta-large")
    return np.asarray(_ce.predict(list(zip(a, b)), batch_size=32), dtype=float)


def score(model_df: pd.DataFrame, human: pd.DataFrame) -> tuple[dict, pd.DataFrame]:
    m = model_df.copy()
    m["k"] = m["File Name"].map(clean_filename)
    merged = human.merge(m, on="k", how="inner")
    row = {"n_papers": len(merged)}
    for short, (hcol, mcol) in TEXT_FIELDS.items():
        h = merged[hcol].astype("string").str.lower()
        mm = merged[mcol].astype("string").str.lower()
        both = h.notna() & mm.notna()
        s = pd.Series(np.nan, index=merged.index)
        if both.any():
            s[both] = ce_scores(list(h[both]), list(mm[both]))
        merged[f"{short}_similarity"] = s
        row[f"{short}_sim"] = s.mean()
        # human has an answer, model said n/a -> 0 instead of dropped
        miss = h.notna() & mm.isna()
        row[f"{short}_miss0"] = pd.concat([s[both], pd.Series(0.0, index=s[miss].index)]).mean()
        row[f"{short}_n_missing"] = int(miss.sum())
    for short, (hcol, mcol) in BINARY_FIELDS.items():
        h = pd.to_numeric(merged[hcol], errors="coerce").fillna(0)
        mm = pd.to_numeric(merged[mcol], errors="coerce").fillna(0)
        row[f"{short}_acc"] = (h == mm).mean()
    return row, merged


def main():
    human = pd.read_csv(HUMAN_CSV, na_values=NA_STRINGS, keep_default_na=True)
    human["k"] = human["filename"].map(clean_filename)

    rows = []
    for model, cfg in MODELS.items():
        cap_csv = os.path.join(cfg["new_dir"], "cap40k", cfg["csv"])
        conditions = {
            "old": load_model_csv(cfg["old"]),
            "cap40k_legacy": legacy_reclean(cap_csv, os.path.splitext(cap_csv)[0] + "_raw_answers.jsonl", cfg["module"]),
            "cap40k": load_model_csv(cap_csv),
            "full": load_model_csv(os.path.join(cfg["new_dir"], "full", cfg["csv"])),
        }
        for cond, df in conditions.items():
            r, merged = score(df, human)
            rows.append({"model": model, "condition": cond, **r})
            if cond == "old":
                ref = pd.read_csv(cfg["old_merged"])
                for short in TEXT_FIELDS:
                    a, b = merged[f"{short}_similarity"].mean(), ref[f"{short}_similarity"].mean()
                    flag = "" if abs(a - b) < 0.005 else "   <-- MISMATCH vs model_eval.R"
                    print(f"  [{model} old] {short}: here {a:.4f} vs model_eval.R {b:.4f}{flag}")

    res = pd.DataFrame(rows)
    res.to_csv(RESULTS_CSV, index=False)
    pd.set_option("display.width", 250)
    show = ["model", "condition", "n_papers"] + [f"{s}_sim" for s in TEXT_FIELDS] + \
           ["rainmet_miss0", "rainmet_n_missing", "endog_miss0", "endog_n_missing"] + [f"{s}_acc" for s in BINARY_FIELDS]
    print(res[show].round(3).to_string(index=False))
    print(f"\n→ {RESULTS_CSV}")


if __name__ == "__main__":
    main()
