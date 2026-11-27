"""
Head-to-head test: Qwen3-32B alone vs the embed -> rerank -> 32B pipeline.

Arms (all Qwen3-32B 4-bit MLX, same taxonomy JSONs, same decision rules, same bare-rainfall filter afterwards):
  solo              32B sees the taxonomy + entry name                    (= 32b_direct + the decision rules)
  pipeline          32B also sees the 8B embedder's top-5 categories with the 8B reranker's scores for them
  solo_context      solo + paper context (title, dependent variable, the paper's rainfall/endogenous variables)
  pipeline_context  pipeline + paper context
The suggestions are a hint, not a filter: the 32B may pick any category. The embedder and reranker score every
category including Other and Unclassifiable, so they can point at gibberish too. They see only the entry name.

Name-only arms run once per unique entry; context arms once per (entry, paper) pair. Paper context comes from the
first run (in RUNS order) that extracted that pair.

Writes to <OneDrive>/weather_iv_lit/analysis/classifier/:
  pipeline_test/      README.md, comparison_rainfall.csv, comparison_endogenous.csv (one row per entry-paper
                      pair, all arms side by side), summary.csv, agreement.csv
  32b_solo/, 32b_pipeline/, 32b_solo_context/, 32b_pipeline_context/
                      one folder per arm, laid out like 32b_direct/: entries_*.csv, README.md, sankeys/
  placements_by_iteration.csv
                      one row per entry: 8b, 32b_direct and each arm's placement in consecutive columns

Steps (from lit_review/analysis/), default all in order:
  DYLD_FALLBACK_LIBRARY_PATH=/opt/homebrew/lib python3 pipeline_comparison.py \
      [items] [suggest] [classify:<arm>,...] [tables] [folders[:<arm>,...]] [placements]
"""

import hashlib
import json
import os
import subprocess
import sys
from collections import Counter, defaultdict

import numpy as np
import pandas as pd

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import classifier_overview as co
import export_classifier_tables as ect
import fixed_label_classifier as flc
import llm_direct_overview as ldo
import sankey_full_corpus_baselines as full
import sankey_iv_clustering as sic
from sankey_taxonomy import unclassifiable_label

ARMS = ["solo", "pipeline", "solo_context", "pipeline_context"]
BACKBONE = "qwen3-8b"
TOP_K = 5
OUT_DIR = os.path.join(ldo.CLASSIFIER_ROOT, "pipeline_test")
WORK = os.path.join(HERE, ".pipeline_test")  # items, suggestions and the 32B cache (not committed)
CACHE = os.path.join(WORK, "llm_cache.json")
SUGGESTIONS = os.path.join(WORK, "suggestions.json")
SIDE_SHORT = {"Rainfall Metrics": "rainfall", "Endogenous Variables": "endogenous"}
CUT = lambda s, n: ("" if pd.isna(s) else " ".join(str(s).split()))[:n]


# ─── items ────────────────────────────────────────────────────────────────
def collect_pairs():
    """{side: {(entry, paper_key): {"runs": Counter, "context": str, "title": str}}}"""
    pairs = {side: {} for side, _, _ in ect.SIDES}
    for key, subdir in co.RUNS.items():
        full.set_paths(key, subdir)
        if not os.path.exists(sic.MERGED_CSV):
            continue
        df = pd.read_csv(sic.MERGED_CSV)
        df["paper_key"] = df["File Name"].map(sic.normalize_filename)
        rows = df.drop_duplicates("paper_key").set_index("paper_key")
        raw = sic.load_rainfall_papers(sic.MERGED_CSV)
        for side, col, req in ect.SIDES:
            exp, _ = sic.expand_column(raw, col, requires_rainfall=req)
            for (entry, pk), n in Counter(zip(exp.entry, exp.paper_idx)).items():
                rec = pairs[side].get((entry, pk))
                if rec is None:
                    p = rows.loc[pk]
                    rec = pairs[side][(entry, pk)] = {
                        "runs": Counter(), "title": CUT(p["Title"], 250),
                        "context": "\n".join([
                            f"Title: {CUT(p['Title'], 250)}",
                            f"Dependent variable(s): {CUT(p['Dependent Variable(s)'], 250)}",
                            f"Rainfall instrument(s): {CUT(p['Rainfall Instrument'], 350)}",
                            f"Endogenous variable(s): {CUT(p['Endogenous Variable(s)'], 350)}",
                        ])}
                rec["runs"][key] += n
    return pairs


