import fitz  # PyMuPDF
import os
import pandas as pd
from openai import OpenAI
import re

# Initialize the OpenAI client
client = OpenAI(api_key='key')

# Fine-tuned model ID
fine_tuned_model_id = 'ft:gpt-4.1-mini-2025-04-14:aide-lab:41mini:C25jTwZ8'

# List of questions with full dependency chain
questions = [
    {"key": "Paper Title",
     "question": "You will be given the text or OCR/parsed content of an academic paper. Extract the paper’s exact title from the document. Deliberate through the identification steps internally but do not write your reasoning; output only the final title. Identify the title as the main, standalone heading near the top of the first page that precedes the author list or the Abstract. Ignore journal or platform front matter such as article-type labels (e.g., Research Article, Original Article), headers and footers, running heads or short titles, page numbers, DOIs, submission or acceptance dates, copyright notices, issue or volume information, and preprint or platform disclaimers. Do not return citation lines or references to the paper elsewhere in the document. For scanned or OCR’d files, use layout cues and keywords to locate the title block: select the prominent line(s) immediately before the author names or affiliations, or before “Abstract”, “Keywords”, or “JEL”. For conference proceedings or series, ignore series names and venue labels (e.g., Proceedings of …, Working Paper, Discussion Paper) unless they are explicitly part of the title block. If the title spans multiple lines, include all lines in order, joining with single spaces. Remove hyphenation only where it is a line-break artifact, and preserve original capitalization and punctuation. Include any subtitle that is part of the same title block (for example, text after a colon or dash). Remove footnote markers or symbols attached to the title text (such as *, †, ‡, or numeric superscripts). If bilingual titles are presented consecutively, return the first full title block as printed. If metadata or an HTML <title> differs from the in-body title, prefer the in-body title on the first page. Output strictly the title text and nothing else: no quotes, labels, prefixes, or extra whitespace or newlines."},
    {"key": "DOI",
     "question": "Extract the DOI of the focal article from the provided material. Identify the DOI for the version of record of the main paper, not DOIs from references, datasets, figures, supplements, errata/corrigenda, retractions, or preprints. Prefer the publisher’s full DOI over shortDOI or preprint identifiers; if both preprint and published DOIs exist, choose the published article’s DOI. Normalize by stripping URL wrappers (e.g., doi:, https://doi.org/), whitespace, line-break hyphenation, and trailing punctuation; return the DOI in lowercase in canonical form like 10.xxxx/xxxxx. Do not return any DOI that appears only in the reference list. If multiple DOIs are visible, select only the one that matches the article’s title/authors/journal/year and ignore all others for output. If no DOI exists for the focal article, answer exactly n/a. Think through the steps needed to disambiguate and verify the focal DOI, but do not reveal your reasoning; output only the final answer. Output must be exactly one token: the DOI string or n/a, with no extra text or formatting."},
    {"key": "Dependent Variables",
     "question": "Identify and list the dependent (outcome) variable(s) used in this paper’s main regression model(s). The dependent variable is the left-hand-side outcome being explained; it is not the treatment, instrument, control, covariate, mediator, moderator, fixed effect, or any right-hand-side regressor. Use only evidence from the paper’s main text, equations, and primary results tables; prefer the primary specification(s) in the main results section. Include additional outcomes only if they are explicitly analyzed as main outcomes (not merely robustness or ancillary checks). Extract the exact outcome variable names as they appear on the left-hand side of equations or as column labels/headers in regression tables. If the same outcome appears across multiple specifications or samples, list it once. If multiple distinct main outcomes are analyzed, list each once. Do not include first-stage outcomes in IV models, treatment assignment indicators, event-study dynamic coefficients, exposure variables, instruments, controls, or fixed effects. Output format: return only the variable name(s), with no commentary, no quotes, and no extra text; separate multiple names with semicolons and a single space after each semicolon; preserve case and any transformations that are part of the left-hand-side specification (e.g., ln(wage), log income, Δ outcome); remove measurement units or clarifying parentheses that are not part of the variable name (e.g., drop “(per 1,000)”). If you cannot identify any dependent variable from the provided content, output exactly: n/a. Perform all reasoning internally and output only the final list."},
    {"key": "Endogenous Variable(s)",
     "question": "Identify the endogenous explanatory/independent variable(s) in this paper. An endogenous variable is any regressor the authors explicitly treat as endogenous due to simultaneity/reverse causality, omitted variables, or measurement error—typically indicated by statements such as “we treat X as endogenous,” “we instrument X,” or the use of IV/2SLS/IV-Probit/GMM/control-function/2SRI, first-stage regressions, excluded instruments, or weak-instrument tests (e.g., Kleibergen–Paap). Extract only the specific variable name(s) the authors claim are endogenous. Output format: return only the variable name(s), separated by semicolons if multiple; no quotes and no additional text. Use only this paper’s content (main text, tables, figures, appendices); ignore references to other papers. Include every variable treated as endogenous in any specification; if none, return n/a. If the immediately preceding task returned 0 or n/a, return n/a here. Do not return rainfall, precipitation, other weather variables/events, or natural phenomena such as PM-based pollution as endogenous variables. Do not return the dependent variable, instruments themselves, controls treated as exogenous, or generic phrases. Do not explain your answer."},
    {"key": "Instrumental Variable Used",
     "question": "Decide whether the paper uses an instrumental-variable method to address endogeneity. Output must be exactly one of: 1, 0, n/a. Return 1 if any specification (main, robustness, or appendix) uses an excluded instrument in an IV framework such as IV/2SLS/TSLS/LIML/3SLS, control-function or two-stage residual inclusion (2SRI), IV-Probit/IV-Logit/IV-Tobit, dynamic panel GMM (Arellano–Bond/Bover/Blundell–Bond), or any GMM/endogenous switching model that explicitly relies on instruments; look for an explicit first stage or instrument set, terms like instrument/instrumented/IV/2SLS, discussion of instrument relevance and exclusion restrictions, or reporting of weak-instrument diagnostics (e.g., Kleibergen–Paap, Cragg–Donald, Stock–Yogo F-statistics) and overidentification tests (Sargan/Hansen J/Anderson–Rubin). Return 0 if the paper runs regressions without using instruments despite discussing endogeneity, or uses other identification strategies instead of IV (e.g., randomized experiments, regression discontinuity, difference-in-differences/event studies, fixed effects only, controls/matching, Heckman selection without excluded instruments, using lags merely as controls) and does not implement an IV first stage or instrument set. Return n/a only if the paper indicates there is no endogeneity concern by design (e.g., a true randomized experiment with exogenous assignment) and therefore has no need for IV. Do not infer IV use from generic mentions of IV/GMM in literature reviews, background, or for other datasets; require actual implementation in this paper’s empirical specifications, results tables, or appendix. Ignore non-statistical uses of the word instrument (e.g., measurement instruments). If multiple instruments or models appear, return 1 if any qualify. Think carefully but do not reveal your reasoning; output exactly one token: 1 or 0 or n/a, with no additional text."},
    {"key": "Instrumental Variable(s)",
     "question": "Identify and list the specific excluded instrumental variables used by the authors in their main econometric analysis to address endogeneity. Use only evidence from this paper’s own content (abstract, main text, tables and figures, methods, results, and appendices) and focus on the authors’ main specification or headline IV models. Count as instruments only variables explicitly used in an instrumental‑variable framework such as two‑stage least squares, IV, IV‑Probit, generalized method of moments, control‑function, or two‑stage residual inclusion, and described as instruments, excluded instruments, or first‑stage regressors. Do not include variables that appear only as regressors, controls, exposures, treatments, fixed effects, trends, lags used as controls, or designs without an IV first stage such as difference‑in‑differences, event studies, regression discontinuity, or matching. Ignore instruments mentioned only in cited literature; use only this paper’s models. If multiple instruments are used in the main analysis, list all of them once, in the order they appear. Reproduce the authors’ instrument names or labels as written; if no concise label is given, provide a brief descriptive phrase. For interaction or set‑based instruments, reproduce the instrument label as written (for example, the interaction term), not its component controls. If no instrumental‑variable method is used in the main analysis, output n/a. Think through the identification and selection criteria step by step before responding, but only output the final answer. Output format: one line containing only the instrument name or names separated by semicolons, with no extra text, quotes, or brackets.",
     "dependency": {"key": "Instrumental Variable Used", "value": "1"}},
    {"key": "Instrumental Variable Rainfall",
     "question": "Decide whether the paper uses rainfall or any precipitation-based measure as an instrumental variable. Your task is to return exactly one of: 1, 0, n/a. Return 1 if any specification in the paper (e.g., IV/2SLS, IV-Probit, GMM with excluded instruments, control-function, 2SRI) uses rainfall or a precipitation-derived measure as an excluded instrument. Qualifying precipitation instruments include rainfall level, deviation, shock, anomaly, standardized or cumulative precipitation, wet-day counts, precipitation intensity, drought or wetness indices such as SPI, SPEI, PDSI, scPDSI, monsoon rainfall, snowfall, snowpack or SWE, or any index explicitly constructed from precipitation. Return 0 if the paper uses instrumental-variable methods but none of the excluded instruments are precipitation-based, or if precipitation itself is the endogenous variable being instrumented by non-precipitation instruments. Return n/a if the paper does not use an instrumental-variable framework at all. Count an instrument as precipitation-based only if it is explicitly used as an excluded instrument in a first-stage/IV framework; look for terms like instrument, instrumental variable, excluded instrument, first stage, 2SLS, IV-Probit, GMM with instruments, control-function, weak-instrument F-statistic, Kleibergen-Paap, Anderson-Rubin. Do not count precipitation if it appears only as a regressor, control, interaction, exposure, or in reduced-form, DiD, event-study, RDD, matching, or OLS designs without an IV first stage. Do not count broad climate indices (e.g., ENSO) unless they are explicitly mapped to or constructed from precipitation as the instrument itself. If multiple instruments are used, return 1 if any are precipitation-based. Use only evidence from this paper’s methods, results, and appendices; ignore references to other papers. Think through the decision internally and silently; do not reveal your reasoning. Final output must be exactly one token: 1 or 0 or n/a, with no additional text.",
     "dependency": {"key": "Instrumental Variable Used", "value": "1"}},
    {"key": "Rainfall Metric",
     "question": "From the paper, identify the precipitation-based instrument variable(s) actually used in the first stage of an instrumental-variables specification. Read the full document (main text and appendix) and locate the exact construction/definition of the rainfall or precipitation shock instrument. Confirm that the variable is used as an excluded instrument in an IV/2SLS/IV-Probit/GMM/control-function/2SRI first stage; look for terms such as instrument, first stage, excluded instrument, weak-instrument F-statistic, Kleibergen–Paap, or Anderson–Rubin. Do not return variables used only as controls in the second stage, outcomes, exposures, or generic mentions unconnected to an IV first stage, and do not return cases where precipitation is the endogenous variable being instrumented by something else. Include precipitation-based measures only, such as rainfall level/total/cumulative/sum, rainfall deviations/anomalies/shocks/z-scores, standardized indices (SPI, SPEI, PDSI, scPDSI), drought/wetness indicators, counts of wet/dry days, precipitation intensity, monsoon onset day, dry-spell length, moving averages or windowed sums (e.g., last 7/30/90 days), seasonal or growing-season totals, monthly totals, log transformations, and percentile or threshold-based definitions. Exclude non-precipitation weather measures (temperature, humidity, wind) unless they are explicitly part of the named instrument used in the first stage. If multiple precipitation-based instruments or variants are used anywhere in the paper, list each one separately. Output rules: return only the exact variable name(s) or definition phrase(s) as written in the paper, one per line; preserve any transformations, thresholds, temporal windows, and spatial units; do not add commentary, labels, section names, statistics, or extra words; use plain text and no quotation marks; if numbers are part of the name (e.g., SPI-12, 7-day rainfall), keep them; if no precipitation-based instrument is used, output exactly n/a. Think through the task and select the most precise phrasing, but do not include your reasoning in the output. Examples of acceptable outputs include phrases like growing-season total rainfall, log monthly total rainfall, rainfall deviations from the long-run district mean, SPI-12 standardized precipitation index.",
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
    cleaned = re.sub(r'\d+\)\s*', '', raw_text)
    variables = [var.strip() for var in cleaned.split(',') if var.strip()]
    return ', '.join(variables)


def extract_relevant_sections(pdf_path):
    relevant_sections = []
    keywords = ["instrument", "instrumental variable", "data", "methods", "iv", "rainfall", "model", "econometric", "metrics", "model", "introduction", "abstract", "conclusion", "strategy", "empirical"]
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
                        "You are an AI assistant that is an expert in economics paper analysis. You specializing in interpreting complex academic conent and extracting nuanced information. The specific information you look to extract when reading an economic papers relates to metadata, research methods, econometric equations, variables used in the estimating equations, the use of instrumental variables." 
                        "Answer using information from provided text. If not available, respond with 'n/a'. Only reply with requested information; do not provide additional words and do not include the the question in your response."
                    )
                },
                {"role": "user", "content": user_query}
            ],
            max_tokens=1000,
            temperature=0
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
                        info_dict[q['key']] = '0' if q['key'] == "Instrumental Variable Rainfall" else 'n/a'
                        temp_answers[q['key']] = info_dict[q['key']]
                        continue

                # Special handling for binary questions
                enforce_binary = q['key'] in ["Instrumental Variable Used", "Instrumental Variable Rainfall"]
                specific_metric = (q['key'] == "Rainfall Metric")

                print(f"Querying: {q['question']}")
                answer = query_model_single(text_to_analyze, q['question'],
                                            enforce_binary=enforce_binary,
                                            specific_metric=specific_metric)

                # Post-processing
                if q['key'] == "Dependent Variables" and answer != "n/a":
                    answer = clean_dependent_variables(answer)
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
