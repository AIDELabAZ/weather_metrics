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
/*
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
end
*/
* **********************************************************************
* 1 - get urls for the pdfs
* **********************************************************************
/*
python
import requests
import pandas as pd
import os
import urllib.request

# Constants
API_KEY = '937c8b4d44a7e6083cfdbb9e3def3b39'
INPUT_FILE_PATH = r'C:\Users\jdmichler\OneDrive - University of Arizona\weather_and_agriculture\output\metric_paper\literature\OpenAlex_Search_Results_test2.xlsx'
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
        with open(os.path.join(output_dir, f'{clean_doi.replace("/", "_")}.pdf'), 'wb') as f:
            f.write(response.content)
        return True
    else:
        print(f"Failed to download {clean_doi}: {response.status_code}")
        return False

# Function to download PDF using urllib
def download_pdf_url(pdf_url, output_dir, doi):
    try:
        response = urllib.request.urlopen(pdf_url)
        with open(os.path.join(output_dir, f'{doi.replace("/", "_")}.pdf'), 'wb') as f:
            f.write(response.read())
        return True
    except Exception as e:
        print(f"Failed to download {pdf_url}: {e}")
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
        if not download_pdf(doi, OUTPUT_DIR, API_KEY):
            print(f"Could not download PDF for DOI: {doi}")

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
        if not download_pdf_url(pdf_url, OUTPUT_DIR, doi):
            print(f"Could not download PDF from URL: {pdf_url}")
            missing_pdfs.append({'doi': doi, 'pdf_url': pdf_url})

    # Save missing PDFs to Excel
    if missing_pdfs:
        df_missing_pdfs = pd.DataFrame(missing_pdfs)
        df_missing_pdfs.to_excel(MISSING_PDF_FILE_PATH, index=False)
        print(f"Missing PDFs saved to {MISSING_PDF_FILE_PATH}")

if __name__ == '__main__':
    main()

end
*/

* **********************************************************************
* 2 - try getting urls for the pdfs using crossref
* **********************************************************************
python
import requests
import pandas as pd
import os
import time

# Function to get metadata from CrossRef API
def get_metadata_from_crossref(doi):
    url = f'https://api.crossref.org/works/{doi}'
    response = requests.get(url)
    if response.status_code == 200:
        return response.json()
    else:
        return None

# Function to extract the full text link from the CrossRef metadata
def get_full_text_link(metadata):
    if 'message' in metadata and 'link' in metadata['message']:
        for link in metadata['message']['link']:
            if 'pdf' in link['content-type'] or 'pdfft' in link['content-type'] or 'reader' in link['content-type']:
                return link['URL']
    return None

# Path to the input Excel file
input_excel_path = r'C:\Users\jdmichler\OneDrive - University of Arizona\weather_and_agriculture\output\metric_paper\literature\OpenAlex_Search_Results.xlsx'

# Read the Excel file to get the DOIs
df_input = pd.read_excel(input_excel_path)
doi_urls = df_input['doi'].dropna().unique()

# Lists to hold the results and missing DOIs
results = []
missing_dois = []

# Process each DOI
for doi in doi_urls:
    print(f"Processing DOI: {doi}")
    metadata = get_metadata_from_crossref(doi)
    if metadata:
        pdf_url = get_full_text_link(metadata)
        if pdf_url:
            results.append({'doi': doi, 'pdf_url': pdf_url})
        else:
            print(f"No PDF link found in metadata for {doi}")
            missing_dois.append({'doi': doi, 'reason': 'No PDF link in metadata'})
    else:
        print(f"Failed to retrieve metadata for {doi}")
        missing_dois.append({'doi': doi, 'reason': 'Failed to retrieve metadata'})
    time.sleep(1)  # Sleep for a second to avoid hitting API rate limits

# Convert results to a DataFrame
df_output = pd.DataFrame(results)

# Path to save the results
output_path = r'C:\Users\jdmichler\OneDrive - University of Arizona\weather_and_agriculture\output\metric_paper\literature\pdf_urls.xlsx'

# Save the results to an Excel file, overwriting the old version
df_output.to_excel(output_path, index=False)
print(f'Results saved to {output_path}')

# Convert missing DOIs to a DataFrame
df_missing = pd.DataFrame(missing_dois)

# Path to save the missing DOIs
missing_output_path = r'C:\Users\jdmichler\OneDrive - University of Arizona\weather_and_agriculture\output\metric_paper\literature\missing_urls.xlsx'

# Save the missing DOIs to an Excel file, overwriting the old version
df_missing.to_excel(missing_output_path, index=False)
print(f'Missing DOIs saved to {missing_output_path}')

end