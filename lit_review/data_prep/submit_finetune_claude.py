import boto3
from datetime import datetime

ROLE_ARN    = "arn:aws:iam::193856783735:role/bedrock-finetuning-role"
BUCKET      = "finetune-job"   # us-east-1 bucket
REGION      = "us-east-1"

job_name   = f"weather-iv-claude-{datetime.now().strftime('%Y%m%d-%H%M')}"
model_name = f"weather-iv-claude-v1-{datetime.now().strftime('%Y%m%d')}"

bedrock = boto3.client("bedrock", region_name=REGION)

response = bedrock.create_model_customization_job(
    customizationType="FINE_TUNING",
    jobName=job_name,
    customModelName=model_name,
    roleArn=ROLE_ARN,
    baseModelIdentifier="arn:aws:bedrock:us-east-1::foundation-model/anthropic.claude-3-haiku-20240307-v1:0:200k",
    hyperParameters={
        "epochCount": "3",
        "batchSize": "4",
        "learningRateMultiplier": "1.0",
    },
    trainingDataConfig={"s3Uri": f"s3://{BUCKET}/training_claude.jsonl"},
    outputDataConfig={"s3Uri": f"s3://{BUCKET}/output/"},
)

print(f"Job submitted: {job_name}")
print(f"Job ARN: {response['jobArn']}")
print(f"Check status: AWS Console → Bedrock → Custom models → Training jobs")
