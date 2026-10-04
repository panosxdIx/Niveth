#!/usr/bin/env bash

set -euo pipefail

UUID="niveth-system-monitor@nivethos"

echo "============================================================"
echo " NIVETH SYSTEM MONITOR — V17 RECOVERY"
echo "============================================================"
echo

echo "[1/3] Checking extension..."

if [ ! -f \
    "$HOME/.local/share/gnome-shell/extensions/$UUID/extension.js" ]; then

    echo "[FAIL] System Monitor extension files not found."
    exit 1
fi

echo "[PASS] Extension files found"
echo

echo "[2/3] Enabling working V17..."

gnome-extensions enable "$UUID"

sleep 2

echo "[PASS] Extension enabled"
echo

echo "[3/3] Checking status..."

gnome-extensions info "$UUID" 2>&1 || true

echo
echo "============================================================"
echo " V17 RECOVERY COMPLETE"
echo "============================================================"
echo
echo "The previous working monitor has been restored."
echo
