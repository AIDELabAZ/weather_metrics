* Project: WB Weather - metric 
* Created on: June 2024
* Created by: jdm
* Last edited by: 10 June 2024
* Edited by: jdm
* Stata v.18.0

* does
    * gets urls to the pdfs for each paper from OpenAlex

* assumes
    * 

* TO DO:
    * 

* **********************************************************************
* 0 - setup
* **********************************************************************

global input "$data/output/metric_paper/literature"
/*
python

# Set output path using Stata global for the ChromeDriver
print("Setting environment variable STATA_DRIVER to:", "$driver")
os.environ['STATA_DRIVER'] = "$driver"
print("Environment variable STATA_DRIVER is set to:", os.environ['STATA_DRIVER'])

# Set output path using Stata global for the input path
print("Setting environment variable STATA_INPUT to:", "$input")
os.environ['STATA_INPUT'] = "$input"
print("Environment variable STATA_INPUT is set to:", os.environ['STATA_INPUT'])

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

python
import os
import pandas as pd
from selenium import webdriver
from selenium.webdriver.chrome.service import Service
from selenium.webdriver.common.by import By
from selenium.webdriver.chrome.options import Options
from selenium.webdriver.support.ui import WebDriverWait
from selenium.webdriver.support import expected_conditions as EC
from bs4 import BeautifulSoup
from urllib.parse import urljoin

# Set environment variables from Stata globals
print("Setting environment variable STATA_DRIVER to:", "$driver")
os.environ['STATA_DRIVER'] = "$driver"
print("Environment variable STATA_DRIVER is set to:", os.environ['STATA_DRIVER'])

print("Setting environment variable STATA_INPUT to:", "$input")
os.environ['STATA_INPUT'] = "$input"
print("Environment variable STATA_INPUT is set to:", os.environ['STATA_INPUT'])

# Read the global variables from the environment
driver_path = os.getenv('STATA_DRIVER')
if not driver_path:
    raise ValueError("Environment variable STATA_DRIVER is not set")

input_path = os.getenv('STATA_INPUT')
if not input_path:
    raise ValueError("Environment variable STATA_INPUT is not set")

# Path to the ChromeDriver
chrome_driver_path = driver_path

# Configure Chrome options
chrome_options = Options()
chrome_options.add_argument('--disable-gpu')  # Disable GPU acceleration

# Set up the WebDriver
service = Service(chrome_driver_path)
driver = webdriver.Chrome(service=service, options=chrome_options)

# Path to the input Excel file
input_excel_path = os.path.join(input_path, 'OpenAlex_Search_Results_test2.xlsx')

# Read the Excel file to get the DOIs and existing PDF URLs
df_input = pd.read_excel(input_excel_path)
doi_urls = df_input['doi'].dropna().unique()
pdf_urls = df_input['primary_location_pdf_url']

# Function to navigate to DOI and find PDF link
def get_pdf_url_from_doi(doi):
    try:
        # Handle specific DOIs directly as PDF URLs
        if any(prefix in doi for prefix in ['10.3386', '10.21315', '10.31219', '10.2307']):
            return f"https://doi.org/{doi}"

        # Handle DOIs containing '10.1257'
        if '10.1257' in doi:
            doi_suffix = doi.split('doi.org/')[-1]  # Extract the suffix of the DOI after 'doi.org/'
            pdf_url = f"https://pubs.aeaweb.org/doi/pdfplus/{doi_suffix}"
            return pdf_url

        # Handle DOIs containing '10.1016'
        if '10.1016' in doi:
            doi_suffix = doi.split('doi.org/')[-1]  # Extract the suffix of the DOI after 'doi.org/'
            pdf_url = f"https://www.sciencedirect.com/science/article/pii/{doi_suffix}/pdfft"
            return pdf_url

        doi_url = f"https://doi.org/{doi}"
        driver.get(doi_url)

        # Wait for the page to load and handle redirects
        WebDriverWait(driver, 10).until(EC.presence_of_element_located((By.TAG_NAME, "body")))
        soup = BeautifulSoup(driver.page_source, 'html.parser')

        # Print out the title of the current page for debugging
        page_title = driver.title
        current_url = driver.current_url
        print(f"Page title: {page_title}")
        print(f"Current URL: {current_url}")

        # Handle CAPTCHA by constructing the URL directly
        if page_title.lower() == "just a moment...":
            doi_suffix = doi.split('doi.org/')[-1]  # Extract the suffix of the DOI after 'doi.org/'
            if 'onlinelibrary.wiley.com' in current_url:
                pdf_url = f"https://onlinelibrary.wiley.com/doi/epdf/{doi_suffix}"
                return pdf_url
            elif 'journals.uchicago.edu' in current_url:
                pdf_url = f"https://www.journals.uchicago.edu/doi/epdf/{doi_suffix}"
                return pdf_url
            elif 'tandfonline.com' in current_url:
                pdf_url = f"https://www.tandfonline.com/doi/epdf/{doi_suffix}"
                return pdf_url

        # Search for links that end with .pdf, contain /epdf/, pdf?, file?, pdfft?, or reader
        pdf_links = soup.find_all('a', href=True)
        for link in pdf_links:
            href = link['href']
            if any(term in href for term in ['.pdf', '/epdf/', 'pdf?', 'file?', 'pdfft?', 'reader']):
                if not href.startswith('http'):
                    href = urljoin(driver.current_url, href)
                return href

        print(f"No PDF link found for {doi_url}")
    except Exception as e:
        print(f"Error navigating to {doi_url}: {e}")
    return None

# Function to save results to Excel
def save_results(results, missing_dois, output_path, missing_output_path):
    df_output = pd.DataFrame(results)
    df_missing = pd.DataFrame(missing_dois, columns=['doi'])

    # Append to the existing files if they exist
    if os.path.exists(output_path):
        df_existing = pd.read_excel(output_path)
        df_output = pd.concat([df_existing, df_output], ignore_index=True)

    if os.path.exists(missing_output_path):
        df_existing_missing = pd.read_excel(missing_output_path)
        df_missing = pd.concat([df_existing_missing, df_missing], ignore_index=True)

    df_output.to_excel(output_path, index=False)
    df_missing.to_excel(missing_output_path, index=False)

# Lists to hold the results and missing DOIs
results = []
missing_dois = []

# Process DOIs in chunks
chunk_size = 100
num_chunks = len(doi_urls) // chunk_size + 1

for i in range(num_chunks):
    chunk_start = i * chunk_size
    chunk_end = min((i + 1) * chunk_size, len(doi_urls))
    chunk_dois = doi_urls[chunk_start:chunk_end]
    chunk_pdf_urls = pdf_urls[chunk_start:chunk_end]

    for doi, pdf_url in zip(chunk_dois, chunk_pdf_urls):
        if pd.notna(pdf_url):
            results.append({'doi': doi, 'pdf_url': pdf_url})
        else:
            print(f"Processing DOI: {doi}")
            pdf_url = get_pdf_url_from_doi(doi)
            if pdf_url is None:
                missing_dois.append(doi)
            results.append({'doi': doi, 'pdf_url': pdf_url})
            print(f'PDF URL for {doi}: {pdf_url}')

    # Save the results after processing each chunk
    output_path = os.path.join(input_path, 'pdf_urls.xlsx')
    missing_output_path = os.path.join(input_path, 'missing_url.xlsx')
    save_results(results, missing_dois, output_path, missing_output_path)

# Close the WebDriver
driver.quit()

print(f'Final results saved to {output_path}')
print(f'Missing DOIs saved to {missing_output_path}')

end

/*
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
input_excel_path = r'C:\Users\jdmichler\OneDrive - University of Arizona\weather_and_agriculture\output\metric_paper\literature\OpenAlex_Search_Results_test2.xlsx'

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