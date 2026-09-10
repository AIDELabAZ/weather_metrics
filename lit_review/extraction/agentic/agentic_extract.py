"""
Agentic metadata extraction over the 88-paper hold-out (pdf_test_20), via
Claude Code headless (`claude -p`) — no OpenAI credits.

Per paper (5 `claude -p` calls):
  1 sectionizer  -> map real headings to canonical kinds
  2 reader A      -> {value, quote, section, confidence} per field (gated)
  3 reader B      -> adversarial challenge of A, per field
  4 verifier      -> does each quote support its value?  (+ a python quote-presence check)
  5 judge         -> final value + consensus {agree|resolved|review} per field

Outputs (default: <weather_iv_lit>/training/models/output/agentic/):
  agentic_output.csv       -- 11 canonical columns, drop-in for analysis/model_eval.R
  agentic_evidence.jsonl   -- full per-paper audit trail
  agentic_review_queue.csv -- (paper, field, value, rationale) for consensus == review

Usage:
  python extraction/agentic/build_examples.py           # once, builds reference/examples.jsonl
  python extraction/agentic/agentic_extract.py --limit 5
  python extraction/agentic/agentic_extract.py          # full 88, resumable
"""
import argparse
import asyncio
import csv
import json
import os
import re
import sys
import time

from pdf_text import build_document, quote_in_text

# ----------------------------------------------------------------------------- paths
HERE = os.path.dirname(os.path.abspath(__file__))
REF_DIR = os.path.join(HERE, "reference")
WEATHER = "/Users/kieran/Library/CloudStorage/OneDrive-UniversityofArizona/weather_iv_lit"
DEFAULT_PDF_DIR = os.path.join(WEATHER, "training/models/finetune_data/pdf_test_20")
DEFAULT_OUT_DIR = os.path.join(WEATHER, "training/models/output/agentic")

# ----------------------------------------------------------------------------- schema
FIELD_TO_COL = {
    "title": "Title",
    "doi": "DOI",
    "empirical_analysis": "Empirical Analysis",
    "dependent_variables": "Dependent Variable(s)",
    "endogeneity_problem": "Endogeneity Problem",
    "endogenous_variables": "Endogenous Variable(s)",
    "iv_used": "Instrumental Variable Used",
    "instruments": "Instrumental Variable(s)",
    "rainfall_iv": "Instrumental Variable Rainfall",
    "rainfall_instrument": "Rainfall Instrument",
}
CSV_FIELDNAMES = ["File Name"] + [FIELD_TO_COL[k] for k in
    ["title", "doi", "empirical_analysis", "dependent_variables", "endogeneity_problem",
     "endogenous_variables", "iv_used", "instruments", "rainfall_iv", "rainfall_instrument"]]

BINARY_FIELDS = ["empirical_analysis", "endogeneity_problem", "iv_used", "rainfall_iv"]
LIST_FIELDS = ["dependent_variables", "endogenous_variables", "instruments", "rainfall_instrument"]
SUBSTANTIVE = BINARY_FIELDS + LIST_FIELDS            # everything but title / doi

# gate field -> value required for a field to be answerable; applied top-down
CASCADE = [
    ("empirical_analysis", ["dependent_variables", "endogeneity_problem", "endogenous_variables",
                            "iv_used", "instruments", "rainfall_iv", "rainfall_instrument"]),
    ("endogeneity_problem", ["endogenous_variables", "iv_used", "instruments",
                             "rainfall_iv", "rainfall_instrument"]),
    ("iv_used", ["instruments", "rainfall_iv", "rainfall_instrument"]),
    ("rainfall_iv", ["rainfall_instrument"]),
]

_EV = {  # per-field evidence object shape used by reader A
    "type": "object", "additionalProperties": False,
    "properties": {
        "value": {"type": "string"},
        "quote": {"type": "string"},
        "section": {"type": "string"},
        "confidence": {"type": "string", "enum": ["high", "medium", "low"]},
    },
    "required": ["value", "quote", "section", "confidence"],
}


