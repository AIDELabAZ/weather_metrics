import fitz  # PyMuPDF
import os
import pandas as pd
from openai import OpenAI
import re

# Initialize the OpenAI client
client = OpenAI(
    api_key='key'
)

# Fine-tuned model ID
fine_tuned_model_id = 'ft:gpt-4o-mini-2024-07-18:aide-lab:rawmodel:AYGVVA3h'

# List of questions to ask with dependencies
questions = [
    {"key": "Paper Title", "question": "What is the title of the paper? Please only provide the paper title as listed without any extra words."},
    {"key": "DOI",
     "question": "What is the DOI (Digital Object Identifier) of the paper? Please provide just the DOI without any other text."},
    {
        "key": "Dependent Variables",
        "question": "List the dependent (outcome) variable analyzed in this paper, only listing the variable names without the title of the question, additional words, or numbers. Example: Text: 'Similar to the literature on the impact of wealth on fertility rate (Black et al., 2013; Dettling and Kearney, 2014; Lovenheim and Mumford, 2013), we regress a reduced form econometric specification for the impact of unanticipated economic shocks on contraceptives use in Equation 2. In this regard, we directly exploit exogenous variations in seasonal precipitation pattern to identify the impact of unanticipated economic shocks on contraceptives use in Uganda:' Variable: 'contraceptive demand' "
    },
    {
        "key": "Endogenous Variable(s)",
        "question": "What is/are the endogenous (explanatory/independent) variable(s) used in this paper? I am interested in specific variable used, please provide just the name of the variable without the title of the question, additional words, or numbers. There will sometimes be more than one, in which case you may list them seperated by commas. Example: Text: 'We use district-level data on farmersí suicides in two major states during the years 1998 to 2004 to es- timate the e§ects of transitory economic shocks and structural change in agriculture on the incidence of suicides in farm house- holds.' Variable: 'economic distress (poverty and economic shocks)' "
    },
    {
        "key": "Instrumental Variable Used",
        "question": "Did the paper use an instrumental variable in the analysis? Please answer with 'Yes' or 'No'. Sometimes the paper will discuss using some instrumental variable but not actually use it in their statistical analysis, please differentiate between mentions of IV use and actual uses."
    },
    {
        "key": "Instrumental Variable(s)",
        "question": "What instrumental variable was used in the paper? Please only list the variable name without the title of the question, additonal words, or numbers. Sometimes the paper will discuss using some instrumental variable but not actually use it in their statistical analysis, please differentiate between mentions and uses. Please provide only the instrumental variable used without any additional text. Example: Test: 'This study uses rainfall variation as an instrumental variable for rice production to esti- mate the impact of poverty on different types of crime across British colonies in South and South East Asia.' Variable: 'annual absolute rainfall deviation' "
    },
    {
        "key": "Instrumental Variable Rainfall",
        "question": "Was rainfall used as an instrumental variable in the paper? Please answer with 'Yes' or 'No'. Please make sure to differentiate between papers that mention the use of rainfall as a variable or instrument but do not actually use it from those that do."
    },
    {
        "key": "Rainfall Metric",
        "question": (
            "Provide the specific rainfall metric used (e.g., 'yearly rainfall deviations' or 'log monthly total rainfall') by looking for the most likely option given the context of the entire text without any additional words or numbers. Example: Text: 'To address such concerns, instead of using weather shocks or short-term changes in rainfall, we use the long-term change in precipitation, as measured by the deviation of actual rainfall from historical levels. ' Variable: 'rainfall deviations measured as actual deviations from historical averages' "
            "Do not respond with broad terms like 'rainfall', 'precipitation', or 'rainfall and humidity' on their own, unless they are part of something like 'rainfall deviations (from long term average)' or 'unexpected rainfall shocks defined as the deviation from the long run precipitation trend' for example. "
            "How exactly was rainfall represented as an instrument in this paper?"
            "Ensure that this metric is actually used in an instrumental variables regression and not just passively mentioned. "
            "For example, in the excerpt 'by using exogenous variations in rainfall and humidity. For the instrumental variable estimation method to adequately address this issue, the instruments used are required to be correlated with the suspected endogenous variable', the rainfall metric I want is 'exogenous variations in rainfall'. "
        ),
        "dependency": {"key": "Instrumental Variable Rainfall", "value": "Yes"}
    },
    {
        "key": "Rainfall Data Source",
        "question": (
            "What is the source of the rainfall data used in the study? Please give me the source of the rainfall data without any additional words or numbers. Example: Text: 'For exposure to climatic disruptions, rainfall data was obtained using Africa Rainfall Climatology version 2 (ARC2) from the National Oceanic and Atmospheric Administration (NOAA), and average minimum and maximum temperature were calculated using ECMWF ERA INTERIM reanalysis model data;5' Data source: 'africa rainfall climatology version 2 (arc2)' "
            "If rainfall is used as an instrumental variable, the data must come from a specific source (e.g., a satellite or organization). "
            "Please find the origin of the rainfall data that was used. "
            "Please only provide the source of the rainfall data, without the title of the question or any additional words."
        ),
        "dependency": {"key": "Instrumental Variable Rainfall", "value": "Yes"}
    }
]


