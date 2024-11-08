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
    "DOI": "What is the DOI of this academic paper?",
    "Dependent Variable(s)": "List the dependent variable analyzed in this paper without numbering or additional text.",
    "Endogenous Variable(s)": "What are the endogenous variable considered in this paper? These are sometimes referred to as explanatory variable and I am interested in specific variable used. Please provide just the endogenous or explanatory variable. There will sometimes be more than one, in which case you may list them seperated by commas.",
    "Instrumental Variable Used": "Did the authors use an instrumental variable in the analysis? Please answer with 'Yes' or 'No'. Sometimes the paper will discuss using some instrumental variable but not actually use it in their statistical analysis, please differentiate between mentions and uses.",
    "Instrumental Variable": "What instrumental variable was used in the paper? Sometimes the paper will discuss using some instrumental variable but not actually use it in their statistical analysis, please differentiate between mentions and uses. Please provide only the instrumental variable used without any additional text.",
    "Instrumental Variable Rainfall": "Was rainfall used as an instrumental variable in the paper? Please answer with 'Yes' or 'No'. Please make sure to differentiate between papers that mention the use of rainfall as a variable or instrument but do not actually use it from those that do.",
    "Rainfall Metric": "Provide the specific metric used (e.g., 'yearly rainfall deviations' or 'log monthly total rainfall'). Do not respond with broad terms like 'rainfall', 'precipitation', or 'rainfall and humidity' on their own, unless they are part of something like 'rainfall deviations (from long term average)' or 'unexpected rainfall shocks defined as the deviation from the long run precipitation trend' for example. How exactly was rainfall represented as an instrument in this paper? Ensure that this metric is actually used in an instrumental variables regression and not just passively mentioned. For example, in the excerpt 'by using exogenous variations in rainfall and humidity. For the instrumental variable estimation method to adequately address this issue, the instruments used are required to be correlated with the suspected endogenous variable', the rainfall metric I want is 'exogenous variations in rainfall'.",
    "Rainfall Data Source": "What is the source of the rainfall data used in the study? If rainfall is used as an instrumental variable, the data must come from a specific source (e.g., a satellite or organization). Please find the origin of the rainfall data that was used. Please only provide the source of the rainfall data."
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
        if any(header in line.lower() for header in ['abstract', 'introduction', 'method', 'data', 'result', 'discussion', 'conclusion']):
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