* Project: WB Weather - metric 
* Created on: June 2024
* Created by: kcd
* Last edited by: 09/04/2024
* Edited by: kcd on mac
* Stata v.18.0

* does
    * Imports pdfs and feeds them to chatgpt via api. reads them and outputs a csv with relevant information
* assumes
    * ChatGPT pro account with sufficient funding
	* pip install openai pymupdf pandas openpyxl in terminal
	* 

* TO DO:
    * everything
	
* notes
	* as of now, the api key is deactivated after every push. each new session requires a newly generated api key until we can figure this out. this may also be an issue that is not 		resolvable and well have to leave a not for people to put in their own key or something. 

* **********************************************************************
* 0 - setup
* **********************************************************************

python
import subprocess
import sys

# Function to install packages
def install(package):
    subprocess.check_call([sys.executable, "-m", "pip", "install", package])
	
# Install required packages
install("pymupdf")
install("openai")
install("pandas")
install("openpyxl")
install("PyPDF2")
end

* **********************************************************************
* 1 - using a small training set to troubleshoot for consistency (n=15)
* **********************************************************************

python
import os
import csv
import pdfplumber
from openai import OpenAI

def extract_text_from_pdf(pdf_file_path):
    """Extracts text from the entire PDF file."""
    full_text = ""
    try:
        with pdfplumber.open(pdf_file_path) as pdf:
            for page in pdf.pages:
                text = page.extract_text()
                if text:
                    full_text += text + "\n"
        # After extracting the text, print the first 500 characters for verification
        print(f"Extracted Text from {pdf_file_path}:\n{full_text[:500]}\n{'-'*80}")
        return full_text
    except Exception as e:
        print(f"An error occurred while extracting text from {pdf_file_path}: {e}")
        return ""

def get_paper_info(text):
    client = OpenAI(api_key='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')

    messages = [
        {"role": "system", "content": "You are an AI assistant that extracts specific details from academic papers."},
        {
            "role": "user",
            "content": (
                "You are an assistant that extracts specific details from academic papers, especially regarding the use of different rainfall metrics used as instrumental variables.\n\n"
                "Please extract the following details from the text, providing as much detail as possible:\n\n"
                "- **Paper title**: Extracted from the title page.\n"
                "- **DOI**: If available, extracted from the text.\n"
                "- **Instrumental variable used**: Indicate 'Yes' if any instrumental variables are used in the paper, 'No' otherwise.\n"
                "- **Instrumental variable rainfall**: Indicate 'Yes' if rainfall is used as an instrumental variable, 'No' otherwise.\n"
                "- **Rainfall metric**: If rainfall is used as an instrumental variable, provide a concise description of the rainfall metric used, such as 'rainfall variation as log weekly deviations from long-term average'. I am interested in how rainfall is measured, calculated, or used as an instrumental variable. If the paper merely discuss rainfall as an IV but does it directly apply it in its analysis please code it as 'No'. If there are multiple mentions of rainfall, please refer to the way it was measured as it appears in the tables or regression outputs. If rainfall is not used as an instrumental variable, state 'N/A'.\n"
                "- **Rainfall data source**: If rainfall is used as an instrumental variable, find the specific source of rainfall data (e.g., which satelite is came from). If rainfall or weather are used, the source of the data will be somewhere in the paper, though you may have to infer. If not available or not applicable, state 'N/A'.\n"
                "- **Explanatory variable(s)**: Provide the explanatory variable (e.g., independent or predictor) of interest or state 'N/A'.\n"
                "- **Outcome variable(s)**: Provide the outcome variable of interest (e.g., dependent or predicted) or state 'N/A'.\n"
                "- **Control variable(s)**: Provide a list of variables that the authors controlled for or state 'N/A'.\n\n"
                "Important:\n"
                "- If rainfall is mentioned or discussed in the paper but not used as an instrumental variable, 'Instrumental variable rainfall' should be 'No', and 'Rainfall metric' and 'Rainfall data source' should be 'N/A'.\n"
                "- If instrumental variables are used in the paper but none of them involve rainfall, 'Instrumental variable rainfall' should be 'No', and 'Rainfall metric' and 'Rainfall data source' should be 'N/A'.\n"
                "- Provide accurate 'Yes' or 'No' answers based on the content of the paper.\n\n"
                "Format your response exactly as in the examples, with each field on a new line.\n\n"
                "Text:\n" + text
            ),
        },
    ]

    try:
        response = client.chat.completions.create(
            model="gpt-4o-mini",
            messages=messages,
            max_tokens=1500,
            n=1,
            temperature=0,  # Set temperature to 0 for deterministic output
        )
        return response.choices[0].message.content.strip()
    except Exception as e:
        print(f"An error occurred during OpenAI API call: {e}")
        return None

def parse_paper_info(info):
    details = {
        "Paper Title": "N/A",
        "DOI": "N/A",
        "Instrumental Variable Used": "N/A",
        "Instrumental Variable Rainfall": "N/A",
        "Rainfall Metric": "N/A",
        "Rainfall Data Source": "N/A",
        "Explanatory Variable(s)": "N/A",
        "Outcome Variable(s)": "N/A",
        "Control Variable(s)": "N/A"
    }

    if not info:
        return details  # Return default values if info is None due to an error

    lines = info.strip().split("\n")
    for line in lines:
        if ":" in line:
            key, value = line.split(":", 1)
            key = key.strip().lower()
            value = value.strip()
            if "paper title" in key:
                details["Paper Title"] = value
            elif "doi" in key:
                details["DOI"] = value
            elif "instrumental variable used" in key:
                details["Instrumental Variable Used"] = value
            elif "instrumental variable rainfall" in key:
                details["Instrumental Variable Rainfall"] = value
            elif "rainfall metric" in key:
                details["Rainfall Metric"] = value
            elif "rainfall data source" in key:
                details["Rainfall Data Source"] = value
            elif "explanatory variable" in key:
                details["Explanatory Variable(s)"] = value
            elif "outcome variable" in key:
                details["Outcome Variable(s)"] = value
            elif "control variable" in key:
                details["Control Variable(s)"] = value

    return details

def process_pdfs_in_directory(directory):
    """Processes all PDFs in the given directory."""
    results = []
    for filename in os.listdir(directory):
        if filename.endswith('.pdf'):
            print(f"Processing file: {filename}")
            pdf_file_path = os.path.join(directory, filename)
            text = extract_text_from_pdf(pdf_file_path)
            if not text:
                print(f"No text extracted from {filename}, skipping.")
                continue
            paper_info = get_paper_info(text)
            parsed_info = parse_paper_info(paper_info)
            parsed_info["File Name"] = filename
            results.append(parsed_info)
    return results

