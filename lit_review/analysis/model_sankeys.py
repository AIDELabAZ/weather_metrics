"""
Rainfall-IV -> endogenous-variable Sankeys for every LLM implementation (GPT-4.1
zero-shot / RAG / SFT, GPT-6.1 Sol, Llama 4 Maverick, Gemma 4 26B, Claude Opus
5.5), categorized with the 32B Solo classifier (Qwen3-32B, taxonomy + decision
rules, entry name only).

Same sample as the agreement tables (model_agreement_tables.py): the 3,840
papers with model-generated labels (full corpus + common held-out evaluation
set), so each Sankey covers exactly the rainfall-IV papers counted in Panel A.
Same drawing as writing/thesis/sankey_final: one link per within-paper
rainfall-IV x endogenous pair with both ends in a shown category, labels outside.

Writes to <OneDrive>/weather_iv_lit/writing/figures/:
  sankey_<model>.png / .eps / .csv   (CSV: one row per drawn link)
  sankey_model_summary.csv            papers and links per model

Run model_agreement_tables.py first (it classifies any entries 32B Solo hasn't seen).
Usage (from lit_review/):
  DYLD_FALLBACK_LIBRARY_PATH=/opt/homebrew/lib python3 analysis/model_sankeys.py [model ...]
"""

import os
import sys
import tempfile

import pandas as pd

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import model_agreement_tables as mat
import sankey_iv_clustering as sic

OUT = os.path.join(mat.ROOT, "writing", "figures")
FILE_STEM = {"gpt": "gpt41_zero_shot", "rag_gpt": "gpt41_rag", "sft_gpt": "gpt41_sft", "sol": "gpt61_sol",
             "llama": "llama4_maverick", "gemma": "gemma4_26b", "claude": "claude_opus_55"}


def main():
    keys = sys.argv[1:] or list(mat.MODELS)
    os.makedirs(OUT, exist_ok=True)
    frames = {k: mat.load(k) for k in mat.MODELS}
    common = sorted(set.intersection(*[set(f.index) for f in frames.values()]))
    labels = mat.solo_labels()

    def lookup(unique_entries, side_name, *a, **k):
        missing = [e for e in unique_entries if e not in labels[side_name]]
        assert not missing, f"{len(missing)} entries without a 32B Solo label (run model_agreement_tables.py): {missing[:5]}"
        m = {e: labels[side_name][e] for e in unique_entries}
        return m, pd.DataFrame({"side": side_name, "entry": list(m), "label": list(m.values())})

    sic.fixed_label_classifier.classify = lookup
    sic.CATEGORIZER = "fixed"
    sic.COUNT_RELATIONSHIPS = sic.OUTSIDE_LABELS = True
    sic.ONE_TO_ONE_ONLY = sic.PAIR_BY_POSITION = False
    sic.OUTPUT_PNG_WIDE_ENDOG = sic.OUTPUT_HTML_ENDOG = sic.CLUSTER_SUMMARY_ENDOG = None
    sic.REJECTED_ENTRIES_CSV = sic.CLASSIFIER_AUDIT_CSV = None
    summary = []
    for key in keys:
        label = mat.MODELS[key][0]
        df = frames[key].loc[common].reset_index()
        df["Instrumental Variable Rainfall"] = (df["Instrumental Variable Rainfall"].str.strip() == "1").astype(int)
        stem = os.path.join(OUT, f"sankey_{FILE_STEM[key]}")
        sic.OUTPUT_PNG_ENDOG, sic.OUTPUT_EPS_ENDOG = stem + ".png", stem + ".eps"
        if os.path.exists(sic.OUTPUT_EPS_ENDOG):  # OneDrive "dataless" placeholder issue on overwrite
            os.remove(sic.OUTPUT_EPS_ENDOG)
        print(f"\n===== {label} =====", flush=True)
        with tempfile.TemporaryDirectory() as tmp:
            sic.MERGED_CSV = os.path.join(tmp, "input.csv")
            df.to_csv(sic.MERGED_CSV, index=False)
            sic.main()
        links = pd.DataFrame(sic.LAST_LINKS)
        rain = df[df["Instrumental Variable Rainfall"] == 1].assign(
            paper_key=lambda d: d["File Name"].map(sic.normalize_filename))
        meta = rain.groupby("paper_key").agg(file_name=("File Name", "first"), title=("Title", "first"))
        links = links.join(meta, on="paper_key")
        links.insert(0, "model", label)
        links[["model", "paper_key", "file_name", "title", "rainfall_iv", "rainfall_category",
               "endogenous_variable", "endogenous_category"]].to_csv(stem + ".csv", index=False)
        summary.append({"model": label, "file": os.path.basename(stem), "rainfall_iv_papers": len(meta),
                        "papers_with_links": links.paper_key.nunique(), "links": len(links)})
        print(f"  {label}: {len(links)} links from {links.paper_key.nunique()} of {len(meta)} rainfall-IV papers")
    if set(keys) == set(mat.MODELS):
        pd.DataFrame(summary).to_csv(os.path.join(OUT, "sankey_model_summary.csv"), index=False)
    print(pd.DataFrame(summary).to_string(index=False))
    print(f"Outputs -> {OUT}")


if __name__ == "__main__":
    main()
