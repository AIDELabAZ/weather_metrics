import os
import csv
import openai
from PyPDF2 import PdfReader

# 1. Define paths, keys, and prompts
OPENAI_API_KEY = "YOUR_API_KEY_HERE"
CUSTOM_GPT_MODEL_ID = "YOUR_CUSTOM_GPT_MODEL_ID_HERE"
PDF_FOLDER_PATH = "/Users/kieran/Library/CloudStorage/OneDrive-UniversityofArizona/weather_iv_lit/training/training_garrett"
OUTPUT_FOLDER_PATH = "/Users/kieran/Library/CloudStorage/OneDrive-UniversityofArizona/weather_iv_lit/training/finetune1/finetune1_output"
OUTPUT_CSV_PATH = os.path.join(OUTPUT_FOLDER_PATH, "customgpt_output.csv")

EXTRACTION_PROMPTS = {
    "Title": "What is the title of this academic paper?",
    "Authors": "Who are the authors of this academic paper?",
    "Publication Year": "In what year was this academic paper published?",
    "Main Research Question": "What is the main research question of this academic paper?",
    "Methodology": "Briefly describe the methodology used in this academic paper.",
    "Key Findings": "What are the key findings or conclusions of this academic paper?"
}

# Set up OpenAI API
openai.api_key = OPENAI_API_KEY

# 2. Functions for generating section summaries
def extract_text_from_pdf(pdf_path):
    with open(pdf_path, 'rb') as file:
        reader = PdfReader(file)
        text = ""
        for page in reader.pages:
            text += page.extract_text()
    return text

def split_into_sections(text):
    sections = []
    current_section = ""
    for line in text.split('\n'):
        if any(header in line.lower() for header in ['abstract', 'introduction', 'method', 'result', 'discussion', 'conclusion']):
            if current_section:
                sections.append(current_section)
            current_section = line + "\n"
        else:
            current_section += line + "\n"
    if current_section:
        sections.append(current_section)
    return sections

def summarize_section(section_text):
    summary_prompt = f"Summarize the following section of an academic paper, focusing on key points and main ideas:\n\n{section_text[:4000]}"
    response = openai.ChatCompletion.create(
        model=CUSTOM_GPT_MODEL_ID,
        messages=[
            {"role": "system", "content": "You are an AI assistant specialized in summarizing academic papers."},
            {"role": "user", "content": summary_prompt}
        ]
    )
    return response.choices[0].message['content'].strip()

def generate_paper_summary(pdf_text):
    sections = split_into_sections(pdf_text)
    section_summaries = [summarize_section(section) for section in sections]
    return "\n\n".join(section_summaries)

# 3. Function for running extraction prompts
def extract_information(text, prompt):
    response = openai.ChatCompletion.create(
        model=CUSTOM_GPT_MODEL_ID,
        messages=[
            {"role": "system", "content": "You are an AI assistant specialized in extracting specific information from academic paper summaries."},
            {"role": "user", "content": f"{prompt}\n\nHere's the paper summary:\n{text[:4000]}"}
        ]
    )
    return response.choices[0].message['content'].strip()

# 4. Main function to process PDFs and generate CSV
def process_pdfs():
    results = []

    for filename in os.listdir(PDF_FOLDER_PATH):
        if filename.endswith('.pdf'):
            pdf_path = os.path.join(PDF_FOLDER_PATH, filename)
            print(f"Processing {filename}...")

            # Extract text and generate summary
            pdf_text = extract_text_from_pdf(pdf_path)
            paper_summary = generate_paper_summary(pdf_text)

            # Extract information using prompts
            paper_data = {"Filename": filename}
            for key, prompt in EXTRACTION_PROMPTS.items():
                paper_data[key] = extract_information(paper_summary, prompt)

            results.append(paper_data)

    # Ensure output directory exists
    os.makedirs(OUTPUT_FOLDER_PATH, exist_ok=True)

    # Write results to CSV
    if results:
        keys = ["Filename"] + list(EXTRACTION_PROMPTS.keys())
        with open(OUTPUT_CSV_PATH, 'w', newline='', encoding='utf-8') as output_file:
            dict_writer = csv.DictWriter(output_file, keys)
            dict_writer.writeheader()
            dict_writer.writerows(results)

        print(f"Results have been written to {OUTPUT_CSV_PATH}")
    else:
        print("No results to write.")

# Run the main function
if __name__ == "__main__":
    process_pdfs()