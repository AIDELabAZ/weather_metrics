* Project: WB Weather - metric 
* Created on: June 2024
* Created by: kcd
* Last edited by: 27 June 2024
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

/*
python
import fitz  # PyMuPDF library for PDF processing
import openpyxl
import requests
import os

# Set your API key for the personalized GPT endpoint
api_key = "org-K90DnhnbnHzjiYNTk4QdJkTu"

# Personalized GPT endpoint URL
gpt_endpoint = "https://chatgpt.com/gpts/editor/g-ko3L5ZVcD"

def extract_text_from_pdf(pdf_path):
    """
    Extracts text from a PDF file.

    :param pdf_path: Path to the PDF file.
    :return: Extracted text as a string.
    """
    text = ""
    document = fitz.open(pdf_path)
    for page_num in range(len(document)):
        page = document.load_page(page_num)
        text += page.get_text()
    return text

def call_personalized_gpt_api(text, prompt):
    """
    Calls the personalized GPT API to extract information based on the prompt.

    :param text: The text to process.
    :param prompt: The prompt to guide GPT extraction.
    :return: Extracted information as a string.
    """
    headers = {
        "Authorization": f"Bearer {api_key}",
        "Content-Type": "application/json"
    }

    payload = {
        "model": "gpt-4-turbo",
        "messages": [
            {"role": "system", "content": "You are an assistant that extracts specific information from academic papers."},
            {"role": "user", "content": f"{prompt}\n\nText:\n{text}"}
        ]
    }

    response = requests.post(gpt_endpoint, headers=headers, json=payload)
    
    if response.status_code == 200:
        return response.json()['choices'][0]['message']['content']
    else:
        print(f"Error: {response.status_code} - {response.text}")
        return ""

def process_paper(pdf_path):
    """
    Processes a PDF academic paper to extract relevant information.

    :param pdf_path: Path to the PDF file.
    :return: A dictionary with extracted information.
    """
    text = extract_text_from_pdf(pdf_path)
    prompt = "Does this academic paper use an instrumental variable (IV) or variables in the empirical or applied analysis? If yes, identify the endogenous variable(s) being instrumented, the instrumental variable(s) used, the dependent variable, and any control variables used in the analysis. If no IV is used, simply state 'No IV used'. Also, identify the DOI for the paper (if available) and the title of the paper."
    response = call_personalized_gpt_api(text, prompt)

    # Parse the response
    if "No IV used" in response:
        iv_present = 0
        endogenous_var = ""
        instrumental_var = ""
        dependent_var = ""
        control_vars = ""
    else:
        iv_present = 1
        lines = response.split("\n")
        if len(lines) >= 4:
            endogenous_var = lines[0].split(":")[1].strip()
            instrumental_var = lines[1].split(":")[1].strip()
            dependent_var = lines[2].split(":")[1].strip()
            control_vars = lines[3].split(":")[1].strip()
        else:
            endogenous_var = ""
            instrumental_var = ""
            dependent_var = ""
            control_vars = ""

    # Extract DOI and title
    doi = "NA"
    title = ""
    if "DOI:" in response:
        doi = response.split("DOI:")[1].split("\n")[0].strip()
    if "Title:" in response:
        title = response.split("Title:")[1].strip()

    return {
        "doi": doi,
        "iv_present": iv_present,
        "y": dependent_var,
        "x": endogenous_var,
        "z": instrumental_var,
        "c": control_vars,
        "title": title
    }

def write_to_excel(data, output_path):
    """
    Writes the extracted information to an Excel file.

    :param data: List of dictionaries containing extracted information.
    :param output_path: Path to the output Excel file.
    """
    workbook = openpyxl.Workbook()
    worksheet = workbook.active

    # Write column headers
    headers = ["doi", "iv_present", "y", "x", "z", "c", "title"]
    worksheet.append(headers)

    # Write data rows
    for row_data in data:
        row = [row_data[header] for header in headers]
        worksheet.append(row)

    workbook.save(output_path)

# Example usage
pdf_dir = "/Users/kieran/Library/CloudStorage/OneDrive-UniversityofArizona/weather_and_agriculture/output/metric_paper/literature/training"
output_path = os.path.join(pdf_dir, "iv_output.xlsx")

data = []
for pdf_file in os.listdir(pdf_dir):
    if pdf_file.endswith(".pdf"):
        pdf_path = os.path.join(pdf_dir, pdf_file)
        print(f"Processing {pdf_path}...")
        extracted_info = process_paper(pdf_path)
        data.append(extracted_info)

write_to_excel(data, output_path)

print(f"Extracted information saved to {output_path}")
end
*/


/*
python
import os
from PyPDF2 import PdfReader
from openai import OpenAI

# Set your OpenAI API key
client = OpenAI(api_key='sk-proj-YRa0EozaWS1ZZJvB0sZqT3BlbkFJjjqPLhfKv5dvM4NkBrjv')

# Use the api_key variable in your API calls
import openai
openai.api_key = api_key
# Directory containing the PDF files
pdf_dir = r'/Users/kieran/Library/CloudStorage/OneDrive-UniversityofArizona/weather_and_agriculture/output/metric_paper/literature/training'

def extract_pdf_title(pdf_path):
    """
    Extract the title from the first page of a PDF using GPT API.
    """
    try:
        with open(pdf_path, 'rb') as file:
            reader = PdfReader(file)
            if len(reader.pages) > 0:
                first_page = reader.pages[0]
                text = first_page.extract_text()
                
                # Use GPT to extract the title
                response = client.chat.completions.create(
                    model="gpt-3.5-turbo",
                    messages=[
                        {"role": "system", "content": "You are a helpful assistant that extracts titles from academic papers."},
                        {"role": "user", "content": f"Extract the title from this text of an academic paper's first page: {text[:500]}"}
                    ]
                )
                
                title = response.choices[0].message.content.strip()
                return title
            else:
                return "No pages found"
    except Exception as e:
        return f"Error reading {pdf_path}: {str(e)}"

def main():
    # Ensure the directory exists
    if not os.path.exists(pdf_dir):
        print(f"Directory {pdf_dir} does not exist.")
        return

    # List all PDF files in the directory
    pdf_files = [f for f in os.listdir(pdf_dir) if f.lower().endswith('.pdf')]

    if not pdf_files:
        print("No PDF files found.")
        return

    # Extract and print titles
    for pdf_file in pdf_files:
        pdf_path = os.path.join(pdf_dir, pdf_file)
        title = extract_pdf_title(pdf_path)
        print(f"Title of '{pdf_file}': {title}")

if __name__ == "__main__":
    main()
end
*/

