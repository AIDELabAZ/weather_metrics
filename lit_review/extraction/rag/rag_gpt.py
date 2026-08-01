import fitz  # PyMuPDF
import os
import re
import csv as _csv
import json
import time
import math
import hashlib
from datetime import datetime

from openai import OpenAI


# -------------------------------------------------------------------
# Config — update these before running
# -------------------------------------------------------------------

client = OpenAI(api_key=os.environ.get("OPENAI_API_KEY"))

# Same base model finetune_gpt.py's fine-tuned model ("ft:gpt-4.1-2025-04-14:...")
# was tuned from. No fine-tuning is used here — retrieved examples replace it.
BASE_MODEL = "gpt-4.1-2025-04-14"

EMBEDDING_MODEL = "text-embedding-3-small"
TOP_K = 3
EMBED_MAX_CHARS = 20000  # keeps embedding inputs safely under the model's token limit


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


# Identical wording to finetune_gpt.py's system message
SYSTEM_PROMPT = (
    "You are an AI assistant that is an expert in analysis of economic literature. "
    "You interpret complex content and extract specific information, especially about "
    "empirical methods, endogeneity problems, and instrumental variable strategies. "
    "Rules: Use only information from the provided text to answer each query. "
    "If the requested information is not available, answer exactly n/a. "
    "Follow the requested output format exactly. "
    "Exclusions: Do not include the user queries, any labels, greek letters, or additional text beyond what is requested. "
    "Do not respond with symbolic notation, only words. "
    "For binary questions with justification requests, always start with 0 or 1"
)

# Extra rule needed only because this script uses the base (non-tuned) model:
# reference examples stand in for what fine-tuning would otherwise have taught it.
REFERENCE_EXAMPLES_INSTRUCTION = (
    " Some questions below include reference examples of correctly formatted answers "
    "drawn from OTHER articles. Use them ONLY to learn the expected answer format and "
    "reasoning style — never copy their content or let them influence what you say "
    "about the current article. Ground every answer only in the current article's text."
)

FULL_SYSTEM_PROMPT = SYSTEM_PROMPT + REFERENCE_EXAMPLES_INSTRUCTION


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

QUESTION_SUFFIX = (
    "\n\nAnswer using only the article text above and, if helpful, your previous answers in this conversation. "
    "Remember to follow the required output format exactly."
)


# -------------------------------------------------------------------
# Cleaning helpers (identical to finetune_gpt.py / conversion_code_gpt.py)
# -------------------------------------------------------------------


def fix_encoding(s):
    """Repair mojibake iteratively until stable (identical to conversion_code_gpt.py)."""
    if not s:
        return s

    def _char_bytes(ch):
        try:
            return ch.encode('cp1252')
        except UnicodeEncodeError:
            try:
                return ch.encode('latin-1')
            except UnicodeEncodeError:
                return None

    def _repair_once(text):
        try:
            return text.encode('cp1252').decode('utf-8')
        except (UnicodeEncodeError, UnicodeDecodeError):
            pass
        result = []
        i = 0
        while i < len(text):
            fixed = False
            for length in (3, 2):
                if i + length <= len(text):
                    chunk = text[i:i+length]
                    char_bytes = [_char_bytes(c) for c in chunk]
                    if None not in char_bytes:
                        raw = b''.join(char_bytes)
                        try:
                            result.append(raw.decode('utf-8'))
                            i += length
                            fixed = True
                            break
                        except UnicodeDecodeError:
                            pass
            if not fixed:
                result.append(text[i])
                i += 1
        return ''.join(result)

    prev = None
    while s != prev:
        prev = s
        s = _repair_once(s)
    return s


def val(row, key):
    """Return field value or 'n/a' for missing/empty fields, with encoding repair."""
    return fix_encoding(row.get(key) or 'n/a')


def norm_bin(v):
    """Normalize a CSV binary field ('1', '1.0', '0', '0.0', '') to '1' or '0'."""
    s = (v or '').strip()
    return '1' if s in ('1', '1.0') else '0'


def normalize_var_list(v):
    """Clean a CSV variable-name string into inference output format ('; '-separated or 'n/a')."""
    if not v or not v.strip():
        return 'n/a'
    txt = v.strip().replace('\r', ' ').replace('\n', ' ')
    parts = [p.strip() for p in txt.split(';') if p.strip()]
    return '; '.join(parts) if parts else 'n/a'


