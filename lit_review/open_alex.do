* Project: WB Weather - metric 
* Created on: Jan 2024
* Created by: cda
* Last edited by: KD 5/30
* Stata v.18.0

* does
    * calls OpenAlex api to search literature

* assumes
    * 

* TO DO:
    * around line 74 needs to be changed to your email address 

* **********************************************************************
* 0 - setup
* **********************************************************************

* Define root folder globals
if `"`c(username)'"' == "jdmichler" {
    global code "C:/Users/jdmichler/git/AIDELabAZ/weather_metrics"
    global data "C:/Users/jdmichler/OneDrive - University of Arizona/weather_and_agriculture"
}

* Define root folder globals
if `"`c(username)'"' == "annal" {
    global code "C:/Users/aljosephson/git/weather_metrics"
    global data "C:/Users/aljosephson/OneDrive - University of Arizona/weather_and_agriculture"
}


global export "$data/output/metric_paper/literature"

python:
import os
print("Setting environment variable STATA_EXPORT to:", "$export")
os.environ['STATA_EXPORT'] = "$export"
print("Environment variable STATA_EXPORT is set to:", os.environ['STATA_EXPORT'])
end


*### Python Script

python
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

# Read the global variable from the environment
export_path = os.getenv('STATA_EXPORT')
if not export_path:
    raise ValueError("Environment variable STATA_EXPORT is not set")

# Define the output path using the global variable
output_path = os.path.join(export_path, "OpenAlex_Search_Results.xlsx")

# Create the directory if it does not exist
os.makedirs(os.path.dirname(output_path), exist_ok=True)

# Base URL for the OpenAlex API with the specified parameters, including the mailto parameter
base_url = "https://api.openalex.org/works?filter=default.search:((Weather)+AND+(Instrumental+Variable))+OR+((Rainfall)+AND+(Instrumental+Variable)),language:languages/en,primary_topic.domain.id:domains/2,primary_topic.field.id:fields/20&mailto=aljosephson@arizona.edu&per-page=200&cursor={}"

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
            all_works.extend(results)
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
selected_columns = [col for col in df.columns if col.count('_') < 3]
df = df[selected_columns]

# Save the DataFrame to an Excel file
df.to_excel(output_path, index=False)

print(f"Data saved to {output_path}")
end