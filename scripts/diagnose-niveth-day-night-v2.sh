#!/usr/bin/env bash

set -u

echo "=================================================="
echo " Niveth Day/Night Diagnostic v2"
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
echo " Wallpaper pair configuration"
echo "=================================================="

if [ -f "$HOME/.config/niveth/wallpaper-pairs.json" ]; then
    cat "$HOME/.config/niveth/wallpaper-pairs.json"
else
    echo "CONFIG NOT FOUND"
fi

echo
echo "=================================================="
echo " Niveth wallpaper service"
echo "=================================================="

echo "--- Unit file ---"
systemctl --user cat niveth-wallpaper.service 2>&1 || true

echo
echo "--- Status ---"
systemctl --user status niveth-wallpaper.service \
    --no-pager \
    -l 2>&1 || true

echo
echo "--- Recent journal ---"
journalctl --user -u niveth-wallpaper.service \
    --no-pager \
    -n 80 \
    2>&1 || true

echo
echo "=================================================="
echo " Niveth wallpaper process"
echo "=================================================="

pgrep -af 'niveth-wallpaper-time.py' || true

echo
echo "=================================================="
echo " Manual script test"
echo "=================================================="

echo "Running the wallpaper script for 8 seconds..."
echo

timeout 8s \
    "$HOME/.local/bin/niveth-wallpaper-time.py" \
    2>&1 || true

echo
echo "=================================================="
echo " COMPLETE"
echo "=================================================="
