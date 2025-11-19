import fitz  # PyMuPDF
import os
import pandas as pd
from openai import OpenAI
import re

# Initialize the OpenAI client
client = OpenAI(api_key='key')

# Fine-tuned model ID
fine_tuned_model_id = 'ft:gpt-4.1-mini-2025-04-14:aide-lab:update:CbuBEy1P'

# List of questions with full dependency chain
questions = [
    {"key": "Paper Title",
     "question": "You will be given the text from an academic paper. Extract the paper’s exact title from the document. Deliberate through the identification steps internally but do not write your reasoning; output only the final title. Identify the title as the main, standalone heading near the top of the first page that precedes the author list or the Abstract. Remove footnote markers or symbols attached to the title text (such as *, †, ‡, or numeric superscripts). Output strictly the title text and nothing else"},
    {"key": "DOI",
     "question": "Extract the DOI of the focal article from the provided material. Identify the DOI for the version of record of the main paper, not DOIs from references, datasets, figures, supplements, errata/corrigenda, retractions, or preprints. Prefer the publisher’s full DOI over shortDOI or preprint identifiers; if both preprint and published DOIs exist, choose the published article’s DOI. Normalize by stripping URL wrappers (e.g., doi:, https://doi.org/), whitespace, line-break hyphenation, and trailing punctuation; return the DOI in lowercase in canonical form like 10.xxxx/xxxxx. Do not return any DOI that appears only in the reference list. If multiple DOIs are visible, select only the one that matches the article’s title/authors/journal/year and ignore all others for output. If no DOI exists for the focal article, answer exactly n/a. Think through the steps needed to disambiguate and verify the focal DOI, but do not reveal your reasoning; output only the final answer. Output must be exactly one token: the DOI string or n/a, with no extra text or formatting."},
    {"key": "Dependent Variables",
     "question": "Identify and list the dependent (outcome) variable(s) used in this paper’s main regression model(s). The dependent variable is the left-hand-side outcome being explained; it is not the treatment, instrument, control, covariate, mediator, moderator, fixed effect, or any right-hand-side regressor. Use only evidence from the paper’s main text, equations, and primary results tables; prefer the primary specification(s) in the main results section. Include additional outcomes only if they are explicitly analyzed as main outcomes (not merely robustness or ancillary checks). Extract the exact outcome variable names as they appear on the left-hand side of equations or as column labels/headers in regression tables. If the same outcome appears across multiple specifications or samples, list it once. If multiple distinct main outcomes are analyzed, list each once. Do not include first-stage outcomes in IV models, treatment assignment indicators, event-study dynamic coefficients, exposure variables, instruments, controls, or fixed effects. Output format: return only the variable name(s), with no commentary, no quotes, and no extra text; separate multiple names with semicolons and a single space after each semicolon; preserve case and any transformations that are part of the left-hand-side specification (e.g., ln(wage), log income, Δ outcome); remove measurement units or clarifying parentheses that are not part of the variable name (e.g., drop “(per 1,000)”). If you cannot identify any dependent variable from the provided content, output exactly: n/a. Perform all reasoning internally and output only the final list."},
    {"key": "Endogenous Variable(s)",
     "question": "Identify the endogenous explanatory variable(s) in this paper if it exists. An endogenous variable is any regressor the authors explicitly treat as endogenous due to simultaneity/reverse causality, omitted variables, or measurement error—typically indicated by statements such as “we treat X as endogenous,” “we instrument X,” or the use of IV/2SLS/IV-Probit/GMM/control-function/2SRI, first-stage regressions, excluded instruments, or weak-instrument tests (e.g., Kleibergen–Paap). Extract only the specific variable name(s) the authors claim are endogenous. Output format: return only the variable name(s), separated by semicolons if multiple; no quotes and no additional text. Use only this paper’s content (main text, tables, figures, appendices); ignore references to other papers. Include every variable treated as endogenous in any specification; if none, return n/a. If the immediately preceding task returned 0 or n/a, return n/a here. Do not return rainfall, precipitation, other weather variables/events, or natural phenomena such as PM-based pollution as endogenous variables. Do not return the dependent variable, instruments themselves, controls treated as exogenous, or generic phrases. Do not explain your answer."},
    {"key": "Instrumental Variable Used",
     "question": "Decide whether the paper uses an instrumental-variable method to address endogeneity. Output must be exactly one of: 1, 0, n/a. Return 1 if any specification (main, robustness, or appendix) uses an excluded instrument in an IV framework such as IV/2SLS/TSLS/LIML/3SLS, control-function or two-stage residual inclusion (2SRI), IV-Probit/IV-Logit/IV-Tobit, dynamic panel GMM (Arellano–Bond/Bover/Blundell–Bond), or any GMM/endogenous switching model that explicitly relies on instruments; look for an explicit first stage or instrument set, terms like instrument/instrumented/IV/2SLS, discussion of instrument relevance and exclusion restrictions, or reporting of weak-instrument diagnostics (e.g., Kleibergen–Paap, Cragg–Donald, Stock–Yogo F-statistics) and overidentification tests (Sargan/Hansen J/Anderson–Rubin). Return 0 if the paper runs regressions without using instruments despite discussing endogeneity, or uses other identification strategies instead of IV (e.g., randomized experiments, regression discontinuity, difference-in-differences/event studies, fixed effects only, controls/matching, Heckman selection without excluded instruments, using lags merely as controls) and does not implement an IV first stage or instrument set. Return n/a only if the paper indicates there is no endogeneity concern by design (e.g., a true randomized experiment with exogenous assignment) and therefore has no need for IV. Do not infer IV use from generic mentions of IV/GMM in literature reviews, background, or for other datasets; require actual implementation in this paper’s empirical specifications, results tables, or appendix. Ignore non-statistical uses of the word instrument (e.g., measurement instruments). If multiple instruments or models appear, return 1 if any qualify. Think carefully but do not reveal your reasoning; output exactly one token: 1 or 0 or n/a, with no additional text."},
    {"key": "Instrumental Variable(s)",
     "question": "Extract the specific instrumental variable(s) used the main analysis, providing only the variable name without additional text or details. Only consider variables explicitly used in an instrumental variable framework (such as two-stage least squares, IV, IV-Probit, generalized method of moments, control-function, or two-stage residual inclusion, and described as instruments, excluded instruments, or first-stage regressors). Do not include variables that appear only as regressors, controls, exposures, treatments, fixed effects, trends, lags used as controls, or designs without an IV first stage such as difference-in-differences, event studies, regression discontinuity, or matching. If no instrumental-variable method is used in the main analysis, output n/a.",
     "dependency": {"key": "Instrumental Variable Used", "value": "1"}},
    {"key": "Instrumental Variable Rainfall",
     "question": "Decide whether the paper uses rainfall or any precipitation based measure as an instrumental variable. Return exactly one of: 1, 0, n/a. Return 1 if any specification in the paper (e.g., IV/2SLS, IV-Probit, GMM with excluded instruments, control-function, 2SRI) uses rainfall or a precipitation-derived measure as an excluded instrument. Qualifying precipitation instruments include rainfall level, deviation, shock, anomaly, standardized or cumulative precipitation, wet-day counts, precipitation intensity, drought or wetness indices such as SPI, SPEI, PDSI, scPDSI, monsoon rainfall, snowfall, snowpack or SWE, or any index explicitly constructed from precipitation. Return 0 if the paper uses instrumental-variable methods but none of the excluded instruments are precipitation-based, or if precipitation itself is the endogenous variable being instrumented by non-precipitation instruments. Return n/a if the paper does not use an instrumental-variable framework at all. Count an instrument as precipitation-based only if it is explicitly used as an excluded instrument in a first-stage/IV framework; look for terms like instrument, instrumental variable, excluded instrument, first stage, 2SLS, IV-Probit, GMM with instruments, control-function, weak-instrument F-statistic, Kleibergen-Paap, Anderson-Rubin. Do not count precipitation if it appears only as a regressor, control, interaction, exposure, or in reduced-form, DiD, event-study, RDD, matching, or OLS designs without an IV first stage. Do not count broad climate indices (e.g., ENSO) unless they are explicitly mapped to or constructed from precipitation as the instrument itself. If multiple instruments are used, return 1 if any are precipitation-based. Use only evidence from this paper’s methods, results, and appendices; ignore references to other papers. Think through the decision internally and silently; do not reveal your reasoning. Final output must be exactly one token: 1 or 0 or n/a, with no additional text.",
     "dependency": {"key": "Instrumental Variable Used", "value": "1"}},
    {"key": "Rainfall Metric",
     "question": "Extract the specific rainfall metric used as an instrument variable in the main analysis. Output only the exact variable name provided in the text. Do not output any additional text beyond the concise variable I am asking for. If no rainfall instrument is used, output n/a.",
     "dependency": {"key": "Instrumental Variable Rainfall", "value": "1"}},
    {"key": "Rainfall Data Source",
     "question": "What is the source of the rainfall data used in the study? Identify and report the exact source of the rainfall/precipitation data used as the instrument: name the dataset or provider (e.g., CHIRPS, TRMM, ERA5, NOAA station records, Indian Meterological Department). Please give me the source of the rainfall data without any additional words or numbers. If rainfall is used as an instrumental variable, the data must come from a specific source (e.g., a satellite or organization). Please find the origin of the rainfall data that was used. Please only provide the source of the rainfall data, without the title of the question or any additional words.",
     "dependency": {"key": "Instrumental Variable Rainfall", "value": "1"}}
]