def pair_id(entry, pk):
    return f"{entry}||{pk}"


def write_items(pairs, sugg) -> None:
    os.makedirs(WORK, exist_ok=True)
    arms = {a: {} for a in ARMS}
    for side, ps in pairs.items():
        entries = sorted({e for e, _ in ps})
        hints = {e: hint_text(sugg[side][e]) for e in entries}
        arms["solo"][side] = entries
        arms["pipeline"][side] = [{"id": e, "entry": e, "hints": hints[e]} for e in entries]
        arms["solo_context"][side] = [{"id": pair_id(e, pk), "entry": e, "context": r["context"]}
                                      for (e, pk), r in sorted(ps.items())]
        arms["pipeline_context"][side] = [{"id": pair_id(e, pk), "entry": e, "context": r["context"],
                                           "hints": hints[e]} for (e, pk), r in sorted(ps.items())]
    for a, d in arms.items():
        with open(os.path.join(WORK, f"items_{a}.json"), "w", encoding="utf-8") as f:
            json.dump(d, f, ensure_ascii=False)
    print("items:", {a: {SIDE_SHORT[s]: len(v) for s, v in d.items()} for a, d in arms.items()})


# ─── suggestions (8B embedder + reranker) ─────────────────────────────────
def category_docs(side):
    """Every category in the JSON, residuals included, as 'Name: description. Examples: ...'."""
    import llm_direct_classifier as ldc
    tax = ldc.load_taxonomy(side)
    names, docs = [], []
    for c in tax["categories"]:
        d = f"{c['category']}: {c['description'].strip().rstrip('.')}"
        if c.get("examples"):
            d += ". Examples: " + "; ".join(c["examples"])
        names.append(c["category"])
        docs.append(d)
    return names, docs


def suggest(pairs) -> dict:
    spec = flc.BACKBONES[BACKBONE]
    db = json.load(open(SUGGESTIONS)) if os.path.exists(SUGGESTIONS) else {}
    for side in pairs:
        names, docs = category_docs(side)
        ns = hashlib.sha256(json.dumps([BACKBONE, TOP_K, docs]).encode()).hexdigest()[:16]
        block = db.setdefault(side, {}).setdefault(ns, {})
        todo = sorted({e for e, _ in pairs[side]} - set(block))
        print(f"[{side}] suggestions: {len(todo)} entries to score")
        if todo:
            sim = flc._embed_similarities(spec, todo, docs, flc._embed_instruction(side))
            top = np.argsort(-sim, axis=1)[:, :TOP_K]
            jobs_pairs = [(e, docs[j]) for i, e in enumerate(todo) for j in top[i]]
            scores = flc._qwen3_rerank(spec["rerank_model"], [(jobs_pairs, flc._rerank_instruction(side))])[0]
            for i, e in enumerate(todo):
                cands = [{"category": names[j], "embed_sim": round(float(sim[i, j]), 3),
                          "rerank": round(float(scores[i * TOP_K + k]), 3)} for k, j in enumerate(top[i])]
                block[e] = sorted(cands, key=lambda c: -c["rerank"])
            os.makedirs(WORK, exist_ok=True)
            with open(SUGGESTIONS, "w", encoding="utf-8") as f:
                json.dump(db, f, ensure_ascii=False)
        db[side]["_current"] = ns
    return {side: db[side][db[side]["_current"]] for side in pairs}


def hint_text(cands) -> str:
    return "\n".join(f"{i}. {c['category']} (reranker {c['rerank']:.2f}, embedding {c['embed_sim']:.2f})"
                     for i, c in enumerate(cands, 1))


# ─── classify (32B, MLX venv) ─────────────────────────────────────────────
def classify(arms) -> None:
    for a in arms:
        print(f"\n===== 32B arm: {a} =====", flush=True)
        subprocess.run([ldo.MLX_PYTHON, os.path.join(HERE, "llm_direct_classifier.py"), "--rules",
                        "--entries", os.path.join(WORK, f"items_{a}.json"), "--cache", CACHE,
                        "--model", ldo.MODEL], check=True)


