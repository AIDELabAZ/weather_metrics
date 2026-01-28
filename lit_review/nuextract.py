import fitz  # PyMuPDF
import os
import pandas as pd
import json
import torch
from transformers import AutoModelForCausalLM, AutoTokenizer
import re
import gc


# -------------------------------------------------------------------
# Config knobs you can tweak
# -------------------------------------------------------------------

# Use the stable tiny version
MODEL_NAME = "numind/NuExtract-tiny"

# Enable M1 GPU (MPS)
if torch.backends.mps.is_available():
    DEVICE = "mps"
    # Set memory limit to prevent crashes
    os.environ['PYTORCH_MPS_HIGH_WATERMARK_RATIO'] = '0.0'
elif torch.cuda.is_available():
    DEVICE = "cuda"
else:
    DEVICE = "cpu"

print(f"Using device: {DEVICE}")

print(f"Loading {MODEL_NAME} on {DEVICE}...")
try:
    model = AutoModelForCausalLM.from_pretrained(
        MODEL_NAME,
        dtype=torch.float16 if DEVICE in ["cuda", "mps"] else torch.float32,
        trust_remote_code=True,
        low_cpu_mem_usage=True
    )
    model = model.to(DEVICE)
    model.eval()
    tokenizer = AutoTokenizer.from_pretrained(MODEL_NAME, trust_remote_code=True)
    print("Model loaded successfully!\n")
except Exception as e:
    print(f"Error loading model: {e}")
    print("Trying alternative loading method...")
    from transformers import AutoModel
    model = AutoModel.from_pretrained(
        MODEL_NAME,
        dtype=torch.float32,
        trust_remote_code=True
    )
    model = model.to(DEVICE)
    tokenizer = AutoTokenizer.from_pretrained(MODEL_NAME, trust_remote_code=True)
    print("Model loaded with fallback method!\n")


# -------------------------------------------------------------------
# Memory management
# -------------------------------------------------------------------

def clear_gpu_memory():
    """Clear GPU memory cache"""
    if DEVICE == "mps":
        torch.mps.empty_cache()
    elif DEVICE == "cuda":
        torch.cuda.empty_cache()
    gc.collect()


# -------------------------------------------------------------------
# NuExtract inference function
# -------------------------------------------------------------------

def predict_nuextract(model, tokenizer, text, schema):
    """Extract structured information using NuExtract."""
    schema_str = json.dumps(json.loads(schema), indent=4)
    
    # Add explicit instructions
    instructions = """Extract information from the academic paper text below. Follow these rules:
- For yes/no fields: answer only "yes" or "no"
- For variables: extract the actual variable names from the paper, not descriptions
- For rainfall_metric: extract the specific measurement (e.g. "log annual rainfall", "monthly precipitation"), not just "rainfall"
- If information is not found, leave the field empty
- Extract verbatim text when possible

"""
    
    input_llm = f"<|input|>\n{instructions}### Template:\n{schema_str}\n### Text:\n{text}\n<|output|>\n"
    
    input_ids = tokenizer(
        input_llm, 
        return_tensors="pt", 
        truncation=True, 
        max_length=2500  # Reduced from 3500 to save memory
    ).to(DEVICE)
    
    with torch.no_grad():
        output = model.generate(
            **input_ids, 
            max_new_tokens=400,
            use_cache=False,
            do_sample=False,
            temperature=None,
            top_p=None
        )
        output_text = tokenizer.decode(output[0], skip_special_tokens=True)
    
    # Clear input tensors immediately
    del input_ids
    del output
    clear_gpu_memory()
    
    try:
        result = output_text.split("<|output|>")[1].strip()
        if "<|end-output|>" in result:
            result = result.split("<|end-output|>")[0].strip()
        return json.loads(result)
    except (IndexError, json.JSONDecodeError) as e:
        print(f"Error parsing NuExtract output: {e}")
        print(f"Raw output: {output_text[:800]}")
        return {}


