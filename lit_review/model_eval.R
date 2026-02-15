############################################
# model evaluation code
############################################
### This script reads in the model output CSV and the human validated csv for the 20% of data excluded from training
### The files are cleaned, normalized, and merged by a common identifier (filename)
### Matrix generation for evaluation of binary identification performance
### BERT-similarity used to generate non-binary performance 
############################################
# load necessary libraries
############################################
library(tidyverse)
library(caret)
library(readxl)
library(reticulate)

############################################
# read in csv files and clean
############################################
# load data
human_data <- read_csv("/Users/kieran/Library/CloudStorage/OneDrive-UniversityofArizona/weather_iv_lit/training/models/finetune_data/removed_20.csv", na = c("n/a", "NA", ""))
model_data <- read_csv("/Users/kieran/Library/CloudStorage/OneDrive-UniversityofArizona/weather_iv_lit/training/models/output/finetune_output.csv", na = c("n/a", "NA", ""))
############################################
# 1) Clean/standardize human data
############################################
human_data_clean <- human_data %>%
  rename(
    ptitle = `title`,
    rainmet = `rain_var`,
    endog = `end_var`,
    depen = `dep_var`,
    iv = `iv_var`
  ) %>%
  mutate(
    filename_human = filename,  # preserve original human filename
    ptitle  = tolower(iconv(ptitle,  to = "UTF-8", sub = "byte")),
    filename = tolower(iconv(filename, to = "UTF-8", sub = "byte")),
    rainmet = tolower(iconv(rainmet, to = "UTF-8", sub = "byte")),
    doi     = tolower(iconv(doi,     to = "UTF-8", sub = "byte")),
    endog   = tolower(iconv(endog,   to = "UTF-8", sub = "byte")),
    depen   = tolower(iconv(depen,   to = "UTF-8", sub = "byte")),
    iv      = tolower(iconv(iv,      to = "UTF-8", sub = "byte")),
    iv_bin   = as.numeric(iv_bin),
    rain_bin = as.numeric(rain_bin),
    emp_bin  = as.numeric(emp_bin)
  )

############################################
# 2) Clean/standardize model data
############################################
model_data <- model_data %>%
  slice(-80)

model_data_clean <- model_data %>%
  rename(
    filename = `File Name`,
    doi = DOI,
    iv_bin = `Instrumental Variable Used`,
    rain_bin = `Instrumental Variable Rainfall`,
    ptitle = `Title`,
    rainmet = `Rainfall Instrument`,
    endog = `Endogenous Variable(s)`,
    depen = `Dependent Variable(s)`,
    iv = `Instrumental Variable(s)`,
    emp_bin = `Empirical Analysis`
  ) %>%
  mutate(
    filename_model = filename,  # preserve original model filename
    ptitle  = tolower(iconv(ptitle,  to = "UTF-8", sub = "byte")),
    filename = tolower(iconv(filename, to = "UTF-8", sub = "byte")),
    rainmet = tolower(iconv(rainmet, to = "UTF-8", sub = "byte")),
    doi     = tolower(iconv(doi,     to = "UTF-8", sub = "byte")),
    endog   = tolower(iconv(endog,   to = "UTF-8", sub = "byte")),
    depen   = tolower(iconv(depen,   to = "UTF-8", sub = "byte")),
    iv      = tolower(iconv(iv,      to = "UTF-8", sub = "byte")),
    iv_bin   = as.numeric(iv_bin),
    rain_bin = as.numeric(rain_bin),
    emp_bin  = as.numeric(emp_bin)
  )

############################################
# 3) Helpers: filename + DOI cleaning
############################################
clean_filenames <- function(df) {
  df %>%
    mutate(
      filename = filename %>%
        str_remove_all("\\.pdf$") %>%
        str_replace_all(" copy( \\d+)?$", "") %>%
        iconv(to = "ASCII//TRANSLIT", sub = "") %>%
        str_squish()
    )
}

clean_doi <- function(df) {
  df %>%
    mutate(
      doi = doi %>%
        str_remove("^https?://(dx\\.)?doi\\.org/") %>%
        str_remove("^https?://") %>%
        str_squish()
    )
}