def arm_results(arm) -> dict:
    """{side: {id: result}} for an arm, matched to its namespace by the system prompt it would build."""
    import llm_direct_classifier as ldc
    if not os.path.exists(CACHE):
        return {}
    db = json.load(open(CACHE, encoding="utf-8"))
    out = {}
    for side in SIDE_SHORT:
        tax = ldc.load_taxonomy(side)
        sys_text = ldc.system_prompt(side, tax, rules=True, context="context" in arm, hints="pipeline" in arm)
        ns = f"{ldo.MODEL}|{ldc.PROMPT_VERSION}|" + hashlib.sha256(sys_text.encode()).hexdigest()[:16]
        out[side] = db.get(ns, {}).get("results", {})
    return out


# ─── tables ───────────────────────────────────────────────────────────────
def final(entry, r, side) -> str:
    return ldo.final_label(entry, r, side) if r else ""


def tables(pairs, sugg) -> None:
    os.makedirs(OUT_DIR, exist_ok=True)
    res = {a: arm_results(a) for a in ARMS}
    direct = {side: ldo.results(side) for side in SIDE_SHORT}
    summary, agree_rows = [], []
    for side, ps in pairs.items():
        pipe8 = pd.read_csv(os.path.join(ldo.PIPELINE_DIR, co.SIDE_FILES[side])).set_index("entry")["category"]
        n_entry = Counter()
        for (e, _), r in ps.items():
            n_entry[e] += sum(r["runs"].values())
        rows = []
        for (e, pk), r in sorted(ps.items()):
            pid = pair_id(e, pk)
            get = lambda a, key: res[a].get(side, {}).get(key, {})
            s, p = get("solo", e), get("pipeline", e)
            sc, pc = get("solo_context", pid), get("pipeline_context", pid)
            cands = sugg[side].get(e, [])
            rows.append({
                "entry": e, "paper": r["title"], "paper_key": pk,
                "pair_occurrences": sum(r["runs"].values()), "entry_occurrences": n_entry[e],
                "runs": "; ".join(f"{k}:{n}" for k, n in r["runs"].most_common()),
                "solo": final(e, s, side), "pipeline": final(e, p, side),
                "solo_context": final(e, sc, side), "pipeline_context": final(e, pc, side),
                "32b_direct": final(e, direct[side].get(e, {}), side),
                "8b_pipeline": pipe8.get(e, ""),
                "bare_rainfall_rule": ldo.rule_for(e, side),
                "reranker_top": ldo.side_label(cands[0]["category"], side) if cands else "",
                "suggestions": "; ".join(f"{c['category']} ({c['rerank']:.2f}/{c['embed_sim']:.2f})" for c in cands),
                "solo_reason": s.get("reason", ""), "pipeline_reason": p.get("reason", ""),
                "solo_context_reason": sc.get("reason", ""), "pipeline_context_reason": pc.get("reason", ""),
            })
        df = pd.DataFrame(rows)
        df["solo_vs_pipeline"] = np.where(df.solo == df.pipeline, "same", "DIFFERENT")
        df["solo_ctx_vs_pipeline_ctx"] = np.where(df.solo_context == df.pipeline_context, "same", "DIFFERENT")
        df = df.sort_values(["entry_occurrences", "entry", "pair_occurrences"], ascending=[False, True, False])
        df.to_csv(os.path.join(OUT_DIR, f"comparison_{SIDE_SHORT[side]}.csv"), index=False)

        w = df.pair_occurrences
        cols = ["solo", "pipeline", "solo_context", "pipeline_context", "32b_direct", "8b_pipeline", "reranker_top"]
        for c in cols:
            if (df[c] == "").all():
                continue
            share = w.groupby(df[c]).sum() / w.sum()
            for cat, v in share.items():
                summary.append({"side": side, "category": cat, "arm": c, "share": round(v, 4)})
        for i, a in enumerate(cols):
            for b in cols[i + 1:]:
                ok = (df[a] != "") & (df[b] != "")
                if ok.any():
                    agree_rows.append({"side": side, "a": a, "b": b,
                                       "agreement_share_of_occurrences": round((w[ok] * (df[a] == df[b])[ok]).sum()
                                                                               / w[ok].sum(), 3)})
        done = {c: int((df[c] != "").sum()) for c in ARMS}
        print(f"  {side}: {len(df)} pairs ({df.entry.nunique()} entries); rows filled per arm: {done}")
    s = pd.DataFrame(summary).pivot_table(index=["side", "category"], columns="arm", values="share", fill_value=0)
    s.to_csv(os.path.join(OUT_DIR, "summary.csv"))
    ag = pd.DataFrame(agree_rows)
    ag.to_csv(os.path.join(OUT_DIR, "agreement.csv"), index=False)
    print(ag[ag.a.isin(["solo", "solo_context"]) | ag.b.isin(["solo", "solo_context"])].to_string(index=False))
    with open(os.path.join(OUT_DIR, "README.md"), "w", encoding="utf-8") as f:
        f.write(README)


