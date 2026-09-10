###
## 1
## This script reads in a CSV containing all data and splits it into 80:20 training/validation and test CSVs
## Split is randomly determined, data are extracted to train_80 and removed_20
## A txt file is also generated with filenames for the removed_20 data
###
import pandas as pd
from sklearn.model_selection import train_test_split

# Load CSV
file_path = "/Users/kieran/Library/CloudStorage/OneDrive-UniversityofArizona/weather_iv_lit/training/training_new_labels/training_all_new.xlsx"
df = pd.read_excel(file_path)

# Calculate exact whole number split sizes
total_rows = len(df)
test_size = round(total_rows * 0.20)
train_size = total_rows - test_size

# Perform split with exact whole numbers
# Random_state=42 leads to split that can be replicated. Remove the line for a completely random split with each rerun.
train_df, test_df = train_test_split(
    df,
    test_size=test_size,
    random_state=42
)

# Save training data (80%)
train_output_path = "/Users/kieran/Library/CloudStorage/OneDrive-UniversityofArizona/weather_iv_lit/training/data_prep_all_models/train_80.csv"
train_df.to_csv(train_output_path, index=False)

# Save test filenames (20%)
test_filenames = test_df["filename"]
test_output_path = "/Users/kieran/Library/CloudStorage/OneDrive-UniversityofArizona/weather_iv_lit/training/data_prep_all_models/test_filenames.txt"
test_filenames.to_csv(test_output_path, index=False, header=False)
# Save removed rows (20%)
test_df.to_csv("/Users/kieran/Library/CloudStorage/OneDrive-UniversityofArizona/weather_iv_lit/training/data_prep_all_models/removed_20.csv", index=False)

# Verification output
print(f"""Split complete:
- Original rows: {total_rows}
- Training set: {len(train_df)} rows ({len(train_df)/total_rows:.1%})
- Test filenames: {len(test_filenames)} files ({len(test_filenames)/total_rows:.1%})""")


