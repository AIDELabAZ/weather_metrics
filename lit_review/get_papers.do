* Project: WB Weather - metric 
* Created on: Jan 2024
* Created by: jdm
* Last edited by: 11 June 2024
* Edited by: jdm
* Stata v.18.0

* does
    * Elsevier API: 937c8b4d44a7e6083cfdbb9e3def3b39
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
* 1 - get pdfs from Elsevier
* **********************************************************************

python
import pandas as pd
import requests
import os
import re

# 1. Load data from the Excel file
excel_file = r"C:\Users\jdmichler\OneDrive - University of Arizona\weather_iv_lit\openalex\OpenAlex_Search_Results_Complete.xlsx"
df = pd.read_excel(excel_file)

# 5. Define the folder to save the PDFs
output_folder = r"C:\Users\jdmichler\OneDrive - University of Arizona\weather_iv_lit\papers"
os.makedirs(output_folder, exist_ok=True)

# 2. Extract the DOI for each paper
dois = df['ids_doi']

# Your Elsevier API key
api_key = '937c8b4d44a7e6083cfdbb9e3def3b39'

for doi in dois:
    if isinstance(doi, str) and doi.startswith('https://doi.org/10.1016'):
        # 3. Check if the paper is published by Elsevier
        doi_suffix = doi.replace('https://doi.org/', '')
        
        # 4. Access the Elsevier API to download the PDF
        url = f'https://api.elsevier.com/content/article/doi/{doi_suffix}'
        headers = {
            'X-ELS-APIKey': api_key,
            'Accept': 'application/pdf'
        }

        response = requests.get(url, headers=headers)

        if response.status_code == 200:
            # Clean the DOI to create a valid filename
            safe_filename = re.sub(r'[^\w\-_\. ]', '_', doi_suffix) + '.pdf'
            filepath = os.path.join(output_folder, safe_filename)
            
            # Save the PDF to the specified folder
            with open(filepath, 'wb') as f:
                f.write(response.content)
            print(f"Downloaded: {safe_filename}")
        else:
            print(f"Failed to download {doi}. HTTP Status Code: {response.status_code}")
end


* **********************************************************************
* 2 - get pdfs from wiley
* **********************************************************************

python
import pandas as pd
import requests
import os
import re
import time

# 1. Load data from the Excel file
excel_file = r"C:\Users\jdmichler\OneDrive - University of Arizona\weather_iv_lit\openalex\OpenAlex_Search_Results_Complete.xlsx"
df = pd.read_excel(excel_file)

# 5. Define the folder to save the PDFs
output_folder = r"C:\Users\jdmichler\OneDrive - University of Arizona\weather_iv_lit\papers"
os.makedirs(output_folder, exist_ok=True)

# Define the folder and file to save the missing papers
missing_papers_folder = r"C:\Users\jdmichler\OneDrive - University of Arizona\weather_iv_lit\openalex"
missing_papers_file = os.path.join(missing_papers_folder, 'missing_papers.csv')

# 2. Extract the DOI for each paper
dois = df['ids_doi']

# Your Wiley API key
api_key = '4215866f-1350-400b-a8bf-69262b8b2dce'

# List to keep track of DOIs that failed to download, along with error messages
failed_downloads = []

# List of Wiley DOI prefixes
wiley_doi_prefixes = [
    '10.1111',
    '10.1002',
    '10.1093/ajae',
    '10.1155',
    '10.1029',
    '10.1093/aepp',
    '10.4073',
    '10.4284'
]