human_data_clean <- human_data_clean %>% clean_filenames() %>% clean_doi()
model_data_clean <- model_data_clean %>% clean_filenames() %>% clean_doi()

############################################
# 4) NA handling for binaries (set NA -> 0)
############################################
model_data_clean <- model_data_clean %>%
  mutate(
    rain_bin = ifelse(is.na(rain_bin), 0, rain_bin),
    iv_bin   = ifelse(is.na(iv_bin),   0, iv_bin),
    emp_bin  = ifelse(is.na(emp_bin),  0, emp_bin)
  )

human_data_clean <- human_data_clean %>%
  mutate(
    rain_bin = ifelse(is.na(rain_bin), 0, rain_bin),
    iv_bin   = ifelse(is.na(iv_bin),   0, iv_bin),
    emp_bin  = ifelse(is.na(emp_bin),  0, emp_bin)
  )

############################################
# 5) Merge on common identifier (filename)
############################################
merged_data <- human_data_clean %>%
  inner_join(
    model_data_clean,
    by = "filename",
    suffix = c("_human", "_model")
  ) %>%
  rename(filename_merged = filename)

write_csv(
  merged_data,
  "/Users/kieran/Library/CloudStorage/OneDrive-UniversityofArizona/weather_iv_lit/training/models/finetune_data/merged_data.csv"
)

############################################
# 6) Prepare factors consistently for caret
############################################
# confusionMatrix requires data/reference to be factors with same levels [web:16]
merged_data <- merged_data %>%
  mutate(
    iv_bin_human   = factor(iv_bin_human,   levels = c(0, 1)),
    iv_bin_model   = factor(iv_bin_model,   levels = c(0, 1)),
    rain_bin_human = factor(rain_bin_human, levels = c(0, 1)),
    rain_bin_model = factor(rain_bin_model, levels = c(0, 1)),
    emp_bin_human  = factor(emp_bin_human,  levels = c(0, 1)),
    emp_bin_model  = factor(emp_bin_model,  levels = c(0, 1))
  )

############################################
# 7) Confusion matrices
############################################
cm_hasIV <- confusionMatrix(
  data      = merged_data$iv_bin_model,
  reference = merged_data$iv_bin_human,
  positive  = "1"
)

cat("\nConfusion Matrix for hasIV:\n")
print(cm_hasIV)

cm_isRainfall <- confusionMatrix(
  data      = merged_data$rain_bin_model,
  reference = merged_data$rain_bin_human,
  positive  = "1"
)

cat("\nConfusion Matrix for isRainfall:\n")
print(cm_isRainfall)

cm_emp_bin <- confusionMatrix(
  data      = merged_data$emp_bin_model,
  reference = merged_data$emp_bin_human,
  positive  = "1"
)

cat("\nConfusion Matrix for emp_bin:\n")
print(cm_emp_bin)

############################################
# BERT semantic similarity for rainmet (Python/reticulate)
############################################
# Set up Python environment
virtualenv_create("bert_env")  
use_virtualenv("bert_env")      

# Install required Python packages
py_install(c("torch", "transformers", "sentence-transformers"))

