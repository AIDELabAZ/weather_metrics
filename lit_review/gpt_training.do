* Project: WB Weather - metric 
* Created on: June 2024
* Created by: kcd
* Last edited by: 3 July 2024
* Edited by: kcd on mac
* Stata v.18.0

* does
    * Imports pdfs and feeds them to GPT via API. Reads them and outputs a CSV with relevant information
* assumes
    * ChatGPT account
	* pip install openai pymupdf pandas openpyxl in terminal
	* 

* TO DO:
    * everything
	
* notes
	* as of now, the api key is deactivated after every push. each new session requires a newly generated api key until we can figure this out. this may also be an issue that is not resolvable and well have to leave a not for people to put in their own key or something. 

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
*/
* **********************************************************************
* 1 - api interface
* **********************************************************************

* troubleshooting

python
import os
import csv
import pandas as pd
from PyPDF2 import PdfReader
import requests
import logging
from openai import OpenAI

# Set up logging
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')

# Set your OpenAI API key
client = OpenAI(api_key='sk-proj-YvWMoI6yzYLDC3SRlsutT3BlbkFJTyIwCohWPRQj5F7LW0q5')

# Directory containing the PDF files
pdf_dir = r'/Users/kieran/Library/CloudStorage/OneDrive-UniversityofArizona/weather_and_agriculture/output/metric_paper/literature/training'

# Excel file containing DOIs
doi_excel_path = r'/Users/kieran/Library/CloudStorage/OneDrive-UniversityofArizona/weather_and_agriculture/output/metric_paper/literature/pdf_urls.xlsx'

# Output CSV file path
csv_output_path = os.path.join(pdf_dir, 'PDF_Analysis.csv')

