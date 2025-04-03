import fitz  # PyMuPDF
import os
import pandas as pd
from openai import OpenAI
import re

client = OpenAI(
    api_key='key'
)

# List of questions to ask with dependencies
questions = [
    {"key": "Paper Title",
     "question": "What is the title of the paper? Please only provide the paper title as listed without any extra words."},
    {"key": "DOI",
     "question": "What is the DOI (Digital Object Identifier) of the paper? Please provide just the DOI without any other text."},
    {"key": "Dependent Variables",
     "question": "List the dependent (outcome) variable analyzed in this paper, only listing the variable names without the title of the question, additional words, or numbers.",
     "few_shot_examples": [
         {"input": "We calculated the speed of the government response as a dichotomous variable that is coded 1 if the government responded to the scandal within one month,1 and 0 otherwise. Panel A of Figure 1 displays the distribution of government responsiveness across scandal types. To measure the severity of officials’ disciplining, we use an ordinal variable ranging from −1 to 10: promotion (−1), no action (0), (serious) warning and record a (serious) demerit (1), suspension from post (2), resignation (3), removal from post (4), dismissal from post (5), expulsion from party and discharge (6), fixed-term imprisonment (7), life imprisonment (8), death sentence with reprieve (9), and death sentence (10). Panel B of Figure 1 plots the distribution of punishments across scandal types. We distributed these cases into four categories based on the severity of the punishment: promotion (−1), no action (0), administrative penalty (1–6), and judicial penalty (7–10).", "output": "government accountability "},
         {"input": "Nonseparable household modelsoutline the interlinkage between agricultural production and household consumption, yet empirical extensions to investigate the effect of production on dietary diversity and diet composition are limited. While a significant literature has investigated the calorie-income elasticity abstracting from production, this paper provides an empirical application of the nonseparable household model linking the effect of exogenous variation in planting season production decisions via climate variability on household dietary diversity. Using degree days, rainfall and agricultural capital stocks as instruments, the effect of production on household dietary diversity at harvest is estimated. The empirical specifications estimate production effects on dietary diversity using both agricultural revenue and crop production diversity. Significant effects of both agricultural revenue and crop production diversity on dietary diversity are estimated. The dietary diversityproduction elasticities imply that a 10 per cent increase in agricultural revenue or crop diversity result in a 1.8 per cent or 2.4 per cent increase in dietary diversity respectively. These results illustrate that agricultural income growth or increased crop diversity may not be sufficient to ensure improved dietary diversity. Increases in agricultural revenue do change diet composition. Estimates of the effect of agricultural income on share of calories by food groups indicate relatively large changes in diet composition. On average, a 10 per cent increase in agricultural revenue makes households 7.2 per cent more likely to consume vegetables, 3.5 per cent more likely to consume fish, and increases the share of tubers consumed by 5.2 per cent.", "output": "household dietary diversity"}
     ]},
    {"key": "Endogenous Variable(s)",
     "question": "What is/are the endogenous (explanatory/independent) variable(s) used in this paper? I am interested in specific variable used, please provide just the name of the variable without the title of the question, additional words, or numbers. There will sometimes be more than one, in which case you may list them separated by commas."},
    {"key": "Instrumental Variable Used",
     "question": "Did the paper use an instrumental variable in the analysis? Please answer with '1' for yes, '0' for no, or 'n/a' if not applicable or unclear."},
    {"key": "Instrumental Variable(s)",
     "question": "What instrumental variable was used in the paper? Please only list the variable name without additional text."},
    {"key": "Instrumental Variable Rainfall",
     "question": "Was rainfall used as an instrumental variable in the paper? Please answer with '1' for yes, '0' for no, or 'n/a' if not applicable or unclear."},
    {"key": "Rainfall Metric",
     "question": "Provide the specific rainfall metric used (e.g., 'yearly rainfall deviations' or 'log monthly total rainfall') by looking for the most likely option given the context of the entire text without any additional words or numbers.",
     "dependency": {"key": "Instrumental Variable Rainfall", "value": "1"}},
    {"key": "Rainfall Data Source",
     "question": "What is the source of the rainfall data used in the study? Please give me the source of the rainfall data without any additional words or numbers.",
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
    keywords = ["instrument", "instrumental variable", "data", "methods", "iv",
                "rainfall", "model", "DOI", "independent variable",
                "dependent variable", "explanatory variable",
                "outcome variable", "endogenous variable",
                "source", "metrics", "analysis"]
    with fitz.open(pdf_path) as doc:
        for page_num in range(len(doc)):
            page = doc.load_page(page_num)
            page_text = page.get_text("text")
            paragraphs = page_text.split('\n\n')
            for paragraph in paragraphs:
                if any(keyword.lower() in paragraph.lower() for keyword in keywords):
                    relevant_sections.append(paragraph)
    return ' '.join(relevant_sections)


def query_model_single(text, question, enforce_binary=False):
    user_query = f"""Based on the following relevant sections from an academic text, please answer this question: {text} Question: {question}"""

    try:
        response = client.chat.completions.create(  # CORRECTED LINE
            model="gpt-4o-mini",
            messages=[
                {
                    "role": "system",
                    "content": "You are an AI assistant that extracts specific information related to academic texts."
                },
                {"role": "user", "content": user_query}
            ],
            max_tokens=1000,
            temperature=0
        )
        answer = response.choices[0].message.content.strip()  # Keep this line as-is
        if enforce_binary:
            return normalize_yes_no(answer)
        return answer if answer else "n/a"
    except Exception as e:
        print(f"Error querying model: {e}")
        return "n/a"



def process_pdfs_conditional_queries(pdf_folder, output_csv):
    os.makedirs(os.path.dirname(output_csv), exist_ok=True)  # Ensure output directory exists

    data = []

    for filename in os.listdir(pdf_folder):
        if filename.endswith(".pdf"):
            pdf_path = os.path.join(pdf_folder, filename)
            print(f"\nProcessing {filename}...")

            relevant_sections = extract_relevant_sections(pdf_path)
            if not relevant_sections:
                print(f"Skipping {filename} - no relevant sections found")
                continue

            max_context_length = 6000 * 3  # Approximate token-to-character conversion
            text_to_analyze = relevant_sections[:max_context_length]

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
                if q.get('dependency'):
                    dep_key = q['dependency']['key']
                    dep_value = q['dependency']['value']
                    current_answer = temp_answers.get(dep_key, info_dict.get(dep_key))
                    if current_answer != dep_value:
                        info_dict[q['key']] = 'n/a'
                        continue

                enforce_binary = q['key'] in ["Instrumental Variable Used", "Instrumental Variable Rainfall"]

                print(f"Querying: {q['question']}")
                answer = query_model_single(text_to_analyze, q['question'], enforce_binary=enforce_binary)

                if q['key'] == "Dependent Variables" and answer != "n/a":
                    answer = clean_dependent_variables(answer)

                info_dict[q['key']] = answer
                temp_answers[q['key']] = answer

            data.append(info_dict)

    df = pd.DataFrame(data)
    df.to_csv(output_csv, index=False, encoding='utf-8-sig')
    print(f"Data saved to {output_csv}")


# Example usage
pdf_folder = '/Users/kieran/Library/CloudStorage/OneDrive-UniversityofArizona/weather_iv_lit/training/training_large'
output_csv = '/Users/kieran/Library/CloudStorage/OneDrive-UniversityofArizona/weather_iv_lit/training/finetune1/finetune1_output/gpt_rag_output.csv'

process_pdfs_conditional_queries(pdf_folder, output_csv)
