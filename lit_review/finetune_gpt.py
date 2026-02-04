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

# Fine-tuned model ID (keep yours here)
fine_tuned_model_id = "ft:gpt-4.1-mini-2025-04-14:aide-lab:janrun:D3DMZE4c"

DEFAULT_MAX_COMPLETION_TOKENS = 40
MAX_COMPLETION_TOKENS_BY_KEY = {
    "Article Title": 30,
    "DOI": 30,
    "Empirical Analysis": 10,
    "Dependent Variable(s)": 30,
    "Endogeneity Problem": 10,
    "Endogenous Variable(s)": 30,
    "Instrumental Variable Regression": 10,
    "Instrumental Variable(s)": 30,
    "Rainfall Instrument": 10,
    "Rainfall Variable(s)": 10,
}

STOP_SEQUENCES_BY_KEY = {
    "Article Title": ["\n\n"],
    "DOI": ["\n\n"],
    "Dependent Variable(s)": ["\n\n"],
    "Endogenous Variable(s)": ["\n\n"],
    "Instrumental Variable(s)": ["\n\n"],
    "Rainfall Variable(s)": ["\n\n"],
    "Empirical Analysis": ["\n", " "],
    "Endogeneity Problem": ["\n", " "],
    "Instrumental Variable Regression": ["\n", " "],
    "Rainfall Instrument": ["\n", " "],
}

TEMPERATURE = 0.0  # for extraction, 0.0 usually improves stability


# -------------------------------------------------------------------
# Questions (long-form prompts from paste.txt, reordered)
# -------------------------------------------------------------------