README = """# Pipeline test: Qwen3-32B alone vs embed -> rerank -> 32B

Generated by `analysis/pipeline_comparison.py`. Same entries as `../8b/` and `../32b_direct/` (full-corpus runs
including claude). Taxonomy: `analysis/taxonomies/*.json`.

## Arms (all Qwen3-32B, 4-bit, local)
| Column | What the 32B sees |
|---|---|
| solo | taxonomy + decision rules + entry name (= 32b_direct + the decision rules) |
| pipeline | solo + the 8B embedder's top-5 categories with the 8B reranker's score for each |
| solo_context | solo + paper context (title, dependent variable, the paper's rainfall and endogenous variables) |
| pipeline_context | pipeline + paper context |

The suggestions are evidence, not a filter: the 32B is told it may choose any category. The embedder and reranker
score every category, Other and Unclassifiable included, so they can flag gibberish too. Name-only arms run once
per unique entry (so all papers with the same entry get the same label); context arms once per entry-paper pair.

Decision rules given to the 32B in every arm:
1. Classify whenever reasonably possible: the most plausible substantive category, even when the precise
   construction is unknown.
2. Unclassifiable only for genuinely uninterpretable entries (x1, driving factor, corrupted text, content-free
   placeholders).
3. Other only as a last resort: interpretable but outside every substantive category.
4. (rainfall) "rainfall shock" -> Two-sided rainfall extremes unless the construction is clearly different.

After the model, every arm applies the bare-rainfall filter used in 32b_direct: "rainfall", "precipitation",
"rainfall squared", "rainfall (mm)", ... -> Unclassifiable (`fixed_label_classifier.BARE_RAINFALL`, flagged in
`bare_rainfall_rule`). Logged, lagged, dummy and period-specific rainfall are classified.

## Files
- `comparison_rainfall.csv`, `comparison_endogenous.csv`: one row per entry-paper pair. Final labels per arm, plus
  `32b_direct` and `8b_pipeline` for reference, `reranker_top` (the reranker's own first choice),
  `suggestions` (category (reranker score / embedding similarity), best first), each arm's one-line reason, and
  `solo_vs_pipeline` / `solo_ctx_vs_pipeline_ctx` = DIFFERENT where the two arms disagree.
  `pair_occurrences` = times this entry was extracted for this paper across the runs; `entry_occurrences` = total
  for the entry.
- `summary.csv`: category shares per arm (weighted by occurrences).
- `agreement.csv`: pairwise agreement between arms (share of occurrences with the same label).

## Reading it
Agreement is not accuracy: no arm here is ground truth. Use the DIFFERENT rows to pick the hand-labelled
validation sample; that is what decides which arm is better.
"""


# ─── per-arm folders + wide placement table ───────────────────────────────
ARM_FOLDERS = {"solo": "32b_solo", "pipeline": "32b_pipeline",
               "solo_context": "32b_solo_context", "pipeline_context": "32b_pipeline_context"}
PLACEMENTS_CSV = os.path.join(ldo.CLASSIFIER_ROOT, "placements_by_iteration.csv")


def arm_entry_labels(arm, side, pairs, res) -> dict[str, str]:
    """One label per entry. Context arms label each entry-paper pair; for an entry whose papers got different
    labels this returns the occurrence-weighted majority (used for Sankeys)."""
    r = res[arm].get(side, {})
    if "context" not in arm:
        return {e: final(e, r[e], side) for e in {e for e, _ in pairs[side]} if e in r}
    votes = defaultdict(Counter)
    for (e, pk), rec in pairs[side].items():
        x = r.get(pair_id(e, pk))
        if x:
            votes[e][final(e, x, side)] += sum(rec["runs"].values())
    return {e: v.most_common(1)[0][0] for e, v in votes.items()}


def arm_placement(arm, side, pairs, res) -> dict[str, str]:
    """Like arm_entry_labels, but a context-arm entry whose papers disagree shows every label with paper counts."""
    if "context" not in arm:
        return arm_entry_labels(arm, side, pairs, res)
    r = res[arm].get(side, {})
    papers = defaultdict(Counter)
    for (e, pk) in pairs[side]:
        x = r.get(pair_id(e, pk))
        if x:
            papers[e][final(e, x, side)] += 1
    return {e: (next(iter(c)) if len(c) == 1 else "; ".join(f"{lab} ({n} papers)" for lab, n in c.most_common()))
            for e, c in papers.items()}


