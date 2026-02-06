import fitz  # PyMuPDF
import os
import pandas as pd
from openai import OpenAI
import re
from datetime import datetime


# -------------------------------------------------------------------
# Config knobs you can tweak
# -------------------------------------------------------------------


# Initialize the OpenAI client
# Tip: consider using an environment variable instead of hardcoding the key.
client = OpenAI(api_key="key")


# Fine-tuned model ID
fine_tuned_model_id = "ft:gpt-4.1-mini-2025-04-14:aide-lab:janrun:D3DMZE4c"


DEFAULT_MAX_COMPLETION_TOKENS = 100
MAX_COMPLETION_TOKENS_BY_KEY = {
    "Title": 100,
    "DOI": 30,
    "Empirical Analysis": 10,
    "Dependent Variable(s)": 100,

    # Bundles (dual queries)
    "Endogeneity Bundle": 100,
    "IV Bundle": 100,
    "Rainfall IV Bundle": 100,

    # Optional re-ask (single-line)
    "Rainfall Instrument Reask": 100,
}

# Second-pass (only used when Rainfall IV=1 but Rainfall Instrument still n/a)
RAINFALL_INSTRUMENT_REASK_MAX_COMPLETION_TOKENS = 120


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


# -------------------------------------------------------------------
# Questions with bundled structure
# -------------------------------------------------------------------


