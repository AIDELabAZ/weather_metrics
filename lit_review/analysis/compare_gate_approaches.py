"""
Compares two ways of deciding Unclassifiable (GATE_APPROACHES, default A vs C),
for each classifier size (GATE_SIZES, default 8B only):

  reranker  (approach A, "updated original"): the Qwen3 reranker answers
            "can this entry be interpreted?" (P(yes) >= 0.5).
  judge     (approach B): rules for near-certain junk (short codes,
            letter-digit codes, corrupted text), then a Qwen3 chat model of
            the same size answers the same question. Too strict.
  concept   (approach C): B's rules + a fixed bare-rainfall list, then the
            chat model is asked a field-neutral "recognizable concept or
            measure?" question.

The category choice (reranker argmax over the real categories + Other) is
identical under both approaches, so differences come only from the gate.
No hand review is applied (classifier_manual_review.csv doesn't exist for
the new taxonomy), so every label here is the classifier's own output.

Writes everything to <OneDrive>/weather_iv_lit/analysis/classifier/gate_comparison_<X>_vs_<Y>/
(gate_comparison/ for the original A-vs-B run):
  README.md               what each file is
  entry_comparison.csv    one row per unique entry: both approaches' labels and
                          scores for every size, side by side
  summary.csv             per side x size x approach: Other / Unclassifiable
                          shares, categories used, agreement between approaches
  transitions.csv         how entries move between category / Other /
                          Unclassifiable when switching from A to B
  category_counts.csv     entries per category, per approach and size
  size_agreement.csv      how often the three sizes agree, per approach
  data_dictionary.csv     every column of the CSVs above
  sankeys/<approach>_<size>/   one Sankey per extraction run (PNG + wide PNG),
                          with logs, audits and residual shares under details/

Usage (from lit_review/):
  DYLD_FALLBACK_LIBRARY_PATH=/opt/homebrew/lib python3 analysis/compare_gate_approaches.py [classify] [tables] [sankeys]
  (no argument = all three steps, in that order; models are only loaded for
  entries missing from the classifier cache)
"""

import itertools
import os
import shutil
import sys
import time

import pandas as pd

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import export_classifier_tables as ect
import fixed_label_classifier as flc
import sankey_frontier_baselines as frontier
import sankey_full_corpus_baselines as full
import sankey_iv_clustering as sic
from sankey_taxonomy import TAXONOMIES, other_label, unclassifiable_label

CLASSIFIER_DIR = "/Users/kieran/Library/CloudStorage/OneDrive-UniversityofArizona/weather_iv_lit/analysis/classifier"
ALL_APPROACHES = {"reranker": ("A", "A (updated original): reranker gate"),
                  "judge": ("B", "B: rules + chat-model judge gate"),
                  "concept": ("C", "C: rules + bare-rainfall list + field-neutral concept judge")}
# The two approaches compared and the sizes, overridable from the environment:
#   GATE_APPROACHES=reranker,judge GATE_SIZES=qwen3-0.6b,qwen3-4b,qwen3-8b reproduces the
#   original A-vs-B run (output folder gate_comparison/).
ACTIVE = os.environ.get("GATE_APPROACHES", "reranker,concept").split(",")
SIZES = os.environ.get("GATE_SIZES", "qwen3-8b").split(",")
APPROACHES = {g: ALL_APPROACHES[g][1] for g in ACTIVE}
LETTER = {g: ALL_APPROACHES[g][0] for g in ACTIVE}
OUT_DIR = os.path.join(CLASSIFIER_DIR, "gate_comparison" if ACTIVE == ["reranker", "judge"]
                       else "gate_comparison_" + "_vs_".join(LETTER[g] for g in ACTIVE))
OLD_REVIEW_CSV = os.path.join(HERE, "classifier_manual_review_old_taxonomy.csv")
SIDES = [s for s, _, _ in ect.SIDES]


def label_type(label: str, side: str) -> str:
    if label == other_label(side):
        return "Other"
    if label == unclassifiable_label(side):
        return "Unclassifiable"
    return "category"


# ─── Step 1: classify ─────────────────────────────────────────────────────
def classify_all(occ) -> dict:
    """{(side, size, gate): audit DataFrame indexed by entry}."""
    audits = {}
    for size in SIZES:
        for gate in APPROACHES:
            for side in SIDES:
                t = time.time()
                print(f"\n[{size} / {gate}] {side}: {len(occ[side])} entries", flush=True)
                _, audit = flc.classify(sorted(occ[side]), side, backbone=size, gate=gate)
                audits[(side, size, gate)] = audit.set_index("entry")
                print(f"  done in {time.time() - t:.0f}s", flush=True)
    return audits


