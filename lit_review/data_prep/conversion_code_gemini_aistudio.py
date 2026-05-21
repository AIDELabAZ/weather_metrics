import csv
import json
import os
import random

# Exact system instruction from finetune_gemini.py — must match inference verbatim
SYSTEM_INSTRUCTION = (
    "You are an AI assistant that is an expert in analysis of economic literature. "
    "You interpret complex content and extract specific information, especially about "
    "empirical methods, endogeneity problems, and instrumental variable strategies. "
    "Rules: Use only information from the provided text to answer each query. "
    "If the requested information is not available, answer exactly n/a. "
    "Follow the requested output format exactly. "
    "Exclusions: Do not include the user queries, any labels, greek letters, or additional text beyond what is requested. "
    "Do not respond with symbolic notation, only words. "
    "For binary questions with justification requests, always start with 0 or 1"
)

# Question texts copied verbatim from finetune_gemini.py
QUESTIONS = [
    {
        "key": "Title",
        "question": (
            "Task: Extract the article title.\nLook: top of first page (main heading before authors/abstract).\nRules: include subtitle if in the same heading; exclude authors/affiliations/journal headers/footers/section headers; ignore footnote markers (*, †, superscripts).\nOutput: ONE line: title text only. No quotes, labels, or extra words."
        ),
    },
    {
        "key": "DOI",
        "question": (
            "Task: Extract the DOI of THIS article (version of record), not DOIs in references.\nLook: first page/front matter for doi:, DOI, https://doi.org/.\nRules: remove URL/prefix (doi:, https://doi.org/); remove spaces/line breaks; strip trailing punctuation; output lowercase.\nOutput: ONE token = normalized DOI (10.xxxx/xxxx) OR exactly n/a."
        ),
    },
    {
        "key": "Empirical Analysis",
        "question": (
            "Task: Does the article contain empirical quantitative statistical estimation (e.g., regressions/econometrics with estimated coefficients/SEs/p-values)?\nLook: 'we estimate/regress', model equations with error terms, regression tables with coefficients.\nRules: do NOT infer from topic/title/abstract. Count only analysis done in THIS article (not summaries of other papers). Exclude purely theoretical work, qualitative/descriptive only, and simulation/calibration only.\nOutput: 1 if yes, 0 if no. Output exactly one character."
        ),
    },
    {
        "key": "Dependent Variable(s)",
        "question": (
            "Task: List the main dependent/outcome variable(s) used in the primary regression/econometric results.\nLook: LHS of main equations; column headers of main regression tables; text describing the main empirical model.\nRules: exclude first-stage outcomes, RHS variables (treatments/endogenous regressors/instruments/controls/covariates/fixed effects), mediators/moderators.\nKeep names exactly as written in the paper/table (including any log/ln/differences/units if shown).\nOutput: ONE line: variable name(s) only; separate multiple with '; '."
        ),
    },
    {
        "key": "Endogeneity Bundle",
        "question": (
            "Only proceed if the text contains empirical quantitative statistical analysis. "
            "Answer BOTH parts below using ONLY the provided article text.\n\n"
            "Part A (binary): Task: In the MAIN empirical analysis, do the authors treat any RHS variable as endogenous (correlated with the error term) and address it explicitly?\nLook: statements that a regressor is endogenous + a method to address it (IV/2SLS/3SLS/LIML, control function/2SRI, GMM with instruments, first stage, weak-IV tests, etc.).\nRules: do NOT count generic mentions of 'endogeneity' without an actual endogenous regressor in the main specs.\nOutput: 1 if yes, 0 if no. Output exactly one character."
            "Part B (list): Task: If endogenous explanatory variable(s) exist in this paper, list the explanatory variable(s) explicitly treated as endogenous in the main analysis.\nLook: 'we instrument X', 'X is endogenous', first-stage descriptions/tables, reduced form, weak-IV/overid tests.\nRules: exclude instruments, dependent variables, and ordinary controls.\nKeep names exactly as written in the paper/table (including any log/ln/differences/units if shown).\nOutput: ONE line: variable name(s) only; separate multiple with '; '."
            "Output format (EXACTLY requested information, no extra text):\n"
            "ENDOGENEITY_PROBLEM: <0 or 1>\n"
            "ENDOGENOUS_VARIABLES: <semicolon-separated list; or n/a>"
        ),
    },
    {
        "key": "IV Bundle",
        "question": (
            "Answer BOTH parts below using ONLY the provided article text.\n\n"
            "Part A (binary): Task: In the MAIN empirical analysis, do the authors implement an IV-type estimator with excluded instruments to address endogeneity?\nLook: an actual excluded instrument set used in a first stage/reduced form; 2SLS/IV/3SLS/LIML; IV-Probit; control function/2SRI; GMM with instruments; exclusion restriction; first-stage equations/tables.\nRules: do NOT count non-statistical uses of 'instrument' (survey instrument, measurement instrument) or papers that only use RCT/RDD/DiD/event study without an IV first stage.\nOutput: 1 if yes, 0 if no. Output exactly one character."
            "Part B (list): Task: List the excluded instrument(s) used in the main IV analysis.\nLook: 'we instrument X with Z', 'Z is our instrument', 'excluded instrument', first-stage/reduced-form equations or tables.\nRules: exclude endogenous regressors themselves, dependent variables, and regular controls.\nKeep names exactly as written in the paper/table (including any log/ln/differences/units if shown).\nOutput: ONE line: instrument name(s) only; separate multiple with '; '."
            "Output format (EXACTLY requested information, no extra text):\n"
            "IV_USED: <0 or 1>\n"
            "IVS: <semicolon-separated list; or n/a>"
        ),
    },
    {
        "key": "Rainfall IV Bundle",
        "question": (
            "Answer BOTH parts below using ONLY the provided article text.\n\n"
            "Part A (binary): Task: Is any excluded instrument based on rainfall/precipitation?\nLook: rainfall, precipitation, drought, monsoon rainfall/onset, wet-day counts, SPI/SPEI/PDSI, precipitation-derived indices used as the EXCLUDED instrument.\nRules: count only if precipitation-based and used as an excluded instrument in an IV first stage/reduced form. Do NOT count precipitation used only as regressor/control/interaction/exposure/outcome. Do NOT count ENSO or other climate indices unless explicitly stated to be precipitation-based AND used as the excluded instrument. Ignore mentions in other papers.\nOutput: 1 if yes, 0 if no. Output exactly one character."
            "Part B (detail): Task: List the specific rainfall/precipitation-based excluded instrument(s) used in the main IV analysis.\nLook: first-stage/reduced-form equations/tables for the precipitation-based instrument name(s) (e.g., total/mean rainfall over a window, rainfall deviations/shocks, monsoon onset, rainfall index, coefficient of variation of rainfall).\nRules: keep names exactly as written in the paper/table (including window/statistic/units/logs if shown).\nOutput: ONE line: rainfall instrument name(s) only; separate multiple with '; '. If Part A != 1, output n/a.\n\n"
            "Output format (EXACTLY requested information, no extra text):\n"
            "RAINFALL_IV: <0 or 1>\n"
            "RAINFALL_INSTRUMENT: <detailed semicolon-separated description(s); or n/a>"
        ),
    },
]