for doi in dois:
    if isinstance(doi, str) and any(doi.startswith(f'https://doi.org/{prefix}') for prefix in wiley_doi_prefixes):
        # Prepare the DOI suffix (remove 'https://doi.org/')
        doi_suffix = doi.replace('https://doi.org/', '')

        # Construct the URL to access Wiley API
        url = f'https://api.wiley.com/onlinelibrary/tdm/v1/articles/{doi_suffix}'

        headers = {
            'Accept': 'application/pdf',
            'Wiley-TDM-Client-Token': api_key
        }

        # Clean the DOI to create a valid filename
        safe_filename = re.sub(r'[^\w\-_\. ]', '_', doi_suffix) + '.pdf'
        filepath = os.path.join(output_folder, safe_filename)

        max_retries = 3
        for attempt in range(1, max_retries + 1):
            try:
                response = requests.get(url, headers=headers, timeout=30)

                if response.status_code == 200:
                    # Overwrite any existing file with the same name
                    with open(filepath, 'wb') as f:
                        f.write(response.content)
                    print(f"Downloaded: {safe_filename}")
                    break  # Exit the retry loop if download is successful
                else:
                    print(f"Attempt {attempt}: Failed to download {doi}. HTTP Status Code: {response.status_code}")
                    if attempt == max_retries:
                        # If last attempt, log the failure
                        failed_downloads.append({'DOI': doi, 'Error': f'HTTP Status Code: {response.status_code}'})
                    else:
                        time.sleep(5)  # Wait before retrying
            except requests.exceptions.RequestException as e:
                print(f"Attempt {attempt}: Error downloading {doi}. Error: {e}")
                if attempt == max_retries:
                    failed_downloads.append({'DOI': doi, 'Error': str(e)})
                else:
                    time.sleep(5)  # Wait before retrying

# Save the list of failed downloads to a CSV file
if failed_downloads:
    failed_df = pd.DataFrame(failed_downloads)
    failed_df.to_csv(missing_papers_file, index=False)
    print(f"\nFailed downloads have been logged to {missing_papers_file}")
else:
    print("\nAll PDFs downloaded successfully.")
end


* **********************************************************************
* 3 - get pdfs from open access publishers
* **********************************************************************

python
import pandas as pd
import requests
import os
import re
import time

# 1. Load the DOI prefixes for Open Access publishers
doi_prefixes_file = r"C:\Users\jdmichler\OneDrive - University of Arizona\weather_iv_lit\openalex\DOI_OA_publishers.xlsx"

try:
    prefix_df = pd.read_excel(doi_prefixes_file)
    # Use the correct column name 'doi_prefix'
    oa_prefixes = prefix_df['doi_prefix'].astype(str).tolist()
    print(f"Loaded {len(oa_prefixes)} Open Access DOI prefixes.")
except Exception as e:
    print(f"Error loading DOI prefixes: {e}")
    oa_prefixes = []

# Proceed only if oa_prefixes is successfully loaded
if not oa_prefixes:
    print("Error: 'oa_prefixes' is empty. Please check the Excel file and column name.")
