"""
Writes two CSVs for reviewing the Sankey categorization (no models are run —
everything is read from the classifier cache, so run the HPC job first):

  <OneDrive>/weather_iv_lit/analysis/classifier/taxonomy.csv
      One row per allowed label (sankey_taxonomy.py), both sides, plus Other,
      with its definition and how many unique entries / entry occurrences land
      in it under each stage of the 8B pipeline:
        embed_only  — embedding nearest label (no reranker, no Other)
        rerank      — reranker's best category (no validity step, no Other)
        model       — two-stage output (validity step can send to Other)
        final       — after classifier_manual_review.csv
      So comparing the count columns shows how each stage changes the story.

  <OneDrive>/weather_iv_lit/analysis/classifier/entry_labels.csv
      One row per unique cleaned entry: n_occurrences (total times it appears,
      summed over runs — one run can report it several times), n_runs (how
      many of the 9 baseline runs reported it at all), runs (per-run counts), then each stage's label for every backbone, the scores,
      and the manual review decision/reason.

Run with:
  DYLD_FALLBACK_LIBRARY_PATH=/opt/homebrew/lib python3 analysis/export_classifier_tables.py
"""

import os
import sys
from collections import Counter, defaultdict

import pandas as pd

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import fixed_label_classifier as flc
import sankey_frontier_baselines as frontier
import sankey_full_corpus_baselines as full
import sankey_iv_clustering as sic
from sankey_taxonomy import OTHER_DEFINITIONS, TAXONOMIES, VALID_DEFINITIONS

OUT_DIR = "/Users/kieran/Library/CloudStorage/OneDrive-UniversityofArizona/weather_iv_lit/analysis/classifier"
BACKBONES = ["qwen3-8b", "qwen3-4b", "qwen3-0.6b"]
MAIN = "qwen3-8b"
SIDES = [  # (side_name, column, requires_rainfall) — as in sic.main()
    ("Rainfall Metrics", "Rainfall Instrument", True),
    ("Endogenous Variables", "Endogenous Variable(s)", False),
]


STAGE_NOTE = ("Stages, in order: embed_only (embedding alone, not used for labels) -> rerank (reranker's "
              "highest-scoring category) -> model (validity check applied: P<0.5 sends to Other) -> "
              "final (hand review applied; used in the Sankeys).")

