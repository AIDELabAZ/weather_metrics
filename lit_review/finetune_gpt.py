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
client = OpenAI(api_key="key")


# Fine-tuned model ID
fine_tuned_model_id = "ft:gpt-4.1-mini-2025-04-14:aide-lab:janrun:D3DMZE4c"

DEFAULT_MAX_COMPLETION_TOKENS = 80
MAX_COMPLETION_TOKENS_BY_KEY = {
    "Paper Title": 30,
    "DOI": 40,
    "Dependent Variables": 40,
    "Endogenous Variable(s)": 40,
    "Instrumental Variable Used": 10,
    "Instrumental Variable(s)": 40,
    "Instrumental Variable Rainfall": 10,
    "Rainfall Metric": 40,
    "Rainfall Data Source": 40,
    "Is Academic Paper": 10,
}

# Second-pass (only used when Rainfall IV=1 but Rainfall Metric still n/a)
RAINFALL_METRIC_REASK_MAX_COMPLETION_TOKENS = 80
RAINFALL_SOURCE_REASK_MAX_COMPLETION_TOKENS = 80

STOP_SEQUENCES_BY_KEY = {
    "Paper Title": ["\n\n"],
    "DOI": ["\n\n"],
    "Dependent Variables": ["\n\n"],
    "Endogenous Variable(s)": ["\n\n"],
    "Instrumental Variable(s)": ["\n\n"],
    "Rainfall Metric": ["\n\n"],
    "Rainfall Data Source": ["\n\n"],
    "Instrumental Variable Used": ["\n", " "],
    "Instrumental Variable Rainfall": ["\n", " "],
    "Is Academic Paper": ["\n", " "],
}

TEMPERATURE = 0.1  # for extraction, 0.0 usually improves stability

# -------------------------------------------------------------------
# Questions
# -------------------------------------------------------------------

