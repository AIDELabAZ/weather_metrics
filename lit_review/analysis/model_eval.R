############################################
# model evaluation code
############################################
### Reads a model output CSV and the human-validated CSV for the 20% of data
### excluded from training, cleans/normalizes/merges them by filename, and reports:
###   - confusion matrices for the binary identification fields
###   - cross-encoder semantic similarity for the free-text fields
### Call evaluate_model() once per model's output CSV (gemini, gpt, llama, gemma, ...).
############################################
library(tidyverse)
library(caret)
library(reticulate)

############################################
# Paths
############################################
human_path <- "/Users/kieran/Library/CloudStorage/OneDrive-UniversityofArizona/weather_iv_lit/training/models/finetune_data/removed_20.csv"
merged_dir <- "/Users/kieran/Library/CloudStorage/OneDrive-UniversityofArizona/weather_iv_lit/training/models/finetune_data"

model_paths <- list(
  # gemini = "/Users/kieran/Library/CloudStorage/OneDrive-UniversityofArizona/weather_iv_lit/training/models/output/finetune_gemini_aistudio_output.csv",
  gpt    = "/Users/kieran/Library/CloudStorage/OneDrive-UniversityofArizona/weather_iv_lit/training/models/output/mini_gpt_finetune_output.csv"
  # llama = "/Users/kieran/Library/CloudStorage/OneDrive-UniversityofArizona/weather_iv_lit/training/models/output/llama_finetune_output.csv",
  # gemma = "/Users/kieran/Library/CloudStorage/OneDrive-UniversityofArizona/weather_iv_lit/training/models/output/gemma_finetune_output.csv"
)

############################################
# Cross-encoder setup (once for the whole session)
############################################
# Create env only once; comment out after first successful run:
virtualenv_create("bert_env")
use_virtualenv("bert_env", required = TRUE)

py_install(c("torch", "transformers", "sentence-transformers"))

