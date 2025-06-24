###
## This script splits the 80% training/validation data to  of total, training:validation
## Data are formatted as JSON files including prompt, source, and desired output for training
## JSON files are extracted as training.json and validation.json for fine tuning
###

import csv
import json
import os
import random

def prepare_fine_tuning_data(csv_input_path, training_output_path, validation_output_path, validation_split=0.1):
    if not os.path.isfile(csv_input_path):
        print(f"Input CSV file not found at {csv_input_path}")
        return

    required_columns = [
        'filename', 'paper title', 'doi', 'dependent variables', 'endogenous variable(s)',
        'instrumental variable used', 'instrumental variable(s)', 'instrumental variable rainfall',
        'rainfall metric', 'rainfall data source', 'dependent origin', 'endogenous origin',
        'instrument origin', 'rainfall metric origin', 'data source origin'
    ]

    data_entries = []
    encodings_to_try = ['utf-8-sig', 'utf-16', 'utf-16-le', 'utf-16-be', 'cp1252', 'latin1']

    for encoding in encodings_to_try:
        try:
            with open(csv_input_path, 'r', encoding=encoding) as csvfile:
                reader = csv.DictReader(csvfile)
                headers = reader.fieldnames

                missing_columns = [col for col in required_columns if col not in headers]
                if missing_columns:
                    print(f"Missing required columns: {', '.join(missing_columns)}")
                    return

                print(f"Successfully read the CSV file using encoding: {encoding}")

                for row in reader:
                    if not row.get('paper title') or not row.get('doi'):
                        print(
                            f"Skipping row due to missing critical information: {row.get('filename', 'Unknown file')}")
                        continue

                    messages = [
                        {
                            "role": "system",
                            "content": "You are an AI assistant that extracts specific information from academic papers. Answer the user's questions using the information from the provided texts. If the information is not available, respond with 'NA.'"
                        },
                        {
                            "role": "user",
                            "content": (
                                "Based on the following academic texts, please answer the questions below.\n\n"
                                f"Dependent Origin:\n{row.get('dependent origin', '')}\n\n"
                                f"Endogenous Origin:\n{row.get('endogenous origin', '')}\n\n"
                                f"Instrument Origin:\n{row.get('instrument origin', '')}\n\n"
                                f"Rainfall Metric Origin:\n{row.get('rainfall metric origin', '')}\n\n"
                                f"Data Source Origin:\n{row.get('data source origin', '')}\n\n"
                                "Questions:\n"
                                "1. What is the file name of the paper?\n"
                                "2. What is the title of the paper?\n"
                                "3. What is the DOI (Digital Object Identifier) of the paper?\n"
                                "4. What dependent variables are analyzed in this paper?\n"
                                "5. What are the endogenous variable(s) considered in this paper?\n"
                                "6. Did the study use an instrumental variable in the analysis?\n"
                                "7. What instrumental variable(s) were used in the study?\n"
                                "8. Was rainfall used as an instrumental variable in the study?\n"
                                "9. How exactly was rainfall quantified or measured as an instrument in this paper?\n"
                                "10. What is the source of the rainfall data used in the study?\n"
                            ).strip()
                        },
                        {
                            "role": "assistant",
                            "content": (
                                f"1. File Name: {row.get('filename', 'NA.')}\n"
                                f"2. Paper Title: {row.get('paper title', 'NA.')}\n"
                                f"3. DOI: {row.get('doi', 'NA.')}\n"
                                f"4. Dependent Variable(s): {row.get('dependent variables', 'NA.')}\n"
                                f"5. Endogenous Variable(s): {row.get('endogenous variable(s)', 'NA.')}\n"
                                f"6. IV Binary: {row.get('instrumental variable used', 'NA.')}\n"
                                f"7. Instrumental Variable(s): {row.get('instrumental variable(s)', 'NA.')}\n"
                                f"8. Rainfall Binary: {row.get('instrumental variable rainfall', 'NA.')}\n"
                                f"9. Rainfall Metric: {row.get('rainfall metric', 'NA.')}\n"
                                f"10. Rainfall Data Source: {row.get('rainfall data source', 'NA.')}\n"
                            ).strip()
                        }
                    ]

                    data_entries.append({"messages": messages})

                break
        except UnicodeError as e:
            print(f"Failed to read with encoding {encoding}: {e}")
        except Exception as e:
            print(f"An unexpected error occurred with encoding {encoding}: {e}")
    else:
        print("Unable to read the CSV file with the tried encodings.")
        return

    print("\nPreview of the first 3 data entries before writing to files:\n")
    for i, entry in enumerate(data_entries[:3]):
        print(f"Entry {i + 1}:")
        print(json.dumps(entry, indent=4, ensure_ascii=False))
        print('-' * 80)

    random.shuffle(data_entries)
    total_entries = len(data_entries)
    validation_size = int(total_entries * validation_split)
    training_size = total_entries - validation_size

    training_data = data_entries[:training_size]
    validation_data = data_entries[training_size:]

    os.makedirs(os.path.dirname(training_output_path), exist_ok=True)
    os.makedirs(os.path.dirname(validation_output_path), exist_ok=True)

    with open(training_output_path, 'w', encoding='utf-8') as train_file:
        for entry in training_data:
            json.dump(entry, train_file, ensure_ascii=False)
            train_file.write('\n')

    with open(validation_output_path, 'w', encoding='utf-8') as val_file:
        for entry in validation_data:
            json.dump(entry, val_file, ensure_ascii=False)
            val_file.write('\n')

    print(f"Training data has been written to {training_output_path}")
    print(f"Validation data has been written to {validation_output_path}")


def preview_jsonl_file(file_path, num_entries=3):
    print(f"\nPreviewing the first {num_entries} entries of {file_path}:\n")
    try:
        with open(file_path, 'r', encoding='utf-8') as f:
            for i in range(num_entries):
                line = f.readline()
                if not line:
                    break
                data = json.loads(line)
                print(f"Entry {i + 1}:")
                print(json.dumps(data, indent=4, ensure_ascii=False))
                print('-' * 80)
    except Exception as e:
        print(f"An error occurred while previewing the file: {e}")


# paths:
csv_input_path = '/Users/kieran/Library/CloudStorage/OneDrive-UniversityofArizona/weather_iv_lit/training/models/finetune_data/train_80.csv'
training_output_path = '/Users/kieran/Library/CloudStorage/OneDrive-UniversityofArizona/weather_iv_lit/training/models/finetune_data/training.jsonl'
validation_output_path = '/Users/kieran/Library/CloudStorage/OneDrive-UniversityofArizona/weather_iv_lit/training/models/finetune_data/validation.jsonl'

prepare_fine_tuning_data(csv_input_path, training_output_path, validation_output_path)
preview_jsonl_file(training_output_path, num_entries=30)
preview_jsonl_file(validation_output_path, num_entries=30)