questions = [
    {
        "key": "Is Academic Paper",
        "question": (
            "Determine whether the provided text contains empirical quantitative statistical analysis. "
            "By empirical quantitative statistical analysis, we mean the article uses regressions, econometrics, "
            "or similar statistical methods to fit a model/equation to data (e.g., estimated coefficients with "
            "standard errors, p-values, confidence intervals; methods like OLS, IV/2SLS, DiD, RDD, fixed effects, "
            "logit/probit, Poisson, GMM, etc.). "
            "Do not infer this from the topic/title alone; verify from the text that estimation is actually done. "
            "Output format: Output exactly one character: 1 if it contains empirical quantitative statistical analysis, "
            "0 if it does not. No other text."
        )
    },

    {
        "key": "Paper Title",
        "question": (
            "Extract the article’s exact title as it appears in the document. "
            "Look for the main standalone heading near the top of the first page, before the author list and/or abstract. "
            "Include any subtitle that is part of the same heading (e.g., separated by a colon or dash). "
            "Do not include author names, affiliations, journal name, running headers, section titles (e.g., Abstract, Introduction), "
            "or footnote markers/symbols attached to the title. "
            "Output format: Output exactly one line containing only the title text and nothing else."
        ),
        "dependency": {"key": "Is Academic Paper", "value": "1"},
    },

    {
        "key": "DOI",
        "question": (
            "Extract the Digital Object Identifier (DOI) of the focal article (version of record). "
            "Look for DOI-like strings near front matter, headers/footers, or citation blocks (e.g., 'doi:', 'DOI', 'https://doi.org/'). "
            "Ignore DOIs that appear only in references unless clearly the article’s own DOI. "
            "If both preprint and published DOIs exist, choose the published DOI. "
            "Normalize by stripping prefixes/URL wrappers (e.g., remove 'doi:' and 'https://doi.org/'), removing whitespace/line-break hyphenation, "
            "and trimming trailing punctuation; convert to lowercase. "
            "Output format: Output exactly one token: the normalized DOI (e.g., 10.xxxx/xxxx) or exactly n/a."
        ),
        "dependency": {"key": "Is Academic Paper", "value": "1"},
    },

    {
        "key": "Dependent Variables",
        "question": (
            "Only proceed if the text contains empirical quantitative statistical analysis. "
            "Identify the dependent (outcome) variable(s) in the main regression models (left-hand-side outcomes). "
            "Do not include first-stage outcomes, treatments, instruments, controls, fixed effects, or other RHS variables. "
            "Normalize names: do not output symbolic notation; remove transformations (e.g., if 'log income' then output 'income'); "
            "remove units/parentheses that are not part of the core name; keep names consistent across papers. "
            "Output format: exactly one line; lower case; a semicolon-separated list with a single space after each semicolon; "
            "do not repeat variables; if none can be identified from the text, output exactly n/a."
        ),
        "dependency": {"key": "Is Academic Paper", "value": "1"},
    },

    {
        "key": "Endogenous Variable(s)",
        "question": (
            "Only proceed if the text contains empirical quantitative statistical analysis. "
            "Identify the explanatory variable(s) the authors explicitly treat as endogenous in the main empirical analysis "
            "(i.e., variables they say are endogenous/potentially endogenous and instrument or otherwise treat as endogenous). "
            "Do not include dependent variables, instruments, controls, or generic phrases without specific variable names. "
            "Do not output symbolic notation; remove transformations (e.g., 'ln fertilizer' -> 'fertilizer') and units; "
            "print everything in lower case; semicolon-separated with a single space after each semicolon; no more than three. "
            "If no endogenous explanatory variable is explicitly identified, output exactly n/a."
        ),
        "dependency": {"key": "Is Academic Paper", "value": "1"},
    },

    {
        "key": "Instrumental Variable Used",
        "question": (
            "Determine whether the article uses an instrumental variable (IV) regression method with excluded instruments "
            "to address endogeneity (e.g., IV/2SLS/LIML/3SLS, IV-probit/logit/tobit, control-function/2SRI, dynamic panel GMM with instruments, etc.). "
            "Ignore non-statistical uses of 'instrument' (e.g., survey instrument). "
            "Do not classify as IV based only on generic mentions or citations to other work; confirm the article implements an IV-type estimator "
            "with excluded instruments (e.g., first stage, instrument set, weak-instrument/over-id tests) in its own analysis. "
            "Output format: Output exactly one character: 1 if IV regression is used, 0 if not. No other text."
        ),
        "dependency": {"key": "Is Academic Paper", "value": "1"},
    },

    {
        "key": "Instrumental Variable(s)",
        "question": (
            "Only proceed if the previous question 'Instrumental Variable Used' was answered 1. "
            "Identify the excluded instrument variable(s) used in the main IV analysis (i.e., variables that enter the first stage "
            "and are excluded from the structural equation). "
            "Do not include endogenous regressors, controls, fixed effects, time trends, lags used only as controls, or non-IV design elements. "
            "Normalize names: do not output symbolic notation; remove transformations and units when they are not part of the core name; "
            "print everything in lower case. "
            "Output format: exactly one line; semicolon-separated with a single space after each semicolon; do not repeat; "
            "no more than three; or exactly n/a."
        ),
        "dependency": {"key": "Instrumental Variable Used", "value": "1"},
    },

    {
        "key": "Instrumental Variable Rainfall",
        "question": (
            "Only proceed if the previous question 'Instrumental Variable Used' was answered 1. "
            "Determine whether any excluded instrument used in the article’s IV framework is based on rainfall or precipitation "
            "(including precipitation-derived indices such as anomalies/shocks/deviations, standardized precipitation, cumulative rainfall, "
            "wet-day counts, precipitation intensity, or drought/wetness indices like SPI/SPEI/PDSI/scPDSI; also snowfall/snowpack/SWE). "
            "Do not count rainfall if it is only a control/exposure/outcome or appears only in non-IV designs; confirm it is an excluded instrument. "
            "Output format: Output exactly one character: 1 if yes, 0 if no. No other text."
        ),
        "dependency": {"key": "Instrumental Variable Used", "value": "1"},
    },

    {
        "key": "Rainfall Metric",
        "question": (
            "Only proceed if the previous question 'Instrumental Variable Rainfall' was answered 1. "
            "Identify the specific rainfall/precipitation-based excluded instrument metric(s) used. "
            "Hard constraint: it must NOT be only 'rainfall'/'precipitation'; it must preserve both (i) the statistic/transform "
            "(e.g., total/mean/std dev/z-score/anomaly/deviation/negative deviation/cumulative, etc.) and (ii) the time scale "
            "(e.g., daily/monthly/seasonal/annual, or specific season/window). "
            "Do not output symbolic notation; remove units like mm; print in lower case. "
            "Output format: exactly one line; semicolon-separated with a single space after each semicolon; no more than three; or exactly n/a."
        ),
        "dependency": {"key": "Instrumental Variable Rainfall", "value": "1"},
    },

    {
        "key": "Rainfall Data Source",
        "question": (
            "Only proceed if the previous question 'Instrumental Variable Rainfall' was answered 1. "
            "What is the source/dataset/provider of the rainfall/precipitation data used for the rainfall-based instrument(s)? "
            "Report the dataset/provider name (e.g., CHIRPS, TRMM, ERA5, NOAA, Indian Meteorological Department), or n/a. "
            "Output format: Output only the source name, or exactly n/a."
        ),
        "dependency": {"key": "Instrumental Variable Rainfall", "value": "1"},
    },
]