def reader_schema():
    props = {"title": {"type": "string"}, "doi": {"type": "string"}}
    for f in SUBSTANTIVE:
        props[f] = _EV
    return {"type": "object", "additionalProperties": False,
            "properties": props, "required": list(props)}


def adversary_schema():
    item = {"type": "object", "additionalProperties": False,
            "properties": {"agree": {"type": "boolean"},
                           "alt_value": {"type": "string"},
                           "alt_quote": {"type": "string"},
                           "reason": {"type": "string"}},
            "required": ["agree", "alt_value", "alt_quote", "reason"]}
    props = {f: item for f in SUBSTANTIVE}
    return {"type": "object", "additionalProperties": False,
            "properties": props, "required": list(props)}


def verifier_schema(fields):
    item = {"type": "object", "additionalProperties": False,
            "properties": {"supported": {"type": "boolean"}, "note": {"type": "string"}},
            "required": ["supported", "note"]}
    props = {f: item for f in fields}
    return {"type": "object", "additionalProperties": False,
            "properties": props, "required": list(props)}


def judge_schema():
    item = {"type": "object", "additionalProperties": False,
            "properties": {"final_value": {"type": "string"},
                           "consensus": {"type": "string", "enum": ["agree", "resolved", "review"]},
                           "rationale": {"type": "string"}},
            "required": ["final_value", "consensus", "rationale"]}
    props = {f: item for f in SUBSTANTIVE}
    props["title"] = {"type": "string"}
    props["doi"] = {"type": "string"}
    return {"type": "object", "additionalProperties": False,
            "properties": props, "required": list(props)}


SECTIONIZER_SCHEMA = {
    "type": "object", "additionalProperties": False,
    "properties": {"sections": {"type": "array", "items": {
        "type": "object", "additionalProperties": False,
        "properties": {"heading": {"type": "string"},
                       "kind": {"type": "string", "enum": [
                           "abstract", "introduction", "background", "data", "methods",
                           "results", "discussion", "conclusion", "appendix",
                           "references", "other"]}},
        "required": ["heading", "kind"]}}},
    "required": ["sections"],
}

# ----------------------------------------------------------------------------- reference text
with open(os.path.join(REF_DIR, "coding_rules.md"), encoding="utf-8") as fh:
    CODING_RULES = fh.read()
with open(os.path.join(REF_DIR, "format_spec.md"), encoding="utf-8") as fh:
    FORMAT_SPEC = fh.read()


def load_examples_block():
    path = os.path.join(REF_DIR, "examples.jsonl")
    if not os.path.exists(path):
        return "(no examples file — run build_examples.py)"
    by_field = {}
    with open(path, encoding="utf-8") as fh:
        for line in fh:
            r = json.loads(line)
            by_field.setdefault(r["field"], []).append(r)
    out = []
    for f in ["empirical_analysis", "dependent_variables", "endogeneity_problem",
              "endogenous_variables", "iv_used", "instruments", "rainfall_iv",
              "rainfall_instrument"]:
        out.append(f"# {f}")
        for r in by_field.get(f, [])[:4]:
            q = (r["quote"] or "").replace("\n", " ")[:200]
            out.append(f'  value={r["value"]!r}  section={r["section"]!r}  quote="{q}"')
    return "\n".join(out)


EXAMPLES_BLOCK = load_examples_block()

# ----------------------------------------------------------------------------- claude -p
def _json_from_text(s):
    s = s.strip()
    i, j = s.find("{"), s.rfind("}")
    if i == -1 or j == -1:
        raise ValueError("no JSON object in result")
    return json.loads(s[i:j + 1])


