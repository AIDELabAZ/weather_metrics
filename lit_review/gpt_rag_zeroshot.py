import os
import csv
import fitz  # PyMuPDF
from openai import OpenAI

# Initialize OpenAI client
client = OpenAI(api_key="key")

# Configuration
input_folder = "/Users/kieran/Library/CloudStorage/OneDrive-UniversityofArizona/weather_iv_lit/training/training_large"
output_csv = "/Users/kieran/Library/CloudStorage/OneDrive-UniversityofArizona/weather_iv_lit/training/models/output/gpt_rag_zeroshot_output.csv"

questions = [
    {"key": "Paper Title", "question": "Extract the exact title from the first page. Exclude section headers or author names."},
    {"key": "DOI", "question": "Provide the DOI (Digital Object Identifier) for this paper."},
    {"key": "Dependent Variables", "question": "List dependent variable from this paper."},
    {"key": "Endogenous Variable(s)", "question": "List endogenous (explanatory) variable from this paper."},
    {"key": "Instrumental Variable Used", "question": "Was an instrumental variable used in this paper? Do not include any additional words or sentences. 1 if yes, 0 if no."},
    {"key": "Instrumental Variable(s)", "question": "What was the instrumental variable USED in the paper? Exclude additional words/sentences, only provide precise answers."},
    {"key": "Instrumental Variable Rainfall", "question": "Was rainfall (or some way of representing rain) USED as an instrumental variable in this paper? 1 if yes, 0 if no."},
    {"key": "Rainfall Metric", "question": '''If rainfall was used as an IV, what descriptive metric appears in TEXT (not equations)? Please only provide responses if they describe some type of rainfall. Examples of acceptable format: "log deviations in anual rainfall" or "average weekly rainfall".'''},
    {"key": "Rainfall Data Source", "question": "If rainfall data was used in this paper, what was the source of the rainfall data used? Exclude general terms and only cite the source, no additional words or sentences."}
]

# Extract text from PDF
def extract_text_from_pdf(pdf_path):
    extracted_text = []
    with fitz.open(pdf_path) as doc:
        for page in doc:
            extracted_text.append(page.get_text("text"))
    return "\n".join(extracted_text)

# Query model with context and question
def query_model(context, question):
    try:
        prompt = f"""STRICT TECHNICAL EXTRACTION:

{question['question']}

CONTEXT:
{context}

RULES:
1. Answer ONLY with requested information and no additional words or sentences.
2. Only respond with text descriptions; there should be no equations or undefined variables from equations.
3. There should only be one dependent and one endogenous variable.
4. If you find that rainfall was not used as an instrumental variable in the paper, rainfall metric will always be n/a."""

        response = client.chat.completions.create(
            model="gpt-4o-mini",
            messages=[{"role": "user", "content": prompt}],
            temperature=0.1,
            max_tokens=150,
        )

        # Extract and clean answer
        answer = response.choices[0].message.content.strip()

        # Enforce binary responses for specific questions
        if question['key'] in ["Instrumental Variable Used", "Instrumental Variable Rainfall"]:
            if answer.lower() in ["1", "yes"]:
                return "1"
            elif answer.lower() in ["0", "no"]:
                return "0"
            else:
                return "n/a"  # Default to NA if response is ambiguous

        # Return cleaned answer for all other questions
        return answer

    except Exception as e:
        print(f"Error querying model: {str(e)}")
        return "n/a"

# Process a single PDF file
def process_pdf(pdf_path):
    raw_text = extract_text_from_pdf(pdf_path)
    results = {"Filename": os.path.basename(pdf_path)}
    print(f"\nProcessing {results['Filename']}...")

    for question in questions:
        print(f"Querying: {question['question']}")
        answer = query_model(raw_text, question)
        print(f"Answer: {answer}")
        results[question["key"]] = answer  # Only store the clean answer

    return results

# Main function to process all PDFs and save output to CSV
def main():
    all_results = []

    for filename in os.listdir(input_folder):
        if filename.endswith(".pdf"):
            pdf_path = os.path.join(input_folder, filename)
            try:
                all_results.append(process_pdf(pdf_path))
            except Exception as e:
                print(f"Error processing {filename}: {str(e)}")

    # Write results to CSV
    with open(output_csv, mode="w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=["Filename"] + [q["key"] for q in questions])
        writer.writeheader()
        writer.writerows(all_results)

if __name__ == "__main__":
    main()
