* Project: WB Weather - metric 
* Created on: June 2024
* Created by: kcd
* Last edited by: 24 June 2024
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

* **********************************************************************
* 0 - setup
* **********************************************************************
/*
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
import openai
import PyPDF2

# Set your OpenAI API key
openai.api_key = 'org-K90DnhnbnHzjiYNTk4QdJkTu'

# Set your GPT endpoint
gpt_endpoint = 'https://chatgpt.com/gpts/editor/g-ko3L5ZVcD'

# Directory containing the PDF files
pdf_dir = r'/Users/kieran/Library/CloudStorage/OneDrive-UniversityofArizona/weather_and_agriculture/output/metric_paper/literature/training'

def extract_pdf_title(pdf_path):
    """
    Extract the title from the first page of a PDF.
    """
    try:
        with open(pdf_path, 'rb') as file:
            reader = PyPDF2.PdfFileReader(file)
            if reader.numPages > 0:
                first_page = reader.getPage(0)
                text = first_page.extractText()
                # Assuming the title is on the first line
                title = text.strip().split('\n')[0]
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

python
import os
import openai
import fitz  # PyMuPDF
import re

# Set your OpenAI API key
openai.api_key = 'org-K90DnhnbnHzjiYNTk4QdJkTu'

# Set your GPT endpoint
gpt_endpoint = 'https://chatgpt.com/gpts/editor/g-ko3L5ZVcD'

# Directory containing the PDF files
pdf_dir = r'/Users/kieran/Library/CloudStorage/OneDrive-UniversityofArizona/weather_and_agriculture/output/metric_paper/literature/training'

def extract_pdf_title(pdf_path):
    """
    Extract the title from a PDF.
    """
    try:
        doc = fitz.open(pdf_path)
        text = ""
        for page_num in range(min(2, len(doc))):  # Scan first two pages
            page = doc.load_page(page_num)
            text += page.get_text()

        # Find potential title using regex
        title_search = re.search(r'\b[A-Z][a-z]+(?: [A-Z][a-z]+)*\b', text)
        if title_search:
            return title_search.group(0)
        else:
            return "Title not found"
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

python
import os
import openai
import fitz  # PyMuPDF

# Set your OpenAI API key
openai.api_key = 'org-K90DnhnbnHzjiYNTk4QdJkTu'

# Set your GPT model
gpt_model = 'gpt-3.5-turbo'  # Use the ChatGPT model

# Directory containing the PDF files
pdf_dir = r'/Users/kieran/Library/CloudStorage/OneDrive-UniversityofArizona/weather_and_agriculture/output/metric_paper/literature/training'

def extract_text_from_pdf(pdf_path, num_pages=3):
    """
    Extract text from the first few pages of a PDF.
    """
    try:
        doc = fitz.open(pdf_path)
        text = ""
        for page_num in range(min(num_pages, len(doc))):  # Scan up to num_pages pages
            page = doc.load_page(page_num)
            text += page.get_text()
        return text
    except Exception as e:
        return f"Error reading {pdf_path}: {str(e)}"

def gpt_identify_title(text):
    """
    Use GPT to identify the title from the extracted text.
    """
    try:
        messages = [
            {"role": "system", "content": "You are a helpful assistant that extracts titles from academic papers."},
            {"role": "user", "content": f"Extract the title of the academic paper from the following text:\n\n{text}\n\nTitle:"}
        ]
        print("Messages sent to GPT:", messages)  # Debug print

        response = openai.ChatCompletion.create(
            model=gpt_model,
            messages=messages
        )
        print("API response:", response)  # Debug print

        title = response['choices'][0]['message']['content'].strip()
        return title
    except Exception as e:
        return f"Error with GPT API: {str(e)}"

def main():
    print(f"Interacting with GPT model: {gpt_model}")

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
        text = extract_text_from_pdf(pdf_path)
        if text.startswith("Error"):
            print(text)  # Print the error message
        else:
            title = gpt_identify_title(text)
            print(f"Title of '{pdf_file}': {title}")

if __name__ == "__main__":
    main()

end



* **********************************************************************
* 1 - get pdfs
* **********************************************************************

