"""
baseline_gemini.py

Zero-shot frontier baseline for the Gemini family: identical prompts,
questions, dependency logic, PDF extraction, and sampling settings
(temperature 0, stop sequences, max_tokens) as baseline_gpt.py, but calls
Gemini 4 Argon, Google's newest model as of Oct 2026 (GA 2026-10-13) — the
Gemini counterpart to baseline_sol.py.

Called through Vertex AI's OpenAI-compatible endpoint, so the request code is
the same as baseline_gpt.py's; only the client's base_url/auth and the model
differ. Auth is Application Default Credentials (gcloud auth
application-default login); the access token is refreshed automatically,
since a full run outlasts its 1-hour lifetime.

Configured below to run against the held-out pdf_test_20 set (ground truth
in removed_20.csv).
"""

import fitz  # PyMuPDF
import json
import os
import shutil
import tempfile
import time
import google.auth
import google.auth.transport.requests
from openai import OpenAI
import re
from datetime import datetime


# -------------------------------------------------------------------
# Config knobs you can tweak
# -------------------------------------------------------------------


GCP_PROJECT  = "311885870283"
GCP_LOCATION = "global"
VERTEX_HOST  = "aiplatform.googleapis.com"

# Newest Gemini model as of Oct 2026. Vertex model IDs in the OpenAI-compatible
# endpoint are "<publisher>/<model>".
BASE_MODEL = "google/gemini-4-argon"

_creds, _ = google.auth.default(scopes=["https://www.googleapis.com/auth/cloud-platform"])
_creds = _creds.with_quota_project(GCP_PROJECT)  # bill/quota the call to this project
_client = None


def get_client():
    """OpenAI client pointed at Vertex, rebuilt whenever the ADC token expires."""
    global _client
    if _client is None or not _creds.valid:
        _creds.refresh(google.auth.transport.requests.Request())
        _client = OpenAI(
            base_url=f"https://{VERTEX_HOST}/v1/projects/{GCP_PROJECT}/locations/{GCP_LOCATION}/endpoints/openapi",
            api_key=_creds.token,
        )
    return _client


DEFAULT_MAX_COMPLETION_TOKENS = 512
MAX_COMPLETION_TOKENS_BY_KEY = {
    "Title": 256,
    "DOI": 128,
    "Empirical Analysis": 256,
    "Dependent Variable(s)": 512,

    # Bundles (dual queries)
    "Endogeneity Bundle": 512,
    "IV Bundle": 512,
    "Rainfall IV Bundle": 512,

    # Optional re-ask (single-line)
    "Rainfall Instrument Reask": 512,
}


STOP_SEQUENCES_BY_KEY = {
    "Title": ["\n\n"],
    "DOI": ["\n\n"],
    "Empirical Analysis": ["\n", " "],
    "Dependent Variable(s)": ["\n\n"],

    # Bundles: encourage exactly two lines
    "Endogeneity Bundle": ["\n\n"],
    "IV Bundle": ["\n\n"],
    "Rainfall IV Bundle": ["\n\n"],

    # Reask: one line
    "Rainfall Instrument Reask": ["\n\n"],
}


TEMPERATURE = 0.0  # for extraction, 0.0 usually improves stability

# Characters of (keyword-filtered) article text sent to the model; None sends
# the full text. Full text is the default since the Oct 2026 context test
# (analysis/compare_context_test.py): dropping the original 40_000 cap cut
# missed IVs/endogeneity without lowering similarity scores. The text is
# resent with every question in the conversation (~7 per paper), so a cap
# multiplies down input cost; 40_000 (~10k tokens) reproduces the original
# runs. The keyword filter in extract_relevant_sections rarely removes
# anything, since PyMuPDF output has few blank lines and each "paragraph" is
# a whole page.
MAX_INPUT_CHARS = None


# -------------------------------------------------------------------
# Questions with bundled structure (identical to finetune_gpt.py)
# -------------------------------------------------------------------


