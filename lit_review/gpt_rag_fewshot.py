import os
import json
import re
import fitz  # PyMuPDF
import pandas as pd
from openai import OpenAI

# ------------------------
# Configuration
# ------------------------
MODEL = os.getenv("OPENAI_MODEL", "gpt-5")
MAX_INPUT_CHARS = 24000  # trim extremely long extracts; adjust up if you have long-context access
KEYWORDS = [
    "title", "doi", "abstract", "introduction", "data", "methods", "model",
    "econometric", "estimation", "strategy", "empirical", "instrument",
    "instrumental variable", "iv", "first stage", "2sls", "gmm",
    "rainfall", "precipitation", "spi", "pdsi", "results", "conclusion"
]

# ------------------------
# OpenAI client
# ------------------------
from openai import OpenAI

client = OpenAI(api_key="key")


# ------------------------
# Utility cleaning
# ------------------------
def normalize_binary_token(answer: str) -> str:
    """Return exactly '1', '0', or 'n/a'."""
    if not answer:
        return "0"
    a = answer.strip().lower()
    if a in {"1", "yes", "y", "true"}:
        return "1"
    if a in {"0", "no", "n", "false"}:
        return "0"
    return "n/a"


def clean_var_token(text: str) -> str:
    """
    Light cleanup for variable tokens—remove list numbers, extra spaces.
    Does not change case or inner punctuation.
    """
    if not text:
        return text
    # Remove enumerations like "1) " or "2) "
    text = re.sub(r"\b\d+\)\s*", "", text)
    # Collapse whitespace
    return re.sub(r"\s+", " ", text).strip()


# ------------------------
# PDF text extraction
# ------------------------
def extract_text(pdf_path: str) -> str:
    """Return full plain text from PDF."""
    parts = []
    with fitz.open(pdf_path) as doc:
        for i in range(len(doc)):
            page = doc.load_page(i)
            parts.append(page.get_text("text"))
    return "\n".join(parts)


def extract_relevant_sections(full_text: str) -> str:
    """
    Keep paragraphs that contain any of our keywords.
    Fallback to full text if we found too little.
    """
    paras = re.split(r"\n{2,}", full_text)
    kept = []
    for p in paras:
        low = p.lower()
        if any(k in low for k in KEYWORDS):
            kept.append(p)
    joined = "\n\n".join(kept)
    if len(joined) < 5000:  # too little—fallback to full text
        joined = full_text
    return joined[:MAX_INPUT_CHARS]