# (file, column, group, description, values) — one row per column of the two tables.
DATA_DICTIONARY = [
    ("entry_labels.csv", "side", "Identity",
     "Which side of the Sankey the entry belongs to.",
     "Rainfall Metrics | Endogenous Variables"),
    ("entry_labels.csv", "entry", "Identity",
     "The variable as extracted by a model, after text cleaning (lower-cased, normalized). One row per unique entry per side.",
     "text"),
    ("entry_labels.csv", "n_occurrences", "Source",
     "Total number of times the entry appears, summed over all runs. One run can report it for several papers.",
     "integer >= 1"),
    ("entry_labels.csv", "n_runs", "Source",
     "How many extraction runs reported the entry at least once.",
     "integer, 1 to number of runs"),
    ("entry_labels.csv", "runs", "Source",
     "Per-run counts, as run:count separated by semicolons. Run names are <full|test>_<model>: full = 3,755-paper "
     "corpus, test = 88-paper test set.",
     "e.g. full_sol:3; test_claude:1"),
    ("entry_labels.csv", "embed_only", "Label (Qwen3-8B)",
     "Category whose name and definition is closest to the entry by embedding cosine similarity. Comparison only; "
     "never used for the Sankeys. " + STAGE_NOTE,
     "a taxonomy category"),
    ("entry_labels.csv", "rerank", "Label (Qwen3-8B)",
     "Category with the highest reranker score, before the validity check. Never Other.",
     "a taxonomy category"),
    ("entry_labels.csv", "model", "Label (Qwen3-8B)",
     "Classifier output: the rerank category, or Other if validity_score < 0.5.",
     "a taxonomy category or Other (<side>)"),
    ("entry_labels.csv", "final", "Label (Qwen3-8B)",
     "Label after applying classifier_manual_review.csv. This is the label used in the Sankey figures.",
     "a taxonomy category or Other (<side>)"),
    ("entry_labels.csv", "manual_review", "Hand review",
     "Decision from classifier_manual_review.csv, if the entry is listed there.",
     "blank = not reviewed | keep = classifier label confirmed | override = category set by hand | other = sent to Other by hand"),
    ("entry_labels.csv", "manual_reason", "Hand review",
     "Note explaining the hand-review decision.",
     "text or blank"),
    ("entry_labels.csv", "embed_vs_rerank_differ", "Label (Qwen3-8B)",
     "Whether embed_only and rerank disagree, i.e. whether the reranker changed the embedding's choice.",
     "True | False"),
    ("entry_labels.csv", "embed_sim", "Score (Qwen3-8B)",
     "Cosine similarity between the entry and the embed_only category. Only meaningful relative to other categories "
     "for the same entry; not a probability.",
     "about 0.2 to 0.8 in practice"),
    ("entry_labels.csv", "rerank_score", "Score (Qwen3-8B)",
     "Reranker's P(yes) that the rerank category describes the entry: softmax of the model's 'yes' and 'no' "
     "next-token logits. Each category is scored independently, so scores across categories do not sum to 1. "
     "Not calibrated: a low score can still be the right category.",
     "0 to 1"),
    ("entry_labels.csv", "rerank_runner_up", "Score (Qwen3-8B)",
     "Category with the second-highest reranker score.",
     "a taxonomy category"),
    ("entry_labels.csv", "rerank_runner_up_score", "Score (Qwen3-8B)",
     "Reranker's P(yes) for the runner-up. A small gap to rerank_score means a close call between two categories.",
     "0 to 1"),
    ("entry_labels.csv", "validity_score", "Score (Qwen3-8B)",
     "Reranker's P(yes) that the entry names a real variable of the side's kind (sankey_taxonomy.VALID_DEFINITIONS). "
     "Below 0.5 the model label is Other.",
     "0 to 1"),
]
for _b in ["qwen3-4b", "qwen3-0.6b"]:
    for _stage in ["embed_only", "rerank", "model", "final"]:
        DATA_DICTIONARY.append((
            "entry_labels.csv", f"{_stage}_{_b}", f"Label ({_b}, robustness)",
            f"Same as {_stage}, using the {_b} embedder and reranker instead of 8B. Compare with {_stage} to see "
            f"whether the label depends on model size.",
            "a taxonomy category" + ("" if _stage in ("embed_only", "rerank") else " or Other (<side>)")))
DATA_DICTIONARY += [
    ("taxonomy.csv", "side", "Identity",
     "Which side of the Sankey the category belongs to.",
     "Rainfall Metrics | Endogenous Variables"),
    ("taxonomy.csv", "order", "Identity",
     "Position of the category in sankey_taxonomy.py. Other is last.",
     "integer"),
    ("taxonomy.csv", "category", "Identity",
     "Category name. These are the only labels the classifier can assign, plus Other.",
     "text"),
    ("taxonomy.csv", "definition", "Identity",
     "Definition the models compare entries against (the category is scored as '<category>: <definition>'). "
     "For Other, the definition of a valid entry used by the validity check.",
     "text"),
] + [
    ("taxonomy.csv", f"n_{kind}_{stage}", "Count (Qwen3-8B)",
     ("Number of unique entries" if kind == "entries" else "Number of entry occurrences (sum of n_occurrences)")
     + f" with this category in the {stage} column of entry_labels.csv. Comparing stages shows how each step "
     "changes the counts.",
     "integer")
    for stage in ["embed_only", "rerank", "model", "final"] for kind in ["entries", "occurrences"]
]


def write_data_dictionary() -> str:
    path = os.path.join(OUT_DIR, "data_dictionary.csv")
    pd.DataFrame(DATA_DICTIONARY, columns=["file", "column", "group", "description", "values"]).to_csv(path, index=False)
    return path


