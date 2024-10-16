import pandas as pd
import jsonlines
import os
import chardet
import pprint

# Declare input and output files
input_csv = '/Users/kieran/Library/CloudStorage/OneDrive-UniversityofArizona/weather_iv_lit/training/finetune1/finetune1_data/training2_data.csv'
output_folder = '/Users/kieran/Library/CloudStorage/OneDrive-UniversityofArizona/weather_iv_lit/training/finetune1/finetune1_data'
train_filename = 'training_train.jsonl'
validation_filename = 'training_validation.jsonl'

# Combine the folder path and file names to create the full output paths
output_train_jsonl = os.path.join(output_folder, train_filename)
output_validation_jsonl = os.path.join(output_folder, validation_filename)

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

# Shuffle the DataFrame
df_shuffled = df.sample(frac=1, random_state=42).reset_index(drop=True)

# Split the DataFrame into 80% training and 20% validation
split_ratio = 0.8
split_index = int(len(df_shuffled) * split_ratio)
train_df = df_shuffled.iloc[:split_index]
validation_df = df_shuffled.iloc[split_index:]

print(f"Total samples: {len(df_shuffled)}")
print(f"Training samples: {len(train_df)}")
print(f"Validation samples: {len(validation_df)}")

def create_jsonl(df, output_path):
    with jsonlines.open(output_path, mode='w') as writer:
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
            inst_section = str(row.get('instrument section', '')).strip()
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

            # Construct the user message
            user_message = f"""Extract the following information from the text:

{origin_texts}

Information to extract:
- Dependent Variables
- Endogenous Variables
- Instrumental Variables
- Rainfall Metric
- Data Source
"""

            # Construct the assistant message (completion)
            assistant_message = f"""Dependent Variables: {row.get('dependent variables', '').strip()}
Endogenous Variables: {row.get('endogenous variable(s)', '').strip()}
Instrumental Variables: {row.get('instrumental variable(s)', '').strip()}
Rainfall Metric: {row.get('rainfall metric', '').strip()}
Data Source: {row.get('rainfall data source', '').strip()}
"""

            # Create the JSON object in chat format
            json_obj = {
                "messages": [
                    {"role": "system", "content": "You are an AI that extracts specific data from text."},
                    {"role": "user", "content": user_message},
                    {"role": "assistant", "content": assistant_message}
                ]
            }

            # Write the JSON object to the JSONL file
            writer.write(json_obj)

# Create JSONL files for training and validation
create_jsonl(train_df, output_train_jsonl)
create_jsonl(validation_df, output_validation_jsonl)

# Optionally, print the first few entries of each JSONL file to verify
def print_jsonl_contents(file_path, num_entries=3):
    print(f"\n--- Displaying first {num_entries} entries of {file_path} ---\n")
    with jsonlines.open(file_path) as reader:
        for i, obj in enumerate(reader):
            if i >= num_entries:
                break
            print("\nMessages:")
            pprint.pprint(obj['messages'])
            print("-" * 80)

print_jsonl_contents(output_train_jsonl)
print_jsonl_contents(output_validation_jsonl)