async def claude_call(system, user, schema, model, timeout=150, max_retries=3):
    args = ["claude", "-p", "--output-format", "json", "--model", model,
            "--tools", "", "--safe-mode", "--no-session-persistence",
            "--system-prompt", system, "--json-schema", json.dumps(schema)]
    last = None
    for attempt in range(max_retries):
        proc = None
        try:
            proc = await asyncio.create_subprocess_exec(
                *args, stdin=asyncio.subprocess.PIPE,
                stdout=asyncio.subprocess.PIPE, stderr=asyncio.subprocess.PIPE)
            out, err = await asyncio.wait_for(proc.communicate(user.encode()), timeout=timeout)
        except asyncio.TimeoutError:
            last = "timeout"
            try:
                proc.kill()
                await asyncio.wait_for(proc.wait(), timeout=10)
            except Exception:
                pass
            await asyncio.sleep(2 * (2 ** attempt))
            continue
        raw = out.decode("utf-8", "replace")
        if proc.returncode == 0 and raw.strip():
            try:
                wrap = json.loads(raw)
                if wrap.get("is_error"):
                    raise ValueError(str(wrap.get("result"))[:300])
                so = wrap.get("structured_output")
                if isinstance(so, dict):
                    return so
                return _json_from_text(wrap.get("result", ""))
            except Exception as e:  # noqa: BLE001
                last = f"parse: {e}"
        else:
            last = (err.decode("utf-8", "replace") or raw)[-400:]
        await asyncio.sleep(2 * (2 ** attempt))
    print(f"    [claude_call] gave up ({last})")
    return None

# ----------------------------------------------------------------------------- sectionize
def candidate_headings(doc_text):
    res, seen = [], set()
    for line in doc_text.splitlines():
        s = line.strip()
        if not (3 <= len(s) <= 90) or s.startswith("[[page "):
            continue
        words = s.split()
        if len(words) > 12:
            continue
        letters = [c for c in s if c.isalpha()]
        if not letters:
            continue
        upper = sum(c.isupper() for c in letters) / len(letters)
        numbered = bool(re.match(r"^(\d+(\.\d+)*\.?|[IVXL]+\.)\s+\S", s))
        titleish = s[0].isupper() and not s.endswith((".", ",", ";", ":"))
        if numbered or upper > 0.6 or (titleish and len(words) <= 8):
            if s.lower() not in seen:
                seen.add(s.lower())
                res.append(s)
    return res[:130]


async def sectionize(doc_text, model):
    heads = candidate_headings(doc_text)
    if len(heads) < 2:
        return {"full text": doc_text[:55000]}, []
    system = ("You identify the top-level section structure of an empirical economics "
              "paper. Given candidate heading lines (in document order) plus the opening "
              "text, return the REAL top-level section headings mapped to a kind. Drop "
              "false positives (table/figure titles, author names, running headers, "
              "reference entries). Use the heading text exactly as given.")
    user = (f"CANDIDATE HEADING LINES (in order):\n" + "\n".join(f"- {h}" for h in heads)
            + f"\n\nOPENING TEXT:\n{doc_text[:3000]}\n\nReturn the section map.")
    res = await claude_call(system, user, SECTIONIZER_SCHEMA, model)
    if not res or not res.get("sections"):
        return {"full text": doc_text[:55000]}, heads

    located = []
    for sec in res["sections"]:
        h = (sec.get("heading") or "").strip()
        if not h:
            continue
        m = re.search(r"(?m)^\s*" + re.escape(h[:60]), doc_text)
        if m:
            located.append((m.start(), sec.get("kind", "other"), h))
    located.sort()
    if len(located) < 2:
        return {"full text": doc_text[:55000]}, heads

    sections = {}
    # any preamble before the first heading -> treat as front matter / abstract-ish
    if located[0][0] > 200:
        sections.setdefault("abstract", "")
        sections["abstract"] += doc_text[:located[0][0]].strip() + "\n"
    for idx, (start, kind, h) in enumerate(located):
        end = located[idx + 1][0] if idx + 1 < len(located) else len(doc_text)
        sections.setdefault(kind, "")
        sections[kind] += f"\n[{h}]\n" + doc_text[start:end].strip() + "\n"
    return sections, heads


READER_ORDER = ["abstract", "introduction", "background", "data", "methods",
                "results", "discussion", "conclusion", "appendix", "full text", "other"]


def reader_input(sections, cap=46000):
    if "full text" in sections and len(sections) == 1:
        return sections["full text"][:cap]
    chunks = []
    for k in READER_ORDER:
        if k in sections and sections[k].strip():
            chunks.append(f"## SECTION: {k}\n{sections[k].strip()}")
    body = "\n\n".join(chunks) or "\n\n".join(sections.values())
    return body[:cap]