questions = [
    {
        "key": "Title",
        "question": (
            "Task: Extract the article title.\nLook: top of first page (main heading before authors/abstract).\nRules: include subtitle if in the same heading; exclude authors/affiliations/journal headers/footers/section headers; ignore footnote markers (*, †, superscripts).\nOutput: ONE line: title text only. No quotes, labels, or extra words."
        ),
    },
    {
        "key": "DOI",
        "question": (
            "Task: Extract the DOI of THIS article (version of record), not DOIs in references.\nLook: first page/front matter for doi:, DOI, https://doi.org/.\nRules: remove URL/prefix (doi:, https://doi.org/); remove spaces/line breaks; strip trailing punctuation; output lowercase.\nOutput: ONE token = normalized DOI (10.xxxx/xxxx) OR exactly n/a."
        ),
    },
    {
        "key": "Empirical Analysis",
        "question": (
            "Task: Does the article contain empirical quantitative statistical estimation (e.g., regressions/econometrics with estimated coefficients/SEs/p-values)?\nLook: 'we estimate/regress', model equations with error terms, regression tables with coefficients.\nRules: do NOT infer from topic/title/abstract. Count only analysis done in THIS article (not summaries of other papers). Exclude purely theoretical work, qualitative/descriptive only, and simulation/calibration only.\nOutput: 1 if yes, 0 if no. Output exactly one character."
        )
    },
    {
        "key": "Dependent Variable(s)",
        "question": (
            "Task: List the main dependent/outcome variable(s) used in the primary regression/econometric results.\nLook: LHS of main equations; column headers of main regression tables; text describing the main empirical model.\nRules: exclude first-stage outcomes, RHS variables (treatments/endogenous regressors/instruments/controls/covariates/fixed effects), mediators/moderators.\nKeep names exactly as written in the paper/table (including any log/ln/differences/units if shown).\nOutput: ONE line: variable name(s) only; separate multiple with '; '."
        ),
        "dependency": {"key": "Empirical Analysis", "value": "1"},
    },

    # -------------------------
    # BUNDLED (DUAL) QUERIES
    # -------------------------

    {
        "key": "Endogeneity Bundle",
        "dependency": {"key": "Empirical Analysis", "value": "1"},
        "field_map": {
            "ENDOGENEITY_PROBLEM": ("Endogeneity Problem", "binary_just"),
            "ENDOGENOUS_VARIABLES": ("Endogenous Variable(s)", "var_list"),
        },
        "question": (
            "Only proceed if the text contains empirical quantitative statistical analysis. "
            "Answer BOTH parts below using ONLY the provided article text.\n\n"
            "Part A (binary): Task: In the MAIN empirical analysis, do the authors treat any RHS variable as endogenous (correlated with the error term) and address it explicitly?\nLook: statements that a regressor is endogenous + a method to address it (IV/2SLS/3SLS/LIML, control function/2SRI, GMM with instruments, first stage, weak-IV tests, etc.).\nRules: do NOT count generic mentions of 'endogeneity' without an actual endogenous regressor in the main specs.\nOutput: 1 if yes, 0 if no. Output exactly one character."
            "Part B (list): Task: If endogenous explanatory variable(s) exist in this paper, list the explanatory variable(s) explicitly treated as endogenous in the main analysis.\nLook: 'we instrument X', 'X is endogenous', first-stage descriptions/tables, reduced form, weak-IV/overid tests.\nRules: exclude instruments, dependent variables, and ordinary controls.\nKeep names exactly as written in the paper/table (including any log/ln/differences/units if shown).\nOutput: ONE line: variable name(s) only; separate multiple with '; '."
            "Output format (EXACTLY requested information, no extra text):\n"
            "ENDOGENEITY_PROBLEM: <0 or 1>\n"
            "ENDOGENOUS_VARIABLES: <semicolon-separated list; or n/a>"
        ),
    },

    {
        "key": "IV Bundle",
        "dependency": {"key": "Endogeneity Problem", "value": "1"},
        "field_map": {
            "IV_USED": ("Instrumental Variable Used", "binary_just"),
            "IVS": ("Instrumental Variable(s)", "var_list"),
        },
        "question": (
            "Answer BOTH parts below using ONLY the provided article text.\n\n"
            "Part A (binary): Task: In the MAIN empirical analysis, do the authors implement an IV-type estimator with excluded instruments to address endogeneity?\nLook: an actual excluded instrument set used in a first stage/reduced form; 2SLS/IV/3SLS/LIML; IV-Probit; control function/2SRI; GMM with instruments; exclusion restriction; first-stage equations/tables.\nRules: do NOT count non-statistical uses of 'instrument' (survey instrument, measurement instrument) or papers that only use RCT/RDD/DiD/event study without an IV first stage.\nOutput: 1 if yes, 0 if no. Output exactly one character."
            "Part B (list): Task: List the excluded instrument(s) used in the main IV analysis.\nLook: 'we instrument X with Z', 'Z is our instrument', 'excluded instrument', first-stage/reduced-form equations or tables.\nRules: exclude endogenous regressors themselves, dependent variables, and regular controls.\nKeep names exactly as written in the paper/table (including any log/ln/differences/units if shown).\nOutput: ONE line: instrument name(s) only; separate multiple with '; '."
            "Output format (EXACTLY requested information, no extra text):\n"
            "IV_USED: <0 or 1>\n"
            "IVS: <semicolon-separated list; or n/a>"
        ),
    },

    {
        "key": "Rainfall IV Bundle",
        "dependency": {"key": "Instrumental Variable Used", "value": "1"},
        "field_map": {
            "RAINFALL_IV": ("Instrumental Variable Rainfall", "binary_just"),
            "RAINFALL_INSTRUMENT": ("Rainfall Instrument", "var_list"),
        },
        "question": (
            "Answer BOTH parts below using ONLY the provided article text.\n\n"
            "Part A (binary): Task: Is any excluded instrument based on rainfall/precipitation?\nLook: rainfall, precipitation, drought, monsoon rainfall/onset, wet-day counts, SPI/SPEI/PDSI, precipitation-derived indices used as the EXCLUDED instrument.\nRules: count only if precipitation-based and used as an excluded instrument in an IV first stage/reduced form. Do NOT count precipitation used only as regressor/control/interaction/exposure/outcome. Do NOT count ENSO or other climate indices unless explicitly stated to be precipitation-based AND used as the excluded instrument. Ignore mentions in other papers.\nOutput: 1 if yes, 0 if no. Output exactly one character."
            "Part B (detail): Task: List the specific rainfall/precipitation-based excluded instrument(s) used in the main IV analysis.\nLook: first-stage/reduced-form equations/tables for the precipitation-based instrument name(s) (e.g., total/mean rainfall over a window, rainfall deviations/shocks, monsoon onset, rainfall index, coefficient of variation of rainfall).\nRules: keep names exactly as written in the paper/table (including window/statistic/units/logs if shown).\nOutput: ONE line: rainfall instrument name(s) only; separate multiple with '; '."
            " If Part A != 1, output n/a.\n\n"
            "Output format (EXACTLY requested information, no extra text):\n"
            "RAINFALL_IV: <0 or 1>\n"
            "RAINFALL_INSTRUMENT: <detailed semicolon-separated description(s); or n/a>"
        ),
    },
]


