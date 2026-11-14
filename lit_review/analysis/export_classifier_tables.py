"""
Writes two CSVs for reviewing the Sankey categorization (no models are run —
everything is read from the classifier cache, so run the classifier for every backbone first):

  <OneDrive>/weather_iv_lit/analysis/classifier/taxonomy.csv
      One row per allowed label (sankey_taxonomy.py / taxonomies/*.json), both
      sides, including Other and Unclassifiable, with its definition and how
      many unique entries / entry occurrences land in it under each stage of
      the pipeline, for each backbone (columns suffixed _<backbone>):
        embed_only  — embedding nearest label (no reranker; can be Other)
        rerank      — reranker's best label (no interpretability step; can be Other)
        model       — classifier output (interpretability step can send to Unclassifiable)
        final       — after classifier_manual_review.csv
      So comparing the count columns shows how each stage changes the story.

  <OneDrive>/weather_iv_lit/analysis/classifier/entry_labels.csv
      One row per unique cleaned entry: n_occurrences (total times it appears,
      summed over runs — one run can report it several times), n_runs (how
      many of the 9 baseline runs reported it at all), runs (per-run counts),
      the manual review decision/reason, then one block per backbone
      (qwen3-8b, qwen3-4b, qwen3-0.6b) with the same columns, each suffixed
      _<backbone>: every stage's label and all the scores.

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
from sankey_taxonomy import (CATEGORY_INFO, INTERPRETABLE_DEFINITIONS, OTHER_DEFINITIONS, TAXONOMIES,
                            UNCLASSIFIABLE_DEFINITIONS, other_label, unclassifiable_label)

OUT_DIR = "/Users/kieran/Library/CloudStorage/OneDrive-UniversityofArizona/weather_iv_lit/analysis/classifier"
BACKBONES = ["qwen3-8b", "qwen3-4b", "qwen3-0.6b"]
SIDES = [  # (side_name, column, requires_rainfall) — as in sic.main()
    ("Rainfall Metrics", "Rainfall Instrument", True),
    ("Endogenous Variables", "Endogenous Variable(s)", False),
]


STAGES = ["embed_only", "rerank", "model", "final"]
STAGE_NOTE = ("Stages, in order: embed_only (embedding alone, not used for labels) -> rerank (reranker's "
              "highest-scoring label, real category or Other) -> model (interpretability check applied: P<0.5 sends to "
              "Unclassifiable) -> "
              "final (hand review applied; used in the Sankeys).")

# Per-backbone columns of entry_labels.csv: (column, kind, description, values).
# Each appears once per backbone as <column>_<backbone>, e.g. rerank_score_qwen3-8b.
# Order: each score sits immediately before the label it produced (embed_sim -> embed_only,
# rerank_score -> rerank, validity_score -> model; final has no score).
BACKBONE_COLUMNS = [
    ("embed_sim", "Score",
     "Cosine similarity between the entry and the embed_only category. Only meaningful relative to other categories "
     "for the same entry; not a probability.",
     "about 0.2 to 0.8 in practice"),
    ("embed_only", "Label",
     "Category whose name and definition is closest to the entry by embedding cosine similarity. Comparison only; "
     "never used for the Sankeys. " + STAGE_NOTE,
     "a taxonomy category or Other (<side>)"),
    ("rerank_score", "Score",
     "Reranker's P(yes) that the rerank label describes the entry: softmax of the model's 'yes' and 'no' "
     "next-token logits. Each category is scored independently, so scores across categories do not sum to 1. "
     "Not calibrated: a low score can still be the right category.",
     "0 to 1"),
    ("rerank", "Label",
     "Label with the highest reranker score among the real categories and Other, before the interpretability "
     "check. Never Unclassifiable.",
     "a taxonomy category or Other (<side>)"),
    ("validity_score", "Score",
     "Reranker's P(yes) that the entry can be interpreted as a measure of the side's kind "
     "(sankey_taxonomy.INTERPRETABLE_DEFINITIONS). Below 0.5 the model label is Unclassifiable.",
     "0 to 1"),
    ("model", "Label",
     "Classifier output: the rerank label, or Unclassifiable if validity_score < 0.5.",
     "a taxonomy category, Other (<side>) or Unclassifiable (<side>)"),
    ("final", "Label",
     "Label after applying classifier_manual_review.csv. This is the label used in the Sankey figures "
     "for this backbone.",
     "a taxonomy category, Other (<side>) or Unclassifiable (<side>)"),
    ("embed_vs_rerank_differ", "Label",
     "Whether embed_only and rerank disagree, i.e. whether the reranker changed the embedding's choice.",
     "True | False"),
    ("rerank_runner_up_score", "Score",
     "Reranker's P(yes) for the runner-up. A small gap to rerank_score means a close call between two labels.",
     "0 to 1"),
    ("rerank_runner_up", "Score",
     "Label with the second-highest reranker score.",
     "a taxonomy category or Other (<side>)"),
    ("best_real_score", "Score",
     "Reranker's P(yes) for best_real_category.",
     "0 to 1"),
    ("best_real_category", "Score",
     "Real category with the highest reranker score, ignoring Other. Shows where an entry labelled Other or "
     "Unclassifiable would otherwise have gone.",
     "a taxonomy category"),
    ("other_score", "Score",
     "Reranker's P(yes) for Other. Other is the label when this beats every real category.",
     "0 to 1"),

]
# audit column -> entry_labels column, for the per-backbone columns read from the classifier audit.
AUDIT_COLUMNS = {
    "embed_top1": "embed_only", "best_category": "rerank", "model_label": "model", "label": "final",
    "embed_top1_sim": "embed_sim", "best_score": "rerank_score", "top2": "rerank_runner_up",
    "top2_score": "rerank_runner_up_score", "best_real_category": "best_real_category",
    "best_real_score": "best_real_score", "other_score": "other_score", "valid_score": "validity_score",
}

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
    ("entry_labels.csv", "manual_review", "Hand review",
     "Decision from classifier_manual_review.csv, if the entry is listed there. Applies to every backbone.",
     "blank = not reviewed | keep = classifier label confirmed | override = category set by hand | "
     "other = sent to Other by hand | unclassifiable = sent to Unclassifiable by hand"),
    ("entry_labels.csv", "manual_reason", "Hand review",
     "Note explaining the hand-review decision.",
     "text or blank"),
] + [
    ("entry_labels.csv", f"{col}_{b}", f"{kind} ({b})", desc, values)
    for b in BACKBONES for col, kind, desc, values in BACKBONE_COLUMNS
] + [
    ("taxonomy.csv", "side", "Identity",
     "Which side of the Sankey the category belongs to.",
     "Rainfall Metrics | Endogenous Variables"),
    ("taxonomy.csv", "order", "Identity",
     "Position of the category in the taxonomy JSON. Other and Unclassifiable are last.",
     "integer"),
    ("taxonomy.csv", "category", "Identity",
     "Category name. These are the only labels the classifier can assign.",
     "text"),
    ("taxonomy.csv", "jel_codes", "Identity",
     "JEL codes from the economic-concepts taxonomy (conceptual anchors only; not shown to the models).",
     "semicolon-separated codes or blank"),
    ("taxonomy.csv", "definition", "Identity",
     "Definition the models compare entries against (the category is scored as '<category>: <definition>'). "
     "For Unclassifiable, the taxonomy's definition followed by the definition of an interpretable entry used by "
     "the interpretability check (entries failing it are Unclassifiable).",
     "text"),
] + [
    ("taxonomy.csv", f"n_{kind}_{stage}_{b}", f"Count ({b})",
     ("Number of unique entries" if kind == "entries" else "Number of entry occurrences (sum of n_occurrences)")
     + f" with this category in the {stage}_{b} column of entry_labels.csv. Comparing stages shows how each step "
     "changes the counts; comparing backbones shows whether the counts depend on model size.",
     "integer")
    for b in BACKBONES for stage in STAGES for kind in ["entries", "occurrences"]
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
        entries = sorted(occ[side])
        df = pd.DataFrame({"side": side, "entry": entries})
        df["n_occurrences"] = [sum(occ[side][e].values()) for e in entries]
        df["n_runs"] = [len(occ[side][e]) for e in entries]
        df["runs"] = ["; ".join(f"{r}:{n}" for r, n in sorted(occ[side][e].items())) for e in entries]
        review = flc._load_manual_review(side)
        df["manual_review"] = df["entry"].map(lambda e: review[e]["decision"].strip().lower() if e in review else "")
        df["manual_reason"] = df["entry"].map(lambda e: review.get(e, {}).get("reason", ""))
        for b in BACKBONES:
            _, audit = flc.classify(entries, side, backbone=b)   # cache only
            a = audit.set_index("entry")
            for src, col in AUDIT_COLUMNS.items():
                df[f"{col}_{b}"] = df["entry"].map(a[src])
            df[f"embed_vs_rerank_differ_{b}"] = df[f"embed_only_{b}"] != df[f"rerank_{b}"]
        entry_frames.append(df)
    entries_df = pd.concat(entry_frames, ignore_index=True)
    columns = ["side", "entry", "n_occurrences", "n_runs", "runs", "manual_review", "manual_reason"] + [
        f"{col}_{b}" for b in BACKBONES for col, _, _, _ in BACKBONE_COLUMNS]
    entries_df = entries_df[columns]
    score_cols = [f"{col}_{b}" for b in BACKBONES for col, kind, _, _ in BACKBONE_COLUMNS
                  if kind == "Score" and col not in ("rerank_runner_up", "best_real_category")]
    entries_df[score_cols] = entries_df[score_cols].round(3)
    entries_df.sort_values(["side", "n_occurrences", "entry"], ascending=[True, False, True], inplace=True)
    entries_path = os.path.join(OUT_DIR, "entry_labels.csv")
    entries_df.to_csv(entries_path, index=False)

    tax_rows = []
    for side, _, _ in SIDES:
        d = entries_df[entries_df["side"] == side]
        labels = [(c, c, d) for c, d in TAXONOMIES[side].items()] + [
            (other_label(side), "Other", OTHER_DEFINITIONS[side]),
            (unclassifiable_label(side), "Unclassifiable",
             f"{UNCLASSIFIABLE_DEFINITIONS[side]} (an interpretable entry is: {INTERPRETABLE_DEFINITIONS[side]})")]
        for i, (label, name, definition) in enumerate(labels, 1):
            row = {"side": side, "order": i, "category": label, "definition": definition,
                   "jel_codes": "; ".join(CATEGORY_INFO[side][name].get("jel_codes", []))}
            for b in BACKBONES:
                for stage in STAGES:
                    hit = d[f"{stage}_{b}"] == label
                    row[f"n_entries_{stage}_{b}"] = int(hit.sum())
                    row[f"n_occurrences_{stage}_{b}"] = int(d.loc[hit, "n_occurrences"].sum())
            tax_rows.append(row)
    tax_path = os.path.join(OUT_DIR, "taxonomy.csv")
    pd.DataFrame(tax_rows).to_csv(tax_path, index=False)

    print(f"{tax_path}\n{entries_path} ({len(entries_df)} entries)\n{write_data_dictionary()}")


if __name__ == "__main__":
    main()
