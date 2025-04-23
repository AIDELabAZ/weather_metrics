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
    ptitle = `paper title`
  ) %>%
  mutate(
    ptitle = iconv(ptitle, to = "UTF-8", sub = "byte"),
    ptitle = tolower(ptitle),
    filename = iconv(filename, to = "UTF-8", sub = "byte"),
    filename = tolower(filename)
  )

model_data_clean <- model_data %>%
  rename(
    filename = `File Name`,
    doi = DOI,
    iv_bin = `Instrumental Variable Used`,
    rain_bin = `Instrumental Variable Rainfall`,
    ptitle = `Paper Title`
  ) %>%
  mutate(
    ptitle = iconv(ptitle, to = "UTF-8", sub = "byte"),
    ptitle = tolower(ptitle),
    filename = iconv(filename, to = "UTF-8", sub = "byte"),
    filename = tolower(filename)
  )

# Clean filenames in BOTH datasets
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

############################################
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