# List of rainfall measurement methods and additional keywords
rainfall_methods = [
    "total rainfall", "deviations in total rainfall", "scaled deviations in total rainfall",
    "mean total rainfall", "total monthly rainfall", "mean monthly rainfall", "rainfall months",
    "daily rainfall", "rainfall days", "no rainfall days", "log of rainfall", "rainfall index",
    "rainfall"
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
        with open(pdf_path, 'rb') as file:
            reader = PdfReader(file)
            text = ""
            for page in reader.pages:
                page_text = page.extract_text()
                if page_text:
                    text += page_text
        
        if not text:
            logging.warning(f"No text extracted from {pdf_path}. Skipping.")
            return None
        
        if not contains_iv_keywords(text):
            logging.info(f"No IV keywords found in {pdf_path}. Skipping.")
            return None

        # Extract title
        title_response = client.chat.completions.create(
            model="gpt-3.5-turbo",
            messages=[
                {"role": "system", "content": "You are a helpful assistant that extracts titles from academic papers. Provide only the title, without any introductory phrases."},
                {"role": "user", "content": f"Extract and provide only the title from this text of an academic paper's first page, without any prefixes or explanations: {text[:1000]}"}
            ]
        )
        title = title_response.choices[0].message.content.strip()
        logging.info(f"Extracted title: {title}")

        # Search for DOI using CrossRef API
        doi = search_doi(title)
        if not doi:
            logging.warning(f"No DOI found for title: {title}")
            return None

        # Check for IV-related keywords
        iv_usage_response = client.chat.completions.create(
            model="gpt-3.5-turbo",
            messages=[
                {"role": "system", "content": "You are an expert in identifying instrumental variable (IV) usage in academic papers."},
                {"role": "user", "content": f"Does this paper use instrumental variables (IV) in its analysis? Respond with only 'Yes' or 'No': {text[:4000]}"}
            ]
        )
        iv_used = iv_usage_response.choices[0].message.content.strip().lower()
        logging.info(f"IV usage detected: {iv_used}")

        endogenous_variable = instrumental_variable = dependent_variable = control_variables = "N/A"

        if iv_used == 'yes':
            # Extract IV details
            iv_details_response = client.chat.completions.create(
                model="gpt-3.5-turbo",
                messages=[
                    {"role": "system", "content": "You are an expert in identifying variables in academic papers using instrumental variables."},
                    {"role": "user", "content": f"Identify the following in the paper: 1) Endogenous variable, 2) Instrumental variable, 3) Dependent variable, 4) Control variables. Provide each on a new line with the label: {text[:6000]}"}
                ]
            )
            iv_details = iv_details_response.choices[0].message.content.strip().split('\n')
            logging.info(f"Extracted IV details: {iv_details}")

            endogenous_variable = extract_detail(iv_details, "Endogenous variable:")
            instrumental_variable = extract_detail(iv_details, "Instrumental variable:")
            dependent_variable = extract_detail(iv_details, "Dependent variable:")
            control_variables = extract_detail(iv_details, "Control variables:")

            if any(method in instrumental_variable.lower() for method in rainfall_methods):
                return title, doi, iv_used, endogenous_variable, instrumental_variable, dependent_variable, control_variables
        
        return None
    except Exception as e:
        logging.error(f"Error processing {pdf_path}: {str(e)}")
        return None

def extract_detail(details, label):
    for detail in details:
        if detail.startswith(label):
            return detail.replace(label, "").strip()
    return "Not specified"

def main():
    if not os.path.exists(pdf_dir):
        logging.error(f"Directory {pdf_dir} does not exist.")
        return

    pdf_files = [f for f in os.listdir(pdf_dir) if f.lower().endswith('.pdf')]

    if not pdf_files:
        logging.error("No PDF files found.")
        return

    with open(csv_output_path, 'w', newline='', encoding='utf-8') as csvfile:
        writer = csv.writer(csvfile)
        writer.writerow(['Filename', 'Title', 'DOI', 'IV Used', 'Endogenous Variable', 'Instrumental Variable', 'Dependent Variable', 'Control Variables'])

        for pdf_file in pdf_files:
            pdf_path = os.path.join(pdf_dir, pdf_file)
            result = extract_paper_info(pdf_path)
            if result is not None:
                writer.writerow([pdf_file] + list(result))
                logging.info(f"Processed: {pdf_file}")
            else:
                logging.info(f"Skipping: {pdf_file}")

    logging.info(f"CSV file '{csv_output_path}' has been created.")

if __name__ == "__main__":
    main()

end


******
******

python
import os
import csv
import pandas as pd
from PyPDF2 import PdfReader
from openai import OpenAI

# Set your OpenAI API key
client = OpenAI(api_key='sk-proj-XPUdanKkVXogbfqVkAbUT3BlbkFJnrBjHZM5cqRiHXQUcIm7')

# Directory containing the PDF files
pdf_dir = r'/Users/kieran/Library/CloudStorage/OneDrive-UniversityofArizona/weather_and_agriculture/output/metric_paper/literature/training'

# Excel file containing DOIs
doi_excel_path = r'/Users/kieran/Library/CloudStorage/OneDrive-UniversityofArizona/weather_and_agriculture/output/metric_paper/literature/pdf_urls.xlsx'

# Output CSV file path
csv_output_path = os.path.join(pdf_dir, 'PDF_Analysis.csv')

def extract_dois_from_excel(excel_path):
    try:
        df = pd.read_excel(excel_path)
        if 'doi' in df.columns:
            return df['doi'].tolist()
        else:
            print("Error: The 'doi' column was not found in the Excel file.")
            return []
    except Exception as e:
        print(f"An error occurred while reading the Excel file: {str(e)}")
        return []

def extract_paper_info(pdf_path, doi):
    try:
        with open(pdf_path, 'rb') as file:
            reader = PdfReader(file)
            text = ""
            for page in reader.pages:
                text += page.extract_text()
        
        # Extract title
        title_response = client.chat.completions.create(
            model="gpt-3.5-turbo",
            messages=[
                {"role": "system", "content": "You are a helpful assistant that extracts titles from academic papers. Provide only the title, without any introductory phrases."},
                {"role": "user", "content": f"Extract and provide only the title from this text of an academic paper's first page, without any prefixes or explanations: {text[:1000]}"}
            ]
        )
        title = title_response.choices[0].message.content.strip()
        
        # Remove any remaining prefixes if present
        prefixes_to_remove = ["The title of the academic paper is", "The title is", "Title:"]
        for prefix in prefixes_to_remove:
            if title.lower().startswith(prefix.lower()):
                title = title[len(prefix):].strip()
        
        # Extract rainfall measurement method
        rainfall_response = client.chat.completions.create(
            model="gpt-3.5-turbo",
            messages=[
                {"role": "system", "content": "You are a helpful assistant that identifies rainfall measurement methods in academic papers. Respond with only the specific method, nothing else."},
                {"role": "user", "content": f"What is the specific rainfall measurement method used in this academic paper? Provide only the method in 1-3 words, such as 'daily rainfall' or 'monthly precipitation': {text[:4000]}"}
            ]
        )
        rainfall_measurement = rainfall_response.choices[0].message.content.strip()
        
        # Determine IV usage
        iv_usage_response = client.chat.completions.create(
            model="gpt-3.5-turbo",
            messages=[
                {"role": "system", "content": "You are an expert in identifying instrumental variable (IV) usage in academic papers."},
                {"role": "user", "content": f"Does this paper use instrumental variables (IV) in its analysis? Respond with only 'Yes' or 'No': {text[:4000]}"}
            ]
        )
        iv_used = iv_usage_response.choices[0].message.content.strip()
        
        if iv_used.lower() == 'yes':
            # Extract IV details
            iv_details_response = client.chat.completions.create(
                model="gpt-3.5-turbo",
                messages=[
                    {"role": "system", "content": "You are an expert in identifying variables in academic papers using instrumental variables."},
                    {"role": "user", "content": f"Identify the following in the paper: 1) Endogenous variable, 2) Instrumental variable, 3) Dependent variable, 4) Control variables. Provide each on a new line with the label: {text[:6000]}"}
                ]
            )
            iv_details = iv_details_response.choices[0].message.content.strip().split('\n')
            endogenous_variable = extract_detail(iv_details, "Endogenous variable:")
            instrumental_variable = extract_detail(iv_details, "Instrumental variable:")
            dependent_variable = extract_detail(iv_details, "Dependent variable:")
            control_variables = extract_detail(iv_details, "Control variables:")
        else:
            endogenous_variable = instrumental_variable = dependent_variable = control_variables = "N/A"
        
        return title, rainfall_measurement, doi, iv_used, endogenous_variable, instrumental_variable, dependent_variable, control_variables
    except Exception as e:
        return f"Error processing {pdf_path}: {str(e)}", "Error", doi, "Error", "Error", "Error", "Error", "Error"

def extract_detail(details, label):
    for detail in details:
        if detail.startswith(label):
            return detail.replace(label, "").strip()
    return "Not specified"

def main():
    if not os.path.exists(pdf_dir):
        print(f"Directory {pdf_dir} does not exist.")
        return

    pdf_files = [f for f in os.listdir(pdf_dir) if f.lower().endswith('.pdf')]

    if not pdf_files:
        print("No PDF files found.")
        return

    dois = extract_dois_from_excel(doi_excel_path)

    with open(csv_output_path, 'w', newline='', encoding='utf-8') as csvfile:
        writer = csv.writer(csvfile)
        writer.writerow(['Filename', 'Title', 'Rainfall Measurement Method', 'DOI', 'IV Used', 'Endogenous Variable', 'Instrumental Variable', 'Dependent Variable', 'Control Variables'])

        for pdf_file, doi in zip(pdf_files, dois):
            pdf_path = os.path.join(pdf_dir, pdf_file)
            title, rainfall_measurement, doi, iv_used, endogenous_variable, instrumental_variable, dependent_variable, control_variables = extract_paper_info(pdf_path, doi)
            writer.writerow([pdf_file, title, rainfall_measurement, doi, iv_used, endogenous_variable, instrumental_variable, dependent_variable, control_variables])
            print(f"Processed: {pdf_file}")

    print(f"CSV file '{csv_output_path}' has been created.")

if __name__ == "__main__":
    main()
end
* **********************************************************************
* 1 - get pdfs
* **********************************************************************

