#!/bin/bash

# List of files to process
files=(
    "m21_ldt_mea_200300_050050_1_AB_bf.txt"
    "m21_ldt_mea_200300_050050_1_BA_bf.txt"
    "m21_ldt_mea_300500_050050_1_AB_bf.txt"
    "m21_ldt_mea_300500_050050_1_BA_bf.txt"
)

# Loop through each file and process
for file in "${files[@]}"; do
    # Use sed to remove spaces and replace tabs with commas
    sed -e 's/ //g' -e 's/\t/,/g' "$file" > "processed_$file"
    echo "Processed $file -> processed_$file"
done
