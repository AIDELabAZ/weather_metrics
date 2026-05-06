import csv
import json
import os
import random

SYSTEM_INSTRUCTION_TEXT = (
    "You are an AI assistant expert in economic literature analysis. "
    "Extract specific metadata from academic paper information provided to you. "
    "Output exactly the requested fields and format. If information is unavailable, use NA."
)


def prepare_fine_tuning_data(
    csv_input_path,
    training_output_path,
    validation_output_path,
    validation_split=0.125,
    seed=42
):
    """
    Reads CSV with specified columns and prepares JSONL files for Vertex AI Gemini fine-tuning.

    Vertex AI supervised fine-tuning format (one JSON object per line):
      {
        "systemInstruction": {
          "role": "user",
          "parts": [{"text": "<system prompt>"}]
        },
        "contents": [
          {"role": "user",  "parts": [{"text": "..."}]},
          {"role": "model", "parts": [{"text": "..."}]}
        ]
      }

    After generating the JSONL files, upload them to Google Cloud Storage:
      gsutil cp training_gemini.jsonl  gs://YOUR_BUCKET/training_gemini.jsonl
      gsutil cp validation_gemini.jsonl gs://YOUR_BUCKET/validation_gemini.jsonl

    Then submit the fine-tuning job with the Vertex AI SDK:
      import vertexai
      from vertexai.tuning import sft

      vertexai.init(project="YOUR_GCP_PROJECT", location="us-central1")
      sft_job = sft.train(
          source_model="gemini-2.5-flash",
          train_dataset="gs://YOUR_BUCKET/training_gemini.jsonl",
          validation_dataset="gs://YOUR_BUCKET/validation_gemini.jsonl",
          tuned_model_display_name="weather-iv-gemini-flash-v1",
          epochs=3,
          adapter_size="ADAPTER_SIZE_ONE",
          learning_rate_multiplier=1.0,
      )
      print(sft_job.tuned_model_name)  # use this endpoint in finetune_gemini.py
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
                    if not row.get('filename') or not row.get('title') or not row.get('doi'):
                        continue

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

                    data_entries.append({
                        "systemInstruction": {
                            "role": "user",
                            "parts": [{"text": SYSTEM_INSTRUCTION_TEXT}]
                        },
                        "contents": [
                            {"role": "user",  "parts": [{"text": user_content}]},
                            {"role": "model", "parts": [{"text": reference_answer}]},
                        ]
                    })
                break
        except UnicodeError as e:
            print(f"Failed to read with encoding {encoding}: {e}")
        except Exception as e:
            print(f"An unexpected error occurred with encoding {encoding}: {e}")
    else:
        print("Unable to read the CSV file with the tried encodings.")
        return

    print("\nPreview of first 3 data entries (Vertex AI Gemini format):\n")
    for i, entry in enumerate(data_entries[:3]):
        print(f"Entry {i + 1}:")
        print(json.dumps(entry, indent=4, ensure_ascii=False))
        print('-' * 80)

    random.seed(seed)
    random.shuffle(data_entries)
    total_entries = len(data_entries)
    validation_size = int(total_entries * validation_split)
    training_size = total_entries - validation_size

    training_data = data_entries[:training_size]
    validation_data = data_entries[training_size:]

    os.makedirs(os.path.dirname(training_output_path), exist_ok=True)
    os.makedirs(os.path.dirname(validation_output_path), exist_ok=True)

    with open(training_output_path, 'w', encoding='utf-8') as f:
        for entry in training_data:
            json.dump(entry, f, ensure_ascii=False)
            f.write('\n')

    with open(validation_output_path, 'w', encoding='utf-8') as f:
        for entry in validation_data:
            json.dump(entry, f, ensure_ascii=False)
            f.write('\n')

    print(f"Training data written to {training_output_path} ({training_size} records)")
    print(f"Validation data written to {validation_output_path} ({validation_size} records)")

    lint_jsonl(training_output_path)
    lint_jsonl(validation_output_path)

    print("\nNext step: upload to GCS and submit the fine-tuning job.")
    print("  gsutil cp", training_output_path, "gs://YOUR_BUCKET/training_gemini.jsonl")
    print("  gsutil cp", validation_output_path, "gs://YOUR_BUCKET/validation_gemini.jsonl")
    print("See the docstring of prepare_fine_tuning_data() for the Vertex AI SDK job-submission snippet.")


def lint_jsonl(path, max_checks=50):
    try:
        with open(path, 'r', encoding='utf-8') as f:
            for i, line in enumerate(f, 1):
                if i > max_checks:
                    break
                obj = json.loads(line)
                contents = obj.get("contents", [])
                assert isinstance(contents, list) and len(contents) >= 2, \
                    f"{path} item {i}: 'contents' should have at least 2 entries"
                assert contents[-1].get("role") == "model", \
                    f"{path} item {i}: last content entry must have role 'model'"
                assert "systemInstruction" in obj, \
                    f"{path} item {i}: missing 'systemInstruction' key"
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
training_output_path = '/Users/kieran/Library/CloudStorage/OneDrive-UniversityofArizona/weather_iv_lit/training/models/finetune_data/training_gemini.jsonl'
validation_output_path = '/Users/kieran/Library/CloudStorage/OneDrive-UniversityofArizona/weather_iv_lit/training/models/finetune_data/validation_gemini.jsonl'

prepare_fine_tuning_data(csv_input_path, training_output_path, validation_output_path)
preview_jsonl_file(training_output_path, num_entries=3)
preview_jsonl_file(validation_output_path, num_entries=3)