questions = [
    {
        "key": "Article Title",
        "question": (
            "Concept (what to look for): You are given the text of an academic article. Your task is to identify the article's exact title as it appears in the document. "
            "Extraction instructions (how to find and clean the variable): Look: Look for the title at the top of the first page. Look for the main, standalone heading that appears before the authors' names and/or the abstract and is visually prominent (e.g., largest heading, centered, or bolded). Ignore running headers, journal names, and later section headings (e.g., \"1 Introduction\"). "
            "Include: Include the full main title text, including any subtitle that is part of the same heading (e.g., separated by a colon or dash). Use the wording, spelling, punctuation, and capitalization as they appear in the document (aside from footnote markers). "
            "Do not include: Do not include author names or affiliations; journal name, volume/issue, or page numbers; running heads or series names; section titles (e.g., \"Abstract\", \"Introduction\"); or footnote markers/symbols attached to the title (e.g., *, †, ‡, numeric superscripts). "
            "Extract: Extract the title as the main standalone heading near the top of the first page that precedes the author list and/or the abstract. Remove any footnote markers or symbols attached to the title text. Perform all reasoning about locating and confirming the title internally. Do not write your reasoning; output only the final title text. Assume there is always exactly one title. "
            "Output format (exact required answer form): Output only the final title text. Do not include any additional text, labels, quotes, or explanation. Output exactly one line containing the title."
        )
    },
    {
        "key": "DOI",
        "question": (
            "Concept (what to look for): You are given material from an academic article. Your task is to extract the Digital Object Identifier (DOI) of the focal article (version of record). "
            "Extraction instructions (how to find and clean the variable): Look: Look through the document for DOI-like strings, especially: near the article's front matter (first page, header/footer, citation block, or journal info); near phrases or labels such as DOI:, doi:, https://doi.org/, http://dx.doi.org/; near strings matching the typical DOI pattern: starting with 10. followed by digits and / (e.g., 10.1016/j.jpubeco.2020.104123). Ignore DOIs that appear only in the reference list, unless there is clear indication they refer to this article's own citation block (not just a cited reference). "
            "Include: Include only the DOI that corresponds to the focal article's version of record (i.e., the published article DOI from the journal/publisher). If both a preprint DOI (e.g., arXiv, SSRN) and a published DOI exist, choose the published DOI. If multiple DOIs are visible, select the one that matches the article's title, authors, journal, and year. Prefer the full publisher DOI over any shortDOI or shortened form. "
            "Do not include: Do not include DOIs from references that only refer to other articles; DOIs for datasets, figures, supplements, appendices, errata, corrigenda, retractions, or preprints when a published DOI exists; ShortDOIs or preprint identifiers if a full published DOI is present; or any DOI that clearly does not match the focal article's title/authors/journal/year. "
            "Extract: Extract the focal article's DOI and normalize it by: stripping any URL wrappers (e.g., remove prefixes such as doi:, DOI:, https://doi.org/, http://dx.doi.org/, etc.); removing extra whitespace and line-break hyphenation; and removing trailing punctuation (e.g., ., ,, ; at the end of the DOI). Convert the DOI to lowercase. Ensure the output is in canonical DOI form (e.g., 10.xxxx/xxxxx with no spaces). Perform all reasoning and disambiguation internally; do not show your reasoning. "
            "Output format (exact required answer form): Output exactly one token: either the normalized DOI string (e.g., 10.1016/j.jpubeco.2020.104123), or exactly n/a if no DOI exists for the focal article. Do not include any additional text, labels, quotes, or explanation. No leading or trailing spaces, and no line breaks beyond the single line containing that token."
        )
    },
    {
        "key": "Empirical Analysis",
        "question": (
            "Concept (what to look for): You are analyzing an academic article. In this task, you must determine whether the article contains empirical quantitative statistical analysis. "
            "By empirical quantitative statistical analysis, we mean that the article uses regressions, econometrics, or similar statistical methods to fit a model or equation to data. "
            "The key idea is that the article estimates statistical relationships using data and formal statistical models (e.g., regression equations with error terms, estimated coefficients, standard errors, p-values). "
            "You must not infer the presence of empirical statistical analysis from the title, abstract, or topic alone. You must verify from the content of the article that it actually performs quantitative statistical estimation. "
            "Extraction instructions (how to determine if the concept is present): Look: Look for sections and headings such as: \"Data\", \"Data and Methods\", \"Empirical Strategy\", \"Identification Strategy\", \"Econometric Model\", \"Empirical Framework\", \"Estimation Strategy\", \"Methodology\", \"Results\", \"Econometric Results\", \"Regression Results\". "
            "Look for textual descriptions that indicate statistical estimation, such as: \"we estimate\", \"we regress\", \"we run regressions\", \"we fit the model\", \"we estimate equation (1)\", \"our empirical model\", \"our econometric specification\", \"our identification strategy\". "
            "Look for equations and models, such as regression-style equations with an error term or model specifications of the form y = beta X + epsilon or similar. "
            "Look for tables and figures, such as: tables of estimated coefficients with standard errors, t-statistics, p-values, confidence intervals, R-squared, or similar regression output. "
            "Look for mentions of statistical estimation methods, such as: OLS, GLS, IV, 2SLS, DiD, RDD, panel data models, fixed effects, random effects, probit, logit, Poisson, negative binomial, maximum likelihood, GMM, etc. "
            "Ignore any analysis only described as having been done in other articles (citations to others' empirical work) unless the current article actually performs its own empirical estimation. "
            "Classify: Classify the article as containing empirical statistical analysis if it includes regressions or econometric models using data; if it fits statistical models (linear or nonlinear) to observational or experimental data and reports estimated parameters and uncertainty (e.g., coefficients with standard errors, p-values, confidence intervals); if it runs causal or predictive empirical models. "
            "Do not classify: Do not classify the article as containing empirical statistical analysis if it only includes purely theoretical analysis; only qualitative/descriptive analysis without regression estimation; only simulations/calibration without estimation on real empirical data; or only reviews other empirical work. "
            "Extract: Carefully evaluate the full article content as needed (not just the title or abstract). Be deliberative and strict. Perform all reasoning internally and do not describe it in your output. "
            "Output format (exact required answer form): Output 1 if the article contains empirical quantitative statistical analysis. Output 0 if it does not. Output exactly one character, either 1 or 0, with no additional text, spaces, or explanation. If you output 0, then in the broader task all subsequent fields for this article should be treated as n/a and you should move on to the next article."
        )
    },
    {
        "key": "Dependent Variable(s)",
        "question": (
            "Only proceed if the previous question \"Empirical Analysis\" was answered 1 (yes, the article contains empirical statistical analysis). "
            "Concept (what to look for): You are analyzing an academic article. In this task, you must determine what the dependent (outcome) variable(s) are in the article's main regression model(s). "
            "List the dependent (outcome) variable(s) used in the article's main regression model(s). The dependent variable is the left-hand-side outcome being explained; it is not the treatment, instrument, control, covariate, mediator, moderator, fixed effect, or any right-hand-side regressor. "
            "There will always be at least one dependent variable whenever the article contains empirical statistical analysis. "
            "Extraction instructions (how to find and clean the variable): Look: Look for the dependent (outcome) variable(s) in the main text describing the empirical model; the left-hand side of equations; column headers or labels in the primary regression tables in the main results section. "
            "Include: Include additional outcomes only if they are explicitly analyzed as main outcomes. If the same outcome appears across multiple specifications, list it once. "
            "Do not include: Do not include first-stage outcomes in IV models; treatments; exposure variables; instruments; controls; fixed effects. "
            "Extract: Extract the name as it appears on the left-hand side / table header. Do not output symbolic notation. Remove transformations on the LHS (e.g., ln(wage) -> wage). Remove units/clarifying parentheses that are not part of the core name. "
            "Output format (exact required answer form): Return only the name(s) of the dependent variable(s), with no commentary, no quotes, and no extra text and separate multiple names with semicolons and a single space after each semicolon. Print everything in lower case. Output exactly one line."
        ),
        "dependency": {"key": "Empirical Analysis", "value": "1"},
    },
    {
        "key": "Endogeneity Problem",
        "question": (
            "Only proceed if the previous question \"Empirical Analysis\" was answered 1 (yes, the article contains empirical statistical analysis). "
            "Concept (what to look for): Determine whether the main empirical regression model(s) suffer from an endogeneity problem, meaning at least one regressor is correlated with the error term and is treated as endogenous in the main analysis. "
            "Extraction instructions: Look for discussion of endogeneity/endogenous/OVB/selection/measurement error/reverse causality/simultaneity tied to the main regression, and/or use of IV/GMM/control-function/dynamic panel estimators with instruments or first-stage equations. "
            "Do not infer from title/topic. Confirm it is actually treated as endogenous in the paper’s main analysis. "
            "Output format (exact required answer form): Output 1 if the article has an endogeneity problem in this sense. Output 0 if it does not. Output exactly one character, either 1 or 0, with no additional text, spaces, or explanation. If you output 0, then in the broader task all subsequent fields for this article should be treated as n/a and you should move on to the next article."
        ),
        "dependency": {"key": "Empirical Analysis", "value": "1"},
    },
    {
        "key": "Endogenous Variable(s)",
        "question": (
            "Only proceed if the previous question \"Endogeneity Problem\" was answered 1. "
            "Concept (what to look for): Identify which explanatory variable(s) the authors explicitly treat as endogenous in the main empirical analysis. "
            "Look for statements like 'we treat X as endogenous' or 'we instrument X', first-stage descriptions, etc. "
            "Do not include dependent variables, instruments, controls, generic phrases, or variables only in minor robustness. "
            "Output format: Return only the name(s), semicolon-separated with a single space after each semicolon, in lower case, exactly one line; or n/a."
        ),
        "dependency": {"key": "Endogeneity Problem", "value": "1"},
    },
    {
        "key": "Instrumental Variable Regression",
        "question": (
            "Only proceed if the previous question \"Endogeneity Problem\" was answered 1. "
            "Concept (what to look for): Determine whether the article uses an instrumental variable (IV) regression method with excluded instruments to address endogeneity (e.g., IV/2SLS/TSLS/LIML/3SLS, IV-probit/logit/tobit, control-function/2SRI, dynamic panel GMM with instruments, etc.). "
            "Ignore non-statistical uses of 'instrument' (e.g., survey instrument). Confirm the paper implements IV-type estimation with excluded instruments in its own analysis. "
            "Output format (exact required answer form): Output 1 if IV regression is used, 0 if not. Output exactly one character."
        ),
        "dependency": {"key": "Endogeneity Problem", "value": "1"},
    },
    {
        "key": "Instrumental Variable(s)",
        "question": (
            "Only proceed if the previous question \"Instrumental Variable Regression\" was answered 1. "
            "Concept (what to look for): Identify the specific excluded instrument variable(s) used in the main IV analysis. "
            "Do not include endogenous regressors, controls, fixed effects, time trends, lags used only as controls, or non-IV design elements. "
            "Output format: Return only the instrument variable name(s), semicolon-separated with a single space after each semicolon, in lower case, exactly one line; or n/a."
        ),
        "dependency": {"key": "Instrumental Variable Regression", "value": "1"},
    },
    {
        "key": "Rainfall Instrument",
        "question": (
            "Only proceed if the previous question \"Instrumental Variable Regression\" was answered 1. "
            "Concept (what to look for): Determine whether any excluded instrument used in the article’s IV framework is based on rainfall or precipitation (including derived indices like anomalies/shocks/deviations, standardized precipitation, cumulative rainfall, wet-day counts, precipitation intensity, drought/wetness indices like SPI/SPEI/PDSI/scPDSI; also snowfall/snowpack/SWE). "
            "Do not count rainfall if it is only a control/exposure/outcome or appears only in non-IV designs; confirm it is an excluded instrument. "
            "Output format: Output exactly one character: 1 if yes, 0 if no."
        ),
        "dependency": {"key": "Instrumental Variable Regression", "value": "1"},
    },
    {
        "key": "Rainfall Variable(s)",
        "question": (
            "Only proceed if the previous question \"Rainfall Instrument\" was answered 1. "
            "Concept (what to look for): Identify the specific rainfall/precipitation-based excluded instrument variable(s) used, preserving both the statistic/transform and the time scale (e.g., mean seasonal rainfall; z-score of annual rainfall; negative deviations in seasonal rainfall). "
            "Do not output symbolic notation; remove units like mm; print in lower case. "
            "Output format: exactly one line; semicolon-separated with a single space after each semicolon; do not repeat; or exactly n/a."
        ),
        "dependency": {"key": "Rainfall Instrument", "value": "1"},
    },
]


