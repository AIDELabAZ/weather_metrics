import fitz  # PyMuPDF
import os
import pandas as pd
from openai import OpenAI
import re

# Initialize the OpenAI client
client = OpenAI(api_key="key")

# Fine-tuned model ID
fine_tuned_model_id = "ft:gpt-4.1-mini-2025-04-14:aide-lab:dec-trial:ClgWlRST"

# -------------------------------------------------------------------
# List of questions with full dependency chain
# -------------------------------------------------------------------
questions = [
    {
        "key": "Paper Title",
        "question": "Task: Extract the exact title of the article from the provided text. What to extract: Read the academic article and return only its exact title. The title is the main standalone name of the article itself. Rules: Do not include anything that is not simply the title of the article. Ignore human names, introduction, abstract, and journal titles. Output format: Output exactly one line containing only the title of the article and nothing else."
    },
    {
        "key": "DOI",
        "question": "Task: Extract the DOI of the focal article (version of record). What to extract: The DOI of the article whose text is provided. A DOI is a string that starts with 10. and contains a slash, for example 10.1016/j.jpubeco.2020.104123. Only return the DOI of this article itself, not DOIs of references, datasets, or supplements. If more than one DOI appears, choose the one that is presented as the articles own DOI in the front matter or header. Output format: Output exactly one token: either the DOI string (as it appears, trimmed of leading “doi:” or “https://doi.org/”) or exactly n/a if the article has no DOI. Do not output any extra text, labels, or punctuation."
    },
    {
        "key": "Dependent Variables",
        "question": "Read the full text of the article carefully, including the abstract, introduction, data, methods, results, tables, figures, and appendix if present. Your task is to identify the primary dependent (outcome) variable or variables used in the articles main regression or statistical model. First, explicitly locate and quote or paraphrase all passages that describe outcome variables, dependent variables, left-hand-side variables, or what is being “explained,” “predicted,” or “regressed on” in the main empirical specification. Then reason step by step to determine which of these correspond to the main dependent variable(s) of the primary analysis, excluding robustness checks, alternative outcomes, secondary analyses, descriptive statistics, measurement validation, or auxiliary models. Normalize each selected dependent variable to a human-readable name that reflects the substantive meaning of the variable being used. Do not use single letters, Greek symbols, equations, or purely symbolic notation. Do not output internal dataset or code variable names unless they are self-explanatory without additional context. Do not output any information beyond the name of the isolated dependent variable. If multiple dependent variables are jointly treated as main outcomes, return up to three distinct names. If only one main outcome exists, return only that one. If the article does not estimate any regression or statistical model with a clearly defined dependent variable in the main analysis, return exactly “n/a”. Your final output must be exactly one line containing either a single dependent variable name, a semicolon-separated list of up to three names, or “n/a”, and nothing else. All reasoning and evidence identification must occur before the final line."
    },
    {
        "key": "Endogenous Variable(s)",
        "question": "Read the entire article carefully, including the abstract, introduction, data, methods, identification strategy, results, tables, figures, and appendix. Your task is to identify the primary explanatory variable or variables that the authors explicitly treat as endogenous in the main empirical analysis. First, locate and enumerate all passages that describe endogeneity, instrumentation, instrumental variables, first-stage regressions, excluded instruments, identification strategies, or statements that a regressor is “endogenous,” “instrumented,” or “potentially endogenous.” Then reason step by step to determine which explanatory variable(s) are central to the identification strategy and are instrumented in the primary regression specification, excluding robustness checks, alternative specifications, placebo analyses, auxiliary models, or secondary endogenous variables. Normalize each selected variable to a short, human-readable descriptive name that reflects its substantive meaning. Do not use single letters, Greek symbols, equations, or purely symbolic notation. Do not output internal dataset or code variable names unless they are self-explanatory without additional context. Do not output any infomration beyond the name of the isolated endogenous explanatory variable. If multiple distinct endogenous explanatory variables are jointly treated as main regressors, include each one once, up to a maximum of three. Use only information from this article. If no endogenous explanatory variable is explicitly identified in the main analysis, return exactly “n/a”. Your final output must be exactly one line containing only the endogenous variable name(s), separated by semicolons if more than one, and nothing else. All reasoning and evidence identification must occur before the final output line."
    },
    {
        "key": "Instrumental Variable Used",
        "question": " Concept (what to look for): You are analyzing an academic article. In this task, you must determine whether the article uses an instrumental variable (IV) regression method to address endogeneity. Instrumental variable methods use excluded instruments in a formal IV framework (e.g., IV/2SLS/TSLS/LIML/3SLS, IV-Probit/IV-Logit/IV-Tobit, control-function or two-stage residual inclusion, dynamic panel GMM such as Arellano-Bond/Bover/Blundell-Bond, or other GMM/endogenous switching models that explicitly rely on instruments). Extraction instructions (how to determine if the concept is present): Look: Look for sections such as \"Empirical Strategy\", \"Identification Strategy\", \"Econometric Model\", \"Instrumental Variables\", \"Estimation\", \"Methodology\", \"Data\", \"Methods\", and \"Results\". Look in the text, equations, and regression tables (including appendices). Search for terms and phrases like \"instrument\", \"instrumented\", \"instrumental variable\", \"IV\", \"2SLS\", \"two-stage least squares\", \"LIML\", \"3SLS\", \"dynamic panel\", \"Arellano-Bond\", \"Blundell-Bond\", \"endogenous switching\", \"first stage\", \"reduced form\", \"excluded instrument\", \"exclusion restriction\", and for discussion of weak-instrument tests (e.g., Kleibergen-Paap, Cragg-Donald, Stock-Yogo) or overidentification tests (e.g., Sargan, Hansen J, Anderson-Rubin). Ignore non-statistical uses of the word \"instrument\" (e.g., survey instrument, measurement instrument). Classify: Classify the article as using instrumental-variable regression if any empirical specification in the article (main analysis, robustness, or appendix) actually implements an IV-type estimator with excluded instruments. This includes cases where the authors: (i) present an explicit first-stage equation or instrument set; (ii) describe using IV/2SLS/TSLS/LIML/3SLS, IV-Probit/IV-Logit/IV-Tobit, control-function or two-stage residual inclusion, or dynamic panel GMM estimators that rely on instruments; or (iii) discuss instrument relevance and exclusion restrictions and report weak-instrument or overidentification diagnostics for their own estimations. Do not classify: Do not classify the article as using instrumental variable regression based only on generic mentions of IV or GMM in literature reviews, theory sections, background discussions, or references to other articles or other datasets. Do not classify as IV if the article only employs other identification strategies without an IV first stage or instrument set, such as randomized controlled trials (without any IV for noncompliance), RDD, DiD, event studies, fixed effects only, controls/matching, or Heckman selection models that do not rely on excluded instruments. Do not treat lags used merely as controls, or trend terms, as evidence of IV use. Extract: Carefully evaluate the discussion of the main empirical model and identification strategy. Be deliberative and strict: confirm that the authors implement an instrumental variable method with excluded instruments, rather than merely discussing instruments and why they are not needed or used. Perform all reasoning internally and do not describe it in your output. Output format (exact required answer form): Output 1 if the article uses an IV to address the endogeneity problem in this sense (i.e., the endogenous regressor is instrumented with a variable that satisfies the exclusion restriction). Output 0 if it does not. Output exactly one character, either 1 or 0, with no additional text, spaces, or explanation. If you output 0, then in the broader task all subsequent fields for this article should be treated as n/a and you should move on to the next article."
    },
    {
        "key": "Instrumental Variable(s)",
        "question": "Only proceed if the previous question \"Instrumental Variable Regression\" was answered 1 (yes, the article uses an instrumental variable regression method to deal with the endogeneity problem). Concept (what to look for): You are analyzing an academic article. In this task, you must identify the specific variable(s) that are used as instrumental variables (excluded instruments) in the main instrumental variable analysis. Extraction instructions (how to find and clean the variable): Look: Look for sections such as \"Empirical Strategy\", \"Identification Strategy\", \"Econometric Model\", \"Instrumental Variables\", \"Estimation\", \"Methodology\", \"Data\", \"Methods\", and \"Results\", including tables and appendices that report first-stage or reduced-form results. Look for phrases like \"we instrument X with Z\", \"Z is our instrument\", \"Z serves as an excluded instrument\", \"Z satisfies the exclusion restriction\", \"first-stage regression\", \"excluded variable\", or \"instrument set\". Examine first-stage or reduced-form equations and any regression tables labeled as first-stage, reduced-form, or IV results for explicit listings of instruments. Include: Include each variable that the authors explicitly describe as an instrument, excluded instrument, or first-stage regressor used to identify an endogenous variable in the main IV analysis. These are variables that enter the first stage but are excluded from the structural equation and are described as providing exogenous variation for the endogenous regressor(s). They are also described as satisfying the \"exclusion restriction\". If multiple distinct main instruments are used, include each instrument once. Do not include: Do not include the dependent variable, the endogenous regressor(s) themselves, standard controls/covariates treated as exogenous, fixed effects, time trends, or lags used only as controls. Do not include design features from non-IV strategies (e.g., DiD indicators, RDD running variables or cutoffs, event-study dummies, matching variables) that are not described as instruments. Do not include variables that appear only in robustness checks or ancillary specifications unless they are clearly described as part of the main IV identification strategy. Do not include exogenous variables that serve as their own instrument and are included in both the first- and second-stage regressions. We are only interested in the excluded instrument. Do not use generic phrases such as \"the instruments\" or \"excluded variables\" without specific variable names. Extract: Extract the specific variable name of each excluded instrument as described in the article's text, equations, or tables. Output the name of the instrumental variable(s), not purely symbolic notation (e.g., do not output z_it if that is the symbol used to represent the IV). Remove transformations that are part of the right-hand-side specification for the first-stage. For example, if the IV is \"ln(rainfall)\", then output \"rainfall\". If the IV is \"log distance\", then output \"distance\". If the IV is \"Δ prices\", then output \"prices\". Remove measurement units or clarifying parentheses that are not part of the core name. For example, drop \"(per 1,000)\", \"(in 2015 USD)\", \"(kg/ha)\", \"(monthly)\", \"(mm)\". You may make minor simplifications or generalizations to the name of the IV, as long as you are consistent. For example, if the IV is \"global commodity price index\", you can output just \"price\". If the IV is \"distance from country border\", you can output just \"distance\". If the IV is \"value of farm assets\", you can output just \"assets\". If the IV is \"mean rainfall, total rainfall, and maximum temperature\" or some other specific measures of weather, you can output just \"rainfall; temperature\" (except when applying the specialized rules in the \"Rainfall Variable(s)\" prompt). The key rule when making simplifications or generalizations is that similar variables across different articles should be given the same normalized name. For example, if two articles have \"investment in agricultural research\" as the IV, do not call this \"agricultural research\" for one article and \"investment in research\" for another article. Perform all reasoning and intermediate steps internally and use only the article content plus the normalization rules specified in this prompt. Output format (exact required answer form): Return only the name(s) of the instrumental variable(s), with no commentary, no quotes, and no extra text and separate multiple names with semicolons and a single space after each semicolon. Print everything in lower case. If there is more than one distinct instrumental variable, separate them with semicolons, with a single space after each semicolon. For example: rainfall; distance; price shock. Do not repeat the same instrumental variable more than once. Do not include any variables that are not excluded instruments (i.e., do not include the dependent variable, endogenous variables, control variables, variables that serve as their own instrument, etc.). Your final output must be exactly one line containing the normalized instrumental variable name, or a semicolon-separated list of such names, in lower case, with nothing else.",
        "dependency": {"key": "Instrumental Variable Used", "value": "1"}
    },
    {
        "key": "Instrumental Variable Rainfall",
        "question": "Only proceed if the previous question \"Instrumental Variable Regression\" was answered 1 (the article uses an instrumental variable regression method to deal with the endogeneity problem). Concept (what to look for): You are analyzing an academic article. In this task, you must determine whether any of the excluded instruments used in the article's instrumental variable framework are based on rainfall or precipitation. Extraction instructions (how to determine if the concept is present): Look: Look for sections such as \"Empirical Strategy\", \"Identification Strategy\", \"Instrumental Variables\", \"IV Strategy\", \"Econometric Model\", \"Estimation\", \"Methodology\", \"Data\", \"Methods\", and \"Results\", including tables and appendices with first-stage or IV results. Look for (i) explicit descriptions of instruments that clearly mention rainfall or precipitation; (ii) terms like \"rainfall\", \"precipitation\", \"rain\", \"snow\", \"drought\", \"monsoon rainfall\", \"dry season rainfall\", \"rainfall shock\", or \"weather shocks\" tied specifically to precipitation; (iii) precipitation-derived indices such as rainfall level, deviations, shocks, anomalies, standardized or cumulative precipitation, wet-day counts, precipitation intensity, drought or wetness indices (e.g., SPI, SPEI, PDSI, scPDSI), or any index explicitly constructed from precipitation. Combine this with evidence of IV use: words like \"instrument\", \"instrumental variable\", \"excluded instrument\", \"first stage\", \"2SLS\", \"IV-Probit\", \"GMM with instruments\", \"control-function\", \"2SRI\", and discussion of weak-instrument diagnostics (e.g., Kleibergen-Paap, Cragg-Donald, Stock-Yogo) or overidentification tests (e.g., Sargan, Hansen J, Anderson-Rubin). Classify: Classify the article as using a rainfall (or precipitation-based) instrument if any specification in the article (main analysis, robustness, or appendix) explicitly uses rainfall or a precipitation-derived measure as an excluded instrument in a first-stage/IV framework. Qualifying precipitation instruments include, for example: rainfall level, rainfall deviations or shocks, rainfall anomalies, standardized precipitation, cumulative rainfall, wet-day counts, precipitation intensity, drought or wetness indices (SPI, SPEI, PDSI, scPDSI), monsoon rainfall, snowfall, snowpack or SWE, or any index the article explicitly constructs from precipitation and uses as an excluded instrument. Do not classify: Do not classify the article as using a rainfall instrument if precipitation appears only as: (i) a regressor, control, interaction term, exposure, or outcome; or (ii) part of non-IV designs like reduced-form regressions, DiD, event studies, RDD, matching, or OLS/fixed-effects models without an IV first stage. Do not count rainfall or precipitation if it is the endogenous variable being instrumented by non-precipitation instruments. Do not count broad climate indices (e.g., ENSO) unless the text explicitly states that they are constructed from or directly represent precipitation and are used as the excluded instrument. Ignore mentions of precipitation-based instruments in other articles or datasets; use only this article's own IV specifications. Extract: Carefully evaluate the discussion of rainfall or precipitation-based variables and how they relate to the excluded instrument. Be deliberative and strict: confirm that the authors use rainfall as the excluded instrumental variable that is described as satisfying the exclusion restriction, rather than merely discussing that rainfall could be used as an instrument and why they are not using it or are just using rainfall as a control or as an instrument for itself. Perform all reasoning internally and do not describe it in your output. Output format (exact required answer form): Output 1 if the article uses rainfall or some measure of precipitation as the excluded instrument in first-stage IV regression to address the endogeneity problem in this sense (i.e., the endogenous regressor is instrumented with a variable that measures precipitation and satisfies the exclusion restriction). Output 0 if it does not. Output exactly one character, either 1 or 0, with no additional text, spaces, or explanation. If you output 0, then in the broader task all subsequent fields for this article should be treated as n/a and you should move on to the next article.",
        "dependency": {"key": "Instrumental Variable Used", "value": "1"}
    },
    {
        "key": "Rainfall Metric",
        "question": "Only proceed if the previous question \"Rainfall Instrument\" was answered 1 (the article uses at least one rainfall- or precipitation-based variable as the excluded instrument). Concept (what to look for): You are analyzing an academic article. In this task, you must identify the specific rainfall or precipitation-based variable(s) that are used as instrumental variables (excluded instruments) in the main instrumental variable analysis. Extraction instructions (how to find and clean the variable): Look: Look at sections such as \"Empirical Strategy\", \"Identification Strategy\", \"Instrumental Variables\", \"IV Strategy\", \"Econometric Model\", \"Estimation\", \"Methodology\", \"Data\", \"Methods\", and \"Results\", including tables and appendices with first-stage or IV results. Look for phrases like \"we instrument X with rainfall\", \"rainfall is our instrument\", \"precipitation index serves as an excluded instrument\", or similar constructions. Examine first-stage or reduced-form equations and any regression tables labeled as first-stage, reduced-form, or IV results for explicit precipitation-based instruments. Pay special attention to variable names that reference rainfall, precipitation, drought, wetness, or related indices (e.g., \"total annual rainfall\", \"standard deviation of rainfall\", \"mean daily rainfall\", \"monsoon rainfall\", \"monsoon onset\", \"deviations in rainfall\", \"below average rainfall\", \"z-score of rainfall\", \"coefficient of variation in rainfall\"). Include: Include each variable that is (i) explicitly described as an excluded instrument or first-stage regressor, and (ii) clearly based on rainfall or precipitation (including derived precipitation indices such as rainfall level, deviations, shocks, anomalies, standardized or cumulative precipitation, wet-day counts, precipitation intensity, and drought or wetness indices like SPI, SPEI, PDSI, scPDSI, monsoon rainfall, snowfall, snowpack, SWE, or other indices explicitly constructed from precipitation). If multiple distinct rainfall/precipitation instruments are used in the first-stage regression, include each one once. Do not include: Do not include non-precipitation instruments (e.g., distance, policy eligibility, prices) even if they appear in the same instrument set. Do not include precipitation variables used only as controls, exposures, or outcomes rather than excluded instruments. Do not include precipitation variables that appear only in non-IV designs (e.g., reduced-form regressions, DiD, event studies, RDD, matching, or OLS/fixed-effects without an IV first stage). Do not include non-precipitation-based weather instruments (e.g., temperature, wind, growing degree days (GDD), soil quality). Do not include generic phrases like \"rainfall instruments\" without specific variable names. Do not base inclusion on references to rainfall instruments in other articles; use only this article's own IV specification. Extract: Extract the specific variable name as described in the article's text, equations, or tables. Output the descriptive name of the rainfall metric, not just symbolic notation (e.g., do not output z_it; instead output the underlying rainfall variable it represents). Remove transformations that are part of the right-hand-side specification in the first-stage. For example, if the rainfall IV is \"ln(total seasonal rainfall)\", then output \"total seasonal rainfall\". If the rainfall IV is \"log mean annual rainfall\", then output \"mean annual rainfall\". If the rainfall IV is \"Δ long run mean rainfall\", then output \"long run mean rainfall\". Remove measurement units or clarifying parentheses that are not part of the core name. For example, drop \"(mm)\". As with \"Dependent Variable(s)\", \"Endogenous Variable(s)\", \"Instrumental Variable(s)\", you can make minor generalizations to the name of the rainfall IV, as long as you are consistent. For example, if the rainfall IV is \"annual standardized rainfall deviation from the long-term\", you can generalize the output to \"rainfall z-score\". If the rainfall IV is \"per cent deviations of 2011 annual rainfall\", you can generalize the output to \"deviations in annual rainfall\". If the rainfall IV is \"rainfall on election day in mm\", you can generalize the output to \"total daily rainfall\". If the rainfall IV is \"The 2005 and 2006 annual rainfall levels, the rainfall deviations from 1988 to 2005,\" you can generalize the output to \"total annual rainfall; deviations in annual rainfall\". However, unlike with \"Dependent Variable(s)\", \"Endogenous Variable(s)\", \"Instrumental Variable(s)\" do not make simplifications to the name of the rainfall IV that drop the rainfall statistic or the time scale. For example, if the rainfall IV is \"mean annual rainfall\", do not simplify to \"mean rainfall\" or \"annual rainfall\". If the rainfall IV is \"total seasonal rainfall\", do not simplify to \"total rainfall\" or \"seasonal rainfall\". If the rainfall IV is \"deviations in annual rainfall\", do not simplify to \"rainfall shocks\". If the rainfall IV is \"mean monthly rainfall, total monthly rainfall, and maximum monthly temperature\" do not simplify to \"mean rainfall; total rainfall\" or \"monthly rainfall\". Both the rainfall statistic (i.e., mean, standard deviation, total, z-score, negative deviations, coefficient of variation) and the time scale (i.e., daily, monthly, seasonal, annual) should be preserved in the name. The key rule when making generalizations while preserving the relevant rainfall statistic (for example, mean, total, z-score) and time scale (for example, daily, monthly, seasonal, annual) is that similar variables across different articles should be given the same normalized name. For example, if two articles have \"the mean of January-March rainfall and average rainfall in this three-month window that negatively differs from the historic average\" as the rainfall IVs, do not call this \"mean rainfall; deviations in rainfall\" for one article and \"seasonal rainfall; seasonal deviations\" for another article. In this case, the rainfall IVs should be listed as \"mean seasonal rainfall; negative deviations in seasonal rainfall\". Perform all reasoning and intermediate steps internally and use only the article content plus the normalization rules specified in this prompt. Output format (exact required answer form): Return only the name(s) of the rainfall instrumental variable(s), with no commentary, no quotes, and no extra text and separate multiple names with semicolons and a single space after each semicolon. Print everything in lower case. If there is more than one distinct rainfall IV, separate them with semicolons, with a single space after each semicolon. For example: mean seasonal rainfall; standard deviation of seasonal rainfall; z-score of annual rainfall. Do not repeat the same rainfall IV more than once. Do not include any variables that are not excluded rainfall instruments (i.e., do not include non-precipitation-based instruments, dependent variables, endogenous variables, control variables, variables that serve as their own instrument, etc.). Your final output must be exactly one line containing the normalized rainfall instrumental variable name, or a semicolon-separated list of such names, in lower case, with nothing else.",
        "dependency": {"key": "Instrumental Variable Rainfall", "value": "1"}
    },
    {
        "key": "Rainfall Data Source",
        "question": "What is the source of the rainfall data used in the study? Identify and report the exact source of the rainfall/precipitation data used as the instrument: name the dataset or provider (e.g., CHIRPS, TRMM, ERA5, NOAA station records, Indian Meterological Department). Please give me the source of the rainfall data without any additional words or numbers. If rainfall is used as an instrumental variable, the data must come from a specific source (e.g., a satellite or organization). Please find the origin of the rainfall data that was used. Please only provide the source of the rainfall data, without the title of the question or any additional words.",
        "dependency": {"key": "Instrumental Variable Rainfall", "value": "1"}
    },
]

