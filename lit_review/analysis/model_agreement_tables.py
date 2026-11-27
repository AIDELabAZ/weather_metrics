"""
Paper-level cross-implementation agreement (Table 3 of the paper) for the GPT-4.1
trio (zero-shot, RAG, SFT) and the same table for the frontier models
(GPT-6.1 Sol, Llama 4 Maverick, Gemma 4 26B, Claude Opus 5.5).

Sample (as in the published Table 3): every paper with a model-generated record,
i.e. the full-corpus run (papers/; the 3,753 filenames all runs share) plus the
87 papers of the common held-out evaluation set that are not already in it, 3,840
papers in all. Held-out records come from each model's test-set run
(test_baseline_<model>_output.csv); for the GPT trio from the September model-only
exports behind the published table. The 351 non-held-out human-reference papers
are not in these files.

Panels A-C follow the published table exactly (rainfall-IV = explicit "1";
exact-string agreement after lower-casing, whitespace collapse and sorting
semicolon-separated items; identical missing strings count as agreement).
Panel D is new: agreement on the 32B Solo taxonomy categories of the papers'
rainfall instruments and endogenous variables (sets of categories per paper).

Writes to <OneDrive>/weather_iv_lit/writing/tables/:
  table3_gpt_agreement.tex, table_frontier_agreement.tex
  agreement_statistics.csv     every number in both tables (long format)
  paper_level_<group>.csv      one row per paper: each model's rainfall-IV flag, normalized strings and categories

Usage (from lit_review/):
  DYLD_FALLBACK_LIBRARY_PATH=/opt/homebrew/lib python3 analysis/model_agreement_tables.py
"""

import itertools
import os
import re
import sys

import pandas as pd

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

ROOT = "/Users/kieran/Library/CloudStorage/OneDrive-UniversityofArizona/weather_iv_lit"
OUTPUT = os.path.join(ROOT, "output")
OUT = os.path.join(ROOT, "writing", "tables")
SEPT = os.path.join(ROOT, "analysis", "model_only_agreement_replication", "outputs")
SOLO = os.path.join(ROOT, "analysis", "classifier", "32b_solo")
N_CORPUS_SEPT = 3753  # September exports: rows 1-3753 corpus, then the 87 held-out papers

COLS = ["File Name", "Title", "DOI", "Empirical Analysis", "Dependent Variable(s)", "Endogeneity Problem",
        "Endogenous Variable(s)", "Instrumental Variable Used", "Instrumental Variable(s)",
        "Instrumental Variable Rainfall", "Rainfall Instrument"]

# key -> (label, full-corpus CSV, held-out source)
MODELS = {
    "gpt":     ("Zero-shot", "gpt/baseline/full_baseline_gpt_output.csv", ("sept", "baseline")),
    "rag_gpt": ("RAG", "gpt/rag/full_rag_gpt_output.csv", ("sept", "rag")),
    "sft_gpt": ("SFT", "gpt/sft/full_sft_gpt_output.csv", ("sept", "sft")),
    "sol":     ("GPT-6.1 Sol", "gpt/baseline_sol/full_baseline_sol_output.csv",
                ("test", "gpt/baseline_sol/test_baseline_sol_output.csv")),
    "llama":   ("Llama 4 Maverick", "llama/baseline/full_baseline_llama_output.csv",
                ("test", "llama/baseline/test_baseline_llama_output.csv")),
    "gemma":   ("Gemma 4 26B", "gemma/baseline/full_baseline_gemma_output.csv",
                ("test", "gemma/baseline/test_baseline_gemma_output.csv")),
    "claude":  ("Claude Opus 5.5", "claude/baseline/full_baseline_claude_output.csv",
                ("test", "claude/baseline/test_baseline_claude_output.csv")),
}
GROUPS = {
    "gpt": {"keys": ["gpt", "rag_gpt", "sft_gpt"], "tex": "gpt_agree.tex",
            "caption": "Cross-Implementation Agreement in Model-Labeled Rainfall-IV Records",
            "label": "gpt_agree", "noun": "implementation"},
    # GPT-4.1 SFT against the newest zero-shot model of each family; Panels C-D compare SFT with each of the others.
    "frontier": {"keys": ["sft_gpt", "sol", "gemma", "llama", "claude"], "reference": "sft_gpt",
                 "tex": "frontier_agree.tex",
                 "caption": "Cross-Model Agreement in Model-Labeled Rainfall-IV Records",
                 "label": "frontier_agree", "noun": "model"},
}
# Column headers of the frontier table (two lines each) and short names for its comparison columns.
HEAD = {"sft_gpt": r"GPT-4.1\\SFT", "sol": r"GPT-6.1\\Sol", "gemma": r"Gemma 4\\26B", "llama": r"Llama 4\\Maverick",
        "claude": r"Claude\\Opus 5.5"}
