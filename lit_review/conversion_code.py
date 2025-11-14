import csv
import json
import os
import random

def prepare_fine_tuning_data(
    csv_input_path,
    training_output_path,
    validation_output_path,
    validation_split=0.125,
    seed=42
):
    """
    Reads CSV with specified columns and prepares JSONL files for OpenAI fine-tuning (chat format), shuffling and splitting into train/validation.
    """
    required_columns = [
        'filename', 'title', 'doi',
        'emp_bin', 'dep_var', 'dep_sec', 'dep_txt',
        'end_bin', 'end_var', 'end_sec', 'end_txt',
        'iv_bin', 'iv_var', 'iv_sec', 'iv_txt',
        'rain_bin', 'rain_var', 'rain_sec', 'rain_txt'
    ]
    encodings_to_try = ['utf-8-sig', 'utf-16', 'utf-16-le', 'utf-16-be', 'cp1252', 'latin1']
    data_entries = []

    # Try opening with several encodings if needed
    for encoding in encodings_to_try:
        try:
            with open(csv_input_path, 'r', encoding=encoding, newline='') as csvfile:
                reader = csv.DictReader(csvfile)
                headers = reader.fieldnames or []
                missing_columns = [col for col in required_columns if col not in headers]
                if missing_columns:
                    print(f"Missing required columns: {', '.join(missing_columns)}")
                    return

                print(f"Successfully read the CSV file using encoding: {encoding}")

                for row in reader:
                    # Skip rows missing filename, title, or doi
                    if not row.get('filename') or not row.get('title') or not row.get('doi'):
                        continue

                    # Prompt template includes all sections
                    user_content = (
                        "Extract information about a research paper from the following fields and answer the corresponding questions.\n"
                        f"Filename: {row.get('filename', 'NA')}\n"
                        f"Title: {row.get('title', 'NA')}\n"
                        f"DOI: {row.get('doi', 'NA')}\n"
                        f"emp_bin: {row.get('emp_bin', 'NA')}\n"
                        f"dep_var: {row.get('dep_var', 'NA')}\n"
                        f"dep_sec: {row.get('dep_sec', 'NA')}\n"
                        f"dep_txt: {row.get('dep_txt', 'NA')}\n"
                        f"end_bin: {row.get('end_bin', 'NA')}\n"
                        f"end_var: {row.get('end_var', 'NA')}\n"
                        f"end_sec: {row.get('end_sec', 'NA')}\n"
                        f"end_txt: {row.get('end_txt', 'NA')}\n"
                        f"iv_bin: {row.get('iv_bin', 'NA')}\n"
                        f"iv_var: {row.get('iv_var', 'NA')}\n"
                        f"iv_sec: {row.get('iv_sec', 'NA')}\n"
                        f"iv_txt: {row.get('iv_txt', 'NA')}\n"
                        f"rain_bin: {row.get('rain_bin', 'NA')}\n"
                        f"rain_var: {row.get('rain_var', 'NA')}\n"
                        f"rain_sec: {row.get('rain_sec', 'NA')}\n"
                        f"rain_txt: {row.get('rain_txt', 'NA')}\n"
                    ).strip()

                    reference_answer = (
                        f"1. Filename: {row.get('filename', 'NA')}\n"
                        f"2. Title: {row.get('title', 'NA')}\n"
                        f"3. DOI: {row.get('doi', 'NA')}\n"
                        f"4. emp_bin: {row.get('emp_bin', 'NA')}\n"
                        f"5. dep_var: {row.get('dep_var', 'NA')}\n"
                        f"6. dep_sec: {row.get('dep_sec', 'NA')}\n"
                        f"7. dep_txt: {row.get('dep_txt', 'NA')}\n"
                        f"8. end_bin: {row.get('end_bin', 'NA')}\n"
                        f"9. end_var: {row.get('end_var', 'NA')}\n"
                        f"10. end_sec: {row.get('end_sec', 'NA')}\n"
                        f"11. end_txt: {row.get('end_txt', 'NA')}\n"
                        f"12. iv_bin: {row.get('iv_bin', 'NA')}\n"
                        f"13. iv_var: {row.get('iv_var', 'NA')}\n"
                        f"14. iv_sec: {row.get('iv_sec', 'NA')}\n"
                        f"15. iv_txt: {row.get('iv_txt', 'NA')}\n"
                        f"16. rain_bin: {row.get('rain_bin', 'NA')}\n"
                        f"17. rain_var: {row.get('rain_var', 'NA')}\n"
                        f"18. rain_sec: {row.get('rain_sec', 'NA')}\n"
                        f"19. rain_txt: {row.get('rain_txt', 'NA')}\n"
                    ).strip()

                    # New: format for OpenAI chat fine-tuning, assistant last
                    data_entries.append({
                        "messages": [
                            {"role": "user", "content": user_content},
                            {"role": "assistant", "content": reference_answer}
                        ]
                    })
                break  # success, stop trying encodings!
        except UnicodeError as e:
            print(f"Failed to read with encoding {encoding}: {e}")
        except Exception as e:
            print(f"An unexpected error occurred with encoding {encoding}: {e}")
    else:
        print("Unable to read the CSV file with the tried encodings.")
        return

    # Preview samples before split
    print("\nPreview of first 3 data entries (OpenAI format):\n")
    for i, entry in enumerate(data_entries[:3]):
        print(f"Entry {i + 1}:")
        print(json.dumps(entry, indent=4, ensure_ascii=False))
        print('-' * 80)

    # Shuffle and split
    random.seed(seed)
    random.shuffle(data_entries)
    total_entries = len(data_entries)
    validation_size = int(total_entries * validation_split)
    training_size = total_entries - validation_size

    training_data = data_entries[:training_size]
    validation_data = data_entries[training_size:]

    # Ensure output directories exist
    os.makedirs(os.path.dirname(training_output_path), exist_ok=True)
    os.makedirs(os.path.dirname(validation_output_path), exist_ok=True)

    # Write JSONL files in OpenAI format
    with open(training_output_path, 'w', encoding='utf-8') as train_file:
        for entry in training_data:
            json.dump(entry, train_file, ensure_ascii=False)
            train_file.write('\n')
    with open(validation_output_path, 'w', encoding='utf-8') as val_file:
        for entry in validation_data:
            json.dump(entry, val_file, ensure_ascii=False)
            val_file.write('\n')

    print(f"Training data written to {training_output_path}")
    print(f"Validation data written to {validation_output_path}")

    lint_jsonl(training_output_path)
    lint_jsonl(validation_output_path)


