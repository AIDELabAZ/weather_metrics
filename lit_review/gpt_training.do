* Project: WB Weather - metric 
* Created on: June 2024
* Created by: kcd
* Last edited by: 02/08/2024
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
* 1 - using a small training set to troubleshoot for consistency (n=16)
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
client = OpenAI(api_key='sk-proj-suQZfMsXyLR71c8rXhj6T3BlbkFJxNLNgMHcgKnmpuqlu9Wp')

# Directory containing the PDF files
pdf_dir = r'/Users/kieran/Library/CloudStorage/OneDrive-UniversityofArizona/weather_and_agriculture/output/metric_paper/literature/training'

# Output CSV file path
csv_output_path = os.path.join(pdf_dir, 'PDF_Analysis.csv')

# List of rainfall measurement methods and additional keywords
rainfall_methods = [
    "total rainfall", "deviations in total rainfall", "scaled deviations in total rainfall",
    "mean total rainfall", "total monthly rainfall", "mean monthly rainfall", "rainfall months",
    "daily rainfall", "rainfall days", "no rainfall days", "log of rainfall", "rainfall index",
    "rainfall", "deviation", "average", "seasonal", "shocks"
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
        logging.debug(f"Extracted text from {pdf_path}: {text[:500]}...")  # Log first 500 characters of extracted text
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
                model="gpt-3.5-turbo",
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
                    model="gpt-3.5-turbo",
                    temperature=0,
                    messages=[
                        {"role": "system", "content": "You are an expert in identifying variables in academic papers."},
                        {"role": "user", "content": f"Identify the following in the paper: 1) Explanatory variable, 2) Instrumental variable, 3) Dependent variable, 4) Control variables. Provide each in one line with the label. Provide short and concise descriptions only. Read entire PDF and be sure to extract what metric or thing was used as the instrumental variable or other variables. Explanatory variable:, Instrumental variable:, Dependent variable:, Control variables:. If any of these variables are not explicitly mentioned, please infer them from the context: {text[:6000]}"}
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
                        model="gpt-3.5-turbo",
                        temperature=0,
                        messages=[
                            {"role": "system", "content": "You are an expert in identifying specific metrics used for rainfall in academic papers."},
                            {"role": "user", "content": f"Can you read the entire PDF and tell me what the rainfall metric is that the authors used as an instrumental variable? Please only give me the metric, I do not want a sentence giving context. Please make sure that the specific metric is given, I do not want it to just say things like 'rainfall measurements'. Do not write things like 'The specific rainfall metric used as an instrumental variable in the study is': {text[:6000]}"}
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
                    model="gpt-3.5-turbo",
                    temperature=0,
                    messages=[
                        {"role": "system", "content": "You are an expert in identifying variables in academic papers."},
                        {"role": "user", "content": f"Identify the following in the paper: 1) Explanatory variable, 2) Dependent variable, 3) Control variables. Provide each in one line with the label. Use terms like 'independent variable', 'predictor', or 'x' synonymously with 'explanatory variable'. Provide short and concise descriptions only. If any of these variables are not explicitly mentioned, please infer them from the context: {text[:6000]}"}
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
* 2 - using a large training set to test output consistency (n=100)
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
client = OpenAI(api_key='sk-proj-suQZfMsXyLR71c8rXhj6T3BlbkFJxNLNgMHcgKnmpuqlu9Wp')

# Directory containing the PDF files
pdf_dir = r'/Users/kieran/Library/CloudStorage/OneDrive-UniversityofArizona/weather_and_agriculture/output/metric_paper/literature/training_large'

# Output CSV file path
csv_output_path = os.path.join(pdf_dir, 'PDF_Analysis.csv')

# List of rainfall measurement methods and additional keywords
rainfall_methods = [
    "total rainfall", "deviations in total rainfall", "scaled deviations in total rainfall",
    "mean total rainfall", "total monthly rainfall", "mean monthly rainfall", "rainfall months",
    "daily rainfall", "rainfall days", "no rainfall days", "log of rainfall", "rainfall index",
    "rainfall", "deviation", "average", "seasonal", "shocks"
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
        logging.debug(f"Extracted text from {pdf_path}: {text[:500]}...")  # Log first 500 characters of extracted text
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
                model="gpt-3.5-turbo",
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
                    model="gpt-3.5-turbo",
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
                        model="gpt-3.5-turbo",
                        temperature=0,
                        messages=[
                            {"role": "system", "content": "You are an expert in identifying specific metrics used for rainfall in academic papers that use instrumental variables."},
                            {"role": "user", "content": f"Read the entire PDF and tell me what the rainfall metric or measurement is that the authors used as an instrumental variable. Only output the name of the metric without any additional words or sentences in less than or equal to 8 words. Examples of desired output: deviations in total rainfall, year-over-year rainfall variation. Sometimes the specific metric used by researchers is stated later in the paper like in the methods or discussion section, so please make sure to read them thoroughly to find how the authors accounted for rainfall in each paper. : {text[:6000]}"}
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
                    model="gpt-3.5-turbo",
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
* 2 - using a large training set to test output consistency (n=100)
* **********************************************************************

python
import os
import csv
import fitz  # PyMuPDF
from openai import OpenAI
import logging

# Set up logging
logging.basicConfig(level=logging.DEBUG, format='%(asctime)s - %(levelname)s - %(message)s')

# Initialize the OpenAI client
client = OpenAI(api_key=os.getenv('OPENAI_API_KEY'))

# Directory containing the PDF files
pdf_dir = r'/Users/kieran/Library/CloudStorage/OneDrive-UniversityofArizona/weather_and_agriculture/output/metric_paper/literature/training'

# Output CSV file path
csv_output_path = os.path.join(pdf_dir, 'small_analysis.csv')

def extract_text_from_pdf(pdf_path):
    try:
        text = ""
        doc = fitz.open(pdf_path)
        for page in doc:
            text += page.get_text()
        logging.debug(f"Extracted text from {pdf_path}: {text[:500]}...")  # Log first 500 characters of extracted text
        return text
    except Exception as e:
        logging.error(f"Error extracting text from {pdf_path}: {str(e)}")
        return None

def get_rainfall_metric(text):
    try:
        response = client.chat.completions.create(
            model="gpt-3.5-turbo",
            messages=[
                {"role": "system", "content": "You are an expert in identifying specific metrics used for rainfall as an instrumental variable in academic papers."},
                {"role": "user", "content": f"Extract the specific metric or variable used for rainfall as an instrumental variable from this text. Provide only the specific metric or variable used, without any additional explanation or context: {text}"}
            ],
            max_tokens=50  # Limit the response length to ensure conciseness
        )
        metric = response.choices[0].message.content.strip()
        return metric if metric else "N/A"
    except Exception as e:
        logging.error(f"Error calling OpenAI API: {str(e)}")
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
        writer.writerow(['Filename', 'Rainfall Metric'])

        for pdf_file in pdf_files:
            pdf_path = os.path.join(pdf_dir, pdf_file)
            text = extract_text_from_pdf(pdf_path)
            if text:
                rainfall_metric = get_rainfall_metric(text)
                writer.writerow([pdf_file, rainfall_metric])
                logging.info(f"Processed: {pdf_file} - Rainfall Metric: {rainfall_metric}")
            else:
                writer.writerow([pdf_file, "N/A"])
                logging.info(f"Skipping: {pdf_file}")

    logging.info(f"CSV file '{csv_output_path}' has been created.")

if __name__ == "__main__":
    main()
end
* **********************************************************************
* 3 - using full training set to test output consistency (n=)
* **********************************************************************

python

end
