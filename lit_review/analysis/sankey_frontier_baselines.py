"""
Rainfall-IV -> endogenous-variable Sankeys for the newest-model zero-shot
baselines (GPT-6.1 Sol, Gemini 4 Argon, Gemma 4 26B, Llama 4 Maverick,
Claude Opus 5.5).

Runs sankey_iv_clustering.main() unchanged once per model, swapping only its
input/output path constants. Unlike the GPT-4.1 Sankeys (built on the full
corpus via *_full_corpus.csv), these baselines were only run on the 88-paper
held-out test set, so each Sankey covers that model's test-set rainfall-IV
papers only (~33-36 papers) -- outputs are named sankey_test_baseline_<model>_*
to keep that distinction visible.

Categorization follows sankey_iv_clustering.CATEGORIZER. With "fixed" (the
default), every model's entries are classified into the same taxonomy
(sankey_taxonomy.py) by a local embedding + reranker classifier, so the
diagrams share categories and are directly comparable. With "llm", each
model gets its own GPT-5 taxonomy (needs OPENAI_API_KEY) and category names
can differ between diagrams.

Run with: /Users/kieran/.virtualenvs/bert_env/bin/python3 analysis/sankey_frontier_baselines.py
"""

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import sankey_iv_clustering as sic

ROOT = "/Users/kieran/Library/CloudStorage/OneDrive-UniversityofArizona/weather_iv_lit"
FIGURES_DIR = os.path.join(ROOT, "writing", "figures")

# model key -> output/ subfolder holding test_baseline_<key>_output.csv
BASELINES = {
    "sol":    "gpt/baseline_sol",
    "gemini": "gemini/baseline",
    "gemma":  "gemma/baseline",
    "llama":  "llama/baseline",
    "claude": "claude/baseline",
}


def set_paths(key, subdir):
    out_dir = os.path.join(ROOT, "output", subdir)
    stem = f"test_baseline_{key}"
    sic.MERGED_CSV = os.path.join(out_dir, f"{stem}_output.csv")
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
    for key, subdir in BASELINES.items():
        print(f"\n===== {key} =====")
        set_paths(key, subdir)
        sic.main()