def normalize_yes_no(answer):
    if not answer:
        return "0"
    answer = answer.strip().lower()
    if answer.startswith('yes') or answer == '1':
        return "1"
    elif answer.startswith('no') or answer == '0':
        return "0"
    else:
        return "n/a"


def clean_dependent_variables(raw_text):
    """
    Simple cleaner for dependent variables: remove numbered prefixes and
    normalize comma-separated list. (Keeps your existing behavior.)
    """
    cleaned = re.sub(r'\d+\)\s*', '', raw_text)
    variables = [var.strip() for var in cleaned.split(',') if var.strip()]
    return ', '.join(variables)


def clean_variable_list(raw_text):
    """
    Take a noisy answer that *should* be just variable names and
    return a semicolon-separated list of cleaned variable names.
    If nothing usable, return 'n/a'.
    """
    if not raw_text:
        return "n/a"
    txt = raw_text.strip()

    # Immediate passthrough for true n/a
    if txt.lower() in {"n/a", "na", "none"}:
        return "n/a"

    # If the model prepends a label like "Endogenous variables: X, Y"
    if ":" in txt:
        head, tail = txt.split(":", 1)
        if any(w in head.lower() for w in ["variable", "variables", "outcome", "instrument"]):
            txt = tail.strip()

    # Replace newlines with spaces; normalize separators
    txt = txt.replace("\n", " ")
    # Treat " and " as a separator sometimes used instead of commas/semicolons
    txt = txt.replace(" and ", "; ")

    # Split on common separators
    parts = re.split(r"[;,]", txt)

    cleaned = []
    for p in parts:
        p = p.strip().strip(".").strip()
        if not p:
            continue

        # Remove obvious explanation tails: " - something", " – something"
        p = re.split(r"\s[-–]\s", p)[0].strip()

        # Remove trailing descriptive clauses (where/which/that/etc.)
        p = re.split(r"\s(?:such as|for|where|which|that)\b", p, flags=re.I)[0].strip()

        # Strip quotes
        p = p.strip('"“”\'')

        # Very long chunks are likely sentences, not variable names
        if len(p.split()) > 8:
            continue

        if p and p.lower() not in {"n/a", "none"}:
            cleaned.append(p)

    # Deduplicate while preserving order
    seen = set()
    uniq = []
    for v in cleaned:
        key = v.lower()
        if key not in seen:
            seen.add(key)
            uniq.append(v)

    return "; ".join(uniq) if uniq else "n/a"


