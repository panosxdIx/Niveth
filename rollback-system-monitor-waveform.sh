#!/usr/bin/env bash

set -u

UUID="niveth-system-monitor@nivethos"
EXT="$HOME/.local/share/gnome-shell/extensions/$UUID"
ROOTFS="$HOME/Niveth/build/rootfs"
ROOTFS_EXT="$ROOTFS/usr/share/gnome-shell/extensions/$UUID"

echo
echo "============================================================"
echo " NIVETH SYSTEM MONITOR — WAVEFORM ROLLBACK"
echo "============================================================"
echo

echo "[1/6] Finding latest waveform-only backup..."

BACKUP="$(
    find "$EXT" \
        -maxdepth 1 \
        -type d \
        -name 'backup-waveform-only-*' \
        -printf '%T@ %p\n' 2>/dev/null |
    sort -nr |
    head -n1 |
    cut -d' ' -f2-
)"

if [ -z "$BACKUP" ] || [ ! -f "$BACKUP/extension.js" ]; then
    echo "[FAIL] waveform-only backup not found."
    echo
    find "$EXT" \
        -maxdepth 1 \
        -type d \
        -name 'backup-*' \
        -printf '%p\n' 2>/dev/null |
        sort
    exit 1
fi

echo "[PASS] Backup found:"
echo "  $BACKUP"
echo

echo "[2/6] Disabling System Monitor..."

gnome-extensions disable "$UUID" 2>/dev/null || true
sleep 2

echo "[3/6] Backing up current broken version..."

SAFETY="$EXT/backup-after-waveform-break-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$SAFETY"

cp -f "$EXT/extension.js" \
      "$SAFETY/extension.js" 2>/dev/null || true

cp -f "$EXT/niveth-audio-meter.py" \
      "$SAFETY/niveth-audio-meter.py" 2>/dev/null || true

echo "[PASS] Safety backup:"
echo "  $SAFETY"
echo

echo "[4/6] Restoring previous extension.js..."

cp -f \
    "$BACKUP/extension.js" \
    "$EXT/extension.js"

if [ -f "$BACKUP/stylesheet.css" ]; then
    cp -f \
        "$BACKUP/stylesheet.css" \
        "$EXT/stylesheet.css"
fi

echo "[PASS] Previous version restored."

if [ -f "$BACKUP/niveth-audio-meter.py" ]; then
    cp -f \
        "$BACKUP/niveth-audio-meter.py" \
        "$EXT/niveth-audio-meter.py"

    chmod +x \
        "$EXT/niveth-audio-meter.py"

    echo "[PASS] Audio helper restored."
fi

echo

echo "[5/6] Syncing restored version to Niveth rootfs..."

if [ -d "$ROOTFS_EXT" ]; then

    cp -f \
        "$EXT/extension.js" \
        "$ROOTFS_EXT/extension.js"

    if [ -f "$EXT/stylesheet.css" ]; then
        cp -f \
            "$EXT/stylesheet.css" \
            "$ROOTFS_EXT/stylesheet.css"
    fi

    if [ -f "$EXT/niveth-audio-meter.py" ]; then
        cp -f \
            "$EXT/niveth-audio-meter.py" \
            "$ROOTFS_EXT/niveth-audio-meter.py"

        chmod +x \
            "$ROOTFS_EXT/niveth-audio-meter.py"
    fi

    echo "[PASS] Rootfs synchronized."

else
    echo "[INFO] Rootfs extension directory not found."
fi

echo

echo "[6/6] Enabling System Monitor..."

gnome-extensions enable "$UUID" 2>/dev/null || true

sleep 5

echo
echo "============================================================"
echo " FINAL STATUS"
echo "============================================================"

gnome-extensions info "$UUID" 2>&1 || true

echo
echo "============================================================"
echo " RECENT ERRORS"
echo "============================================================"

journalctl \
    --user \
    -b \
    --no-pager \
    -o cat 2>/dev/null |
grep -Ei \
    "niveth-system-monitor|NIVETH AUDIO|TypeError|ReferenceError|SyntaxError" |
tail -40 || true

echo
echo "============================================================"
echo " ROLLBACK COMPLETE"
echo "============================================================"
echo
echo "Restored from:"
echo "  $BACKUP"
echo
echo "Safety backup:"
echo "  $SAFETY"
echo