# -------------------------------------------------------------------
# Cleaning helpers
# -------------------------------------------------------------------

def normalize_yes_no(answer: str) -> str:
    if not answer:
        return "n/a"
    a = answer.strip().lower()
    if a.startswith("yes") or a == "1":
        return "1"
    if a.startswith("no") or a == "0":
        return "0"
    if a in {"n/a", "na"}:
        return "n/a"
    # if model violates format, be conservative
    return "n/a"


def clean_variable_list(raw_text: str) -> str:
    if not raw_text:
        return "n/a"
    txt = raw_text.strip()

    if txt.lower() in {"n/a", "na", "none"}:
        return "n/a"

    # Strip label-like prefixes: "Dependent variables: X; Y"
    if ":" in txt:
        head, tail = txt.split(":", 1)
        if any(w in head.lower() for w in ["variable", "variables", "outcome", "instrument"]):
            txt = tail.strip()

    txt = txt.replace("\n", " ")
    txt = re.sub(r"\s+", " ", txt)

    # Normalize conjunctions to separators
    txt = txt.replace(" and ", "; ")

    # Split on semicolon or comma
    parts = re.split(r"[;,]", txt)

    cleaned = []
    for p in parts:
        p = p.strip().strip(".").strip()
        if not p:
            continue

        # Trim after dash explanations
        p = re.split(r"\s[-–]\s", p)[0].strip()
        # Trim common trailing clauses
        p = re.split(r"\s(?:such as|for|where|which|that)\b", p, flags=re.I)[0].strip()
        p = p.strip("\"'")

        # Drop overly long phrases
        if len(p.split()) > 18:
            continue

        if p and p.lower() not in {"n/a", "none"}:
            cleaned.append(p.lower())

    # De-duplicate
    seen, uniq = set(), []
    for v in cleaned:
        if v not in seen:
            seen.add(v)
            uniq.append(v)

    return "; ".join(uniq) if uniq else "n/a"


