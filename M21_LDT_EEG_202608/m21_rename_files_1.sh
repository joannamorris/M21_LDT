#!/bin/bash

# Renames files with 'm21_subj###' to 'M21_S###

# Find all files in subdirectories matching the pattern and rename them
find . -type f \( -name "m21_subj*.eeg" -o -name "m21_subj*.vhdr" -o -name "m21_subj*.vmrk" \) | while read -r file; do
  # Extract the subject number from the file name (e.g., 104 from m21_subj104_170923_part2.eeg)
  subject_number=$(echo "$file" | sed -E 's/.*subj([0-9]{3}).*/\1/')

  # Get the directory where the file is located
  dir=$(dirname "$file")

  # Create the new filename with the desired pattern (e.g., M21_S104_LDT.eeg)
  new_file="${dir}/$(echo "$file" | sed -E "s/.*subj[0-9]{3}_.*/M21_S${subject_number}_LDT.${file##*.}/")"

  # Rename the file
  mv "$file" "$new_file"

  # Print the rename action
  echo "Renamed $file to $new_file"

  # If the file is a .vhdr or .vmrk file, modify its content
  if [[ "$new_file" == *.vhdr ]]; then
    # Update lines 6 and 7 in the .vhdr file to the new file names
    sed -i "" -e "6s|DataFile=.*|DataFile=M21_S${subject_number}_LDT.eeg|" \
               -e "7s|MarkerFile=.*|MarkerFile=M21_S${subject_number}_LDT.vmrk|" "$new_file"
    echo "Updated $new_file contents for DataFile and MarkerFile."
  elif [[ "$new_file" == *.vmrk ]]; then
    # Update line 5 in the .vmrk file to the new file name
    sed -i "" "5s|DataFile=.*|DataFile=M21_S${subject_number}_LDT.eeg|" "$new_file"
    echo "Updated $new_file contents for DataFile."
  fi
done
