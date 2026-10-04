#!/usr/bin/env bash

set -u

UUID="niveth-system-monitor@nivethos"

EXT="$HOME/.local/share/gnome-shell/extensions/$UUID"

ROOTFS="$HOME/Niveth/build/rootfs"
ROOTFS_EXT="$ROOTFS/usr/share/gnome-shell/extensions/$UUID"

BACKUP="$EXT/backup-visible-v7-20260926-003554"

echo
echo "============================================================"
echo " NIVETH SYSTEM MONITOR — RESTORE V7"
echo "============================================================"
echo

if [ ! -d "$EXT" ]; then
    echo "[FAIL] Extension directory not found:"
    echo "  $EXT"
    exit 1
fi

if [ ! -d "$BACKUP" ]; then
    echo "[FAIL] V7 backup not found:"
    echo "  $BACKUP"
    exit 1
fi

if [ ! -f "$BACKUP/extension.js" ]; then
    echo "[FAIL] V7 extension.js not found."
    exit 1
fi

echo "[1/7] Creating safety backup..."

SAFETY="$EXT/backup-before-v7-restore-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$SAFETY"

for file in \
    extension.js \
    stylesheet.css \
    metadata.json \
    niveth-audio-meter.py
do
    if [ -f "$EXT/$file" ]; then
        cp -f \
            "$EXT/$file" \
            "$SAFETY/$file"
    fi
done

echo "[PASS] Safety backup:"
echo "  $SAFETY"
echo

echo "[2/7] Disabling current System Monitor..."

gnome-extensions disable "$UUID" 2>/dev/null || true
sleep 2

echo "[3/7] Restoring V7..."

for file in \
    extension.js \
    stylesheet.css \
    metadata.json \
    niveth-audio-meter.py
do
    if [ -f "$BACKUP/$file" ]; then
        cp -f \
            "$BACKUP/$file" \
            "$EXT/$file"
    fi
done

if [ -f "$EXT/niveth-audio-meter.py" ]; then
    chmod +x \
        "$EXT/niveth-audio-meter.py"
fi

echo "[PASS] V7 restored."
echo

echo "[4/7] Synchronizing V7 to Niveth rootfs..."

if [ -d "$ROOTFS_EXT" ]; then

    sudo cp -f \
        "$EXT/extension.js" \
        "$ROOTFS_EXT/extension.js"

    if [ -f "$EXT/stylesheet.css" ]; then
        sudo cp -f \
            "$EXT/stylesheet.css" \
            "$ROOTFS_EXT/stylesheet.css"
    fi

    if [ -f "$EXT/metadata.json" ]; then
        sudo cp -f \
            "$EXT/metadata.json" \
            "$ROOTFS_EXT/metadata.json"
    fi

    if [ -f "$EXT/niveth-audio-meter.py" ]; then
        sudo cp -f \
            "$EXT/niveth-audio-meter.py" \
            "$ROOTFS_EXT/niveth-audio-meter.py"

        sudo chmod +x \
            "$ROOTFS_EXT/niveth-audio-meter.py"
    fi

    echo "[PASS] Rootfs synchronized."

else

    echo "[INFO] Rootfs extension directory not found."
    echo "[INFO] Live version restored only."

fi

echo
echo "[5/7] Enabling V7..."

gnome-extensions enable "$UUID" 2>/dev/null || true

sleep 5

echo
echo "[6/7] Final status..."

gnome-extensions info "$UUID" 2>&1 || true

echo
echo "[7/7] Recent System Monitor errors..."

journalctl \
    --user \
    -b \
    --no-pager \
    -o cat 2>/dev/null |
grep -Ei \
    "niveth-system-monitor|NIVETH AUDIO|TypeError|ReferenceError|SyntaxError" |
tail -30 || true

echo
echo "============================================================"
echo " V7 RESTORE COMPLETE"
echo "============================================================"
echo
echo "Restored from:"
echo "  $BACKUP"
echo
echo "Safety backup:"
echo "  $SAFETY"
echo
