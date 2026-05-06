import csv
import json
import os
import random

SYSTEM_PROMPT = (
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
    Reads CSV with specified columns and prepares JSONL files for Bedrock Claude fine-tuning.

    Bedrock Claude format (one JSON object per line):
      {
        "system": "<system prompt>",
        "messages": [
          {"role": "user",      "content": "..."},
          {"role": "assistant", "content": "..."}
        ]
      }

    After generating the JSONL files, upload them to S3 before submitting the fine-tuning job:
      aws s3 cp training_claude.jsonl  s3://YOUR_BUCKET/training_claude.jsonl
      aws s3 cp validation_claude.jsonl s3://YOUR_BUCKET/validation_claude.jsonl

    Then submit the fine-tuning job with boto3:
      import boto3
      bedrock = boto3.client("bedrock", region_name="us-west-2")
      bedrock.create_model_customization_job(
          customizationType="FINE_TUNING",
          jobName="weather-iv-claude-haiku",
          customModelName="weather-iv-claude-haiku-v1",
          roleArn="arn:aws:iam::ACCOUNT_ID:role/BedrockFineTuningRole",
          baseModelIdentifier="anthropic.claude-haiku-4-5-20251001-v1:0:200k",
          hyperParameters={
              "epochCount": "3",
              "batchSize": "8",
              "learningRateMultiplier": "1.0",
              "earlyStoppingPatience": "5",
          },
          trainingDataConfig={"s3Uri": "s3://YOUR_BUCKET/training_claude.jsonl"},
          validationDataConfig={"s3Uri": "s3://YOUR_BUCKET/validation_claude.jsonl"},
          outputDataConfig={"s3Uri": "s3://YOUR_BUCKET/output/"},
      )
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
                        "system": SYSTEM_PROMPT,
                        "messages": [
                            {"role": "user",      "content": user_content},
                            {"role": "assistant", "content": reference_answer},
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

    print("\nPreview of first 3 data entries (Bedrock Claude format):\n")
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

    print("\nNext step: upload to S3 and submit the fine-tuning job.")
    print("  aws s3 cp", training_output_path, "s3://YOUR_BUCKET/training_claude.jsonl")
    print("  aws s3 cp", validation_output_path, "s3://YOUR_BUCKET/validation_claude.jsonl")
    print("See the docstring of prepare_fine_tuning_data() for the boto3 job-submission snippet.")


def lint_jsonl(path, max_checks=50):
    try:
        with open(path, 'r', encoding='utf-8') as f:
            for i, line in enumerate(f, 1):
                if i > max_checks:
                    break
                obj = json.loads(line)
                msgs = obj.get("messages", [])
                assert isinstance(msgs, list) and len(msgs) >= 2, \
                    f"{path} item {i}: should have at least 2 messages"
                assert msgs[-1].get("role") == "assistant", \
                    f"{path} item {i}: last message must be assistant"
                assert "system" in obj, \
                    f"{path} item {i}: missing 'system' key"
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
training_output_path = '/Users/kieran/Library/CloudStorage/OneDrive-UniversityofArizona/weather_iv_lit/training/models/finetune_data/training_claude.jsonl'
validation_output_path = '/Users/kieran/Library/CloudStorage/OneDrive-UniversityofArizona/weather_iv_lit/training/models/finetune_data/validation_claude.jsonl'

prepare_fine_tuning_data(csv_input_path, training_output_path, validation_output_path)
preview_jsonl_file(training_output_path, num_entries=3)
preview_jsonl_file(validation_output_path, num_entries=3)