# ----------------------------------------------------------------------------- readers / verifier / judge
def _ev_line(f, ev):
    return (f"{f}: value={ev.get('value','?')!r} | section={ev.get('section','?')!r} | "
            f"conf={ev.get('confidence','?')} | quote=\"{(ev.get('quote') or '')[:280]}\"")


async def read_standard(text, model):
    system = (
        "You are an expert coder of empirical economics papers, replicating a human "
        "coding protocol. Extract every field using ONLY the article text below. For "
        "each field return {value, quote, section, confidence}. The quote must be an "
        "EXACT copy of a contiguous span from the article text below — same words, same "
        "order, no edits, no ellipses, no stitching separate sentences together — and "
        "must contain the value plus wording that makes its role explicit (e.g. the word "
        "'endogenous' / 'instrument'). If you cannot find an exact span, pick the closest "
        "real sentence and lower confidence. Never invent or paraphrase a quote. Respect "
        "the hierarchical gates: if a gate binary "
        "is not '1', set that field and everything below it to value 'n/a', quote '', "
        "section 'n/a'.")
    user = (f"CODING RULES:\n{CODING_RULES}\n\n"
            f"VALUE FORMAT:\n{FORMAT_SPEC}\n\n"
            f"WORKED EXAMPLES (style/format only — do NOT use their content):\n{EXAMPLES_BLOCK}\n\n"
            f"ARTICLE TEXT:\n{text}\n\nExtract all fields now.")
    return await claude_call(system, user, reader_schema(), model)


async def read_adversarial(text, ra, model):
    system = (
        "You are a skeptical red-team second reader. Another reader has coded an "
        "economics paper. For EACH field, try to disprove or improve the extraction "
        "using ONLY the article text. Press hardest on: is the named instrument "
        "actually EXCLUDED (first stage only, not a second-stage control)? Is the "
        "'endogenous variable' genuinely claimed endogenous, not an ordinary regressor? "
        "Is 'empirical analysis' real estimation done in THIS paper (not a lit review)? "
        "Does 'rainfall_iv' meet the bar (precipitation-based EXCLUDED instrument, not a "
        "control/exposure/outcome, not a bare climate index)? Return agree=true/false "
        "per field; if false give alt_value, alt_quote (verbatim), and reason. If you "
        "agree, set alt_value and alt_quote to ''.")
    dump = "\n".join(_ev_line(f, ra.get(f, {})) for f in SUBSTANTIVE)
    user = (f"CODING RULES:\n{CODING_RULES}\n\nARTICLE TEXT:\n{text}\n\n"
            f"READER A EXTRACTION:\n{dump}\n\nChallenge each field now.")
    return await claude_call(system, user, adversary_schema(), model)


async def verify_llm(text, pairs, model):
    """pairs: {field: (value, quote)} for non-n/a fields."""
    if not pairs:
        return {}
    system = (
        "You verify whether a quote actually establishes a claimed extraction value "
        "under the coding rule. supported=true only if the quote is on-topic AND its "
        "wording makes the value's role explicit per the rule (for instruments: shows "
        "it is used as an excluded instrument / in the first stage; for endogenous "
        "variables: shows it is treated as endogenous; etc.). Give a one-line note.")
    lines = [f"{f}:\n  value: {v}\n  quote: \"{(q or '')[:400]}\"" for f, (v, q) in pairs.items()]
    user = (f"CODING RULES:\n{CODING_RULES}\n\nARTICLE TEXT (for reference):\n{text[:30000]}\n\n"
            f"CHECK THESE:\n" + "\n".join(lines))
    return await claude_call(system, user, verifier_schema(list(pairs)), model) or {}