SHORT = {"gpt": "Zero-shot", "rag_gpt": "RAG", "sft_gpt": "SFT", "sol": "Sol", "gemma": "Gemma", "llama": "Llama",
         "claude": "Claude"}
NUM = ["one", "two", "three", "four", "five", "six"]
# Published Table 3 (GPT trio), used to check the rebuild.
PUBLISHED = {"n": 3840, "pos": [160, 168, 187], "unique": [9, 14, 35], "union": 218, "all": 137,
             "exact": {2: 23, 1: 58},
             "C": {"Dependent variable(s)": [57, 6, 7, 5], "Endogenous variable(s)": [67, 44, 48, 37],
                   "Rainfall instrument(s)": [67, 30, 28, 24],
                   "Rainfall instrument and endogenous variable lists": [36, 14, 10, 8]}}

STRING_ROWS = {"Dependent variable(s)": ["Dependent Variable(s)"],
               "Endogenous variable(s)": ["Endogenous Variable(s)"],
               "Rainfall instrument(s)": ["Rainfall Instrument"],
               "Rainfall instrument and endogenous variable lists": ["Rainfall Instrument", "Endogenous Variable(s)"]}
CATEGORY_ROWS = {"Rainfall instrument categories": ["rain_cats"],
                 "Endogenous variable categories": ["endog_cats"],
                 "Both category sets": ["rain_cats", "endog_cats"]}


def read(path: str) -> pd.DataFrame:
    df = pd.read_csv(path, dtype=str, keep_default_na=False)
    df.columns = [c.replace(".", " ").replace("Variable s ", "Variable(s)").strip() for c in df.columns]
    df = df.rename(columns={"Dependent Variable s": "Dependent Variable(s)",
                            "Endogenous Variable s": "Endogenous Variable(s)",
                            "Instrumental Variable s": "Instrumental Variable(s)"})
    df["File Name"] = df["File Name"].str.strip()
    return df[COLS]


def load(key: str) -> pd.DataFrame:
    _, full, (kind, src) = MODELS[key]
    corpus = read(os.path.join(OUTPUT, full))
    held = (read(os.path.join(SEPT, f"{src}_model_corpus.csv")).iloc[N_CORPUS_SEPT:] if kind == "sept"
            else read(os.path.join(OUTPUT, src)))
    df = pd.concat([corpus, held[~held["File Name"].isin(corpus["File Name"])]])
    return df.drop_duplicates("File Name").set_index("File Name")


def norm(s: str) -> str:
    items = [" ".join(p.split()) for p in re.sub(r"\s+", " ", s.lower()).strip().split(";")]
    return "; ".join(sorted(i for i in items if i))


# Each paper is counted once (the paper's sample, also used by model_sankeys.py). The 3,840 filenames include 19
# papers stored twice under DOI filenames that differ only in punctuation (10.1016_j.jue... / 10.1016j.jue...): 13
# have one copy in the corpus and one in the held-out set, 6 are doubled within the corpus; the corpus copy (else
# the first filename) is kept. AGREEMENT_ORIGINAL_SAMPLE=1 instead keeps all 3,840 filenames, as the published
# Table 3 did, and writes *_original_sample outputs.
DEDUPE = os.environ.get("AGREEMENT_ORIGINAL_SAMPLE") != "1"
SUFFIX = "" if DEDUPE else "_original_sample"