# -------------------------------------------------------------------
# Normalization / cleaning helpers
# -------------------------------------------------------------------

def normalize_yes_no(answer):
    if not answer:
        return "0"
    answer = answer.strip().lower()
    if answer.startswith("yes") or answer == "1":
        return "1"
    elif answer.startswith("no") or answer == "0":
        return "0"
    else:
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
        p = p.strip("\"“”'")

        if len(p.split()) > 8:
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
    txt = txt.strip("\"“”'").strip(" .,")

    return txt if txt else "n/a"

# -------------------------------------------------------------------
# PDF text extraction
# -------------------------------------------------------------------

def extract_relevant_sections(pdf_path):
    relevant_sections = []
    keywords = [
        "instrument", "instrumental variable", "data", "methods", "iv",
        "rainfall", "model", "econometric", "metrics", "introduction",
        "abstract", "conclusion", "strategy", "empirical",
    ]
    with fitz.open(pdf_path) as doc:
        for page_num in range(len(doc)):
            page = doc.load_page(page_num)
            page_text = page.get_text("text")
            paragraphs = page_text.split("\n\n")
            for paragraph in paragraphs:
                if any(keyword.lower() in paragraph.lower() for keyword in keywords):
                    relevant_sections.append(paragraph)
    return " ".join(relevant_sections)