async def judge(ra, rb, quote_found, vr, model):
    system = (
        "You are the adjudicator. Given reader A, adversarial reader B, and verifier "
        "results, output the FINAL value for each field, a consensus label, and a "
        "one-line rationale. Rules:\n"
        "- consensus 'agree': A and B agree AND the value is well supported (verifier "
        "supported, or quote_found, or the quote is clearly on point) -> final = A's "
        "value. A false quote_found=False alone does NOT force 'review' when the "
        "verifier supports it and B agrees.\n"
        "- consensus 'resolved': they differed and one value is clearly better "
        "supported by the article -> final = that value (may be B's alt).\n"
        "- consensus 'review': genuine unresolved disagreement, OR the quote is absent "
        "AND the verifier is not convinced, OR confidence is low -> final = your "
        "best-supported guess, but flag it.\n"
        "- Gates: if a gate binary's final value is not '1', every field below it is "
        "'n/a'.\n"
        "- Format every final value per the VALUE FORMAT spec (binaries exactly "
        "1/0/n/a; lists '; '-joined; NEVER a bare 'rainfall'/'precipitation' for "
        "rainfall_instrument). Also return a cleaned title and a normalized lowercase doi.")
    rows = []
    for f in SUBSTANTIVE:
        a, b = ra.get(f, {}), rb.get(f, {})
        rows.append(
            f"{f}:\n"
            f"  A: value={a.get('value','?')!r} conf={a.get('confidence','?')} "
            f"quote_found={quote_found.get(f)} verifier_supported={vr.get(f, {}).get('supported')} "
            f"verifier_note={vr.get(f, {}).get('note','')!r}\n"
            f"     A_quote=\"{(a.get('quote') or '')[:240]}\"\n"
            f"  B: agree={b.get('agree')} alt_value={b.get('alt_value','')!r} "
            f"reason={b.get('reason','')!r}\n"
            f"     B_quote=\"{(b.get('alt_quote') or '')[:240]}\"")
    user = (f"VALUE FORMAT:\n{FORMAT_SPEC}\n\n"
            f"reader A title={ra.get('title','')!r} doi={ra.get('doi','')!r}\n\n"
            + "\n".join(rows) + "\n\nProduce the final adjudication.")
    return await claude_call(system, user, judge_schema(), model)

# ----------------------------------------------------------------------------- normalization
def norm_bin(s):
    s = str(s or "").strip().lower()
    if s in ("1", "1.0", "yes", "true"):
        return "1"
    if s in ("0", "0.0", "no", "false"):
        return "0"
    return "n/a"


def norm_list(s):
    s = str(s or "").strip()
    if not s or s.lower() in ("n/a", "na", "none", "null"):
        return "n/a"
    out, seen = [], set()
    for p in re.split(r"\s*;\s*", s):
        p = p.strip().strip('"').strip("-").strip()
        p = re.sub(r"^(the\s+)?(dependent|outcome|endogenous|instrument(al)?)\s+variable[s]?\s+(is|are|:)\s+", "", p, flags=re.I)
        if not p or len(p.split()) > 12:
            continue
        if p.lower() in seen:
            continue
        seen.add(p.lower())
        out.append(p)
    return "; ".join(out) if out else "n/a"


def norm_doi(s):
    s = str(s or "").strip().lower()
    s = re.sub(r"^\s*(doi:\s*|https?://(dx\.)?doi\.org/)", "", s)
    s = re.sub(r"\s+", "", s).strip(" .,;)")
    return s if s.startswith("10.") else "n/a"


def apply_cascade(vals):
    for gate, below in CASCADE:
        if norm_bin(vals.get(gate)) != "1":
            for k in below:
                vals[k] = "n/a"
    return vals

