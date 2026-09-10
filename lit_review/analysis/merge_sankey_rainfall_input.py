"""
merge_sankey_rainfall_input.py

Builds the paper population that feeds the rainfall Sankey, as an explicit CSV.

Population = union of
  - model corpus rows with  Instrumental Variable Rainfall == 1   (full_finetune_gpt_output.csv)
  - human out-of-sample rows with  rain_bin == 1                  (training_all_new.xlsx)

Dedup: by NORMALIZED TITLE (lowercase, whitespace/newlines collapsed,
punctuation stripped). Rows are stacked human-first, then model, then
duplicate titles are dropped keeping the first occurrence — so for a paper
that appears in both, the human-verified row wins and the model row is
discarded. Duplicate titles within a single source are also collapsed.

One row per paper. Count columns (raw = non-empty ';'-split pieces, dropping
"", n/a, na, none; clean = of those, how many survive the Sankey noise filter
clean_entry(..., requires_rainfall=...)):

  n_rainfall_iv          / n_rainfall_iv_clean
  n_dependent_var        / n_dependent_var_clean
  n_endogenous_var       / n_endogenous_var_clean

Σ n_rainfall_iv over all rows = total rainfall IVs shown in the Sankey, with a
paper that lists k rainfall instruments counted k times.

clean_entry / normalize_filename are reused from merge_rainfall_iv_counts.py
(mirrored from sankey_iv_clustering.py).
"""
import re
import pandas as pd

from merge_rainfall_iv_counts import clean_entry, _BLANKS  # noqa: E402

# ─── Paths ────────────────────────────────────────────────────────────────
# GPT input is the full fine-tuned (sft) corpus run; output sits with the
# other sft-derived Sankey artifacts. HUMAN_XLSX is a training/ input.
GPT_CSV    = "/Users/kieran/Library/CloudStorage/OneDrive-UniversityofArizona/weather_iv_lit/output/gpt/sft/full_sft_gpt_output.csv"
HUMAN_XLSX = "/Users/kieran/Library/CloudStorage/OneDrive-UniversityofArizona/weather_iv_lit/training/training_new_labels/training_all_new.xlsx"
OUTPUT_CSV = "/Users/kieran/Library/CloudStorage/OneDrive-UniversityofArizona/weather_iv_lit/output/gpt/sft/merged_sankey_rainfall_iv_dependent.csv"


def norm_title(t) -> str:
    s = str(t).lower().strip()
    s = re.sub(r"\s+", " ", s)          # collapse newlines / runs of spaces
    s = re.sub(r"[^a-z0-9 ]", "", s)    # drop punctuation
    return s.strip()


def raw_pieces(val) -> list[str]:
    if not isinstance(val, str):
        return []
    return [p.strip() for part in val.split(";")
            if (p := part.strip()) and p.lower() not in _BLANKS]


def clean_pieces(val, requires_rainfall: bool = False) -> list[str]:
    if not isinstance(val, str):
        return []
    return [c for part in val.split(";")
            if (c := clean_entry(part, requires_rainfall=requires_rainfall))]


