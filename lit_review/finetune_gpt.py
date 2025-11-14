
import fitz  # PyMuPDF
import os
import pandas as pd
from openai import OpenAI
import re

# ==============================
# CONFIG
# ==============================

client = OpenAI(api_key="key")
fine_tuned_model_id = "ft:gpt-4.1-mini-2025-04-14:aide-lab:update:CbuBEy1P"

pdf_folder = "/Users/kieran/Library/CloudStorage/OneDrive-UniversityofArizona/weather_iv_lit/training/models/finetune_data/pdf_test_20"
output_folder = "/Users/kieran/Library/CloudStorage/OneDrive-UniversityofArizona/weather_iv_lit/training/models/output"
output_csv = os.path.join(output_folder, "finetune_output.csv")

os.makedirs(output_folder, exist_ok=True)

questions = [
    {
        "key": "title",
        "question": (
            "Extract the paper’s exact title from the document. "
            "Return only the title text, strictly no author names or author-related information. "
            "If no title is present, output exactly: n/a."
        ),
    },
    {
        "key": "doi",
        "question": "Extract the DOI of the article. Return only the DOI string or n/a if not present.",
    },
    {
        "key": "emp_bin",
        "question": (
            "Does this paper present a complete empirical analysis? "
            "Respond only with 1 (yes), 0 (no), or n/a (not clear)."
        ),
    },
    {
        "key": "dep_var",
        "question": (
            "Identify only the dependent (outcome) variable used in the main regression analysis. "
            "Return only the variable name, no explanations or extra text. If none, return n/a."
        ),
    },
    {
        "key": "end_bin",
        "question": (
            "Does the paper treat any regressor as endogenous and attempt to address endogeneity? "
            "Reply only 1, 0, or n/a."
        ),
    },
    {
        "key": "end_var",
        "question": (
            "Identify the endogenous explanatory variable(s) used, if any. "
            "Return only variable name(s) separated by semicolons, or n/a with no extra text."
        ),
    },
    {
        "key": "iv_bin",
        "question": "Does the paper use an instrumental variable method? Reply 1, 0, or n/a.",
    },
    {
        "key": "iv_var",
        "question": (
            "Identify the instrumental variable(s) used if any. "
            "Return only names separated by semicolons or n/a."
        ),
        "dependency": {"key": "iv_bin", "value": "1"},
    },
    {
        "key": "rain_bin",
        "question": "Is rainfall used as an instrumental variable in this analysis? Reply 1, 0, or n/a.",
        "dependency": {"key": "iv_bin", "value": "1"},
    },
    {
        "key": "rain_var",
        "question": (
            "Specify the exact precipitation-based instrumental variable (IV) name if present. "
            "This includes any instance in which rainfall is used as an instrumental variable in the analysis. "
            "If you cannot find a rainfall IV respond with n/a."
        ),
        "dependency": {"key": "rain_bin", "value": "1"},
    },
]

# ==============================
# HELPER FUNCTIONS
# ==============================

def normalize_yes_no(answer) -> str:
    """Normalize binary answers to '1', '0', or 'n/a', robust to ints."""
    if answer is None:
        return "n/a"
    answer = str(answer).strip().lower()
    if answer.startswith("yes") or answer == "1":
        return "1"
    if answer.startswith("no") or answer == "0":
        return "0"
    if answer in {"1", "0", "n/a"}:
        return answer
    return "n/a"