# -------------------------------------------------------------------
# Dependency consistency enforcer (new order + gates)
# -------------------------------------------------------------------

def enforce_dependency_consistency(ans: dict) -> dict:
    ea = ans.get("Empirical Analysis", "n/a")
    endog_prob = ans.get("Endogeneity Problem", "n/a")
    iv_reg = ans.get("Instrumental Variable Regression", "n/a")
    rain_iv = ans.get("Rainfall Instrument", "n/a")

    # If Empirical Analysis != 1, everything downstream is n/a
    if ea != "1":
        for k in [
            "Dependent Variable(s)",
            "Endogeneity Problem",
            "Endogenous Variable(s)",
            "Instrumental Variable Regression",
            "Instrumental Variable(s)",
            "Rainfall Instrument",
            "Rainfall Variable(s)",
        ]:
            ans[k] = "n/a"
        return ans

    # If Endogeneity Problem != 1, everything downstream is n/a
    if endog_prob != "1":
        for k in [
            "Endogenous Variable(s)",
            "Instrumental Variable Regression",
            "Instrumental Variable(s)",
            "Rainfall Instrument",
            "Rainfall Variable(s)",
        ]:
            ans[k] = "n/a"
        return ans

    # If IV regression not used, instruments & rainfall pieces are n/a
    if iv_reg != "1":
        for k in [
            "Instrumental Variable(s)",
            "Rainfall Instrument",
            "Rainfall Variable(s)",
        ]:
            ans[k] = "n/a"
        return ans

    # If rainfall is not an instrument, rainfall variables are n/a
    if rain_iv != "1":
        ans["Rainfall Variable(s)"] = "n/a"
        return ans

    return ans