def build_document_context(row):
    """Combine text excerpts from a training CSV row into one deduplicated block
    (identical to conversion_code_gpt.py) — used as the retrieval text for the
    'general' pool (Title / DOI / Empirical Analysis)."""
    seen = set()
    excerpts = []
    for col in ('dep_txt', 'end_txt', 'iv_txt', 'rain_txt'):
        text = fix_encoding((row.get(col) or '').strip())
        if text and text not in seen:
            seen.add(text)
            excerpts.append(text)
    return '\n\n'.join(excerpts)


def normalize_binary_with_justification(answer):
    if not answer:
        return "n/a", ""
    answer = answer.strip()
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
    if not raw_text:
        return "n/a"
    txt = raw_text.strip()
    if txt.lower() in {"n/a", "na", "none"}:
        return "n/a"
    if ":" in txt:
        head, tail = txt.split(":", 1)
        if any(w in head.lower() for w in ["variable", "variables", "outcome", "instrument"]):
            txt = tail.strip()
    txt = txt.replace("\\n", " ").replace(" and ", "; ")
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


def parse_prefixed_lines(answer, field_map):
    out = {tkey: "n/a" for _, (tkey, _) in field_map.items()}
    just = {}
    if not answer:
        return out, just
    lines = [ln.strip() for ln in answer.splitlines() if ln.strip()]
    for prefix, (tkey, kind) in field_map.items():
        pat = re.compile(rf"^{re.escape(prefix)}\s*[:=]\s*(.*)$", re.I)
        val_ = None
        for ln in lines:
            m = pat.match(ln)
            if m:
                val_ = m.group(1).strip()
                break
        if val_ is None:
            continue
        if kind == "binary_just":
            b, j = normalize_binary_with_justification(val_)
            out[tkey] = b
            if j:
                just[tkey] = j
        elif kind == "var_list":
            out[tkey] = clean_variable_list(val_)
        else:
            out[tkey] = val_.strip() if val_.strip() else "n/a"
    return out, just


def extract_instruments_from_justification(justification_text):
    if not justification_text:
        return "n/a"
    txt = justification_text.strip().lower()
    for prefix in ["instruments:", "instrument:", "uses", "using", "include", "includes"]:
        if txt.startswith(prefix):
            txt = txt[len(prefix):].strip()
    txt = txt.strip(".,;:\\\"'")
    if not txt or txt in {"n/a", "na", "none"}:
        return "n/a"
    return txt


def extract_rainfall_iv_snippets(full_text, max_chars=9000):
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


def enforce_dependency_consistency(temp_answers, justifications, *, verbose=False):
    empirical = temp_answers.get("Empirical Analysis", "0")
    endogeneity = temp_answers.get("Endogeneity Problem", "n/a")
    iv_used = temp_answers.get("Instrumental Variable Used", "n/a")
    rain_iv = temp_answers.get("Instrumental Variable Rainfall", "n/a")

    if empirical != "1":
        for k in [
            "Dependent Variable(s)", "Endogeneity Problem", "Endogenous Variable(s)",
            "Instrumental Variable Used", "Instrumental Variable(s)",
            "Instrumental Variable Rainfall", "Rainfall Instrument"
        ]:
            temp_answers[k] = "n/a"
        return temp_answers

    if endogeneity != "1":
        temp_answers["Endogenous Variable(s)"] = "n/a"
        temp_answers["Instrumental Variable Used"] = "n/a"
        temp_answers["Instrumental Variable(s)"] = "n/a"
        temp_answers["Instrumental Variable Rainfall"] = "n/a"
        temp_answers["Rainfall Instrument"] = "n/a"
        return temp_answers

    if iv_used != "1":
        temp_answers["Instrumental Variable(s)"] = "n/a"
        temp_answers["Instrumental Variable Rainfall"] = "n/a"
        temp_answers["Rainfall Instrument"] = "n/a"
        return temp_answers

    if rain_iv != "1":
        temp_answers["Rainfall Instrument"] = "n/a"
        return temp_answers

    rain_justification = justifications.get("Instrumental Variable Rainfall", "")
    if rain_justification:
        current = temp_answers.get("Rainfall Instrument", "").strip()
        if current in {"", "n/a", "0", "1"}:
            extracted = extract_instruments_from_justification(rain_justification)
            if extracted != "n/a":
                if verbose:
                    print(f"Filling Rainfall Instrument from Rainfall IV justification: '{extracted}'")
                temp_answers["Rainfall Instrument"] = extracted

    return temp_answers


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
# Field-specific query text extraction (retrieval only — does not affect
# what's sent to the model as the actual article text, only what's used
# to find similar training examples for each question)
# -------------------------------------------------------------------

