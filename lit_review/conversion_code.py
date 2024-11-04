import csv
import json
import os
import random

def prepare_fine_tuning_data(csv_input_path, training_output_path, validation_output_path, validation_split=0.2):
    # Check if the input CSV file exists
    if not os.path.isfile(csv_input_path):
        print(f"Input CSV file not found at {csv_input_path}")
        return

    data_entries = []

    # Try reading the CSV file with different encodings
    encodings_to_try = ['utf-8-sig', 'utf-16', 'utf-16-le', 'utf-16-be', 'cp1252', 'latin1']
    for encoding in encodings_to_try:
        try:
            with open(csv_input_path, 'r', encoding=encoding) as csvfile:
                reader = csv.DictReader(csvfile)
                first_row = next(reader)
                csvfile.seek(0)
                reader = csv.DictReader(csvfile)
                print(f"Successfully read the CSV file using encoding: {encoding}")

                # Process the CSV data inside the with block
                for row in reader:
                    # Extract the context sections from the row
                    dependent_origin = row.get('dependent origin', '')
                    endogenous_origin = row.get('endogenous origin', '')
                    instrument_origin = row.get('instrument origin', '')
                    rainfall_metric_origin = row.get('rainfall metric origin', '')
                    data_source_origin = row.get('data source origin', '')

                    # Construct the messages for chat format
                    messages = [
                        {
                            "role": "system",
                            "content": (
                                "You are an AI assistant that extracts specific information from academic papers. "
                                "Answer the user's questions using the information from the provided texts. If the information is not available, respond with 'NA.'"
                            )
                        },
                        {
                            "role": "user",
                            "content": (
                                "Based on the following academic texts, please answer the questions below.\n\n"
                                "Dependent Origin:\n"
                                f"{dependent_origin}\n\n"
                                "Endogenous Origin:\n"
                                f"{endogenous_origin}\n\n"
                                "Instrument Origin:\n"
                                f"{instrument_origin}\n\n"
                                "Rainfall Metric Origin:\n"
                                f"{rainfall_metric_origin}\n\n"
                                "Data Source Origin:\n"
                                f"{data_source_origin}\n\n"
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
                                f"1. File Name: {row.get('File Name', 'NA.')}\n"
                                f"2. Paper Title: {row.get('paper title', 'NA.')}\n"
                                f"3. DOI: {row.get('doi', 'NA.')}\n"
                                f"4. Dependent Variables: {row.get('dependent variables', 'NA.')}\n"
                                f"5. Endogenous Variable(s): {row.get('endogenous variable(s)', 'NA.')}\n"
                                f"6. Instrumental Variable Used: {row.get('instrumental variable used', 'NA.')}\n"
                                f"7. Instrumental Variable(s): {row.get('instrumental variable(s)', 'NA.')}\n"
                                f"8. Instrumental Variable Rainfall: {row.get('instrumental variable rainfall', 'NA.')}\n"
                                f"9. Rainfall Metric: {row.get('rainfall metric', 'NA.')}\n"
                                f"10. Rainfall Data Source: {row.get('rainfall data source', 'NA.')}\n"
                            ).strip()
                        }
                    ]

                    # Create the data entry
                    data_entry = {
                        "messages": messages
                    }

                    # Append the data entry to the list
                    data_entries.append(data_entry)

                # Break out of the encoding detection loop after successful processing
                break

        except UnicodeError as e:
            print(f"Failed to read with encoding {encoding}: {e}")
            continue
        except Exception as e:
            print(f"An unexpected error occurred with encoding {encoding}: {e}")
            continue
    else:
        print("Unable to read the CSV file with the tried encodings.")
        return

    # Preview data entries before shuffling and splitting
    print("\nPreview of the first 3 data entries before writing to files:\n")
    for i, entry in enumerate(data_entries[:3]):
        print(f"Entry {i+1}:")
        print(json.dumps(entry, indent=4, ensure_ascii=False))
        print('-' * 80)

    # Shuffle the data entries
    random.shuffle(data_entries)

    # Calculate the split index
    total_entries = len(data_entries)
    validation_size = int(total_entries * validation_split)
    training_size = total_entries - validation_size

    # Split the data
    training_data = data_entries[:training_size]
    validation_data = data_entries[training_size:]

    # Ensure the output directory exists
    training_output_dir = os.path.dirname(training_output_path)
    validation_output_dir = os.path.dirname(validation_output_path)
    os.makedirs(training_output_dir, exist_ok=True)
    os.makedirs(validation_output_dir, exist_ok=True)

    # Write training data to JSONL file
    with open(training_output_path, 'w', encoding='utf-8') as train_file:
        for entry in training_data:
            json_line = json.dumps(entry, ensure_ascii=False)
            train_file.write(json_line + '\n')

    # Write validation data to JSONL file
    with open(validation_output_path, 'w', encoding='utf-8') as val_file:
        for entry in validation_data:
            json_line = json.dumps(entry, ensure_ascii=False)
            val_file.write(json_line + '\n')

    print(f"Training data has been written to {training_output_path}")
    print(f"Validation data has been written to {validation_output_path}")

# Add the preview function
def preview_jsonl_file(file_path, num_entries=3):
    """
    Prints a preview of the first few entries in a JSONL file.

    Args:
        file_path (str): The path to the JSONL file.
        num_entries (int): The number of entries to preview.
    """
    print(f"\nPreviewing the first {num_entries} entries of {file_path}:\n")
    try:
        with open(file_path, 'r', encoding='utf-8') as f:
            for i in range(num_entries):
                line = f.readline()
                if not line:
                    break
                data = json.loads(line)
                print(f"Entry {i+1}:")
                print(json.dumps(data, indent=4, ensure_ascii=False))
                print('-' * 80)
    except Exception as e:
        print(f"An error occurred while previewing the file: {e}")

# Example usage:
csv_input_path = '/Users/kieran/Library/CloudStorage/OneDrive-UniversityofArizona/weather_iv_lit/training/finetune1/finetune1_data/training_data.csv'  # Replace with your CSV file path

# Output paths
training_output_path = '/Users/kieran/Library/CloudStorage/OneDrive-UniversityofArizona/weather_iv_lit/training/finetune1/finetune1_data/training_data.jsonl'
validation_output_path = '/Users/kieran/Library/CloudStorage/OneDrive-UniversityofArizona/weather_iv_lit/training/finetune1/finetune1_data/validation_data.jsonl'

# Call the function to prepare data
prepare_fine_tuning_data(csv_input_path, training_output_path, validation_output_path)

# Preview the training data
preview_jsonl_file(training_output_path, num_entries=30)

# Preview the validation data
preview_jsonl_file(validation_output_path, num_entries=30)
