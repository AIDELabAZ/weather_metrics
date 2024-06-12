* Project: WB Weather - metric 
* Created on: June 2024
* Created by: jdm
* Last edited by: 10 June 2024
* Edited by: jdm
* Stata v.18.0

* does
    * downloads the PDF from the pdf url file

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
install("webdriver-manager")
install("openpyxl")
end
*/
* **********************************************************************
* 1 - get pdfs
* **********************************************************************

python
import os
import pandas as pd
import requests
from time import sleep
from random import randint

# Path to the input Excel file
input_excel_path = r'C:\Users\jdmichler\OneDrive - University of Arizona\weather_and_agriculture\output\metric_paper\literature\pdf_urls.xlsx'

# Directory where the PDFs will be saved
directory = r'C:\Users\jdmichler\OneDrive - University of Arizona\weather_and_agriculture\output\metric_paper\literature\output'

# Path to save the URLs that couldn't be downloaded
missing_urls_path = r'C:\Users\jdmichler\OneDrive - University of Arizona\weather_and_agriculture\output\metric_paper\literature\missing.xlsx'

# Read the Excel file to get the PDF URLs
df_input = pd.read_excel(input_excel_path)
pdf_urls = df_input['pdf_url'].dropna().unique()

# List to hold the URLs that couldn't be downloaded
missing_urls = []

# Function to download a PDF directly
def download_pdf(url, save_path):
    headers = {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/58.0.3029.110 Safari/537.3',
        'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8',
        'Accept-Language': 'en-US,en;q=0.5',
        'Connection': 'keep-alive'
    }
    try:
        response = requests.get(url, headers=headers)
        response.raise_for_status()  # Will raise HTTPError for bad responses
        with open(save_path, 'wb') as out_file:
            out_file.write(response.content)
        print(f'PDF downloaded and saved to {save_path}')
        return True  # Exit function if successful
    except requests.exceptions.RequestException as e:
        print(f'Direct download failed for {url}: {e}')
        return False

# Function to process each URL
def process_url(pdf_url):
    # Extract the DOI from the URL
    doi = pdf_url.split('/')[-1]
    save_path = os.path.join(directory, f'{doi}.pdf')
    
    # Attempt direct download first
    if download_pdf(pdf_url, save_path):
        return True
    
    # If direct download fails, add URL to missing URLs list
    missing_urls.append(pdf_url)
    return False

# Loop through each PDF URL and download the PDF
for pdf_url in pdf_urls:
    if not pd.isna(pdf_url) and pdf_url != '':
        process_url(pdf_url)

# Save the missing URLs to an Excel file
df_missing = pd.DataFrame(missing_urls, columns=['missed_pdf'])
df_missing.to_excel(missing_urls_path, index=False)

print(f'Missing URLs saved to {missing_urls_path}')

end