# -------------------------------------------------------------------
# Validation function
# -------------------------------------------------------------------

def validate_extraction(extracted, key, value):
    """Check if extracted value is actually valid or just echoing the schema"""
    if not value or value == "":
        return True  # Empty is ok
    
    str_value = str(value).lower()
    
    # Check if it's echoing the question/hint
    bad_phrases = [
        "yes or no", "what is", "what are", "which", "how was", 
        "does the paper", "are any", "if rainfall", "extract", "answer",
        "used in the", "treated as", "measured", "source of"
    ]
    
    if any(phrase in str_value for phrase in bad_phrases):
        print(f"  ⚠ Rejected {key}: echoing schema question")
        return False
    
    # For rainfall metrics, must have a modifier (not just "rainfall")
    if key == "rainfall_metric":
        if isinstance(value, list):
            for item in value:
                item_str = str(item).strip().lower()
                # Check if it's ONLY rainfall/precipitation without modifiers
                if item_str in ["rainfall", "precipitation", "rain", "precip"]:
                    print(f"  ⚠ Rejected rainfall_metric: too generic ('{item}')")
                    return False
                # Must contain rainfall/precip AND something else
                has_rain_term = any(term in item_str for term in ["rainfall", "precipitation", "rain", "precip"])
                if has_rain_term and len(item_str.split()) < 2:
                    print(f"  ⚠ Rejected rainfall_metric: needs specific metric ('{item}')")
                    return False
        elif str_value in ["rainfall", "precipitation", "rain", "precip"]:
            print(f"  ⚠ Rejected rainfall_metric: too generic")
            return False
    
    # For instrumental variables, reject if it's too generic
    if key == "instrumental_variables":
        if isinstance(value, list):
            for item in value:
                item_str = str(item).strip().lower()
                if item_str in ["yes", "no", "instrumental variable", "iv", "instrument"]:
                    print(f"  ⚠ Rejected IV: too generic ('{item}')")
                    return False
    
    return True


# -------------------------------------------------------------------
# Cleaning helpers (adapted for NuExtract output)
# -------------------------------------------------------------------

def normalize_yes_no(answer):
    """Convert various yes/no formats to 1/0/n/a"""
    if answer is None or answer == "":
        return "n/a"
    if isinstance(answer, int):
        return "1" if answer == 1 else "0" if answer == 0 else "n/a"
    if isinstance(answer, str):
        a = answer.strip().lower()
        if a in {"yes", "1", "true"}:
            return "1"
        if a in {"no", "0", "false"}:
            return "0"
    return "n/a"


def clean_variable_list(raw_value, validated=True):
    """Clean and format variable lists from NuExtract output"""
    if not validated:
        return "n/a"
    
    if raw_value is None or raw_value == "":
        return "n/a"
    
    # Handle list outputs
    if isinstance(raw_value, list):
        if not raw_value:
            return "n/a"
        cleaned = [str(v).strip() for v in raw_value if v and str(v).strip()]
        return "; ".join(cleaned[:3])  # Limit to 3 items
    
    # Handle string outputs
    if isinstance(raw_value, str):
        txt = raw_value.strip()
        if txt.lower() in {"n/a", "na", "none", "null", ""}:
            return "n/a"
        
        # Split on semicolons or commas
        parts = re.split(r"[;,]", txt)
        cleaned = [p.strip() for p in parts if p.strip()]
        return "; ".join(cleaned[:3])
    
    return "n/a"


def clean_string_field(raw_value, validated=True):
    """Clean single string fields"""
    if not validated:
        return "n/a"
    
    if raw_value is None or raw_value == "":
        return "n/a"
    if isinstance(raw_value, str):
        txt = raw_value.strip()
        return txt if txt and txt.lower() not in {"n/a", "na", "none", "null"} else "n/a"
    return str(raw_value)


# -------------------------------------------------------------------
# Rainfall inference helpers
# -------------------------------------------------------------------