# -------------------------------------------------------------------
# PDF extraction
# -------------------------------------------------------------------

def extract_relevant_sections(pdf_path: str) -> str:
    relevant_sections = []
    keywords = [
        "instrument", "instrumental variable", "data", "methods", "iv",
        "rainfall", "precipitation", "econometric", "estimation",
        "abstract", "introduction", "results", "first stage", "first-stage",
        "endogeneity", "endogenous", "2sls", "two-stage least squares",
        "doi"
    ]

    try:
        with fitz.open(pdf_path) as doc:
            for page_num in range(len(doc)):
                page = doc.load_page(page_num)
                page_text = page.get_text("text")
                paragraphs = page_text.split("\n\n")
                for paragraph in paragraphs:
                    if any(keyword in paragraph.lower() for keyword in keywords):
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

def query_model_with_history(messages, q_key, enforce_binary=False):
    max_comp = get_max_completion_tokens(q_key)
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

        # Keep your existing truncation approach
        max_tokens = 6000
        text_to_analyze = relevant_sections[: max_tokens * 4]

        info_dict = {
            "File Name": filename,
            "Article Title": "n/a",
            "DOI": "n/a",
            "Empirical Analysis": "n/a",
            "Dependent Variable(s)": "n/a",
            "Endogeneity Problem": "n/a",
            "Endogenous Variable(s)": "n/a",
            "Instrumental Variable Regression": "n/a",
            "Instrumental Variable(s)": "n/a",
            "Rainfall Instrument": "n/a",
            "Rainfall Variable(s)": "n/a",
        }

        temp_answers = info_dict.copy()

        messages = [
            {
                "role": "system",
                "content": (
                    "You are an AI assistant that is an expert in analysis of economic literature. "
                    "You interpret complex content and extract specific information, especially metadata. "
                    "Rules: Use only information from the provided text to answer each query. "
                    "If the requested information is not available, answer exactly n/a. "
                    "Follow the requested output format exactly. "
                    "Do not include labels, quotes, or additional text beyond the required output."
                ),
            },
            {
                "role": "user",
                "content": (
                    "You will be asked a sequence of extraction questions about the same academic article. "
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
                if temp_answers.get(dep_key) != dep_val:
                    temp_answers[q_key] = "n/a"
                    temp_answers = enforce_dependency_consistency(temp_answers)
                    info_dict[q_key] = temp_answers[q_key]
                    print(f"Skipping '{q_key}' due to unmet dependency ({dep_key} != {dep_val})")
                    continue

            enforce_binary = q_key in {
                "Empirical Analysis",
                "Endogeneity Problem",
                "Instrumental Variable Regression",
                "Rainfall Instrument",
            }

            print(f"Querying: {q_key} (max_tokens={get_max_completion_tokens(q_key)})")

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

            messages.append({"role": "assistant", "content": answer})

            # Post-processing
            if enforce_binary:
                answer = normalize_yes_no(answer)

            if q_key in {"Dependent Variable(s)", "Endogenous Variable(s)", "Instrumental Variable(s)", "Rainfall Variable(s)"}:
                answer = clean_variable_list(answer)

            temp_answers[q_key] = answer
            temp_answers = enforce_dependency_consistency(temp_answers)

            info_dict[q_key] = temp_answers[q_key]
            print(f"Answer for {q_key}: {info_dict[q_key]}")

        info_dict = enforce_dependency_consistency(info_dict)
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
