############################################
# 1. Load necessary libraries
############################################
# install.packages("caret")  # Uncomment if not installed
library(caret)

############################################
# 2. Read in your CSV files
############################################
# Adjust the file paths as needed
human_data <- read.csv("human_extracted.csv", stringsAsFactors = FALSE)
model_data <- read.csv("model_extracted.csv", stringsAsFactors = FALSE)

############################################
# 3. Merge datasets on a common identifier
############################################
# Suppose both CSVs have a column named 'paper_id' to match records
merged_data <- merge(human_data, model_data, by = "paper_id", suffixes = c("_human", "_model"))

############################################
# 4. Check and/or convert columns to 0/1 or factor
############################################
# Example columns: 'hasIV_human', 'hasIV_model', 'isRainfall_human', 'isRainfall_model'
# Make sure these columns are consistent. E.g., if they're "Yes"/"No", convert to 1/0 or factor.

# Let's assume they're numeric 0/1. Convert them to factor for confusionMatrix:
merged_data$hasIV_human      <- factor(merged_data$hasIV_human, levels = c(0, 1))
merged_data$hasIV_model      <- factor(merged_data$hasIV_model, levels = c(0, 1))
merged_data$isRainfall_human <- factor(merged_data$isRainfall_human, levels = c(0, 1))
merged_data$isRainfall_model <- factor(merged_data$isRainfall_model, levels = c(0, 1))

############################################
# 5. Confusion Matrices for Performance
############################################

### (A) For 'hasIV' comparison

cm_hasIV <- confusionMatrix(
  data      = merged_data$hasIV_model,      # Predictions
  reference = merged_data$hasIV_human,      # Ground truth
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