FIELD_QUERY_TERMS = {
    "Dependent Variable(s)": [
        "dependent variable", "outcome variable", "outcome", "left-hand side", "lhs",
        "regress", "estimat"
    ],
    "Endogeneity Bundle": [
        "endogen", "instrument", "2sls", "first stage", "first-stage",
        "control function", "gmm", "weak instrument", "reduced form"
    ],
    "IV Bundle": [
        "instrument", "2sls", "first stage", "first-stage", "excluded",
        "iv-probit", "gmm", "exclusion restriction"
    ],
    "Rainfall IV Bundle": [
        "rainfall", "precipitation", "rain", "precip", "monsoon", "drought", "weather"
    ],
}


def filter_paragraphs_by_terms(full_text, terms, max_chars=9000):
    if not full_text or not terms:
        return ""
    paras = [p.strip() for p in full_text.split("\n\n") if p.strip()]
    keep = [p for p in paras if any(t in p.lower() for t in terms)]
    out = "\n\n".join(keep)
    if len(out) > max_chars:
        out = out[:max_chars]
    return out


# -------------------------------------------------------------------
# Training data retrieval index
# -------------------------------------------------------------------

TRAIN_CSV_PATH = "/Users/kieran/Library/CloudStorage/OneDrive-UniversityofArizona/weather_iv_lit/training/models/finetune_data/train_80.csv"
EMBEDDING_CACHE_PATH = os.path.join(os.path.dirname(__file__), ".rag_gpt_embedding_cache.json")

REQUIRED_TRAIN_COLUMNS = [
    'filename', 'title', 'doi',
    'emp_bin', 'dep_var', 'dep_sec', 'dep_txt',
    'end_bin', 'end_var', 'end_sec', 'end_txt',
    'iv_bin', 'iv_var', 'iv_sec', 'iv_txt',
    'rain_bin', 'rain_var', 'rain_sec', 'rain_txt'
]


def load_training_rows(csv_path):
    """Read train_80.csv the same way conversion_code_gpt.py does (encoding fallback chain)."""
    encodings_to_try = ['utf-8-sig', 'utf-16', 'utf-16-le', 'utf-16-be', 'cp1252', 'latin1']
    for encoding in encodings_to_try:
        try:
            with open(csv_path, 'r', encoding=encoding, newline='') as csvfile:
                reader = _csv.DictReader(csvfile)
                headers = reader.fieldnames or []
                missing = [c for c in REQUIRED_TRAIN_COLUMNS if c not in headers]
                if missing:
                    print(f"Missing required columns in training CSV: {', '.join(missing)}")
                    return []
                print(f"Successfully read training CSV using encoding: {encoding}")
                return list(reader)
        except UnicodeError as e:
            print(f"Failed to read training CSV with encoding {encoding}: {e}")
        except Exception as e:
            print(f"Unexpected error reading training CSV with encoding {encoding}: {e}")
    print("Unable to read the training CSV with the tried encodings.")
    return []


def _hash_text(text):
    return hashlib.sha256(text.encode("utf-8")).hexdigest()


def _load_embedding_cache():
    if os.path.exists(EMBEDDING_CACHE_PATH):
        try:
            with open(EMBEDDING_CACHE_PATH, "r", encoding="utf-8") as f:
                return json.load(f)
        except Exception:
            return {}
    return {}


def _save_embedding_cache(cache):
    with open(EMBEDDING_CACHE_PATH, "w", encoding="utf-8") as f:
        json.dump(cache, f)


_embedding_cache = _load_embedding_cache()