def normalize_yes_no(answer):
    if not answer:
        return "No"
    answer = answer.strip().lower()
    if answer.startswith('yes'):
        return "Yes"
    elif answer.startswith('no'):
        return "No"
    else:
        return "No"  # Default to 'No' if unclear


def clean_dependent_variables(raw_text):
    cleaned = re.sub(r'\d+\)\s*', '', raw_text)
    variables = [var.strip() for var in cleaned.split(',') if var.strip()]
    return ', '.join(variables)


def validate_rainfall_metric(metric):
    # Implement validation logic if needed
    return True


def extract_relevant_sections(pdf_path):
    relevant_sections = []
    keywords = ["instrument", "instrumental variable", "data", "methods", "iv", "rainfall", "model"]

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
    user_query = f"""Based on the following relevant sections from an academic text, please answer the question below.
    {text}
    Question: {question}
    {"Please respond with 'Yes' or 'No'." if enforce_binary else "Provide a concise and accurate answer. The response should be a specific metric without broad terms. Avoid using general phrases and ensure the metric is precisely defined. If the information is not available, respond with 'NA.'."} """

    try:
        response = client.chat.completions.create(
            model=fine_tuned_model_id,
            messages=[
                {
                    "role": "system",
                    "content": (
                        "You are an AI assistant that extracts specific information related to the use of rainfall as an instrumental variable from academic papers based on provided texts."
                        "Answer the user's question using the information from the provided text. If the information is not available, respond with 'NA.' Only reply with the information requested, do not provide any additional words like 'variable:'"
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
        return answer if answer else "NA."
    except Exception as e:
        print(f"Error querying the model: {e}")
        return "NA."


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
                'Paper Title': 'NA.',
                'DOI': 'NA.',
                'Dependent Variables': 'NA.',
                'Endogenous Variable(s)': 'NA.',
                'Instrumental Variable Used': 'No',
                'Instrumental Variable(s)': 'NA.',
                'Instrumental Variable Rainfall': 'No',
                'Rainfall Metric': 'NA.',
                'Rainfall Data Source': 'NA.'
            }

            temp_answers = {}

            for q in questions:
                if 'dependency' in q:
                    dep_key = q['dependency']['key']
                    dep_value = q['dependency']['value']
                    current_answer = temp_answers.get(dep_key, info_dict.get(dep_key, "No"))

                    if dep_key in ["Instrumental Variable Used", "Instrumental Variable Rainfall"]:
                        current_answer = normalize_yes_no(current_answer)

                    if current_answer != dep_value:
                        print(
                            f"Skipping '{q['key']}' because '{dep_key}' is '{current_answer}' instead of '{dep_value}'. Setting as 'NA.'")
                        info_dict[q['key']] = 'NA.'
                        continue

                enforce_binary = q['question'].lower().startswith("did the study use") or q[
                    'question'].lower().startswith("was rainfall used")
                specific_metric = (q['key'] == "Rainfall Metric")

                print(f"Querying: {q['question']}")
                answer = query_model_single(text_to_analyze, q['question'], enforce_binary=enforce_binary,
                                            specific_metric=specific_metric)

                if q['key'] == "Dependent Variables" and answer != "NA.":
                    answer = clean_dependent_variables(answer)

                info_dict[q['key']] = answer
                temp_answers[q['key']] = answer
                print(f"Answer: {answer}")

            print(f"Final extracted info for {filename}: {info_dict}")
            data.append(info_dict)

    df = pd.DataFrame(data)
    df.to_csv(output_csv, index=False)
    print(f"Data saved to {output_csv}")


# Example usage
pdf_folder = '/Users/kieran/Library/CloudStorage/OneDrive-UniversityofArizona/weather_iv_lit/training/training_michler'
output_folder = '/Users/kieran/Library/CloudStorage/OneDrive-UniversityofArizona/weather_iv_lit/training/finetune1/finetune1_output'
output_csv = os.path.join(output_folder, 'output_raw.csv')
os.makedirs(output_folder, exist_ok=True)

process_pdfs_conditional_queries(pdf_folder, output_csv)

# current output has a ton of weird stuff like titling each cell "variable: xyz" or whatever. also have not checked for performance, and rainfall iv is not always binary response