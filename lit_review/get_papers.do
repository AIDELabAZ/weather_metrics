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
import pandas as pd
from selenium import webdriver
from selenium.webdriver.chrome.service import Service
from selenium.webdriver.common.by import By
from selenium.webdriver.chrome.options import Options
from selenium.webdriver.support.ui import WebDriverWait
from selenium.webdriver.support import expected_conditions as EC
from bs4 import BeautifulSoup
from urllib.parse import urljoin

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
        doi_url = f"https://doi.org/{doi}"
        driver.get(doi_url)
        # Wait for the page to load
        WebDriverWait(driver, 10).until(EC.presence_of_element_located((By.TAG_NAME, "body")))
        soup = BeautifulSoup(driver.page_source, 'html.parser')
        
        # Print out the title of the current page for debugging
        print(f"Page title: {driver.title}")
        
        # Attempt to find a direct PDF link
        pdf_link = soup.find('a', href=True, string='PDF')
        if pdf_link:
            full_pdf_url = urljoin(driver.current_url, pdf_link['href'])
            print(f"Found direct PDF link: {full_pdf_url}")
            return full_pdf_url
        
        # Attempt to find any link that contains 'pdf' in the URL
        for link in soup.find_all('a', href=True):
            if 'pdf' in link['href']:
                full_pdf_url = urljoin(driver.current_url, link['href'])
                print(f"Found PDF link containing 'pdf': {full_pdf_url}")
                return full_pdf_url
        
        print(f"No PDF link found for {doi_url}")
    except Exception as e:
        print(f"Error navigating to {doi_url}: {e}")
    return None

# List to hold the results
results = []

# Get PDF URLs for all DOIs
for doi in doi_urls:
    print(f"Processing DOI: {doi}")
    pdf_url = get_pdf_url_from_doi(doi)
    results.append({'doi': doi, 'pdf_url': pdf_url})
    print(f'PDF URL for {doi}: {pdf_url}')

# Close the WebDriver
driver.quit()

# Convert results to a DataFrame
df_output = pd.DataFrame(results)

# Path to save the results
output_path = r'C:\Users\jdmichler\OneDrive - University of Arizona\weather_and_agriculture\output\metric_paper\literature\pdf_urls.xlsx'

# Save the results to an Excel file
df_output.to_excel(output_path, index=False)

print(f'Results saved to {output_path}')

end