def dedupe(files: list[str]) -> list[str]:
    import sankey_iv_clustering as sic
    corpus = set(read(os.path.join(OUTPUT, MODELS["gpt"][1]))["File Name"])
    best = {}
    for f in sorted(files, key=lambda f: (f not in corpus, f)):
        best.setdefault(sic.normalize_filename(f), f)
    return sorted(best.values())


SIDES = ["Rainfall Metrics", "Endogenous Variables"]
SOLO_ITEMS = os.path.join(HERE, ".pipeline_test", "items_solo_heldout.json")


def solo_labels() -> dict[str, dict[str, str]]:
    """{side: {entry: final 32B Solo label}} from the pipeline_comparison cache (corpus + held-out entries)."""
    import pipeline_comparison as pc
    res = pc.arm_results("solo")
    return {side: {e: pc.final(e, r, side) for e, r in res.get(side, {}).items()} for side in SIDES}


def classify_missing(missing: dict[str, set]) -> None:
    """Run the 32B Solo arm (local MLX, same prompt and cache as pipeline_comparison) on unlabelled entries."""
    import json
    import subprocess
    import llm_direct_overview as ldo
    import pipeline_comparison as pc
    with open(SOLO_ITEMS, "w", encoding="utf-8") as f:
        json.dump({side: sorted(missing[side]) for side in SIDES}, f, ensure_ascii=False)
    print(f"  classifying {sum(map(len, missing.values()))} entries with 32B Solo ...", flush=True)
    subprocess.run([ldo.MLX_PYTHON, os.path.join(HERE, "llm_direct_classifier.py"), "--rules",
                    "--entries", SOLO_ITEMS, "--cache", pc.CACHE, "--model", ldo.MODEL], check=True)


def expand_papers(df: pd.DataFrame):
    """Rainfall-IV papers of one model, split into entries the way the Sankeys do. Returns (raw, {side: exp})."""
    import sankey_iv_clustering as sic
    import tempfile
    src = df.reset_index()[["File Name", "Title", "Rainfall Instrument", "Endogenous Variable(s)"]].copy()
    # the Sankey loader keeps rows whose flag is numerically 1
    src["Instrumental Variable Rainfall"] = (df["Instrumental Variable Rainfall"].str.strip() == "1").astype(int).values
    with tempfile.TemporaryDirectory() as tmp:
        p = os.path.join(tmp, "in.csv")
        src.to_csv(p, index=False)
        raw = sic.load_rainfall_papers(p)  # indexed by sic.normalize_filename(File Name)
    exps = {side: sic.expand_column(raw, col, requires_rainfall=req)[0]
            for side, col, req in [("Rainfall Metrics", "Rainfall Instrument", True),
                                   ("Endogenous Variables", "Endogenous Variable(s)", False)]}
    return src, exps


def categories(frames: dict[str, pd.DataFrame]) -> None:
    """Add rain_cats / endog_cats: the sorted set of 32B Solo categories of each paper's entries."""
    import sankey_iv_clustering as sic
    lookup = solo_labels()
    expanded = {k: expand_papers(df)[1] for k, df in frames.items()}
    missing = {side: set().union(*[set(e[side]["entry"]) for e in expanded.values()]) - set(lookup[side])
               for side in SIDES}
    if any(missing.values()):
        classify_missing(missing)
        lookup = solo_labels()
    for key, df in frames.items():
        keys = df.index.map(sic.normalize_filename)
        for side, out in [("Rainfall Metrics", "rain_cats"), ("Endogenous Variables", "endog_cats")]:
            exp = expanded[key][side]
            lab = exp["entry"].map(lookup[side])
            assert lab.notna().all(), f"{key}/{side}: unlabelled entries remain"
            cats = exp.assign(cat=lab).groupby("paper_idx")["cat"].agg(lambda c: "; ".join(sorted(set(c))))
            df[out] = pd.Series(keys.map(cats), index=df.index).fillna("")