# -------------------------------------------------------------------
# Model query
# -------------------------------------------------------------------

def query_model_single(text, question, enforce_binary=False, specific_metric=False):
    user_query = (
        "Based on the following relevant sections from an academic text, "
        "please answer the question below.\n\n"
        f"{text}\n\n"
        f"Question: {question}\n\n"
        f"{'Please respond with \"1\" for yes, \"0\" for no, or \"n/a\" if not applicable or unclear.' if enforce_binary else 'Provide a concise and accurate answer. The response should be a specific metric without broad terms. Avoid using general phrases and ensure the metric is precisely defined. If information is not available, respond with \"n/a\".'}"
    )

    try:
        response = client.chat.completions.create(
            model=fine_tuned_model_id,
            messages=[
                {
                    "role": "system",
                    "content": (
                        "You are an AI assistant that is an expert in economics paper analysis. You interpret complex academic content and extract specific information, especially metadata and econometric variables. Use only information from the provided text. If the requested information is not available, answer exactly n/a. Follow the requested output format exactly. Do not include the question, labels, or any additional text in your response."
                    ),
                },
                {"role": "user", "content": user_query},
            ],
            max_tokens=1000,
            temperature=0.0,
        )
        answer = response.choices[0].message.content.strip()
        if not answer:
            return "n/a"
        if enforce_binary:
            return normalize_yes_no(answer)
        return answer
    except Exception as e:
        print(f"Error querying model: {e}")
        return "n/a"