def embed_texts(texts, max_retries=4, base_delay=2.0):
    """Return one embedding per input text, using an on-disk cache keyed by content hash."""
    results = [None] * len(texts)
    to_fetch, to_fetch_idx = [], []
    for i, t in enumerate(texts):
        h = _hash_text(t)
        if h in _embedding_cache:
            results[i] = _embedding_cache[h]
        else:
            to_fetch.append(t)
            to_fetch_idx.append(i)

    if to_fetch:
        for attempt in range(max_retries):
            try:
                response = client.embeddings.create(model=EMBEDDING_MODEL, input=to_fetch)
                for idx, item in zip(to_fetch_idx, response.data):
                    results[idx] = item.embedding
                    _embedding_cache[_hash_text(texts[idx])] = item.embedding
                _save_embedding_cache(_embedding_cache)
                break
            except Exception as e:
                if attempt < max_retries - 1:
                    delay = base_delay * (2 ** attempt)
                    print(f"Embedding error: {e}. Retrying in {delay:.0f}s...")
                    time.sleep(delay)
                else:
                    print(f"Embedding failed after {max_retries} attempts: {e}")
    return results


def cosine_sim(a, b):
    dot = sum(x * y for x, y in zip(a, b))
    norm_a = math.sqrt(sum(x * x for x in a))
    norm_b = math.sqrt(sum(y * y for y in b))
    if norm_a == 0 or norm_b == 0:
        return 0.0
    return dot / (norm_a * norm_b)


def build_retrieval_pools(rows):
    """
    Build one retrieval pool per question, embedding each pool's texts in one
    batched call. Only train_80.csv is used — never removed_20.csv (the test set) —
    so no test-set information leaks into the RAG examples, matching what the
    fine-tuned model itself was allowed to see.
    """
    general_texts, general_rows = [], []
    field_texts = {k: [] for k in FIELD_QUERY_TERMS}
    field_rows = {k: [] for k in FIELD_QUERY_TERMS}

    for row in rows:
        doc_context = build_document_context(row)
        if doc_context:
            general_texts.append(doc_context[:EMBED_MAX_CHARS])
            general_rows.append(row)

        for field, col in (
            ("Dependent Variable(s)", "dep_txt"),
            ("Endogeneity Bundle", "end_txt"),
            ("IV Bundle", "iv_txt"),
            ("Rainfall IV Bundle", "rain_txt"),
        ):
            text = fix_encoding((row.get(col) or "").strip())
            if text:
                field_texts[field].append(text[:EMBED_MAX_CHARS])
                field_rows[field].append(row)

    pools = {}

    general_embeddings = embed_texts(general_texts) if general_texts else []
    general_pool = []
    for row, text, emb in zip(general_rows, general_texts, general_embeddings):
        if emb is None:
            continue
        emp = norm_bin(row.get('emp_bin', ''))
        general_pool.append({
            "text": text,
            "embedding": emb,
            "answers": {
                "Title": val(row, 'title'),
                "DOI": val(row, 'doi').strip().lower(),
                "Empirical Analysis": emp,
            },
        })
    pools["general"] = general_pool

    for field in FIELD_QUERY_TERMS:
        texts = field_texts[field]
        embeddings = embed_texts(texts) if texts else []
        pool = []
        for row, text, emb in zip(field_rows[field], texts, embeddings):
            if emb is None:
                continue
            end = norm_bin(row.get('end_bin', ''))
            iv = norm_bin(row.get('iv_bin', ''))
            rain = norm_bin(row.get('rain_bin', ''))
            if field == "Dependent Variable(s)":
                answer = normalize_var_list(val(row, 'dep_var'))
            elif field == "Endogeneity Bundle":
                answer = (f"ENDOGENEITY_PROBLEM: {end}\n"
                          f"ENDOGENOUS_VARIABLES: {normalize_var_list(val(row, 'end_var'))}")
            elif field == "IV Bundle":
                answer = (f"IV_USED: {iv}\n"
                          f"IVS: {normalize_var_list(val(row, 'iv_var'))}")
            else:  # Rainfall IV Bundle
                answer = (f"RAINFALL_IV: {rain}\n"
                          f"RAINFALL_INSTRUMENT: {normalize_var_list(val(row, 'rain_var'))}")
            pool.append({"text": text, "embedding": emb, "answer": answer})
        pools[field] = pool

    for key, pool in pools.items():
        print(f"Retrieval pool '{key}': {len(pool)} examples")

    return pools