def stats(group: str, frames: dict[str, pd.DataFrame]) -> tuple[dict, pd.DataFrame]:
    keys = GROUPS[group]["keys"]
    universe = sorted(set.intersection(*[set(frames[k].index) for k in keys]))
    for k in keys:
        assert len(frames[k]) == len(universe), f"{k}: {len(frames[k])} papers vs {len(universe)} in common"
    pos = {k: set(frames[k].index[frames[k]["Instrumental Variable Rainfall"].str.strip() == "1"]) for k in keys}
    union = set.union(*pos.values())
    n_pos = {f: sum(f in pos[k] for k in keys) for f in union}
    core = sorted(f for f, c in n_pos.items() if c == len(keys))
    s = {"n": len(universe), "keys": keys,
         "pos": [len(pos[k]) for k in keys],
         "unique": [len(pos[k] - set.union(set(), *[pos[j] for j in keys if j != k])) for k in keys],
         "union": len(union), "all": len(core),
         "exact": {c: sum(v == c for v in n_pos.values()) for c in range(1, len(keys))}}
    ref = GROUPS[group].get("reference")
    combos = ([[ref, k] for k in keys if k != ref] if ref else
              [list(p) for p in itertools.combinations(keys, 2)] + [keys])
    s["combos"] = combos

    def agree(cols, transform):
        out = []
        for combo in combos:
            vals = [frames[k].loc[core, cols].apply(lambda r: tuple(transform(x) for x in r), axis=1) for k in combo]
            out.append(int(sum(all(v.iloc[i] == vals[0].iloc[i] for v in vals[1:]) for i in range(len(core)))))
        return out

    s["C"] = {row: agree(cols, norm) for row, cols in STRING_ROWS.items()}
    s["D"] = {row: agree(cols, str) for row, cols in CATEGORY_ROWS.items()}

    paper = pd.DataFrame(index=universe)
    for k in keys:
        f = frames[k]
        paper[f"{k}_rainfall_iv"] = (f.loc[universe, "Instrumental Variable Rainfall"].str.strip() == "1").astype(int)
        for c, short in [("Dependent Variable(s)", "dependent"), ("Endogenous Variable(s)", "endogenous"),
                         ("Rainfall Instrument", "rainfall_instrument")]:
            paper[f"{k}_{short}"] = f.loc[universe, c].map(norm)
        paper[f"{k}_rainfall_categories"] = f.loc[universe, "rain_cats"]
        paper[f"{k}_endogenous_categories"] = f.loc[universe, "endog_cats"]
    paper.insert(0, "n_models_rainfall_iv", paper[[f"{k}_rainfall_iv" for k in keys]].sum(axis=1))
    paper.index.name = "file_name"
    return s, paper


def check_published(s: dict) -> None:
    ok = all([s["n"] == PUBLISHED["n"], s["pos"] == PUBLISHED["pos"], s["unique"] == PUBLISHED["unique"],
              s["union"] == PUBLISHED["union"], s["all"] == PUBLISHED["all"],
              all(s["exact"][c] == v for c, v in PUBLISHED["exact"].items()), s["C"] == PUBLISHED["C"]])
    print("  GPT trio reproduces the published Table 3 (Panels A-C):", "YES" if ok else "NO")
    if not ok:
        print("   ", {k: s[k] for k in ("n", "pos", "unique", "union", "all", "exact", "C")})


def pct(x, n):
    return f"{100 * x / n:.1f}"


NOTE_COMMON = (r"Panel A counts explicit rainfall-IV labels of 1; all other codes are not counted as positive. ")
NOTE_STRINGS = (r"In Panel C, strings are lowercased, whitespace is standardized, and semicolon-separated lists are "
                r"sorted without removing repeated items. Missing-value strings remain literal and count as agreement "
                r"when identical. Exact-string disagreement need not imply disagreement in meaning. Panel D reports "
                r"agreement after assigning variables to the categories defined in Appendix~\ref{app:class}. "
                r"Agreement requires identical sets of categories, including the residual categories Other and "
                r"Unclassifiable. ")


def dup_sentence() -> str:
    return (" Papers stored under two filenames that differ only in DOI punctuation are counted once." if DEDUPE else
            " Nineteen papers are stored under two filenames that differ only in DOI punctuation and are counted "
            "under each.")


def sample_noun() -> str:
    return "unique papers" if DEDUPE else "unique filenames"


def write_tex(group: str, s: dict) -> None:
    (write_tex_frontier if GROUPS[group].get("reference") else write_tex_gpt)(group, s)
    print(f"  table -> {os.path.join(OUT, GROUPS[group]['tex'].replace('.tex', f'{SUFFIX}.tex'))}")


