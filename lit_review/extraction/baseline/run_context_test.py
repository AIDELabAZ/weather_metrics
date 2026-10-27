"""
Zero-shot baselines on the 88-paper test set, run under two conditions to
separate two fixes:

  cap40k — original 40,000-character input cap, new ';'-only cleaner
  full   — no input cap, new cleaner

Both runs save raw answers (*_raw_answers.jsonl), so the cleaner's effect is
measured without another API run: re-clean cap40k's raw answers with
clean_variable_list_legacy and compare. (Approximate only — the legacy
cleaner could turn an answer into n/a and trigger the rainfall re-ask, which
the new cleaner doesn't.) cap40k vs full then isolates the cap.

Sol runs at temperature 1, so part of any difference between runs is
sampling noise; cap40k re-cleaned with the legacy cleaner vs the original
published run estimates that noise.

Run with: /Users/kieran/.virtualenvs/bert_env/bin/python3 extraction/baseline/run_context_test.py <gpt41|sol> [cap40k|full]
"""

import importlib
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

ROOT = "/Users/kieran/Library/CloudStorage/OneDrive-UniversityofArizona/weather_iv_lit"
PDF_FOLDER = os.path.join(ROOT, "training", "data_prep_all_models", "pdf_test_20")

# model key -> (extraction module, output folder, output csv name)
MODELS = {
    "gpt41": ("baseline_gpt", os.path.join(ROOT, "output", "gpt", "baseline_context_test"), "test_baseline_gpt_output.csv"),
    "sol":   ("baseline_sol", os.path.join(ROOT, "output", "gpt", "baseline_sol_context_test"), "test_baseline_sol_output.csv"),
}

CONDITIONS = {
    "cap40k": 40_000,
    "full": None,
}

if __name__ == "__main__":
    module_name, out_root, csv_name = MODELS[sys.argv[1]]
    mod = importlib.import_module(module_name)
    for name in sys.argv[2:] or list(CONDITIONS):
        mod.MAX_INPUT_CHARS = CONDITIONS[name]
        out_dir = os.path.join(out_root, name)
        os.makedirs(out_dir, exist_ok=True)
        print(f"\n===== {sys.argv[1]} / {name} (MAX_INPUT_CHARS={mod.MAX_INPUT_CHARS}) =====")
        mod.process_pdfs_conditional_queries(PDF_FOLDER, os.path.join(out_dir, csv_name))