# -------------------------------------------------------------------
# Cleaning helpers
# -------------------------------------------------------------------

def normalize_yes_no(answer):
    if not answer:
        return "n/a"
    a = answer.strip().lower()
    if a.startswith("yes") or a == "1":
        return "1"
    if a.startswith("no") or a == "0":
        return "0"
    if a in {"n/a", "na"}:
        return "n/a"
    return "n/a"

def clean_dependent_variables(raw_text):
    if not raw_text:
        return "n/a"
    cleaned = re.sub(r"\d+\)\s*", "", raw_text)
    variables = [var.strip() for var in cleaned.split(",") if var.strip()]
    return ", ".join(variables) if variables else "n/a"

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
    
    txt = txt.replace("\n", " ")
    txt = txt.replace(" and ", "; ")
    
    parts = re.split(r"[;,]", txt)
    
    cleaned = []
    for p in parts:
        p = p.strip().strip(".").strip()
        if not p:
            continue
        
        p = re.split(r"\s[-–]\s", p)[0].strip()
        p = re.split(r"\s(?:such as|for|where|which|that)\b", p, flags=re.I)[0].strip()
        p = p.strip("\"\"\"'")
        
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

def clean_rainfall_source(raw_text):
    if not raw_text:
        return "n/a"
    txt = raw_text.strip()
    
    if txt.lower() in {"n/a", "na", "none"}:
        return "n/a"
    
    txt = re.split(r"[.\n]", txt, 1)[0].strip()
    txt = re.sub(r"^(from|data from|rainfall data from)\s+", "", txt, flags=re.I)
    txt = txt.strip("\"\"\"'").strip(" .,")
    
    return txt if txt else "n/a"

# -------------------------------------------------------------------
# NEW: rainfall inference + metric extraction from IV list
# -------------------------------------------------------------------

RAINFALL_TERMS = [
    "rainfall", "precipitation", "rain", "precip",
    "monsoon", "drought", "shocks", "weather", "typhoon", "hurricane", "storm", "drought"
]

def iv_list_mentions_rainfall(iv_list_text: str) -> bool:
    if not iv_list_text:
        return False
    t = iv_list_text.strip().lower()
    if t in {"n/a", "na", "none"}:
        return False
    return any(term in t for term in RAINFALL_TERMS)

def extract_rainfall_metrics_from_iv_list(iv_list_text: str) -> str:
    """
    If IV list includes rainfall instruments, return those entries as the rainfall metric(s).
    This prevents Rainfall Metric = n/a when your IV list already contains a rainfall instrument phrase.
    """
    if not iv_list_text:
        return "n/a"
    t = iv_list_text.strip()
    if t.lower() in {"n/a", "na", "none"}:
        return "n/a"
    
    parts = [p.strip() for p in t.split(";") if p.strip()]
    keep = []
    for p in parts:
        pl = p.lower()
        if any(term in pl for term in RAINFALL_TERMS):
            keep.append(pl)
    
    seen, uniq = set(), []
    for k in keep:
        if k not in seen:
            seen.add(k)
            uniq.append(k)
    
    return "; ".join(uniq) if uniq else "n/a"

def extract_rainfall_iv_snippets(full_text: str, max_chars: int = 9000) -> str:
    """
    Second-pass context reducer: keep only paragraphs likely to mention rainfall instruments + their construction.
    """
    if not full_text:
        return ""
    
    paras = [p.strip() for p in full_text.split("\n\n") if p.strip()]
    keep = []
    for p in paras:
        pl = p.lower()
        if any(term in pl for term in RAINFALL_TERMS) and (
            "instrument" in pl or "iv" in pl or "2sls" in pl or "first stage" in pl or "first-stage" in pl or "excluded" in pl
        ):
            keep.append(p)
    
    out = "\n\n".join(keep)
    if len(out) > max_chars:
        out = out[:max_chars]
    return out

