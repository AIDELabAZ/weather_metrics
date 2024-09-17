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


* **********************************************************************
* 2 - using a large training set to test output consistency (n=100)
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
    pdf_directory = '/Users/kieran/Library/CloudStorage/OneDrive-UniversityofArizona/weather_iv_lit/training/training_large'

    # Process the PDFs
    results = process_pdfs_in_directory(pdf_directory)

    # Save the results to a CSV file in the same directory as the PDFs
    output_file = os.path.join(pdf_directory, 'PDF_Analysis_Updated.csv')
    save_results_to_csv(results, output_file)
    print(f"Results saved to {output_file}")
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


