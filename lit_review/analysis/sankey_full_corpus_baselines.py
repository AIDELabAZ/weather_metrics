"""
Rainfall-IV -> endogenous-variable Sankeys for the newest-model zero-shot
baselines run on the full papers/ corpus (Oct 2026): GPT-6.1 Sol, Llama 4
Maverick, Gemma 4 26B, Claude Opus 5.5. Gemini 4 Argon was only run on the
88-paper test set (see sankey_frontier_baselines.py).

Runs sankey_iv_clustering.main() unchanged once per model, swapping only its
input/output path constants, like sankey_frontier_baselines.py. Input is each
model's full_baseline_<key>_output.csv directly (papers/ only — the 88
held-out test papers are not included, so unlike the GPT-4.1 *_full_corpus.csv
files these don't add the test-set rows). Outputs are named
sankey_full_baseline_<key>_*.

Categorization uses the fixed taxonomy (sankey_iv_clustering.CATEGORIZER =
"fixed") with the qwen3-0.6b backbone, which is already downloaded; the 4B
pair is the intended default but needs ~16 GB of disk. The 0.6B reranker is
known to over-assign "Other" on the endogenous side — check the classifier
audit CSVs.

Run with: python3 analysis/sankey_full_corpus_baselines.py [model ...]
       or SANKEY_BACKBONE=qwen3-8b python3 analysis/sankey_full_corpus_baselines.py
          after running the HPC classifier (analysis/hpc/README.md).
"""

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import fixed_label_classifier
import sankey_iv_clustering as sic

ROOT = "/Users/kieran/Library/CloudStorage/OneDrive-UniversityofArizona/weather_iv_lit"
FIGURES_DIR = os.path.join(ROOT, "writing", "figures")

# SANKEY_BACKBONE=qwen3-8b uses the results scored on HPC (analysis/hpc/,
# merged into the local cache) — the 8B models never load on the Mac.
fixed_label_classifier.BACKBONE = os.environ.get("SANKEY_BACKBONE", "qwen3-0.6b")

# model key -> output/ subfolder holding full_baseline_<key>_output.csv
BASELINES = {
    "sol":    "gpt/baseline_sol",
    "llama":  "llama/baseline",
    "gemma":  "gemma/baseline",
    "claude": "claude/baseline",
    # GPT-4.1 zero-shot / fine-tuned / RAG, raw model output only (no human
    # rows, unlike analysis/{baseline,sft,rag}_full_corpus.csv behind the
    # Sep 2026 sankey_{baseline,sft,rag}_gpt_* figures, which are kept as-is).
    "gpt":     "gpt/baseline",
    "sft_gpt": "gpt/sft",
    "rag_gpt": "gpt/rag",
}

# Keys whose files aren't named full_baseline_<key>: input is <stem>_output.csv,
# outputs are sankey_<stem>[_<backbone>]_*.
STEMS = {
    "sft_gpt": "full_sft_gpt",
    "rag_gpt": "full_rag_gpt",
}


def set_paths(key, subdir):
    out_dir = os.path.join(ROOT, "output", subdir)
    # Outputs get a _<backbone> suffix when SANKEY_BACKBONE is set, so 0.6b /
    # 4b / 8b Sankeys sit side by side; the input CSV name never changes.
    base = STEMS.get(key, f"full_baseline_{key}")
    stem = base
    if "SANKEY_BACKBONE" in os.environ:
        stem += "_" + os.environ["SANKEY_BACKBONE"]
    sic.MERGED_CSV = os.path.join(out_dir, f"{base}_output.csv")
    sic.OUTPUT_HTML_ENDOG = os.path.join(out_dir, f"sankey_{stem}_rainfall_endog.html")
    sic.OUTPUT_PNG_ENDOG = os.path.join(FIGURES_DIR, f"sankey_{stem}_rainfall_endog.png")
    sic.OUTPUT_PNG_WIDE_ENDOG = os.path.join(FIGURES_DIR, f"sankey_{stem}_rainfall_endog_wide.png")
    sic.OUTPUT_EPS_ENDOG = os.path.join(FIGURES_DIR, f"sankey_{stem}_rainfall_endog.eps")
    sic.CLUSTER_SUMMARY_ENDOG = os.path.join(out_dir, f"cluster_{stem}_summary_endog.csv")
    sic.REJECTED_ENTRIES_CSV = os.path.join(out_dir, f"rejected_entries_{stem}.csv")
    sic.RELATIONSHIPS_RAW_ENDOG_CSV = os.path.join(out_dir, f"relationships_raw_endog_{stem}.csv")
    sic.RELATIONSHIPS_CATEGORIZED_ENDOG_CSV = os.path.join(out_dir, f"relationships_categorized_endog_{stem}.csv")
    sic.CLASSIFIER_AUDIT_CSV = os.path.join(out_dir, f"classifier_audit_{stem}.csv")


if __name__ == "__main__":
    keys = sys.argv[1:] or list(BASELINES)
    for key in keys:
        print(f"\n===== {key} =====")
        set_paths(key, BASELINES[key])
        sic.main()