py_run_string("
from sentence_transformers import CrossEncoder
import numpy as np

_ce_model = CrossEncoder('cross-encoder/stsb-roberta-large')

def ce_similarity(texts1, texts2, batch_size=32):
    pairs = list(zip(texts1, texts2))
    scores = _ce_model.predict(pairs, batch_size=batch_size)
    return np.array(scores, dtype=float)
")

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

similarity_metrics <- function(v) {
  r <- range(v, na.rm = TRUE)
  c(
    n      = sum(!is.na(v)),
    mean   = mean(v, na.rm = TRUE),
    median = median(v, na.rm = TRUE),
    sd     = sd(v, na.rm = TRUE),
    min    = r[1],
    max    = r[2]
  )
}

############################################
# Shared cleaning helpers
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

############################################
# Clean human data (fixed schema, shared across every model)
############################################
human_data <- read_csv(human_path, na = c("n/a", "NA", ""))

human_data_clean <- human_data %>%
  rename(
    ptitle  = title,
    rainmet = rain_var,
    endog   = end_var,
    depen   = dep_var,
    iv      = iv_var
  ) %>%
  mutate(
    filename_human = filename,  # preserve original human filename
    ptitle   = tolower(iconv(ptitle,   to = "UTF-8", sub = "byte")),
    filename = tolower(iconv(filename, to = "UTF-8", sub = "byte")),
    rainmet  = tolower(iconv(rainmet,  to = "UTF-8", sub = "byte")),
    doi      = tolower(iconv(doi,      to = "UTF-8", sub = "byte")),
    endog    = tolower(iconv(endog,    to = "UTF-8", sub = "byte")),
    depen    = tolower(iconv(depen,    to = "UTF-8", sub = "byte")),
    iv       = tolower(iconv(iv,       to = "UTF-8", sub = "byte")),
    iv_bin   = as.numeric(iv_bin),
    rain_bin = as.numeric(rain_bin),
    emp_bin  = as.numeric(emp_bin),
    end_bin  = as.numeric(end_bin)
  ) %>%
  clean_filenames() %>%
  clean_doi() %>%
  mutate(
    iv_bin   = ifelse(is.na(iv_bin),   0, iv_bin),
    rain_bin = ifelse(is.na(rain_bin), 0, rain_bin),
    emp_bin  = ifelse(is.na(emp_bin),  0, emp_bin),
    end_bin  = ifelse(is.na(end_bin),  0, end_bin)
  )

############################################
# Per-model evaluation
############################################
evaluate_model <- function(model_path, model_label) {
  cat("\n============================\nEvaluating:", model_label, "\n============================\n")

  model_data <- read_csv(model_path, na = c("n/a", "NA", ""))

  model_data_clean <- model_data %>%
    rename(
      filename = `File Name`,
      doi      = DOI,
      iv_bin   = `Instrumental Variable Used`,
      rain_bin = `Instrumental Variable Rainfall`,
      ptitle   = `Title`,
      rainmet  = `Rainfall Instrument`,
      endog    = `Endogenous Variable(s)`,
      depen    = `Dependent Variable(s)`,
      iv       = `Instrumental Variable(s)`,
      emp_bin  = `Empirical Analysis`,
      end_bin  = `Endogeneity Problem`
    ) %>%
    mutate(
      filename_model = filename,  # preserve original model filename
      ptitle   = tolower(iconv(ptitle,   to = "UTF-8", sub = "byte")),
      filename = tolower(iconv(filename, to = "UTF-8", sub = "byte")),
      rainmet  = tolower(iconv(rainmet,  to = "UTF-8", sub = "byte")),
      doi      = tolower(iconv(doi,      to = "UTF-8", sub = "byte")),
      endog    = tolower(iconv(endog,    to = "UTF-8", sub = "byte")),
      depen    = tolower(iconv(depen,    to = "UTF-8", sub = "byte")),
      iv       = tolower(iconv(iv,       to = "UTF-8", sub = "byte")),
      iv_bin   = as.numeric(iv_bin),
      rain_bin = as.numeric(rain_bin),
      emp_bin  = as.numeric(emp_bin),
      end_bin  = as.numeric(end_bin)
    ) %>%
    clean_filenames() %>%
    clean_doi() %>%
    mutate(
      iv_bin   = ifelse(is.na(iv_bin),   0, iv_bin),
      rain_bin = ifelse(is.na(rain_bin), 0, rain_bin),
      emp_bin  = ifelse(is.na(emp_bin),  0, emp_bin),
      end_bin  = ifelse(is.na(end_bin),  0, end_bin)
    )

  merged_data <- human_data_clean %>%
    inner_join(model_data_clean, by = "filename", suffix = c("_human", "_model")) %>%
    rename(filename_merged = filename)

  write_csv(merged_data, file.path(merged_dir, paste0("merged_data_", model_label, ".csv")))

  # confusionMatrix requires data/reference to be factors with the same levels
  merged_data <- merged_data %>%
    mutate(
      iv_bin_human   = factor(iv_bin_human,   levels = c(0, 1)),
      iv_bin_model   = factor(iv_bin_model,   levels = c(0, 1)),
      rain_bin_human = factor(rain_bin_human, levels = c(0, 1)),
      rain_bin_model = factor(rain_bin_model, levels = c(0, 1)),
      emp_bin_human  = factor(emp_bin_human,  levels = c(0, 1)),
      emp_bin_model  = factor(emp_bin_model,  levels = c(0, 1)),
      end_bin_human  = factor(end_bin_human,  levels = c(0, 1)),
      end_bin_model  = factor(end_bin_model,  levels = c(0, 1))
    )

  cat("\nConfusion Matrix for hasIV:\n")
  print(confusionMatrix(merged_data$iv_bin_model, merged_data$iv_bin_human, positive = "1"))

  cat("\nConfusion Matrix for isRainfall:\n")
  print(confusionMatrix(merged_data$rain_bin_model, merged_data$rain_bin_human, positive = "1"))

  cat("\nConfusion Matrix for emp_bin:\n")
  print(confusionMatrix(merged_data$emp_bin_model, merged_data$emp_bin_human, positive = "1"))

  cat("\nConfusion Matrix for end_bin:\n")
  print(confusionMatrix(merged_data$end_bin_model, merged_data$end_bin_human, positive = "1"))

  merged_data$rainmet_similarity <- ce_score_pairs(merged_data$rainmet_human, merged_data$rainmet_model)
  merged_data$endog_similarity   <- ce_score_pairs(merged_data$endog_human,   merged_data$endog_model)
  merged_data$doi_similarity     <- ce_score_pairs(merged_data$doi_human,     merged_data$doi_model)
  merged_data$depen_similarity   <- ce_score_pairs(merged_data$depen_human,   merged_data$depen_model)
  merged_data$ptitle_similarity  <- ce_score_pairs(merged_data$ptitle_human,  merged_data$ptitle_model)
  merged_data$iv_similarity      <- ce_score_pairs(merged_data$iv_human,      merged_data$iv_model)

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

  cat("\nSemantic similarity summary:\n")
  print(similarity_summary)

  invisible(merged_data)
}

############################################
# Run for every model
############################################
results <- setNames(
  lapply(names(model_paths), function(m) evaluate_model(model_paths[[m]], m)),
  names(model_paths)
)

