############################################
# model evaluation code
############################################
### This script reads in the model output CSV and the human validated csv for the 15% of data excluded from training
### The files are cleaned, normalized, and merged by a common identifier (filename)
### ConfusionMatrix used to evaluate binary identification performance
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
human_data <- read_csv("/Users/kieran/Library/CloudStorage/OneDrive-UniversityofArizona/weather_iv_lit/training/models/finetune1_data/removed_15.csv")
model_data <- read_csv("/Users/kieran/Library/CloudStorage/OneDrive-UniversityofArizona/weather_iv_lit/training/models/output/finetune_output.csv")

# clean the 'ptitle' column to lowercase and convert encoding to UTF-8
human_data_clean <- human_data %>%
  rename(
    ptitle = `paper title`,
    rainmet = `rainfall metric`
  ) %>%
  mutate(
    ptitle = iconv(ptitle, to = "UTF-8", sub = "byte"),
    ptitle = tolower(ptitle),
    filename = iconv(filename, to = "UTF-8", sub = "byte"),
    filename = tolower(filename),
    rainmet = iconv(rainmet, to = "UTF-8", sub = "byte"),
    rainmet = tolower(rainmet),
    doi = iconv(doi, to = "UTF-8", sub = "byte"),
    doi = tolower(doi)
  )

model_data_clean <- model_data %>%
  rename(
    filename = `File Name`,
    doi = DOI,
    iv_bin = `Instrumental Variable Used`,
    rain_bin = `Instrumental Variable Rainfall`,
    ptitle = `Paper Title`,
    rainmet = `Rainfall Metric`
  ) %>%
  mutate(
    ptitle = iconv(ptitle, to = "UTF-8", sub = "byte"),
    ptitle = tolower(ptitle),
    filename = iconv(filename, to = "UTF-8", sub = "byte"),
    filename = tolower(filename),
    rainmet = iconv(rainmet, to = "UTF-8", sub = "byte"),
    rainmet = tolower(rainmet),
    doi = iconv(doi, to = "UTF-8", sub = "byte"),
    doi = tolower(doi)
  )

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

human_data_clean <- human_data_clean %>% clean_filenames()
model_data_clean <- model_data_clean %>% clean_filenames()

############################################
# merge datasets on a common identifier
############################################
merged_data <- human_data_clean %>%
  inner_join(
    model_data_clean,
    by = c("filename"),
    suffix = c("_human", "_model")
  )

############################################
# convert to factor for confusionMatrix:
merged_data$hasIV_human <- factor(merged_data$iv_bin_human, levels = c(0, 1))
merged_data$hasIV_model <- factor(merged_data$iv_bin_model, levels = c(0, 1))
merged_data$isRainfall_human <- factor(merged_data$rain_bin_human, levels = c(0, 1))
merged_data$isRainfall_model <- factor(merged_data$rain_bin_model, levels = c(0, 1))

# convert columns to factors with the same levels
merged_data$iv_bin_model <- factor(merged_data$iv_bin_model, levels = c("0", "1"))
merged_data$iv_bin_human <- factor(merged_data$iv_bin_human, levels = c("0", "1"))


############################################
# confusion matrices for performance
############################################
### confusion matrix for hasiv
cm_hasIV <- confusionMatrix(
  data = merged_data$iv_bin_model,
  reference = merged_data$iv_bin_human,
  positive = "1"
)

cat("\nConfusion Matrix for hasIV:\n")
print(cm_hasIV)

### confusion matrix for israinfall
cm_isRainfall <- confusionMatrix(
  data = merged_data$isRainfall_model,
  reference = merged_data$isRainfall_human,
  positive = "1"
)

cat("\nConfusion Matrix for isRainfall:\n")
print(cm_isRainfall)


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