def main() -> None:
    # ── model corpus, rainfall IVs only ─────────────────────────────────
    gpt = pd.read_csv(GPT_CSV)
    gpt = gpt[gpt["Instrumental Variable Rainfall"] == 1.0].copy()
    gpt = pd.DataFrame({
        "source":             "model",
        "paper_title":        gpt["Title"],
        "file_ref":           gpt["File Name"],
        "doi":                gpt["DOI"],
        "rainfall_iv_flag":   gpt["Instrumental Variable Rainfall"],
        "rainfall_iv_text":   gpt["Rainfall Instrument"],
        "dependent_var_text": gpt["Dependent Variable(s)"],
        "endogenous_var_text": gpt["Endogenous Variable(s)"],
    })

    # ── human out-of-sample, rainfall IVs only ─────────────────────────
    hum = pd.read_excel(HUMAN_XLSX)
    hum = hum[hum["rain_bin"] == 1.0].copy()
    hum = pd.DataFrame({
        "source":             "human",
        "paper_title":        hum["title"],
        "file_ref":           hum["filename"],
        "doi":                hum["doi"],
        "rainfall_iv_flag":   hum["rain_bin"],
        "rainfall_iv_text":   hum["rain_var"],
        "dependent_var_text": hum["dep_var"],
        "endogenous_var_text": hum["end_var"],
    })

    n_gpt_raw, n_hum_raw = len(gpt), len(hum)

    # ── stack human-first, dedup by normalized title (human wins) ──────
    both = pd.concat([hum, gpt], ignore_index=True)
    both["title_key"] = both["paper_title"].map(norm_title)

    title_source_counts = both.groupby("title_key")["source"].agg(set)
    both["also_in_other_source"] = both["title_key"].map(
        lambda k: int(len(title_source_counts[k]) > 1)
    )

    n_before = len(both)
    merged = both.drop_duplicates("title_key", keep="first").reset_index(drop=True)
    n_dropped = n_before - len(merged)

    # ── per-paper counts ─────────────────────────────────────────────
    merged["n_rainfall_iv"]          = merged["rainfall_iv_text"].map(lambda v: len(raw_pieces(v)))
    merged["n_rainfall_iv_clean"]    = merged["rainfall_iv_text"].map(lambda v: len(clean_pieces(v, True)))
    merged["n_dependent_var"]        = merged["dependent_var_text"].map(lambda v: len(raw_pieces(v)))
    merged["n_dependent_var_clean"]  = merged["dependent_var_text"].map(lambda v: len(clean_pieces(v, False)))
    merged["n_endogenous_var"]       = merged["endogenous_var_text"].map(lambda v: len(raw_pieces(v)))
    merged["n_endogenous_var_clean"] = merged["endogenous_var_text"].map(lambda v: len(clean_pieces(v, False)))

    merged = merged[[
        "title_key", "paper_title", "source", "also_in_other_source",
        "file_ref", "doi", "rainfall_iv_flag",
        "n_rainfall_iv", "n_rainfall_iv_clean",
        "n_dependent_var", "n_dependent_var_clean",
        "n_endogenous_var", "n_endogenous_var_clean",
        "rainfall_iv_text", "dependent_var_text", "endogenous_var_text",
    ]].sort_values(["source", "paper_title"]).reset_index(drop=True)

    merged.to_csv(OUTPUT_CSV, index=False)

    # ── report ──────────────────────────────────────────────────────
    n_h = int((merged["source"] == "human").sum())
    n_m = int((merged["source"] == "model").sum())
    n_overlap = int(merged["also_in_other_source"].sum())
    print(f"model rainfall rows in   : {n_gpt_raw}")
    print(f"human rainfall rows in   : {n_hum_raw}")
    print(f"stacked                  : {n_before}")
    print(f"dropped as dup title     : {n_dropped}  "
          f"(within-source dups + {n_overlap} cross-source titles where human won)")
    print(f"MERGED distinct papers   : {len(merged)}   (human {n_h}, model {n_m})")
    print()
    print(f"TOTAL rainfall IVs in Sankey (Σ n_rainfall_iv)       : {int(merged['n_rainfall_iv'].sum())}")
    print(f"  after noise filter    (Σ n_rainfall_iv_clean)      : {int(merged['n_rainfall_iv_clean'].sum())}")
    print(f"TOTAL dependent vars         (Σ n_dependent_var)     : {int(merged['n_dependent_var'].sum())}")
    print(f"  after noise filter        (Σ n_dependent_var_clean): {int(merged['n_dependent_var_clean'].sum())}")
    print(f"TOTAL endogenous vars        (Σ n_endogenous_var)    : {int(merged['n_endogenous_var'].sum())}")
    print()
    print("papers by rainfall-IV count (raw):")
    for k, v in merged["n_rainfall_iv"].value_counts().sort_index().items():
        print(f"   {k} IV(s): {v} papers")
    print()
    print(f"papers with 0 surviving rainfall IVs after cleaning: "
          f"{int((merged['n_rainfall_iv_clean'] == 0).sum())} "
          f"(become 'Other'/'Not Specified' nodes in the Sankey)")
    print(f"\nWrote {OUTPUT_CSV}")


if __name__ == "__main__":
    main()