def save_results_to_csv(results, output_file):
    """Saves the extracted results to a CSV file."""
    fieldnames = [
        "File Name", "Paper Title", "DOI", "Instrumental Variable Used",
        "Instrumental Variable Rainfall", "Rainfall Metric",
        "Rainfall Data Source", "Explanatory Variable(s)",
        "Outcome Variable(s)", "Control Variable(s)"
    ]

    try:
        with open(output_file, 'w', newline='', encoding='utf-8') as csvfile:
            writer = csv.DictWriter(csvfile, fieldnames=fieldnames)
            writer.writeheader()
            for result in results:
                writer.writerow(result)
    except Exception as e:
        print(f"An error occurred while saving results to CSV: {e}")

if __name__ == "__main__":
    # Define the directory containing the PDFs
    pdf_directory = '/Users/kieran/Library/CloudStorage/OneDrive-UniversityofArizona/weather_iv_lit/training/training_small'

    # Process the PDFs
    results = process_pdfs_in_directory(pdf_directory)

    # Save the results to a CSV file in the same directory as the PDFs
    output_file = os.path.join(pdf_directory, 'PDF_Analysis_small')
    save_results_to_csv(results, output_file)
    print(f"Results saved to {output_file}")
end

python
import os
import glob
import re
import pandas as pd
from PyPDF2 import PdfReader
from sfi import Data, Macro, Stata
import spacy

# Load spaCy model
nlp = spacy.load('en_core_web_sm')

# Clear the current Stata dataset
Stata.run('clear')

# Define the folder path
folder_path = '/Users/kieran/Library/CloudStorage/OneDrive-UniversityofArizona/weather_iv_lit/training/training_small'

# Get a list of all PDF files in the folder
pdf_files = glob.glob(os.path.join(folder_path, '*.pdf'))

# Initialize a list to hold the data
data = []

# Define common terms for instrumental variables
instrumental_variables = ['rainfall', 'weather', 'temperature', 'precipitation', 'humidity']

# Function to extract text from PDF
def extract_text(pdf_file):
    text = ''
    try:
        with open(pdf_file, 'rb') as file:
            reader = PdfReader(file)
            for page in reader.pages:
                page_text = page.extract_text()
                if page_text:
                    text += page_text
        # Replace multiple spaces and newlines with a single space
        text = re.sub(r'\s+', ' ', text)
    except Exception as e:
        print(f"Error reading {pdf_file}: {e}")
    return text

# Function to extract the paper title
def extract_title(text):
    lines = text.strip().split('\n')
    title = ''
    for line in lines[:10]:  # Check the first 10 lines
        if len(line.strip()) > len(title):
            title = line.strip()
    return title

# Function to extract DOI
def extract_doi(text):
    doi_match = re.search(r'\b10\.\d{4,9}/[-._;()/:A-Z0-9]+', text, re.IGNORECASE)
    return doi_match.group(0) if doi_match else ''

# Function to extract instrumental variables
def extract_instrumental_variables(text):
    instruments_found = []
    for term in instrumental_variables:
        if re.search(r'\b' + re.escape(term) + r'\b', text, re.IGNORECASE):
            instruments_found.append(term)
    return ', '.join(set(instruments_found))

# Function to extract rainfall metrics using spaCy
def extract_rainfall_metrics(text):
    doc = nlp(text)
    metrics_found = []
    for sentence in doc.sents:
        if 'rainfall' in sentence.text.lower():
            # Extract noun chunks containing 'rainfall'
            for chunk in sentence.noun_chunks:
                if 'rainfall' in chunk.text.lower():
                    metrics_found.append(chunk.text.strip())
            # Look for adjectives and modifiers
            for token in sentence:
                if token.text.lower() == 'rainfall':
                    modifiers = [child.text for child in token.children if child.dep_ in ('amod', 'compound')]
                    if modifiers:
                        phrase = ' '.join(modifiers + [token.text])
                        metrics_found.append(phrase.strip())
            # Include the sentence for context
            metrics_found.append(sentence.text.strip())
    return '; '.join(set(metrics_found))

# Function to extract how rainfall is used in regressions
def extract_rainfall_usage(text):
    doc = nlp(text)
    usage_sentences = []
    for sentence in doc.sents:
        if 'rainfall' in sentence.text.lower() and any(
            word in sentence.text.lower() for word in [
                'regression', 'instrument', 'iv', 'dependent variable',
                'independent variable', 'used as', 'exogenous', 'endogenous'
            ]
        ):
            usage_sentences.append(sentence.text.strip())
    return ' '.join(usage_sentences)

# Function to extract exogenous independent variables
def extract_exogenous_variables(text):
    exogenous_vars = re.findall(r'exogenous variables? (are|is|include) ([^.;]+)', text, re.IGNORECASE)
    return ', '.join([var[1] for var in exogenous_vars])

# Function to extract dependent variables
def extract_dependent_variables(text):
    dependent_vars = re.findall(r'dependent variables? (are|is|include) ([^.;]+)', text, re.IGNORECASE)
    return ', '.join([var[1] for var in dependent_vars])

# Function to extract data sources
def extract_data_sources(text):
    data_sources = [
        'NASA', 'NOAA', 'USGS', 'European Space Agency', 'satellite data',
        'remote sensing', 'meteorological organization', 'Climate Prediction Center',
        'National Meteorological Agency'
    ]
    sources_found = []
    for source in data_sources:
        if re.search(r'\b' + re.escape(source) + r'\b', text, re.IGNORECASE):
            sources_found.append(source)
    return ', '.join(set(sources_found))

# Process each PDF file
for pdf_file in pdf_files:
    print(f"Processing {pdf_file}...")
    text = extract_text(pdf_file)

    # Extract required information
    title = extract_title(text) or ''
    doi = extract_doi(text) or ''
    instruments = extract_instrumental_variables(text) or ''
    rainfall_metric = ''
    rainfall_usage = ''
    data_source = ''
    if instruments and ('rainfall' in instruments.lower() or 'weather' in instruments.lower()):
        rainfall_metric = extract_rainfall_metrics(text)
        rainfall_usage = extract_rainfall_usage(text)
        data_source = extract_data_sources(text)
    exogenous_vars = extract_exogenous_variables(text) or ''
    dependent_vars = extract_dependent_variables(text) or ''

    # Append the data
    data.append({
        'Paper Title': title,
        'DOI': doi,
        'Instrumental Variable Used': instruments,
        'Rainfall Metric Used': rainfall_metric,
        'Rainfall Usage in Regression': rainfall_usage,
        'Exogenous Independent Variables': exogenous_vars,
        'Dependent Variables': dependent_vars,
        'Source of Rainfall Data': data_source  # Ensure this key is always included
    })