questions = [
    {
        "key": "Title",
        "question": (
            "Extract the article's exact title as it appears in the document. "
            "Look for the main standalone heading near the top of the first page, before the author list and/or abstract. "
            "Include any subtitle that is part of the same heading (e.g., separated by a colon or dash). "
            "Do not include author names, affiliations, journal name, running headers, section titles (e.g., Abstract, Introduction), "
            "or footnote markers/symbols attached to the title. "
            "Output format: Output exactly one line containing only the title text and nothing else."
        ),
    },
    {
        "key": "DOI",
        "question": (
            "Extract the Digital Object Identifier (DOI) of the focal article (version of record). "
            "Look for DOI-like strings near front matter, headers/footers, or citation blocks (e.g., 'doi:', 'DOI', 'https://doi.org/'). "
            "Ignore DOIs that appear only in references unless clearly the article's own DOI. "
            "If both preprint and published DOIs exist, choose the published DOI. "
            "Normalize by stripping prefixes/URL wrappers (e.g., remove 'doi:' and 'https://doi.org/'), removing whitespace/line-break hyphenation, "
            "and trimming trailing punctuation; convert to lowercase. "
            "Output format: Output exactly one token: the normalized DOI (e.g., 10.xxxx/xxxx) or exactly n/a."
        ),
    },
    {
        "key": "Empirical Analysis",
        "question": (
            "Determine whether the provided text contains empirical quantitative statistical analysis. "
            "By empirical quantitative statistical analysis, we mean the article uses regressions, econometrics, "
            "or similar statistical methods to fit a model/equation to data (e.g., estimated coefficients with "
            "standard errors, p-values, confidence intervals; methods like OLS, IV/2SLS, DiD, RDD, fixed effects, "
            "logit/probit, Poisson, GMM, etc.). "
            "Do not infer this from the topic/title alone; verify from the text that estimation is actually done. "
            "If you answer 1, in your response briefly note the key phrase or evidence that confirms empirical analysis "
            "(e.g., 'regression results', 'estimated coefficients'). "
            "Output format: Start with exactly one character: 1 if it contains empirical quantitative statistical analysis, "
            "0 if it does not. If 1, follow with a brief justification on the same line."
        )
    },
    {
        "key": "Dependent Variable(s)",
        "question": (
            "Only proceed if the text contains empirical quantitative statistical analysis. "
            "Identify the dependent (outcome) variable(s) in the main regression models (left-hand-side outcomes). "
            "Do not include first-stage outcomes, treatments, instruments, controls, fixed effects, or other RHS variables. "
            "Normalize names: do not output symbolic notation; remove transformations (e.g., if 'log income' then output 'income'); "
            "remove units/parentheses that are not part of the core name; keep names consistent across papers. "
            "Output format: exactly one line; lower case; a semicolon-separated list with a single space after each semicolon; "
            "do not repeat variables; if none can be identified from the text, output exactly n/a."
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
            "Part A (binary): Determine whether the authors explicitly identify/discuss an endogeneity problem "
            "(omitted variable bias, reverse causality, measurement error, simultaneity, selection, etc.). \n"
            "Part B (list): If you found that there was an explicitly mentioned endogeneity problem in the text, identify the specific explanatory variable(s) the authors treat as endogenous "
            "(these will not be instruments,  outcomes, or controls). If Part A != 1, output n/a.\n\n"
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
            "Only proceed if an endogeneity problem is identified. "
            "Answer BOTH parts below using ONLY the provided article text.\n\n"
            "Part A (binary): Determine whether the article uses an instrumental variable (IV) regression method with excluded instruments "
            "(IV/2SLS/LIML/3SLS, control-function/2SRI, IV-probit/logit/tobit, etc.). \n"
            "Part B (list): If you identified use of an instrumental variable in part A, list the excluded instrument variable(s) used in the main IV analysis "
            "(first stage, excluded from structural equation). If Part A != 1, output n/a.\n\n"
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
            "Only proceed if IV regression is used. "
            "Answer BOTH parts below using ONLY the provided article text.\n\n"
            "Part A (binary): Determine whether any excluded instrument in the IV framework is based on rainfall/precipitation "
            "(including anomalies/shocks/deviations; SPI/SPEI/PDSI/scPDSI; wet-day counts; intensity; snowfall/snowpack/SWE). "
            "Confirm it is an excluded instrument (not just a control). \n"
            "Part B (detail): If you found that some rainfall metric was used as an instrumental variable in part A, state that exact rainfall/precipitation-based excluded instrument metric(s)  "
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

        p = re.split(r"\\s[-–]\\s", p)[0].strip()
        p = re.split(r"\\s(?:such as|for|where|which|that)\\b", p, flags=re.I)[0].strip()
        p = p.strip("\\\"\"''")

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
        else:  # "text"
            out[tkey] = val.strip() if val.strip() else "n/a"

    return out, just


# -------------------------------------------------------------------
# Accuracy check helpers
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
# PDF extraction
# -------------------------------------------------------------------


def extract_relevant_sections(pdf_path):
    relevant_sections = []
    keywords = [
        "instrument", "instrumental variable", "data", "methods", "iv",
        "rainfall", "model", "econometric", "metrics", "introduction",
        "abstract", "conclusion", "strategy", "empirical", "estimation",
        "outcome", "precipitation", "first stage", "first-stage",
        "endogeneity", "endogenous", "identification", "2SLS", "first stage",
        "second stage", "doi", "strategy", "excluded", "estimate", "effect", "affects", "exogenous",
        "two-stage least squares", "first stage", "2sls", "GMM", "fixed effects"
    ]

    try:
        with fitz.open(pdf_path) as doc:
            for page_num in range(len(doc)):
                page = doc.load_page(page_num)
                page_text = page.get_text("text")
                paragraphs = page_text.split("\n\n")
                for paragraph in paragraphs:
                    if any(keyword.lower() in paragraph.lower() for keyword in keywords):
                        relevant_sections.append(paragraph)
    except Exception as e:
        print(f"Error extracting PDF {pdf_path}: {e}")
        return ""

    return " ".join(relevant_sections)


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


def query_model_with_history(messages, q_key, is_binary=False, max_completion_tokens_override=None):
    max_comp = int(max_completion_tokens_override) if max_completion_tokens_override is not None else get_max_completion_tokens(q_key)
    stop = get_stop_sequences(q_key)

    try:
        kwargs = dict(
            model=fine_tuned_model_id,
            messages=messages,
            max_tokens=max_comp,
            temperature=TEMPERATURE,
        )
        if stop:
            kwargs["stop"] = stop

        response = client.chat.completions.create(**kwargs)
        answer = response.choices[0].message.content.strip()

        if not answer:
            return "n/a"

        return answer

    except Exception as e:
        print(f"Error querying model ({q_key}): {e}")
        return "n/a"


# -------------------------------------------------------------------
# Main processing
# -------------------------------------------------------------------


def process_pdfs_conditional_queries(pdf_folder, output_csv):
    data = []

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
        ]

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
                                max_completion_tokens_override=RAINFALL_INSTRUMENT_REASK_MAX_COMPLETION_TOKENS,
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

            # Apply consistency checks after each answer
            temp_answers = enforce_dependency_consistency(temp_answers, justifications, verbose=True)

            info_dict[q_key] = temp_answers[q_key]
            print(f"Answer for {q_key}: {info_dict[q_key]}")

        # Final global consistency pass
        info_dict = enforce_dependency_consistency(info_dict, justifications, verbose=False)

        print(f"Final extracted info for {filename}: {info_dict}")
        data.append(info_dict)

    df = pd.DataFrame(data)
    df.to_csv(output_csv, index=False)
    print(f"Data saved to {output_csv}")


# -------------------------------------------------------------------
# Paths and execution
# -------------------------------------------------------------------


if __name__ == "__main__":
    pdf_folder = "/Users/kieran/Library/CloudStorage/OneDrive-UniversityofArizona/weather_iv_lit/training/models/finetune_data/pdf_test_20"
    output_folder = "/Users/kieran/Library/CloudStorage/OneDrive-UniversityofArizona/weather_iv_lit/training/models/output"
    os.makedirs(output_folder, exist_ok=True)
    output_csv = os.path.join(output_folder, "finetune_output.csv")

    process_pdfs_conditional_queries(pdf_folder, output_csv)


print(f"Script finished: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
