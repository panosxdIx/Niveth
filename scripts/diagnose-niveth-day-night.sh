#!/usr/bin/env bash

set -u

echo "=================================================="
echo " Niveth Day/Night Diagnostic"
echo "=================================================="
echo

echo "=== CURRENT TIME ==="
date
echo

echo "=== GNOME COLOR SCHEME ==="
gsettings get org.gnome.desktop.interface color-scheme 2>&1 || true
echo

echo "=== GNOME WALLPAPER LIGHT ==="
gsettings get org.gnome.desktop.background picture-uri 2>&1 || true
echo

echo "=== GNOME WALLPAPER DARK ==="
gsettings get org.gnome.desktop.background picture-uri-dark 2>&1 || true
echo

echo "=================================================="
echo " Niveth wallpaper scripts"
echo "=================================================="

for file in \
    "$HOME/.local/bin/niveth-wallpaper-time.py" \
    "$HOME/.local/bin/niveth-wallpaper-chooser.py"
do
    echo
    echo "--- $file ---"
    if [ -f "$file" ]; then
        ls -l "$file"
        echo
        sed -n '1,260p' "$file"
    else
        echo "NOT FOUND"
    fi
done

echo
echo "=================================================="
echo " User systemd wallpaper units"
echo "=================================================="

find "$HOME/.config/systemd/user" -maxdepth 1 -type f \
    \( -iname '*wallpaper*' -o -iname '*niveth*' \) \
    -print 2>/dev/null | sort

echo
echo "=== SYSTEMD TIMERS ==="
systemctl --user list-timers --all 2>&1 | grep -Ei 'wallpaper|niveth' || true

echo
echo "=== SYSTEMD SERVICES ==="
systemctl --user list-units --all 2>&1 | grep -Ei 'wallpaper|niveth' || true

echo
echo "=================================================="
echo " Wallpaper directory"
echo "=================================================="

find "$HOME/.local/share/niveth/wallpapers" \
    -maxdepth 2 \
    -type f \
    -printf '%f\n' 2>/dev/null | sort

echo
echo "=================================================="
echo " GNOME extensions related to Niveth"
echo "=================================================="

gnome-extensions list 2>&1 | grep -Ei 'niveth|dark|wallpaper' || true

echo
echo "=================================================="
echo " COMPLETE"
echo "=================================================="