def retrieve_top_k(pool, query_embedding, k=TOP_K):
    scored = [(cosine_sim(query_embedding, entry["embedding"]), entry) for entry in pool]
    scored.sort(key=lambda x: x[0], reverse=True)
    return [entry for _, entry in scored[:k]]


def get_reference_examples(q_key, doc_context, pools, k=TOP_K):
    """Per-question dynamic retrieval: embed a query conditioned on this specific
    question, search only that question's pool, and return its top-k matches."""
    if q_key in ("Title", "DOI", "Empirical Analysis"):
        pool_key = "general"
        query_text = doc_context[:EMBED_MAX_CHARS]
    else:
        pool_key = q_key
        query_text = filter_paragraphs_by_terms(doc_context, FIELD_QUERY_TERMS.get(q_key, []))
        if not query_text:
            query_text = doc_context[:EMBED_MAX_CHARS]
        else:
            query_text = query_text[:EMBED_MAX_CHARS]

    pool = pools.get(pool_key, [])
    if not pool or not query_text:
        return []

    query_embedding = embed_texts([query_text])[0]
    if query_embedding is None:
        return []

    top = retrieve_top_k(pool, query_embedding, k=k)

    examples = []
    for entry in top:
        answer = entry["answers"].get(q_key, "n/a") if pool_key == "general" else entry["answer"]
        examples.append({"excerpt": entry["text"], "answer": answer})
    return examples


def format_reference_block(examples, excerpt_chars=800):
    if not examples:
        return ""
    lines = ["Reference examples from OTHER articles (format/style guidance only — do not use their content):"]
    for i, ex in enumerate(examples, 1):
        excerpt = ex["excerpt"][:excerpt_chars]
        lines.append(f"\nExample {i} article excerpt:\n{excerpt}")
        lines.append(f"Example {i} correct answer:\n{ex['answer']}")
    return "\n".join(lines) + "\n\n"


# -------------------------------------------------------------------
# Model query with conversation history (same pattern as finetune_gpt.py,
# pointed at the base model instead of a fine-tuned model id)
# -------------------------------------------------------------------


def query_model_with_history(messages, q_key, max_completion_tokens_override=None,
                              max_retries=4, base_delay=2.0):
    max_comp = int(max_completion_tokens_override) if max_completion_tokens_override is not None \
        else MAX_COMPLETION_TOKENS_BY_KEY.get(q_key, DEFAULT_MAX_COMPLETION_TOKENS)
    stop = STOP_SEQUENCES_BY_KEY.get(q_key)

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
            response = client.chat.completions.create(**kwargs)
            answer = response.choices[0].message.content.strip()
            return answer if answer else "n/a"
        except Exception as e:
            if attempt < max_retries - 1:
                delay = base_delay * (2 ** attempt)
                print(f"Error querying model ({q_key}): {e}. Retrying in {delay:.0f}s...")
                time.sleep(delay)
            else:
                print(f"Error querying model ({q_key}) after {max_retries} attempts: {e}")
                return "n/a"


# -------------------------------------------------------------------
# Main processing
# -------------------------------------------------------------------


FIELDNAMES = [
    "File Name", "Title", "DOI", "Empirical Analysis", "Dependent Variable(s)",
    "Endogeneity Problem", "Endogenous Variable(s)", "Instrumental Variable Used",
    "Instrumental Variable(s)", "Instrumental Variable Rainfall", "Rainfall Instrument",
]


