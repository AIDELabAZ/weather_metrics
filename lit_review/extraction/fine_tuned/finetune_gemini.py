import fitz  # PyMuPDF
import os
import time
import re
import csv as _csv
from datetime import datetime

from google import genai
from google.genai import types


# -------------------------------------------------------------------
# Config — update these before running
# -------------------------------------------------------------------

GCP_PROJECT   = "311885870283"
GCP_LOCATION  = "us-west1"
ENDPOINT_ID   = "938070335469649920"
ENDPOINT_NAME = f"projects/{GCP_PROJECT}/locations/{GCP_LOCATION}/endpoints/{ENDPOINT_ID}"

DEFAULT_MAX_OUTPUT_TOKENS = 512
MAX_OUTPUT_TOKENS_BY_KEY = {
    "Title": 256,
    "DOI": 128,
    "Empirical Analysis": 256,
    "Dependent Variable(s)": 512,
    "Endogeneity Bundle": 512,
    "IV Bundle": 512,
    "Rainfall IV Bundle": 512,
    "Rainfall Instrument Reask": 512,
}

STOP_SEQUENCES_BY_KEY = {
    "Title": ["\n\n"],
    "DOI": ["\n\n"],
    "Empirical Analysis": ["\n", " "],
    "Dependent Variable(s)": ["\n\n"],
    "Endogeneity Bundle": ["\n\n"],
    "IV Bundle": ["\n\n"],
    "Rainfall IV Bundle": ["\n\n"],
    "Rainfall Instrument Reask": ["\n\n"],
}

TEMPERATURE = 0.0

# Must match conversion_code_gemini.py exactly
SYSTEM_INSTRUCTION = (
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

# Must match conversion_code_gemini.py exactly
QUESTION_SUFFIX = (
    "\n\nAnswer using only the article text above and, if helpful, your previous answers in this conversation. "
    "Remember to follow the required output format exactly."
)


# -------------------------------------------------------------------
# Questions (identical to conversion_code_gemini.py)
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
        ),
    },
    {
        "key": "Dependent Variable(s)",
        "question": (
            "Task: List the main dependent/outcome variable(s) used in the primary regression/econometric results.\nLook: LHS of main equations; column headers of main regression tables; text describing the main empirical model.\nRules: exclude first-stage outcomes, RHS variables (treatments/endogenous regressors/instruments/controls/covariates/fixed effects), mediators/moderators.\nKeep names exactly as written in the paper/table (including any log/ln/differences/units if shown).\nOutput: ONE line: variable name(s) only; separate multiple with '; '."
        ),
        "dependency": {"key": "Empirical Analysis", "value": "1"},
    },
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
# Cleaning helpers
# -------------------------------------------------------------------

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
        val = None
        for ln in lines:
            m = pat.match(ln)
            if m:
                val = m.group(1).strip()
                break
        if val is None:
            continue
        if kind == "binary_just":
            b, j = normalize_binary_with_justification(val)
            out[tkey] = b
            if j:
                just[tkey] = j
        elif kind == "var_list":
            out[tkey] = clean_variable_list(val)
        else:
            out[tkey] = val.strip() if val.strip() else "n/a"
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


# -------------------------------------------------------------------
# PDF extraction
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
# Single-turn query — matches training format exactly
# -------------------------------------------------------------------

_client = None

def get_client():
    global _client
    if _client is None:
        _client = genai.Client(vertexai=True, project=GCP_PROJECT, location=GCP_LOCATION)
    return _client


def _part(text):
    """Wrap text in Vertex AI parts format (matches conversion_code_gemini.py)."""
    return [{"text": text}]


def initial_contents(doc_context):
    """
    Build the opening two turns of the conversation, identical to the first
    two entries of `contents` in conversion_code_gemini.py's build_record().
    """
    return [
        {
            "role": "user",
            "parts": _part(
                "You will be asked a sequence of extraction questions about the same academic article. "
                "I am specifically interested in how researchers address endogeneity problems, particularly "
                "using instrumental variables and especially rainfall-based instruments. "
                "Use answers you have already given as context for later questions when helpful, "
                "but always ground your answers in the provided text.\n\n"
                "Here are the relevant sections from the article:\n\n"
                f"{doc_context}"
            ),
        },
        {
            "role": "model",
            "parts": _part("Understood. I will answer each extraction question using only the provided article text."),
        },
    ]


def query_model_with_history(contents, q_key, max_output_tokens_override=None,
                              max_retries=4, base_delay=2.0):
    client = get_client()
    max_tok = int(max_output_tokens_override) if max_output_tokens_override is not None \
        else MAX_OUTPUT_TOKENS_BY_KEY.get(q_key, DEFAULT_MAX_OUTPUT_TOKENS)
    stop = STOP_SEQUENCES_BY_KEY.get(q_key)

    for attempt in range(max_retries):
        try:
            response = client.models.generate_content(
                model=ENDPOINT_NAME,
                contents=contents,
                config=types.GenerateContentConfig(
                    system_instruction=SYSTEM_INSTRUCTION,
                    temperature=TEMPERATURE,
                    max_output_tokens=max_tok,
                    stop_sequences=stop if stop else None,
                    thinking_config=types.ThinkingConfig(thinking_budget=0),
                )
            )
            answer = response.text.strip()
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


