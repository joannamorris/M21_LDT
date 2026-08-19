#!/bin/bash

# renames files with 'part1' extension to remove 'part1' and add 'LDT'

# Find all files in subdirectories matching the specified pattern and rename them
find . -type f \( -name "S*_part1.eeg" -o -name "S*_part1.vhdr" -o -name "S*_part1.vmrk" \) | while read -r file; do
  # Extract the subject identifier (e.g., "S101" from "S101_part1.eeg")
  subject_id=$(echo "$file" | sed -E 's/.*(S[0-9]+)_part1\..*/\1/')

  # Get the directory where the file is located
  dir=$(dirname "$file")

  # Create the new filename with the desired pattern (e.g., S101_LDT.eeg)
  new_file="${dir}/${subject_id}_LDT.${file##*.}"

  # Rename the file
  mv "$file" "$new_file"

  # Print the rename action
  echo "Renamed $file to $new_file"

  # If the file is a .vhdr or .vmrk file, modify its content
  if [[ "$new_file" == *.vhdr ]]; then
    # Update lines 6 and 7 in the .vhdr file to the new file names
    sed -i "" -e "6s|DataFile=.*|DataFile=${subject_id}_LDT.eeg|" \
               -e "7s|MarkerFile=.*|MarkerFile=${subject_id}_LDT.vmrk|" "$new_file"
    echo "Updated $new_file contents for DataFile and MarkerFile."
  elif [[ "$new_file" == *.vmrk ]]; then
    # Update line 5 in the .vmrk file to the new file name
    sed -i "" "5s|DataFile=.*|DataFile=${subject_id}_LDT.eeg|" "$new_file"
    echo "Updated $new_file contents for DataFile."
  fi
done