QUESTION_SUFFIX = (
    "\n\nAnswer using only the article text above and, if helpful, your previous answers in this conversation. "
    "Remember to follow the required output format exactly."
)


def fix_encoding(s):
    """Repair mojibake iteratively until stable.

    Handles:
    - Single-level cp1252 mojibake (â€™ → ')
    - Multi-level encoding (Ã¢â‚¬Ëœ → â€˜ → ')
    - Mixed cp1252/latin-1 per-char (â€\\x9d → ")
    - Strings with Greek letters (passed through unchanged)
    """
    if not s:
        return s

    def _char_bytes(ch):
        try:
            return ch.encode('cp1252')
        except UnicodeEncodeError:
            try:
                return ch.encode('latin-1')
            except UnicodeEncodeError:
                return None

    def _repair_once(text):
        try:
            return text.encode('cp1252').decode('utf-8')
        except (UnicodeEncodeError, UnicodeDecodeError):
            pass
        result = []
        i = 0
        while i < len(text):
            fixed = False
            for length in (3, 2):
                if i + length <= len(text):
                    chunk = text[i:i+length]
                    char_bytes = [_char_bytes(c) for c in chunk]
                    if None not in char_bytes:
                        raw = b''.join(char_bytes)
                        try:
                            result.append(raw.decode('utf-8'))
                            i += length
                            fixed = True
                            break
                        except UnicodeDecodeError:
                            pass
            if not fixed:
                result.append(text[i])
                i += 1
        return ''.join(result)

    prev = None
    while s != prev:
        prev = s
        s = _repair_once(s)
    return s


def val(row, key):
    """Return field value or 'n/a' for missing/empty fields, with encoding repair."""
    return fix_encoding(row.get(key) or 'n/a')


def norm_bin(v):
    """Normalize a CSV binary field ('1', '1.0', '0', '0.0', '') to '1' or '0'."""
    s = (v or '').strip()
    return '1' if s in ('1', '1.0') else '0'


