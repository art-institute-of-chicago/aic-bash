#!/bin/bash

IMAGE_ID="d02e0079-8e82-733e-683c-cb83a387ee5e"

curl -s "https://www.artic.edu/iiif/2/$IMAGE_ID/full/80,/0/default.jpg" --output default.jpg

INPUT="$(jp2a --term-fit --color --html default.jpg)"

# Remove HTML tags from beginning and end
INPUT="${INPUT:449}"
INPUT="${INPUT::-29}"
INPUT="${INPUT::-5}" # <br/>

# Replace &nbsp; with a placeholder character that's not in the character map
# https://github.com/cslarsen/jp2a/blob/61d205f6959d88e0cc8d8879fe7d66eb0932ecca/src/options.c#L69
INPUT="${INPUT//&nbsp;/&}"

# Replace <br/> with actual newlines
INPUT="${INPUT//<br\/>/$'\n'}"

# Start building our output for rendering
OUTPUT=''

# Split HTML by <br/> into rows
while IFS=$'\n' read -ra ROWS; do
    for ROW in "${ROWS[@]}"; do

        # Transform spans into space-separated quadruples of R G B [Char], using pipes as span-separators
        ROW="$(echo "$ROW" | sed -re "s/<span style='color:#([a-f0-9]{2})([a-f0-9]{2})([a-f0-9]{2});'>(.)<\/span>/\1 \2 \3 \4|/g")"

        # Discard the last pipe
        ROW="${ROW::-1}"

        # Split row into columns using pipes
        while IFS='|' read -ra COLS; do
            for COL in "${COLS[@]}"; do

                # Split column into values using spaces
                COL=($COL)

                # Convert RGB hex to decimal
                R="$(( 16#${COL[0]} ))"
                G="$(( 16#${COL[1]} ))"
                B="$(( 16#${COL[2]} ))"

                # Get character and fix spaces
                C="${COL[3]//&/ }"

                #  https://gist.github.com/XVilka/8346728
                OUTPUT+="\033[38;2;${R};${G};${B}m${C}\033[0m"

            done
        done <<< "$ROW"

        OUTPUT+='\n'

    done
done <<< "$INPUT"

printf "$OUTPUT"
