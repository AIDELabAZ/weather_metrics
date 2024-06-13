* Project: WB Weather - metric 
* Created on: Jan 2024
* Created by: cda
* Last edited by: KD 5/30
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

global export "$data/output/metric_paper/literature"

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
* 1 - python script
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

# Create the directory if it does not exist
os.makedirs(os.path.dirname(base_output_path), exist_ok=True)

# Base URL for the OpenAlex API with the specified parameters, including the mailto parameter
base_url = f"https://api.openalex.org/works?filter=default.search:((Weather)+AND+(Instrumental+Variable))+OR+((Rainfall)+AND+(Instrumental+Variable)),language:languages/en,primary_topic.domain.id:domains/2,primary_topic.field.id:fields/20&mailto={user_email}&per-page=200&cursor={{}}"

all_works = []
cursor = '*'
total_results = 0
request_count = 0

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
                work['primary_location_pdf_url'] = pdf_url
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
selected_columns = [col for col in df.columns if col.count('_') < 3] + ['primary_location_pdf_url']
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