# ─── Step 2: tables ───────────────────────────────────────────────────────
PER_SIZE_COLUMNS = [  # (column, description, values) — each is suffixed _<size>
    ("embed_sim", "Cosine similarity between the entry and embed_only. Relative only; not a probability.", "about 0.2 to 0.8"),
    ("embed_only", "Category closest to the entry by embedding similarity. Comparison only; not used for labels.",
     "a category or Other (<side>)"),
    ("rerank_score", "Reranker P(yes) for the rerank label. Same under both approaches.", "0 to 1"),
    ("rerank", "Highest-scoring label among the real categories and Other. Same under both approaches; it is the "
               "final label whenever the gate passes.", "a category or Other (<side>)"),
    ("rerank_runner_up_score", "Reranker P(yes) for the runner-up. A small gap to rerank_score is a close call.", "0 to 1"),
    ("rerank_runner_up", "Second-highest-scoring label.", "a category or Other (<side>)"),
    ("best_real_score", "Reranker P(yes) for best_real_category.", "0 to 1"),
    ("best_real_category", "Highest-scoring real category, ignoring Other: where an Other or Unclassifiable entry "
                           "would otherwise have gone.", "a category"),
    ("other_score", "Reranker P(yes) for Other.", "0 to 1"),
]
GATE_COLUMNS = {  # per active approach, suffixed _<size>
    "reranker": [
        ("reranker_gate_score", "Approach A: the reranker's P(yes) that the entry can be interpreted. Below 0.5 -> "
                                "Unclassifiable.", "0 to 1"),
        ("label_reranker", "Approach A label: rerank, or Unclassifiable if reranker_gate_score < 0.5.",
         "a category, Other (<side>) or Unclassifiable (<side>)")],
    "judge": [
        ("judge_gate_score", "Approach B: the chat model's P(yes) that the entry identifies a specific measure. "
                             "Below 0.5 -> Unclassifiable. Computed even when a rule fired.", "0 to 1"),
        ("label_judge", "Approach B label: Unclassifiable if a rule fired (rule_judge) or judge_gate_score < 0.5, "
                        "otherwise rerank.", "a category, Other (<side>) or Unclassifiable (<side>)")],
    "concept": [
        ("concept_gate_score", "Approach C: the chat model's P(yes) that the entry names a recognizable concept or "
                               "measure (field-neutral question). Below 0.5 -> Unclassifiable. Computed even when a "
                               "rule fired.", "0 to 1"),
        ("label_concept", "Approach C label: Unclassifiable if a rule fired (rule_concept) or concept_gate_score < "
                          "0.5, otherwise rerank.", "a category, Other (<side>) or Unclassifiable (<side>)")],
}
PER_SIZE_COLUMNS += [c for g in ACTIVE for c in GATE_COLUMNS[g]]
PER_SIZE_COLUMNS.append(("same_label", f"Whether the {' and '.join(LETTER[g] for g in ACTIVE)} labels are identical.",
                         "True | False"))