def entry_occurrences() -> dict[str, dict[str, Counter]]:
    """{side: {entry: Counter(run -> n occurrences)}} over all baseline runs."""
    occ = {side: defaultdict(Counter) for side, _, _ in SIDES}
    runs = [(full, "full", k, d) for k, d in full.BASELINES.items()] + \
           [(frontier, "test", k, d) for k, d in frontier.BASELINES.items()]
    for driver, kind, key, subdir in runs:
        driver.set_paths(key, subdir)
        if not os.path.exists(sic.MERGED_CSV):
            continue
        rain_df_raw = sic.load_rainfall_papers(sic.MERGED_CSV)
        for side, col, req in SIDES:
            exp, _ = sic.expand_column(rain_df_raw, col, requires_rainfall=req)
            for entry, n in exp["entry"].value_counts().items():
                occ[side][entry][f"{kind}_{key}"] += n
    return occ


def main():
    os.makedirs(OUT_DIR, exist_ok=True)
    occ = entry_occurrences()

    entry_frames = []
    for side, _, _ in SIDES:
        other = f"Other ({side})"
        entries = sorted(occ[side])
        df = pd.DataFrame({"side": side, "entry": entries})
        df["n_occurrences"] = [sum(occ[side][e].values()) for e in entries]
        df["n_runs"] = [len(occ[side][e]) for e in entries]
        df["runs"] = ["; ".join(f"{r}:{n}" for r, n in sorted(occ[side][e].items())) for e in entries]
        for b in BACKBONES:
            _, audit = flc.classify(entries, side, other, backbone=b)   # cache only
            a = audit.set_index("entry")
            s = "" if b == MAIN else f"_{b}"
            df[f"embed_only{s}"] = df["entry"].map(a["embed_top1"])
            df[f"rerank{s}"] = df["entry"].map(a["best_category"])
            df[f"model{s}"] = df["entry"].map(a["model_label"])
            df[f"final{s}"] = df["entry"].map(a["label"])
            if b == MAIN:
                df["embed_sim"] = df["entry"].map(a["embed_top1_sim"]).round(3)
                df["rerank_score"] = df["entry"].map(a["best_score"]).round(3)
                df["rerank_runner_up"] = df["entry"].map(a["top2"])
                df["rerank_runner_up_score"] = df["entry"].map(a["top2_score"]).round(3)
                df["validity_score"] = df["entry"].map(a["valid_score"]).round(3)
                df["manual_review"] = df["entry"].map(a["manual_review"])
        review = flc._load_manual_review(side)
        df["manual_reason"] = df["entry"].map(lambda e: review.get(e, {}).get("reason", ""))
        df["embed_vs_rerank_differ"] = df["embed_only"] != df["rerank"]
        entry_frames.append(df)
    entries_df = pd.concat(entry_frames, ignore_index=True)
    lead = ["side", "entry", "n_occurrences", "n_runs", "runs", "embed_only", "rerank", "model", "final",
            "manual_review", "manual_reason", "embed_vs_rerank_differ"]
    entries_df = entries_df[lead + [c for c in entries_df.columns if c not in lead]]
    entries_df.sort_values(["side", "n_occurrences", "entry"], ascending=[True, False, True], inplace=True)
    entries_path = os.path.join(OUT_DIR, "entry_labels.csv")
    entries_df.to_csv(entries_path, index=False)

    tax_rows = []
    for side, _, _ in SIDES:
        d = entries_df[entries_df["side"] == side]
        other = f"Other ({side})"
        labels = list(TAXONOMIES[side].items()) + [
            (other, f"{OTHER_DEFINITIONS[side]} (a valid entry is: {VALID_DEFINITIONS[side]})")]
        for i, (label, definition) in enumerate(labels, 1):
            row = {"side": side, "order": i, "category": label, "definition": definition}
            for stage in ["embed_only", "rerank", "model", "final"]:
                hit = d[stage] == label
                row[f"n_entries_{stage}"] = int(hit.sum())
                row[f"n_occurrences_{stage}"] = int(d.loc[hit, "n_occurrences"].sum())
            tax_rows.append(row)
    tax_path = os.path.join(OUT_DIR, "taxonomy.csv")
    pd.DataFrame(tax_rows).to_csv(tax_path, index=False)

    print(f"{tax_path}\n{entries_path} ({len(entries_df)} entries)\n{write_data_dictionary()}")


if __name__ == "__main__":
    main()