def normalize_var_list(v):
    """Clean a CSV variable-name string into inference output format ('; '-separated or 'n/a')."""
    if not v or not v.strip():
        return 'n/a'
    txt = v.strip().replace('\r', ' ').replace('\n', ' ')
    parts = [p.strip() for p in txt.split(';') if p.strip()]
    return '; '.join(parts) if parts else 'n/a'


def build_document_context(row):
    """Combine text excerpts from the CSV into a deduplicated 'relevant sections' block."""
    seen = set()
    excerpts = []
    for col in ('dep_txt', 'end_txt', 'iv_txt', 'rain_txt'):
        text = fix_encoding((row.get(col) or '').strip())
        if text and text not in seen:
            seen.add(text)
            excerpts.append(text)
    return '\n\n'.join(excerpts)


def build_text_input(doc_context, prior_qa_pairs, current_key, current_question):
    """
    Build the text_input string for a single Q/A training example.

    Format:
      {SYSTEM_INSTRUCTION}

      Article sections:
      {doc_context}

      [Previous answers: ... (if any prior pairs)]

      Question key: {current_key}.
      {current_question}

      Answer using only the article text above...
    """
    parts = [SYSTEM_INSTRUCTION, ""]

    parts.append("Article sections:")
    parts.append(doc_context)

    if prior_qa_pairs:
        parts.append("")
        parts.append("Previous answers:")
        for q_key, q_text, a_text in prior_qa_pairs:
            parts.append(f"Q: Question key: {q_key}.")
            parts.append(q_text)
            parts.append(f"A: {a_text}")
            parts.append("")

    parts.append(f"Question key: {current_key}.")
    parts.append(current_question)
    parts.append(QUESTION_SUFFIX.strip())

    return "\n".join(parts)


def build_records(row):
    """
    Build a list of Google AI Studio fine-tuning records from one CSV row.
    Each record is {"text_input": "...", "output": "..."}.
    Returns empty list if the row should be skipped (missing filename/title/doi).

    Dependency logic:
    - emp=1 gates: Dependent Variable(s), Endogeneity Bundle
    - end=1 gates: IV Bundle
    - iv=1 gates: Rainfall IV Bundle
    """
    if not row.get('filename') or not row.get('title') or not row.get('doi'):
        return []

    emp  = norm_bin(row.get('emp_bin', ''))
    end  = norm_bin(row.get('end_bin', ''))
    iv   = norm_bin(row.get('iv_bin', ''))
    rain = norm_bin(row.get('rain_bin', ''))

    doc_context = build_document_context(row)

    # List of (key, question_text, answer_text) tuples in the order they are asked
    qa_sequence = []

    def get_q_text(key):
        return next(q['question'] for q in QUESTIONS if q['key'] == key)

    def add_qa(key, answer):
        """Append a Q/A pair and emit a training record for it."""
        q_text = get_q_text(key)
        text_input = build_text_input(doc_context, qa_sequence, key, q_text)
        record = {"text_input": text_input, "output": answer}
        # Now add this pair to the history for subsequent questions
        qa_sequence.append((key, q_text, answer))
        return record

    records = []

    records.append(add_qa("Title", val(row, 'title')))
    records.append(add_qa("DOI", val(row, 'doi').strip().lower()))
    records.append(add_qa("Empirical Analysis", emp))

    if emp == '1':
        records.append(add_qa(
            "Dependent Variable(s)",
            normalize_var_list(val(row, 'dep_var'))
        ))
        records.append(add_qa(
            "Endogeneity Bundle",
            f"ENDOGENEITY_PROBLEM: {end}\n"
            f"ENDOGENOUS_VARIABLES: {normalize_var_list(val(row, 'end_var'))}"
        ))

    if end == '1':
        records.append(add_qa(
            "IV Bundle",
            f"IV_USED: {iv}\n"
            f"IVS: {normalize_var_list(val(row, 'iv_var'))}"
        ))

    if iv == '1':
        records.append(add_qa(
            "Rainfall IV Bundle",
            f"RAINFALL_IV: {rain}\n"
            f"RAINFALL_INSTRUMENT: {normalize_var_list(val(row, 'rain_var'))}"
        ))

    return records


