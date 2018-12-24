#!/bin/bash

# https://stackoverflow.com/questions/59895/getting-the-source-directory-of-a-bash-script-from-within
DIR_SCRIPT="$(dirname "${BASH_SOURCE[0]}")"
DIR_QUERIES="$DIR_SCRIPT/queries"

FILE_IMAGE="/tmp/aic-bash.jpg"
FILE_RESPONSE="/tmp/aic-bash.json"

API_URL='https://aggregator-data.artic.edu/api/v1/search'

OPT_FILL='--fill' # fill by default

# Check what options were passed
while test $# != 0; do
    case "$1" in
        -i|--id) OPT_ID=$2; shift 2 ;;
        -j|--json) OPT_JSON=$2; shift 2 ;;
        -n|--no-fill) OPT_FILL=''; shift ;;
        -*)
            echo "usage: $(basename $0) [-i id] [-j file] [-n] [query]"
            echo "  -i, --id=N      Retrive specific artwork via numeric id"
            echo "  -j, --json=...  Path to JSON file containing a query to run"
            echo "  -n, --no-fill   Disable background color fill"
            echo "  [query]         (Optional) Full-text search string"
            exit 1
        ;;
        *) break ;;
    esac
done

# Check if the positional argument for full-text was passed
if [ ! -z "$1" ]; then
    OPT_FULLTEXT=$1
    shift
fi

if [ ! -z "$OPT_ID" ]; then
    OPT_JSON="$DIR_QUERIES/default-id.json"
elif [ -z "$OPT_JSON" ]; then
    if [ -z "$OPT_FULLTEXT" ]; then
        OPT_JSON="$DIR_QUERIES/default-random-public-domain-oil-painting.json"
    else
        OPT_JSON="$DIR_QUERIES/default-fulltext.json"
    fi
fi

# Normalize JSON path for validation output
OPT_JSON="$(realpath "$OPT_JSON")"

# Ensure the JSON file exists
if [ ! -f "$OPT_JSON" ]; then
    echo "File not found: $OPT_JSON"
    exit 1
fi

# Get our request body from the JSON file
API_QUERY="$(cat "$OPT_JSON")"

# Ensure the query is valid JSON
if ! jq -e . 2>&1 >/dev/null <<< "${API_QUERY}"; then
    echo "File is not valid JSON: $OPT_JSON"
    exit 1
fi

# Replace "VAR_NOW" in query with an actual timestamp
API_QUERY="$(echo "$API_QUERY" | sed "s/VAR_NOW/$(date +"%T")/g")"

# Replace "VAR_FULLTEXT" in query with the supplied text
API_QUERY="$(echo "$API_QUERY" | sed "s/VAR_FULLTEXT/$OPT_FULLTEXT/g")"

# Replace "VAR_ID" in query with the --id parameter
API_QUERY="$(echo "$API_QUERY" | sed "s/VAR_ID/$OPT_ID/g")"

# Assume that the response contains at least one artwork record
STATUS="$(curl -s -H "Content-Type: application/json; charset=UTF-8" -d "$API_QUERY" -w %{http_code} -m 5 "$API_URL" -o "$FILE_RESPONSE")"

if [ ! "$STATUS" = "200" ]; then
    echo "Sorry, we are having trouble connecting to our API. Try again later!"
    exit 1
fi

API_RESPONSE="$(cat "$FILE_RESPONSE")"

# Parse artwork fields using jq
# https://stedolan.github.io/jq/
ARTWORK_ID="$(echo "$API_RESPONSE" | jq -r '.data[0].id')"
ARTWORK_TITLE="$(echo "$API_RESPONSE" | jq -r '.data[0].title')"
ARTWORK_DATE="$(echo "$API_RESPONSE" | jq -r '.data[0].date_display')"
ARTWORK_ARTIST="$(echo "$API_RESPONSE" | jq -r '.data[0].artist_display')"
IMAGE_ID="$(echo "$API_RESPONSE" | jq -r '.data[0].image_id')"

# Download image from AIC's IIIF server
STATUS="$(curl -s "https://www.artic.edu/iiif/2/$IMAGE_ID/full/400,/0/default.jpg" -w %{http_code} -m 5 --output "$FILE_IMAGE")"

if [ ! "$STATUS" = "200" ]; then
    echo "Sorry, we are having trouble downloading the image. Try again later!"
    exit 1
fi

# We'll need to leave space for outputting artwork info
# To do so, we need to estimate how many lines the info will take to render
function linecount() {

    COLS="$(tput cols)"
    L=0

    # Account for line wrap in narrow consoles
    while IFS=$'\n' read -ra ROWS; do
        for ROW in "${ROWS[@]}"; do

            # https://stackoverflow.com/questions/2395284/round-a-divided-number-in-bash
            L="$(( ${L}+(${#ROW}+${COLS}-1)/${COLS} ))"

        done
    done <<< "$1"

    echo "$L"
}

# Not the same algorithm as on the website, but accurate enough for simpler titles
# https://stackoverflow.com/questions/47050589/create-url-friendly-slug-with-pure-bash
slugify () {
    echo "$1" | iconv -c -t ascii//TRANSLIT | sed -r s/[~\^]+//g | sed -r s/[^a-zA-Z0-9]+/-/g | sed -r s/^-+\|-+$//g | tr A-Z a-z
}

# Build output lines so we can measure them, mirroring website conventions
OUTPUT_TITLE_DATE="$ARTWORK_TITLE, $ARTWORK_DATE"
OUTPUT_ARTIST="$ARTWORK_ARTIST"
OUTPUT_URL="https://www.artic.edu/artworks/$ARTWORK_ID/$(slugify "$ARTWORK_TITLE")"

# We cheat here and modify the built-in variable for terminal height
# This causes jp2a to underestimate when doing --term-fit
OLD_LINES="$(tput lines)"
export LINES="$(( ${OLD_LINES}-$(linecount "$OUTPUT_TITLE_DATE")-$(linecount "$OUTPUT_ARTIST")-$(linecount "$OUTPUT_URL") ))"

# https://github.com/cslarsen/jp2a
INPUT="$(jp2a --term-fit --color --html $OPT_FILL "$FILE_IMAGE")"

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
if [ ! "$OPT_FILL" = '--fill' ]; then

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

# Output artwork info
echo "$OUTPUT_TITLE_DATE"
echo "$OUTPUT_ARTIST"
echo "$OUTPUT_URL"

# Clean up temporary files
rm "$FILE_IMAGE"
rm "$FILE_RESPONSE"
