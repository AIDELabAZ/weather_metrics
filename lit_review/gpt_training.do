* Project: WB Weather - metric 
* Created on: June 2024
* Created by: kcd
* Last edited by: 13 June 2024
* Edited by: kcd on mac
* Stata v.18.0

* does
    * Imports pdfs and feeds them to GPT via API. Reads them and outputs a CSV with relevant information
* assumes
    * ChatGPT account
	* pip install openai
	* 

* TO DO:
    * everything

* **********************************************************************
* 0 - setup
* **********************************************************************
python
import openai
import fitz  # PyMuPDF
import pandas as pd

os.environ["OPENAI_API_KEY"] = "sk-proj-kgFfZT6s4i6bbK6ivJ83T3BlbkFJ0cFc6wME3NzaLxNxX3n5"
openai.api_key = os.getenv("OPENAI_API_KEY")

def chatgpt_api(prompt, model="gpt-4-turbo", temperature=0.7, max_tokens=1000):
    """
    Calls the GPT API to extract information based on the prompt.

    :param prompt: The prompt to guide GPT extraction.
    :param model: The GPT model to use.
    :param temperature: Sampling temperature.
    :param max_tokens: Maximum tokens in the response.
    :return: Extracted information as a string.
    """
    response = openai.ChatCompletion.create(
        model=model,
        messages=[
            {"role": "user", "content": prompt}
        ],
        temperature=temperature,
        max_tokens=max_tokens
    )
    
    return response.choices[0].message['content']

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

def extract_information_from_pdfs(pdf_paths, prompt, output_csv):
    """
    Extracts information from a list of PDFs and writes it to a CSV.

    :param pdf_paths: List of paths to PDF files.
    :param prompt: The prompt to guide GPT extraction.
    :param output_csv: Path to the output CSV file.
    """
    data = []
    for pdf_path in pdf_paths:
        print(f"Processing {pdf_path}...")
        text = extract_text_from_pdf(pdf_path)
        # Formulate a specific prompt with the PDF content
        specific_prompt = f"{prompt}\n\nHere is the text from
nse.choices[0].message.content
end


* **********************************************************************
* 1 - get pdfs
* **********************************************************************

