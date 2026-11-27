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


def _part(text):
    """Wrap text in Vertex AI parts format."""
    return [{"text": text}]


def build_record(row):
    """
    Build a complete multi-turn Vertex AI Gemini fine-tuning record from one CSV row.
    Returns None if the row should be skipped (missing filename/title/doi).

    Vertex AI supervised fine-tuning format:
      {
        "systemInstruction": {"role": "system", "parts": [{"text": "..."}]},
        "contents": [
          {"role": "user",  "parts": [{"text": "..."}]},
          {"role": "model", "parts": [{"text": "..."}]},
          ...
        ]
      }
    """
    if not row.get('filename') or not row.get('title') or not row.get('doi'):
        return None

    emp  = norm_bin(row.get('emp_bin', ''))
    end  = norm_bin(row.get('end_bin', ''))
    iv   = norm_bin(row.get('iv_bin', ''))
    rain = norm_bin(row.get('rain_bin', ''))

    doc_context = build_document_context(row)

    contents = [
        {
            "role": "user",
            "parts": _part(
                "You will be asked a sequence of extraction questions about the same academic article. "
                "I am specifically interested in how researchers address endogeneity problems, particularly "
                "using instrumental variables and especially rainfall-based instruments. "
                "Use answers you have already given as context for later questions when helpful, "
                "but always ground your answers in the provided text.\n\n"
                "Here are the relevant sections from the article:\n\n"
                f"{doc_context}"
            ),
        },
        {
            "role": "model",
            "parts": _part("Understood. I will answer each extraction question using only the provided article text."),
        },
    ]

    def add_question(q_key, answer):
        q_text = next(q['question'] for q in QUESTIONS if q['key'] == q_key)
        contents.append({
            "role": "user",
            "parts": _part(f"Question key: {q_key}.\n{q_text}{QUESTION_SUFFIX}"),
        })
        contents.append({"role": "model", "parts": _part(answer)})

    add_question("Title",              val(row, 'title'))
    add_question("DOI",                val(row, 'doi').strip().lower())
    add_question("Empirical Analysis", emp)

    if emp == '1':
        add_question("Dependent Variable(s)",
                     normalize_var_list(val(row, 'dep_var')))
        add_question("Endogeneity Bundle",
                     f"ENDOGENEITY_PROBLEM: {end}\n"
                     f"ENDOGENOUS_VARIABLES: {normalize_var_list(val(row, 'end_var'))}")

    if end == '1':
        add_question("IV Bundle",
                     f"IV_USED: {iv}\n"
                     f"IVS: {normalize_var_list(val(row, 'iv_var'))}")

    if iv == '1':
        add_question("Rainfall IV Bundle",
                     f"RAINFALL_IV: {rain}\n"
                     f"RAINFALL_INSTRUMENT: {normalize_var_list(val(row, 'rain_var'))}")

    return {
        "systemInstruction": {
            "role": "system",
            "parts": _part(SYSTEM_INSTRUCTION),
        },
        "contents": contents,
    }