# Create a DataFrame
df = pd.DataFrame(data)

# Verify columns
print("DataFrame Columns:", df.columns)

# Adjust variable lengths
max_length_title = 2000
max_length_other = 500
max_length_usage = 5000  # Increase length for usage sentences

# Add variables to the Stata dataset
Data.addVarStr("Paper_Title", max_length_title)
Data.addVarStr("DOI", 100)
Data.addVarStr("Instrumental_Variable_Used", max_length_other)
Data.addVarStr("Rainfall_Metric_Used", max_length_other)
Data.addVarStr("Rainfall_Usage_in_Regression", max_length_usage)
Data.addVarStr("Exogenous_Independent_Variables", max_length_other)
Data.addVarStr("Dependent_Variables", max_length_other)
Data.addVarStr("Source_of_Rainfall_Data", max_length_other)

# Set the number of observations
Data.setObsTotal(len(df))

# Store data in the Stata dataset
Data.store("Paper_Title", None, df['Paper Title'])
Data.store("DOI", None, df['DOI'])
Data.store("Instrumental_Variable_Used", None, df['Instrumental Variable Used'])
Data.store("Rainfall_Metric_Used", None, df['Rainfall Metric Used'])
Data.store("Rainfall_Usage_in_Regression", None, df['Rainfall Usage in Regression'])
Data.store("Exogenous_Independent_Variables", None, df['Exogenous Independent Variables'])
Data.store("Dependent_Variables", None, df['Dependent Variables'])
Data.store("Source_of_Rainfall_Data", None, df['Source of Rainfall Data'])

# Set the output path as a Stata macro
output_csv = os.path.join(folder_path, 'nlp_trial.csv')
Macro.setLocal('output_path', output_csv)

print(f"Data has been processed. CSV file will be saved to: {output_csv}")

end

export delimited using "`output_path'", replace
* **********************************************************************
* 2 - using a large training set to test output consistency (n=100)
*key= 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
* **********************************************************************

python
import os
import PyPDF2
from openai import OpenAI

# Initialize the OpenAI client
client = OpenAI(api_key='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')

# Path to the folder containing the PDFs
pdf_folder = '/Users/kieran/Library/CloudStorage/OneDrive-UniversityofArizona/weather_iv_lit/training/training_small'

# Function to extract text from PDF
def extract_text_from_pdf(pdf_path):
    text = ''
    with open(pdf_path, 'rb') as f:
        reader = PyPDF2.PdfReader(f)
        for page_num in range(len(reader.pages)):
            page = reader.pages[page_num]
            text += page.extract_text()
    return text

# Function to split text into paragraphs
def split_into_paragraphs(text):
    text = text.replace('\n\n', '\n')
    paragraphs = text.split('\n')
    return [para.strip() for para in paragraphs if para.strip()]

# Function to check if paragraph contains information of interest
def analyze_paragraph(paragraph):
    prompt = f"""You are an assistant that extracts specific information from academic papers.

Given the following paragraph:

\"\"\"
{paragraph}
\"\"\"

Answer the following questions:

1. Does this paragraph mention the specific instrumental variable used and how it was quantified in the regression? If yes, provide the details.
2. If the instrumental variable used was rainfall, does the paragraph mention the specific source of the data? If yes, provide the details.
3. Does this paragraph mention the specific explanatory/independent variable that was instrumented for? If yes, provide the details.
4. Does this paragraph mention the outcome/dependent variable of interest? If yes, provide the details.

If the paragraph does not contain the information, just reply 'No'."""

    response = client.chat.completions.create(
        model="gpt-4o-mini",  # or another appropriate model
        messages=[
            {"role": "system", "content": "You are a helpful assistant."},
            {"role": "user", "content": prompt}
        ],
        max_tokens=500,
        temperature=0
    )
    answer = response.choices[0].message.content.strip()
    return answer

# Keywords to filter paragraphs
keywords = [
    'instrumental variable', 'IV', 'regression', 'rainfall',
    'dependent variable', 'independent variable', 'explanatory variable',
    'outcome variable', 'instrumented'
]

# Main script
for filename in os.listdir(pdf_folder):
    if filename.endswith('.pdf'):
        pdf_path = os.path.join(pdf_folder, filename)
        print(f"Processing {filename}...")
        text = extract_text_from_pdf(pdf_path)
        paragraphs = split_into_paragraphs(text)
        for paragraph in paragraphs:
            if any(keyword.lower() in paragraph.lower() for keyword in keywords):
                result = analyze_paragraph(paragraph)
                if 'No' not in result:
                    print(f"Paragraph:\n{paragraph}\n")
                    print(f"Analysis:\n{result}\n")
end

*** with limits
python
import os
import pdfplumber
import openai
import time
import re
import pandas as pd
import stata_setup

# Configure stata_setup
stata_setup.config('/Applications/Stata/StataSE.app/Contents/MacOS/stata-se', 'se')  # Update this path for your Stata installation
from pystata import stata

def extract_relevant_sections_from_text(full_text):
    """
    Extracts only the 'Methods' and 'Data' sections (and their synonyms) from the full text.
    """
    section_titles = [
        'Methods', 'Methodology', 'Materials and Methods', 'Data', 'Data and Methods',
        'Experimental', 'Experimental Procedures', 'Study Area and Data', 'Data Collection', 'Materials'
    ]
    section_patterns = [re.compile(r'^.*\b' + re.escape(title) + r'\b.*$', re.IGNORECASE) for title in section_titles]
    lines = full_text.split('\n')
    relevant_text = ''
    recording = False
    current_section = ''

    for i, line in enumerate(lines):
        if any(pattern.match(line.strip()) for pattern in section_patterns):
            if recording:
                relevant_text += f"\n\n{current_section}:\n{relevant_text.strip()}\n\n"
                relevant_text = ''
            recording = True
            current_section = line.strip()
            print(f"Found section start: {current_section}")
            continue
        if recording and re.match(r'^\s*[A-Z][A-Za-z0-9\s]{0,50}$', line.strip()):
            print(f"Found section end: {line.strip()}")
            relevant_text += f"\n\n{current_section}:\n{relevant_text.strip()}\n\n"
            recording = False
            current_section = ''
        if recording:
            relevant_text += line + '\n'

    if recording and current_section:
        relevant_text += f"\n\n{current_section}:\n{relevant_text.strip()}\n\n"

    return relevant_text.strip()

