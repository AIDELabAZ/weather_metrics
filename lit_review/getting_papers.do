* Project: WB Weather - metric 
* Created on: Jan 2024
* Created by: cda
* Last edited by: KD 5/30
* Stata v.18.0

* does
    * searches for papers from OpenAlex search results

* assumes
    * anaconda (python) installed
	* chromedriver installed

* TO DO:
    * 

* **********************************************************************
* 0 - setup
* **********************************************************************


*### Python Script

python
import os
import pandas as pd
from selenium import webdriver
from selenium.webdriver.chrome.service import Service
from selenium.webdriver.common.by import By
from selenium.webdriver.chrome.options import Options
from selenium.webdriver.support.ui import WebDriverWait
from selenium.webdriver.support import expected_conditions as EC

# Path to the ChromeDriver
chrome_driver_path = r"C:\Users\jdmichler\AppData\Local\Google\Chrome\chromedriver.exe"  # Update path to your chromedriver

# Initialize Chrome WebDriver
options = Options()
options.headless = False  # Set to False to see the browser actions
service = Service(chrome_driver_path)
driver = webdriver.Chrome(service=service, options=options)

# Path to the input Excel file
input_path = r"C:\Users\jdmichler\OneDrive - University of Arizona\weather_and_agriculture\output\metric_paper\literature\OpenAlex_Search_Results_test.xlsx"

# Path to save PDFs
output_dir = r"C:\Users\jdmichler\OneDrive - University of Arizona\weather_and_agriculture\output\metric_paper\literature\output"
os.makedirs(output_dir, exist_ok=True)

# Read the Excel file
try:
    df = pd.read_excel(input_path)
    print("Excel file read successfully.")
except Exception as e:
    print(f"An error occurred while reading the Excel file: {e}")
    driver.quit()
    sys.exit(1)

# Extract DOI addresses
dois = df['doi'].dropna().unique()
if len(doi
end