# ------------------------
# Prompt + JSON schema for one-shot extraction
# ------------------------
def build_instruction() -> str:
    """
    One instruction block that covers all outputs at once.
    Dependencies are enforced by instruction AND post-processing.
    """
    return (
        "You are an assistant expert in reading academic economics papers and extracting specific information.\n"
        "Work only from the supplied text. If a field is not determinable, return exactly 'n/a' (or empty list where appropriate).\n"
        "Return ONLY the JSON that matches the provided schema. No extra commentary.\n\n"
        "Field rules:\n"
        "1) paper_title — Extract the exact in-body title (main standalone heading near top of first page), excluding article-type labels, headers/footers, running heads, DOIs, dates, disclaimers, and series/venue names unless printed as part of the title block. merge multi-line titles with single spaces; strip footnote symbols; output strictly the title text.\n"
        "2) doi — Extract the DOI for the focal article (version of record). return exactly the article’s DOI for the version of record, normalized and lowercased. Think step‑by‑step to locate and verify the correct DOI; output only the final DOI string or 'n/a'. Locate candidates in the title/author/journal block, publisher imprint, or citation line on the first pages; you may also check the article footer or metadata panels. If multiple candidates are present, choose the one explicitly tied to the article itself (nearest to the title/journal imprint or labeled “version of record”/“article”) and not a supplement or dataset.\n"
        "3) dependent_variables — List the left-hand-side dependent/outcome vartiable(s) in the paper’s MAIN regressions. Include each unique main outcome once. Preserve transformations (e.g., ln(wage), Δ outcome). Exclude instruments, treatments, controls, FE, first-stage outcomes, and ancillary robustness-only outcomes.\n"
        "4) endogenous_variables — List regressors the authors explicitly treat as endogenous (the key explanatory/independent variable that is instrumented for) (e.g., they say 'we instrument X', run first-stages, report weak-instrument tests). Use variable names/labels from the paper.\n"
        "5) iv_used — Was an instrumental variable used? Exactly one of: '1' if any IV/GMM/2SLS/IV-Probit/2SRI/etc. with an excluded instrument is implemented; '0' if no IV is used; 'n/a' only if there is truly no endogeneity concern by design (e.g., pure randomized experiment with exogenous assignment).\n"
        "6) iv_list — What was the specific instrumental variable(s) used in the main analysis, in the authors’ labels (not generic descriptions). If iv_used!='1', return 'n/a'.\n"
        "7) iv_rainfall — Was rainfall used as an instrumental variable? Exactly one of: '1' if ANY excluded instrument is rainfall/precipitation-based (rainfall totals, deviations, SPI/SPEI/PDSI/scPDSI, drought/wetness indices, wet-day counts, etc.); '0' if IVs are used but none are precipitation-based; 'n/a' if iv_used!='1'.\n"
        "8) rainfall_metric — If iv_rainfall=='1', list the exact rainfall instrument definition(s) as written (e.g., 'growing-season total rainfall', 'SPI-12', 'rainfall deviations from long-run district mean'). One definition per list item. If iv_rainfall!='1', return 'n/a'.\n"
        "9) rainfall_data_source — If iv_rainfall=='1', return ONLY the dataset/provider name for precipitation data (e.g., 'CHIRPS', 'TRMM', 'ERA5', 'NOAA station records', 'Indian Meteorological Department'), with no extra words. If iv_rainfall!='1', return 'n/a'.\n"
        "Perform all reasoning internally and output only the final structured JSON."
    )


def build_json_schema() -> dict:
    """Strict JSON schema for Structured Outputs."""
    return {
        "name": "econ_paper_extraction",
        "schema": {
            "type": "object",
            "additionalProperties": False,
            "properties": {
                "paper_title": {"type": "string"},
                "doi": {"type": "string"},
                "dependent_variables": {
                    "type": "array",
                    "items": {"type": "string"}
                },
                "endogenous_variables": {
                    "type": "array",
                    "items": {"type": "string"}
                },
                "iv_used": {"type": "string", "enum": ["1", "0", "n/a"]},
                "iv_list": {
                    "type": "array",
                    "items": {"type": "string"}
                },
                "iv_rainfall": {"type": "string", "enum": ["1", "0", "n/a"]},
                "rainfall_metric": {
                    "type": "array",
                    "items": {"type": "string"}
                },
                "rainfall_data_source": {"type": "string"},
            },
            "required": [
                "paper_title", "doi",
                "dependent_variables", "endogenous_variables",
                "iv_used", "iv_list",
                "iv_rainfall", "rainfall_metric", "rainfall_data_source"
            ],
        },
        "strict": True
    }


# ------------------------
# Single-call model query
# ------------------------
def query_model_batch(text: str) -> dict:
    """
    Make ONE chat.completions call to GPT-5 with Structured Outputs (strict).
    Returns a parsed dict matching the schema (or raises).
    """
    instruction = build_instruction()
    json_schema = build_json_schema()

    resp = client.chat.completions.create(
        model=MODEL,
        temperature=1,
        messages=[
            {
                "role": "system",
                "content": instruction
            },
            {
                "role": "user",
                "content": (
                    "Relevant sections from the academic paper follow. "
                    "Answer using ONLY this content.\n\n"
                    f"{text}"
                ),
            },
        ],
        # Structured Outputs via JSON schema (strict)
        response_format={
            "type": "json_schema",
            "json_schema": json_schema
        },
        # You may add `max_tokens` if needed, but often not required with strict schema.
    )

    content = resp.choices[0].message.content
    return json.loads(content)


