#!/usr/bin/env bash

set -u

EXT_ID="niveth-dock@nivethos"
JS="$HOME/.local/share/gnome-shell/extensions/$EXT_ID/extension.js"

echo
echo "=================================================="
echo " NIVETH DOCK — CLEAN RELOAD"
echo "=================================================="
echo

if [ ! -f "$JS" ]; then
    echo "[FAIL] extension.js not found:"
    echo "$JS"
    exit 1
fi

echo "[1/6] Current extension state"

gnome-extensions info "$EXT_ID" 2>&1 \
    | grep -E "State:|Enabled:" || true

echo
echo "[2/6] Disabling Dock"

gnome-extensions disable "$EXT_ID" || true

echo "[PASS] Disable command sent"

echo
echo "[3/6] Waiting for complete teardown"

sleep 3

echo "[PASS] Wait completed"

echo
echo "[4/6] Enabling Dock"

gnome-extensions enable "$EXT_ID"

echo "[PASS] Enable command sent"

echo
echo "[5/6] Waiting for extension initialization"

sleep 4

echo "[PASS] Initialization wait completed"

echo
echo "[6/6] Final verification"

echo
echo "--- Extension state ---"

gnome-extensions info "$EXT_ID" 2>&1 \
    | grep -E "State:|Enabled:" || true

echo
echo "--- Current color scheme ---"

gsettings get org.gnome.desktop.interface color-scheme

echo
echo "--- Current Dock theme code ---"

grep -nE \
    "_updateTheme|_dock.set_style|this._isDark = dark|105, 216, 255|65, 49, 132" \
    "$JS" \
    | head -40 || true

echo
echo "--- Recent GNOME Shell errors ---"

journalctl --user -b \
    --since "30 seconds ago" \
    2>/dev/null \
    | grep -Ei \
        "niveth-dock|extension|stylesheet|syntax|error" \
    | tail -40 || true

echo
echo "=================================================="
echo " CLEAN RELOAD COMPLETE"
echo "=================================================="
echo
echo "Τώρα το Dock πρέπει να είναι πλήρως φορτωμένο"
echo "από το τρέχον extension.js."
echo