********
Get IV
********
/*
python
import os
from PyPDF2 import PdfReader
from openai import OpenAI

# Set your OpenAI API key
client = OpenAI(api_key='sk-proj-YRa0EozaWS1ZZJvB0sZqT3BlbkFJjjqPLhfKv5dvM4NkBrjv')

# Directory containing the PDF files
pdf_dir = r'/Users/kieran/Library/CloudStorage/OneDrive-UniversityofArizona/weather_and_agriculture/output/metric_paper/literature/training'

def extract_title_and_rainfall_measurement(pdf_path):
    """
    Extract the title and the rainfall measurement method from a PDF using GPT API.
    """
    try:
        with open(pdf_path, 'rb') as file:
            reader = PdfReader(file)
            text = ""
            for page in reader.pages:
                text += page.extract_text()
            
            # Use GPT to extract the title
            title_response = client.chat.completions.create(
                model="gpt-3.5-turbo",
                messages=[
                    {"role": "system", "content": "You are a helpful assistant that extracts titles from academic papers."},
                    {"role": "user", "content": f"Extract the title from this text of an academic paper's first page: {text[:500]}"}
                ]
            )
            title = title_response.choices[0].message.content.strip()
            
            # Use GPT to extract the rainfall measurement method
            rainfall_response = client.chat.completions.create(
                model="gpt-3.5-turbo",
                messages=[
                    {"role": "system", "content": "You are a helpful assistant that identifies rainfall measurement methods in academic papers."},
                    {"role": "user", "content": f"Identify how rainfall was measured or the rainfall measurement method used in this academic paper. Provide a brief description of the method: {text[:4000]}"}
                ]
            )
            rainfall_measurement = rainfall_response.choices[0].message.content.strip()
            
            return title, rainfall_measurement
    except Exception as e:
        return f"Error reading {pdf_path}: {str(e)}", None

def main():
    # Ensure the directory exists
    if not os.path.exists(pdf_dir):
        print(f"Directory {pdf_dir} does not exist.")
        return

    # List all PDF files in the directory
    pdf_files = [f for f in os.listdir(pdf_dir) if f.lower().endswith('.pdf')]

    if not pdf_files:
        print("No PDF files found.")
        return

    # Extract and print titles and rainfall measurement methods
    for pdf_file in pdf_files:
        pdf_path = os.path.join(pdf_dir, pdf_file)
        title, rainfall_measurement = extract_title_and_rainfall_measurement(pdf_path)
        print(f"Title of '{pdf_file}': {title}")
        print(f"Rainfall Measurement Method in '{pdf_file}': {rainfall_measurement}")
        print("-" * 50)

if __name__ == "__main__":
    main()
end

*/

*****
Install in terminal: pip install xlsxwriter
*****
/*
python
import os
import csv
from PyPDF2 import PdfReader
from openai import OpenAI

# Set your OpenAI API key
client = OpenAI(api_key='sk-proj-YRa0EozaWS1ZZJvB0sZqT3BlbkFJjjqPLhfKv5dvM4NkBrjv')

# Directory containing the PDF files
pdf_dir = r'/Users/kieran/Library/CloudStorage/OneDrive-UniversityofArizona/weather_and_agriculture/output/metric_paper/literature/training'

# Output CSV file path
csv_output_path = os.path.join(pdf_dir, 'PDF_Analysis.csv')

def extract_title_and_rainfall_measurement(pdf_path):
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
            
            return title, rainfall_measurement
    except Exception as e:
        return f"Error processing {pdf_path}: {str(e)}", "Error extracting rainfall measurement"

def main():
    if not os.path.exists(pdf_dir):
        print(f"Directory {pdf_dir} does not exist.")
        return

    pdf_files = [f for f in os.listdir(pdf_dir) if f.lower().endswith('.pdf')]

    if not pdf_files:
        print("No PDF files found.")
        return

    with open(csv_output_path, 'w', newline='', encoding='utf-8') as csvfile:
        writer = csv.writer(csvfile)
        writer.writerow(['Filename', 'Title', 'Rainfall Measurement Method'])

        for pdf_file in pdf_files:
            pdf_path = os.path.join(pdf_dir, pdf_file)
            title, rainfall_measurement = extract_title_and_rainfall_measurement(pdf_path)
            writer.writerow([pdf_file, title, rainfall_measurement])
            print(f"Processed: {pdf_file}")

    print(f"CSV file '{csv_output_path}' has been created.")

if __name__ == "__main__":
    main()
end
*/



******
this is the one, currently running into issues with incorrect doi and several missing values
******

python
import os
import csv
import pandas as pd
from PyPDF2 import PdfReader
from openai import OpenAI

# Set your OpenAI API key
client = OpenAI(api_key='sk-proj-YRa0EozaWS1ZZJvB0sZqT3BlbkFJjjqPLhfKv5dvM4NkBrjv')

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