def extract_text_from_pdf(pdf_file_path):
    """Extracts text from the entire PDF file and then filters for relevant sections."""
    full_text = ""
    try:
        with pdfplumber.open(pdf_file_path) as pdf:
            for page in pdf.pages:
                text = page.extract_text()
                if text:
                    full_text += text + "\n"
        relevant_text = extract_relevant_sections_from_text(full_text)
        print(f"Extracted Relevant Text from {pdf_file_path}:\n{relevant_text[:500]}\n{'-'*80}")
        return relevant_text
    except Exception as e:
        print(f"An error occurred while extracting text from {pdf_file_path}: {e}")
        return ""

def get_paper_info(text, messages):
    openai.api_key = "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"

    messages.append({
        "role": "user",
        "content": (
            "Please extract the following details from the text, providing as much detail as possible:\n\n"
            "- **Paper title**: Extracted from the title page.\n"
            "- **DOI**: If available, extracted from the text.\n"
            "- **Instrumental variable used**: Indicate 'Yes' if any instrumental variables are used in the paper, 'No' otherwise.\n"
            "- **Instrumental variable rainfall**: Indicate 'Yes' if rainfall is used as an instrumental variable, 'No' otherwise.\n"
            "- **Rainfall metric**: If rainfall is used as an instrumental variable, provide a concise description of the rainfall metric used.\n"
            "- **Rainfall data source**: If rainfall is used as an instrumental variable, find the specific source of rainfall data.\n"
            "- **Explanatory variable(s)**: Provide the explanatory variable or state 'N/A'.\n"
            "- **Outcome variable(s)**: Provide the outcome variable or state 'N/A'.\n"
            "- **Control variable(s)**: Provide a list of variables that the authors controlled for or state 'N/A'.\n\n"
            "Important:\n"
            "- If rainfall is mentioned but not used as an instrumental variable, 'Instrumental variable rainfall' should be 'No', and 'Rainfall metric' and 'Rainfall data source' should be 'N/A'.\n"
            "- Provide accurate 'Yes' or 'No' answers based on the content of the paper.\n\n"
            "Format your response exactly as in the examples, with each field on a new line.\n\n"
            "Text:\n" + text
        ),
    })

    messages = messages[-100:]

    try:
        client = openai.OpenAI(api_key=openai.api_key)
        response = client.chat.completions.create(
            model="gpt-4o-mini",  
            messages=messages,
            max_tokens=1500,
            n=1,
            temperature=0
        )

        assistant_reply = response.choices[0].message.content.strip()
        messages.append({"role": "assistant", "content": assistant_reply})
        return assistant_reply, messages
    except openai.RateLimitError:
        print("Rate limit exceeded. Waiting for 60 seconds.")
        time.sleep(60)
        return get_paper_info(text, messages)
    except Exception as e:
        print(f"An error occurred during OpenAI API call: {e}")
        return None, messages

def parse_paper_info(info):
    details = {
        "paper_title": "N/A",
        "doi": "N/A",
        "instrumental_variable_used": "N/A",
        "instrumental_variable_rainfall": "N/A",
        "rainfall_metric": "N/A",
        "rainfall_data_source": "N/A",
        "explanatory_variables": "N/A",
        "outcome_variables": "N/A",
        "control_variables": "N/A"
    }

    if not info:
        return details

    lines = info.strip().split("\n")
    for line in lines:
        if ":" in line:
            key, value = line.split(":", 1)
            key = key.strip().lower()
            value = value.strip()
            if "paper title" in key:
                details["paper_title"] = value
            elif "doi" in key:
                details["doi"] = value
            elif "instrumental variable used" in key:
                details["instrumental_variable_used"] = value
            elif "instrumental variable rainfall" in key:
                details["instrumental_variable_rainfall"] = value
            elif "rainfall metric" in key:
                details["rainfall_metric"] = value
            elif "rainfall data source" in key:
                details["rainfall_data_source"] = value
            elif "explanatory variable" in key:
                details["explanatory_variables"] = value
            elif "outcome variable" in key:
                details["outcome_variables"] = value
            elif "control variable" in key:
                details["control_variables"] = value

    return details

def process_pdfs_in_directory(directory):
    """Processes all PDFs in the given directory."""
    results = []
    messages = [
        {"role": "system", "content": "You are an AI assistant that extracts specific details from academic papers. Improve your extraction based on previous interactions."}
    ]

    for filename in os.listdir(directory):
        if filename.endswith('.pdf'):
            print(f"Processing file: {filename}")
            pdf_file_path = os.path.join(directory, filename)
            text = extract_text_from_pdf(pdf_file_path)
            if not text:
                print(f"No relevant text extracted from {filename}, skipping.")
                continue
            paper_info, messages = get_paper_info(text, messages)
            parsed_info = parse_paper_info(paper_info)
            parsed_info["file_name"] = filename
            results.append(parsed_info)

    return results

def save_results_to_stata(results):
    """Saves the extracted results to Stata using PyStata."""
    df = pd.DataFrame(results)
    
    # Transfer the DataFrame to Stata
    stata.pdataframe_to_data(df, force=True)
    
    # Use Stata commands to manipulate the data
    stata.run('describe')
    stata.run('list in 1/5')  # List the first 5 observations
    
    # Save the dataset in Stata format
    stata.run('save extracted_results, replace')
    print("Results saved to Stata dataset 'extracted_results.dta'.")

if __name__ == "__main__":
    pdf_directory = '/Users/kieran/Library/CloudStorage/OneDrive-UniversityofArizona/weather_iv_lit/training/training_large'
    results = process_pdfs_in_directory(pdf_directory)
    save_results_to_stata(results)
end
* **********************************************************************
* 3 - using full training set to test output consistency (n=)
* **********************************************************************

python
import os
import csv
import requests
import logging
import fitz  # PyMuPDF
import time
from openai import OpenAI