ARM_README = """# {title}

Generated by `analysis/pipeline_comparison.py` (arm `{arm}`). Runs: {runs}. Taxonomy: `analysis/taxonomies/*.json`.
Comparison of all arms: `../pipeline_test/` and `../placements_by_iteration.csv`.

## What Qwen3-32B saw
{what}

Decision rules in the prompt: classify whenever reasonably possible; Unclassifiable only for genuinely
uninterpretable entries (x1, driving factor, corrupted text, content-free placeholders); Other only as a last resort;
(rainfall) "rainfall shock" -> Two-sided rainfall extremes unless the construction is clearly different.
After the model, the bare-rainfall filter ("rainfall", "precipitation", "rainfall squared", ... -> Unclassifiable)
is applied, as in `../32b_direct/`.

## Entry files
{rows}

| Column | Meaning |
|---|---|
| category | Final label (after the bare-rainfall filter) |
| 32b_category | The model's own choice |
| rule | "bare rainfall" when the filter overrode the model |
| category_prob | Model's probability of the category it wrote (near 1 almost always) |
| runner_up, reason | Model's second choice and one-sentence justification |
| suggestions | (pipeline arms) the 8B embedder's top 5 with reranker score / embedding similarity, best first |

## Sankeys
`sankeys/sankey_full_<run>.png` (+ `_wide.png`); Other shown, Unclassifiable excluded (share in
`sankeys/details/residual_shares_full_<run>.csv`).{sankey_note}
"""
ARM_WHAT = {
    "solo": "The taxonomy JSON, the decision rules, and the entry name. Nothing else (= 32b_direct + decision rules).",
    "pipeline": "As 32b_solo, plus the 8B embedder's 5 most similar categories with the 8B reranker's score for each "
                "(a hint; the model may choose any category).",
    "solo_context": "As 32b_solo, plus paper context: title, dependent variable(s), and the paper's extracted rainfall "
                    "and endogenous variables (from the first run that extracted this entry for this paper).",
    "pipeline_context": "As 32b_pipeline, plus the paper context described for 32b_solo_context.",
}


def write_arm_folders(pairs, sugg, arms, sankeys=True) -> None:
    res = {a: arm_results(a) for a in ARMS}
    for arm in arms:
        if not any(res[arm].get(s) for s in SIDE_SHORT):
            print(f"  skip {arm}: no results yet")
            continue
        out = os.path.join(ldo.CLASSIFIER_ROOT, ARM_FOLDERS[arm])
        os.makedirs(out, exist_ok=True)
        ctx = "context" in arm
        for side in SIDE_SHORT:
            r = res[arm].get(side, {})
            n_entry, runs_entry = Counter(), defaultdict(Counter)
            for (e, pk), rec in pairs[side].items():
                n_entry[e] += sum(rec["runs"].values())
                runs_entry[e].update(rec["runs"])
            keys = (sorted(pairs[side]) if ctx else [(e, None) for e in sorted(n_entry)])
            rows = []
            for e, pk in keys:
                x = r.get(pair_id(e, pk) if ctx else e)
                if not x:
                    continue
                row = {"entry": e}
                if ctx:
                    row["paper"] = pairs[side][(e, pk)]["title"]
                row.update({
                    "category": final(e, x, side), "32b_category": ldo.side_label(x["category"], side),
                    "rule": ldo.rule_for(e, side), "category_prob": x["category_prob"],
                    "runner_up": ldo.side_label(x["runner_up"], side), "reason": x["reason"],
                })
                if ctx:
                    rec = pairs[side][(e, pk)]
                    row["pair_occurrences"] = sum(rec["runs"].values())
                    row["entry_occurrences"] = n_entry[e]
                    row["runs"] = "; ".join(f"{k}:{n}" for k, n in rec["runs"].most_common())
                else:
                    row["n_occurrences"] = n_entry[e]
                    row["runs"] = "; ".join(f"{k}:{n}" for k, n in runs_entry[e].most_common())
                if "pipeline" in arm:
                    row["suggestions"] = "; ".join(f"{c['category']} ({c['rerank']:.2f}/{c['embed_sim']:.2f})"
                                                   for c in sugg[side].get(e, []))
                rows.append(row)
            df = pd.DataFrame(rows)
            if df.empty:
                print(f"  {arm} / {side}: no results yet")
                continue
            sort = (["entry_occurrences", "entry", "pair_occurrences"] if ctx else ["n_occurrences", "entry"])
            df.sort_values(sort, ascending=[False, True, False][:len(sort)]).to_csv(
                os.path.join(out, co.SIDE_FILES[side]), index=False)
        with open(os.path.join(out, "README.md"), "w", encoding="utf-8") as f:
            f.write(ARM_README.format(
                title=f"Qwen3-32B, arm {ARM_FOLDERS[arm]}", arm=arm, runs=", ".join(co.RUNS), what=ARM_WHAT[arm],
                rows=("One row per entry-paper pair (the model was asked once per paper), most frequent entry first."
                      if ctx else "One row per unique entry, most frequent first."),
                sankey_note=("\nThe Sankey code labels each unique entry once per run, so an entry whose papers got "
                             "different labels is drawn with its occurrence-weighted majority label." if ctx else "")))
        print(f"  {arm}: tables -> {out}")
        if sankeys:
            lab = {side: arm_entry_labels(arm, side, pairs, res) for side in SIDE_SHORT}

            def lookup(unique_entries, side_name, *a, **k):
                m = {e: lab[side_name].get(e, unclassifiable_label(side_name)) for e in unique_entries}
                return m, pd.DataFrame({"side": side_name, "entry": list(m), "label": list(m.values())})

            sic.fixed_label_classifier.classify = lookup
            # co.run_sankeys removes each EPS just before rewriting it (OneDrive "dataless" placeholder issue).
            co.OUT_DIR, co.BACKBONE, co.GATE = out, f"qwen3-32b-{arm}", "none"
            co.run_sankeys()


