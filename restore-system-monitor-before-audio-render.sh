#!/usr/bin/env bash

set -u

UUID="niveth-system-monitor@nivethos"
EXT="$HOME/.local/share/gnome-shell/extensions/$UUID"

echo
echo "============================================================"
echo " NIVETH SYSTEM MONITOR — RESTORE PREVIOUS VERSION"
echo "============================================================"
echo

if [ ! -d "$EXT" ]; then
    echo "[FAIL] Extension directory not found:"
    echo "  $EXT"
    exit 1
fi

echo "[1/6] Searching for latest audio-render backup..."

BACKUP="$(
    find "$EXT" \
        -maxdepth 1 \
        -type d \
        -name 'backup-audio-render-*' \
        -printf '%T@ %p\n' 2>/dev/null |
    sort -nr |
    head -n1 |
    cut -d' ' -f2-
)"

if [ -z "$BACKUP" ] || [ ! -d "$BACKUP" ]; then
    echo "[FAIL] No backup-audio-render backup found."
    echo
    echo "Available backups:"
    find "$EXT" \
        -maxdepth 1 \
        -type d \
        -name 'backup-*' \
        -printf '  %p\n' 2>/dev/null |
        sort
    exit 1
fi

echo "[PASS] Backup found:"
echo "  $BACKUP"
echo

echo "[2/6] Disabling extension..."

gnome-extensions disable "$UUID" 2>/dev/null || true
sleep 2

echo "[3/6] Creating safety backup of current broken version..."

SAFETY="$EXT/backup-before-restore-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$SAFETY"

cp -f "$EXT/extension.js" \
    "$SAFETY/extension.js" 2>/dev/null || true

cp -f "$EXT/niveth-audio-meter.py" \
    "$SAFETY/niveth-audio-meter.py" 2>/dev/null || true

echo "[PASS] Safety backup:"
echo "  $SAFETY"
echo

echo "[4/6] Restoring previous extension.js..."

if [ ! -f "$BACKUP/extension.js" ]; then
    echo "[FAIL] Backup extension.js missing."
    exit 1
fi

cp -f \
    "$BACKUP/extension.js" \
    "$EXT/extension.js"

echo "[PASS] extension.js restored."

if [ -f "$BACKUP/niveth-audio-meter.py" ]; then
    cp -f \
        "$BACKUP/niveth-audio-meter.py" \
        "$EXT/niveth-audio-meter.py"

    chmod +x "$EXT/niveth-audio-meter.py"

    echo "[PASS] niveth-audio-meter.py restored."
fi

echo

echo "[5/6] Re-syncing restored version to Niveth rootfs..."

ROOTFS="$HOME/Niveth/build/rootfs"
ROOTFS_EXT="$ROOTFS/usr/share/gnome-shell/extensions/$UUID"

if [ -d "$ROOTFS_EXT" ]; then

    cp -f \
        "$EXT/extension.js" \
        "$ROOTFS_EXT/extension.js"

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
    echo "       Live extension restored successfully."
fi

echo

echo "[6/6] Re-enabling extension..."

gnome-extensions enable "$UUID" 2>/dev/null || true

sleep 4

echo
echo "============================================================"
echo " RESULT"
echo "============================================================"
echo

gnome-extensions info "$UUID" 2>/dev/null || true

echo
echo "Restored from:"
echo "  $BACKUP"

echo
echo "Safety backup:"
echo "  $SAFETY"

echo
echo "============================================================"
echo " RESTORE COMPLETE"
echo "============================================================"
echo