# Set up logging
logging.basicConfig(level=logging.DEBUG, format='%(asctime)s - %(levelname)s - %(message)s')

# Set your OpenAI API key
client = OpenAI(api_key='KEY')

# Directory containing the PDF files
pdf_dir = r'/Users/kieran/Library/CloudStorage/OneDrive-UniversityofArizona/weather_and_agriculture/output/metric_paper/literature/training_all'

# Output CSV file path
csv_output_path = os.path.join(pdf_dir, 'PDF_Analysis_all.csv')

# List of rainfall measurement methods and additional keywords
rainfall_methods = [
    "total rainfall", "deviations in total rainfall", "scaled deviations in total rainfall",
    "mean total rainfall", "total monthly rainfall", "mean monthly rainfall", "rainfall months",
    "daily rainfall", "rainfall days", "no rainfall days", "log of rainfall", "rainfall index",
    "rainfall", "deviation", "average", "seasonal", "shocks", "average annual precipitation"
]

# List of keywords to identify instrumental variables
iv_keywords = ["instrument", "instrumental variable", "iv"]

def search_doi(title, authors=None):
    base_url = "https://api.crossref.org/works"
    headers = {
        "User-Agent": "MyApp/1.0 (mailto:your_email@example.com)"
    }
    query = title
    if authors:
        query += ' ' + ' '.join(authors)

    params = {
        "query": query,
        "rows": 1
    }
    
    response = requests.get(base_url, headers=headers, params=params)
    
    if response.status_code == 200:
        data = response.json()
        if data['message']['items']:
            return data['message']['items'][0].get('DOI', None)
    else:
        logging.error(f"Error searching DOI: {response.status_code} {response.text}")
    
    return None

def extract_text_from_pdf(pdf_path):
    try:
        text = ""
        doc = fitz.open(pdf_path)
        for page in doc:
            text += page.get_text()
        logging.debug(f"Extracted text from {pdf_path}: {text[:2000]}...")  # Log first 500 characters of extracted text
        return text
    except Exception as e:
        logging.error(f"Error extracting text from {pdf_path}: {str(e)}")
        return None

def find_rainfall_method(text):
    for method in rainfall_methods:
        if method in text.lower():
            return method
    return "N/A"

def contains_iv_keywords(text):
    return any(keyword in text.lower() for keyword in iv_keywords)

def extract_paper_info(pdf_path):
    try:
        logging.info(f"Processing {pdf_path}")
        text = extract_text_from_pdf(pdf_path)

        if not text:
            logging.warning(f"No text extracted from {pdf_path}. Skipping.")
            return None

        # Extract title
        title = extract_with_retries(
            lambda: client.chat.completions.create(
                model="gpt-4-turbo",
                temperature=0,
                messages=[
                    {"role": "system", "content": "You are a helpful assistant that extracts titles from academic papers. Provide only the title, without any introductory phrases."},
                    {"role": "user", "content": f"Extract and provide only the title from this text of an academic paper's first page, without any prefixes or explanations: {text[:1000]}"}
                ]
            ).choices[0].message.content.strip(),
            pdf_path,
            "title"
        )
        
        logging.info(f"Extracted title: {title}")

        # Search for DOI using CrossRef API
        doi = search_doi(title)
        if not doi:
            logging.warning(f"No DOI found for title: {title}")

        # Check for IV-related keywords
        iv_used = extract_with_retries(
            lambda: client.chat.completions.create(
                model="gpt-4-turbo",
                temperature=0,
                messages=[
                    {"role": "system", "content": "You are an expert in identifying instrumental variable (IV) usage in academic papers."},
                    {"role": "user", "content": f"Does this paper use instrumental variables (IV) in its analysis? Respond with only 'Yes' or 'No': {text[:4000]}"}
                ]
            ).choices[0].message.content.strip().lower(),
            pdf_path,
            "IV usage"
        )
        
        logging.info(f"IV usage detected: {iv_used}")

        explanatory_details = {
            "Explanatory variable": "N/A",
            "Instrumental variable": "N/A",
            "Dependent variable": "N/A",
            "Control variables": "N/A"
        }

        rainfall_as_iv = "no"
        if iv_used == 'yes':
            # Extract IV details
            explanatory_details_text = extract_with_retries(
                lambda: client.chat.completions.create(
                    model="gpt-4-turbo",
                    temperature=0,
                    messages=[
                        {"role": "system", "content": "You are an expert in identifying variables in academic papers."},
                        {"role": "user", "content": f"Identify the following in the paper in 8 words or less: 1) Explanatory variable, 2) Instrumental variable, 3) Dependent variable, 4) Control variables. Provide each in one line with the label. Provide short and concise descriptions only. Read entire PDF and be sure to extract what metric or thing was used as the instrumental variable or other variables. Explanatory variable:, Instrumental variable:, Dependent variable:, Control variables:. If any of these variables are not explicitly mentioned, please infer them from the context: {text[:6000]}"}
                    ]
                ).choices[0].message.content.strip().split('\n'),
                pdf_path,
                "explanatory details"
            )

            for detail in explanatory_details_text:
                if detail.startswith("Explanatory variable:"):
                    explanatory_details["Explanatory variable"] = detail.replace("Explanatory variable:", "").strip()
                elif detail.startswith("Instrumental variable:"):
                    explanatory_details["Instrumental variable"] = detail.replace("Instrumental variable:", "").strip()
                elif detail.startswith("Dependent variable:"):
                    explanatory_details["Dependent variable"] = detail.replace("Dependent variable:", "").strip()
                elif detail.startswith("Control variables:"):
                    explanatory_details["Control variables"] = detail.replace("Control variables:", "").strip()

            # Extract the specific rainfall metric
            if any(method in explanatory_details["Instrumental variable"].lower() for method in rainfall_methods):
                specific_rainfall_metric = extract_with_retries(
                    lambda: client.chat.completions.create(
                        model="gpt-4-turbo",
                        temperature=0,
                        messages=[
                            {"role": "system", "content": "You are an expert in identifying specific metrics used for rainfall in academic papers that use instrumental variables."},
                            {"role": "user", "content": f"Read the entire PDF and tell me what the rainfall metric or measurement is that the authors used as an instrumental variable. Many of these papers use rainfall data as an instrumental variable, but how are they measuring it, or what exactly do they mean by rainfall data? am looking for something more specific than just rainfall, like deviations in total rainfall, year-over-year rainfall variation. Only output the name of the metric without any additional words or sentences in less than or equal to 8 words. THe metric used will never just be 'rainfall', there will always be some method by which they measure it like 'deviations in total rainfall' or 'ln(rain)'. Please read the ENTIRE PDF and of the multiple mentions of rainfall, deduce which one includes the actual metric by which it is measured. Examples of desired output: deviations in total rainfall, year-over-year rainfall variation. Sometimes the specific metric used by researchers is stated later in the paper like in the methods or discussion section, so please make sure to read them thoroughly to find how the authors accounted for rainfall in each paper. : {text[:6000]}"}
                        ]
                    ).choices[0].message.content.strip(),
                    pdf_path,
                    "specific rainfall metric"
                )
                
                # Verify the specific rainfall metric is not a general term
                if any(method in specific_rainfall_metric.lower() for method in rainfall_methods):
                    explanatory_details["Instrumental variable"] = specific_rainfall_metric
                else:
                    explanatory_details["Instrumental variable"] = "N/A"

                rainfall_as_iv = "yes"

        else:
            # Extract non-IV related variables
            explanatory_details_text = extract_with_retries(
                lambda: client.chat.completions.create(
                    model="gpt-4-turbo",
                    temperature=0,
                    messages=[
                        {"role": "system", "content": "You are an expert in identifying variables in academic papers."},
                        {"role": "user", "content": f"Identify the following in the paper in 8 words or less: 1) Explanatory variable, 2) Dependent variable, 3) Control variables. Provide each in one line with the label. Use terms like 'independent variable', 'predictor', or 'x' synonymously with 'explanatory variable'. Provide short and concise descriptions only. If any of these variables are not explicitly mentioned, please infer them from the context: {text[:6000]}"}
                    ]
                ).choices[0].message.content.strip().split('\n'),
                pdf_path,
                "explanatory details without IV"
            )

            for detail in explanatory_details_text:
                if detail.startswith("Explanatory variable:"):
                    explanatory_details["Explanatory variable"] = detail.replace("Explanatory variable:", "").strip()
                elif detail.startswith("Dependent variable:"):
                    explanatory_details["Dependent variable"] = detail.replace("Dependent variable:", "").strip()
                elif detail.startswith("Control variables:"):
                    explanatory_details["Control variables"] = detail.replace("Control variables:", "").strip()

        return title, doi, iv_used, rainfall_as_iv, explanatory_details["Explanatory variable"], explanatory_details["Instrumental variable"], explanatory_details["Dependent variable"], explanatory_details["Control variables"]

    except Exception as e:
        logging.error(f"Error processing {pdf_path}: {str(e)}")
        return None