def write_placements(pairs) -> None:
    """One row per (side, entry): where each iteration placed it, in consecutive columns."""
    res = {a: arm_results(a) for a in ARMS}
    out = []
    for side in SIDE_SHORT:
        pipe8 = pd.read_csv(os.path.join(ldo.PIPELINE_DIR, co.SIDE_FILES[side])).set_index("entry")["category"]
        direct = ldo.results(side)
        n_entry = Counter()
        runs_by_entry = defaultdict(Counter)  # which extraction runs found the entry, and how often
        for (e, _), rec in pairs[side].items():
            n_entry[e] += sum(rec["runs"].values())
            runs_by_entry[e].update(rec["runs"])
        place = {a: arm_placement(a, side, pairs, res) for a in ARMS}
        for e in sorted(n_entry, key=lambda x: (-n_entry[x], x)):
            row = {"side": side, "entry": e, "n_occurrences": n_entry[e],
                   "runs": "; ".join(f"{r}:{n}" for r, n in
                                     sorted(runs_by_entry[e].items(), key=lambda x: (-x[1], x[0]))),
                   "8b_pipeline": pipe8.get(e, ""),
                   "32b_direct": final(e, direct.get(e, {}), side)}
            for a in ARMS:
                row[ARM_FOLDERS[a]] = place[a].get(e, "")
            labels = {row[c] for c in ["8b_pipeline", "32b_direct"] + [ARM_FOLDERS[a] for a in ARMS] if row[c]}
            row["n_distinct_placements"] = len(labels)
            out.append(row)
    pd.DataFrame(out).to_csv(PLACEMENTS_CSV, index=False)
    print(f"  placements -> {PLACEMENTS_CSV} ({len(out)} entries)")


def main():
    steps = sys.argv[1:] or ["items", "suggest", "classify:" + ",".join(ARMS), "tables", "folders", "placements"]
    pairs = collect_pairs()
    sugg = suggest(pairs)  # cached after the first run, so cheap
    for step in steps:
        if step == "items":
            write_items(pairs, sugg)
        elif step.startswith("classify:"):
            classify(step.split(":", 1)[1].split(","))
        elif step == "tables":
            tables(pairs, sugg)
        elif step.startswith("folders"):  # folders or folders:solo,pipeline ; folders-nosankey skips Sankeys
            arms = step.split(":", 1)[1].split(",") if ":" in step else ARMS
            write_arm_folders(pairs, sugg, arms, sankeys=not step.startswith("folders-nosankey"))
        elif step == "placements":
            write_placements(pairs)
    print(f"\nOutputs -> {OUT_DIR}")


if __name__ == "__main__":
    main()