# -------------------------------------------------------------------
# Main processing with enforced dependencies
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
            "Paper Title": "n/a",
            "DOI": "n/a",
            "Dependent Variables": "n/a",
            "Endogenous Variable(s)": "n/a",
            "Instrumental Variable Used": "0",
            "Instrumental Variable(s)": "n/a",
            "Instrumental Variable Rainfall": "0",
            "Rainfall Metric": "n/a",
            "Rainfall Data Source": "n/a",
        }

        temp_answers = info_dict.copy()

        for q in questions:
            q_key = q["key"]

            # -------------------------
            # Universal dependency gate
            # -------------------------
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

                    # Binary flags default to "0", others "n/a"
                    if q_key in ["Instrumental Variable Used", "Instrumental Variable Rainfall"]:
                        temp_answers[q_key] = "0"
                    else:
                        temp_answers[q_key] = "n/a"

                    info_dict[q_key] = temp_answers[q_key]
                    continue

            # -------------------------
            # Decide query settings
            # -------------------------
            enforce_binary = q_key in [
                "Instrumental Variable Used",
                "Instrumental Variable Rainfall",
            ]
            specific_metric = q_key == "Rainfall Metric"

            print(f"Querying: {q_key}")
            answer = query_model_single(
                text_to_analyze,
                q["question"],
                enforce_binary=enforce_binary,
                specific_metric=specific_metric,
            )

            # -------------------------
            # Post-processing
            # -------------------------
            if q_key == "Dependent Variables" and answer != "n/a":
                answer = clean_dependent_variables(answer)

            if q_key in ["Endogenous Variable(s)", "Instrumental Variable(s)", "Rainfall Metric"]:
                answer = clean_variable_list(answer)

            if q_key == "Rainfall Data Source":
                answer = clean_rainfall_source(answer)

            if enforce_binary:
                answer = normalize_yes_no(answer)

            # Hard guardrails:
            # If IV Used != 1, force all downstream IV fields to safe defaults
            if q_key == "Instrumental Variable Used":
                if answer != "1":
                    answer = "0"
                    temp_answers["Instrumental Variable(s)"] = "n/a"
                    temp_answers["Instrumental Variable Rainfall"] = "0"
                    temp_answers["Rainfall Metric"] = "n/a"
                    temp_answers["Rainfall Data Source"] = "n/a"

            # If IV Rainfall != 1, force rainfall-specific details to safe defaults
            if q_key == "Instrumental Variable Rainfall":
                if answer != "1":
                    answer = "0"
                    temp_answers["Rainfall Metric"] = "n/a"
                    temp_answers["Rainfall Data Source"] = "n/a"

            info_dict[q_key] = answer
            temp_answers[q_key] = answer
            print(f"Answer for {q_key}: {answer}")

        print(f"Final extracted info for {filename}: {info_dict}")
        data.append(info_dict)

    df = pd.DataFrame(data)
    df.to_csv(output_csv, index=False)
    print(f"Data saved to {output_csv}")

# -------------------------------------------------------------------
# Paths and execution
# -------------------------------------------------------------------

pdf_folder = "/Users/kieran/Library/CloudStorage/OneDrive-UniversityofArizona/weather_iv_lit/training/models/finetune_data/pdf_test_20"
output_folder = "/Users/kieran/Library/CloudStorage/OneDrive-UniversityofArizona/weather_iv_lit/training/models/output"
os.makedirs(output_folder, exist_ok=True)
output_csv = os.path.join(output_folder, "finetune_output.csv")

process_pdfs_conditional_queries(pdf_folder, output_csv)