# Python code for BERT similarity
py_run_string("
from sentence_transformers import SentenceTransformer, util
import numpy as np

def bert_similarity(texts1, texts2):
    model = SentenceTransformer('all-MiniLM-L6-v2')
    emb1 = model.encode(texts1, convert_to_tensor=True)
    emb2 = model.encode(texts2, convert_to_tensor=True)
    return util.pytorch_cos_sim(emb1, emb2).cpu().numpy()
")

### rainmet similarity
# Extract rainmet columns
rainmet_human <- merged_data$rainmet_human
rainmet_model <- merged_data$rainmet_model

# Calculate similarities
similarity_matrix <- py$bert_similarity(rainmet_human, rainmet_model)
merged_data$rainmet_similarity <- diag(similarity_matrix)

# Calculate metrics
similarity_metrics <- list(
  mean = mean(merged_data$rainmet_similarity, na.rm = TRUE),
  median = median(merged_data$rainmet_similarity, na.rm = TRUE),
  sd = sd(merged_data$rainmet_similarity, na.rm = TRUE)
)

# Print results
cat("\nBERT Semantic Similarity (Python/reticulate):\n")
print(similarity_metrics)
# mean = 37.72%, median = 49.11%, sd = 26.79%

### endogenous similarity
# Extract rainmet columns
endog_human <- merged_data$endog_human
endog_model <- merged_data$endog_model

# Calculate similarities
similarity_matrix <- py$bert_similarity(endog_human, endog_model)
merged_data$endog_similarity <- diag(similarity_matrix)

# Calculate metrics
similarity_metrics <- list(
  mean = mean(merged_data$endog_similarity, na.rm = TRUE),
  median = median(merged_data$endog_similarity, na.rm = TRUE),
  sd = sd(merged_data$endog_similarity, na.rm = TRUE)
)

# Print results
cat("\nBERT Semantic Similarity (Python/reticulate):\n")
print(similarity_metrics)
# mean = 43.36%, median = 40.36%, sd = 31.69%

### doi similarity
# Extract rainmet columns
doi_human <- merged_data$doi_human
doi_model <- merged_data$doi_model

# Calculate similarities
similarity_matrix <- py$bert_similarity(doi_human, doi_model)
merged_data$doi_similarity <- diag(similarity_matrix)

# Calculate metrics
similarity_metrics <- list(
  mean = mean(merged_data$doi_similarity, na.rm = TRUE),
  median = median(merged_data$doi_similarity, na.rm = TRUE),
  sd = sd(merged_data$doi_similarity, na.rm = TRUE)
)

# Print results
cat("\nBERT Semantic Similarity (Python/reticulate):\n")
print(similarity_metrics)
# mean = 70.82%, median = 73.48%, sd = 30.86%

### dependent similarity
# Extract rainmet columns
depen_human <- merged_data$depen_human
depen_model <- merged_data$depen_model

# Calculate similarities
similarity_matrix <- py$bert_similarity(depen_human, depen_model)
merged_data$depen_similarity <- diag(similarity_matrix)

# Calculate metrics
similarity_metrics <- list(
  mean = mean(merged_data$depen_similarity, na.rm = TRUE),
  median = median(merged_data$depen_similarity, na.rm = TRUE),
  sd = sd(merged_data$depen_similarity, na.rm = TRUE)
)

# Print results
cat("\nBERT Semantic Similarity (Python/reticulate):\n")
print(similarity_metrics)
# mean = 55.48%, median = 62.65%, sd = 31.29%

### title similarity
# Extract rainmet columns
ptitle_human <- merged_data$ptitle_human
ptitle_model <- merged_data$ptitle_model

# Calculate similarities
similarity_matrix <- py$bert_similarity(ptitle_human, ptitle_model)
merged_data$ptitle_similarity <- diag(similarity_matrix)

# Calculate metrics
similarity_metrics <- list(
  mean = mean(merged_data$ptitle_similarity, na.rm = TRUE),
  median = median(merged_data$ptitle_similarity, na.rm = TRUE),
  sd = sd(merged_data$ptitle_similarity, na.rm = TRUE)
)

# Print results
cat("\nBERT Semantic Similarity (Python/reticulate):\n")
print(similarity_metrics)
# mean = 93.88%, median = 99.99%, sd = 18.71%

### iv similarity
# Extract rainmet columns
iv_human <- merged_data$iv_human
iv_model <- merged_data$iv_model

# Calculate similarities
similarity_matrix <- py$bert_similarity(iv_human, iv_model)
merged_data$iv_similarity <- diag(similarity_matrix)

# Calculate metrics
similarity_metrics <- list(
  mean = mean(merged_data$iv_similarity, na.rm = TRUE),
  median = median(merged_data$iv_similarity, na.rm = TRUE),
  sd = sd(merged_data$iv_similarity, na.rm = TRUE)
)

# Print results
cat("\nBERT Semantic Similarity (Python/reticulate):\n")
print(similarity_metrics)
# mean = 32.93%, median = 14.52%, sd = 33.92%









############# NEWBERT
############################################
# Higher-quality semantic similarity (Cross-Encoder STS) via reticulate
############################################
library(reticulate)

# 1) Python env (create once; comment out after first successful run)
virtualenv_create("bert_env")
use_virtualenv("bert_env", required = TRUE)

# CrossEncoder lives in sentence-transformers; torch + transformers are dependencies
py_install(c("torch", "transformers", "sentence-transformers"))

# 2) Define Python Cross-Encoder scorer (loads model once, scores in batches)
py_run_string("
from sentence_transformers import CrossEncoder
import numpy as np

# Load once (global) so you don't reload for every column
_ce_model = CrossEncoder('cross-encoder/stsb-roberta-large')

def ce_similarity(texts1, texts2, batch_size=32):
    pairs = list(zip(texts1, texts2))  # list of (text1, text2)
    scores = _ce_model.predict(pairs, batch_size=batch_size)
    return np.array(scores, dtype=float)
")

# 3) R helper: safely score aligned pairs (handles NA)
ce_score_pairs <- function(x, y, batch_size = 32L) {
  stopifnot(length(x) == length(y))

  ok <- !(is.na(x) | is.na(y))
  out <- rep(NA_real_, length(x))

  if (any(ok)) {
    out[ok] <- py$ce_similarity(
      as.character(x[ok]),
      as.character(y[ok]),
      batch_size = as.integer(batch_size)
    )
  }
  out
}

# 4) Apply to your aligned columns (one-to-one rows)
merged_data$rainmet_similarity <- ce_score_pairs(merged_data$rainmet_human, merged_data$rainmet_model)
merged_data$endog_similarity   <- ce_score_pairs(merged_data$endog_human,   merged_data$endog_model)
merged_data$doi_similarity     <- ce_score_pairs(merged_data$doi_human,     merged_data$doi_model)
merged_data$depen_similarity   <- ce_score_pairs(merged_data$depen_human,   merged_data$depen_model)
merged_data$ptitle_similarity  <- ce_score_pairs(merged_data$ptitle_human,  merged_data$ptitle_model)
merged_data$iv_similarity      <- ce_score_pairs(merged_data$iv_human,      merged_data$iv_model)

# 5) Metrics helper (mean/median/sd + min/max)
similarity_metrics <- function(v) {
  r <- range(v, na.rm = TRUE)  # returns c(min, max) when na.rm=TRUE [web:10]
  c(
    n      = sum(!is.na(v)),
    mean   = mean(v, na.rm = TRUE),
    median = median(v, na.rm = TRUE),
    sd     = sd(v, na.rm = TRUE),
    min    = r[1],
    max    = r[2]
  )
}

# 6) Combined table output
similarity_summary <- data.frame(
  field = c("rainmet", "endog", "doi", "depen", "ptitle", "iv"),
  rbind(
    similarity_metrics(merged_data$rainmet_similarity),
    similarity_metrics(merged_data$endog_similarity),
    similarity_metrics(merged_data$doi_similarity),
    similarity_metrics(merged_data$depen_similarity),
    similarity_metrics(merged_data$ptitle_similarity),
    similarity_metrics(merged_data$iv_similarity)
  ),
  row.names = NULL,
  check.names = FALSE
)

print(similarity_summary)

# \Optional: nicer printing
# print(within(similarity_summary, {
#   mean   <- round(mean, 3)
#   median <- round(median, 3)
#   sd     <- round(sd, 3)
#   min    <- round(min, 3)
#   max    <- round(max, 3)
# }))


#######################################################
#######################################################
#######################################################
#######################################################
#######################################################
#######################################################
#######################################################
#######################################################
#######################################################
############################################
# model evaluation code (UPDATED to match new extractor output)
############################################
# - Matches new model output columns:
#   File Name, Title, DOI, Empirical Analysis, Dependent Variable(s),
#   Endogeneity Problem, Endogenous Variable(s),
#   Instrumental Variable Used, Instrumental Variable(s),
#   Instrumental Variable Rainfall, Rainfall Instrument
# - Removes "academic paper"; uses "empirical" instead
# - Adds HUMAN endogenous identification category:
#     endog_id_bin_human = 1 if end_var present, else n/a (NA)
#   and also creates eval-ready 0/1 versions for confusionMatrix.
#
# Note: caret::confusionMatrix requires data/reference to be factors with the same levels. [web:17]
############################################

library(tidyverse)
library(caret)
library(reticulate)

############################################
# Paths
############################################
human_path <- "/Users/kieran/Library/CloudStorage/OneDrive-UniversityofArizona/weather_iv_lit/training/models/finetune_data/removed_20.csv"
model_path <- "/Users/kieran/Library/CloudStorage/OneDrive-UniversityofArizona/weather_iv_lit/training/models/output/finetune_output.csv"
merged_out  <- "/Users/kieran/Library/CloudStorage/OneDrive-UniversityofArizona/weather_iv_lit/training/models/finetune_data/merged_data.csv"

############################################
# Read in data
############################################
human_data <- read_csv(human_path, na = c("n/a", "NA", ""))
model_data <- read_csv(model_path, na = c("n/a", "NA", ""))

############################################
# Helpers
############################################
norm_txt <- function(x) {
  x <- iconv(x, to = "UTF-8", sub = "byte")
  x <- tolower(x)
  x <- str_replace_all(x, "\\s+", " ")
  x <- str_squish(x)
  x
}

clean_filenames <- function(df) {
  df %>%
    mutate(
      filename = filename %>%
        norm_txt() %>%
        str_remove_all("\\.pdf$") %>%
        str_replace_all(" copy( \\d+)?$", "") %>%
        iconv(to = "ASCII//TRANSLIT", sub = "") %>%
        str_squish()
    )
}

clean_doi <- function(df) {
  df %>%
    mutate(
      doi = doi %>%
        norm_txt() %>%
        str_remove("^https?://(dx\\.)?doi\\.org/") %>%
        str_remove("^doi:\\s*") %>%
        str_squish()
    )
}

# For n/a-style text fields: 1 if present, else 0
present_na_style <- function(x) {
  x <- norm_txt(as.character(x))
  ifelse(is.na(x) | x %in% c("", "n/a", "na", "none"), 0L, 1L)
}

# Confusion-matrix helper (only runs if columns exist and have complete cases)
maybe_confusion <- function(df, pred_col, ref_col, title, positive = "1") {
  if (!(pred_col %in% names(df) && ref_col %in% names(df))) {
    cat("\nSkipping", title, "- missing column(s):", pred_col, "and/or", ref_col, "\n")
    return(invisible(NULL))
  }

  tmp <- df %>%
    select(all_of(c(pred_col, ref_col))) %>%
    drop_na()

  if (nrow(tmp) == 0) {
    cat("\nSkipping", title, "- no complete cases.\n")
    return(invisible(NULL))
  }

  # Enforce identical factor levels to avoid caret errors. [web:17]
  pred <- factor(as.character(tmp[[pred_col]]), levels = c("0", "1"))
  ref  <- factor(as.character(tmp[[ref_col]]),  levels = c("0", "1"))

  cat("\nConfusion Matrix for", title, ":\n")
  print(confusionMatrix(data = pred, reference = ref, positive = positive))
  invisible(NULL)
}

############################################
# Clean HUMAN data
############################################
# Expected human columns (adjust rename targets if your CSV differs):
# filename, title, doi, dep_var, end_var, iv_var, rain_var, iv_bin, rain_bin
human_data_clean <- human_data %>%
  rename(
    filename = filename,
    ptitle   = title,
    doi      = doi,
    depen    = dep_var,
    endog    = end_var,
    iv       = iv_var,
    rainmet  = rain_var
  ) %>%
  mutate(
    filename_human = filename,

    filename = norm_txt(filename),
    ptitle   = norm_txt(ptitle),
    doi      = norm_txt(doi),
    depen    = norm_txt(depen),
    endog    = norm_txt(endog),
    iv       = norm_txt(iv),
    rainmet  = norm_txt(rainmet),

    iv_bin   = as.integer(iv_bin),
    rain_bin = as.integer(rain_bin)
  )

# NEW: Endogenous identification (HUMAN)
# 1 if something is present, otherwise n/a (NA)
human_data_clean <- human_data_clean %>%
  mutate(
    endog_id_bin_human = ifelse(present_na_style(endog) == 1L, 1L, NA_integer_),
    # Eval-ready 0/1 version for confusionMatrix:
    endog_id_eval_human = present_na_style(endog)
  )

# NEW/UPDATED: Empirical binary (HUMAN)
# Adjust to your actual human column name(s). If none exist, it stays NA and is skipped.
human_data_clean <- human_data_clean %>%
  mutate(
    empirical_bin_human = case_when(
      "empirical_bin" %in% names(human_data) ~ as.integer(human_data$empirical_bin),
      "empirical"     %in% names(human_data) ~ as.integer(human_data$empirical),
      TRUE ~ NA_integer_
    )
  )

human_data_clean <- human_data_clean %>%
  clean_filenames() %>%
  clean_doi() %>%
  mutate(
    iv_bin   = ifelse(is.na(iv_bin), 0L, iv_bin),
    rain_bin = ifelse(is.na(rain_bin), 0L, rain_bin)
  )

############################################
# Clean MODEL data (matches your new extractor output)
############################################
model_data_clean <- model_data %>%
  rename(
    filename   = `File Name`,
    ptitle     = `Title`,
    doi        = `DOI`,
    empirical  = `Empirical Analysis`,
    depen      = `Dependent Variable(s)`,
    endogprob  = `Endogeneity Problem`,
    endog      = `Endogenous Variable(s)`,
    iv_used    = `Instrumental Variable Used`,
    iv         = `Instrumental Variable(s)`,
    rain_iv    = `Instrumental Variable Rainfall`,
    rainmet    = `Rainfall Instrument`
  ) %>%
  mutate(
    filename_model = filename,

    filename  = norm_txt(filename),
    ptitle    = norm_txt(ptitle),
    doi       = norm_txt(doi),
    depen     = norm_txt(depen),
    endog     = norm_txt(endog),
    iv        = norm_txt(iv),
    rainmet   = norm_txt(rainmet),

    # Convert model "1/0/n/a" style outputs to numeric binaries
    empirical_bin_model = ifelse(norm_txt(empirical) == "1", 1L, 0L),
    iv_bin_model        = ifelse(norm_txt(iv_used)   == "1", 1L, 0L),
    rain_bin_model      = ifelse(norm_txt(rain_iv)   == "1", 1L, 0L),
    endogprob_bin_model = ifelse(norm_txt(endogprob) == "1", 1L, 0L),

    # NEW: Endogenous identification (MODEL)
    # 1 if something is present, otherwise n/a (NA)
    endog_id_bin_model = ifelse(present_na_style(endog) == 1L, 1L, NA_integer_),
    # Eval-ready 0/1 version for confusionMatrix:
    endog_id_eval_model = present_na_style(endog)
  ) %>%
  clean_filenames() %>%
  clean_doi()

############################################
# Merge on filename
############################################
merged_data <- human_data_clean %>%
  inner_join(model_data_clean, by = "filename", suffix = c("_human", "_model")) %>%
  rename(filename_merged = filename)

write_csv(merged_data, merged_out)

############################################
# Confusion matrices (binary tasks)
############################################
# Existing (human-provided) IV and rainfall bins:
maybe_confusion(merged_data, "iv_bin_model",   "iv_bin",   "Instrumental Variable Used (IV)")
maybe_confusion(merged_data, "rain_bin_model", "rain_bin", "Rainfall-based IV used")

# Empirical (if your human file has empirical_bin_human populated):
maybe_confusion(merged_data, "empirical_bin_model", "empirical_bin_human", "Empirical analysis (empirical)")

# Endogenous-ID confusion matrix using eval-ready 0/1 versions:
maybe_confusion(merged_data, "endog_id_eval_model", "endog_id_eval_human", "Endogenous variable identified")

# Optional: endogeneity problem flagged (only if you add a human binary later)
# maybe_confusion(merged_data, "endogprob_bin_model", "endogprob_bin_human", "Endogeneity problem flagged")

############################################
# Cross-Encoder semantic similarity via reticulate
############################################
# Create env only once; comment out after first successful run:
# virtualenv_create("bert_env")
d o