else:
    # 2. Load data from the main Excel file
    excel_file = r"C:\Users\jdmichler\OneDrive - University of Arizona\weather_iv_lit\openalex\OpenAlex_Search_Results_Complete.xlsx"
    df = pd.read_excel(excel_file)

    # 3. Define the folder to save the PDFs
    output_folder = r"C:\Users\jdmichler\OneDrive - University of Arizona\weather_iv_lit\papers"
    os.makedirs(output_folder, exist_ok=True)

    # Define the folder and file to save the missing papers
    missing_papers_folder = r"C:\Users\jdmichler\OneDrive - University of Arizona\weather_iv_lit\openalex"
    missing_papers_file = os.path.join(missing_papers_folder, 'missing_papers.csv')

    # 4. Extract the DOI for each paper
    dois = df['ids_doi']

    # List to keep track of DOIs that failed to download, along with error messages
    failed_downloads = []

    # Your email address for the APIs
    email_address = 'jdmichler@arizona.edu'  # Your actual email address

    # Your CORE API key
    core_api_key = 'LAxfnJ5e8h1U7dpPXyKmMOzYqgBVtHTD'

    # Delay between requests in seconds
    request_delay = 0.5  # Adjust as needed

    # User-Agent string for CrossRef
    user_agent = 'UniversityOfArizonaWeatherIVLit/1.0 (mailto:jdmichler@arizona.edu)'

    for doi_url in dois:
        if isinstance(doi_url, str):
            doi_suffix = doi_url.replace('https://doi.org/', '')
            doi_prefix = '/'.join(doi_suffix.split('/')[:2])

            if any(doi_prefix.startswith(prefix) for prefix in oa_prefixes):
                # Initialize variables
                pdf_downloaded = False

                # 5. Use the Unpaywall API to find the Open Access PDF URL
                unpaywall_url = f"https://api.unpaywall.org/v2/{doi_suffix}?email={email_address}"
                try:
                    response = requests.get(unpaywall_url, timeout=30)
                    if response.status_code == 200:
                        data = response.json()
                        oa_locations = data.get('oa_locations', [])
                        pdf_url = None

                        # Find a PDF URL from the OA locations
                        for location in oa_locations:
                            if location.get('url_for_pdf'):
                                pdf_url = location['url_for_pdf']
                                break

                        if pdf_url:
                            # Download the PDF
                            pdf_response = requests.get(pdf_url, timeout=30)
                            if pdf_response.status_code == 200:
                                # Clean the DOI to create a valid filename
                                safe_filename = re.sub(r'[^\w\-_\. ]', '_', doi_suffix) + '.pdf'
                                filepath = os.path.join(output_folder, safe_filename)

                                # Save the PDF
                                with open(filepath, 'wb') as f:
                                    f.write(pdf_response.content)
                                print(f"Downloaded via Unpaywall: {safe_filename}")
                                pdf_downloaded = True
                            else:
                                print(f"Failed to download PDF from Unpaywall for {doi_url}. HTTP Status Code: {pdf_response.status_code}")
                        else:
                            print(f"No PDF URL found via Unpaywall for {doi_url}")
                    else:
                        print(f"Unpaywall API request failed for {doi_url}. HTTP Status Code: {response.status_code}")
                except requests.exceptions.RequestException as e:
                    print(f"Error accessing Unpaywall API for {doi_url}. Error: {e}")

                # Add delay to comply with rate limits
                time.sleep(request_delay)

                # If not downloaded, try CORE API
                if not pdf_downloaded:
                    # 6. Use the CORE API to find the Open Access PDF URL
                    core_search_url = f"https://api.core.ac.uk/v3/search/works"
                    headers = {
                        'Authorization': f'Bearer {core_api_key}',
                        'Content-Type': 'application/json'
                    }
                    params = {
                        'q': f'doi:"{doi_suffix}"',
                        'page': 1,
                        'pageSize': 1
                    }
                    try:
                        response = requests.get(core_search_url, headers=headers, params=params, timeout=30)
                        if response.status_code == 200:
                            data = response.json()
                            results = data.get('results', [])
                            if results:
                                full_text_url = results[0].get('fullTextIdentifier')
                                if full_text_url:
                                    # Download the PDF
                                    pdf_response = requests.get(full_text_url, timeout=30)
                                    if pdf_response.status_code == 200:
                                        # Clean the DOI to create a valid filename
                                        safe_filename = re.sub(r'[^\w\-_\. ]', '_', doi_suffix) + '.pdf'
                                        filepath = os.path.join(output_folder, safe_filename)

                                        # Save the PDF
                                        with open(filepath, 'wb') as f:
                                            f.write(pdf_response.content)
                                        print(f"Downloaded via CORE: {safe_filename}")
                                        pdf_downloaded = True
                                    else:
                                        print(f"Failed to download PDF from CORE for {doi_url}. HTTP Status Code: {pdf_response.status_code}")
                                        failed_downloads.append({'DOI': doi_url, 'Error': f'CORE PDF download failed with status code {pdf_response.status_code}'})
                                else:
                                    print(f"No full text URL found in CORE for {doi_url}")
                                    failed_downloads.append({'DOI': doi_url, 'Error': 'No full text URL found in CORE'})
                            else:
                                print(f"No results found in CORE for {doi_url}")
                                failed_downloads.append({'DOI': doi_url, 'Error': 'No results found in CORE'})
                        else:
                            print(f"CORE API request failed for {doi_url}. HTTP Status Code: {response.status_code}")
                            failed_downloads.append({'DOI': doi_url, 'Error': f'CORE API failed with status code {response.status_code}'})
                    except requests.exceptions.RequestException as e:
                        print(f"Error accessing CORE API for {doi_url}. Error: {e}")
                        failed_downloads.append({'DOI': doi_url, 'Error': f'CORE API error: {str(e)}'})

                    # Add delay to comply with rate limits
                    time.sleep(request_delay)

                # If still not downloaded, try CrossRef API
                if not pdf_downloaded:
                    # 7. Use the CrossRef API to find the PDF URL
                    crossref_url = f"https://api.crossref.org/works/{doi_suffix}"
                    headers = {
                        'User-Agent': user_agent
                    }
                    try:
                        response = requests.get(crossref_url, headers=headers, timeout=30)
                        if response.status_code == 200:
                            data = response.json()
                            message = data.get('message', {})
                            links = message.get('link', [])
                            pdf_url = None

                            # Find a link with content-type 'application/pdf'
                            for link in links:
                                if link.get('content-type') == 'application/pdf':
                                    pdf_url = link.get('URL')
                                    break

                            if pdf_url:
                                # Download the PDF
                                pdf_response = requests.get(pdf_url, headers=headers, timeout=30)
                                if pdf_response.status_code == 200:
                                    # Clean the DOI to create a valid filename
                                    safe_filename = re.sub(r'[^\w\-_\. ]', '_', doi_suffix) + '.pdf'
                                    filepath = os.path.join(output_folder, safe_filename)

                                    # Save the PDF
                                    with open(filepath, 'wb') as f:
                                        f.write(pdf_response.content)
                                    print(f"Downloaded via CrossRef: {safe_filename}")
                                    pdf_downloaded = True
                                else:
                                    print(f"Failed to download PDF from CrossRef for {doi_url}. HTTP Status Code: {pdf_response.status_code}")
                                    failed_downloads.append({'DOI': doi_url, 'Error': f'CrossRef PDF download failed with status code {pdf_response.status_code}'})
                            else:
                                print(f"No PDF URL found via CrossRef for {doi_url}")
                                failed_downloads.append({'DOI': doi_url, 'Error': 'No PDF URL found via CrossRef'})
                        else:
                            print(f"CrossRef API request failed for {doi_url}. HTTP Status Code: {response.status_code}")
                            failed_downloads.append({'DOI': doi_url, 'Error': f'CrossRef API failed with status code {response.status_code}'})
                    except requests.exceptions.RequestException as e:
                        print(f"Error accessing CrossRef API for {doi_url}. Error: {e}")
                        failed_downloads.append({'DOI': doi_url, 'Error': f'CrossRef API error: {str(e)}'})

                    # Add delay to comply with rate limits
                    time.sleep(request_delay)

                # If still not downloaded, log the failure
                if not pdf_downloaded:
                    print(f"Failed to download PDF for {doi_url} via Unpaywall, CORE, and CrossRef.")
                    # Error already logged in failed_downloads list
            else:
                print(f"DOI prefix does not match Open Access prefixes for {doi_url}")

    # Save the list of failed downloads to a CSV file
    if failed_downloads:
        failed_df = pd.DataFrame(failed_downloads)
        failed_df.to_csv(missing_papers_file, index=False)
        print(f"\nFailed downloads have been logged to {missing_papers_file}")
    else:
        print("\nAll PDFs downloaded successfully.")
end



/* END */