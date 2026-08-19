#!/bin/bash

# Renames mislabed taskID from 'VSL' to 'LDT'

# Find all files in subdirectories matching the specified pattern and rename them
find . -type f \( -name "M21_S*_VSL.eeg" -o -name "M21_S*_VSL.vhdr" -o -name "M21_S*_VSL.vmrk" \) | while read -r file; do
  # Extract the subject identifier (e.g., "S101" from "M21_S101_VSL.eeg")
  subject_id=$(echo "$file" | sed -E 's/.*(S[0-9]+)_VSL\..*/\1/')

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
