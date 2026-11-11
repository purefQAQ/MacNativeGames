#!/bin/bash
# Double-click to build Pokémon Pokopia 2.0.1 with the local icon image.
# Override paths with SOURCE_DUMP, WORK_DIR, SHARED_FONTS, ICON_FILE, OUTPUT_APP, or PYTHON.

set -u
set -o pipefail

REPO_ROOT="$(cd "$(dirname "$0")" && pwd)"
GAME_FILES_ROOT="${GAME_FILES_ROOT:-$(dirname "$REPO_ROOT")}"
SOURCE_DUMP="${SOURCE_DUMP:-$GAME_FILES_ROOT/SourceData/Pokémon Pokopia/Pokopia}"
WORK_DIR="${WORK_DIR:-$GAME_FILES_ROOT/SourceData/Pokémon Pokopia/Pokopia_build}"
SHARED_FONTS="${SHARED_FONTS:-$GAME_FILES_ROOT/SourceData/The Legend of Zelda Tears of the Kingdom/TOTK_build/totk/extracted/firmware/shared-fonts}"
ICON_FILE="${ICON_FILE:-$GAME_FILES_ROOT/SourceData/Icon/pokopia.jpeg}"
OUTPUT_APP="${OUTPUT_APP:-$GAME_FILES_ROOT/Pokémon Pokopia.app}"
PYTHON="${PYTHON:-}"

pause_and_exit() {
    local status="${1:-1}"
    echo
    read -r -p "Press Return to close this window. " _ || true
    exit "$status"
}

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
if [ ! -d "$SOURCE_DUMP" ]; then
    echo "Pokopia dump folder not found: $SOURCE_DUMP"
    pause_and_exit
fi
if [ ! -d "$SHARED_FONTS" ]; then
    echo "Shared fonts folder not found: $SHARED_FONTS"
    pause_and_exit
fi
if [ ! -f "$ICON_FILE" ]; then
    echo "Pokopia icon image not found: $ICON_FILE"
    pause_and_exit
fi

cd "$REPO_ROOT" || pause_and_exit
echo "Building Pokémon Pokopia with icon: $ICON_FILE"
echo "Output: $OUTPUT_APP"
echo "Work folder: $WORK_DIR"
echo
"$PYTHON" build_app.py "$SOURCE_DUMP" \
    --shared-fonts "$SHARED_FONTS" \
    --work "$WORK_DIR" \
    --out "$OUTPUT_APP" \
    --app-icon "$ICON_FILE"
status=$?

if [ "$status" -eq 0 ]; then
    echo
    echo "Build complete: $OUTPUT_APP"
    open -R "$OUTPUT_APP"
else
    echo
    echo "Build failed with exit code $status."
fi
pause_and_exit "$status"
