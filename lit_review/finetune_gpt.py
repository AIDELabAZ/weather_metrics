###
## This script calls on the fine-tuned model via API and feeds it sections of PDFs that were determined through keyword identification
## The model reads the sections it is fed and a set of queries are run, model outputs are compiled and extracted as a CSV
## Data come from the 15% out of training removed_15 folder and are output as finetune_output
###

import fitz  # PyMuPDF
import os
import pandas as pd
from openai import OpenAI
import re

# Initialize the OpenAI client
client = OpenAI(
    api_key=''
)

# Fine-tuned model ID
fine_tuned_model_id = 'ft:gpt-4o-mini-2024-07-18:aide-lab:test427:BRBNF6RP'

# List of questions to ask with dependencies
questions = [
    {"key": "Paper Title",
     "question": "What is the title of the paper? Please only provide the paper title as listed without any extra words."},
    {"key": "DOI",
     "question": "What is the DOI (Digital Object Identifier) of the paper? Please provide just the DOI without any other text."},
    {"key": "Dependent Variables",
     "question": "List the dependent (outcome) variable analyzed in this paper, only listing the variable names without the title of the question, additional words, or numbers."},
    {"key": "Endogenous Variable(s)",
     "question": "What is/are the endogenous (explanatory/independent) variable(s) used in this paper? I am interested in specific variable used, please provide just the name of the variable without the title of the question, additional words, or numbers. There will sometimes be more than one, in which case you may list them separated by commas."},
    {"key": "Instrumental Variable Used",
     "question": "Did the paper use an instrumental variable in the analysis? Please answer with '1' for yes, '0' for no, or 'n/a' if not applicable or unclear."},
    {"key": "Instrumental Variable(s)",
     "question": "What instrumental variable was used in the paper? Please only list the variable name without the title of the question, additional words, or numbers. Sometimes the paper will discuss using some instrumental variable but not actually use it in their statistical analysis, please differentiate between mentions and uses. Please provide only the instrumental variable used without any additional text."},
    {"key": "Instrumental Variable Rainfall",
     "question": "Was rainfall used as an instrumental variable in the paper? Please answer with '1' for yes, '0' for no, or 'n/a' if not applicable or unclear."},
    {"key": "Rainfall Metric",
     "question": "Provide the specific rainfall metric used (e.g., 'yearly rainfall deviations' or 'log monthly total rainfall') by looking for the most likely option given the context of the entire text without any additional words or numbers. Do not respond with broad terms like 'rainfall', 'precipitation', or 'rainfall and humidity' on their own, unless they are part of something like 'rainfall deviations (from long term average)' or 'unexpected rainfall shocks defined as the deviation from the long run precipitation trend' for example. How exactly was rainfall represented as an instrument in this paper? Ensure that this metric is actually used in an instrumental variables regression and not just passively mentioned.",
     "dependency": {"key": "Instrumental Variable Rainfall", "value": "1"}},
    {"key": "Rainfall Data Source",
     "question": "What is the source of the rainfall data used in the study? Please give me the source of the rainfall data without any additional words or numbers. If rainfall is used as an instrumental variable, the data must come from a specific source (e.g., a satellite or organization). Please find the origin of the rainfall data that was used. Please only provide the source of the rainfall data, without the title of the question or any additional words.",
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
    user_query = f"""Based on the following relevant sections from an academic text, please answer the question below. {text} Question: {question} {"Please respond with '1' for yes, '0' for no, or 'n/a' if not applicable or unclear." if enforce_binary else "Provide a concise and accurate answer. The response should be a specific metric without broad terms. Avoid using general phrases and ensure the metric is precisely defined. If information is not available, respond with 'n/a'."} """

    try:
        response = client.chat.completions.create(
            model=fine_tuned_model_id,
            messages=[
                {
                    "role": "system",
                    "content": (
                        "You are an AI assistant that extracts specific information related to the use of rainfall as an instrumental variable from academic papers based on provided texts."
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
                # Query for Instrumental Variable Used first
                if q['key'] == "Instrumental Variable Used":
                    print(f"Querying: {q['question']}")
                    answer = query_model_single(text_to_analyze, q['question'], enforce_binary=True)
                    info_dict[q['key']] = answer
                    temp_answers[q['key']] = answer
                    print(f"Answer: {answer}")

                    # If no IV is used, set related fields accordingly
                    if answer == "0":
                        info_dict['Instrumental Variable(s)'] = 'n/a'
                        info_dict['Instrumental Variable Rainfall'] = '0'
                        info_dict['Rainfall Metric'] = 'n/a'
                        info_dict['Rainfall Data Source'] = 'n/a'
                        continue

                # Query for Instrumental Variable Rainfall only if IV Used is 1
                elif q['key'] == "Instrumental Variable Rainfall":
                    if info_dict['Instrumental Variable Used'] == "1":
                        print(f"Querying: {q['question']}")
                        answer = query_model_single(text_to_analyze, q['question'], enforce_binary=True)
                        info_dict[q['key']] = answer
                        temp_answers[q['key']] = answer
                        print(f"Answer: {answer}")

                        # If IV Rainfall is 0, set related fields accordingly
                        if answer == "0":
                            info_dict['Rainfall Metric'] = 'n/a'
                            info_dict['Rainfall Data Source'] = 'n/a'
                    else:
                        info_dict[q['key']] = '0'
                        temp_answers[q['key']] = '0'

                # Process other questions normally
                elif q.get('dependency'):
                    dep_key = q['dependency']['key']
                    dep_value = q['dependency']['value']
                    current_answer = temp_answers.get(dep_key, info_dict.get(dep_key, None))

                    if current_answer != dep_value:
                        print(
                            f"Skipping '{q['key']}' because '{dep_key}' is '{current_answer}' instead of '{dep_value}'. Setting as 'n/a'")
                        info_dict[q['key']] = 'n/a'
                        continue

                enforce_binary = q['key'] in ["Instrumental Variable Used", "Instrumental Variable Rainfall"]
                specific_metric = (q['key'] == "Rainfall Metric")

                print(f"Querying: {q['question']}")
                answer = query_model_single(text_to_analyze, q['question'], enforce_binary=enforce_binary,
                                            specific_metric=specific_metric)

                if q['key'] == "Dependent Variables" and answer != "n/a":
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
pdf_folder = '/Users/kieran/Library/CloudStorage/OneDrive-UniversityofArizona/weather_iv_lit/training/models/finetune1_data/pdf_test_15'
output_folder = '/Users/kieran/Library/CloudStorage/OneDrive-UniversityofArizona/weather_iv_lit/training/models/output'
output_csv = os.path.join(output_folder, 'finetune_output.csv')
os.makedirs(output_folder, exist_ok=True)
process_pdfs_conditional_queries(pdf_folder, output_csv)
