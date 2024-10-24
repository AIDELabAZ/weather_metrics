import fitz  # PyMuPDF
import os
import pandas as pd
from openai import OpenAI

# Initialize the OpenAI client
client = OpenAI(api_key='')

# Fine-tuned model ID
fine_tuned_model_id = 'ft:gpt-4o-mini-2024-07-18:aide-lab:minitry:ALgsKbV1'  # Replace with your model ID

# Function to extract text from a PDF
def extract_text_from_pdf(pdf_path):
    text = ""
    with fitz.open(pdf_path) as doc:
        for page_num in range(len(doc)):
            page = doc.load_page(page_num)
            page_text = page.get_text("text")
            if page_text:
                text += page_text
    return text

# Function to query the fine-tuned GPT model
def query_model(text, filename):
    user_query = f"""Based on the following academic text, please answer the questions below.

{text}

Questions:
1. What is the file name of the paper?
2. What is the title of the paper?
3. What is the DOI (Digital Object Identifier) of the paper?
4. What dependent variables are analyzed in this paper?
5. What are the endogenous variable(s) considered in this paper?
6. Did the study use an instrumental variable in the analysis?
7. What instrumental variable(s) were used in the study?
8. Was rainfall used as an instrumental variable in the study?
9. How exactly was rainfall quantified or measured as an instrument in this paper?
10. What is the source of the rainfall data used in the study?

Please answer in the following format:
1. File Name: {filename}
2. Paper Title: [Answer]
3. DOI: [Answer]
4. Dependent Variables: [Answer]
5. Endogenous Variable(s): [Answer]
6. Instrumental Variable Used: [Answer]
7. Instrumental Variable(s): [Answer]
8. Instrumental Variable Rainfall: [Answer]
9. Rainfall Metric: [Answer]
10. Rainfall Data Source: [Answer]
"""

    try:
        response = client.chat.completions.create(
            model=fine_tuned_model_id,
            messages=[
                {
                    "role": "system",
                    "content": (
                        "You are an AI assistant that extracts specific information from academic papers based on provided texts. "
                        "Answer the user's questions using the information from the provided text. If the information is not available, respond with 'NA.'"
                    )
                },
                {"role": "user", "content": user_query}
            ],
            max_tokens=1000,
            temperature=0
        )
        return response.choices[0].message.content.strip()
    except Exception as e:
        print(f"Error querying the model: {e}")
        return None

# Function to parse the model's output into a dictionary
def parse_extracted_info(extracted_info, filename):
    info_dict = {
        'File Name': filename,
        'Paper Title': 'NA.',
        'DOI': 'NA.',
        'Dependent Variables': 'NA.',
        'Endogenous Variable(s)': 'NA.',
        'Instrumental Variable Used': 'NA.',
        'Instrumental Variable(s)': 'NA.',
        'Instrumental Variable Rainfall': 'NA.',
        'Rainfall Metric': 'NA.',
        'Rainfall Data Source': 'NA.'
    }

    if not extracted_info:
        return info_dict

    for line in extracted_info.split('\n'):
        if ':' in line:
            key_part, value = line.split(':', 1)
            key = key_part.strip().lstrip('0123456789. ').strip()
            value = value.strip()
            if key in info_dict and value.lower() not in ['', 'none', 'na', 'na.', 'not provided', 'not specified']:
                info_dict[key] = value
    print(f"Parsed information: {info_dict}")
    return info_dict

# Function to process PDFs in a folder and extract data into a CSV
def process_pdfs(pdf_folder, output_csv):
    data = []

    for filename in os.listdir(pdf_folder):
        if filename.endswith(".pdf"):
            pdf_path = os.path.join(pdf_folder, filename)
            print(f"\nProcessing {filename}...")

            extracted_text = extract_text_from_pdf(pdf_path)
            print(f"Extracted text length: {len(extracted_text)} characters")

            # If the text is too long, truncate it to avoid exceeding token limits
            max_tokens = 3500  # Adjust as needed
            text_to_analyze = extracted_text[:max_tokens * 4]  # Approximate conversion from tokens to characters

            print("Querying model...")
            extracted_info = query_model(text_to_analyze, filename)
            if extracted_info:
                print(f"Model response:\n{extracted_info}")
                info_dict = parse_extracted_info(extracted_info, filename)
            else:
                print(f"Failed to get a response from the model for {filename}")
                info_dict = {
                    'File Name': filename,
                    'Paper Title': 'NA.',
                    'DOI': 'NA.',
                    'Dependent Variables': 'NA.',
                    'Endogenous Variable(s)': 'NA.',
                    'Instrumental Variable Used': 'NA.',
                    'Instrumental Variable(s)': 'NA.',
                    'Instrumental Variable Rainfall': 'NA.',
                    'Rainfall Metric': 'NA.',
                    'Rainfall Data Source': 'NA.'
                }

            print(f"Final extracted info for {filename}: {info_dict}")
            data.append(info_dict)

    df = pd.DataFrame(data)
    df.to_csv(output_csv, index=False)
    print(f"Data saved to {output_csv}")

# Example usage
pdf_folder = '/Users/kieran/Library/CloudStorage/OneDrive-UniversityofArizona/weather_iv_lit/training/training_garrett'
output_folder = '/Users/kieran/Library/CloudStorage/OneDrive-UniversityofArizona/weather_iv_lit/training/finetune1/finetune1_output'
output_csv = os.path.join(output_folder, 'output.csv')

os.makedirs(output_folder, exist_ok=True)

process_pdfs(pdf_folder, output_csv)