def build_entry_table(occ, audits) -> pd.DataFrame:
    old = pd.read_csv(OLD_REVIEW_CSV, dtype=str, keep_default_na=False) if os.path.exists(OLD_REVIEW_CSV) \
        else pd.DataFrame(columns=["side", "entry", "decision", "reason"])
    old = old.set_index(["side", "entry"])
    frames = []
    for side in SIDES:
        entries = sorted(occ[side])
        df = pd.DataFrame({"side": side, "entry": entries})
        df["n_occurrences"] = [sum(occ[side][e].values()) for e in entries]
        df["n_runs"] = [len(occ[side][e]) for e in entries]
        df["runs"] = ["; ".join(f"{r}:{n}" for r, n in sorted(occ[side][e].items())) for e in entries]
        for gate in ACTIVE:
            if gate != "reranker":
                df[f"rule_{gate}"] = [flc.gate_rule(e, side, gate) for e in entries]
        df["old_review_decision"] = [old["decision"].get((side, e), "") for e in entries]
        df["old_review_reason"] = [old["reason"].get((side, e), "") for e in entries]
        for size in SIZES:
            a = audits[(side, size, ACTIVE[0])]   # category columns are identical under every gate
            m = lambda frame, col: df["entry"].map(frame[col])
            df[f"embed_sim_{size}"] = m(a, "embed_top1_sim").round(3)
            df[f"embed_only_{size}"] = m(a, "embed_top1")
            df[f"rerank_score_{size}"] = m(a, "best_score").round(3)
            df[f"rerank_{size}"] = m(a, "best_category")
            df[f"rerank_runner_up_score_{size}"] = m(a, "top2_score").round(3)
            df[f"rerank_runner_up_{size}"] = m(a, "top2")
            df[f"best_real_score_{size}"] = m(a, "best_real_score").round(3)
            df[f"best_real_category_{size}"] = m(a, "best_real_category")
            df[f"other_score_{size}"] = m(a, "other_score").round(3)
            for gate in ACTIVE:
                g = audits[(side, size, gate)]
                df[f"{gate}_gate_score_{size}"] = m(g, "valid_score").round(3)
                df[f"label_{gate}_{size}"] = m(g, "label")
            df[f"same_label_{size}"] = df[f"label_{ACTIVE[0]}_{size}"] == df[f"label_{ACTIVE[1]}_{size}"]
        frames.append(df)
    out = pd.concat(frames, ignore_index=True)
    return out.sort_values(["side", "n_occurrences", "entry"], ascending=[True, False, True]).reset_index(drop=True)


def build_summaries(et: pd.DataFrame) -> dict[str, pd.DataFrame]:
    summary, transitions, counts, agreement = [], [], [], []
    for side in SIDES:
        d = et[et["side"] == side]
        tot_u, tot_o = len(d), int(d["n_occurrences"].sum())
        for size in SIZES:
            for gate in APPROACHES:
                lab = d[f"label_{gate}_{size}"]
                types = lab.map(lambda x: label_type(x, side))
                row = {"side": side, "size": size, "approach": APPROACHES[gate],
                       "n_unique_entries": tot_u, "n_occurrences": tot_o}
                for t in ["category", "Other", "Unclassifiable"]:
                    hit = types == t
                    row[f"n_unique_{t}"] = int(hit.sum())
                    row[f"pct_unique_{t}"] = round(100 * hit.sum() / max(tot_u, 1), 1)
                    row[f"pct_occurrences_{t}"] = round(100 * d.loc[hit, "n_occurrences"].sum() / max(tot_o, 1), 1)
                row["n_categories_used"] = int(lab[types == "category"].nunique())
                row["pct_same_label_as_other_approach"] = round(100 * d[f"same_label_{size}"].mean(), 1)
                summary.append(row)
            g1, g2 = ACTIVE
            ta = d[f"label_{g1}_{size}"].map(lambda x: label_type(x, side))
            tb = d[f"label_{g2}_{size}"].map(lambda x: label_type(x, side))
            for (a, b), g in d.groupby([ta, tb]):
                transitions.append({"side": side, "size": size, f"approach_{LETTER[g1]}_type": a,
                                    f"approach_{LETTER[g2]}_type": b,
                                    "n_unique": len(g), "n_occurrences": int(g["n_occurrences"].sum()),
                                    "examples": "; ".join(g["entry"].head(8))})
        for gate in APPROACHES:
            for s1, s2 in itertools.combinations(SIZES, 2):
                agreement.append({"side": side, "approach": APPROACHES[gate], "size_1": s1, "size_2": s2,
                                  "pct_same_label": round(100 * (d[f"label_{gate}_{s1}"] == d[f"label_{gate}_{s2}"]).mean(), 1)})
            all_same = d[[f"label_{gate}_{s}" for s in SIZES]].nunique(axis=1) == 1
            agreement.append({"side": side, "approach": APPROACHES[gate], "size_1": "all sizes", "size_2": "",
                              "pct_same_label": round(100 * all_same.mean(), 1)})
        for cat in list(TAXONOMIES[side]) + [other_label(side), unclassifiable_label(side)]:
            row = {"side": side, "category": cat}
            for gate in APPROACHES:
                for size in SIZES:
                    hit = d[f"label_{gate}_{size}"] == cat
                    row[f"n_unique_{gate}_{size}"] = int(hit.sum())
                    row[f"n_occurrences_{gate}_{size}"] = int(d.loc[hit, "n_occurrences"].sum())
            counts.append(row)
    return {"summary.csv": pd.DataFrame(summary), "transitions.csv": pd.DataFrame(transitions),
            "category_counts.csv": pd.DataFrame(counts), "size_agreement.csv": pd.DataFrame(agreement)}