def _save(group: str, lines: list[str]) -> None:
    with open(os.path.join(OUT, GROUPS[group]["tex"].replace(".tex", f"{SUFFIX}.tex")), "w") as f:
        f.write("\n".join(lines) + "\n")


def write_tex_gpt(group: str, s: dict) -> None:
    """Table 3 layout (threeparttable): pairwise comparisons plus all three."""
    g, keys, n, m = GROUPS[group], s["keys"], s["n"], len(s["keys"])
    lab = [MODELS[k][0] for k in keys]
    noun, nouns, word = g["noun"], g["noun"] + "s", NUM[m - 1]
    heads = ["--".join(SHORT[k] for k in c) if len(c) < m else f"All {word}" for c in s["combos"]]
    ncol = len(heads) + 1
    pad = " &" * (ncol - 1 - m)
    half, rest = (ncol - 1) // 2, ncol - 1 - (ncol - 1) // 2
    L = [r"\begin{table}[!htbp]", r"	\centering", rf"	\caption{{{g['caption']}}}",
         rf"	\label{{{g['label']}{SUFFIX}}}", r"	\begin{threeparttable}", r"		\footnotesize",
         r"		\setlength{\tabcolsep}{5pt}", r"		\renewcommand{\arraystretch}{1.18}", "",
         rf"		\begin{{tabular}}{{l{'r' * (ncol - 1)}}}", r"			\toprule", "",
         rf"			\multicolumn{{{ncol}}}{{l}}{{\textit{{Panel A: Rainfall-IV identification}}}} \\",
         r"			\addlinespace[2pt]", "				& " + " & ".join(lab) + pad + r" \\", r"			\midrule",
         "			Rainfall-IV papers & " + " & ".join(map(str, s["pos"])) + pad + r" \\",
         r"			Share of common model-labeled corpus (\%) & "
         + " & ".join(f"{100 * p / n:.2f}" for p in s["pos"]) + pad + r" \\",
         f"			Unique to {noun} & " + " & ".join(map(str, s["unique"])) + pad + r" \\", "",
         r"			\addlinespace[8pt]",
         rf"			\multicolumn{{{ncol}}}{{l}}{{\textit{{Panel B: Cross-{noun} overlap in rainfall-IV identification}}}} \\",
         r"			\addlinespace[2pt]",
         rf"				& \multicolumn{{{half}}}{{c}}{{Papers}} & \multicolumn{{{rest}}}{{c}}{{Share of union (\%)}} \\",
         r"			\midrule"]
    for name, v in panel_b_rows(s, noun, nouns):
        L.append(rf"			{name} & \multicolumn{{{half}}}{{c}}{{{v}}} & \multicolumn{{{rest}}}{{c}}{{{pct(v, s['union'])}}} \\")
    for p, title in (("C", "Exact"), ("D", "Category")):
        L += ["", r"			\addlinespace[8pt]",
              rf"			\multicolumn{{{ncol}}}{{l}}{{\textit{{Panel {p}: {title} agreement conditional on rainfall-IV "
              r"identification}} \\", r"			\addlinespace[2pt]",
              "				& " + " & ".join(heads) + r" \\", r"			\midrule"]
        L += [f"			{name} & " + " & ".join(f"{v} ({pct(v, s['all'])})" for v in vals) + r" \\"
              for name, vals in s[p].items()]
    L += ["", r"			\bottomrule", r"		\end{tabular}", "", r"		\begin{tablenotes}[flushleft]", r"			\footnotesize",
          rf"			\item \textit{{Note:}} The sample contains {n:,} {sample_noun()} with model-generated labels from "
          rf"all {word} {nouns}: the full-corpus extraction plus the papers of the common held-out evaluation set. "
          r"The non-held-out human-reference records are not included. " + NOTE_COMMON
          + rf"Panel B reports overlap among the {s['union']} papers labeled positive by at least one {noun}. "
          rf"Panels C and D report agreement among the {s['all']} papers labeled positive by all {word}, with "
          r"percentages of that sample in parentheses. " + NOTE_STRINGS
          + r"The last row of each panel requires agreement on both rainfall instruments and endogenous variables, "
          r"not their within-paper pairings." + dup_sentence(),
          r"		\end{tablenotes}", r"	\end{threeparttable}", r"\end{table}"]
    _save(group, L)