# ------------------------
# Post-processing & normalization (dependencies + CSV-friendly)
# ------------------------
def normalize_record(rec: dict) -> dict:
    """
    - Enforce binary tokens
    - Apply dependency knockouts
    - Clean variable tokens
    - Convert arrays to desired string forms for CSV
    """
    iv_used = normalize_binary_token(rec.get("iv_used", "0"))
    iv_rain = normalize_binary_token(rec.get("iv_rainfall", "n/a"))

    # Dependency: if iv_used != '1', zero-out IV fields
    if iv_used != "1":
        iv_list = []
        iv_rain = "n/a"
        rainfall_metric = []
        rainfall_source = "n/a"
    else:
        iv_list = rec.get("iv_list", [])
        rainfall_metric = rec.get("rainfall_metric", [])
        rainfall_source = rec.get("rainfall_data_source", "n/a")
        # Dependency: if iv_rainfall != '1', clear rainfall details
        if iv_rain != "1":
            rainfall_metric = []
            rainfall_source = "n/a"

    # Clean variables
    dep_vars = [clean_var_token(v) for v in rec.get("dependent_variables", []) if v.strip()]
    endog_vars = [clean_var_token(v) for v in rec.get("endogenous_variables", []) if v.strip()]
    iv_list = [clean_var_token(v) for v in iv_list if v.strip()]
    rainfall_metric = [clean_var_token(v) for v in rainfall_metric if v.strip()]

    # DOI normalization: lowercase + strip wrappers if any slipped through
    doi = (rec.get("doi") or "").strip()
    doi = doi.lower()
    doi = doi.replace("https://doi.org/", "").replace("http://doi.org/", "").replace("doi:", "").strip()
    if doi and not doi.startswith("10."):
        # If model emitted something not DOI-like, set to n/a
        doi = "n/a"
    if not doi:
        doi = "n/a"

    return {
        "Paper Title": (rec.get("paper_title") or "").strip(),
        "DOI": doi,
        "Dependent Variables": "; ".join(dep_vars) if dep_vars else "n/a",
        "Endogenous Variable(s)": "; ".join(endog_vars) if endog_vars else "n/a",
        "Instrumental Variable Used": iv_used,
        "Instrumental Variable(s)": "; ".join(iv_list) if iv_list else "n/a",
        "Instrumental Variable Rainfall": iv_rain,
        "Rainfall Metric": "\n".join(rainfall_metric) if rainfall_metric else "n/a",
        "Rainfall Data Source": rainfall_source if rainfall_source else "n/a",
    }


# ------------------------
# Main driver
# ------------------------
def process_pdfs_single_call(pdf_folder: str, output_csv: str):
    rows = []

    for filename in os.listdir(pdf_folder):
        if not filename.lower().endswith(".pdf"):
            continue

        pdf_path = os.path.join(pdf_folder, filename)
        print(f"\nProcessing {filename}...")

        full_text = extract_text(pdf_path)
        relevant = extract_relevant_sections(full_text)
        print(f"Extracted {len(relevant):,} characters of relevant text")

        try:
            raw = query_model_batch(relevant)
        except Exception as e:
            print(f"Model call failed for {filename}: {e}")
            # Write an all-n/a row except filename
            rows.append({
                "File Name": filename,
                "Paper Title": "n/a",
                "DOI": "n/a",
                "Dependent Variables": "n/a",
                "Endogenous Variable(s)": "n/a",
                "Instrumental Variable Used": "0",
                "Instrumental Variable(s)": "n/a",
                "Instrumental Variable Rainfall": "n/a",
                "Rainfall Metric": "n/a",
                "Rainfall Data Source": "n/a",
            })
            continue

        norm = normalize_record(raw)
        norm["File Name"] = filename
        print(f"Extracted for {filename}: {norm}")
        rows.append(norm)

    df = pd.DataFrame(rows)
    df.to_csv(output_csv, index=False)
    print(f"\nSaved {len(rows)} rows to {output_csv}")


# ------------------------
# CLI paths (edit these)
# ------------------------
if __name__ == "__main__":
    # Update these paths as needed
    pdf_folder = "/Users/kieran/Library/CloudStorage/OneDrive-UniversityofArizona/weather_iv_lit/training/models/finetune_data/pdf_test_20"
    output_folder = "/Users/kieran/Library/CloudStorage/OneDrive-UniversityofArizona/weather_iv_lit/training/models/output"
    os.makedirs(output_folder, exist_ok=True)
    output_csv = os.path.join(output_folder, "batch_output.csv")
    process_pdfs_single_call(pdf_folder, output_csv)