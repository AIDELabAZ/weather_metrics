###
## This script reads in a CSV containing all data and splits it into 85:15 training/validation:test CSVs
## Split is randomly determined, data are extracted to train_85 and removed_15
## A txt file is also generated with filenames for the removed_15 data
###

import pandas as pd
from sklearn.model_selection import train_test_split

# Load CSV
file_path = "/Users/kieran/Library/CloudStorage/OneDrive-UniversityofArizona/weather_iv_lit/training/models/finetune1_data/training_data_nodup.csv"
df = pd.read_csv(file_path)

# Calculate exact whole number split sizes
total_rows = len(df)
test_size = round(total_rows * 0.15)
train_size = total_rows - test_size

# Perform split with exact whole numbers
train_df, test_df = train_test_split(
    df,
    test_size=test_size,
    random_state=42
)

# Save training data (85%)
train_output_path = "/Users/kieran/Library/CloudStorage/OneDrive-UniversityofArizona/weather_iv_lit/training/models/finetune1_data/train_85.csv"
train_df.to_csv(train_output_path, index=False)

# Save test filenames (15%)
test_filenames = test_df["filename"]
test_output_path = "/Users/kieran/Library/CloudStorage/OneDrive-UniversityofArizona/weather_iv_lit/training/models/finetune1_data/test_filenames.txt"
test_filenames.to_csv(test_output_path, index=False, header=False)
# Save removed rows (15%)
test_df.to_csv("/Users/kieran/Library/CloudStorage/OneDrive-UniversityofArizona/weather_iv_lit/training/models/finetune1_data/removed_15.csv", index=False)

# Verification output
print(f"""Split complete:
- Original rows: {total_rows}
- Training set: {len(train_df)} rows ({len(train_df)/total_rows:.1%})
- Test filenames: {len(test_filenames)} files ({len(test_filenames)/total_rows:.1%})""")