def panel_b_rows(s: dict, noun: str, nouns: str) -> list[tuple[str, int]]:
    m = len(s["keys"])
    rows = [(f"Identified by at least one {noun}", s["union"]), (f"Identified by all {NUM[m - 1]}", s["all"])]
    rows += [(f"Identified by exactly {NUM[c - 1]}", s["exact"][c]) for c in range(m - 1, 0, -1)]
    return rows + [(f"Any disagreement across {nouns}", s["union"] - s["all"])]


def write_tex_frontier(group: str, s: dict) -> None:
    """Frontier layout (minipage, two tabulars): GPT-4.1 SFT compared with each other model in Panels C-D."""
    g, keys, n, m = GROUPS[group], s["keys"], s["n"], len(s["keys"])
    ref = g["reference"]
    others = [k for k in keys if k != ref]
    word = NUM[m - 1]
    w_a = 0.60 / m  # Panel A/B model columns share 60% of the width; the label column takes 40%
    w_c = 0.60 / len(others)
    half, rest = m // 2, m - m // 2
    mc = lambda span, text: rf"\multicolumn{{{span}}}{{@{{}}c@{{}}}}{{{text}}}"
    share_head = r"Share of union (\%)"
    L = [r"\begin{table}[!htbp]", r"    \centering", rf"    \caption{{{g['caption']}}}",
         rf"    \label{{{g['label']}{SUFFIX}}}", r"    \begin{minipage}{\linewidth}", r"        \footnotesize",
         r"        \setlength{\tabcolsep}{4pt}", r"        \renewcommand{\arraystretch}{1.00}",
         r"        \setlength{\parskip}{0pt}", "",
         rf"        \noindent\begin{{tabular}}{{@{{}}p{{0.40\linewidth}}*{{{m}}}{{@{{}}>{{\centering\arraybackslash}}"
         rf"p{{{w_a:.2f}\linewidth}}}}@{{}}}}",
         r"            \toprule", "",
         rf"            \multicolumn{{{m + 1}}}{{@{{}}l@{{}}}}{{\textit{{Panel A: Rainfall-IV identification}}}} \\",
         r"            \addlinespace[1pt]"]
    L += ["                & " + "\n                & ".join(rf"\shortstack[c]{{{HEAD[k]}}}" for k in keys) + r" \\",
          r"            \midrule",
          "            Rainfall-IV papers & " + " & ".join(map(str, s["pos"])) + r" \\",
          r"            Share of common model-labeled corpus (\%) & "
          + " & ".join(f"{100 * p / n:.2f}" for p in s["pos"]) + r" \\",
          "            Unique to model & " + " & ".join(map(str, s["unique"])) + r" \\", "",
          r"            \addlinespace[4pt]",
          rf"            \multicolumn{{{m + 1}}}{{@{{}}l@{{}}}}{{\textit{{Panel B: Cross-model overlap in rainfall-IV "
          r"identification}} \\", r"            \addlinespace[1pt]",
          f"                & {mc(half, 'Papers')} & {mc(rest, share_head)} " + r"\\", r"            \midrule"]
    L += [f"            {name} & {mc(half, v)} & {mc(rest, pct(v, s['union']))} " + r"\\"
          for name, v in panel_b_rows(s, "model", "models")]
    L += ["", r"        \end{tabular}\par\vspace{4pt}",
          rf"        \noindent\begin{{tabular}}{{@{{}}p{{0.40\linewidth}}*{{{len(others)}}}{{@{{}}>{{\centering"
          rf"\arraybackslash}}p{{{w_c:.2f}\linewidth}}}}@{{}}}}"]
    heads = " & ".join(f"{SHORT[ref]}--{SHORT[k]}" for k in others)
    for i, (p, title) in enumerate((("C", "Exact"), ("D", "Category"))):
        L += ([] if i == 0 else ["", r"            \addlinespace[4pt]"])
        L += [rf"            \multicolumn{{{len(others) + 1}}}{{@{{}}l@{{}}}}{{\textit{{Panel {p}: {title} agreement "
              r"conditional on rainfall-IV identification}} \\", r"            \addlinespace[1pt]",
              f"                & {heads} " + r"\\", r"            \midrule"]
        L += [f"            {name} & " + " & ".join(f"{v} ({pct(v, s['all'])})" for v in vals) + r" \\"
              for name, vals in s[p].items()]
    L += ["", r"            \bottomrule", r"        \end{tabular}", "", r"        \par\smallskip", r"        \footnotesize",
          r"        \raggedright",
          rf"        \noindent\textit{{Note:}} The sample contains {n:,} {sample_noun()} with model-generated labels from "
          rf"all {word} models: the full-corpus extraction plus the papers of the common held-out evaluation set. "
          r"The non-held-out "
          r"human-reference records are not included. " + NOTE_COMMON
          + rf"Panel B reports overlap among the {s['union']} papers labeled positive by at least one model. Panels C "
          rf"and D compare GPT-4.1 SFT to each of the {NUM[len(others) - 1]} other models among the {s['all']} papers "
          rf"labeled positive by all {word}, with percentages of that sample in parentheses. " + NOTE_STRINGS
          + r"The last row of Panels C and D requires agreement on both rainfall instruments and endogenous "
          r"variables, not their within-paper pairings." + dup_sentence(),
          r"    \end{minipage}", r"\end{table}"]
    _save(group, L)