# -------------------------------------------------------------------
# Dependency consistency enforcer (UPDATED)
# -------------------------------------------------------------------

def enforce_dependency_consistency(temp_answers, *, verbose=False):
    is_paper = temp_answers.get("Is Academic Paper", "0")
    iv_used = temp_answers.get("Instrumental Variable Used", "n/a")
    rain_iv = temp_answers.get("Instrumental Variable Rainfall", "n/a")
    
    # Academic gate
    if is_paper != "1":
        for k in [
            "Paper Title", "DOI", "Dependent Variables", "Endogenous Variable(s)",
            "Instrumental Variable Used", "Instrumental Variable(s)",
            "Instrumental Variable Rainfall", "Rainfall Metric", "Rainfall Data Source"
        ]:
            temp_answers[k] = "n/a"
        return temp_answers
    
    # IV gate
    if iv_used != "1":
        temp_answers["Instrumental Variable(s)"] = "n/a"
        temp_answers["Instrumental Variable Rainfall"] = "n/a"
        temp_answers["Rainfall Metric"] = "n/a"
        temp_answers["Rainfall Data Source"] = "n/a"
        return temp_answers
    
    # If IV list implies rainfall, force rainfall flag to 1
    iv_list = temp_answers.get("Instrumental Variable(s)", "")
    if iv_list_mentions_rainfall(iv_list):
        if verbose and temp_answers.get("Instrumental Variable Rainfall") != "1":
            print("Overriding Instrumental Variable Rainfall -> 1 because IV list mentions rainfall/precip.")
        temp_answers["Instrumental Variable Rainfall"] = "1"
        rain_iv = "1"
    
    # Rainfall gate
    if rain_iv != "1":
        temp_answers["Rainfall Metric"] = "n/a"
        temp_answers["Rainfall Data Source"] = "n/a"
        return temp_answers
    
    # If rainfall IV = 1 and rainfall metric is missing/binary, fill from IV list
    rm = (temp_answers.get("Rainfall Metric") or "").strip().lower()
    if rm in {"", "n/a", "0", "1"}:
        inferred = extract_rainfall_metrics_from_iv_list(iv_list)
        if inferred != "n/a":
            if verbose:
                print("Filling Rainfall Metric from rainfall entries in IV list.")
            temp_answers["Rainfall Metric"] = inferred
    
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
        "outcome", "precipitation", "first stage", "first-stage"
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