def extract_with_retries(func, pdf_path, description, retries=5, delay=2):
    for i in range(retries):
        try:
            result = func()
            if result:
                return result
        except Exception as e:
            logging.error(f"Error extracting {description} on attempt {i + 1} for {pdf_path}: {str(e)}")
            time.sleep(delay)
    logging.error(f"Failed to extract {description} after {retries} attempts for {pdf_path}")
    return "N/A"

def main():
    if not os.path.exists(pdf_dir):
        logging.error(f"Directory {pdf_dir} does not exist.")
        return

    pdf_files = [f for f in os.listdir(pdf_dir) if f.lower().endswith('.pdf')]

    if not pdf_files:
        logging.error("No PDF files found.")
        return

    logging.info(f"Found {len(pdf_files)} PDF files")

    with open(csv_output_path, 'w', newline='', encoding='utf-8') as csvfile:
        writer = csv.writer(csvfile)
        writer.writerow(['Filename', 'Title', 'DOI', 'IV Used', 'Rainfall as IV', 'Explanatory Variable', 'Instrumental Variable', 'Dependent Variable', 'Control Variables'])

        for pdf_file in pdf_files:
            pdf_path = os.path.join(pdf_dir, pdf_file)
            result = extract_paper_info(pdf_path)
            if result is not None:
                writer.writerow([pdf_file] + list(result))
                logging.info(f"Processed: {pdf_file}")
            else:
                writer.writerow([pdf_file] + ["N/A"] * 8)  # Ensure row is added even if data extraction fails
                logging.info(f"Skipping: {pdf_file}")

    logging.info(f"CSV file '{csv_output_path}' has been created.")

if __name__ == "__main__":
    main()
end

* **********************************************************************
* 4 - text extraction script
* **********************************************************************
python
from transformers import pipeline
end 

python
import os
import sys
from glob import glob
import logging
from transformers import pipeline

# Initialize logging
logging.basicConfig(level=logging.INFO)

# Define the directory containing the PDFs
pdf_dir = '/Users/kieran/Library/CloudStorage/OneDrive-UniversityofArizona/weather_iv_lit/training/training_small'  # Replace with your actual path

# Define the queries and their corresponding labels
queries = {
    "instrumental_variable": "Find paragraphs that specify the instrumental variable used and how it was quantified in the regression.",
    "rainfall_data_source": "Find paragraphs that mention the specific source of the data if the instrumental variable used was rainfall.",
    "explanatory_variable": "Find paragraphs that specify the explanatory/independent variable instrumented for.",
    "dependent_variable": "Find paragraphs that specify the outcome/dependent variable of interest."
}

# Labels for classification
labels = list(queries.keys())

# Initialize the transformer model for zero-shot classification with error handling
try:
    classifier = pipeline("zero-shot-classification", model="facebook/bart-large-mnli")
    logging.info("Classifier initialized successfully.")
except Exception as e:
    logging.error(f"Error initializing the classifier: {e}")
    sys.exit(1)

# Adjusted text processing function
MAX_LENGTH = 512  # Adjust this as needed

def process_pdf(pdf_file, classifier, labels):
    from PyPDF2 import PdfReader
    logging.info(f"Processing document: {os.path.basename(pdf_file)}")
    reader = PdfReader(pdf_file)
    text = ""
    for page in reader.pages:
        page_text = page.extract_text()
        if page_text:
            text += page_text + "\n"

    # Check if any text was extracted
    if not text.strip():
        logging.warning(f"No text extracted from {os.path.basename(pdf_file)}.")
        return {}

    # Split the text into paragraphs
    paragraphs = text.split('\n\n')
    results = {key: [] for key in labels}
    for paragraph in paragraphs:
        if len(paragraph.strip()) == 0:
            continue
        # Split long paragraphs into smaller chunks
        chunks = [paragraph[i:i+MAX_LENGTH] for i in range(0, len(paragraph), MAX_LENGTH)]
        for chunk in chunks:
            try:
                classification = classifier(chunk, candidate_labels=labels, multi_label=True)
                for i, label in enumerate(classification['labels']):
                    score = classification['scores'][i]
                    if score > 0.5:
                        results[label].append({
                            'document': os.path.basename(pdf_file),
                            'paragraph': chunk.strip(),
                            'score': score
                        })
            except Exception as e:
                logging.error(f"Error during classification: {e}")
                continue
    return results