# -------------------------------------------------------------------
# Cleaning helpers (identical to finetune_gpt.py)
# -------------------------------------------------------------------


def normalize_binary_with_justification(answer):
    """
    Extract binary answer (0 or 1) from a response that may include justification.
    Returns tuple: (binary_value, justification_text)
    """
    if not answer:
        return "n/a", ""

    answer = answer.strip()

    # Check if starts with 0 or 1
    if answer.startswith("1"):
        justification = answer[1:].strip().lstrip(":-").strip()
        return "1", justification
    elif answer.startswith("0"):
        return "0", ""
    elif answer.lower().startswith("yes"):
        justification = answer[3:].strip().lstrip(":-").strip()
        return "1", justification
    elif answer.lower().startswith("no"):
        return "0", ""
    elif answer.lower() in {"n/a", "na"}:
        return "n/a", ""

    return "n/a", ""


def clean_variable_list(raw_text):
    """
    Split a variable-list answer on ';' only — the separator every prompt asks
    for — without rewriting the variables themselves. The legacy cleaner
    below also split on ' and ' and on commas, and cut at 'which'/'that'/
    'for'/'where', which mangled correct answers before they were scored
    (e.g. "rainfall in the monsoon months of june, july, august" ->
    "...of june; july; august"; "number of months in which ..." ->
    "number of months in").
    """
    if not raw_text:
        return "n/a"
    txt = raw_text.replace("\\n", " ").strip()

    if txt.lower() in {"n/a", "na", "none"}:
        return "n/a"

    if ":" in txt:
        head, tail = txt.split(":", 1)
        if any(w in head.lower() for w in ["variable", "variables", "outcome", "instrument"]):
            txt = tail.strip()

    seen = set()
    uniq = []
    for p in txt.split(";"):
        p = p.strip().strip(".").strip().strip("\"\"''")
        if p and p.lower() not in {"n/a", "none"} and p.lower() not in seen:
            seen.add(p.lower())
            uniq.append(p)

    return "; ".join(uniq) if uniq else "n/a"


def clean_variable_list_legacy(raw_text):
    """Original cleaner, kept so saved raw answers can be re-cleaned the old
    way to measure what the new one changed (see RAW_ANSWERS sidecar)."""
    if not raw_text:
        return "n/a"
    txt = raw_text.strip()

    if txt.lower() in {"n/a", "na", "none"}:
        return "n/a"

    if ":" in txt:
        head, tail = txt.split(":", 1)
        if any(w in head.lower() for w in ["variable", "variables", "outcome", "instrument"]):
            txt = tail.strip()

    txt = txt.replace("\\n", " ")
    txt = txt.replace(" and ", "; ")

    parts = re.split(r"[;,]", txt)

    cleaned = []
    for p in parts:
        p = p.strip().strip(".").strip()
        if not p:
            continue

        p = re.split(r"\s[-–]\s", p)[0].strip()
        p = re.split(r"\s(?:such as|for|where|which|that)\b", p, flags=re.I)[0].strip()
        p = p.strip("\"\"''")

        if len(p.split()) > 10:
            continue

        if p and p.lower() not in {"n/a", "none"}:
            cleaned.append(p)

    seen = set()
    uniq = []
    for v in cleaned:
        key = v.lower()
        if key not in seen:
            seen.add(key)
            uniq.append(v)

    return "; ".join(uniq) if uniq else "n/a"

