import vertexai
from vertexai.tuning import sft

# -------------------------------------------------------------------
# Config — update these before running
# -------------------------------------------------------------------

GCP_PROJECT  = "YOUR_GCP_PROJECT"
GCP_LOCATION = "us-central1"

GCS_BUCKET = "YOUR_BUCKET"
TRAIN_PATH = f"gs://{GCS_BUCKET}/training_llama.jsonl"
VALIDATION_PATH = f"gs://{GCS_BUCKET}/validation_llama.jsonl"

# Confirm the exact tuning-eligible Model Garden ID in the Vertex AI console
# (Tune and distill > Llama) before running — availability varies by project/region.
SOURCE_MODEL = "llama-3.1-8b"

TUNED_MODEL_DISPLAY_NAME = "weather-iv-llama-v1"
EPOCHS = 3
LEARNING_RATE_MULTIPLIER = 1.0


def main():
    vertexai.init(project=GCP_PROJECT, location=GCP_LOCATION)

    print(f"Submitting Vertex AI SFT tuning job for {SOURCE_MODEL}...")
    print(f"  train_dataset: {TRAIN_PATH}")
    print(f"  validation_dataset: {VALIDATION_PATH}")

    sft_job = sft.train(
        source_model=SOURCE_MODEL,
        train_dataset=TRAIN_PATH,
        validation_dataset=VALIDATION_PATH,
        tuned_model_display_name=TUNED_MODEL_DISPLAY_NAME,
        epochs=EPOCHS,
        learning_rate_multiplier=LEARNING_RATE_MULTIPLIER,
    )

    print("Tuning job submitted.")
    print(f"Job resource name: {sft_job.resource_name}")
    print("Check status in the Vertex AI console (Tuning > your project).")
    print("Once complete, copy the deployed endpoint/tuned model name into "
          "extraction/fine_tuned/finetune_llama.py (ENDPOINT_ID / GCP_PROJECT / GCP_LOCATION).")


if __name__ == "__main__":
    main()