def strip_to_variable_names(answer) -> str:
    """
    Clean up variable name answers:
    - Handle n/a
    - Remove URLs, 'Downloaded from', DOIs
    - Split on semicolons
    - Drop author-like / boilerplate chunks
    - Keep only reasonable tokens
    """
    if answer is None:
        return "n/a"

    answer = str(answer)
    low_all = answer.lower().strip()

    if low_all in {"n/a", "na", "none"}:
        return "n/a"

    # If the model just echoes template text, treat as n/a
    if "string or n/a" in low_all or "string or n a" in low_all:
        return "n/a"

    # Remove URLs and boilerplate junk
    answer = re.sub(r"https?://\S+", " ", answer, flags=re.IGNORECASE)
    answer = re.sub(r"doi:\S+", " ", answer, flags=re.IGNORECASE)
    answer = re.sub(r"Downloaded from.*", " ", answer, flags=re.IGNORECASE)

    parts = [v.strip() for v in answer.split(";") if v.strip()]
    cleaned_parts = []

    author_markers = [
        "original submitted", "revision received", "accepted", "abstract",
        "©", "copyright", "journal", "wiley", "springer"
    ]

    for part in parts:
        low = part.lower()

        # Drop obviously huge garbage chunks
        if len(part) > 200:
            continue

        # Drop chunks that contain explicit author/metadata markers
        if any(m in low for m in author_markers):
            continue

        # Keep only reasonable word-like tokens
        tokens = re.findall(r"[\w\-\(\)\.]+", part)
        if not tokens:
            continue

        # If too many tokens, it's probably a sentence/paragraph, not a variable name
        if len(tokens) > 10:
            continue

        cleaned = " ".join(tokens)
        cleaned_parts.append(cleaned)

    return "; ".join(cleaned_parts) if cleaned_parts else "n/a"


def clean_dependent_variables(raw_text: str) -> str:
    """Clean dependent variable list."""
    if not raw_text:
        return "n/a"
    cleaned = re.sub(r"\d+\)\s*", "", str(raw_text))
    variables = [var.strip() for var in cleaned.split(",") if var.strip()]
    return "; ".join(variables) if variables else "n/a"


def clean_title(raw_title: str) -> str:
    """Clean title to a single line without trailing junk."""
    if not raw_title:
        return "n/a"

    raw_title = str(raw_title)
    lines = [l.strip() for l in raw_title.splitlines() if l.strip()]
    if not lines:
        return "n/a"

    title = lines[0]
    title = re.sub(r"\s*\d{4,}\s*$", "", title)  # strip long trailing number
    title = re.sub(r"\s+", " ", title)
    title = title.strip(" ,;.")
    return title if title else "n/a"


def extract_relevant_sections(pdf_path: str) -> str:
    """Extract broadly relevant sections (data, methods, instruments, etc.)."""
    relevant_sections = []
    keywords = [
        "instrument",
        "instrumental variable",
        "data",
        "methods",
        "iv ",
        "rainfall",
        "precipitation",
        "model",
        "econometric",
        "metrics",
        "introduction",
        "abstract",
        "conclusion",
        "strategy",
        "empirical",
        "modeling",
        "approach",
    ]
    with fitz.open(pdf_path) as doc:
        for page_num in range(len(doc)):
            page = doc.load_page(page_num)
            page_text = page.get_text("text")
            paragraphs = page_text.split("\n\n")
            for paragraph in paragraphs:
                if any(keyword.lower() in paragraph.lower() for keyword in keywords):
                    relevant_sections.append(paragraph)
    return " ".join(relevant_sections)


def get_first_page_text(pdf_path: str, char_limit: int = 5000) -> str:
    """Get text from the first page, truncated to char_limit."""
    with fitz.open(pdf_path) as doc:
        page = doc.load_page(0)
        text = page.get_text("text")
    return text[:char_limit]