def parse_prefixed_lines(answer: str, field_map: dict):
    """
    Parse model output that is required to be one-line-per-field with prefixes.

    field_map format:
      {
        "PREFIX": ("Target Column Name", "binary_just" | "var_list" | "text")
      }

    Returns:
      parsed: dict of target column -> value
      justifications: dict of target column (binary fields) -> justification text
    """
    out = {tkey: "n/a" for _, (tkey, _) in field_map.items()}
    just = {}

    if not answer:
        return out, just

    lines = [ln.strip() for ln in answer.splitlines() if ln.strip()]

    # Newer models tend to honor the system prompt's "no labels" rule over the
    # bundle's "PREFIX: value" format, returning bare values one per line
    # (e.g. "1\nvar a; var b"). If NO line carries a prefix and the line count
    # matches the field count, map lines to fields positionally. Prompts are
    # left untouched so they stay identical to the other baseline runs.
    # (Same fallback as baseline_sol.py.)
    prefixes = list(field_map.keys())
    any_prefixed = any(
        re.match(rf"^{re.escape(p)}\s*[:=]", ln, re.I) for p in prefixes for ln in lines
    )
    positional = None
    if not any_prefixed and len(lines) == len(prefixes):
        positional = dict(zip(prefixes, lines))

    for prefix, (tkey, kind) in field_map.items():
        pat = re.compile(rf"^{re.escape(prefix)}\s*[:=]\s*(.*)$", re.I)

        val = None
        for ln in lines:
            m = pat.match(ln)
            if m:
                val = m.group(1).strip()
                break
        if val is None and positional is not None:
            val = positional[prefix]

        if val is None:
            continue

        if kind == "binary_just":
            b, j = normalize_binary_with_justification(val)
            out[tkey] = b
            if j:
                just[tkey] = j
        elif kind == "var_list":
            out[tkey] = clean_variable_list(val)
        else:  # "text"
            out[tkey] = val.strip() if val.strip() else "n/a"

    return out, just


# -------------------------------------------------------------------
# Accuracy check helpers (identical to finetune_gpt.py)
# -------------------------------------------------------------------


def extract_instruments_from_justification(justification_text):
    """
    Extract instrument names from the justification text provided when
    Instrumental Variable Rainfall = 1.
    """
    if not justification_text:
        return "n/a"

    # Clean up the justification
    txt = justification_text.strip().lower()

    # Remove common prefixes
    for prefix in ["instruments:", "instrument:", "uses", "using", "include", "includes"]:
        if txt.startswith(prefix):
            txt = txt[len(prefix):].strip()

    # Clean and format
    txt = txt.strip(".,;:\\\"'")

    if not txt or txt in {"n/a", "na", "none"}:
        return "n/a"

    return txt


def extract_rainfall_iv_snippets(full_text: str, max_chars: int = 9000) -> str:
    """
    Second-pass context reducer: keep only paragraphs likely to mention rainfall instruments + their construction.
    """
    if not full_text:
        return ""

    RAINFALL_TERMS = [
        "rainfall", "precipitation", "rain", "precip",
        "monsoon", "drought", "weather", "typhoon", "hurricane", "storm", "wet", "dry"
    ]

    paras = [p.strip() for p in full_text.split("\n\n") if p.strip()]
    keep = []
    for p in paras:
        pl = p.lower()
        if any(term in pl for term in RAINFALL_TERMS) and (
            "instrument" in pl or "iv" in pl or "2sls" in pl or "first stage" in pl or
            "first-stage" in pl or "excluded" in pl
        ):
            keep.append(p)

    out = "\n\n".join(keep)
    if len(out) > max_chars:
        out = out[:max_chars]
    return out


# -------------------------------------------------------------------
# Dependency consistency enforcer (same output columns as before)
# -------------------------------------------------------------------