def process_pdfs_conditional_queries(pdf_folder, output_csv):
    # Always overwrite — reprocess all PDFs on every run
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

        doc_context = relevant_sections[:40000]

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

        # Single conversation thread for this PDF (mirrors finetune_gpt.py's `messages`
        # and the multi-turn `contents` structure used in the training data).
        contents = initial_contents(doc_context)

        for q in questions:
            q_key = q["key"]
            q_text = q["question"]

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
                    temp_answers = enforce_dependency_consistency(
                        temp_answers, justifications, verbose=True)
                    continue

            print(f"Querying: {q_key} "
                  f"(max_output_tokens={MAX_OUTPUT_TOKENS_BY_KEY.get(q_key, DEFAULT_MAX_OUTPUT_TOKENS)})")

            question_text = f"Question key: {q_key}.\n{q_text}{QUESTION_SUFFIX}"
            contents.append({"role": "user", "parts": _part(question_text)})

            answer = query_model_with_history(contents, q_key)

            # Append the model's raw answer to the conversation (matches finetune_gpt.py)
            contents.append({"role": "model", "parts": _part(answer)})

            if "field_map" in q:
                parsed, bundle_just = parse_prefixed_lines(answer, q["field_map"])
                for col, val in parsed.items():
                    temp_answers[col] = val
                    info_dict[col] = val
                for col, jtxt in bundle_just.items():
                    justifications[col] = jtxt
                temp_answers = enforce_dependency_consistency(
                    temp_answers, justifications, verbose=True)
                for col in parsed.keys():
                    print(f"Answer for {col}: {info_dict[col]}")

                # Rainfall instrument re-ask when rain=1 but instrument still missing
                if q_key == "Rainfall IV Bundle":
                    if (temp_answers.get("Instrumental Variable Rainfall") == "1"
                            and temp_answers.get("Rainfall Instrument", "n/a") == "n/a"):
                        focused = extract_rainfall_iv_snippets(doc_context)
                        if focused:
                            print("Re-asking rainfall instrument detail with focused context...")
                            reask_q_text = (
                                "Now focus only on the following rainfall- and IV-related snippets "
                                f"from the article:\n\n{focused}\n\n"
                                "Provide EXACTLY one line in this format:\n"
                                "RAINFALL_INSTRUMENT: <detailed semicolon-separated description(s); or n/a>\n\n"
                                "Do not include any other lines or text."
                            )
                            contents.append({"role": "user", "parts": _part(reask_q_text)})
                            retry = query_model_with_history(
                                contents, "Rainfall Instrument Reask",
                                max_output_tokens_override=MAX_OUTPUT_TOKENS_BY_KEY["Rainfall Instrument Reask"],
                            )
                            contents.append({"role": "model", "parts": _part(retry)})
                            parsed2, _ = parse_prefixed_lines(
                                retry,
                                {"RAINFALL_INSTRUMENT": ("Rainfall Instrument", "var_list")}
                            )
                            temp_answers["Rainfall Instrument"] = parsed2.get("Rainfall Instrument", "n/a")
                            info_dict["Rainfall Instrument"] = temp_answers["Rainfall Instrument"]
                            temp_answers = enforce_dependency_consistency(
                                temp_answers, justifications, verbose=True)
                            print(f"Answer for Rainfall Instrument (reask): {info_dict['Rainfall Instrument']}")

                continue

            is_binary = q_key == "Empirical Analysis"
            if is_binary:
                binary_val, justification = normalize_binary_with_justification(answer)
                temp_answers[q_key] = binary_val
                if justification:
                    justifications[q_key] = justification
                    print(f"  Binary: {binary_val}, Justification: {justification[:100]}...")
            else:
                if q_key == "Dependent Variable(s)":
                    answer = clean_variable_list(answer)
                temp_answers[q_key] = answer

            temp_answers = enforce_dependency_consistency(
                temp_answers, justifications, verbose=True)
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
    pdf_folder = "/Users/kieran/Library/CloudStorage/OneDrive-UniversityofArizona/weather_iv_lit/training/models/finetune_data/pdf_test_20"
    output_folder = "/Users/kieran/Library/CloudStorage/OneDrive-UniversityofArizona/weather_iv_lit/training/models/output"
    os.makedirs(output_folder, exist_ok=True)
    output_csv = os.path.join(output_folder, "finetune_gemini_aistudio_output.csv")

    process_pdfs_conditional_queries(pdf_folder, output_csv)
    print(f"Script finished: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
