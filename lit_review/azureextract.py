import fitz  # PyMuPDF
import os
import time
import pandas as pd
from openai import AzureOpenAI
import re

# -------------------------------------------------------------------
# Config knobs you can tweak - UPDATE THESE FOR YOUR AZURE SETUP
# -------------------------------------------------------------------
AZURE_ENDPOINT = "https://your-resource-name.openai.azure.com/"  # Your Azure endpoint
AZURE_API_KEY = "your-azure-api-key"  # Your Azure API key
AZURE_DEPLOYMENT_NAME = "phi-3-5-mini-instruct"  # Your Phi-3.5 deployment name

# Initialize the Azure OpenAI client
client = AzureOpenAI(
    azure_endpoint=AZURE_ENDPOINT,
    api_key=AZURE_API_KEY, 
    api_version="2024-10-21"  # Recent API version for Phi-3.5
)

# Use Phi-3.5 model deployment instead of fine-tuned GPT
MODEL_NAME = AZURE_DEPLOYMENT_NAME

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
            "Determine whether the provided PDF text is an academic paper.\n"
            "An academic paper typically has a title, author list, abstract, sections (e.g., introduction, data, methods), and references.\n"
            "Non-papers include posters, slide decks/presentations, proposals, memos, syllabi, or random excerpts.\n"
            "Output format: Output exactly one character: 1 if it is an academic paper, 0 if it is not. No other text."
        )
    },
    {
        "key": "Paper Title",
        "question": (
            "Extract the exact title of the article from the provided text. "
            "The title is the main standalone name of the article itself. "
            "Do not include anything that is not simply the title of the article."
            "Ignore human names, introduction, abstract, and journal names. "
            "Output format: Output exactly one line containing only the title of the article and nothing else."
        ),
        "dependency": {"key": "Is Academic Paper", "value": "1"},
    },
    {
        "key": "DOI",
        "question": (
            "Extract the DOI of the focal article (version of record). "
            "A DOI is a string that starts with 10. and contains a slash. "
            "Only return the DOI of the article itself, not DOIs of referenced articles, datasets, or supplements. "
            "If more than one DOI appears, choose the one that is presented as the article's own DOI in the front matter or header. "
            "Output format: Output exactly one token: either the DOI string (as it appears, trimmed of leading \"doi:\" or \"https://doi.org/\") "
            "or exactly n/a if the article has no DOI. Do not output any extra text, labels, or punctuation."
        ),
        "dependency": {"key": "Is Academic Paper", "value": "1"},
    },
    {
        "key": "Dependent Variables",
        "question": (
            "Extract the dependent variable name or names used in the article's main analysis. "
            "This is the outcome or effect being measured by the researcher. "
            "Do not output single letters, Greek symbols, equations, or purely symbolic notation. "
            "If the article does not estimate any regression or statistical model with a clearly defined dependent variable in the main analysis, return exactly \"n/a\". "
            "Output format: exactly one line containing either a single dependent variable name, a semicolon-separated list of no more than three names, or \"n/a\""
        ),
        "dependency": {"key": "Is Academic Paper", "value": "1"},
    },
    {
        "key": "Endogenous Variable(s)",
        "question": (
            "Extract the primary explanatory variable name or names that the authors explicitly treat as endogenous in the main empirical analysis. "
            "This is an independent variable in a regression model that correlates with the error term, biasing estimates. "
            "Normalize each selected variable to a short, human-readable descriptive name that reflects its substantive meaning. "
            "Do not use single letters, Greek symbols, equations, or purely symbolic notation. "
            "Do not output internal dataset or code variable names unless they are self-explanatory without additional context. "
            "If no endogenous explanatory variable is explicitly identified in the main analysis, return exactly \"n/a\". "
            "Output format: exactly one line containing the endogenous explanatory variable name(s), a semicolon-separated list of no more than three names, or \"n/a\" "
        ),
        "dependency": {"key": "Is Academic Paper", "value": "1"},
    },
    {
        "key": "Instrumental Variable Used",
        "question": (
            "Determine whether the authors of the article used an instrumental variable (IV) in their main empirical analysis. "
            "This is a regression method to address endogeneity in independent variables. Instrumental variable methods use excluded instruments in a formal IV framework. "
            "Ignore non-statistical uses of the word \"instrument\" (e.g., survey instrument, measurement instrument). "
            "Do not classify the article as using instrumental variable regression based only on generic mentions of IV. "
            "Do not use single letters, Greek symbols, equations, or purely symbolic notation. "
            "Output format: Output 1 if the article uses an IV in this sense. Output 0 if it does not. Output exactly one character, either 1 or 0, with no additional text."
        ),
        "dependency": {"key": "Is Academic Paper", "value": "1"},
    },
    {
        "key": "Instrumental Variable(s)",
        "question": (
            "Only proceed if the previous question \"Instrumental Variable Used\" was answered 1.\n"
            "If the authors used an IV, identify the instrumental variable(s) used in the main analysis.\n"
            "This is a regression method to address endogeneity in independent variables. Instrumental variable methods use excluded instruments in a formal IV framework. "
            "Return only the name(s) of the instrumental variable(s), no commentary; lower case; semicolon-separated; or n/a."
            "Do not use single letters, Greek symbols, equations, or purely symbolic notation. "
            "Output format: exactly one line containing either a single instrumental variable variable name, a semicolon-separated list of no more than three names, or \"n/a\""
        ),
        "dependency": {"key": "Instrumental Variable Used", "value": "1"},
    },
    {
        "key": "Instrumental Variable Rainfall",
        "question": (
            "Only proceed if the previous question \"Instrumental Variable Used\" was answered 1.\n"
            "If the authors used an instrumental variable in their analysis, were any of these instruments based on rainfall or precipitation?\n"
            "This means employing rainfall measurements as an exogenous shock to identify causal effects in econometric analysis. "
            "Output 1 if yes, 0 if no. Exactly one character."
        ),
        "dependency": {"key": "Instrumental Variable Used", "value": "1"},
    },
    {
        "key": "Rainfall Metric",
        "question": (
            "Only proceed if the previous question \"Instrumental Variable Rainfall\" was answered 1.\n"
            "If the authors used rainfall or percipitation metric as an instrumental variable, identify which specific instrument metric(s) were used.\n"
            "This means that they employed rainfall measurements as an exogenous shock to identify causal effects in econometric analysis. "
            "Hard constraint: it must NOT be just 'rainfall' or 'precipitation'; it must include statistic/transform/time scale "
            "(e.g., 'log annual rainfall', 'monthly average precipitation', 'z-score of seasonal rainfall').\n"
            "Do not use single letters, Greek symbols, equations, or purely symbolic notation. "
            "Output formet: exactly one line containing only the rainfall metric name(s), a semicolon-separated list of no more than three names, or \"n/a\""
        ),
        "dependency": {"key": "Instrumental Variable Rainfall", "value": "1"},
    },
    {
        "key": "Rainfall Data Source",
        "question": (
            "Only proceed if the previous question \"Instrumental Variable Rainfall\" was answered 1.\n"
            "What is the source of the rainfall data used in the study? "
            "Identify and report the exact dataset/provider (e.g., CHIRPS, TRMM, ERA5, NOAA, Indian Meteorological Department). "
            "Output only the source name, or n/a."
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
# Model query with conversation history (UPDATED FOR AZURE/PHI-3.5)
# -------------------------------------------------------------------
def query_model_with_history(messages, q_key, enforce_binary=False, max_completion_tokens_override=None,
                             max_retries=4, base_delay=2.0):
    max_comp = int(max_completion_tokens_override) if max_completion_tokens_override is not None else get_max_completion_tokens(q_key)
    stop = get_stop_sequences(q_key)

    kwargs = dict(
        model=MODEL_NAME,
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
            if not answer:
                return "n/a"
            if enforce_binary:
                return normalize_yes_no(answer)
            return answer

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
    output_csv = os.path.join(output_folder, "phi35_output.csv")
    
    process_pdfs_conditional_queries(pdf_folder, output_csv)