def query_model_with_history(messages, q_key, enforce_binary=False, max_completion_tokens_override=None):
    max_comp = int(max_completion_tokens_override) if max_completion_tokens_override is not None else get_max_completion_tokens(q_key)
    stop = get_stop_sequences(q_key)
    
    try:
        kwargs = dict(
            model=fine_tuned_model_id,
            messages=messages,
            max_tokens=max_comp,  # CHANGED: use max_tokens instead of max_completion_tokens
            temperature=TEMPERATURE,
        )
        if stop:
            kwargs["stop"] = stop
        
        response = client.chat.completions.create(**kwargs)
        answer = response.choices[0].message.content.strip()
        
        if not answer:
            return "n/a"
        if enforce_binary:
            return normalize_yes_no(answer)
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
        
        max_tokens = 6000
        text_to_analyze = relevant_sections[: max_tokens * 4]
        
        info_dict = {
            "File Name": filename,
            "Is Academic Paper": "0",
            "Paper Title": "n/a",
            "DOI": "n/a",
            "Dependent Variables": "n/a",
            "Endogenous Variable(s)": "n/a",
            "Instrumental Variable Used": "n/a",
            "Instrumental Variable(s)": "n/a",
            "Instrumental Variable Rainfall": "n/a",
            "Rainfall Metric": "n/a",
            "Rainfall Data Source": "n/a",
        }
        
        temp_answers = info_dict.copy()
        
        # Single conversation thread for this PDF
        messages = [
            {
                "role": "system",
                "content": (
                    "You are an AI assistant that is an expert in analysis of economic literature. "
                    "You interpret complex content and extract specific information, especially metadata. "
                    "Rules: Use only information from the provided text to answer each query. If the requested information is not available, answer exactly n/a. Follow the requested output format exactly. "
                    "Exclusions: Do not include the user queries, any labels, greek letters, or additional text in your response. Do not respond with symbolic notation, only words. "
                ),
            },
            {
                "role": "user",
                "content": (
                    "You will be asked a sequence of extraction questions about the same academic article. I am specifically interested in how researchers used rainfall metrics as an instrumental variables. "
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
                
                if current_dep_answer != dep_val:
                    print(
                        f"Skipping '{q_key}' due to unmet dependency "
                        f"({dep_key}={current_dep_answer} != {dep_val})"
                    )
                    temp_answers[q_key] = "n/a"
                    temp_answers = enforce_dependency_consistency(temp_answers, verbose=True)
                    info_dict[q_key] = temp_answers[q_key]
                    continue
            
            enforce_binary = q_key in [
                "Is Academic Paper",
                "Instrumental Variable Used",
                "Instrumental Variable Rainfall",
            ]
            
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
                enforce_binary=enforce_binary,
            )
            
            # Append the model's raw answer to the conversation
            messages.append({"role": "assistant", "content": answer})
            
            # Post-processing
            if q_key == "Dependent Variables" and answer != "n/a":
                answer = clean_dependent_variables(answer)
            
            if q_key in ["Endogenous Variable(s)", "Instrumental Variable(s)", "Rainfall Metric"]:
                answer = clean_variable_list(answer)
            
            if q_key == "Rainfall Data Source":
                answer = clean_rainfall_source(answer)
            
            if enforce_binary:
                answer = normalize_yes_no(answer)
            
            temp_answers[q_key] = answer
            temp_answers = enforce_dependency_consistency(temp_answers, verbose=True)
            
            # SECOND PASS: Rainfall Metric
            if q_key == "Rainfall Metric":
                if temp_answers.get("Instrumental Variable Rainfall") == "1" and temp_answers.get("Rainfall Metric", "n/a") == "n/a":
                    focused = extract_rainfall_iv_snippets(text_to_analyze)
                    if focused:
                        print("Re-asking Rainfall Metric with rainfall/IV-focused context...")
                        messages.append({
                            "role": "user",
                            "content": (
                                "Now focus only on the following rainfall- and IV-related snippets from the article:\n\n"
                                f"{focused}\n\n"
                                f"Re-ask for key: Rainfall Metric.\n{q['question']}\n\n"
                                "Answer again, correcting your previous answer if needed, and follow the same output format."
                            ),
                        })
                        retry = query_model_with_history(
                            messages,
                            q_key="Rainfall Metric",
                            enforce_binary=False,
                            max_completion_tokens_override=RAINFALL_METRIC_REASK_MAX_COMPLETION_TOKENS,
                        )
                        messages.append({"role": "assistant", "content": retry})
                        retry = clean_variable_list(retry)
                        temp_answers["Rainfall Metric"] = retry
                        temp_answers = enforce_dependency_consistency(temp_answers, verbose=True)
            
            # SECOND PASS: Rainfall Data Source
            if q_key == "Rainfall Data Source":
                if temp_answers.get("Instrumental Variable Rainfall") == "1" and temp_answers.get("Rainfall Data Source", "n/a") == "n/a":
                    focused = extract_rainfall_iv_snippets(text_to_analyze)
                    if focused:
                        print("Re-asking Rainfall Data Source with rainfall/IV-focused context...")
                        messages.append({
                            "role": "user",
                            "content": (
                                "Now focus only on the following rainfall- and IV-related snippets from the article:\n\n"
                                f"{focused}\n\n"
                                f"Re-ask for key: Rainfall Data Source.\n{q['question']}\n\n"
                                "Answer again, correcting your previous answer if needed, and follow the same output format."
                            ),
                        })
                        retry = query_model_with_history(
                            messages,
                            q_key="Rainfall Data Source",
                            enforce_binary=False,
                            max_completion_tokens_override=RAINFALL_SOURCE_REASK_MAX_COMPLETION_TOKENS,
                        )
                        messages.append({"role": "assistant", "content": retry})
                        retry = clean_rainfall_source(retry)
                        temp_answers["Rainfall Data Source"] = retry
                        temp_answers = enforce_dependency_consistency(temp_answers, verbose=True)
            
            info_dict[q_key] = temp_answers[q_key]
            print(f"Answer for {q_key}: {info_dict[q_key]}")
        
        # Final global consistency pass
        info_dict = enforce_dependency_consistency(info_dict, verbose=False)
        
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
