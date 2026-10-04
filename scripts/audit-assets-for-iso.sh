#!/usr/bin/env bash

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

echo "============================================================"
echo "NIVETH ASSET SOURCE AUDIT"
echo "============================================================"
echo
echo "PROJECT_ROOT=$PROJECT_ROOT"

echo
echo "=== 1. Niveth Notes assets ==="
echo

find \
    "$HOME/Niveth" \
    "$HOME/.local/share/niveth-notes" \
    "$HOME/Niveth-desktop-snapshot-"* \
    -type f \
    \( \
        -iname '*note*' \
        -o -iname '*.svg' \
        -o -iname '*.png' \
        -o -iname '*.jpg' \
    \) \
    2>/dev/null | sort | head -300

echo
echo "=== 2. Niveth App Center assets ==="
echo

find \
    "$HOME/Niveth" \
    "$HOME/.local/share/niveth-app-center" \
    "$HOME/Niveth-desktop-snapshot-"* \
    -type f \
    \( \
        -iname '*app*' \
        -o -iname '*center*' \
        -o -iname '*.svg' \
        -o -iname '*.png' \
        -o -iname '*.jpg' \
    \) \
    2>/dev/null | sort | head -300

echo
echo "=== 3. Niveth Files assets ==="
echo

find \
    "$HOME/Niveth-Files" \
    "$HOME/Niveth" \
    -type f \
    \( \
        -iname '*org.niveth.Files*' \
        -o -iname '*.svg' \
        -o -iname '*.png' \
        -o -iname '*.jpg' \
    \) \
    2>/dev/null | sort | head -300

echo
echo "=== 4. Cursor theme directories ==="
echo

find \
    "$HOME/.icons" \
    "$HOME/.local/share/icons" \
    "/usr/share/icons" \
    -maxdepth 4 \
    -type d \
    -iname '*retrosmart*' \
    2>/dev/null | sort

echo
echo "=== 5. Cursor theme references ==="
echo

grep -Ril \
    "retrosmart-xcursor-mac-ish-gruvbox" \
    "$HOME/.icons" \
    "$HOME/.local/share/icons" \
    "/usr/share/icons" \
    2>/dev/null | sort

echo
echo "=== 6. Cursor-related theme files ==="
echo

find \
    "$HOME/.icons" \
    "$HOME/.local/share/icons" \
    "/usr/share/icons" \
    -maxdepth 5 \
    -type f \
    \( \
        -name 'cursor.theme' \
        -o -name 'index.theme' \
    \) \
    2>/dev/null | \
    grep -Ei 'retro|gruvbox|mac|cursor' | sort | head -300

echo
echo "=== 7. Current host GNOME settings ==="
echo

echo "Icon theme:"
gsettings get org.gnome.desktop.interface icon-theme 2>/dev/null || true

echo
echo "Cursor theme:"
gsettings get org.gnome.desktop.interface cursor-theme 2>/dev/null || true

echo
echo "Cursor size:"
gsettings get org.gnome.desktop.interface cursor-size 2>/dev/null || true

echo
echo "=== 8. Current desktop entries ==="
echo

for app in \
    "com.niveth.Notes.desktop" \
    "com.niveth.AppCenter.desktop" \
    "org.niveth.Files.desktop" \
    "niveth-ptyxis.desktop"
do
    echo
    echo "--- $app ---"

    find \
        "$HOME/.local/share/applications" \
        "/usr/share/applications" \
        -type f \
        -name "$app" \
        -print \
        2>/dev/null | head -10
done

echo
echo "=== 9. Icon files currently installed in hicolor ==="
echo

find \
    "/usr/share/icons/hicolor" \
    "$HOME/.local/share/icons/hicolor" \
    -type f \
    2>/dev/null | \
    grep -Ei 'niveth|notes|appcenter|files' | sort | head -300

echo
echo "=== 10. Niveth project icon directories ==="
echo

find \
    "$PROJECT_ROOT" \
    -maxdepth 5 \
    -type d \
    2>/dev/null | \
    grep -Ei '/(icons|icon|assets)$|icons/' | sort | head -300

echo
echo "============================================================"
echo "END OF ASSET AUDIT"
echo "============================================================"
