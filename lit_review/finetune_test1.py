import fitz  # PyMuPDF
import os
import pandas as pd
from openai import OpenAI

# Initialize the OpenAI client
client = OpenAI(api_key='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')  # Replace with your actual API key

# Fine-tuned model ID
fine_tuned_model_id = 'ft:gpt-4o-mini-2024-07-18:aide-lab:test2:AILHjgdl'  # Replace with your model ID

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

# Function to extract sections based on keywords
def extract_section(text, keywords):
    extracted_sections = {}
    text_lower = text.lower()
    for keyword in keywords:
        keyword_lower = keyword.lower()
        start_idx = text_lower.find(keyword_lower)
        if start_idx == -1:
            continue
        end_idx = len(text)
        for other_keyword in keywords:
            if other_keyword != keyword:
                other_idx = text_lower.find(other_keyword.lower(), start_idx + len(keyword))
                if other_idx != -1 and other_idx > start_idx:
                    end_idx = min(end_idx, other_idx)
        extracted_sections[keyword] = text[start_idx:end_idx].strip()
    return extracted_sections

# Function to query the fine-tuned GPT model with a focus on rainfall metrics
def query_model(text):
    user_query = f"""Analyze the following text and extract information about:
1. Dependent Variables
2. Endogenous Variables
3. Instrumental Variables
4. Rainfall Metric (How is rainfall defined and measured in the study?)
5. Data Source

For each category, provide a brief description if found. If information is not available for a category, state "Not specified".

Text to analyze:
{text}

Please format your response as follows:
Dependent Variables: [Description or "Not specified"]
Endogenous Variables: [Description or "Not specified"]
Instrumental Variables: [Description or "Not specified"]
Rainfall Metric: [Description or "Not specified"]
Data Source: [Description or "Not specified"]
"""
    response = client.chat.completions.create(
        model=fine_tuned_model_id,
        messages=[
            {"role": "system", "content": "You are a helpful assistant skilled in analyzing academic papers."},
            {"role": "user", "content": user_query}
        ],
        max_tokens=1000,
        temperature=0
    )
    return response.choices[0].message.content.strip()

# Function to parse the model's output into a dictionary
def parse_extracted_info(extracted_info):
    info_dict = {
        'Dependent Variables': 'Not specified',
        'Endogenous Variables': 'Not specified',
        'Instrumental Variables': 'Not specified',
        'Rainfall Metric': 'Not specified',
        'Data Source': 'Not specified'
    }
    for line in extracted_info.split('\n'):
        if ':' in line:
            key, value = line.split(':', 1)
            key = key.strip()
            value = value.strip()
            if key in info_dict and value.lower() not in ['', 'none', 'not specified']:
                info_dict[key] = value
    print(f"Parsed information: {info_dict}")
    return info_dict

# Function to process PDFs in a folder and extract data into a CSV
def process_pdfs(pdf_folder, output_csv):
    keywords = ["abstract", "introduction", "methodology", "data", "results", "conclusion"]
    data = []

    for filename in os.listdir(pdf_folder):
        if filename.endswith(".pdf"):
            pdf_path = os.path.join(pdf_folder, filename)
            print(f"\nProcessing {filename}...")

            extracted_text = extract_text_from_pdf(pdf_path)
            print(f"Extracted text length: {len(extracted_text)} characters")

            sections = extract_section(extracted_text, keywords)
            print(f"Extracted sections: {list(sections.keys())}")

            pdf_info = {'PDF Name': filename}
            pdf_info.update({k: 'Not specified' for k in ['Dependent Variables', 'Endogenous Variables', 'Instrumental Variables', 'Rainfall Metric', 'Data Source']})

            if sections:
                for section_name, section_text in sections.items():
                    try:
                        print(f"Querying model for section: {section_name}")
                        extracted_info = query_model(section_text[:4000])  # Limit to 4000 characters to avoid token limits
                        print(f"Model response:\n{extracted_info}")
                        info_dict = parse_extracted_info(extracted_info)
                        for key, value in info_dict.items():
                            if value != 'Not specified' and pdf_info[key] == 'Not specified':
                                pdf_info[key] = value
                    except Exception as e:
                        print(f"Error querying model for {filename} section '{section_name}': {str(e)}")
            else:
                print(f"No relevant sections found in {filename}")

            print(f"Final extracted info for {filename}: {pdf_info}")
            data.append(pdf_info)

    df = pd.DataFrame(data)
    df.to_csv(output_csv, index=False)
    print(f"Data saved to {output_csv}")

# Example usage
pdf_folder = '/Users/kieran/Library/CloudStorage/OneDrive-UniversityofArizona/weather_iv_lit/training/training_small'
output_folder = '/Users/kieran/Library/CloudStorage/OneDrive-UniversityofArizona/weather_iv_lit/training/finetune1/finetune1_output'
output_csv = os.path.join(output_folder, 'output.csv')

os.makedirs(output_folder, exist_ok=True)

process_pdfs(pdf_folder, output_csv)