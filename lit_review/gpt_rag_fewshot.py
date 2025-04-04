import fitz  # PyMuPDF
import os
import pandas as pd
import re
from openai import OpenAI

# Initialize the OpenAI client
client = OpenAI(api_key="key")  # Replace with your key

# List of questions to ask with dependencies
questions = [
    {"key": "Paper Title",
     "question": "What is the title of the paper? Please only provide the paper title as listed without any extra words."},
    {"key": "DOI",
     "question": "What is the DOI (Digital Object Identifier) of the paper? Please provide just the DOI without any other text."},
    {"key": "Dependent Variables",
     "question": "List the dependent (outcome) variable analyzed in this paper, only listing the variable names without additional words or numbers."},
    {"key": "Endogenous Variable(s)",
     "question": "What is/are the endogenous (explanatory/independent) variable(s) used in this paper? Provide just the name(s) separated by commas if multiple."},
    {"key": "Instrumental Variable Used",
     "question": "Did the paper use an instrumental variable? Answer '1' (yes), '0' (no), or 'n/a'."},
    {"key": "Instrumental Variable(s)",
     "question": "What instrumental variable was used? Provide only the variable name."},
    {"key": "Instrumental Variable Rainfall",
     "question": "Was rainfall used as an IV? Answer '1', '0', or 'n/a'."},
    {"key": "Rainfall Metric",
     "question": "Provide specific rainfall metric used in IV regression (e.g., 'yearly deviations').",
     "dependency": {"key": "Instrumental Variable Rainfall", "value": "1"}},
    {"key": "Rainfall Data Source",
     "question": "Source of rainfall data? Provide only the source name.",
     "dependency": {"key": "Instrumental Variable Rainfall", "value": "1"}}
]


def normalize_yes_no(answer):
    """Normalize yes/no answers to 1/0/n/a format"""
    if not answer:
        return "0"
    answer = answer.strip().lower()
    if answer.startswith('yes') or answer == '1':
        return "1"
    return "0" if answer.startswith('no') or answer == '0' else "n/a"


def clean_dependent_variables(raw_text):
    """Clean and format dependent variables list"""
    cleaned = re.sub(r'\d+\)\s*', '', raw_text)
    variables = [var.strip() for var in cleaned.split(',') if var.strip()]
    return ', '.join(variables)


def extract_relevant_sections(pdf_path):
    """Extract relevant sections from PDF using keywords"""
    keywords = ["instrument", "data", "methods", "iv", "rainfall", "model"]
    relevant_sections = []

    with fitz.open(pdf_path) as doc:
        for page in doc:
            paragraphs = page.get_text("text").split('\n\n')
            relevant_sections.extend([
                p for p in paragraphs
                if any(kw in p.lower() for kw in keywords)
            ])
    return ' '.join(relevant_sections)


def query_model_single(text, question, enforce_binary=False):
    """Query OpenAI API with modern syntax"""
    system_msg = (
        "You extract specific information from academic papers. "
        "Respond with exact values or 'n/a' if unavailable. "
        "No explanations or extra text."
    )

    try:
        response = client.chat.completions.create(
            model="gpt-4o-mini",  # Use valid model name
            messages=[
                {"role": "system", "content": system_msg},
                {"role": "user", "content": f"{text}\nQuestion: {question}"}
            ],
            max_tokens=500,
            temperature=.5
        )
        answer = response.choices[0].message.content.strip()
        return normalize_yes_no(answer) if enforce_binary else answer

    except Exception as e:
        print(f"API Error: {str(e)[:200]}")  # Truncate long errors
        return "n/a"


def process_pdfs_conditional_queries(pdf_folder, output_csv):
    """Main processing function with dependency handling"""
    data = []

    for filename in os.listdir(pdf_folder):
        if not filename.endswith(".pdf"):
            continue

        pdf_path = os.path.join(pdf_folder, filename)
        print(f"\nProcessing {filename}...")

        # Extract and process text
        text = extract_relevant_sections(pdf_path)[:24000]  # ~6k tokens
        info = {
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
        temp = {}

        for q in questions:
            if q.get('dependency'):
                dep_key = q['dependency']['key']
                if temp.get(dep_key, info[dep_key]) != q['dependency']['value']:
                    info[q['key']] = 'n/a'
                    continue

            enforce_binary = q['key'] in ["Instrumental Variable Used", "Instrumental Variable Rainfall"]
            answer = query_model_single(text, q['question'], enforce_binary)

            if q['key'] == "Dependent Variables" and answer != "n/a":
                answer = clean_dependent_variables(answer)

            info[q['key']] = answer
            temp[q['key']] = answer
            print(f"{q['key']}: {answer}")

        data.append(info)

    pd.DataFrame(data).to_csv(output_csv, index=False)
    print(f"\nSaved results to: {output_csv}")


# Execution
if __name__ == "__main__":
    pdf_folder = '/Users/kieran/Library/CloudStorage/OneDrive-UniversityofArizona/weather_iv_lit/training/training_large'  # Your path
    output_csv = '/Users/kieran/Library/CloudStorage/OneDrive-UniversityofArizona/weather_iv_lit/training/models/output/gpt_rag_zeroshot_output.csv'  # Your path
    process_pdfs_conditional_queries(pdf_folder, output_csv)
