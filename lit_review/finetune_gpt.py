import fitz  # PyMuPDF
import os
import pandas as pd
from openai import OpenAI
import re

# Initialize the OpenAI client
client = OpenAI(api_key='')

# Fine-tuned model ID
fine_tuned_model_id = 'ft:gpt-4o-mini-2024-07-18:aide-lab:promptupdate:BwyCKxtd'

# List of questions with full dependency chain
questions = [
    {"key": "Paper Title",
     "question": "What is the title of the paper? Extract the paper's exact title—only the title—from the PDF, prioritizing the title page/front matter; ignore author names, affiliations, journal headers/footers, and running heads, and if the file is a scanned image use OCR cues to select the standalone line(s) immediately preceding the author list. Please only provide the paper title as listed without any additional text."},
    {"key": "DOI",
     "question": "What is the DOI (Digital Object Identifier) of the paper? Scan the PDF (title page, headers/footers, first/last pages) for any string beginning with '10.' and formatted as a DOI. If multiple DOIs appear, return the one for the focal article and note others. Please provide just the DOI without any additional text. If no DOI exists, answer 'n/a'."},
    {"key": "Empirical Analysis",
     "question": "Determine whether this paper includes empirical quantitative analysis via regression or similar statistical methods. Scan for data sections, econometric/empirical strategy descriptions, model equations with error terms, coefficient tables with standard errors/p-values, and mentions of estimation techniques (e.g., OLS, IV, DiD). Please answer with '1' if the paper does contain empirical statistical analysis, '0' for no, or 'n/a' if not applicable or unclear."},
    {"key": "Dependent Variable(s)",
     "question": "If you answered '1' to the previous question, meaning the paper does contain empirical statistical analysis, then identify and list the dependent (outcome) variable(s) in the regression equation. Only list the variable names without any additional text. The dependent variable is the left hand side measure of the study's main outcome (the quantity the authors aim to explain or predict) modeled as a function of the explanatory variables.  There will sometimes be more than one, in which case you may list them separated by semicolons."},
    {"key": "Endogenous Variable(s) Present",
     "question": "If you answered '1' to the question about empirical analysis, then determine whether the authors treat any regressor as endogenous. Search for explicit mentions of 'endogeneity' or related biases, reports of Hausman/DWH or overidentification tests, use of IV/2SLS/GMM or endogenous switching or control-function methods, and first-stage/reduced-form equations indicating instrumentation. identify whether the authors address the endogeneity by using instrumental variables. Please answer with '1' if the paper does contain empirical statistical analysis, '0' for no, or 'n/a' if not applicable because the paper does not contain any empirical analysis or dependent variable(s)."},
    {"key": "Endogenous Variable(s)",
     "question": "If you answered '1' to the question about the presence of an endogeneity issue, then identify and list the endogenous (explanatory/independent) variable(s) used in this paper. An endogenous variable is any regressor whose observed variation is correlated with the model's error term— ecause it is jointly determined with the outcome or influenced by omitted factors, simultaneity, or measurement error. Endogenous variables produce coefficients that would be biased/inconsistent under naive OLS. I am interested in the specific variable that the authors claim are endogenous. Please provide just the name of the variable(s) without any additional text. If there is an endogeneity issue than there will be an endogenous variable. Rainfall, precipitation, or other weather events or natural phenomanon like pollution measured in PM will never be the endogenous variable. There will sometimes be more than one endogenous, in which case you may list them separated by semicolons. If you answered '0' or 'n/a' to the previous question, than answer 'n/a' to this question."},
    {"key": "Instrumental Variable(s) Use",
     "question": "If you answered '1' to the question about the presence of an endogeneity issue, then identify whether the authors address the endogeneity issue by using instrumental variables. Look for explicit mention of IV/2SLS/GMM, endogenous switching, a first-stage equation or table, discussion of the instrument's relevance and exclusion restriction, or reporting of weak-instrument or overidentification tests. Authors will often write that they `instrument` for the endogenous variable, which is another clue to determine if an instrumental variable is used. Be care because sometimes the authors will discuss using an instrumental variable but conclude it is not necessary or possible and end up not using one in their statistical analysis. Please differentiate between mentions or discussions of instrumental variables and their actual use in the regression analysis. Please answer with '1' if they did use an instrument, '0' for no, or 'n/a' if there is not an endogeneity issue."},
    {"key": "Instrumental Variable(s)",
     "question": "If you answered '1' to the question about if an instrumental variable was used, then identify and list the exact variable(s) that the authors say is their 'instrument'. The instrumental variable(s) will be the variables used in the first-stage to predict the endogenous regressor and excluded from the second-stage because the authors claim that the instrument affects the outcome only through the endogenous regressor. Please provide only the instrumental variable used without any additional text. There will sometimes be more than one instrumental variable, in which case you may list them separated by semicolons. If you answered '0' or 'n/a' to the previous question, than answer 'n/a' to this question.",
     "dependency": {"key": "Instrumental Variable Used", "value": "1"}},
    {"key": "Instrumental Variable Rainfall",
     "question": "If you answered '1' to the question about if an instrumental variable was used, then identify whether any rainfall/precipitation measure is used as an instrumental variable. Scan for IV/2SLS language, first-stage equations or tables where a rainfall variable predicts the endogenous regressor, and discussion of its relevance/exclusion restriction. The authors may not literally write 'rainfall' in the instrument list. Watch for variable labels like: rain, rainfall, precip, precipitation, rain_dev, rain_anom, rain_shock, rain_gs (growing season), SPI, PDSI, 'ENSO index', 'monsoon onset', drought, 'rainfall z-score', 'weather shocks', 'hydro-meteorological index', 'water availability', 'soil moisture anomaly'. If any of these show up in the first-stage but not the second-stage as a control, it is probably the instrument. Please answer with '1' for yes, '0' for no, or 'n/a' if there is not an instrumental variable used.",
     "dependency": {"key": "Instrumental Variable Used", "value": "1"}},
    {"key": "Rainfall Metric",
     "question": "If you answered '1' to the question about if rainfall was used as an instrumental variable, then identify and list exactly how the paper measures or constructs the rainfall/weather-shock instrument. Give the precise variable name(s) (e.g., growing-season total rainfall, mean daily rainfall, day of monsoon onset, days without rain). Pay particular attention to any transformations of the volume of precipitation (e.g., deviation, z-score) or thresholds used. If multiple rainfall measures are used, list each and note how they differ. Do not respond with broad terms like 'rainfall', 'precipitation', or 'rainfall and humidity' on their own, unless they are part of something like 'rainfall deviations (from long term average)' or 'unexpected rainfall shocks defined as the deviation from the long run precipitation trend' for example. Ensure that this metric is actually used in the first-stage of an instrumental variables regression and not as a control in the second-stage or just passively mentioned. If you answered '0' or 'n/a' to the previous question, than answer 'n/a' to this question.",
     "dependency": {"key": "Instrumental Variable Rainfall", "value": "1"}},
    {"key": "Rainfall Data Source",
     "question": "If you answered '1' to the question about if rainfall was used as an instrumental variable, then identify and report the exact source of the rainfall/precipitation data used as the instrument: name the dataset or provider (e.g., CHIRPS, TRMM, ERA5, NOAA station records, Indian Meterological Department). Please give me the source of the rainfall data without any additional words or numbers. If rainfall is used as an instrumental variable, the data must come from a specific source (e.g., a satellite or organization). Please find the origin of the rainfall data that was used. Please only provide the source of the rainfall data, without the title of the question or any additional words.  If you answered '0' or 'n/a' to the question about if rainfall was used as an instrumental variable, than answer 'n/a' to this question.",
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
                        "You are an AI assistant that is an expert in economics paper analysis. You specializing in interpreting complex academic conent and extracting nuanced information. The specific information you look to extract when reading an economic papers relates to metadata, research methods, econometric equations, variables used in the estimating equations, the use of instrumental variables, and especially the use of rainfall as an instrumental variable."
                        "Answer using information from provided text. If not available, respond with 'n/a'. Only reply with requested information; do not provide additional words."
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
