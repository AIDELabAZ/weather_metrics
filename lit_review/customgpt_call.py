import os
import csv
import time
import re
from openai import OpenAI
from PyPDF2 import PdfReader
import tiktoken

# Set up OpenAI client
client = OpenAI(
    api_key='apikey')

# Define the Assistant ID
ASSISTANT_ID = "asst_owUoWG8gcMHWHT0jIRIUB0Ah"  # Replace with your actual Assistant ID

# Paths to PDF folder and output folder
PDF_FOLDER_PATH = "/Users/kieran/Library/CloudStorage/OneDrive-UniversityofArizona/weather_iv_lit/training/training_mini"
OUTPUT_FOLDER_PATH = "/Users/kieran/Library/CloudStorage/OneDrive-UniversityofArizona/weather_iv_lit/training/finetune1/finetune1_output"
OUTPUT_CSV_PATH = os.path.join(OUTPUT_FOLDER_PATH, "customgpt_output.csv")

# Extraction prompts
EXTRACTION_PROMPTS = {
    "Title": "Provide only the title of this academic paper, without any additional text.",
    "DOI": "Provide only the DOI of this academic paper, without any additional text.",
    "Dependent Variable(s)": "List only the dependent variable(s) analyzed in this paper, without any additional text or explanations.",
    "Endogenous Variable(s)": "List only the endogenous variables considered in this paper, separated by commas if multiple, without any additional text or explanations.",
    "Instrumental Variable Used": "Answer only 'Yes' or 'No': Did the authors use an instrumental variable in the analysis?",
    "Instrumental Variable": "Provide only the name of the instrumental variable used in the paper, without any additional text or explanations.",
    "Instrumental Variable Rainfall": "Answer only 'Yes' or 'No': Was rainfall used as an instrumental variable in the paper?",
    "Rainfall Metric": "Provide only the specific metric used for rainfall as an instrumental variable (e.g., 'log deviations in weekly rainfall'), without any additional text or explanations.",
    "Rainfall Data Source": "Provide only the specific organization, satellite, or device used to collect the rainfall data in this study. For example, 'NOAA', 'TRMM satellite', or 'local weather stations'. If not explicitly stated, respond with 'Not specified'."
}

# Helper function to truncate text based on token limit
def truncate_text(text, max_tokens=3500):
    encoding = tiktoken.get_encoding("cl100k_base")
    tokens = encoding.encode(text)
    if len(tokens) > max_tokens:
        tokens = tokens[:max_tokens]
    return encoding.decode(tokens)

# Function to extract text from a PDF
def extract_text_from_pdf(pdf_path):
    with open(pdf_path, 'rb') as file:
        reader = PdfReader(file)
        text = ""
        for page in reader.pages:
            page_text = page.extract_text()
            if page_text:
                text += page_text
        return text

# Function to interact with the Assistant
def interact_with_assistant(content):
    thread = client.beta.threads.create()

    client.beta.threads.messages.create(
        thread_id=thread.id,
        role="user",
        content="Please provide concise responses, focusing only on the specific information requested. Avoid additional explanations or context unless explicitly asked.\n\n" + content
    )

    run = client.beta.threads.runs.create(
        thread_id=thread.id,
        assistant_id=ASSISTANT_ID
    )

    while True:
        run_status = client.beta.threads.runs.retrieve(thread_id=thread.id, run_id=run.id)
        if run_status.status == 'completed':
            break
        time.sleep(1)

    messages = client.beta.threads.messages.list(thread_id=thread.id)
    return messages.data[0].content[0].text.value

# Function to generate a summary of the entire paper
def generate_paper_summary(pdf_text, focus):
    truncated_text = truncate_text(pdf_text)
    return interact_with_assistant(
        f"Summarize the following academic paper, focusing specifically on {focus}. Provide a concise summary:\n\n{truncated_text}")

# Function to extract specific information using prompts
def extract_information(pdf_text, prompt, focus):
    summary = generate_paper_summary(pdf_text, focus)
    truncated_summary = truncate_text(summary)
    response = interact_with_assistant(f"{prompt}\n\nHere's the focused paper summary:\n{truncated_summary}")

    if focus == "Title":
        return response.strip()
    elif focus == "DOI":
        doi_match = re.search(r'\b(10\.\d{4,}(?:\.\d+)*\/\S+)\b', response)
        return doi_match.group(0) if doi_match else "DOI not found"
    elif focus == "Rainfall Data Source":
        # Extract only the source name, removing any additional text
        source = response.strip().split(',')[0].split('.')[-1].strip()
        return source if source and source.lower() != "not specified" else "Not specified"
    else:
        return response.strip()

# Function to post-process results
def post_process_results(results):
    for paper in results:
        for key, value in paper.items():
            if key in ["Filename", "Title", "DOI"]:
                continue
            elif key == "Instrumental Variable Used" or key == "Instrumental Variable Rainfall":
                paper[key] = "Yes" if "yes" in value.lower() else "No"
            elif key == "Rainfall Data Source":
                # Keep the full source name without truncation
                paper[key] = value
            else:
                paper[key] = value.split('.')[0][:50].strip()
    return results

# Main function to process PDFs and generate the CSV output
def process_pdfs():
    results = []
    pdf_files = [f for f in os.listdir(PDF_FOLDER_PATH) if f.endswith('.pdf')]
    total_files = len(pdf_files)

    for idx, filename in enumerate(pdf_files, 1):
        print(f"Processing {idx}/{total_files}: {filename}...")
        pdf_path = os.path.join(PDF_FOLDER_PATH, filename)
        try:
            pdf_text = extract_text_from_pdf(pdf_path)
            if not pdf_text.strip():
                print(f"No text extracted from {filename}. Skipping.")
                continue
            paper_data = {"Filename": filename}
            for key, prompt in EXTRACTION_PROMPTS.items():
                paper_data[key] = extract_information(pdf_text, prompt, key)
            results.append(paper_data)
        except Exception as e:
            print(f"Error processing {filename}: {e}")

    # Post-process results
    results = post_process_results(results)

    # Ensure the output directory exists
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