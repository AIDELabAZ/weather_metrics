* Project: WB Weather - metric 
* Created on: Jan 2024
* Created by: jdm
* Last edited by: 11 June 2024
* Edited by: jdm
* Stata v.18.0

* does
    * usings Elsevier API to get papers on ScienceDirect
	* Wiley API: 4215866f-1350-400b-a8bf-69262b8b2dce
	
* assumes
    * 

* TO DO:
    * 

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
install("selenium")
install("beautifulsoup4")
install("pandas")
install("PyPDF2")
end

* **********************************************************************
* 1 - get urls for the pdfs
* **********************************************************************

python
import requests
import pandas as pd
import os
import urllib.request
import PyPDF2

# Constants
API_KEY = '937c8b4d44a7e6083cfdbb9e3def3b39'
INPUT_FILE_PATH = r'C:\Users\jdmichler\OneDrive - University of Arizona\weather_and_agriculture\output\metric_paper\literature\elsevier_urls1.xlsx'
PDF_URL_FILE_PATH = r'C:\Users\jdmichler\OneDrive - University of Arizona\weather_and_agriculture\output\metric_paper\literature\pdf_urls.xlsx'
OUTPUT_DIR = r'C:\Users\jdmichler\OneDrive - University of Arizona\weather_and_agriculture\output\metric_paper\literature\output'
MISSING_DOI_FILE_PATH = r'C:\Users\jdmichler\OneDrive - University of Arizona\weather_and_agriculture\output\metric_paper\literature\missing_url.xlsx'
MISSING_PDF_FILE_PATH = r'C:\Users\jdmichler\OneDrive - University of Arizona\weather_and_agriculture\output\metric_paper\literature\missing_pdf.xlsx'
ELSEVIER_URL = 'https://api.elsevier.com/content/article/doi/'

# Function to check if DOI is from ScienceDirect
def is_elsevier_doi(doi):
    if isinstance(doi, str):
        return '10.1016' in doi.lower()
    return False

# Function to download PDF from Elsevier API
def download_pdf(doi, output_dir, api_key):
    # Remove 'https://doi.org/' prefix if present
    clean_doi = doi.replace('https://doi.org/', '')
    headers = {
        'Accept': 'application/pdf',
        'X-ELS-APIKey': api_key
    }
    response = requests.get(f'{ELSEVIER_URL}{clean_doi}', headers=headers)
    if response.status_code == 200:
        pdf_path = os.path.join(output_dir, f'{clean_doi.replace("/", "_")}.pdf')
        with open(pdf_path, 'wb') as f:
            f.write(response.content)
        return pdf_path
    else:
        print(f"Failed to download {clean_doi}: {response.status_code}")
        return None

# Function to download PDF using urllib
def download_pdf_url(pdf_url, output_dir, doi):
    try:
        pdf_path = os.path.join(output_dir, f'{doi.replace("/", "_")}.pdf')
        response = urllib.request.urlopen(pdf_url)
        with open(pdf_path, 'wb') as f:
            f.write(response.read())
        return pdf_path
    except Exception as e:
        print(f"Failed to download {pdf_url}: {e}")
        return None

# Function to check if the PDF has more than one page
def verify_pdf(pdf_path):
    try:
        with open(pdf_path, 'rb') as f:
            reader = PyPDF2.PdfFileReader(f)
            return reader.numPages > 1
    except Exception as e:
        print(f"Error verifying PDF {pdf_path}: {e}")
        return False

def main():
    # Read the Excel file for DOIs
    df_doi = pd.read_excel(INPUT_FILE_PATH)

    # Convert all column names to lower case for consistent checking
    df_doi.columns = map(str.lower, df_doi.columns)

    # Ensure the DOI column exists
    if 'doi' not in df_doi.columns:
        print("DOI column not found in the Excel file.")
        return

    # Filter DOIs associated with ScienceDirect
    df_doi['is_elsevier'] = df_doi['doi'].apply(is_elsevier_doi)
    df_elsevier = df_doi[df_doi['is_elsevier']]
    df_other = df_doi[~df_doi['is_elsevier']]

    # Debug information
    print(f"Total DOIs: {len(df_doi)}")
    print(f"ScienceDirect DOIs: {len(df_elsevier)}")
    print(f"Other DOIs: {len(df_other)}")

    # Download PDFs from Elsevier
    for doi in df_elsevier['doi']:
        print(f"Attempting to download PDF for DOI: {doi}")
        pdf_path = download_pdf(doi, OUTPUT_DIR, API_KEY)
        if pdf_path and verify_pdf(pdf_path):
            print(f"Downloaded and verified PDF for DOI: {doi}")
        else:
            print(f"Could not download or verify PDF for DOI: {doi}")

    # Save missing DOIs to Excel
    df_other.to_excel(MISSING_DOI_FILE_PATH, index=False)
    print(f"Missing DOIs saved to {MISSING_DOI_FILE_PATH}")

    # Read the Excel file for PDF URLs
    df_url = pd.read_excel(PDF_URL_FILE_PATH)

    # Convert all column names to lower case for consistent checking
    df_url.columns = map(str.lower, df_url.columns)

    # Ensure the pdf_url column exists
    if 'pdf_url' not in df_url.columns:
        print("pdf_url column not found in the Excel file.")
        return

    # Download PDFs from URLs
    missing_pdfs = []
    for index, row in df_url.iterrows():
        doi = row['doi'] if 'doi' in row else 'unknown_doi'
        pdf_url = row['pdf_url']
        print(f"Attempting to download PDF from URL: {pdf_url}")
        pdf_path = download_pdf_url(pdf_url, OUTPUT_DIR, doi)
        if pdf_path and verify_pdf(pdf_path):
            print(f"Downloaded and verified PDF from URL: {pdf_url}")
        else:
            print(f"Could not download or verify PDF from URL: {pdf_url}")
            missing_pdfs.append({'doi': doi, 'pdf_url': pdf_url})

    # Save missing PDFs to Excel
    if missing_pdfs:
        df_missing_pdfs = pd.DataFrame(missing_pdfs)
        df_missing_pdfs.to_excel(MISSING_PDF_FILE_PATH, index=False)
        print(f"Missing PDFs saved to {MISSING_PDF_FILE_PATH}")

if __name__ == '__main__':
    main()

end

