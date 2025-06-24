###
## This script matches filenames from the 10% test CSV to those of the PDFs in the full PDF folder
## Matched PDF files are copied to a new folder callede pdf_test_10
###

import os
import shutil
from pathlib import Path


def move_test_pdfs(test_filenames_path, pdf_source_folder, test_pdf_dest):
    source_dir = Path(pdf_source_folder)
    dest_dir = Path(test_pdf_dest)
    dest_dir.mkdir(exist_ok=True, parents=True)

    with open(test_filenames_path, 'r') as f:
        test_files = [line.strip() for line in f.readlines()]

    moved = []
    missing = []

    for original_name in test_files:
        filename = original_name
        found = False

        # First try exact match
        src_path = source_dir / filename
        if src_path.exists():
            found = True
        else:
            # Case-insensitive search with any extension
            matches = list(source_dir.glob(f"{filename}.*"))
            if not matches:
                # Try filename without extension
                base_name = Path(filename).stem
                matches = list(source_dir.glob(f"{base_name}.*"))
                if not matches:
                    no_ext_file = source_dir / base_name
                    if no_ext_file.exists():
                        matches = [no_ext_file]

            # Check all matches for PDF header
            for match in matches:
                try:
                    with open(match, 'rb') as f:
                        if f.read(4) == b'%PDF':
                            src_path = match
                            found = True
                            break
                except Exception as e:
                    continue

        if not found:
            missing.append(original_name)
            continue

        # Generate destination filename
        dest_filename = f"{src_path.stem}.pdf"
        dest_path = dest_dir / dest_filename

        # Copy and preserve metadata
        shutil.copy2(src_path, dest_path)
        moved.append(dest_filename)

    # Print results (unchanged)
    print(f"\nResults:")
    print(f"Successfully moved: {len(moved)} files")
    print(f"Missing files: {len(missing)}")

    if missing:
        print("\nMissing files list:")
        print("\n".join(missing))
        print("\nTroubleshooting steps:")
        print("1. Verify filenames in test_filenames.txt match source PDFs")
        print("2. Check for extra spaces/newlines in filenames")
        print("3. Ensure files have valid PDF headers")


# Usage remains the same
move_test_pdfs(
    "/Users/kieran/Library/CloudStorage/OneDrive-UniversityofArizona/weather_iv_lit/training/models/finetune_data/test_filenames.txt",
    "/Users/kieran/Library/CloudStorage/OneDrive-UniversityofArizona/weather_iv_lit/training/training_all",
    "/Users/kieran/Library/CloudStorage/OneDrive-UniversityofArizona/weather_iv_lit/training/models/finetune_data/pdf_test_20"
)

