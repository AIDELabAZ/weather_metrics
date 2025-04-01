import os
import csv
import re
import time
import random
import hashlib
from concurrent.futures import ThreadPoolExecutor
from functools import lru_cache
from pathlib import Path
from tqdm import tqdm
import pdfplumber
import tiktoken
from openai import OpenAI

# Configuration
DEEPSEEK_API_KEY = "sk-c999193bd25c447b9a8d71a3af8f2ed5"
MODEL_NAME = "deepseek-chat"
MAX_TOKENS = 3500
MAX_WORKERS = 5
RETRY_ATTEMPTS = 3
BASE_DELAY = 1

# Path configuration
PDF_FOLDER = Path("/Users/kieran/Library/CloudStorage/OneDrive-UniversityofArizona/weather_iv_lit/training/training_large")
OUTPUT_FOLDER = Path("/Users/kieran/Library/CloudStorage/OneDrive-UniversityofArizona/weather_iv_lit/training/finetune1/finetune1_output")
OUTPUT_CSV = OUTPUT_FOLDER / "deepseek_out.csv"

# Natural language prompts from original code
PROMPT_COMPONENTS = {
    "title_prompt": "Provide only the title of this academic paper, without any additional text.",
    "doi_prompt": "Provide only the DOI of this academic paper, without any additional text.",
    "dep_var_prompt": "List only the dependent variable(s) analyzed in this paper, without any additional text or explanations.",
    "endo_var_prompt": "List only the endogenous variables considered in this paper, separated by commas if multiple, without any additional text or explanations.",
    "iv_used_prompt": "Answer only 'Yes' or 'No': Did the authors use an instrumental variable in the analysis?",
    "iv_name_prompt": "Provide only the name of the instrumental variable used in the paper, without any additional text or explanations.",
    "rain_iv_prompt": "Answer only 'Yes' or 'No': Was rainfall used as an instrumental variable in the paper?",
    "rain_metric_prompt": (
        "Provide the specific rainfall metric used (e.g., 'yearly rainfall deviations' or 'log monthly total rainfall') "
        "without any additional unnecessary text. Do not respond exclusively with broad terms like 'rainfall', "
        "'precipitation', or 'rainfall and humidity' alone, unless they are part of something like 'rainfall deviations "
        "(from long term average)' or 'unexpected rainfall shocks defined as the deviation from the long run precipitation "
        "trend'. Ensure that the rainfall metric you find is actually used in an instrumental variables regression and not "
        "just passively mentioned."
    ),
    "rain_source_prompt": (
        "Provide only the specific organization, satellite, or device used to collect the rainfall data in this study. "
        "For example: 'NOAA', 'TRMM satellite', or 'local weather stations'. If not explicitly stated, respond with 'Not specified'."
    )
}

# Structured prompt template
EXTRACTION_PROMPT_TEMPLATE = """Extract specific information from this academic paper following these exact requirements:

1. Title: {title_prompt}
2. DOI: {doi_prompt}
3. Dependent Variables: {dep_var_prompt}
4. Endogenous Variables: {endo_var_prompt}
5. IV Used: {iv_used_prompt}
6. IV Name: {iv_name_prompt}
7. Rainfall IV: {rain_iv_prompt}
8. Rainfall Metric: {rain_metric_prompt}
9. Rainfall Source: {rain_source_prompt}

Format your response EXACTLY like this:
Title: [title]
DOI: [doi]
Dependent Variables: [comma-separated list]
Endogenous Variables: [comma-separated list]
IV Used: [Yes/No]
IV Name: [name]
Rainfall IV: [Yes/No]
Rainfall Metric: [specific metric]
Rainfall Source: [source]

Paper Content:
{text}"""

# Initialize tokenizer and OpenAI client
tokenizer = tiktoken.get_encoding("cl100k_base")
client = OpenAI(api_key=DEEPSEEK_API_KEY, base_url="https://api.deepseek.com")

def get_file_hash(file_path):
    """Generate MD5 hash of file contents"""
    with open(file_path, "rb") as f:
        return hashlib.md5(f.read()).hexdigest()

@lru_cache(maxsize=100)
def extract_text_from_pdf(pdf_path):
    """Extract text from PDF with caching"""
    text = ""
    with pdfplumber.open(pdf_path) as pdf:
        for page in pdf.pages:
            page_text = page.extract_text()
            if page_text:
                text += page_text + "\n"
    return text.strip()

def truncate_text(text, max_tokens=MAX_TOKENS):
    """Truncate text to token limit"""
    tokens = tokenizer.encode(text)
    return tokenizer.decode(tokens[:max_tokens])

