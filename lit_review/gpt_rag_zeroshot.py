import os
import csv
import re
import fitz  # PyMuPDF
import spacy
from openai import OpenAI

# Initialize NLP and OpenAI
nlp = spacy.load("en_core_web_sm")
client = OpenAI(api_key="key")
MODEL_NAME = "gpt-4o-mini"  # Regular non-fine-tuned model

# Configuration
input_folder = "/Users/kieran/Library/CloudStorage/OneDrive-UniversityofArizona/weather_iv_lit/training/training_large"
output_csv = "/Users/kieran/Library/CloudStorage/OneDrive-UniversityofArizona/weather_iv_lit/training/models/output/gpt_rag_zeroshot_output.csv"
SECTION_KEYWORDS = ["methodology", "data", "results", "iv", "instrument"]
MAX_CONTEXT_LENGTH = 6000 * 4  # ~24k tokens
VALIDATION_RULES = {
    "DOI": r"\b10\.\d{4,}/[-._;()/:A-Za-z0-9]+\b",
    "Instrumental Variable Used": r"^[10n/a]$",
    "Instrumental Variable Rainfall": r"^[10n/a]$"
}

questions = [
    {"key": "Paper Title",
     "question": "What is the title of the paper? Provide only the exact title from the first page."},
    {"key": "DOI",
     "question": "What is the DOI (Digital Object Identifier) of the paper? Please provide just the DOI without any other text."},
    {"key": "Dependent Variables",
     "question": "List the dependent (outcome) variable analyzed in this paper, only listing the variable names without the title of the question, additional words, or numbers."},
    {"key": "Endogenous Variable(s)",
     "question": "What is/are the endogenous (explanatory/independent) variable(s) used in this paper? I am interested in specific variable used, please provide just the name of the variable without the title of the question, additional words, or numbers. There will sometimes be more than one, in which case you may list them separated by commas."},
    {"key": "Instrumental Variable Used",
     "question": "Did the paper use an instrumental variable in the analysis? Please answer with '1' for yes, '0' for no, or 'n/a' if not applicable or unclear."},
    {"key": "Instrumental Variable(s)",
     "question": "What instrumental variable was used in the paper? Please only list the variable name without the title of the question, additional words, or numbers. Sometimes the paper will discuss using some instrumental variable but not actually use it in their statistical analysis, please differentiate between mentions and uses. Please provide only the instrumental variable used without any additional text."},
    {"key": "Instrumental Variable Rainfall",
     "question": "Was rainfall used as an instrumental variable in the paper? Please answer with '1' for yes, '0' for no, or 'n/a' if not applicable or unclear."},
    {"key": "Rainfall Metric",
     "question": "Provide the specific rainfall metric used (e.g., 'yearly rainfall deviations' or 'log monthly total rainfall') by looking for the most likely option given the context of the entire text without any additional words or numbers. Do not respond with broad terms like 'rainfall', 'precipitation', or 'rainfall and humidity' on their own, unless they are part of something like 'rainfall deviations (from long term average)' or 'unexpected rainfall shocks defined as the deviation from the long run precipitation trend' for example. How exactly was rainfall represented as an instrument in this paper? Ensure that this metric is actually used in an instrumental variables regression and not just passively mentioned.",
     "dependency": {"key": "Instrumental Variable Rainfall", "value": "1"}},
    {"key": "Rainfall Data Source",
     "question": "What is the source of the rainfall data used in the study? Please give me the source of the rainfall data without any additional words or numbers. If rainfall is used as an instrumental variable, the data must come from a specific source (e.g., a satellite or organization). Please find the origin of the rainfall data that was used. Please only provide the source of the rainfall data, without the title of the question or any additional words.",
     "dependency": {"key": "Instrumental Variable Rainfall", "value": "1"}}
]


