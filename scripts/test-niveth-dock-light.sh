#!/usr/bin/env bash

set -euo pipefail

EXT_ID="niveth-dock@nivethos"

echo
echo "=================================================="
echo " Niveth Dock — LIGHT MODE TEST"
echo "=================================================="
echo

echo "[1/4] Setting GNOME color scheme to Light"

gsettings set org.gnome.desktop.interface color-scheme 'prefer-light'

echo "[PASS] GNOME Light mode requested"

echo
echo "[2/4] Current color scheme"

gsettings get org.gnome.desktop.interface color-scheme

echo
echo "[3/4] Reloading Niveth Dock"

gnome-extensions disable "$EXT_ID" || true
sleep 1
gnome-extensions enable "$EXT_ID"

sleep 2

echo "[PASS] Niveth Dock reloaded"

echo
echo "[4/4] Extension status"

gnome-extensions info "$EXT_ID" | grep -E \
    "State:|Enabled:"

echo
echo "=================================================="
echo " LIGHT TEST READY"
echo "=================================================="
echo
echo "Το Dock τώρα πρέπει να χρησιμοποιεί το .light CSS."
echo