# ----------------------------------------------------------------------------- per paper
async def process_paper(pdf_path, model, judge_model):
    fname = os.path.basename(pdf_path)
    t0 = time.time()
    doc_text, meta = build_document(pdf_path)
    ev = {"file": fname, "pdf_meta": meta, "fields": {}}

    if meta.get("empty"):
        row = {c: "n/a" for c in CSV_FIELDNAMES}
        row["File Name"] = fname
        ev["error"] = "empty_pdf_text"
        return row, ev, [(fname, "*", "n/a", "empty pdf text")]

    sections, heads = await sectionize(doc_text, model)
    ev["sections"] = sorted(sections)
    rtext = reader_input(sections)

    ra = await read_standard(rtext, model)
    if ra is None:
        row = {c: "n/a" for c in CSV_FIELDNAMES}
        row["File Name"] = fname
        ev["error"] = "reader_a_failed"
        return row, ev, [(fname, "*", "n/a", "reader A call failed")]

    rb_raw = await read_adversarial(rtext, ra, model)
    rb = rb_raw or {}
    ev["reader_b_ok"] = rb_raw is not None

    # python quote-presence check
    quote_found = {}
    for f in SUBSTANTIVE:
        v = str(ra.get(f, {}).get("value", "n/a")).strip().lower()
        q = ra.get(f, {}).get("quote", "")
        quote_found[f] = None if v in ("n/a", "", "0") else quote_in_text(q, doc_text)

    pairs = {f: (ra[f]["value"], ra[f]["quote"]) for f in SUBSTANTIVE
             if str(ra.get(f, {}).get("value", "n/a")).strip().lower() not in ("n/a", "", "0")
             and ra[f].get("quote")}
    vr = await verify_llm(rtext, pairs, model)

    jg = await judge(ra, rb, quote_found, vr, judge_model) or {}

    # assemble finals
    finals, review = {}, []
    for f in SUBSTANTIVE:
        jf = jg.get(f, {})
        fv = jf.get("final_value", ra.get(f, {}).get("value", "n/a"))
        finals[f] = norm_bin(fv) if f in BINARY_FIELDS else norm_list(fv)
        cons = jf.get("consensus", "review")
        ev["fields"][f] = {
            "final": finals[f], "consensus": cons, "rationale": jf.get("rationale", ""),
            "reader_a": ra.get(f, {}), "reader_b": rb.get(f, {}),
            "quote_found": quote_found[f], "verifier": vr.get(f, {}),
        }
        if cons == "review":
            review.append((fname, f, finals[f], jf.get("rationale", "")))

    # guard: don't lose a well-supported reader-A extraction to a judge slip
    for f in LIST_FIELDS:
        av = str(ra.get(f, {}).get("value", "n/a")).strip()
        b_ok = (not rb.get(f)) or rb[f].get("agree", True)
        if (finals[f] == "n/a" and av.lower() not in ("n/a", "", "0")
                and (quote_found.get(f) or vr.get(f, {}).get("supported")) and b_ok):
            finals[f] = norm_list(av)
            ev["fields"][f]["final"] = finals[f]
            ev["fields"][f]["rationale"] = (
                ev["fields"][f].get("rationale", "")
                + " [restored reader-A value — judge returned n/a despite support]").strip()

    finals = apply_cascade(finals)
    for f in SUBSTANTIVE:                      # keep evidence consistent with cascade
        if ev["fields"][f]["final"] != finals[f]:
            ev["fields"][f]["final"] = finals[f]
            ev["fields"][f]["rationale"] = (ev["fields"][f]["rationale"] + " [gated -> n/a]").strip()

    title = (jg.get("title") or ra.get("title") or "").strip().strip('"') or "n/a"
    doi = norm_doi(jg.get("doi") or ra.get("doi"))

    row = {"File Name": fname, "Title": title, "DOI": doi}
    for f in SUBSTANTIVE:
        row[FIELD_TO_COL[f]] = finals[f]
    ev["title"], ev["doi"] = title, doi
    ev["elapsed_s"] = round(time.time() - t0, 1)
    return row, ev, review

# ----------------------------------------------------------------------------- runner
def load_done(csv_path):
    if not os.path.exists(csv_path):
        return set()
    with open(csv_path, newline="", encoding="utf-8") as fh:
        return {r["File Name"] for r in csv.DictReader(fh) if r.get("File Name")}