# Prepare a dictionary to store the results
results = {key: [] for key in queries.keys()}

# Iterate over the PDF files
pdf_files = glob(os.path.join(pdf_dir, '*.pdf'))
for pdf_file in pdf_files:
    pdf_results = process_pdf(pdf_file, classifier, labels)
    for key, items in pdf_results.items():
        results[key].extend(items)

# Output the results
for key, paragraphs in results.items():
    print(f"\n=== Results for {key.replace('_', ' ').title()} ===")
    for item in paragraphs:
        print(f"Document: {item['document']}")
        print(f"Score: {item['score']:.2f}")
        print(f"Paragraph:\n{item['paragraph']}\n")
end

python
import os
from glob import glob
from PyPDF2 import PdfReader
import openai

# Set your OpenAI API key (ensure you keep your API key secure)
openai.api_key = os.getenv('OPENAI_API_KEY')

# Define the directory containing the PDFs
pdf_dir = 'path/to/pdf_folder'

# Define the queries
queries = {
    "instrumental_variable": "Extract the paragraph that specifies the instrumental variable used and how it was quantified in the regression.",
    "rainfall_data_source": "Extract the paragraph that mentions the specific source of the data if the instrumental variable used was rainfall.",
    "explanatory_variable": "Extract the paragraph that specifies the explanatory/independent variable instrumented for.",
    "dependent_variable": "Extract the paragraph that specifies the outcome/dependent variable of interest."
}

# Prepare a dictionary to store the results
results = {key: [] for key in queries.keys()}

# Iterate over the PDF files
pdf_files = glob(os.path.join(pdf_dir, '*.pdf'))
for pdf_file in pdf_files:
    print(f"Processing document: {os.path.basename(pdf_file)}")
    reader = PdfReader(pdf_file)
    text = ""
    for page in reader.pages:
        text += page.extract_text() + "\n"

    # Split the text into paragraphs
    paragraphs = text.split('\n\n')
    for paragraph in paragraphs:
        if len(paragraph.strip()) == 0:
            continue
        for key, prompt in queries.items():
            # Prepare the prompt for the API
            full_prompt = f"{prompt}\n\nParagraph:\n{paragraph}\n\nDoes this paragraph contain the required information? Answer 'Yes' or 'No'."
            response = openai.Completion.create(
                engine="text-davinci-003",
                prompt=full_prompt,
                max_tokens=5,
                temperature=0,
                n=1,
                stop=None
            )
            answer = response.choices[0].text.strip().lower()
            if answer == 'yes':
                results[key].append({
                    'document': os.path.basename(pdf_file),
                    'paragraph': paragraph.strip()
                })

# Output the results
for key, paragraphs in results.items():
    print(f"\n=== Results for {key.replace('_', ' ').title()} ===")
    for item in paragraphs:
        print(f"Document: {item['document']}")
        print(f"Paragraph:\n{item['paragraph']}\n")
end

*** end is confused
python:
python:
import os
import re
import csv
import logging
import spacy
from pdfminer.high_level import extract_text
from pdf2image import convert_from_path
import pytesseract
from spacy.matcher import Matcher

# Configure logging
logging.basicConfig(
    filename='pdf_processing.log',
    level=logging.INFO,
    format='%(asctime)s:%(levelname)s:%(message)s'
)

# Define the folder containing the PDFs
PDF_FOLDER = '/Users/kieran/Library/CloudStorage/OneDrive-UniversityofArizona/weather_iv_lit/training/training_small'  # Replace with your folder path

# Define patterns to exclude (like tables, figures, references)
exclude_patterns = [
    r'\btable\b',
    r'\bfigure\b',
    r'\breferences\b',
    r'\bappendix\b',
    r'\bappendices\b',
    r'\btabular\b',
    r'\bsee figure\b',
    r'\bsee table\b',
    # Add more as needed
]

compiled_exclude_patterns = [re.compile(pattern, re.IGNORECASE) for pattern in exclude_patterns]

def contains_exclude(paragraph):
    """Check if the paragraph should be excluded based on exclude patterns."""
    return any(pattern.search(paragraph) for pattern in compiled_exclude_patterns)

def extract_text_with_ocr(pdf_path):
    """Extract text from a PDF using OCR."""
    try:
        images = convert_from_path(pdf_path)
        text = ""
        for image in images:
            text += pytesseract.image_to_string(image)
        return text
    except Exception as e:
        logging.error(f"OCR Error reading {pdf_path}: {e}")
        return ""

def extract_sections(text, sections_of_interest):
    """
    Extract specified sections from the text.
    """
    # More flexible regex pattern for section headers
    section_pattern = re.compile(
        r'(?P<header>^(?:\d+\.?\s*)?(?:' + '|'.join(sections_of_interest) + r').*?(?:\n|$))',
        re.IGNORECASE | re.MULTILINE
    )

    # Find all section headers
    sections = list(section_pattern.finditer(text))
    extracted_sections = {}

    for i, match in enumerate(sections):
        section_title = match.group('header').strip()
        start = match.end()
        end = sections[i+1].start() if i+1 < len(sections) else None
        section_content = text[start:end].strip()
        extracted_sections[section_title] = section_content

    return extracted_sections