def data_dictionary() -> pd.DataFrame:
    rows = [
        ("entry_comparison.csv", "side", "Rainfall Metrics or Endogenous Variables.", "text"),
        ("entry_comparison.csv", "entry", "Cleaned entry as extracted (one row per unique entry per side).", "text"),
        ("entry_comparison.csv", "n_occurrences", "Times the entry appears, summed over all extraction runs.", "integer"),
        ("entry_comparison.csv", "n_runs", "Number of extraction runs that reported the entry.", "integer"),
        ("entry_comparison.csv", "runs", "Per-run counts as run:count (full_ = 3,755-paper corpus, test_ = 88-paper test set).", "text"),
        *[("entry_comparison.csv", f"rule_{g}",
           f"Approach {LETTER[g]} rule that sends the entry straight to Unclassifiable (short code, letter-digit "
           f"code, corrupted text{', bare rainfall' if g == 'concept' else ''}), or blank. Same for every size.",
           "text or blank") for g in ACTIVE if g != "reranker"],
        ("entry_comparison.csv", "old_review_decision",
         "Reference only: decision from the hand review done against the OLD taxonomy (keep/other; 'other' then "
         "meant junk or non-variable). Not applied to any label here.", "keep | other | blank"),
        ("entry_comparison.csv", "old_review_reason", "Reference only: note from that old review.", "text or blank"),
    ]
    rows += [("entry_comparison.csv", f"{c}_<size>", d, v) for c, d, v in PER_SIZE_COLUMNS]
    rows += [
        ("summary.csv", "n_unique_<type> / pct_unique_<type>",
         "Unique entries labelled a real category, Other, or Unclassifiable, and their % of all unique entries.", "integer / %"),
        ("summary.csv", "pct_occurrences_<type>", "Same, weighted by n_occurrences (share of everything extracted).", "%"),
        ("summary.csv", "n_categories_used", "Number of distinct real categories assigned at least once.", "integer"),
        ("summary.csv", "pct_same_label_as_other_approach", "% of unique entries with the same label under both "
                                                            "approaches (same size).", "%"),
        ("transitions.csv", " / ".join(f"approach_{LETTER[g]}_type" for g in ACTIVE),
         "Label type under each approach.", "category | Other | Unclassifiable"),
        ("transitions.csv", "n_unique / n_occurrences / examples", "Entries with that pair of types; up to 8 examples "
                                                                   "(most frequent first).", "integer / text"),
        ("category_counts.csv", "n_unique_<approach>_<size> / n_occurrences_<approach>_<size>",
         "Entries (unique / weighted) with this label under the approach and size.", "integer"),
        ("size_agreement.csv", "pct_same_label", "% of unique entries with the same final label in both sizes (or all "
                                                 "three), within one approach.", "%"),
    ]
    return pd.DataFrame(rows, columns=["file", "column", "description", "values"])


APPROACH_NOTES = {
    "reranker": "the Qwen3 reranker decides whether an entry can be interpreted, by scoring it against a "
                "definition paragraph (in practice this measures topical resemblance).",
    "judge": "rules for near-certain junk, then a Qwen3 chat model of the same size is asked whether the name "
             "identifies a specific measure.",
    "concept": "the same junk rules, plus a fixed list of bare rainfall names (rainfall, precipitation, rainfall "
               "squared, ...) on the rainfall side, then a Qwen3 chat model is asked a field-neutral question: does "
               "the name refer to a recognizable concept or measure?",
}


def readme() -> str:
    g1, g2 = ACTIVE
    l1, l2 = LETTER[g1], LETTER[g2]
    return f"""# Gate comparison: {l1} vs {l2}

Generated by `analysis/compare_gate_approaches.py`. Labels are the classifier's own output, with no hand review.
Sizes: {", ".join(SIZES)}.

""" + "".join(f"- **{APPROACHES[g]}:** {APPROACH_NOTES[g]}\n" for g in ACTIVE) + f"""
Both approaches pick the category the same way: the reranker's best match among the real categories and Other.
They differ only in which entries are sent to Unclassifiable.

| File | What it is |
|---|---|
| entry_comparison.csv | Every unique entry, with each size's scores and labels under both approaches, side by side |
| summary.csv | Other / Unclassifiable shares and agreement, per side x size x approach |
| transitions.csv | How entries move between category / Other / Unclassifiable from {l1} to {l2} |
| category_counts.csv | Entries per category, per approach and size |
| size_agreement.csv | How consistent the three sizes are under each approach |
| data_dictionary.csv | Every column |
| sankeys/<approach>_<size>/ | One Sankey per extraction run (Other shown, Unclassifiable excluded); details/ has logs, audits and residual shares |

Suggested reading order: summary.csv, then transitions.csv, then entry_comparison.csv
(filter `same_label_<size>` = False to see only the entries where the approaches disagree).
"""