def enforce_dependency_consistency(temp_answers, justifications, *, verbose=False):
    """
    Enforce path dependencies and accuracy checks.

    Path dependencies:
    - If Empirical Analysis = 0, skip all following questions
    - If Endogeneity Problem = 0, skip all following questions
    - If Instrumental Variable Used = 0, skip all following questions
    - If Instrumental Variable Rainfall = 0, skip all following questions

    Accuracy checks:
    - If Rainfall IV = 1, optionally use its justification to populate Rainfall Instrument if still missing
    """

    empirical = temp_answers.get("Empirical Analysis", "0")
    endogeneity = temp_answers.get("Endogeneity Problem", "n/a")
    iv_used = temp_answers.get("Instrumental Variable Used", "n/a")
    rain_iv = temp_answers.get("Instrumental Variable Rainfall", "n/a")

    # Gate 1: Empirical Analysis
    if empirical != "1":
        for k in [
            "Dependent Variable(s)", "Endogeneity Problem", "Endogenous Variable(s)",
            "Instrumental Variable Used", "Instrumental Variable(s)",
            "Instrumental Variable Rainfall", "Rainfall Instrument"
        ]:
            temp_answers[k] = "n/a"
        return temp_answers

    # Gate 2: Endogeneity Problem
    if endogeneity != "1":
        temp_answers["Endogenous Variable(s)"] = "n/a"
        temp_answers["Instrumental Variable Used"] = "n/a"
        temp_answers["Instrumental Variable(s)"] = "n/a"
        temp_answers["Instrumental Variable Rainfall"] = "n/a"
        temp_answers["Rainfall Instrument"] = "n/a"
        return temp_answers

    # Gate 3: IV Used
    if iv_used != "1":
        temp_answers["Instrumental Variable(s)"] = "n/a"
        temp_answers["Instrumental Variable Rainfall"] = "n/a"
        temp_answers["Rainfall Instrument"] = "n/a"
        return temp_answers

    # Gate 4: Rainfall IV
    if rain_iv != "1":
        temp_answers["Rainfall Instrument"] = "n/a"
        return temp_answers

    # Accuracy check: If Rainfall IV = 1, use justification to populate Rainfall Instrument
    rain_justification = justifications.get("Instrumental Variable Rainfall", "")
    if rain_justification:
        current_rainfall_instrument = temp_answers.get("Rainfall Instrument", "").strip()
        if current_rainfall_instrument in {"", "n/a", "0", "1"}:
            extracted = extract_instruments_from_justification(rain_justification)
            if extracted != "n/a":
                if verbose:
                    print(f"Filling Rainfall Instrument from Rainfall IV justification: '{extracted}'")
                temp_answers["Rainfall Instrument"] = extracted

    return temp_answers


# -------------------------------------------------------------------
# PDF extraction (identical to finetune_gpt.py)
# -------------------------------------------------------------------


def extract_relevant_sections(pdf_path, max_retries=4, base_delay=3.0):
    relevant_sections = []
    keywords = [
        "instrument", "instrumental variable", "data", "methods", "iv",
        "rainfall", "model", "econometric", "metrics", "introduction",
        "abstract", "conclusion", "strategy", "empirical", "estimation",
        "outcome", "precipitation", "first stage", "first-stage",
        "endogeneity", "endogenous", "identification", "2SLS",
        "second stage", "doi", "excluded", "estimate", "effect", "affects", "exogenous",
        "two-stage least squares", "2sls", "GMM", "fixed effects"
    ]

    # OneDrive stores these PDFs as on-demand ("cloud-only") files — the first
    # open() on an unhydrated file can fail while OneDrive downloads it in the
    # background. Retrying after a short delay resolves this without any
    # persistent failures (confirmed empirically across the full test folder).
    for attempt in range(max_retries):
        try:
            with fitz.open(pdf_path) as doc:
                for page_num in range(len(doc)):
                    page = doc.load_page(page_num)
                    page_text = page.get_text("text")
                    paragraphs = page_text.split("\n\n")
                    for paragraph in paragraphs:
                        if any(keyword.lower() in paragraph.lower() for keyword in keywords):
                            relevant_sections.append(paragraph)
            return " ".join(relevant_sections)
        except Exception as e:
            if attempt < max_retries - 1:
                delay = base_delay * (attempt + 1)
                print(f"Error opening PDF {pdf_path}: {e}. Retrying in {delay:.0f}s "
                      f"(likely still downloading from OneDrive)...")
                time.sleep(delay)
            else:
                print(f"Error extracting PDF {pdf_path} after {max_retries} attempts: {e}")
                return ""


# -------------------------------------------------------------------
# Token control helpers
# -------------------------------------------------------------------


def get_max_completion_tokens(q_key: str) -> int:
    return int(MAX_COMPLETION_TOKENS_BY_KEY.get(q_key, DEFAULT_MAX_COMPLETION_TOKENS))


def get_stop_sequences(q_key: str):
    return STOP_SEQUENCES_BY_KEY.get(q_key)


# -------------------------------------------------------------------
# Model query with conversation history
# -------------------------------------------------------------------


# Vertex's managed (MaaS) models return transient 429s / "request queue is
# full" under load, so retry longer than baseline_gpt.py does — a failed call
# becomes "n/a" and would be scored as a wrong answer.
class ModelCallError(Exception):
    """A model call failed in a way retrying won't fix, or ran out of retries.
    Raised instead of returning "n/a", so a failed call is never recorded as
    the model's answer; process_pdfs_conditional_queries stops that paper and
    records the error (Extraction Error column + raw-answers sidecar)."""


def _status(e):
    # HTTP status from whichever SDK raised: openai/anthropic set .status_code,
    # google-genai and google-api-core set .code.
    status = getattr(e, "status_code", None) or getattr(e, "code", None)
    return status if isinstance(status, int) else None


def _is_transient(e):
    # Worth retrying: rate limits, timeouts, server errors, dropped connections.
    status = _status(e)
    if status is not None:
        return status in (408, 409, 429) or status >= 500
    return isinstance(e, (ConnectionError, TimeoutError)) or any(
        k in type(e).__name__ for k in ("Connection", "Timeout", "Transport", "Unavailable"))