def extract_structured_text(pdf_path):
    """Enhanced text extraction with academic section awareness"""
    with fitz.open(pdf_path) as doc:
        sections = []
        current_section = "header"

        for page in doc:
            text = page.get_text("text")
            lines = text.split('\n')

            for line in lines:
                line = line.strip()
                # Detect section headers
                if any(re.search(rf"\b{sec}\b", line, re.I) for sec in SECTION_KEYWORDS):
                    current_section = line.upper()
                elif re.search(r"\babstract\b", line, re.I):
                    current_section = "ABSTRACT"
                elif re.search(r"\breferences\b", line, re.I):
                    current_section = "REFERENCES"

                if current_section != "REFERENCES":
                    sections.append(f"[{current_section}] {line}")

        return "\n".join(sections)


def expand_keyword_context(text, keywords=SECTION_KEYWORDS, window=2):
    """Semantic context expansion around key terms"""
    doc = nlp(text)
    sentences = [sent.text.strip() for sent in doc.sents]
    relevant = set()

    for i, sent in enumerate(sentences):
        if any(kw in sent.lower() for kw in keywords):
            for j in range(max(0, i - window), min(len(sentences), i + window + 1)):
                relevant.add(j)

    return " ".join(sentences[i] for i in sorted(relevant))


def build_validation_prompt(question, context):
    """Structured prompt engineering for better accuracy"""
    return f"""
    [ACADEMIC EXTRACTION TASK]
    Extract: {question['question']}

    [CONTEXT]
    {context[:MAX_CONTEXT_LENGTH]}

    [RULES]
    1. Answer ONLY with requested information
    2. Prioritize methodology/data sections
    3. Validate patterns:
       - Variables: Do not output the question or variable name in the response
       - Instruments: Require explicit usage context
       - Rainfall: Be sure that when rainfall is used as an instrument, the rainfall metric is found and specified
    4. Use 'n/a' for uncertain answers

    [RESPONSE FORMAT]
    {question['key']}: 
    """


def validate_response(response, question_key):
    """Structured validation with fallback"""
    response = response.strip(' ."')
    if not response or response.lower() == "nan":
        return "n/a"

    if pattern := VALIDATION_RULES.get(question_key):
        if not re.search(pattern, response, re.I):
            return "n/a"

    return response


def query_model(context, question):
    """Enhanced query with validation-aware prompting"""
    try:
        response = client.chat.completions.create(
            model=MODEL_NAME,
            messages=[{
                "role": "user",
                "content": build_validation_prompt(question, context)
            }],
            temperature=0.1,
            max_tokens=150
        )
        answer = response.choices[0].message.content.strip()
        return validate_response(answer, question["key"])
    except Exception as e:
        print(f"API Error: {str(e)}")
        return "n/a"


def process_pdf(pdf_path):
    """Two-phase processing with dependency resolution"""
    raw_text = extract_structured_text(pdf_path)
    context = expand_keyword_context(raw_text)
    results = {}

    # First pass - independent questions
    for q in [q for q in questions if not q.get("dependency")]:
        results[q["key"]] = query_model(context, q)

    # Second pass - dependent questions
    for q in [q for q in questions if q.get("dependency")]:
        dep_key = q["dependency"]["key"]
        dep_value = q["dependency"]["value"]

        if results.get(dep_key) == dep_value:
            results[q["key"]] = query_model(context, q)
        else:
            results[q["key"]] = "n/a"

    return results


def normalize_answer(answer, question_key):
    """Consistent answer formatting"""
    if question_key == "Dependent Variables":
        return re.sub(r'\d+\)\s*', '', answer).strip()
    if question_key in ["Instrumental Variable Used", "Instrumental Variable Rainfall"]:
        return answer


def main_processing():
    all_results = []

    # Process each PDF file in input_folder
    for filename in os.listdir(input_folder):
        if filename.endswith(".pdf"):
            pdf_path = os.path.join(input_folder, filename)
            print(f"Processing {filename}...")
            results = process_pdf(pdf_path)
            results["Filename"] = filename  # Add filename to results
            all_results.append(results)

    # Write results to CSV file
    with open(output_csv, mode="w", newline="", encoding="utf-8") as csvfile:
        writer = csv.DictWriter(csvfile, fieldnames=["Filename"] + [q["key"] for q in questions])
        writer.writeheader()
        writer.writerows(all_results)


if __name__ == "__main__":
    main_processing()
