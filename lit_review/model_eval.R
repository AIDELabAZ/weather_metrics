############################################
# model evaluation code
############################################

############################################
# load necessary libraries
############################################
install.packages("caret")
install.packages("tidyverse")
install.packages("readxl")
library(caret)
library(tidyverse)
library(readxl)

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
    rainmet = tolower(rainmet)
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
    rainmet = tolower(rainmet)
  )

clean_filenames <- function(df) {
  df %>%
    mutate(
      filename = filename %>%
        # Remove .pdf and .pdf extensions
        str_remove_all("\\.pdf$") %>%
        # Standardize copy numbers
        str_replace_all(" copy( \\d+)?$", "") %>%
        # Clean special characters
        iconv(to = "ASCII//TRANSLIT", sub = "") %>%
        # Normalize whitespace
        str_squish()
    )
}

human_data_clean <- human_data_clean %>% clean_filenames()
model_data_clean <- model_data_clean %>% clean_filenames()

############################################
# merge datasets on a common identifier
############################################
merged_data <- merge(human_data_clean, model_data_clean, by = "filename", suffixes = c("_human", "_model"))

## getting terrible merge rate suddenly have to explore this
# check and/or convert columns to 0/1 or factor
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
### currently working with 80.08% identification accuracy. good recall with 90% of true positives identified.
### poor performance on identifying true negative cases (specificity) with 36.96% true negatives identified (stays consistent with increased n).
### positive predictive power is significantly better than negative predictive power (model is better at finding what is vs what is not)
cm_hasIV <- confusionMatrix(
  data = merged_data$iv_bin_model,
  reference = merged_data$iv_bin_human,
  positive = "1"
)

cat("\nConfusion Matrix for hasIV:\n")
print(cm_hasIV)

### confusion matrix for israinfall
### 72.49% accuracy, up from mid 60s with about hals as many obs
### 89.77% true positive rate with 61.7% true negative rate. getting significantly better with increased n.
cm_isRainfall <- confusionMatrix(
  data = merged_data$isRainfall_model,
  reference = merged_data$isRainfall_human,
  positive = "1"
)

cat("\nConfusion Matrix for isRainfall:\n")
print(cm_isRainfall)

############################################
# similarity matching for rainmet column
###########################################

############################################
# BERT semantic similarity for rainmet (Python/reticulate)
############################################

# Set up Python environment
library(reticulate)
virtualenv_create("bert_env")  # Create isolated environment
use_virtualenv("bert_env")      # Activate environment

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
