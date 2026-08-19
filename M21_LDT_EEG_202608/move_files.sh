#!/bin/bash

for f in *.*; do
    # Search for filenames containing "S", "s", or "subj" followed by 3 digits
    dir=$(echo "$f" | grep -o -i "\(S\|subj\)[0-9][0-9][0-9]") 

    # If the pattern "subj###" is found, replace "subj" with "S"
    dir=$(echo "$dir" | sed 's/subj/S/i')

    # Convert the directory name to uppercase for consistency
    dir=$(echo "$dir" | tr '[:lower:]' '[:upper:]')

    if [ "$dir" ]; then  # check if string found
        mkdir -p "$dir"  # create directory if it doesn't exist
        mv "$f" "$dir"   # move file into new dir
    else
        echo "INCORRECT FILE FORMAT: \"$f\"" # print error if file format is unexpected
    fi
done