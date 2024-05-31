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
python:

#Import requests and call API
import requests

response = requests.get('https://api.openalex.org/works?page=1&filter=default.search:((Weather)+AND+(Instrumen[…]y_topic.domain.id:domains/2,primary_topic.field.id:fields/20')
## Test if the connection was successful

print(response.status_code)
## Returns 500, problem with server for API?
end


