#!/usr/bin/env bash

set -Eeuo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP_DIR="$PROJECT_ROOT/build/source-backup-before-user-path-fix-$STAMP"

echo "============================================================"
echo " Niveth - User Path Normalization"
echo "============================================================"
echo
echo "Project : $PROJECT_ROOT"
echo "Backup  : $BACKUP_DIR"
echo

mkdir -p "$BACKUP_DIR"

backup_file() {
    local file="$1"

    if [[ -f "$file" ]]; then
        local relative
        relative="${file#$PROJECT_ROOT/}"

        mkdir -p "$BACKUP_DIR/$(dirname "$relative")"
        cp -a "$file" "$BACKUP_DIR/$relative"

        echo "BACKUP  $relative"
    fi
}

require_file() {
    local file="$1"

    if [[ ! -f "$file" ]]; then
        echo
        echo "ERROR: required source file does not exist:"
        echo "  $file"
        exit 1
    fi
}

FILES_TO_FIX=(
    "$HOME/.local/bin/niveth-app-center"
    "$HOME/.local/bin/niveth-files"

    "$HOME/.local/share/applications/com.niveth.Notes.desktop"
    "$HOME/.local/share/applications/org.niveth.Files.desktop"
    "$HOME/.local/share/applications/niveth-terminal.desktop"

    "$HOME/.local/share/niveth-app-center/niveth-app-center.py"
)

echo "=== Checking source files ==="

for file in "${FILES_TO_FIX[@]}"; do
    require_file "$file"
    echo "OK      $file"
done

echo
echo "=== Creating backups ==="

for file in "${FILES_TO_FIX[@]}"; do
    backup_file "$file"
done

echo
echo "=== Applying user-independent paths ==="

python3 - <<'PY'
from pathlib import Path
import os

home = Path.home()

replacements = {
    # --------------------------------------------------------
    # Niveth App Center launcher
    # --------------------------------------------------------
    home / ".local/bin/niveth-app-center": [
        (
            f'{home}/.local/share/niveth-app-center/niveth-app-center.py',
            '/usr/lib/niveth/apps/niveth-app-center/niveth-app-center.py',
        ),
    ],

    # --------------------------------------------------------
    # Niveth Files launcher
    # --------------------------------------------------------
    home / ".local/bin/niveth-files": [
        (
            f'{home}/Niveth-Files/main.py',
            '/usr/lib/niveth/apps/niveth-files/main.py',
        ),
    ],

    # --------------------------------------------------------
    # Niveth App Center internal post-install launcher
    # --------------------------------------------------------
    home / ".local/share/niveth-app-center/niveth-app-center.py": [
        (
            f'{home}/.local/bin/niveth-post-install',
            '/usr/local/bin/niveth-post-install',
        ),
    ],

    # --------------------------------------------------------
    # Niveth Notes desktop launcher
    # --------------------------------------------------------
    home / ".local/share/applications/com.niveth.Notes.desktop": [
        (
            f'python3 {home}/.local/share/niveth-notes/niveth-notes.py',
            'python3 /usr/lib/niveth/apps/niveth-notes/niveth-notes.py',
        ),
    ],

    # --------------------------------------------------------
    # Niveth Files desktop launcher
    # --------------------------------------------------------
    home / ".local/share/applications/org.niveth.Files.desktop": [
        (
            f'Exec={home}/.local/bin/niveth-files',
            'Exec=/usr/local/bin/niveth-files',
        ),
        (
            f'TryExec={home}/.local/bin/niveth-files',
            'TryExec=/usr/local/bin/niveth-files',
        ),
    ],

    # --------------------------------------------------------
    # Niveth Terminal desktop launcher
    # --------------------------------------------------------
    home / ".local/share/applications/niveth-terminal.desktop": [
        (
            f'Exec={home}/.local/bin/niveth-terminal',
            'Exec=/usr/local/bin/niveth-terminal',
        ),
    ],
}

for path, items in replacements.items():

    if not path.is_file():
        raise SystemExit(f"Missing source file: {path}")

    text = path.read_text()

    original = text

    for old, new in items:
        text = text.replace(old, new)

    if text == original:
        print(f"NOTE    no change needed: {path}")
    else:
        path.write_text(text)
        print(f"FIXED   {path}")
PY

echo
echo "=== Checking source files for /home/modos hardcoded paths ==="

FOUND=0

while IFS= read -r file; do

    if grep -n '/home/modos' "$file" >/dev/null 2>&1; then
        echo
        echo "FOUND: $file"
        grep -n '/home/modos' "$file"
        FOUND=1
    fi

done < <(
    printf '%s\n' \
        "$HOME/.local/bin/niveth-app-center" \
        "$HOME/.local/bin/niveth-files" \
        "$HOME/.local/share/niveth-app-center/niveth-app-center.py" \
        "$HOME/.local/share/applications/com.niveth.Notes.desktop" \
        "$HOME/.local/share/applications/org.niveth.Files.desktop" \
        "$HOME/.local/share/applications/niveth-terminal.desktop"
)

echo

if [[ "$FOUND" -eq 0 ]]; then
    echo "OK: no /home/modos paths remain in the fixed source files."
else
    echo "ERROR: some hardcoded /home/modos paths remain."
    exit 1
fi

echo
echo "============================================================"
echo " User path normalization completed successfully"
echo "============================================================"
echo
echo "Backup:"
echo "  $BACKUP_DIR"
echo