def _aborts_run(e):
    # Every paper would fail the same way, so stop the whole run rather than
    # failing paper by paper: bad credentials/permissions/model name
    # (401/403/404), exhausted credit (OpenAI reports it as a 429), or an
    # exception that isn't an API error at all (e.g. missing credentials).
    if "insufficient_quota" in str(e):
        return True
    status = _status(e)
    if status is not None:
        return status in (401, 403, 404)
    return not _is_transient(e)


def query_model_with_history(messages, q_key, is_binary=False, max_completion_tokens_override=None,
                             max_retries=8, base_delay=2.0, max_delay=60.0):
    max_comp = int(max_completion_tokens_override) if max_completion_tokens_override is not None else get_max_completion_tokens(q_key)
    stop = get_stop_sequences(q_key)

    kwargs = dict(
        model=BASE_MODEL,
        messages=messages,
        max_tokens=max_comp,
        temperature=TEMPERATURE,
    )
    if stop:
        kwargs["stop"] = stop

    for attempt in range(max_retries):
        try:
            response = get_client().chat.completions.create(**kwargs)
            answer = (response.choices[0].message.content or "").strip()
            return answer if answer else "n/a"

        except Exception as e:

            if _aborts_run(e):

                raise

            if not _is_transient(e):

                raise ModelCallError(f"{q_key}: {e}") from e
            if attempt < max_retries - 1:
                delay = min(base_delay * (2 ** attempt), max_delay)
                print(f"Error querying model ({q_key}): {e}. Retrying in {delay:.0f}s...")
                time.sleep(delay)
            else:
                raise ModelCallError(f"{q_key}: failed after {max_retries} attempts: {e}") from e


# -------------------------------------------------------------------
# Main processing
# -------------------------------------------------------------------


FIELDNAMES = [
    "File Name", "Title", "DOI", "Empirical Analysis", "Dependent Variable(s)",
    "Endogeneity Problem", "Endogenous Variable(s)", "Instrumental Variable Used",
    "Instrumental Variable(s)", "Instrumental Variable Rainfall", "Rainfall Instrument",
    "Extraction Error",  # empty unless a model call failed (see ModelCallError)
]

SYNC_EVERY_N_PDFS = 50  # how often to checkpoint the local file to OneDrive mid-run


def _atomic_sync_to_onedrive(local_path, dest_path):
    """
    Copy local_path to dest_path atomically: write to a temp file in the
    SAME directory as dest_path, then os.replace() it into place. os.replace
    is an atomic rename, so OneDrive's sync client only ever observes either
    the old complete file or the new complete file — never a partial one.
    """
    dest_dir = os.path.dirname(dest_path)
    fd, tmp_path = tempfile.mkstemp(dir=dest_dir, suffix=".tmp")
    os.close(fd)
    shutil.copyfile(local_path, tmp_path)
    os.replace(tmp_path, dest_path)