def prepare_fine_tuning_data(
    csv_input_path,
    training_output_path,
    validation_output_path,
    validation_split=0.125,
    seed=42
):
    """
    Reads CSV with specified columns and prepares JSONL files for Vertex AI Gemini fine-tuning.

    Vertex AI supervised fine-tuning format (one JSON object per line):
      {
        "systemInstruction": {"role": "system", "parts": [{"text": "<system prompt>"}]},
        "contents": [
          {"role": "user",  "parts": [{"text": "..."}]},
          {"role": "model", "parts": [{"text": "..."}]}
        ]
      }

    After generating the JSONL files, upload them to Google Cloud Storage:
      gsutil cp training_gemini.jsonl  gs://YOUR_BUCKET/training_gemini.jsonl
      gsutil cp validation_gemini.jsonl gs://YOUR_BUCKET/validation_gemini.jsonl

    Then submit the fine-tuning job with the Vertex AI SDK:
      import vertexai
      from vertexai.tuning import sft

      vertexai.init(project="YOUR_GCP_PROJECT", location="us-central1")
      sft_job = sft.train(
          source_model="gemini-2.5-flash",
          train_dataset="gs://YOUR_BUCKET/training_gemini.jsonl",
          validation_dataset="gs://YOUR_BUCKET/validation_gemini.jsonl",
          tuned_model_display_name="weather-iv-gemini-flash-v1",
          epochs=3,
          adapter_size="ADAPTER_SIZE_ONE",
          learning_rate_multiplier=1.0,
      )
      print(sft_job.tuned_model_name)  # use this endpoint in finetune_gemini.py
    """
    required_columns = [
        'filename', 'title', 'doi',
        'emp_bin', 'dep_var', 'dep_sec', 'dep_txt',
        'end_bin', 'end_var', 'end_sec', 'end_txt',
        'iv_bin', 'iv_var', 'iv_sec', 'iv_txt',
        'rain_bin', 'rain_var', 'rain_sec', 'rain_txt'
    ]
    encodings_to_try = ['utf-8-sig', 'utf-16', 'utf-16-le', 'utf-16-be', 'cp1252', 'latin1']
    data_entries = []

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
                    record = build_record(row)
                    if record:
                        data_entries.append(record)
                break
        except UnicodeError as e:
            print(f"Failed to read with encoding {encoding}: {e}")
        except Exception as e:
            print(f"An unexpected error occurred with encoding {encoding}: {e}")
    else:
        print("Unable to read the CSV file with the tried encodings.")
        return

    print(f"\nTotal records built: {len(data_entries)}")
    print("\nPreview of first 3 data entries (Vertex AI Gemini format):\n")
    for i, entry in enumerate(data_entries[:3]):
        n_turns = len(entry['contents'])
        print(f"Entry {i + 1} ({n_turns} content turns):")
        print(json.dumps(entry, indent=4, ensure_ascii=False))
        print('-' * 80)

    random.seed(seed)
    random.shuffle(data_entries)
    total_entries = len(data_entries)
    validation_size = int(total_entries * validation_split)
    training_size = total_entries - validation_size

    training_data = data_entries[:training_size]
    validation_data = data_entries[training_size:]

    os.makedirs(os.path.dirname(training_output_path), exist_ok=True)
    os.makedirs(os.path.dirname(validation_output_path), exist_ok=True)

    with open(training_output_path, 'w', encoding='utf-8') as train_file:
        for entry in training_data:
            json.dump(entry, train_file, ensure_ascii=False)
            train_file.write('\n')

    with open(validation_output_path, 'w', encoding='utf-8') as val_file:
        for entry in validation_data:
            json.dump(entry, val_file, ensure_ascii=False)
            val_file.write('\n')

    print(f"Training data written to {training_output_path} ({training_size} records)")
    print(f"Validation data written to {validation_output_path} ({validation_size} records)")

    lint_jsonl(training_output_path)
    lint_jsonl(validation_output_path)


def lint_jsonl(path, max_checks=50):
    """Format check for generated JSONL files."""
    BUNDLE_PAIRS = [
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
                contents = obj.get("contents", [])

                assert "systemInstruction" in obj, \
                    f"item {i}: missing 'systemInstruction' key"
                assert isinstance(contents, list) and len(contents) >= 2, \
                    f"item {i}: 'contents' should have at least 2 entries"
                assert contents[-1].get("role") == "model", \
                    f"item {i}: last content entry must have role 'model'"
                assert len(contents) % 2 == 0, \
                    f"item {i}: contents count must be even, got {len(contents)}"
                assert len(contents) >= 8, \
                    f"item {i}: expected at least 8 content turns, got {len(contents)}"

                for idx, turn in enumerate(contents):
                    expected_role = "user" if idx % 2 == 0 else "model"
                    assert turn.get("role") == expected_role, \
                        f"item {i} contents[{idx}]: expected '{expected_role}', got '{turn.get('role')}'"
                    parts = turn.get("parts", [])
                    assert parts and parts[0].get("text", ""), \
                        f"item {i} contents[{idx}]: text content is empty"

                for key_a, key_b in BUNDLE_PAIRS:
                    for turn in contents:
                        text = (turn.get("parts") or [{}])[0].get("text", "")
                        if key_a in text:
                            assert key_b in text, \
                                f"item {i}: found '{key_a}' without '{key_b}'"

        print(f"Lint OK (checked first {min(i, max_checks)} items): {path}")
    except Exception as e:
        print(f"Lint FAILED for {path}: {e}")


def preview_jsonl_file(file_path, num_entries=3):
    print(f"\nPreviewing the first {num_entries} entries of {file_path}:\n")
    try:
        with open(file_path, 'r', encoding='utf-8') as f:
            for i in range(num_entries):
                line = f.readline()
                if not line:
                    break
                data = json.loads(line)
                n_turns = len(data['contents'])
                print(f"Entry {i + 1} ({n_turns} content turns):")
                print(json.dumps(data, indent=4, ensure_ascii=False))
                print('-' * 80)
    except Exception as e:
        print(f"An error occurred while previewing the file: {e}")


# File paths (update as needed)
csv_input_path = '/Users/kieran/Library/CloudStorage/OneDrive-UniversityofArizona/weather_iv_lit/training/models/finetune_data/train_80.csv'
training_output_path = '/Users/kieran/Library/CloudStorage/OneDrive-UniversityofArizona/weather_iv_lit/training/models/finetune_data/training_gemini.jsonl'
validation_output_path = '/Users/kieran/Library/CloudStorage/OneDrive-UniversityofArizona/weather_iv_lit/training/models/finetune_data/validation_gemini.jsonl'

prepare_fine_tuning_data(csv_input_path, training_output_path, validation_output_path)
preview_jsonl_file(training_output_path, num_entries=3)
preview_jsonl_file(validation_output_path, num_entries=3)
