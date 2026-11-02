#!/bin/bash
# Double-click in Finder to build Breath of the Wild from your own files.
# By default, game files live in ../SourceData, keys in ../NS Key/prod.keys,
# and shared fonts in the existing Tears of the Kingdom work folder.
# Override these paths with environment variables or edit the defaults below.

set -u
set -o pipefail

REPO_ROOT="$(cd "$(dirname "$0")" && pwd)"
GAME_FILES_ROOT="${GAME_FILES_ROOT:-$(dirname "$REPO_ROOT")}"
KEYS_FILE="${KEYS_FILE:-$GAME_FILES_ROOT/NS Key/prod.keys}"
SHARED_FONTS="${SHARED_FONTS:-$GAME_FILES_ROOT/SourceData/The Legend of Zelda Tears of the Kingdom/TOTK_build/totk/extracted/firmware/shared-fonts}"
OUTPUT_APP="${OUTPUT_APP:-}"
PYTHON="${PYTHON:-}"
BASE_GAME="${BASE_GAME:-}"
LOG_DIR="$HOME/Library/Logs"

pause_and_exit() {
    local status="${1:-1}"
    echo
    read -r -p "Press Return to close this window. " _ || true
    exit "$status"
}

select_candidate() {
    local label="$1"
    local index
    CHOSEN=""

    if [ "${#CANDIDATES[@]}" -eq 0 ]; then
        return 1
    fi
    if [ "${#CANDIDATES[@]}" -eq 1 ]; then
        CHOSEN="${CANDIDATES[0]}"
        return 0
    fi

    echo "Multiple $label files were found:"
    for ((index = 0; index < ${#CANDIDATES[@]}; index++)); do
        printf '  %d) %s\n' "$((index + 1))" "${CANDIDATES[$index]}"
    done
    while true; do
        read -r -p "Choose a file (1-${#CANDIDATES[@]}): " index || return 1
        if [[ "$index" =~ ^[0-9]+$ ]] && [ "$index" -ge 1 ] && [ "$index" -le "${#CANDIDATES[@]}" ]; then
            CHOSEN="${CANDIDATES[$((index - 1))]}"
            return 0
        fi
        echo "Enter a number from 1 to ${#CANDIDATES[@]}."
    done
}

find_candidates() {
    local title_id="$1"
    shift
    CANDIDATES=()
    while IFS= read -r -d '' file; do
        CANDIDATES+=("$file")
    done < <(
        find "$GAME_FILES_ROOT" -path "$REPO_ROOT" -prune -o -type f -iname "*$title_id*" \( "$@" \) -print0 2>/dev/null
    )
}

has_shared_fonts() {
    local fonts_dir="$1"
    local font
    for font in \
        0-standard.bfttf \
        1-chinese-simplified.bfttf \
        2-chinese-simplified-extension.bfttf \
        3-chinese-traditional.bfttf \
        4-korean.bfttf \
        5-nintendo-extension.bfttf; do
        [ -s "$fonts_dir/$font" ] || return 1
    done
}

if [ ! -d "$GAME_FILES_ROOT" ]; then
    echo "Game files folder not found: $GAME_FILES_ROOT"
    pause_and_exit
fi

if [ -z "$PYTHON" ]; then
    for candidate in /opt/homebrew/bin/python3.14 /usr/local/bin/python3.14 "$(command -v python3.14 || true)"; do
        if [ -n "$candidate" ] && [ -x "$candidate" ]; then
            PYTHON="$candidate"
            break
        fi
    done
fi
if [ -z "$PYTHON" ] || [ ! -x "$PYTHON" ]; then
    echo "Python 3.14 is needed. Install it with: brew install python@3.14"
    pause_and_exit
fi
if [ ! -d /opt/homebrew/opt/opus ] || [ ! -d /opt/homebrew/opt/libvpx ]; then
    echo "Missing Homebrew dependencies. Install them with: brew install opus libvpx"
    pause_and_exit
fi
if ! xcrun --show-sdk-path >/dev/null 2>&1; then
    echo "Xcode Command Line Tools are missing or unavailable. Run: xcode-select --install"
    pause_and_exit
fi

if [ -z "$BASE_GAME" ]; then
    find_candidates 01007EF00011E000 -iname '*.xci' -o -iname '*.nsp'
    if ! select_candidate "Breath of the Wild base game"; then
        echo "Could not find a Breath of the Wild base XCI/NSP with title ID 01007EF00011E000."
        echo "Set BASE_GAME to the path of your own supported game file."
        pause_and_exit
    fi
    BASE_GAME="$CHOSEN"
fi
if [ ! -f "$BASE_GAME" ]; then
    echo "Game file not found: $BASE_GAME"
    pause_and_exit
fi

if [ ! -f "$KEYS_FILE" ]; then
    CANDIDATES=()
    while IFS= read -r -d '' file; do
        CANDIDATES+=("$file")
    done < <(find "$GAME_FILES_ROOT" -path "$REPO_ROOT" -prune -o -type f -iname 'prod.keys' -print0 2>/dev/null)
    if select_candidate "prod.keys"; then
        KEYS_FILE="$CHOSEN"
    else
        echo "prod.keys not found. Set KEYS_FILE to the file dumped from your own Switch."
        pause_and_exit
    fi
fi

if ! has_shared_fonts "$SHARED_FONTS"; then
    echo "The six required shared-font files were not found in:"
    echo "  $SHARED_FONTS"
    echo "Set SHARED_FONTS to the shared-fonts folder from a previous Tears of the Kingdom build."
    pause_and_exit
fi

if [ -z "$OUTPUT_APP" ]; then
    OUTPUT_APP="$(dirname "$BASE_GAME")/Breath of the Wild.app"
fi
mkdir -p "$LOG_DIR" || pause_and_exit
log_file="$LOG_DIR/MacNativeGames-build-botw-$(date '+%Y%m%d-%H%M%S').log"
build_args=("$BASE_GAME" -k "$KEYS_FILE" --shared-fonts "$SHARED_FONTS" -o "$OUTPUT_APP")

echo "Building Breath of the Wild with the current repository code."
echo "The build can take about 20 minutes. Keep this window open."
echo "Output: $OUTPUT_APP"
echo "Log: $log_file"
echo
cd "$REPO_ROOT" || pause_and_exit
"$PYTHON" build_app.py "${build_args[@]}" 2>&1 | tee "$log_file"
status=$?

if [ "$status" -eq 0 ]; then
    echo
    echo "Build complete: $OUTPUT_APP"
    open -R "$OUTPUT_APP"
else
    echo
    echo "Build failed with exit code $status. See the log above or: $log_file"
fi
pause_and_exit "$status"