RAINFALL_TERMS = [
    "rainfall", "precipitation", "rain", "precip",
    "monsoon", "drought", "shocks", "weather", "typhoon", "hurricane", "storm"
]


def iv_list_mentions_rainfall(iv_list_text: str) -> bool:
    if not iv_list_text or iv_list_text == "n/a":
        return False
    t = iv_list_text.lower()
    return any(term in t for term in RAINFALL_TERMS)


def extract_rainfall_metrics_from_iv_list(iv_list_text: str) -> str:
    """Extract rainfall-related instruments from IV list"""
    if not iv_list_text or iv_list_text == "n/a":
        return "n/a"
    
    parts = [p.strip() for p in iv_list_text.split(";") if p.strip()]
    keep = []
    for p in parts:
        pl = p.lower()
        # Only keep if it mentions rainfall AND has additional context
        if any(term in pl for term in RAINFALL_TERMS) and len(pl.split()) >= 2:
            keep.append(p)
    
    return "; ".join(keep) if keep else "n/a"


# -------------------------------------------------------------------
# Dependency consistency enforcer
# -------------------------------------------------------------------

def enforce_dependency_consistency(temp_answers, *, verbose=False):
    is_paper = temp_answers.get("Is Academic Paper", "0")
    iv_used = temp_answers.get("Instrumental Variable Used", "n/a")
    rain_iv = temp_answers.get("Instrumental Variable Rainfall", "n/a")
    
    # Academic gate
    if is_paper != "1":
        for k in [
            "Paper Title", "DOI", "Dependent Variables", "Endogenous Variable(s)",
            "Instrumental Variable Used", "Instrumental Variable(s)",
            "Instrumental Variable Rainfall", "Rainfall Metric", "Rainfall Data Source"
        ]:
            temp_answers[k] = "n/a"
        return temp_answers
    
    # IV gate
    if iv_used != "1":
        temp_answers["Instrumental Variable(s)"] = "n/a"
        temp_answers["Instrumental Variable Rainfall"] = "n/a"
        temp_answers["Rainfall Metric"] = "n/a"
        temp_answers["Rainfall Data Source"] = "n/a"
        return temp_answers
    
    # If IV list implies rainfall, force rainfall flag to 1
    iv_list = temp_answers.get("Instrumental Variable(s)", "")
    if iv_list_mentions_rainfall(iv_list):
        if verbose and temp_answers.get("Instrumental Variable Rainfall") != "1":
            print("  → Overriding Instrumental Variable Rainfall -> 1 (IV list mentions rainfall)")
        temp_answers["Instrumental Variable Rainfall"] = "1"
        rain_iv = "1"
    
    # Rainfall gate
    if rain_iv != "1":
        temp_answers["Rainfall Metric"] = "n/a"
        temp_answers["Rainfall Data Source"] = "n/a"
        return temp_answers
    
    # If rainfall IV = 1 and rainfall metric is missing, fill from IV list
    rm = (temp_answers.get("Rainfall Metric") or "").strip().lower()
    if rm in {"", "n/a", "0", "1"}:
        inferred = extract_rainfall_metrics_from_iv_list(iv_list)
        if inferred != "n/a":
            if verbose:
                print("  → Filling Rainfall Metric from IV list")
            temp_answers["Rainfall Metric"] = inferred
    
    return temp_answers


# -------------------------------------------------------------------
# PDF extraction with PRIORITY SECTIONS
# -------------------------------------------------------------------

