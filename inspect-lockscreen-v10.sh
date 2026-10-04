#!/usr/bin/env bash

set -u

UUID="niveth-lockscreen@nivethos"
EXT="$HOME/.local/share/gnome-shell/extensions/$UUID"
OUT="$HOME/Niveth/lockscreen-v10-current.txt"

{
    echo "============================================================"
    echo " NIVETH LOCK SCREEN — EXACT V10 STATE"
    echo "============================================================"
    echo

    echo "=== DATE ==="
    date
    echo

    echo "=== GNOME ==="
    gnome-shell --version 2>&1 || true
    echo

    echo "=== EXTENSION INFO ==="
    gnome-extensions info "$UUID" 2>&1 || true
    echo

    echo "=== METADATA.JSON ==="
    echo "------------------------------------------------------------"
    cat "$EXT/metadata.json" 2>&1 || true
    echo

    echo "=== EXTENSION.JS ==="
    echo "------------------------------------------------------------"
    cat "$EXT/extension.js" 2>&1 || true
    echo

    echo "=== STYLESHEET.CSS ==="
    echo "------------------------------------------------------------"
    cat "$EXT/stylesheet.css" 2>&1 || true
    echo

    echo "=== BACKUPS ==="
    echo "------------------------------------------------------------"
    find "$EXT" -maxdepth 1 -type d -name 'backup-*' -printf '%f\n' 2>/dev/null | sort
    echo

    echo "=== RELEVANT FUNCTIONS ==="
    echo "------------------------------------------------------------"
    grep -nE \
        'enable|disable|_apply|_updateBackgroundEffects|_removeBlur|_placeLogo|background|blur|dialog' \
        "$EXT/extension.js" 2>&1 || true
    echo

    echo "=== RECENT LOCKSCREEN LOGS ==="
    echo "------------------------------------------------------------"
    journalctl \
        --user \
        -b \
        --no-pager \
        2>/dev/null |
    grep -Ei \
        'NIVETH LOCK SCREEN|unlockDialog|unlock-dialog|background|blur' |
    tail -150 || true
    echo

    echo "============================================================"
    echo " END"
    echo "============================================================"

} > "$OUT"

echo
echo "============================================================"
echo " V10 DIAGNOSTIC COMPLETE"
echo "============================================================"
echo
echo "Saved to:"
echo "  $OUT"
echo
echo "File size:"
ls -lh "$OUT"
echo
echo "============================================================"