def clean_rainfall_source(raw_text):
    """
    For the rainfall data source, keep only the dataset/provider name.
    Example: 'We use CHIRPS rainfall data from ...' -> 'CHIRPS'.
    """
    if not raw_text:
        return "n/a"
    txt = raw_text.strip()

    if txt.lower() in {"n/a", "na", "none"}:
        return "n/a"

    # Take only the first sentence/line
    txt = re.split(r"[.\n]", txt, 1)[0].strip()

    # Remove leading phrases like "from", "data from", etc.
    txt = re.sub(r"^(from|data from|rainfall data from)\s+", "", txt, flags=re.I)

    # Strip quotes and trailing punctuation
    txt = txt.strip('"“”\'').strip(" .,")

    return txt if txt else "n/a"


def extract_relevant_sections(pdf_path):
    relevant_sections = []
    keywords = ["instrument", "instrumental variable", "data", "methods", "iv", "rainfall",
                "model", "econometric", "metrics", "introduction", "abstract",
                "conclusion", "strategy", "empirical"]
    with fitz.open(pdf_path) as doc:
        for page_num in range(len(doc)):
            page = doc.load_page(page_num)
            page_text = page.get_text("text")
            paragraphs = page_text.split('\n\n')
            for paragraph in paragraphs:
                if any(keyword.lower() in paragraph.lower() for keyword in keywords):
                    relevant_sections.append(paragraph)
    return ' '.join(relevant_sections)


