#!/usr/bin/env bash

set -euo pipefail

echo "============================================================"
echo "NIVETH ASSETS ONLY"
echo "============================================================"

echo
echo "=== NOTES ==="
find \
    "$HOME/.local/share/niveth-notes" \
    "$HOME/Niveth" \
    -maxdepth 6 \
    -type f \
    \( -iname '*note*.svg' -o -iname '*note*.png' -o -iname '*note*.jpg' -o -iname '*notes*.svg' -o -iname '*notes*.png' \) \
    2>/dev/null | sort

echo
echo "=== APP CENTER ==="
find \
    "$HOME/.local/share/niveth-app-center" \
    "$HOME/Niveth" \
    -maxdepth 6 \
    -type f \
    \( -iname '*app-center*.svg' -o -iname '*app-center*.png' \
       -o -iname '*appcenter*.svg' -o -iname '*appcenter*.png' \
       -o -iname '*center*.svg' -o -iname '*center*.png' \) \
    2>/dev/null | sort

echo
echo "=== FILES ICONS ==="
find \
    "$HOME/Niveth-Files" \
    "$HOME/Niveth" \
    -maxdepth 7 \
    -type f \
    \( -iname '*org.niveth.Files*.svg' \
       -o -iname '*files*.svg' \
       -o -iname '*folder*.svg' \) \
    2>/dev/null | sort

echo
echo "=== ALL Niveth SVG/PNG ASSETS ==="
find \
    "$HOME/Niveth-Files" \
    "$HOME/Niveth" \
    "$HOME/.local/share/niveth-notes" \
    "$HOME/.local/share/niveth-app-center" \
    -maxdepth 7 \
    -type f \
    \( -iname '*.svg' -o -iname '*.png' \) \
    2>/dev/null | \
    grep -Ei 'niveth|notes|app|center|files|folder|icon' | \
    sort

echo
echo "=== CURSOR THEME ==="

echo "--- exact theme name ---"
grep -Ril \
    "retrosmart-xcursor-mac-ish-gruvbox" \
    "$HOME/.icons" \
    "$HOME/.local/share/icons" \
    /usr/share/icons \
    2>/dev/null | sort

echo
echo "--- directories containing retrosmart ---"
find \
    "$HOME/.icons" \
    "$HOME/.local/share/icons" \
    /usr/share/icons \
    -type d \
    -iname '*retrosmart*' \
    2>/dev/null | sort

echo
echo "--- GNOME cursor setting ---"
gsettings get org.gnome.desktop.interface cursor-theme 2>/dev/null || true
gsettings get org.gnome.desktop.interface cursor-size 2>/dev/null || true

echo
echo "=== HOST ICON THEME ==="
gsettings get org.gnome.desktop.interface icon-theme 2>/dev/null || true

echo
echo "=== DESKTOP FILES ==="

for f in \
    "$HOME/.local/share/applications/com.niveth.Notes.desktop" \
    "$HOME/.local/share/applications/com.niveth.AppCenter.desktop" \
    "$HOME/.local/share/applications/org.niveth.Files.desktop"
do
    if [ -f "$f" ]; then
        echo
        echo "--- $f ---"
        grep -E '^(Name|Icon|Exec|StartupWMClass)=' "$f" || true
    fi
done

echo
echo "============================================================"
echo "END"
echo "============================================================"
