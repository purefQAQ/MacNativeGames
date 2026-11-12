#!/bin/bash
# Double-click in Finder to rebuild Tears of the Kingdom from your own files.
# By default, game files live in ../SourceData, keys in ../NS Key/prod.keys,
# and firmware in ../Firmware*. Override these paths with environment variables
# or edit the defaults below if your files are elsewhere.

set -u
set -o pipefail

REPO_ROOT="$(cd "$(dirname "$0")" && pwd)"
GAME_FILES_ROOT="${GAME_FILES_ROOT:-$(dirname "$REPO_ROOT")}"
KEYS_FILE="${KEYS_FILE:-$GAME_FILES_ROOT/NS Key/prod.keys}"
FIRMWARE_DIR="${FIRMWARE_DIR:-}"
OUTPUT_APP="${OUTPUT_APP:-$GAME_FILES_ROOT/Tears of the Kingdom.app}"
PYTHON="${PYTHON:-}"
BASE_GAME="${BASE_GAME:-}"
UPDATE_GAME="${UPDATE_GAME:-}"
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
    find_candidates 0100F2C0115B6000 -iname '*.xci' -o -iname '*.nsp'
    if ! select_candidate "base game"; then
        echo "Could not find a Tears of the Kingdom base XCI/NSP with title ID 0100F2C0115B6000."
        echo "Set BASE_GAME to the path of your own supported 1.0.0 base game."
        pause_and_exit
    fi
    BASE_GAME="$CHOSEN"
fi
if [ ! -f "$BASE_GAME" ]; then
    echo "Base game file not found: $BASE_GAME"
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

if [ -z "$UPDATE_GAME" ]; then
    find_candidates 0100F2C0115B6800 -iname '*.nsp' -o -iname '*.nsz'
    if select_candidate "update"; then
        UPDATE_GAME="$CHOSEN"
    elif [ "${#CANDIDATES[@]}" -eq 0 ]; then
        echo "No update found. Supported updates are 1.2.1 and 1.4.3."
        read -r -p "Build the base game only (version 1.0.0)? [y/N] " answer || pause_and_exit
        case "$answer" in
            y|Y|yes|YES) ;;
            *) pause_and_exit 0 ;;
        esac
    fi
fi
if [ -n "$UPDATE_GAME" ] && [ ! -f "$UPDATE_GAME" ]; then
    echo "Update file not found: $UPDATE_GAME"
    pause_and_exit
fi

if [ -z "$FIRMWARE_DIR" ]; then
    CANDIDATES=()
    while IFS= read -r -d '' dir; do
        if find "$dir" -maxdepth 1 -type f -iname '*.nca' -print -quit 2>/dev/null | grep -q .; then
            CANDIDATES+=("$dir")
        fi
    done < <(find "$GAME_FILES_ROOT" -path "$REPO_ROOT" -prune -o -maxdepth 1 -type d -iname 'Firmware*' -print0 2>/dev/null)
    if [ "${#CANDIDATES[@]}" -gt 0 ]; then
        if ! select_candidate "firmware folder"; then
            pause_and_exit
        fi
        FIRMWARE_DIR="$CHOSEN"
    fi
fi
if [ -n "$FIRMWARE_DIR" ] && { [ ! -d "$FIRMWARE_DIR" ] || ! find "$FIRMWARE_DIR" -maxdepth 1 -type f -iname '*.nca' -print -quit 2>/dev/null | grep -q .; }; then
    echo "No firmware .nca files found in: $FIRMWARE_DIR"
    pause_and_exit
fi

mkdir -p "$LOG_DIR" || pause_and_exit
log_file="$LOG_DIR/MacNativeGames-build-totk-$(date '+%Y%m%d-%H%M%S').log"
build_args=("$BASE_GAME" -k "$KEYS_FILE" -o "$OUTPUT_APP")
if [ -n "$FIRMWARE_DIR" ]; then
    build_args+=(--firmware "$FIRMWARE_DIR")
fi
if [ -n "$UPDATE_GAME" ]; then
    build_args+=(--update "$UPDATE_GAME")
fi

echo "Building Tears of the Kingdom with the current repository code."
echo "The build can take 20–40 minutes. Keep this window open."
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
