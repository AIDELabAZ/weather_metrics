* Project: WB Weather - metric 
* Created on: Jan 2024
* Created by: cda
* Last edited by: KD 5/30
* Stata v.18.0

* does
    * searches for papers from OpenAlex search results

* assumes
    * 

* TO DO:
    * 

* **********************************************************************
* 0 - setup
* **********************************************************************


*### Python Script

python
import os
import time
import pandas as pd
import requests
from bs4 import BeautifulSoup
from selenium import webdriver
from selenium.webdriver.chrome.service import Service
from selenium.webdriver.common.by import By
from selenium.webdriver.chrome.options import Options
from selenium.webdriver.support.ui import WebDriverWait
from selenium.webdriver.support import expected_conditions as EC
import subprocess
import sys

# Function to install a package
def install(package):
    subprocess.check_call([sys.executable, "-m", "pip", "install", package])

# Install required packages
packages = ["pandas", "requests", "openpyxl", "beautifulsoup4", "selenium"]
for package in packages:
    try:
        __import__(package)
    except ImportError:
        install(package)

# Path to the ChromeDriver
chrome_driver_path = r"C:\Users\jdmichler\AppData\Local\Google\Chrome\chromedriver.exe"  # Updated path to your chromedriver

# Initialize Chrome WebDriver
options = Options()
options.headless = True
service = Service(chrome_driver_path)
driver = webdriver.Chrome(service=service, options=options)

# Updated input path
input_path = r"C:\Users\jdmichler\OneDrive - University of Arizona\weather_and_agriculture\output\metric_paper\literature\OpenAlex_Search_Results_test.xlsx"
try:
    print(f"Attempting to read the Excel file from: {input_path}")
    df = pd.read_excel(input_path)
    print("Excel file read successfully.")
except PermissionError:
    print(f"PermissionError: Unable to access the file at {input_path}. Please ensure the file is not open in another program and you have the necessary permissions.")
    sys.exit(1)
except Exception as e:
    print(f"An error occurred while reading the Excel file: {e}")
    sys.exit(1)

# Extract DOI addresses
dois = df['doi'].dropna().unique()

# Directory to save PDFs
output_dir = r"C:\Users\jdmichler\OneDrive - University of Arizona\weather_and_agriculture\output\metric_paper\literature\output"
os.makedirs(output_dir, exist_ok=True)

# Function to download PDF from a URL
def download_pdf(pdf_url, output_path):
    response = requests.get(pdf_url)
    if response.status_code == 200:
        with open(output_path, 'wb') as file:
            file.write(response.content)
        print(f"Downloaded PDF from {pdf_url} to {output_path}")
    else:
        print(f"Failed to download PDF from {pdf_url}")

# Function to navigate to DOI and find PDF link
def get_pdf_url_from_doi(doi_url):
    try:
        driver.get(doi_url)
        # Wait for the page to load
        WebDriverWait(driver, 10).until(EC.presence_of_element_located((By.TAG_NAME, "body")))
        soup = BeautifulSoup(driver.page_source, 'html.parser')
        # Attempt to find a direct PDF link
        pdf_link = soup.find('a', href=True, string='PDF')
        if pdf_link:
            return pdf_link['href']
        # Attempt to find any link that contains 'pdf' in the URL
        for link in soup.find_all('a', href=True):
            if 'pdf' in link['href']:
                return link['href']
    except Exception as e:
        print(f"Error navigating to {doi_url}: {e}")
    return None

# Process each DOI
for doi in dois:
    # Ensure the DOI is correctly formatted
    doi = doi.strip()  # Remove any leading/trailing whitespace
    doi = doi.replace('https://doi.org/', '')  # Remove the https://doi.org/ prefix if present
    if not doi.startswith("10."):
        print(f"Skipping invalid DOI: {doi}")
        continue
    doi_url = f"https://doi.org/{doi}"
    print(f"Processing DOI: {doi_url}")
    pdf_url = get_pdf_url_from_doi(doi_url)
    if pdf_url:
        print(f"Found PDF URL: {pdf_url}")
        try:
            # Ensure the PDF URL is absolute
            if not pdf_url.startswith('http'):
                pdf_url = f"https://doi.org{pdf_url}"
            file_name = f"{doi.replace('/', '_')}.pdf"
            output_path = os.path.join(output_dir, file_name)
            download_pdf(pdf_url, output_path)
        except Exception as e:
            print(f"Failed to download {doi} directly: {e}")
            # Use proxy URL to attempt download
            proxy_url = f"http://ezproxy.library.arizona.edu/login?url={pdf_url}"
            try:
                download_pdf(proxy_url, output_path)
                print(f"Downloaded with proxy: {doi}")
            except Exception as proxy_e:
                print(f"Failed to download with proxy {doi}: {proxy_e}")
    else:
        print(f"No PDF found for {doi}")

driver.quit()
end