def extract_iv_sections(pdf_path: str, window_chars: int = 2000) -> str:
    """
    Extract sections specifically around instrumental-variable-related terms.
    This is used for iv_bin, iv_var, rain_bin, rain_var, end_bin, end_var.
    """
    keywords = [
        "instrument",
        "instrumental",
        "endogenous",
        "endogeneity",
        "two-stage",
        "2sls",
        "iv ",
        "iv,",
        "iv.",
    ]
    sections = []

    with fitz.open(pdf_path) as doc:
        for page_num in range(len(doc)):
            page_text = doc.load_page(page_num).get_text("text")
            lowered = page_text.lower()
            for kw in keywords:
                idx = lowered.find(kw)
                if idx != -1:
                    start = max(0, idx - window_chars // 2)
                    end = min(len(page_text), idx + window_chars // 2)
                    sections.append(page_text[start:end])

    return " ".join(sections)


def query_model_single(text: str, question: str, enforce_binary: bool = False, strip_vars: bool = False) -> str:
    """Query the fine-tuned model for a single field."""
    if enforce_binary:
        constraint_text = (
            "Valid outputs are strictly: 1, 0, or n/a.\n"
            "- 1 = yes\n"
            "- 0 = no\n"
            "- n/a = not clear from the text\n"
            "You MUST answer with exactly one of: 1, 0, n/a. No other text."
        )
    else:
        constraint_text = (
            "Answer with a short phrase only, no full sentences, no explanations, "
            "no surrounding quotes, and no line breaks. If uncertain, answer exactly: n/a."
        )

    user_query = (
        f"{question}\n\n"
        "Paper excerpt:\n"
        f"{text}\n\n"
        "Instructions:\n"
        f"{constraint_text}"
    )

    try:
        response = client.chat.completions.create(
            model=fine_tuned_model_id,
            messages=[
                {
                    "role": "system",
                    "content": (
                        "You are an AI assistant expert in economics paper analysis. "
                        "You must follow the user's instructions about allowed output formats exactly. "
                        "Never include explanations, prose, or multiple lines. "
                        "If the correct answer is unclear, output exactly: n/a."
                    ),
                },
                {"role": "user", "content": user_query},
            ],
            max_tokens=50,
            temperature=0,
        )
        answer = response.choices[0].message.content.strip()

        if enforce_binary:
            return normalize_yes_no(answer)
        if strip_vars:
            return strip_to_variable_names(answer)

        return answer if answer else "n/a"

    except Exception as e:
        print(f"Error querying model: {e}")
        return "n/a"


def fix_logical_consistency(info_dict: dict) -> dict:
    """
    Post-hoc logic to enforce consistency between *_bin and *_var fields.
    - If we have a non-n/a iv_var, force iv_bin = 1.
    - If iv_bin == 1 but iv_var == n/a, downgrade iv_bin to n/a.
    - If we have a non-n/a rain_var, force rain_bin = 1.
    - If rain_bin == 1 but rain_var == n/a, try to infer rainfall IV from iv_var;
      if that fails, downgrade rain_bin to n/a.
    """

    # IV consistency
    iv_bin = normalize_yes_no(info_dict.get("iv_bin", "n/a"))
    iv_var_raw = info_dict.get("iv_var", "") or ""
    iv_var_clean = strip_to_variable_names(iv_var_raw)
    info_dict["iv_var"] = iv_var_clean

    if iv_var_clean != "n/a":
        info_dict["iv_bin"] = "1"
    elif iv_bin == "1" and iv_var_clean == "n/a":
        info_dict["iv_bin"] = "n/a"

    # Endogenous variable consistency
    end_bin = normalize_yes_no(info_dict.get("end_bin", "n/a"))
    end_var_raw = info_dict.get("end_var", "") or ""
    end_var_clean = strip_to_variable_names(end_var_raw)
    info_dict["end_var"] = end_var_clean

    if end_var_clean != "n/a":
        info_dict["end_bin"] = "1"
    elif end_bin == "1" and end_var_clean == "n/a":
        info_dict["end_bin"] = "n/a"

    # Rain consistency
    rain_bin = normalize_yes_no(info_dict.get("rain_bin", "n/a"))
    rain_var_raw = info_dict.get("rain_var", "") or ""
    rain_var_clean = strip_to_variable_names(rain_var_raw)

    # If we already have a clean rain_var, force rain_bin = 1
    if rain_var_clean != "n/a":
        info_dict["rain_var"] = rain_var_clean
        info_dict["rain_bin"] = "1"
    else:
        # No clean rain_var; try to infer from iv_var
        rain_like = []
        for part in iv_var_clean.split(";"):
            if re.search(r"rain|precip", part, re.IGNORECASE):
                rain_like.append(part.strip())

        if rain_like:
            info_dict["rain_var"] = "; ".join(rain_like)
            info_dict["rain_bin"] = "1"
        elif rain_bin == "1":
            # Claimed rainfall IV but couldn't identify any
            info_dict["rain_bin"] = "n/a"
            info_dict["rain_var"] = "n/a"
        else:
            info_dict["rain_var"] = "n/a"
            info_dict["rain_bin"] = rain_bin if rain_bin in {"0", "n/a"} else "n/a"

    return info_dict

# ==============================
# MAIN PROCESSING FUNCTION
# ==============================

def process_pdfs_conditional_queries(pdf_folder: str, output_csv: str):
    data = []

    for filename in os.listdir(pdf_folder):
        if not filename.endswith(".pdf"):
            continue

        pdf_path = os.path.join(pdf_folder, filename)
        print(f"\nProcessing {filename}...")

        relevant_sections = extract_relevant_sections(pdf_path)
        first_page_text = get_first_page_text(pdf_path)
        iv_sections = extract_iv_sections(pdf_path)

        print(f"Extracted relevant sections length: {len(relevant_sections)} characters")
        max_tokens = 5000  # rough limit
        text_to_analyze = relevant_sections[: max_tokens * 4]

        info_dict = {q["key"]: "n/a" for q in questions}
        info_dict["filename"] = filename
        temp_answers = {}

        for q in questions:
            key = q["key"]

            # Handle dependencies
            if "dependency" in q:
                dep_key = q["dependency"]["key"]
                dep_value = q["dependency"]["value"]
                if temp_answers.get(dep_key, info_dict.get(dep_key)) != dep_value:
                    info_dict[key] = "n/a"
                    temp_answers[key] = "n/a"
                    print(
                        f"Skipping '{key}' due to unmet dependency "
                        f"({dep_key} != {dep_value})"
                    )
                    continue

            enforce_binary = key.endswith("_bin")
            strip_vars = key in {"dep_var", "end_var", "iv_var", "rain_var"}

            # Choose context based on the question
            if key in {"title", "doi"}:
                text_for_q = first_page_text
            elif key in {"end_bin", "end_var", "iv_bin", "iv_var", "rain_bin", "rain_var"}:
                text_for_q = iv_sections or text_to_analyze
            else:
                text_for_q = text_to_analyze

            print(f"Querying: {q['question']}")
            answer = query_model_single(
                text_for_q,
                q["question"],
                enforce_binary=enforce_binary,
                strip_vars=strip_vars,
            )

            if key == "dep_var" and answer != "n/a":
                answer = clean_dependent_variables(answer)
            if key == "title" and answer != "n/a":
                answer = clean_title(answer)

            info_dict[key] = answer
            temp_answers[key] = answer
            print(f"Answer for {key}: {answer}")

        # Enforce cross-field consistency (end_*, iv_*, rain_*)
        info_dict = fix_logical_consistency(info_dict)
        print("After consistency check:")
        print(
            f"  end_bin={info_dict['end_bin']}, end_var={info_dict['end_var']}\n"
            f"  iv_bin={info_dict['iv_bin']}, iv_var={info_dict['iv_var']}\n"
            f"  rain_bin={info_dict['rain_bin']}, rain_var={info_dict['rain_var']}"
        )

        data.append(info_dict)

    df = pd.DataFrame(data)
    df.to_csv(output_csv, index=False)
    print(f"\nData saved to {output_csv}")


# ==============================
# RUN
# ==============================

if __name__ == "__main__":
    process_pdfs_conditional_queries(pdf_folder, output_csv)