def process_pdfs_conditional_queries(pdf_folder, output_csv, pools):
    csv_file = open(output_csv, "w", newline="", encoding="utf-8")
    writer = _csv.DictWriter(csv_file, fieldnames=FIELDNAMES, extrasaction="ignore")
    writer.writeheader()

    for filename in os.listdir(pdf_folder):
        if not filename.endswith(".pdf"):
            continue

        pdf_path = os.path.join(pdf_folder, filename)
        print(f"\nProcessing {filename}...")
        relevant_sections = extract_relevant_sections(pdf_path)
        print(f"Extracted relevant sections length: {len(relevant_sections)} characters")

        max_tokens = 10000
        text_to_analyze = relevant_sections[: max_tokens * 4]

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
        justifications = {}

        # Single conversation thread for this PDF (identical framing to finetune_gpt.py)
        messages = [
            {
                "role": "system",
                "content": FULL_SYSTEM_PROMPT,
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

        for q in questions:
            q_key = q["key"]

            dep = q.get("dependency")
            if dep is not None:
                dep_key = dep["key"]
                dep_val = dep["value"]
                current_dep_answer = temp_answers.get(dep_key)
                current_dep_binary = (
                    current_dep_answer[0]
                    if current_dep_answer and current_dep_answer[0] in {"0", "1"}
                    else current_dep_answer
                )
                if current_dep_binary != dep_val:
                    print(f"Skipping '{q_key}' due to unmet dependency "
                          f"({dep_key}={current_dep_binary} != {dep_val})")
                    if "field_map" in q:
                        for _, (tkey, _) in q["field_map"].items():
                            temp_answers[tkey] = "n/a"
                            info_dict[tkey] = "n/a"
                    else:
                        temp_answers[q_key] = "n/a"
                        info_dict[q_key] = "n/a"
                    temp_answers = enforce_dependency_consistency(temp_answers, justifications, verbose=True)
                    continue

            print(f"Querying: {q_key} (max_completion_tokens={MAX_COMPLETION_TOKENS_BY_KEY.get(q_key, DEFAULT_MAX_COMPLETION_TOKENS)})")

            reference_examples = get_reference_examples(q_key, text_to_analyze, pools)
            reference_block = format_reference_block(reference_examples)
            print(f"  Retrieved {len(reference_examples)} reference example(s) for '{q_key}'")

            question_text = (
                f"Question key: {q_key}.\n\n"
                f"{reference_block}"
                f"{q['question']}\n\n"
                "Answer using only the article text above and, if helpful, your previous answers in this conversation. "
                "Remember to follow the required output format exactly."
            )
            messages.append({"role": "user", "content": question_text})

            answer = query_model_with_history(messages, q_key=q_key)

            # Append the model's raw answer to the conversation
            messages.append({"role": "assistant", "content": answer})

            # Bundles: parse into their target columns
            if "field_map" in q:
                parsed, bundle_just = parse_prefixed_lines(answer, q["field_map"])

                for col, val_ in parsed.items():
                    temp_answers[col] = val_
                    info_dict[col] = val_

                for col, jtxt in bundle_just.items():
                    justifications[col] = jtxt

                temp_answers = enforce_dependency_consistency(temp_answers, justifications, verbose=True)

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
                                max_completion_tokens_override=MAX_COMPLETION_TOKENS_BY_KEY["Rainfall Instrument Reask"],
                            )
                            messages.append({"role": "assistant", "content": retry})

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

            temp_answers = enforce_dependency_consistency(temp_answers, justifications, verbose=True)

            info_dict[q_key] = temp_answers[q_key]
            print(f"Answer for {q_key}: {info_dict[q_key]}")

        info_dict = enforce_dependency_consistency(info_dict, justifications, verbose=False)

        print(f"Final extracted info for {filename}: {info_dict}")
        writer.writerow(info_dict)
        csv_file.flush()

    csv_file.close()
    print(f"Data saved to {output_csv}")


# -------------------------------------------------------------------
# Paths and execution
# -------------------------------------------------------------------


if __name__ == "__main__":
    pdf_folder = "/Users/kieran/Library/CloudStorage/OneDrive-UniversityofArizona/weather_iv_lit/papers"
    output_folder = "/Users/kieran/Library/CloudStorage/OneDrive-UniversityofArizona/weather_iv_lit/training/models/output"
    os.makedirs(output_folder, exist_ok=True)
    output_csv = os.path.join(output_folder, "full_rag_gpt_output.csv")

    training_rows = load_training_rows(TRAIN_CSV_PATH)
    retrieval_pools = build_retrieval_pools(training_rows)

    process_pdfs_conditional_queries(pdf_folder, output_csv, retrieval_pools)
    print(f"Script finished: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