def write_tables(occ, audits) -> None:
    et = build_entry_table(occ, audits)
    et.to_csv(os.path.join(OUT_DIR, "entry_comparison.csv"), index=False)
    for name, df in build_summaries(et).items():
        df.to_csv(os.path.join(OUT_DIR, name), index=False)
    data_dictionary().to_csv(os.path.join(OUT_DIR, "data_dictionary.csv"), index=False)
    with open(os.path.join(OUT_DIR, "README.md"), "w", encoding="utf-8") as f:
        f.write(readme())
    print(f"\nTables -> {OUT_DIR} ({len(et)} entries)")


# ─── Step 3: Sankeys ──────────────────────────────────────────────────────
def run_sankeys() -> None:
    runs = [(full, "full", k, d) for k, d in full.BASELINES.items()] + \
           [(frontier, "test", k, d) for k, d in frontier.BASELINES.items()]
    for size in SIZES:
        for gate in APPROACHES:
            flc.BACKBONE, flc.GATE = size, gate
            folder = os.path.join(OUT_DIR, "sankeys", f"{gate}_{size}")
            # A and B are unchanged since the original A-vs-B run: reuse its Sankeys.
            earlier = os.path.join(CLASSIFIER_DIR, "gate_comparison", "sankeys", f"{gate}_{size}")
            if gate in ("reranker", "judge") and os.path.isdir(earlier) and os.path.abspath(earlier) != os.path.abspath(folder):
                shutil.copytree(earlier, folder, dirs_exist_ok=True)
                print(f"\n===== Sankeys {gate} / {size}: copied from {earlier} =====", flush=True)
                continue
            details = os.path.join(folder, "details")
            os.makedirs(details, exist_ok=True)
            for driver, kind, key, subdir in runs:
                driver.set_paths(key, subdir)          # sets the input CSV; outputs redirected below
                if not os.path.exists(sic.MERGED_CSV):
                    print(f"  skip (missing input): {sic.MERGED_CSV}")
                    continue
                stem = f"{kind}_{key}"
                sic.OUTPUT_PNG_ENDOG = os.path.join(folder, f"sankey_{stem}.png")
                sic.OUTPUT_PNG_WIDE_ENDOG = os.path.join(folder, f"sankey_{stem}_wide.png")
                sic.OUTPUT_HTML_ENDOG = os.path.join(details, f"sankey_{stem}.html")
                sic.OUTPUT_EPS_ENDOG = os.path.join(details, f"sankey_{stem}.eps")
                sic.CLUSTER_SUMMARY_ENDOG = os.path.join(details, f"cluster_summary_endog_{stem}.csv")
                sic.REJECTED_ENTRIES_CSV = os.path.join(details, f"rejected_entries_{stem}.csv")
                sic.RELATIONSHIPS_RAW_ENDOG_CSV = os.path.join(details, f"relationships_raw_endog_{stem}.csv")
                sic.RELATIONSHIPS_CATEGORIZED_ENDOG_CSV = os.path.join(details, f"relationships_categorized_endog_{stem}.csv")
                sic.CLASSIFIER_AUDIT_CSV = os.path.join(details, f"classifier_audit_{stem}.csv")
                print(f"\n===== Sankey {gate} / {size} / {stem} =====", flush=True)
                sic.main()


def main():
    steps = sys.argv[1:] or ["classify", "tables", "sankeys"]
    os.makedirs(OUT_DIR, exist_ok=True)
    occ = ect.entry_occurrences()
    audits = classify_all(occ) if {"classify", "tables"} & set(steps) else None
    if "tables" in steps:
        write_tables(occ, audits)
    if "sankeys" in steps:
        run_sankeys()


if __name__ == "__main__":
    main()
