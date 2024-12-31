############################################
# Model evaluation code 
############################################

############################################
# 1. Load necessary libraries
############################################
install.packages("caret")
install.packages("tidyverse")
install.packages("readxl")
library(caret)
library(tidyverse)
library(readxl)

############################################
# 2. Read in CSV files anbd clean
############################################
# Adjust the file paths as needed
human_data <- read_csv("/Users/kieran/Library/CloudStorage/OneDrive-UniversityofArizona/weather_iv_lit/training/finetune1/finetune1_data/training_data_full.csv")
model_data <- read_csv("/Users/kieran/Library/CloudStorage/OneDrive-UniversityofArizona/weather_iv_lit/training/finetune1/finetune1_output/output.csv")

human_data_clean <- human_data %>% 
  rename(
    filename = `File Name`,
    doi = DOI,
    iv_bin = `IV Binary`,
    rain_bin = `Rainfall Binary`
  )

model_data_clean <- model_data %>% 
  rename(
    filename = `File Name`,
    doi = DOI,
    iv_bin = `IV Binary`,
    rain_bin = `Rainfall Binary`)
############################################
# 3. Merge datasets on a common identifier
############################################
# Suppose both CSVs have a column named 'paper_id' to match records
merged_data <- merge(human_data_clean, model_data_clean, by = "doi", suffixes = c("_human", "_model"))

############################################
# 4. Check and/or convert columns to 0/1 or factor
############################################
# Example columns: 'hasIV_human', 'hasIV_model', 'isRainfall_human', 'isRainfall_model'
# Make sure these columns are consistent. E.g., if they're "Yes"/"No", convert to 1/0 or factor.

# Let's assume they're numeric 0/1. Convert them to factor for confusionMatrix:
merged_data$hasIV_human      <- factor(merged_data$iv_bin_human, levels = c(0, 1))
merged_data$hasIV_model      <- factor(merged_data$iv_bin_model, levels = c(0, 1))
merged_data$isRainfall_human <- factor(merged_data$rain_bin_human, levels = c(0, 1))
merged_data$isRainfall_model <- factor(merged_data$rain_bin_model, levels = c(0, 1))

# Convert both columns to factors with the same levels
merged_data$iv_bin_model <- factor(merged_data$iv_bin_model, levels = c("0", "1"))
merged_data$iv_bin_human <- factor(merged_data$iv_bin_human, levels = c("0", "1"))


############################################
# 5. Confusion Matrices for Performance
############################################

### (A) For 'hasIV' comparison

cm_hasIV <- confusionMatrix(
  data      = merged_data$iv_bin_model,      # Predictions
  reference = merged_data$iv_bin_human,      # Ground truth
  positive  = "1"                          # Which factor level is considered "positive"?
)

cat("\nConfusion Matrix for hasIV:\n")
print(cm_hasIV)

# This object includes metrics like Accuracy, Kappa, Sensitivity, Specificity, etc.
# You can access them by cm_hasIV$overall and cm_hasIV$byClass

### (B) For 'isRainfall' comparison

cm_isRainfall <- confusionMatrix(
  data      = merged_data$isRainfall_model,  # Predictions
  reference = merged_data$isRainfall_human,  # Ground truth
  positive  = "1"
)

cat("\nConfusion Matrix for isRainfall:\n")
print(cm_isRainfall)