async def main_async(args):
    pdf_dir = args.pdf_dir
    out_dir = args.out_dir
    os.makedirs(out_dir, exist_ok=True)
    out_csv = os.path.join(out_dir, "agentic_output.csv")
    out_ev = os.path.join(out_dir, "agentic_evidence.jsonl")
    out_rev = os.path.join(out_dir, "agentic_review_queue.csv")

    all_pdfs = sorted(f for f in os.listdir(pdf_dir) if f.lower().endswith(".pdf"))
    if args.papers:
        want = {p if p.endswith(".pdf") else p + ".pdf" for p in args.papers.split(",")}
        all_pdfs = [f for f in all_pdfs if f in want]
    done = set() if args.fresh else load_done(out_csv)
    todo = [f for f in all_pdfs if f not in done]
    if args.limit:
        todo = todo[:args.limit]
    print(f"{len(all_pdfs)} pdfs | {len(done)} already done | {len(todo)} to process | "
          f"concurrency {args.concurrency} | model {args.model}")
    if not todo:
        return

    mode = "w" if (args.fresh or not os.path.exists(out_csv)) else "a"
    csv_fh = open(out_csv, mode, newline="", encoding="utf-8")
    writer = csv.DictWriter(csv_fh, fieldnames=CSV_FIELDNAMES, extrasaction="ignore")
    if mode == "w":
        writer.writeheader()
    ev_fh = open(out_ev, "w" if args.fresh else "a", encoding="utf-8")
    rev_new = args.fresh or not os.path.exists(out_rev)
    rev_fh = open(out_rev, "w" if args.fresh else "a", newline="", encoding="utf-8")
    rev_w = csv.writer(rev_fh)
    if rev_new:
        rev_w.writerow(["File Name", "field", "final_value", "rationale"])

    sem = asyncio.Semaphore(args.concurrency)
    lock = asyncio.Lock()
    n_done = [0]

    async def worker(fn):
        async with sem:
            print(f"  -> start {fn}", flush=True)
            try:
                row, ev, review = await asyncio.wait_for(
                    process_paper(os.path.join(pdf_dir, fn), args.model, args.judge_model),
                    timeout=args.paper_timeout)
            except asyncio.TimeoutError:
                print(f"  !! {fn}: paper timeout ({args.paper_timeout}s) — skipped", flush=True)
                return
            except Exception as e:  # noqa: BLE001
                print(f"  !! {fn}: {e}", flush=True)
                return
        async with lock:
            writer.writerow(row)
            csv_fh.flush()
            ev_fh.write(json.dumps(ev, ensure_ascii=False) + "\n")
            ev_fh.flush()
            for r in review:
                rev_w.writerow(r)
            rev_fh.flush()
            n_done[0] += 1
            rv = sum(1 for f in SUBSTANTIVE if ev.get("fields", {}).get(f, {}).get("consensus") == "review")
            print(f"  [{n_done[0]}/{len(todo)}] done {fn}  emp={row['Empirical Analysis']} "
                  f"iv={row['Instrumental Variable Used']} rain={row['Instrumental Variable Rainfall']} "
                  f"review={rv} {ev.get('elapsed_s','?')}s", flush=True)

    await asyncio.gather(*(worker(fn) for fn in todo))
    for fh in (csv_fh, ev_fh, rev_fh):
        fh.close()
    print(f"\nwrote -> {out_csv}\n         {out_ev}\n         {out_rev}")


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--pdf-dir", default=DEFAULT_PDF_DIR)
    ap.add_argument("--out-dir", default=DEFAULT_OUT_DIR)
    ap.add_argument("--model", default="claude-sonnet-5")
    ap.add_argument("--judge-model", default=None, help="default: same as --model")
    ap.add_argument("--concurrency", type=int, default=3)
    ap.add_argument("--paper-timeout", type=int, default=900, help="wall-clock cap per paper (s)")
    ap.add_argument("--limit", type=int, default=0)
    ap.add_argument("--papers", default="", help="comma-separated pdf basenames (smoke test)")
    ap.add_argument("--fresh", action="store_true", help="ignore existing output, start over")
    args = ap.parse_args()
    try:
        sys.stdout.reconfigure(line_buffering=True)
    except Exception:
        pass
    args.judge_model = args.judge_model or args.model
    asyncio.run(main_async(args))


if __name__ == "__main__":
    main()