def prepare_fine_tuning_data(
    csv_input_path,
    training_output_path,
    validation_output_path,
    validation_split=0.125,
    seed=42
):
    """
    Reads CSV and prepares JSONL files for Google AI Studio Gemini fine-tuning.

    Google AI Studio fine-tuning format (one JSON object per line):
      {"text_input": "...", "output": "..."}

    Each CSV row produces multiple training examples (one per question/answer pair),
    with full preceding context included in text_input.
    """
    required_columns = [
        'filename', 'title', 'doi',
        'emp_bin', 'dep_var', 'dep_sec', 'dep_txt',
        'end_bin', 'end_var', 'end_sec', 'end_txt',
        'iv_bin', 'iv_var', 'iv_sec', 'iv_txt',
        'rain_bin', 'rain_var', 'rain_sec', 'rain_txt'
    ]
    encodings_to_try = ['utf-8-sig', 'utf-16', 'utf-16-le', 'utf-16-be', 'cp1252', 'latin1']
    all_records = []

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
                    row_records = build_records(row)
                    all_records.extend(row_records)
                break
        except UnicodeError as e:
            print(f"Failed to read with encoding {encoding}: {e}")
        except Exception as e:
            print(f"An unexpected error occurred with encoding {encoding}: {e}")
    else:
        print("Unable to read the CSV file with the tried encodings.")
        return

    print(f"\nTotal training examples built: {len(all_records)}")

    random.seed(seed)
    random.shuffle(all_records)

    total = len(all_records)
    validation_size = int(total * validation_split)
    training_size = total - validation_size

    training_data = all_records[:training_size]
    validation_data = all_records[training_size:]

    os.makedirs(os.path.dirname(training_output_path), exist_ok=True)
    os.makedirs(os.path.dirname(validation_output_path), exist_ok=True)

    with open(training_output_path, 'w', encoding='utf-8') as f:
        for record in training_data:
            json.dump(record, f, ensure_ascii=False)
            f.write('\n')

    with open(validation_output_path, 'w', encoding='utf-8') as f:
        for record in validation_data:
            json.dump(record, f, ensure_ascii=False)
            f.write('\n')

    print(f"Training data written to {training_output_path} ({training_size} records)")
    print(f"Validation data written to {validation_output_path} ({validation_size} records)")

    lint_jsonl(training_output_path)
    lint_jsonl(validation_output_path)


def lint_jsonl(path, max_checks=50):
    """Format check for generated JSONL files."""
    BUNDLE_KEYS = [
        ('ENDOGENEITY_PROBLEM', 'ENDOGENOUS_VARIABLES'),
        ('IV_USED', 'IVS'),
        ('RAINFALL_IV', 'RAINFALL_INSTRUMENT'),
    ]
    try:
        with open(path, 'r', encoding='utf-8') as f:
            for i, line in enumerate(f, 1):
                if i > max_checks:
                    break
                obj = json.loads(line)

                assert "text_input" in obj, f"item {i}: missing 'text_input' key"
                assert "output" in obj, f"item {i}: missing 'output' key"
                assert obj["text_input"].strip(), f"item {i}: 'text_input' is empty"
                assert obj["output"].strip(), f"item {i}: 'output' is empty"
                assert SYSTEM_INSTRUCTION[:40] in obj["text_input"], \
                    f"item {i}: text_input does not begin with SYSTEM_INSTRUCTION"
                assert "Article sections:" in obj["text_input"], \
                    f"item {i}: text_input missing 'Article sections:' header"
                assert "Question key:" in obj["text_input"], \
                    f"item {i}: text_input missing 'Question key:'"

                output = obj["output"]
                for key_a, key_b in BUNDLE_KEYS:
                    if key_a in output:
                        assert key_b in output, \
                            f"item {i}: output has '{key_a}' without '{key_b}'"

        print(f"Lint OK (checked first {min(i, max_checks)} items): {path}")
    except Exception as e:
        print(f"Lint FAILED for {path}: {e}")


def preview_jsonl_file(file_path, num_entries=2):
    print(f"\nPreviewing the first {num_entries} entries of {file_path}:\n")
    try:
        with open(file_path, 'r', encoding='utf-8') as f:
            for i in range(num_entries):
                line = f.readline()
                if not line:
                    break
                data = json.loads(line)
                print(f"Entry {i + 1}:")
                # Show truncated text_input and full output
                text_input = data.get("text_input", "")
                output = data.get("output", "")
                print(f"  text_input ({len(text_input)} chars): {text_input[:300]}...")
                print(f"  output: {output}")
                print('-' * 80)
    except Exception as e:
        print(f"An error occurred while previewing the file: {e}")


# File paths
csv_input_path = '/Users/kieran/Library/CloudStorage/OneDrive-UniversityofArizona/weather_iv_lit/training/models/finetune_data/train_80.csv'
training_output_path = '/Users/kieran/Library/CloudStorage/OneDrive-UniversityofArizona/weather_iv_lit/training/models/finetune_data/training_gemini_aistudio.jsonl'
validation_output_path = '/Users/kieran/Library/CloudStorage/OneDrive-UniversityofArizona/weather_iv_lit/training/models/finetune_data/validation_gemini_aistudio.jsonl'

prepare_fine_tuning_data(csv_input_path, training_output_path, validation_output_path)
preview_jsonl_file(training_output_path, num_entries=2)
preview_jsonl_file(validation_output_path, num_entries=2)