def extract_relevant_sections(pdf_path):
    """Extract text with priority on methodology sections"""
    priority_sections = []
    secondary_sections = []
    
    # High-priority keywords (methodology and IV sections)
    keywords_priority = [
        "instrumental variable", "instrument", "identification strategy", 
        "empirical strategy", "methodology", "econometric", "rainfall", 
        "precipitation", "first stage", "first-stage", "2sls", "iv estimation",
        "identification", "endogeneity", "exogenous"
    ]
    
    # Secondary keywords (general context)
    keywords_secondary = [
        "data", "methods", "model", "estimation", "abstract", "introduction",
        "conclusion", "results", "empirical"
    ]
    
    try:
        with fitz.open(pdf_path) as doc:
            for page_num in range(len(doc)):
                page = doc.load_page(page_num)
                page_text = page.get_text("text")
                paragraphs = page_text.split("\n\n")
                
                for paragraph in paragraphs:
                    para_lower = paragraph.lower()
                    # Priority sections first
                    if any(keyword in para_lower for keyword in keywords_priority):
                        priority_sections.append(paragraph)
                    # Secondary sections
                    elif any(keyword in para_lower for keyword in keywords_secondary):
                        secondary_sections.append(paragraph)
    except Exception as e:
        print(f"Error extracting PDF {pdf_path}: {e}")
        return ""
    
    # Combine priority sections first, then fill remaining space with secondary
    combined = " ".join(priority_sections + secondary_sections)
    print(f"  Priority sections: {len(priority_sections)}, Secondary: {len(secondary_sections)}")
    return combined


# -------------------------------------------------------------------
# Main processing with NuExtract
# -------------------------------------------------------------------

