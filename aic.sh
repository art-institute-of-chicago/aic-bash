#!/bin/bash

# https://stackoverflow.com/questions/59895/getting-the-source-directory-of-a-bash-script-from-within
DIR_SCRIPT="$(dirname "${BASH_SOURCE[0]}")"
DIR_QUERIES="$DIR_SCRIPT/queries"

IMAGE_PATH="/tmp/default.jpg"

# Check what flags were passed
while test $# != 0
do
    case "$1" in
    -f|--fill) OPT_FILL=--fill ;;
    *)  usage ;;
    esac
    shift
done

API_URL='https://aggregator-data.artic.edu/api/v1/search'
API_QUERY="$(cat "$DIR_QUERIES/default-random-public-domain-oil-painting.json")"

# Replace "VAR_NOW" in query with an actual timestamp
API_QUERY="$(echo "$API_QUERY" | sed "s/VAR_NOW/$(date +"%T")/g")"

# Assume that the response contains at least one artwork record
API_RESPONSE="$(curl -s -H "Content-Type: application/json; charset=UTF-8" -d "$API_QUERY" "$API_URL")"

# Parse artwork fields using jq
# https://stedolan.github.io/jq/
ARTWORK_ID="$(echo "$API_RESPONSE" | jq -r '.data[0].id')"
ARTWORK_TITLE="$(echo "$API_RESPONSE" | jq -r '.data[0].title')"
ARTWORK_DATE="$(echo "$API_RESPONSE" | jq -r '.data[0].date_display')"
ARTWORK_ARTIST="$(echo "$API_RESPONSE" | jq -r '.data[0].artist_display')"
IMAGE_ID="$(echo "$API_RESPONSE" | jq -r '.data[0].image_id')"

# Download image from AIC's IIIF server
curl -s "https://www.artic.edu/iiif/2/$IMAGE_ID/full/80,/0/default.jpg" --output "$IMAGE_PATH"

# We cheat here and modify the built-in variable for terminal height
# This causes jp2a to underestimate when doing --term-fit
# We need the extra space to output artwork info
OLD_LINES="$(tput lines)"
export LINES="$(( ${OLD_LINES}-4 ))"

# https://github.com/cslarsen/jp2a
INPUT="$(jp2a --term-fit --color --html $OPT_FILL "$IMAGE_PATH")"

# Restore the hacked term variable
export LINES="$OLD_LINES"

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

# For performance, we'll do just one check here, rather than inside the loops
# This causes code duplication, so be sure to double check when you make changes
if [ -z "$OPT_FILL" ]; then

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
                    OUTPUT+="\033[38;2;${R};${G};${B}m${C}"

                done
            done <<< "$ROW"

            # Reset color and insert newline
            OUTPUT+='\033[0m\n'

        done
    done <<< "$INPUT"

else

    # Split HTML by <br/> into rows
    while IFS=$'\n' read -ra ROWS; do
        for ROW in "${ROWS[@]}"; do

            # Transform spans into space-separated quadruples of R G B [Char], using pipes as span-separators
            ROW="$(echo "$ROW" | sed -re "s/<span style='color:#([a-f0-9]{2})([a-f0-9]{2})([a-f0-9]{2}); background-color:#([a-f0-9]{2})([a-f0-9]{2})([a-f0-9]{2});'>(.)<\/span>/\1 \2 \3 \4 \5 \6 \7|/g")"

            # Discard the last pipe
            ROW="${ROW::-1}"

            # Split row into columns using pipes
            while IFS='|' read -ra COLS; do
                for COL in "${COLS[@]}"; do

                    # Split column into values using spaces
                    COL=($COL)

                    # Handle the background color
                    R="$(( 16#${COL[3]} ))"
                    G="$(( 16#${COL[4]} ))"
                    B="$(( 16#${COL[5]} ))"

                    # https://gist.github.com/XVilka/8346728
                    OUTPUT+="\033[48;2;${R};${G};${B}m"

                    # Handle the foreground color
                    R="$(( 16#${COL[0]} ))"
                    G="$(( 16#${COL[1]} ))"
                    B="$(( 16#${COL[2]} ))"

                    # Get character and fix spaces
                    C="${COL[6]//&/ }"

                    # https://gist.github.com/XVilka/8346728
                    OUTPUT+="\033[38;2;${R};${G};${B}m${C}"

                done
            done <<< "$ROW"

            # Reset color and insert newline
            OUTPUT+='\033[0m\n'

        done
    done <<< "$INPUT"

fi

printf "$OUTPUT"

# https://stackoverflow.com/questions/47050589/create-url-friendly-slug-with-pure-bash
slugify () {
    echo "$1" | iconv -t ascii//TRANSLIT | sed -r s/[~\^]+//g | sed -r s/[^a-zA-Z0-9]+/-/g | sed -r s/^-+\|-+$//g | tr A-Z a-z
}

# Output artwork info
echo "$ARTWORK_TITLE, $ARTWORK_DATE"
echo "$ARTWORK_ARTIST"
echo "https://www.artic.edu/artworks/$ARTWORK_ID/$(slugify "$ARTWORK_TITLE")"

# Clean up temporary files
rm "$IMAGE_PATH"
