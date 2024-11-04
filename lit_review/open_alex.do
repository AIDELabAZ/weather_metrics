* Project: WB Weather - metric 
* Created on: Jan 2024
* Created by: cda
* Edited by: jdm
* Edited on: 10 Sept 2024
* Stata v.18.0

* does
    * calls OpenAlex api to search literature

* assumes
    * python installed on machine

* TO DO:
    * done

* **********************************************************************
* 0 - setup
* **********************************************************************

* set relative path for output in stata
	global 			export "$data/openalex"

* set up relative paths in python
python:
import os

# Set output path using Stata global
print("Setting environment variable STATA_EXPORT to:", "$export")
os.environ['STATA_EXPORT'] = "$export"
print("Environment variable STATA_EXPORT is set to:", os.environ['STATA_EXPORT'])

# Set user email using Stata global
print("Setting environment variable USER_EMAIL to:", "$email")
os.environ['USER_EMAIL'] = "$email"
print("Environment variable USER_EMAIL is set to:", os.environ['USER_EMAIL'])

import subprocess
import sys
import requests
import pandas as pd
import os
import time

# Function to install a package
def install(package):
    subprocess.check_call([sys.executable, "-m", "pip", "install", package])

# Install pandas and openpyxl if not already installed
install("pandas")
install("openpyxl")
install("requests")
end


* **********************************************************************
* 1 - access openalex via api and search database
* **********************************************************************

python
import requests
import pandas as pd
import os
import time

# Set the user email
user_email = os.getenv('USER_EMAIL')

# Read the global variable from the environment
export_path = os.getenv('STATA_EXPORT')
if not export_path:
    raise ValueError("Environment variable STATA_EXPORT is not set")

# Define the base output path using the global variable
base_output_path = os.path.join(export_path, "OpenAlex_Search_Results")

# Directory to save downloaded PDFs
pdf_save_dir = r"C:\Users\jdmichler\OneDrive - University of Arizona\weather_iv_lit\papers"
os.makedirs(pdf_save_dir, exist_ok=True)

# Base URL for the OpenAlex API with the specified parameters, including the mailto parameter
base_url = f"https://api.openalex.org/works?filter=default.search:((Weather)+AND+(Instrumental+Variable))+OR+((Rainfall)+AND+(Instrumental+Variable)),language:languages/en,primary_topic.domain.id:domains/2,primary_topic.field.id:fields/20&mailto={user_email}&per-page=200&cursor={{}}"

all_works = []
cursor = '*'
total_results = 0
request_count = 0

def download_pdf(pdf_url, save_dir, title):
    """Attempts to download a PDF from the given URL to the specified directory."""
    if not pdf_url.endswith(".pdf"):
        return "no"
    try:
        pdf_path = os.path.join(save_dir, title.replace(" ", "_") + ".pdf")
        response = requests.get(pdf_url, stream=True)
        response.raise_for_status()
        with open(pdf_path, "wb") as pdf_file:
            for chunk in response.iter_content(chunk_size=1024):
                pdf_file.write(chunk)
        return "yes"
    except Exception as e:
        print(f"Failed to download PDF: {pdf_url}. Error: {e}")
        return "no"

while cursor:
    url = base_url.format(cursor)
    response = requests.get(url)
    request_count += 1

    if response.status_code == 200:
        data = response.json()
        results = data.get("results", [])
        if results is not None:
            for work in results:
                primary_location = work.get('primary_location') or {}
                pdf_url = primary_location.get('pdf_url', '')
                
                # Attempt to download PDF if a valid URL exists
                downloaded = "no"
                if pdf_url:
                    title = work.get("title", "unnamed_paper")
                    downloaded = download_pdf(pdf_url, pdf_save_dir, title)
                
                # Add download status and PDF URL to work dictionary
                work['primary_location_pdf_url'] = pdf_url
                work['downloaded'] = downloaded
                all_works.append(work)
            total_results += len(results)
        
        cursor = data.get("meta", {}).get("next_cursor")
        
        print(f"Cursor: {cursor}, Total Results: {total_results}, Request Count: {request_count}")
        
        if not cursor or len(results) == 0:
            break
        
        # Sleep to avoid rate limiting (10 requests per second)
        if request_count % 10 == 0:
            time.sleep(1)
    else:
        print(f"Failed to retrieve data: {response.status_code}")
        break

print(f"Total works retrieved: {total_results}")

# Normalize JSON data with limited depth
df = pd.json_normalize(all_works, sep='_')

# Select only relevant columns (example columns, adjust as necessary)
selected_columns = [col for col in df.columns if col.count('_') < 3] + ['primary_location_pdf_url', 'downloaded']
df = df[selected_columns]

# Split the DataFrame into chunks of 850 rows each
chunk_size = 850
num_chunks = (len(df) + chunk_size - 1) // chunk_size

for i in range(num_chunks):
    chunk = df.iloc[i*chunk_size:(i+1)*chunk_size]
    output_path = f"{base_output_path}{i+1}.xlsx"
    chunk.to_excel(output_path, index=False)
    print(f"Data saved to {output_path}")

print("All data saved to separate Excel files.")

end

* **********************************************************************
* 2 - combine output into single file
* **********************************************************************

python
import pandas as pd
import os

# List of Excel files to combine
file_names = [
    'OpenAlex_Search_Results1.xlsx',
    'OpenAlex_Search_Results2.xlsx',
    'OpenAlex_Search_Results3.xlsx',
    'OpenAlex_Search_Results4.xlsx',
    'OpenAlex_Search_Results5.xlsx'
]

# Initialize an empty list to hold dataframes
dfs = []

# Load each file and append its dataframe to the list
for file_name in file_names:
    file_path = os.path.join(export_path, file_name)
    df = pd.read_excel(file_path)
    dfs.append(df)

# Concatenate all the dataframes into a single dataframe
combined_df = pd.concat(dfs, ignore_index=True)

# Define the output file path for the combined result
output_file = os.path.join(export_path, 'OpenAlex_Search_Results_Complete.xlsx')

# Save the combined dataframe to a new Excel file
combined_df.to_excel(output_file, index=False)

print(f"Combined file saved to {output_file}")
end