def process_pdf(pdf_path, nlp, matcher):
    """Extract text from a PDF and return labeled matching paragraphs."""
    try:
        text = extract_text(pdf_path)
        if not text.strip():
            logging.warning(f"No text extracted from {pdf_path}. Trying OCR.")
            text = extract_text_with_ocr(pdf_path)
        
        if not text.strip():
            logging.error(f"Failed to extract text from {pdf_path} even with OCR.")
            return "N/A"
        
        logging.info(f"Successfully extracted {len(text)} characters from {pdf_path}")
        
        # Extract only methods and data sections
        sections_of_interest = ['methods', 'data', 'methodology', 'data collection']
        extracted_sections = extract_sections(text, sections_of_interest)
        
        if not extracted_sections:
            logging.warning(f"No relevant sections found in {pdf_path}")
            return "N/A"
        
        # Combine the extracted sections
        combined_text = ' '.join(extracted_sections.values())
        
        # Split text into paragraphs based on double newlines or indentation
        paragraphs = re.split(r'\n\s*\n', combined_text)
        
        # Initialize dictionary to hold the best matching paragraph per category
        results = {
            "Rainfall Metric": {"para": None, "score": 0},
            "Endogenous Variable": {"para": None, "score": 0},
            "Outcome Variable": {"para": None, "score": 0},
            "Data Source": {"para": None, "score": 0}
        }
        
        for para in paragraphs:
            # Clean up the paragraph by removing excessive whitespace
            clean_para = ' '.join(para.split())
            
            # Skip excluded paragraphs
            if contains_exclude(clean_para):
                continue
            
            doc = nlp(clean_para)
            matches = matcher(doc)
            
            for match_id, start, end in matches:
                span = doc[start:end]
                category = nlp.vocab.strings[match_id]
                
                # Assign scores based on the number of matches
                if category == 'Rainfall_Metric':
                    score = 1  # You can enhance scoring logic here
                    if score > results["Rainfall Metric"]["score"]:
                        results["Rainfall Metric"]["para"] = clean_para
                        results["Rainfall Metric"]["score"] = score
                
                elif category == 'Endogenous_Variable':
                    score = 1
                    if score > results["Endogenous Variable"]["score"]:
                        results["Endogenous Variable"]["para"] = clean_para
                        results["Endogenous Variable"]["score"] = score
                
                elif category == 'Outcome_Variable':
                    score = 1
                    if score > results["Outcome Variable"]["score"]:
                        results["Outcome Variable"]["para"] = clean_para
                        results["Outcome Variable"]["score"] = score
                
                elif category == 'Data_Source':
                    score = 1
                    if score > results["Data Source"]["score"]:
                        results["Data Source"]["para"] = clean_para
                        results["Data Source"]["score"] = score
        
        # Prepare the final result list with labels
        final_results = []
        for category, info in results.items():
            if info["para"]:
                final_results.append((category, info["para"]))
        
        if final_results:
            return final_results
        else:
            return "N/A"
    except Exception as e:
        logging.error(f"Error processing {pdf_path}: {e}")
        return "N/A"

def main():
    # Load spaCy model
    try:
        nlp = spacy.load('en_core_web_sm')
    except OSError:
        print("Downloading 'en_core_web_sm' model for spaCy as it was not found...")
        from spacy.cli import download
        download('en_core_web_sm')
        nlp = spacy.load('en_core_web_sm')

    # Initialize spaCy Matcher
    matcher = Matcher(nlp.vocab)

    # Define patterns for each category using spaCy's token-based Matcher
    rainfall_patterns = [
        [{'LOWER': 'log'}, {'ORTH': '('}, {'LOWER': 'rainfall'}, {'ORTH': ')'}],
        [{'LOWER': 'log'}, {'LOWER': 'rainfall'}],
        [{'LOWER': 'monthly'}, {'LOWER': 'deviations'}, {'LOWER': 'in'}, {'LOWER': 'rainfall'}],
        [{'LOWER': 'rainfall'}],
        [{'LOWER': 'precipitation'}],
        [{'LOWER': 'weather'}, {'LOWER': 'metric'}],
        [{'LOWER': 'deviations'}, {'LOWER': 'in'}, {'LOWER': 'precipitation'}],
        [{'LOWER': 'rainfall'}, {'LOWER': 'variability'}],
        [{'LOWER': 'rainfall'}, {'LOWER': 'anomalies'}],
    ]

    endogenous_var_patterns = [
        [{'LOWER': 'endogenous'}, {'LOWER': 'variable'}],
        [{'LOWER': 'policy'}, {'LOWER': 'variable'}],
        [{'LOWER': 'investment'}, {'LOWER': 'level'}],
        [{'LOWER': 'economic'}, {'LOWER': 'growth'}],
        [{'LOWER': 'regulatory'}, {'LOWER': 'change'}],
    ]

    outcome_var_patterns = [
        [{'LOWER': 'y'},
        [{'LOWER': 'outcome'}],
        [{'LOWER': 'explained'},
        [{'LOWER': 'dependent variable'}, 
        [{'LOWER': 'dependent'}, {'LOWER': 'variable'}],
    ]

    source_patterns = [
        [{'LOWER': 'satellite'}, {'LOWER': 'data'}],
        [{'LOWER': 'government'}, {'LOWER': 'organization'}],
        [{'LOWER': 'noaa'}],
        [{'LOWER': 'nasa'}],
        [{'LOWER': 'local'}, {'LOWER': 'weather'}, {'LOWER': 'stations'}],
        [{'LOWER': 'remote'}, {'LOWER': 'sensing'}],
        [{'LOWER': 'meteorological'}, {'LOWER': 'agency'}],
    ]

    # Add patterns to the matcher with unique IDs
    matcher.add('Rainfall_Metric', rainfall_patterns)
    matcher.add('Endogenous_Variable', endogenous_var_patterns)
    matcher.add('Outcome_Variable', outcome_var_patterns)
    matcher.add('Data_Source', source_patterns)

    # Initialize results list for CSV output
    results = []
    
    # Iterate over all PDF files in the designated folder
    for filename in os.listdir(PDF_FOLDER):
        if filename.lower().endswith('.pdf'):
            pdf_path = os.path.join(PDF_FOLDER, filename)
            print(f"\nProcessing PDF: {filename}")
            result = process_pdf(pdf_path, nlp, matcher)
            
            if result == "N/A":
                print(f"No relevant information found in {filename}")
                results.append([filename, "N/A", "N/A"])
            else:
                print(f"Found {len(result)} matching paragraphs in {filename}")
                for label, para in result:
                    print(f"\n--- {label} ---\n{para[:100]}...\n")  # Print only first 100 chars
                    results.append([filename, label, para])
    
    # Write results to a CSV file
    with open('pdf_extraction_results.csv', 'w', newline='', encoding='utf-8') as csvfile:
        writer = csv.writer(csvfile)
        writer.writerow(['PDF Filename', 'Category', 'Content'])
        for row in results:
            writer.writerow(row)
    
    print("\nExtraction complete. Results saved to pdf_extraction_results.csv")

if __name__ == "__main__":
    main()
end

python
import sys
print(sys.executable)
end


end
