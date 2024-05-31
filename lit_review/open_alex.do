* Project: WB Weather - metric 
* Created on: Jan 2024
* Created by: cda
* Last edited by: KD on Mac
* Stata v.18.0

* does
	* calls OpenAlex api to search literature

* assumes
	* 

* TO DO:
	* 


* **********************************************************************
* 0 - setup
* **********************************************************************
// Path to the GitHub repository
global github_path "/Users/kieran/Documents/GitHub/weather_metrics"

// Path to the output folder
global output_path "/Users/kieran/Library/CloudStorage/OneDrive-UniversityofArizona/weather_and_agriculture/output/metric_paper"

* **********************************************************************
* 1 - start PyStata
* **********************************************************************
// Start PyStata 






python:
import requests
import csv

# Define the URL for the OpenAlex API query
url = 'https://api.openalex.org/works?page=1&filter=default.search:((Weather)+AND+(Instrumentation))+AND+(primary_topic.domain.id:domains/2,primary_topic.field.id:fields/20)'
response = requests.get(url)
data = response.json()

# Specify the file path
file_path = '/Users/kieran/Library/CloudStorage/OneDrive-UniversityofArizona/weather_and_agriculture/output/metric_paper/output.csv'

# Write data to CSV
with open(file_path, 'w', newline='') as csvfile:
    writer = csv.writer(csvfile)
    # Write headers
    writer.writerow(data['results'][0].keys())
    # Write data rows
    for item in data['results']:
        writer.writerow(item.values())
end


*stata // Start PyStata 
python: 
import requests 
import csv url = 'https://api.openalex.org/works?page=1&filter=default.search:((Weather)+AND+
(Instrumentation))' 
response = requests.get(url) 
data = response.json #
file_path = '/Users/kieran/Library/CloudStorage/OneDrive-UniversityofArizona/weather_and_agriculture/output/metric_paper/output.csv'
* Write data to CSV with
open(file _path, 'w', newline=") as csvfile: writer = csv.writer(csvfile) 
* Write headers 
writer.writerow(data['results'][O].keys) 
* Write data rows for item in 
data['results']: writer.writerow(item.values)) 
end 