def lint_jsonl(path, max_checks=50):
    """Quick format check for generated JSONL files."""
    try:
        with open(path, 'r', encoding='utf-8') as f:
            for i, line in enumerate(f, 1):
                if i > max_checks:
                    break
                obj = json.loads(line)
                msgs = obj.get("messages", [])
                assert isinstance(msgs, list) and len(msgs) >= 2, f"{path} item {i}: should have at least 2 messages"
                assert msgs[-1].get("role") == "assistant", f"{path} item {i}: last message is not assistant"
        print(f"Lint OK (checked first {min(i, max_checks)} items): {path}")
    except Exception as e:
        print(f"Lint FAILED for {path}: {e}")

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

# File paths (update as needed)
csv_input_path = '/Users/kieran/Library/CloudStorage/OneDrive-UniversityofArizona/weather_iv_lit/training/models/finetune_data/train_80.csv'
training_output_path = '/Users/kieran/Library/CloudStorage/OneDrive-UniversityofArizona/weather_iv_lit/training/models/finetune_data/training.jsonl'
validation_output_path = '/Users/kieran/Library/CloudStorage/OneDrive-UniversityofArizona/weather_iv_lit/training/models/finetune_data/validation.jsonl'

# Run preprocessing and preview
prepare_fine_tuning_data(csv_input_path, training_output_path, validation_output_path)
preview_jsonl_file(training_output_path, num_entries=3)
preview_jsonl_file(validation_output_path, num_entries=3)