def query_model_single(text, question, enforce_binary=False, specific_metric=False):
    user_query = f"""Based on the following relevant sections from an academic text, please answer the question below. {text} Question: {question} {"Please respond with '1' for yes, '0' for no, or 'n/a' if not applicable or unclear." if enforce_binary else "Provide a concise and accurate answer. The response should be a specific metric without broad terms. Avoid using general phrases and ensure the metric is precisely defined. If information is not available, respond with 'n/a'."} """

    try:
        response = client.chat.completions.create(
            model=fine_tuned_model_id,
            messages=[
                {
                    "role": "system",
                    "content": (
                        "You are an AI assistant that is an expert in economics paper analysis. You specializing in interpreting complex academic conent and extracting specific information, specifically metadata like the variables used in an econometric analysis."
                        "Answer using information from provided text. If not available, respond with 'n/a'. Only reply with requested information; do not provide additional text and do not include the the question in your response."
                    )
                },
                {"role": "user", "content": user_query}
            ],
            max_tokens=1000,
            temperature=.5
        )
        answer = response.choices[0].message.content.strip()
        if enforce_binary:
            return normalize_yes_no(answer)
        return answer if answer else "n/a"
    except Exception as e:
        print(f"Error querying model: {e}")
        return "n/a"


def process_pdfs_conditional_queries(pdf_folder, output_csv):
    data = []

    for filename in os.listdir(pdf_folder):
        if filename.endswith(".pdf"):
            pdf_path = os.path.join(pdf_folder, filename)
            print(f"\nProcessing {filename}...")
            relevant_sections = extract_relevant_sections(pdf_path)
            print(f"Extracted relevant sections length: {len(relevant_sections)} characters")
            max_tokens = 6000
            text_to_analyze = relevant_sections[:max_tokens * 4]

            info_dict = {
                'File Name': filename,
                'Paper Title': 'n/a',
                'DOI': 'n/a',
                'Dependent Variables': 'n/a',
                'Endogenous Variable(s)': 'n/a',
                'Instrumental Variable Used': '0',
                'Instrumental Variable(s)': 'n/a',
                'Instrumental Variable Rainfall': '0',
                'Rainfall Metric': 'n/a',
                'Rainfall Data Source': 'n/a'
            }

            temp_answers = {}

            for q in questions:
                # Universal dependency check for all questions
                if q.get('dependency'):
                    dep_key = q['dependency']['key']
                    dep_value = q['dependency']['value']
                    current_answer = temp_answers.get(dep_key, info_dict.get(dep_key, None))

                    if current_answer != dep_value:
                        print(f"Skipping '{q['key']}' due to unmet dependency")
                        # For binary rainfall question default to '0'; others 'n/a'
                        info_dict[q['key']] = '0' if q['key'] == "Instrumental Variable Rainfall" else 'n/a'
                        temp_answers[q['key']] = info_dict[q['key']]
                        continue

                # Special handling for binary questions
                enforce_binary = q['key'] in ["Instrumental Variable Used", "Instrumental Variable Rainfall"]
                specific_metric = (q['key'] == "Rainfall Metric")

                print(f"Querying: {q['question']}")
                answer = query_model_single(
                    text_to_analyze,
                    q['question'],
                    enforce_binary=enforce_binary,
                    specific_metric=specific_metric
                )

                # Post-processing
                if q['key'] == "Dependent Variables" and answer != "n/a":
                    answer = clean_dependent_variables(answer)

                # Enforce variable-name-only outputs for variable questions
                if q['key'] in ["Endogenous Variable(s)", "Instrumental Variable(s)", "Rainfall Metric"]:
                    answer = clean_variable_list(answer)

                if q['key'] == "Rainfall Data Source":
                    answer = clean_rainfall_source(answer)

                if enforce_binary:
                    answer = normalize_yes_no(answer)

                info_dict[q['key']] = answer
                temp_answers[q['key']] = answer
                print(f"Answer: {answer}")

            print(f"Final extracted info for {filename}: {info_dict}")
            data.append(info_dict)

    df = pd.DataFrame(data)
    df.to_csv(output_csv, index=False)
    print(f"Data saved to {output_csv}")


# pathnames
pdf_folder = '/Users/kieran/Library/CloudStorage/OneDrive-UniversityofArizona/weather_iv_lit/training/models/finetune_data/pdf_test_20'
output_folder = '/Users/kieran/Library/CloudStorage/OneDrive-UniversityofArizona/weather_iv_lit/training/models/output'
output_csv = os.path.join(output_folder, 'finetune_output.csv')
os.makedirs(output_folder, exist_ok=True)
process_pdfs_conditional_queries(pdf_folder, output_csv)
