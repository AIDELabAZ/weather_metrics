import pandas as pd
import jsonlines
import os
import chardet

# Declare input and output files
input_csv = '/Users/kieran/Library/CloudStorage/OneDrive-UniversityofArizona/weather_iv_lit/training/finetune1/finetune1_data/training1_data.csv'
output_folder = '/Users/kieran/Library/CloudStorage/OneDrive-UniversityofArizona/weather_iv_lit/training/finetune1/finetune1_data'
output_filename = 'training1_jsonldata.jsonl'

# Combine the folder path and file name to create the full output path
output_jsonl = os.path.join(output_folder, output_filename)

# Create the output folder if it doesn't exist
os.makedirs(output_folder, exist_ok=True)

# Detect the file encoding
with open(input_csv, 'rb') as f:
    result = chardet.detect(f.read(100000))
    detected_encoding = result['encoding']
    print(f"Detected encoding: {detected_encoding}")

# Read the CSV file into a DataFrame with the detected encoding
df = pd.read_csv(input_csv, encoding=detected_encoding)

# Replace NaN with empty strings
df = df.fillna('')

# Open a JSONL file for writing
with jsonlines.open(output_jsonl, mode='w') as writer:
    for index, row in df.iterrows():
        # Extract origin texts and sections
        origin_texts = ''

        # Dependent Variable
        dep_origin = str(row.get('dependent origin', '')).strip()
        dep_section = str(row.get('dependent section', '')).strip()
        if dep_origin:
            origin_texts += f"Dependent Variable (Section: {dep_section}): {dep_origin}\n"

        # Endogenous Variable
        endo_origin = str(row.get('endogenous origin', '')).strip()
        endo_section = str(row.get('endogenous section', '')).strip()
        if endo_origin:
            origin_texts += f"Endogenous Variable (Section: {endo_section}): {endo_origin}\n"

        # Instrumental Variable
        inst_origin = str(row.get('instrument origin', '')).strip()
        inst_section = str(row.get('instrument section', '')).strip()  # Ensure correct column name
        if inst_origin:
            origin_texts += f"Instrumental Variable (Section: {inst_section}): {inst_origin}\n"

        # Rainfall Metric
        metric_origin = str(row.get('rainfall metric origin', '')).strip()
        metric_section = str(row.get('metric section', '')).strip()
        if metric_origin:
            origin_texts += f"Rainfall Metric (Section: {metric_section}): {metric_origin}\n"

        # Data Source
        data_origin = str(row.get('data source origin', '')).strip()
        data_section = str(row.get('data source section', '')).strip()
        if data_origin:
            origin_texts += f"Data Source (Section: {data_section}): {data_origin}\n"

        # Construct the prompt
        prompt = f"""Extract the following information from the text:

{origin_texts}

Information to extract:
- Dependent Variables
- Endogenous Variables
- Instrumental Variables
- Rainfall Metric
- Data Source
"""
        # Construct the completion
        completion = f"""Dependent Variables: {row.get('dependent variables', '').strip()}
Endogenous Variables: {row.get('endogenous variable(s)', '').strip()}
Instrumental Variables: {row.get('instrumental variable(s)', '').strip()}
Rainfall Metric: {row.get('rainfall metric', '').strip()}
Data Source: {row.get('rainfall data source', '').strip()}
"""
        # Create the JSON object
        json_obj = {
            "prompt": prompt,
            "completion": completion
        }

        # Write the JSON object to the JSONL file
        writer.write(json_obj)
####################################################################################################
### display contents of json to check conversion
####################################################################################################
import jsonlines
import pprint

# Specify the path to your JSONL file
jsonl_file = '/Users/kieran/Library/CloudStorage/OneDrive-UniversityofArizona/weather_iv_lit/training/finetune1/finetune1_data/training1_jsonldata.jsonl'

# Open and read the JSONL file
with jsonlines.open(jsonl_file) as reader:
    for obj in reader:
        print("Prompt:")
        print(obj['prompt'])
        print("\nCompletion:")
        print(obj['completion'])
        print("-" * 80)

