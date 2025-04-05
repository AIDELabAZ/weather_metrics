import os
import csv
import re
import fitz  # PyMuPDF
from openai import OpenAI
from typing import Dict, List, Optional

# Initialize OpenAI client
client = OpenAI(api_key="key")

# Configuration
input_folder = "/Users/kieran/Library/CloudStorage/OneDrive-UniversityofArizona/weather_iv_lit/training/training_large"
output_csv = "/Users/kieran/Library/CloudStorage/OneDrive-UniversityofArizona/weather_iv_lit/training/models/output/gpt_rag_zeroshot_output.csv"

# Enhanced DOI regex with validation
DOI_REGEX = re.compile(
    r'\b(10[.][0-9]{4,}(?:[.][0-9]+)*/[-._;()/:A-Za-z0-9]+)\b',
    re.IGNORECASE
)

# Optimized questions with precise instructions
questions = [
    {
        "key": "Paper Title",
        "question": '''Extract the exact title from page 1. Ignore headers, author names, and conference info. Return only the main title in title case.'''
    },
    {
        "key": "DOI",
        "question": '''What was the DOI for this paper?'''
    },
    {
        "key": "Dependent Variable",
        "question": '''What was the PRIMARY outcome measures or dependent variable of interest?
        Only provide the name of the variable without additional text or numbers.'''
    },
    {
        "key": "Endogenous Variable",
        "question": '''What were the endogenous/explanatory variable(s) used?
        Only provide the name of the variable without additional text or numbers.'''
    },
    {
        "key": "Instrumental Variable Used",
        "question": '''Was an Instrumental Variable EXPLICITLY used? 
        Return 1 (yes) or 0 (no) ONLY'''
    },
    {
        "key": "Instrumental Variable",
        "question": '''Which specific Instrumental Variable was explicitly used in this paper?"
        Only provide the name of the variable without additional text or numbers.'''
    },
    {
        "key": "Instrumental Variable Rainfall",
        "question": '''If an Instrumental Variable was used, was it some version of rainfall?
        Return 1 (yes) or 0 (no) ONLY'''
    },
    {
        "key": "Rainfall Metric",
        "question": '''If rainfall was used as an Instrumental Variable, extract the EXACT metric:
        Return exact text from the abstract or methodology section
        Only provide the name of the variable without additional text.
        Ensure that the full name is returned, avoid using broad terms like simply "Rainfall" or "Rain".'''
    },
    {
        "key": "Rainfall Data Source",
        "question": '''If rainfall data used, what was the source? This should be an organization or a specific data collection method.
        Return exact name from data section'''
    }
]


def extract_text_from_pdf(pdf_path: str) -> Dict[str, str]:
    """Improved text extraction focusing on key sections"""
    text = []
    first_page = ""
    metadata = ""

    with fitz.open(pdf_path) as doc:
        metadata = str(doc.metadata)

        # Prioritize first 3 and last 2 pages
        for page_num in [0, 1, 2, -2, -1]:
            try:
                page = doc[page_num]
                blocks = page.get_text("blocks", flags=fitz.TEXT_PRESERVE_WHITESPACE)
                blocks.sort(key=lambda b: (b[1], b[0]))  # Vertical then horizontal
                page_text = "\n".join([b[4].strip() for b in blocks if b[6] == 0])

                if page_num == 0:
                    first_page = page_text
                text.append(page_text)
            except IndexError:
                continue

    return {
        "metadata": metadata,
        "first_page": first_page,
        "main_text": "\n".join(text)
    }


def validate_doi(doi: str) -> bool:
    """Robust DOI validation"""
    if not doi or len(doi) < 10:
        return False
    if not doi.startswith('10.'):
        return False
    parts = doi.split('/')
    return len(parts) >= 2 and '.' in parts[0]


def extract_doi(context: Dict) -> Optional[str]:
    """Multi-layered DOI extraction"""
    # Check metadata first
    if meta_doi := DOI_REGEX.search(context["metadata"]):
        return meta_doi.group(0)

    # Check first page text
    text = context["first_page"] + context["main_text"]
    for match in DOI_REGEX.finditer(text):
        if validate_doi(match.group(0)):
            return match.group(0)
    return None


def validate_iv_response(answer: str) -> str:
    """Strict IV validation"""
    answer = answer.lower().strip()
    if any(kw in answer for kw in ["n/a", "none", "not mentioned"]):
        return "n/a"
    if any(kw in answer for kw in ["yes", "1", "iv", "instrument"]):
        return "1"
    if any(kw in answer for kw in ["no", "0", "not used"]):
        return "0"
    return "n/a"


def query_model(context: str, question: Dict) -> str:
    """Structured query with validation"""
    try:
        system_msg = '''You are a research assistant who specializes in extracting specific information from academic papers. The project you are working on is related to instrumental variable selection. Follow these rules:
        1. Answer ONLY with requested information
        2. Do not number responses
        3. Format outputs without any additional text or numbers
        4. Be specific about how rainfall was represented if used as an Instrumental Variable'''

        response = client.chat.completions.create(
            model="gpt-4o-mini",
            messages=[
                {"role": "system", "content": system_msg},
                {"role": "user", "content": f"{question['question']}\n\nCONTEXT:\n{context[:10000]}"}
            ],
            temperature=0.3,
            max_tokens=300
        )

        answer = response.choices[0].message.content.strip()

        # Special handling for different question types
        if question["key"] == "DOI":
            return extract_doi(context) or "n/a"

        if question["key"] in ["Instrumental Variable Used", "Instrumental Variable Rainfall"]:
            return validate_iv_response(answer)

        if question["key"] in ["Dependent Variable", "Endogenous Variable", "Instrumental Variable"]:
            if not answer or len(answer) < 4:
                return "n/a"
            return "\n".join([f"{i + 1}. {line}" for i, line in enumerate(answer.split("\n")[:3])])

        return answer if answer else "n/a"

    except Exception as e:
        print(f"Query error: {str(e)}")
        return "n/a"


def process_pdf(pdf_path: str) -> Dict:
    """Processing pipeline with enhanced validation"""
    text_data = extract_text_from_pdf(pdf_path)
    results = {"Filename": os.path.basename(pdf_path)}

    # DOI extraction pipeline
    results["DOI"] = extract_doi(text_data) or "n/a"

    # Process other questions
    for question in questions:
        if question["key"] == "DOI":
            continue

        context = text_data["main_text"]
        results[question["key"]] = query_model(context, question)

    # Post-processing validation
    if results["Instrumental Variable Rainfall"] == "1":
        if results["Rainfall Metric"] == "n/a":
            results["Rainfall Metric"] = query_model(text_data["main_text"],
                                                     next(q for q in questions if q["key"] == "Rainfall Metric"))
    else:
        results["Rainfall Metric"] = "n/a"
        results["Rainfall Data Source"] = "n/a"

    return results


def main():
    """Main processing loop with error handling"""
    all_results = []

    for filename in os.listdir(input_folder):
        if filename.endswith(".pdf"):
            pdf_path = os.path.join(input_folder, filename)
            try:
                print(f"Processing {filename}...")
                result = process_pdf(pdf_path)
                all_results.append(result)
            except Exception as e:
                print(f"Error processing {filename}: {str(e)}")
                all_results.append({"Filename": filename, "error": str(e)})

    # Write results
    fieldnames = ["Filename"] + [q["key"] for q in questions] + ["error"]
    with open(output_csv, mode="w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(all_results)


if __name__ == "__main__":
    main()