def deepseek_api_request(prompt):
    """Send request to DeepSeek API with retry logic and exponential backoff"""
    for attempt in range(RETRY_ATTEMPTS):
        try:
            response = client.chat.completions.create(
                model=MODEL_NAME,
                messages=[
                    {"role": "system", "content": "You are a helpful assistant"},
                    {"role": "user", "content": prompt},
                ],
                temperature=0.1,
                max_tokens=1000
            )
            if response.choices and response.choices[0].message:
                return response.choices[0].message.content
            else:
                print(f"Empty response from API on attempt {attempt + 1}")
        except Exception as e:
            print(f"Error on attempt {attempt + 1}: {str(e)}")
            if attempt < RETRY_ATTEMPTS - 1:
                sleep_time = BASE_DELAY * (2 ** attempt) + random.uniform(0, 1)
                time.sleep(sleep_time)
    return None

def parse_response(response):
    """Parse the structured response from DeepSeek"""
    if not response:
        return {}

    result = {}
    current_field = None

    for line in response.split("\n"):
        line = line.strip()
        if not line:
            continue

        if ":" in line:
            field, value = line.split(":", 1)
            current_field = field.strip()
            result[current_field] = value.strip()
        elif current_field:
            result[current_field] += " " + line

    # Validate and format fields
    for key in ["Dependent Variables", "Endogenous Variables"]:
        if key in result:
            result[key] = [v.strip() for v in result[key].split(",") if v.strip()]

    for key in ["IV Used", "Rainfall IV"]:
        if key in result:
            result[key] = "Yes" if result[key].lower().startswith("yes") else "No"

    if "DOI" in result:
        doi_match = re.search(r'\b10\.\d{4,}/[^\s]+', result["DOI"])
        result["DOI"] = doi_match.group(0) if doi_match else "Not found"

    if "Rainfall Source" in result:
        source = result["Rainfall Source"].split(",")[0].split(".")[-1].strip()
        result["Rainfall Source"] = source if source.lower() != "not specified" else "Not specified"

    return result

def process_single_pdf(pdf_path):
    """Process a single PDF file"""
    print(f"Processing: {pdf_path.name}")
    try:
        # Check cache first
        file_hash = get_file_hash(pdf_path)
        cache_key = f"{pdf_path.name}_{file_hash}"

        # Extract and process text
        text = extract_text_from_pdf(pdf_path)
        if not text:
            print(f"Empty text for {pdf_path.name}")
            return None

        truncated_text = truncate_text(text)
        prompt = EXTRACTION_PROMPT_TEMPLATE.format(
            text=truncated_text,
            **PROMPT_COMPONENTS
        )

        # Get API response
        response = deepseek_api_request(prompt)
        if not response:
            print(f"Failed to process: {pdf_path.name}")
            return None

        # Validate API response
        if response and response.strip():
            data = parse_response(response)
        else:
            print(f"Empty or invalid response for {pdf_path.name}")
            return None

        data["Filename"] = pdf_path.name
        data["File Hash"] = file_hash

        return data

    except Exception as e:
        print(f"Error processing {pdf_path.name}: {str(e)}")
        return None

def process_pdfs():
    """Main processing function with parallel execution"""
    PDF_FOLDER.mkdir(parents=True, exist_ok=True)
    OUTPUT_FOLDER.mkdir(parents=True, exist_ok=True)

    pdf_files = list(PDF_FOLDER.glob("*.pdf"))
    print(f"Found {len(pdf_files)} PDF files to process")

    results = []
    with ThreadPoolExecutor(max_workers=MAX_WORKERS) as executor:
        futures = {executor.submit(process_single_pdf, pdf): pdf for pdf in pdf_files}

        with tqdm(total=len(pdf_files), desc="Processing PDFs", unit="file") as pbar:
            for future in futures:
                result = future.result()
                if result:
                    results.append(result)
                pbar.update(1)

    if results:
        fieldnames = [
            "Filename", "File Hash", "Title", "DOI",
            "Dependent Variables", "Endogenous Variables",
            "IV Used", "IV Name", "Rainfall IV",
            "Rainfall Metric", "Rainfall Source"
        ]

        with open(OUTPUT_CSV, "w", newline="", encoding="utf-8") as f:
            writer = csv.DictWriter(f, fieldnames=fieldnames)
            writer.writeheader()

            for row in results:
                # Flatten list fields for CSV
                row_copy = row.copy()
                for list_field in ["Dependent Variables", "Endogenous Variables"]:
                    if list_field in row_copy:
                        row_copy[list_field] = ", ".join(row_copy[list_field])
                writer.writerow(row_copy)

        print(f"Successfully processed {len(results)} files. Results saved to {OUTPUT_CSV}")
    else:
        print("No valid results to save")

if __name__ == "__main__":
    start_time = time.time()
    process_pdfs()
    print(f"Total processing time: {time.time() - start_time:.2f} seconds")