def long_stats(group: str, s: dict) -> list[dict]:
    rows = [{"table": group, "panel": "A", "statistic": "papers in sample", "comparison": "", "value": s["n"]}]
    for k, p, u in zip(s["keys"], s["pos"], s["unique"]):
        lab = MODELS[k][0]
        rows += [{"table": group, "panel": "A", "statistic": "rainfall-IV papers", "comparison": lab, "value": p},
                 {"table": group, "panel": "A", "statistic": "share of corpus (%)", "comparison": lab,
                  "value": round(100 * p / s["n"], 2)},
                 {"table": group, "panel": "A", "statistic": "unique", "comparison": lab, "value": u}]
    rows += [{"table": group, "panel": "B", "statistic": "at least one", "comparison": "", "value": s["union"]},
             {"table": group, "panel": "B", "statistic": "all", "comparison": "", "value": s["all"]}]
    rows += [{"table": group, "panel": "B", "statistic": f"exactly {c}", "comparison": "", "value": v}
             for c, v in s["exact"].items()]
    for panel in ("C", "D"):
        for name, vals in s[panel].items():
            for combo, v in zip(s["combos"], vals):
                rows.append({"table": group, "panel": panel, "statistic": name,
                             "comparison": " / ".join(MODELS[k][0] for k in combo), "value": v,
                             "share_of_all_positive (%)": round(100 * v / s["all"], 1)})
    return rows


def main():
    os.makedirs(OUT, exist_ok=True)
    frames = {k: load(k) for k in MODELS}
    common = set.intersection(*[set(f.index) for f in frames.values()])
    keep = sorted(common)
    if DEDUPE:
        keep = dedupe(keep)
    frames = {k: f.loc[keep].copy() for k, f in frames.items()}
    print(f"Common sample: {len(keep)} papers" + (f" ({len(common) - len(keep)} duplicate copies dropped)"
                                                  if DEDUPE else ""))
    categories(frames)
    rows = []
    for group in GROUPS:
        s, paper = stats(group, frames)
        if group == "gpt" and not DEDUPE:
            check_published(s)
        write_tex(group, s)
        paper.to_csv(os.path.join(OUT, f"paper_level_{group}{SUFFIX}.csv"))
        rows += long_stats(group, s)
        print(f"\n== {group}: n={s['n']} pos={s['pos']} unique={s['unique']} union={s['union']} all={s['all']} "
              f"exact={s['exact']}")
        for p in ("C", "D"):
            for name, v in s[p].items():
                print(f"  {p} {name}: {v}")
    pd.DataFrame(rows).to_csv(os.path.join(OUT, f"agreement_statistics{SUFFIX}.csv"), index=False)
    print(f"\nOutputs -> {OUT}")


if __name__ == "__main__":
    main()
