#!/usr/bin/env bash

if ! [ -x "$(command -v jq)" ]; then
    echo 'Please install jq: https://stedolan.github.io/jq/' >&2
    exit 1
fi

if ! [ -x "$(command -v jp2a)" ]; then
    echo 'Please install jp2a: https://csl.name/jp2a/' >&2
    exit 1
fi

# https://stackoverflow.com/questions/59895/getting-the-source-directory-of-a-bash-script-from-within
DIR_SCRIPT="$(dirname "${BASH_SOURCE[0]}")"
DIR_QUERIES="$DIR_SCRIPT/queries"
DIR_CACHES="$DIR_SCRIPT/caches"

FILE_IMAGE="/tmp/aic-bash.jpg"
FILE_RESPONSE="/tmp/aic-bash.json"

API_URL='https://aggregator-data.artic.edu/api/v1/search'

OPT_FILL='--fill' # fill background by default
OPT_SIZE='843' # default for artwork detail pages

# we define default OPT_LIMIT later, so that we can validate options
MAX_LIMIT='100' # hard cap on --limit for serverside performance

# Clear stale cached results
for FILE_CACHE in "$DIR_CACHES"/*.txt; do
    [ -e "$FILE_CACHE" ] || continue
    CACHE_MAXAGE="$(jq -r '.maxage' "$FILE_CACHE")"
    CACHE_AGE="$(( $(date '+%s') - $(date -r "$FILE_CACHE" '+%s') ))"
    if [ $CACHE_AGE -gt $CACHE_MAXAGE ]; then
        rm "$FILE_CACHE"
    fi
done

# Check what options were passed
while test $# != 0; do
    case "$1" in
        -c|--cache)
            if [ ! -z "$2" ] && [[ $2 =~ ^[0-9]+$ ]] ; then
                OPT_CACHE=$2;
                shift 2
            else
                OPT_CACHE=3600;
                shift 1
            fi
        ;;
        -i|--id)
            if [ -z "$2" ] || ! [[ $2 =~ ^[0-9]+$ ]] ; then
                echo "Please provide a numeric id for the --id option." >&2
                exit 1
            fi
            OPT_ID=$2;
            shift 2
        ;;
        -j|--json)
            if [ -z "$2" ] || [[ $2 =~ ^- ]] ; then
                echo "Please provide a path for the --json option." >&2
                exit 1
            fi
            OPT_JSON=$2;
            shift 2
        ;;
        -l|--limit)
            if [ -z "$2" ] || ! [[ $2 =~ ^[0-9]+$ ]] ; then
                echo "Please provide a number for the --limit option." >&2
                exit 1
            fi
            if [ "$2" -gt $MAX_LIMIT ] ; then
                echo "Please keep --limit under $MAX_LIMIT." >&2
                exit 1
            fi
            if [ "$2" -lt 1 ] ; then
                echo "Please set --limit to at least 1." >&2
                exit 1
            fi
            OPT_LIMIT=$2;
            shift 2
        ;;
        -n|--no-fill)
            OPT_FILL='';
            shift
        ;;
        -q|--quality)
            if [ "$2" = 'h' ] || [ "$2" = 'high' ] ; then
                OPT_SIZE='843'
            elif [ "$2" = 'm' ] || [ "$2" = 'medium' ] ; then
                OPT_SIZE='400'
            elif [ "$2" = 'l' ] || [ "$2" = 'low' ] ; then
                OPT_SIZE='200'
            else
                echo "Please provide a valid value for the --quality option:" >&2
                echo "  h, m, l, high, medium, low" >&2
                exit 1
            fi
            shift 2
        ;;
        -s|--seed)
            if [ -z "$2" ] || [[ $2 =~ ^- ]] ; then
                echo "Please provide a value for the --seed option." >&2
                exit 1
            fi
            OPT_SEED=$2;
            shift 2
        ;;
        -*)
            echo "usage: $(basename $0) [options] [query]"
            echo "  -c, --cache [num]     Cache results of this query for [num] seconds."
            echo "                        [num] defaults to 1 hour (3600 sec) if blank."
            echo "                        Use cached results if available."
            echo "  -i, --id <id>         Retrive specific artwork via numeric id."
            echo "  -j, --json <path>     Path to JSON file containing a query to run."
            echo "  -l, --limit <num>     How many artworks to retrieve. Defaults to 1."
            echo "                        One random artwork from results will be shown."
            echo "  -n, --no-fill         Disable background color fill."
            echo "  -q, --quality <enum>  Affects width of image retrieved from server."
            echo "                        Reduces color artifacts. Valid options:"
            echo "                          h, high   = 843x (default)"
            echo "                          m, medium = 400x"
            echo "                          l, low    = 200x"
            echo "  -s, --seed <val>      For random queries. Defaults to timestamp."
            echo "  [query]               (Optional) Full-text search string."
            exit 1
        ;;
        *)
            # This allows positional arguments (i.e. full-text search) to work
            break
        ;;
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
    echo "JSON file not found: $OPT_JSON" >&2
    exit 1
fi

# Get our request body from the JSON file
API_QUERY="$(cat "$OPT_JSON")"

# Ensure the query is valid JSON
if ! jq -e . 2>&1 >/dev/null <<< "${API_QUERY}"; then
    echo "File is not valid JSON: $OPT_JSON" >&2
    exit 1
fi

# Function to validate that JSON file has placeholders to support options
function checkjson() {
    if [ ! -z "$1" ] && [[ $API_QUERY != *"$2"* ]]; then
        echo "$3 was passed, but JSON file is missing '$2' placeholder:" >&2
        echo "  $OPT_JSON" >&2
        exit 1
    fi
}

# Replace "VAR_SEED" in query with the --seed parameter
checkjson "$OPT_SEED" 'VAR_SEED' 'Seed'
if [ -z "$OPT_SEED" ]; then
    OPT_SEED="$(date +"%T")" # use current timestamp by default
fi
API_QUERY="$(echo "$API_QUERY" | sed "s/VAR_SEED/$OPT_SEED/g")"

# Replace "VAR_FULLTEXT" in query with the supplied text
checkjson "$OPT_FULLTEXT" 'VAR_FULLTEXT' 'Full-text query'
API_QUERY="$(echo "$API_QUERY" | sed "s/VAR_FULLTEXT/$OPT_FULLTEXT/g")"

# Replace "VAR_ID" in query with the --id parameter
checkjson "$OPT_ID" 'VAR_ID' 'Identifier'
API_QUERY="$(echo "$API_QUERY" | sed "s/VAR_ID/$OPT_ID/g")"

# Replace "VAR_LIMIT" in query with the --limit parameter
checkjson "$OPT_LIMIT" 'VAR_LIMIT' 'Limit'
if [ -z "$OPT_LIMIT" ]; then
    OPT_LIMIT='1' # retrieve one result by default
fi
API_QUERY="$(echo "$API_QUERY" | sed "s/VAR_LIMIT/$OPT_LIMIT/g")"

# Generate cache filename by hashing the query
FILE_CACHE="$DIR_CACHES/$(echo -n "$API_QUERY" | md5sum | awk '{print $1}').txt"

# Determine if the cache file needs to be deleted
if [ -f "$FILE_CACHE" ]; then
    if [ -z "$OPT_CACHE" ]; then
        # Delete cache file if the cache option was omitted
        rm "$FILE_CACHE"
    else
        # Delete cache file if it is older than the passed cache time
        CACHE_AGE="$(( $(date '+%s') - $(date -r "$FILE_CACHE" '+%s') ))"
        if [ $CACHE_AGE -gt $OPT_CACHE ]; then
            rm "$FILE_CACHE"
        fi
    fi
fi

# Helper for saving the cache file with (optional) specific modified time
function savecache() {
    jq -n --arg maxage "$OPT_CACHE" --argjson response "$1" '{"maxage":$maxage,"response":$response}' > "$FILE_CACHE"
    if [ ! -z "$2" ]; then
        touch -d "$2" "$FILE_CACHE"
    fi
}

# If the cache file still exists, use it
if [ -f "$FILE_CACHE" ]; then

    API_CACHE="$(cat "$FILE_CACHE")"

    API_RESPONSE="$(echo "$API_CACHE" | jq -r '.response')"
    API_COUNT="$(echo "$API_RESPONSE" | jq -r '.data | length')"

    # Update maxage in cache file to match cache option, but preserve its modified time
    CACHE_MAXAGE="$(echo "$API_CACHE" | jq -r '.maxage')"
    if [ $CACHE_MAXAGE -ne $OPT_CACHE ]; then
        savecache "$API_RESPONSE" "$(date -r "$FILE_CACHE" --rfc-3339 ns)"
    fi

else

    # Actually query the API! Ensure that the request succeeded
    STATUS="$(curl -s -H "Content-Type: application/json; charset=UTF-8" -d "$API_QUERY" -w %{http_code} -m 5 "$API_URL" -o "$FILE_RESPONSE")"

    if [ ! "$STATUS" = "200" ]; then
        echo "Sorry, we are having trouble connecting to our API. Try again later!" >&2
        exit 1
    fi

    API_RESPONSE="$(cat "$FILE_RESPONSE")"
    API_COUNT="$(echo "$API_RESPONSE" | jq -r '.data | length')"

    # Exit early if there's no results
    if [ "$API_COUNT" = '0' ]; then
        echo "Sorry, we couldn't find any results matching your criteria." >&2
        exit 1
    fi

    # If the cache option was passed, save response to the cache file
    if [ ! -z "$OPT_CACHE" ]; then
        savecache "$API_RESPONSE"
    fi

fi

# Select random artwork from results
API_INDEX=$(( RANDOM % $API_COUNT ))

# Parse artwork fields using jq
# https://stedolan.github.io/jq/
ARTWORK_ID="$(echo "$API_RESPONSE" | jq -r ".data[$API_INDEX].id")"
ARTWORK_TITLE="$(echo "$API_RESPONSE" | jq -r ".data[$API_INDEX].title")"
ARTWORK_DATE="$(echo "$API_RESPONSE" | jq -r ".data[$API_INDEX].date_display")"
ARTWORK_ARTIST="$(echo "$API_RESPONSE" | jq -r ".data[$API_INDEX].artist_display")"
IMAGE_ID="$(echo "$API_RESPONSE" | jq -r ".data[$API_INDEX].image_id")"

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
# https://unix.stackexchange.com/questions/13711/differences-between-sed-on-mac-osx-and-other-standard-sed
slugify () {
    echo "$1" | iconv -c -t ascii//TRANSLIT | sed -E s/[~\^]+//g | sed -E s/[^a-zA-Z0-9]+/-/g | sed -E s/^-+\|-+$//g | tr A-Z a-z
}

# Build output lines so we can measure them, mirroring website conventions
OUTPUT_TITLE_DATE="$ARTWORK_TITLE, $ARTWORK_DATE"
OUTPUT_ARTIST="$ARTWORK_ARTIST"
OUTPUT_URL="https://www.artic.edu/artworks/$ARTWORK_ID/$(slugify "$ARTWORK_TITLE")"
OUTPUT_TOMBSTONE="$OUTPUT_TITLE_DATE"$'\n'"$OUTPUT_ARTIST"$'\n'"$OUTPUT_URL"

# Now that the tombstone is ready, abort early if there's no image
if [ "$IMAGE_ID" = "null" ]; then
    echo -e "\033[0;31mUnfortunately, this artwork has no preferred image.\033[0m" >&2
    echo "$OUTPUT_TOMBSTONE"
    exit 1
fi

# Download image from AIC's IIIF server
STATUS="$(curl -s "https://www.artic.edu/iiif/2/$IMAGE_ID/full/$OPT_SIZE,/0/default.jpg" -w %{http_code} -m 5 --output "$FILE_IMAGE")"

if [ ! "$STATUS" = "200" ]; then
    echo "Sorry, we are having trouble downloading the image. Try again later!" >&2
    exit 1
fi

# We cheat here and modify the built-in variable for terminal height
# This causes jp2a to underestimate when doing --term-fit
OLD_LINES="$(tput lines)"
export LINES="$(( ${OLD_LINES}-$(linecount "$OUTPUT_TOMBSTONE") ))"

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
            ROW="$(echo "$ROW" | sed -E "s/<span style='color:#([a-f0-9]{2})([a-f0-9]{2})([a-f0-9]{2});'>(.)<\/span>/\1 \2 \3 \4|/g")"

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
            ROW="$(echo "$ROW" | sed -E "s/<span style='color:#([a-f0-9]{2})([a-f0-9]{2})([a-f0-9]{2}); background-color:#([a-f0-9]{2})([a-f0-9]{2})([a-f0-9]{2});'>(.)<\/span>/\1 \2 \3 \4 \5 \6 \7|/g")"

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
echo "$OUTPUT_TOMBSTONE"

# Clean up temporary files
if [ -f "$FILE_IMAGE" ]; then
    rm "$FILE_IMAGE"
fi

if [ -f "$FILE_RESPONSE" ]; then
    rm "$FILE_RESPONSE"
fi
