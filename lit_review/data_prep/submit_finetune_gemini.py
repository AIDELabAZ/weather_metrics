from google import genai
from google.genai import types
import json
import os

API_KEY = os.environ.get("GEMINI_API_KEY")
TRAIN_PATH = "/Users/kieran/Library/CloudStorage/OneDrive-UniversityofArizona/weather_iv_lit/training/models/finetune_data/training_gemini_aistudio.jsonl"

client = genai.Client(api_key=API_KEY)

training_examples = []
with open(TRAIN_PATH) as f:
    for line in f:
        obj = json.loads(line)
        training_examples.append(
            types.TuningExample(text_input=obj["text_input"], output=obj["output"])
        )

print(f"Loaded {len(training_examples)} training examples.")

tuning_job = client.tunings.tune(
    base_model="models/gemini-1.5-flash-001-tuning",
    training_dataset=types.TuningDataset(examples=training_examples),
    config=types.CreateTuningJobConfig(
        epoch_count=3,
        batch_size=4,
        learning_rate_multiplier=1.0,
        tuned_model_display_name="weather-iv-gemini",
    ),
)

print(f"Tuning job submitted.")
print(f"Job name: {tuning_job.name}")
print(f"Check status: https://aistudio.google.com  (My models tab)")