def process_pdfs_with_nuextract(pdf_folder, output_csv):
    data = []
    
    for filename in os.listdir(pdf_folder):
        if not filename.endswith(".pdf"):
            continue
        
        pdf_path = os.path.join(pdf_folder, filename)
        print(f"\n{'='*60}")
        print(f"Processing {filename}...")
        print(f"{'='*60}")
        
        relevant_sections = extract_relevant_sections(pdf_path)
        print(f"Extracted relevant sections length: {len(relevant_sections)} characters")
        
        # Truncate to fit NuExtract's context window (keep at 6000)
        max_chars = 6000
        text_to_analyze = relevant_sections[:max_chars]
        
        # Initialize results
        info_dict = {
            "File Name": filename,
            "Is Academic Paper": "0",
            "Paper Title": "n/a",
            "DOI": "n/a",
            "Dependent Variables": "n/a",
            "Endogenous Variable(s)": "n/a",
            "Instrumental Variable Used": "n/a",
            "Instrumental Variable(s)": "n/a",
            "Instrumental Variable Rainfall": "n/a",
            "Rainfall Metric": "n/a",
            "Rainfall Data Source": "n/a",
        }
        
        # Define extraction schema - with EXAMPLES not questions
        schema = """{
            "is_academic_paper": "yes",
            "paper_title": "The Impact of Rainfall on Agricultural Productivity",
            "doi": "10.1234/example.2024",
            "dependent_variables": ["crop yield", "income", "productivity"],
            "endogenous_variables": ["fertilizer use", "labor supply"],
            "instrumental_variable_used": "yes",
            "instrumental_variables": ["historical rainfall patterns", "distance to weather station"],
            "instrumental_variable_rainfall": "yes",
            "rainfall_metric": ["log of monthly rainfall", "annual rainfall deviation", "rainfall shocks"],
            "rainfall_data_source": "NOAA Climate Data"
        }"""
        
        print("Querying NuExtract model...")
        extracted = predict_nuextract(model, tokenizer, text_to_analyze, schema)
        print(f"Raw extraction: {extracted}")
        
        # Process extraction results with validation
        is_paper_raw = extracted.get("is_academic_paper", "")
        is_paper_valid = validate_extraction(extracted, "is_academic_paper", is_paper_raw)
        is_paper = "1" if "yes" in str(is_paper_raw).lower() and is_paper_valid else "0"
        info_dict["Is Academic Paper"] = is_paper
        
        if is_paper == "1":
            # Validate each extraction
            title = extracted.get("paper_title")
            title_valid = validate_extraction(extracted, "paper_title", title)
            info_dict["Paper Title"] = clean_string_field(title, title_valid)
            
            doi = extracted.get("doi")
            doi_valid = validate_extraction(extracted, "doi", doi)
            info_dict["DOI"] = clean_string_field(doi, doi_valid)
            
            dep_vars = extracted.get("dependent_variables")
            dep_valid = validate_extraction(extracted, "dependent_variables", dep_vars)
            info_dict["Dependent Variables"] = clean_variable_list(dep_vars, dep_valid)
            
            endog_vars = extracted.get("endogenous_variables")
            endog_valid = validate_extraction(extracted, "endogenous_variables", endog_vars)
            info_dict["Endogenous Variable(s)"] = clean_variable_list(endog_vars, endog_valid)
            
            iv_used_raw = extracted.get("instrumental_variable_used", "")
            iv_used_valid = validate_extraction(extracted, "instrumental_variable_used", iv_used_raw)
            
            # Check if yes in raw value OR if instrumental_variables list is populated
            iv_list_raw = extracted.get("instrumental_variables", [])
            iv_list_valid = validate_extraction(extracted, "instrumental_variables", iv_list_raw)
            has_ivs = (iv_list_raw and len(iv_list_raw) > 0) if isinstance(iv_list_raw, list) else bool(iv_list_raw)
            
            iv_used = "1" if (("yes" in str(iv_used_raw).lower() and iv_used_valid) or (has_ivs and iv_list_valid)) else "0"
            info_dict["Instrumental Variable Used"] = iv_used
            
            if iv_used == "1":
                info_dict["Instrumental Variable(s)"] = clean_variable_list(iv_list_raw, iv_list_valid)
                
                rain_iv_raw = extracted.get("instrumental_variable_rainfall", "")
                rain_iv_valid = validate_extraction(extracted, "instrumental_variable_rainfall", rain_iv_raw)
                
                # Check if rainfall mentioned in IV list OR explicit yes
                iv_list = info_dict["Instrumental Variable(s)"]
                rain_iv = "1" if (("yes" in str(rain_iv_raw).lower() and rain_iv_valid) or 
                                 iv_list_mentions_rainfall(iv_list)) else "0"
                info_dict["Instrumental Variable Rainfall"] = rain_iv
                
                if rain_iv == "1":
                    rain_metric = extracted.get("rainfall_metric")
                    rain_metric_valid = validate_extraction(extracted, "rainfall_metric", rain_metric)
                    info_dict["Rainfall Metric"] = clean_variable_list(rain_metric, rain_metric_valid)
                    
                    rain_source = extracted.get("rainfall_data_source")
                    rain_source_valid = validate_extraction(extracted, "rainfall_data_source", rain_source)
                    info_dict["Rainfall Data Source"] = clean_string_field(rain_source, rain_source_valid)
        
        # Apply consistency rules
        info_dict = enforce_dependency_consistency(info_dict, verbose=True)
        
        print(f"\nFinal extracted info:")
        for key, value in info_dict.items():
            if key != "File Name":
                print(f"  {key}: {value}")
        
        data.append(info_dict)
        
        # Clear GPU memory after each PDF
        clear_gpu_memory()
    
    # Save to CSV
    df = pd.DataFrame(data)
    df.to_csv(output_csv, index=False)
    print(f"\n{'='*60}")
    print(f"Data saved to {output_csv}")
    print(f"Processed {len(data)} PDF(s)")
    print(f"{'='*60}")


# -------------------------------------------------------------------
# Paths and execution
# -------------------------------------------------------------------

if __name__ == "__main__":
    pdf_folder = "/Users/kieran/Library/CloudStorage/OneDrive-UniversityofArizona/weather_iv_lit/training/models/finetune_data/smalltest"
    output_folder = "/Users/kieran/Library/CloudStorage/OneDrive-UniversityofArizona/weather_iv_lit/training/models/output"
    os.makedirs(output_folder, exist_ok=True)
    output_csv = os.path.join(output_folder, "nuextract_output.csv")
    
    process_pdfs_with_nuextract(pdf_folder, output_csv)
