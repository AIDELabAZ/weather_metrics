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

* troubleshooting training small

python
import os
import csv
import requests
import logging
import fitz  # PyMuPDF
from openai import OpenAI
import time

# Set up logging
logging.basicConfig(level=logging.DEBUG, format='%(asctime)s - %(levelname)s - %(message)s')

# Set your OpenAI API key
client = OpenAI(api_key='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')

# Directory containing the PDF files
pdf_dir = r'/Users/kieran/Library/CloudStorage/OneDrive-UniversityofArizona/weather_and_agriculture/output/metric_paper/literature/training'

# Output CSV file path
csv_output_path = os.path.join(pdf_dir, 'PDF_Analysis.csv')

# List of rainfall measurement methods and additional keywords
rainfall_methods = [
    "total rainfall", "deviations in total rainfall", "scaled deviations in total rainfall",
    "mean total rainfall", "total monthly rainfall", "mean monthly rainfall", "rainfall months",
    "daily rainfall", "rainfall days", "no rainfall days", "log of rainfall", "rainfall index",
    "rainfall", "deviation", "average", "seasonal", "shocks", "other"
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
        text = ""
        doc = fitz.open(pdf_path)
        for page in doc:
            text += page.get_text()

        logging.debug(f"Extracted text from {pdf_path}: {text[:500]}...")  # Log first 500 characters of extracted text

        if not text:
            logging.warning(f"No text extracted from {pdf_path}. Skipping.")
            return None

        # Extract title
        title = extract_with_retries(
            lambda: client.chat.completions.create(
                model="gpt-3.5-turbo",
                temperature=0,
                messages=[
                    {"role": "system", "content": "You are a helpful assistant that extracts titles from academic papers. Provide only the title, without any introductory phrases."},
                    {"role": "user", "content": f"Extract and provide only the title from this text of an academic paper's first page, without any prefixes or explanations: {text[:2000]}"}
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
                model="gpt-3.5-turbo",
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

        iv_details = {
            "Endogenous explanatory variable": "N/A",
            "Instrumental variable": "N/A",
            "Dependent variable": "N/A",
            "Control variables": "N/A"
        }

        rainfall_as_iv = "no"
        if iv_used == 'yes':
            # Extract IV details
            iv_details_text = extract_with_retries(
                lambda: client.chat.completions.create(
                    model="gpt-3.5-turbo",
                    temperature=0,
                    messages=[
                        {"role": "system", "content": "You are an expert in identifying variables in academic papers using instrumental variables."},
                        {"role": "user", "content": f"Identify the following in the paper: 1) Endogenous explanatory variable, 2) Instrumental variable, 3) Dependent variable, 4) Control variables. Provide each in one line with the label. Provide short and concise descriptions only. Endogenous explanatory variable:, Instrumental variable:, Dependent variable:, Control variables:. If any of these variables are not explicitly mentioned, please infer them from the context of the whole PDF: {text[:8000]}"}
                    ]
                ).choices[0].message.content.strip().split('\n'),
                pdf_path,
                "IV details"
            )

            for detail in iv_details_text:
                if detail.startswith("Endogenous explanatory variable:"):
                    iv_details["Endogenous explanatory variable"] = detail.replace("Endogenous explanatory variable:", "").strip()
                elif detail.startswith("Instrumental variable:"):
                    iv_details["Instrumental variable"] = detail.replace("Instrumental variable:", "").strip()
                elif detail.startswith("Dependent variable:"):
                    iv_details["Dependent variable"] = detail.replace("Dependent variable:", "").strip()
                elif detail.startswith("Control variables:"):
                    iv_details["Control variables"] = detail.replace("Control variables:", "").strip()

            # Extract the specific rainfall metric
            if any(method in iv_details["Instrumental variable"].lower() for method in rainfall_methods):
                specific_rainfall_metric = extract_with_retries(
                    lambda: client.chat.completions.create(
                        model="gpt-3.5-turbo",
                        temperature=0,
                        messages=[
                            {"role": "system", "content": "You are an expert in identifying specific metrics used for rainfall in academic papers."},
                            {"role": "user", "content": f"Extract the specific metric or variable used for rainfall as an instrumental variable from this paper. Provide only the specific metric or variable used for the instrumental variable if it involves rainfall, without any introductory phrases: {text[:8000]}"}
                        ]
                    ).choices[0].message.content.strip(),
                    pdf_path,
                    "specific rainfall metric"
                )
                
                # Verify the specific rainfall metric is not a general term
                if any(method in specific_rainfall_metric.lower() for method in rainfall_methods):
                    iv_details["Instrumental variable"] = specific_rainfall_metric.split(':')[-1].strip()
                else:
                    iv_details["Instrumental variable"] = "N/A"

                rainfall_as_iv = "yes"
        
        return title, doi, iv_used, rainfall_as_iv, iv_details["Endogenous explanatory variable"], iv_details["Instrumental variable"], iv_details["Dependent variable"], iv_details["Control variables"]

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
        writer.writerow(['Filename', 'Title', 'DOI', 'IV Used', 'Rainfall as IV', 'Endogenous Explanatory Variable', 'Instrumental Variable', 'Dependent Variable', 'Control Variables'])

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


******
******
python
# Define the function to extract text from PDF
def extract_text_from_pdf(pdf_path):
    ...

# Define the function to analyze the paper
def analyze_paper(paper_text):
    ...

# Specify the PDF file path
pdf_path = '...'

# Extract text from the PDF
paper_text = extract_text_from_pdf(pdf_path)

# Analyze the paper
analysis_result = analyze_paper(paper_text)

# Print the result
print(analysis_result)
end
python
import openai
import fitz  # PyMuPDF

# Replace 'your-api-key' with your actual OpenAI API key
openai.api_key = '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'

def extract_text_from_pdf(pdf_path):
    # Open the PDF file
    doc = fitz.open(pdf_path)
    text = ""
    # Iterate through each page
    for page_num in range(len(doc)):
        page = doc.load_page(page_num)
        text += page.get_text()
    return text

def analyze_paper(paper_text):
    # Define the prompt to send to the GPT model
    prompt = f"""
    Analyze the following research paper text and provide the following details in a structured format:
    - Instrumental Variable used
    - Rainfall Metric used
    - Dependent Variable
    - Outcome Variable
    - Independent Variable

    Research Paper Text:
    {paper_text}

    Provide the output in the following format:
    | Instrumental Variable | Rainfall Metric Used | Dependent Variable | Outcome Variable | Independent Variable |
    """

    # Debugging print statement
    print("Prompt Sent to GPT:")
    print(prompt[:2000])  # Print the first 2000 characters of the prompt to ensure it's being created correctly

    # Call the OpenAI GPT API
    response = openai.Completion.create(
        engine="text-davinci-003",
        prompt=prompt,
        max_tokens=1500,
        n=1,
        stop=None,
        temperature=0.5,
    )

    # Debugging print statements
    print("API Response:")
    print(response)

    # Extract the text from the response
    result = response.choices[0].text.strip() if response.choices else None

    return result

# Path to the PDF file
pdf_path = '/Users/kieran/Library/CloudStorage/OneDrive-UniversityofArizona/weather_and_agriculture/output/metric_paper/literature/training/1-s2.0-S0305750X1930275X-main copy.pdf'

# Extract text from the PDF
paper_text = extract_text_from_pdf(pdf_path)

# Debugging print statement
print("Extracted Text from PDF:")
print(paper_text[:1000])  # Print the first 1000 characters of the extracted text to check if extraction worked

# Analyze the paper
analysis_result = analyze_paper(paper_text)

# Print the result
print("Analysis Result:")
print(analysis_result)

end

* **********************************************************************
* 1 - get pdfs
* **********************************************************************

