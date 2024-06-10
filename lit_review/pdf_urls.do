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

# Path to the ChromeDriver
chrome_driver_path = r'C:\Users\jdmichler\AppData\Local\Google\Chrome\chromedriver.exe'

# Configure Chrome options
chrome_options = Options()
# Remove headless to allow manual intervention
# chrome_options.add_argument('--headless')
chrome_options.add_argument('--disable-gpu')  # Disable GPU acceleration

# Set up the WebDriver
service = Service(chrome_driver_path)
driver = webdriver.Chrome(service=service, options=chrome_options)

# Path to the input Excel file
input_excel_path = r'C:\Users\jdmichler\OneDrive - University of Arizona\weather_and_agriculture\output\metric_paper\literature\OpenAlex_Search_Results_test2.xlsx'

# Read the Excel file to get the DOIs
df_input = pd.read_excel(input_excel_path)
doi_urls = df_input['doi'].dropna().unique()

# Function to navigate to DOI and find PDF link
def get_pdf_url_from_doi(doi):
    try:
        if '10.3386' in doi:
            return f"https://doi.org/{doi}"  # Directly use the DOI as the PDF URL

        doi_url = f"https://doi.org/{doi}"
        driver.get(doi_url)

        # Wait for the page to load and handle redirects
        WebDriverWait(driver, 10).until(EC.presence_of_element_located((By.TAG_NAME, "body")))
        soup = BeautifulSoup(driver.page_source, 'html.parser')

        # Print out the title of the current page for debugging
        page_title = driver.title
        print(f"Page title: {page_title}")

        # Handle CAPTCHA by constructing the URL directly
        if page_title.lower() == "just a moment...":
            current_url = driver.current_url
            doi_suffix = doi.split('doi.org/')[-1]  # Extract the suffix of the DOI after 'doi.org/'
            if 'onlinelibrary.wiley.com' in current_url:
                pdf_url = f"https://onlinelibrary.wiley.com/doi/epdf/{doi_suffix}"
                print(f"Constructed PDF URL for Wiley: {pdf_url}")
                return pdf_url
            elif 'journals.uchicago.edu' in current_url:
                pdf_url = f"https://www.journals.uchicago.edu/doi/epdf/{doi_suffix}"
                print(f"Constructed PDF URL for UChicago: {pdf_url}")
                return pdf_url
            elif '10.1257' in doi:
                pdf_url = f"https://www.aeaweb.org/articles/pdf/doi/{doi_suffix}"
                print(f"Constructed PDF URL for AEA: {pdf_url}")
                return pdf_url

        # Search for links that end with .pdf or contain /epdf/
        pdf_links = soup.find_all('a', href=True)
        for link in pdf_links:
            href = link['href']
            if href.endswith('.pdf') or '/epdf/' in href:
                if not href.startswith('http'):
                    href = driver.current_url.split('/doi/')[0] + href
                print(f"Found PDF link: {href}")
                return href

        print(f"No PDF link found for {doi_url}")
    except Exception as e:
        print(f"Error navigating to {doi_url}: {e}")
    return None

# Lists to hold the results and missing DOIs
results = []
missing_dois = []

# Get PDF URLs for all DOIs
for doi in doi_urls:
    print(f"Processing DOI: {doi}")
    pdf_url = get_pdf_url_from_doi(doi)
    if pdf_url is None:
        missing_dois.append(doi)
    results.append({'doi': doi, 'pdf_url': pdf_url})
    print(f'PDF URL for {doi}: {pdf_url}')

# Close the WebDriver
driver.quit()

# Convert results to a DataFrame
df_output = pd.DataFrame(results)

# Path to save the results
output_path = r'C:\Users\jdmichler\OneDrive - University of Arizona\weather_and_agriculture\output\metric_paper\literature\pdf_urls.xlsx'

# Save the results to an Excel file, overwriting the old version
df_output.to_excel(output_path, index=False)

print(f'Results saved to {output_path}')

# Convert missing DOIs to a DataFrame
df_missing = pd.DataFrame(missing_dois, columns=['doi'])

# Path to save the missing DOIs
missing_output_path = r'C:\Users\jdmichler\OneDrive - University of Arizona\weather_and_agriculture\output\metric_paper\literature\missing_url.xlsx'

# Save the missing DOIs to an Excel file, overwriting the old version
df_missing.to_excel(missing_output_path, index=False)

print(f'Missing DOIs saved to {missing_output_path}')

end