def process_pdfs_conditional_queries(pdf_folder, output_csv):
    # Write incrementally to a LOCAL temp file, not the live OneDrive-synced
    # destination directly. A full-corpus run makes thousands of small
    # flush() calls over many hours — doing that straight into a
    # cloud-synced folder has twice now produced torn writes (rows spliced
    # together mid-write, corrupting the CSV). Only the finished file ever
    # touches the OneDrive path, copied in atomically (see
    # _atomic_sync_to_onedrive), both periodically as a crash-safety
    # checkpoint and once at the end.
    import csv as _csv
    local_tmp = os.path.join(tempfile.gettempdir(), f"baseline_gemini_{os.getpid()}.csv")
    csv_file = open(local_tmp, "w", newline="", encoding="utf-8")
    writer = _csv.DictWriter(csv_file, fieldnames=FIELDNAMES, extrasaction="ignore")
    writer.writeheader()
    # Sidecar: every model answer before parsing/cleaning, one JSON line per
    # paper, so cleaning can be changed (or the legacy cleaner re-applied)
    # without re-running the API calls.
    raw_jsonl = os.path.splitext(output_csv)[0] + "_raw_answers.jsonl"
    local_raw = os.path.join(tempfile.gettempdir(), f"baseline_gemini_{os.getpid()}_raw.jsonl")
    raw_file = open(local_raw, "w", encoding="utf-8")
    n_processed = 0

    failed = []  # (filename, error) for papers a model call failed on
    for filename in os.listdir(pdf_folder):
        if not filename.endswith(".pdf"):
            continue

        pdf_path = os.path.join(pdf_folder, filename)
        print(f"\nProcessing {filename}...")
        relevant_sections = extract_relevant_sections(pdf_path)
        print(f"Extracted relevant sections length: {len(relevant_sections)} characters")

        text_to_analyze = relevant_sections if MAX_INPUT_CHARS is None else relevant_sections[:MAX_INPUT_CHARS]
        raw_answers = {}  # q_key -> model's answer before any parsing/cleaning
        error = None  # set if a model call fails (ModelCallError)

        info_dict = {
            "File Name": filename,
            "Title": "n/a",
            "DOI": "n/a",
            "Empirical Analysis": "0",
            "Dependent Variable(s)": "n/a",
            "Endogeneity Problem": "n/a",
            "Endogenous Variable(s)": "n/a",
            "Instrumental Variable Used": "n/a",
            "Instrumental Variable(s)": "n/a",
            "Instrumental Variable Rainfall": "n/a",
            "Rainfall Instrument": "n/a",
        }

        temp_answers = info_dict.copy()
        justifications = {}  # Store justifications from binary outputs (now from bundles too)

        # Single conversation thread for this PDF
        messages = [
            {
                "role": "system",
                "content": (
                    "You are an AI assistant that is an expert in analysis of economic literature. "
                    "You interpret complex content and extract specific information, especially about "
                    "empirical methods, endogeneity problems, and instrumental variable strategies. "
                    "Rules: Use only information from the provided text to answer each query. "
                    "If the requested information is not available, answer exactly n/a. "
                    "Follow the requested output format exactly. "
                    "Exclusions: Do not include the user queries, any labels, greek letters, or additional text beyond what is requested. "
                    "Do not respond with symbolic notation, only words. "
                    "For binary questions with justification requests, always start with 0 or 1"
                ),
            },
            {
                "role": "user",
                "content": (
                    "You will be asked a sequence of extraction questions about the same academic article. "
                    "I am specifically interested in how researchers address endogeneity problems, particularly "
                    "using instrumental variables and especially rainfall-based instruments. "
                    "Use answers you have already given as context for later questions when helpful, "
                    "but always ground your answers in the provided text.\n\n"
                    "Here are the relevant sections from the article:\n\n"
                    f"{text_to_analyze}"
                ),
            },
            {
                "role": "assistant",
                "content": "Understood. I will answer each extraction question using only the provided article text.",
            },
        ]

        try:
            for q in questions:
                q_key = q["key"]

                # Dependency gate
                dep = q.get("dependency")
                if dep is not None:
                    dep_key = dep["key"]
                    dep_val = dep["value"]
                    current_dep_answer = temp_answers.get(dep_key)

                    # For binary questions with justification, extract just the binary part
                    if current_dep_answer and current_dep_answer[0] in {"0", "1"}:
                        current_dep_binary = current_dep_answer[0]
                    else:
                        current_dep_binary = current_dep_answer

                    if current_dep_binary != dep_val:
                        print(
                            f"Skipping '{q_key}' due to unmet dependency "
                            f"({dep_key}={current_dep_binary} != {dep_val})"
                        )

                        # If bundle, set all target columns to n/a
                        if "field_map" in q:
                            for _, (tkey, _) in q["field_map"].items():
                                temp_answers[tkey] = "n/a"
                                info_dict[tkey] = "n/a"
                        else:
                            temp_answers[q_key] = "n/a"
                            info_dict[q_key] = "n/a"

                        temp_answers = enforce_dependency_consistency(temp_answers, justifications, verbose=True)
                        continue

                print(f"Querying: {q_key} (max_completion_tokens={get_max_completion_tokens(q_key)})")

                question_text = (
                    f"Question key: {q_key}.\n"
                    f"{q['question']}\n\n"
                    "Answer using only the article text above and, if helpful, your previous answers in this conversation. "
                    "Remember to follow the required output format exactly."
                )
                messages.append({"role": "user", "content": question_text})

                answer = query_model_with_history(
                    messages,
                    q_key=q_key,
                    is_binary=(q_key == "Empirical Analysis"),
                )

                # Append the model's raw answer to the conversation
                messages.append({"role": "assistant", "content": answer})
                raw_answers[q_key] = answer

                # Bundles: parse into their target columns
                if "field_map" in q:
                    parsed, bundle_just = parse_prefixed_lines(answer, q["field_map"])

                    # write parsed outputs into the real columns
                    for col, val in parsed.items():
                        temp_answers[col] = val
                        info_dict[col] = val

                    # store justifications for binary fields (keyed by the target column name)
                    for col, jtxt in bundle_just.items():
                        justifications[col] = jtxt

                    # Apply consistency checks after bundle parse
                    temp_answers = enforce_dependency_consistency(temp_answers, justifications, verbose=True)

                    # Print bundle results
                    for col in parsed.keys():
                        print(f"Answer for {col}: {info_dict[col]}")

                    # SECOND PASS: if rainfall IV=1 but Rainfall Instrument still n/a, re-ask just the detail line
                    if q_key == "Rainfall IV Bundle":
                        if temp_answers.get("Instrumental Variable Rainfall") == "1" and temp_answers.get("Rainfall Instrument", "n/a") == "n/a":
                            focused = extract_rainfall_iv_snippets(text_to_analyze)
                            if focused:
                                print("Re-asking rainfall instrument detail with rainfall/IV-focused context...")
                                messages.append({
                                    "role": "user",
                                    "content": (
                                        "Now focus only on the following rainfall- and IV-related snippets from the article:\n\n"
                                        f"{focused}\n\n"
                                        "Provide EXACTLY one line in this format:\n"
                                        "RAINFALL_INSTRUMENT: <detailed semicolon-separated description(s); or n/a>\n\n"
                                        "Do not include any other lines or text."
                                    ),
                                })
                                retry = query_model_with_history(
                                    messages,
                                    q_key="Rainfall Instrument Reask",
                                    is_binary=False,
                                    max_completion_tokens_override=MAX_COMPLETION_TOKENS_BY_KEY["Rainfall Instrument Reask"],
                                )
                                messages.append({"role": "assistant", "content": retry})
                                raw_answers["Rainfall Instrument Reask"] = retry

                                parsed2, _ = parse_prefixed_lines(
                                    retry,
                                    {"RAINFALL_INSTRUMENT": ("Rainfall Instrument", "var_list")}
                                )
                                temp_answers["Rainfall Instrument"] = parsed2.get("Rainfall Instrument", "n/a")
                                info_dict["Rainfall Instrument"] = temp_answers["Rainfall Instrument"]
                                temp_answers = enforce_dependency_consistency(temp_answers, justifications, verbose=True)

                                print(f"Answer for Rainfall Instrument (reask): {info_dict['Rainfall Instrument']}")

                    continue

                # Non-bundle questions
                is_binary = q_key in ["Empirical Analysis"]

                if is_binary:
                    binary_val, justification = normalize_binary_with_justification(answer)
                    temp_answers[q_key] = binary_val
                    if justification:
                        justifications[q_key] = justification
                        print(f"  Binary: {binary_val}, Justification: {justification[:100]}...")
                else:
                    if q_key in ["Dependent Variable(s)"]:
                        answer = clean_variable_list(answer)
                    temp_answers[q_key] = answer

                # Apply consistency checks after each answer
                temp_answers = enforce_dependency_consistency(temp_answers, justifications, verbose=True)

                info_dict[q_key] = temp_answers[q_key]
                print(f"Answer for {q_key}: {info_dict[q_key]}")
        except ModelCallError as e:
            # Every remaining question resends the same article, so it would fail
            # the same way. Stop this paper and keep what was already answered;
            # unanswered fields stay n/a, flagged by the Extraction Error column.
            error = str(e)
            failed.append((filename, error))
            print(f"  [FAILED] {filename}: {error}")


        # Final global consistency pass
        info_dict = enforce_dependency_consistency(info_dict, justifications, verbose=False)

        print(f"Final extracted info for {filename}: {info_dict}")
        info_dict["Extraction Error"] = error or ""
        writer.writerow(info_dict)
        csv_file.flush()
        raw_file.write(json.dumps({
            "File Name": filename,
            "max_input_chars": MAX_INPUT_CHARS,
            "full_chars": len(relevant_sections),
            "input_chars": len(text_to_analyze),
            "raw_answers": raw_answers,
            "error": error,
        }) + "\n")
        raw_file.flush()

        n_processed += 1
        if n_processed % SYNC_EVERY_N_PDFS == 0:
            _atomic_sync_to_onedrive(local_tmp, output_csv)
            _atomic_sync_to_onedrive(local_raw, raw_jsonl)
            print(f"  [checkpoint] synced {n_processed} rows → {output_csv}")

    if failed:
        print(f"\n{len(failed)} paper(s) FAILED — these rows are incomplete, not model answers; rerun them:")
        for fn, err in failed:
            print(f"  {fn}: {err}")
    csv_file.close()
    raw_file.close()
    _atomic_sync_to_onedrive(local_tmp, output_csv)
    _atomic_sync_to_onedrive(local_raw, raw_jsonl)
    os.remove(local_tmp)
    os.remove(local_raw)
    print(f"Data saved to {output_csv}")


# -------------------------------------------------------------------
# Paths and execution
# -------------------------------------------------------------------
# Held-out test set → /output/gemini/baseline/test_baseline_gemini_output.csv. For a full-corpus run, point
# pdf_folder at /weather_iv_lit/papers and name the output full_baseline_gemini_output.csv.

if __name__ == "__main__":
    pdf_folder = "/Users/kieran/Library/CloudStorage/OneDrive-UniversityofArizona/weather_iv_lit/training/finetune_data/pdf_test_20"
    output_folder = "/Users/kieran/Library/CloudStorage/OneDrive-UniversityofArizona/weather_iv_lit/output/gemini/baseline"
    os.makedirs(output_folder, exist_ok=True)
    output_csv = os.path.join(output_folder, "test_baseline_gemini_output.csv")

    process_pdfs_conditional_queries(pdf_folder, output_csv)
    print(f"Script finished: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
