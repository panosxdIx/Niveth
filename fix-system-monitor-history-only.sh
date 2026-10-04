#!/usr/bin/env bash

set -u

UUID="niveth-system-monitor@nivethos"
EXT="$HOME/.local/share/gnome-shell/extensions/$UUID"
ROOTFS="$HOME/Niveth/build/rootfs"
ROOTFS_EXT="$ROOTFS/usr/share/gnome-shell/extensions/$UUID"

echo
echo "============================================================"
echo " NIVETH SYSTEM MONITOR — HISTORY ONLY FIX"
echo "============================================================"
echo

if [ ! -f "$EXT/extension.js" ]; then
    echo "[FAIL] extension.js not found:"
    echo "  $EXT/extension.js"
    exit 1
fi

echo "[1/7] Creating backup..."

BACKUP="$EXT/backup-before-history-fix-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$BACKUP"

cp -f "$EXT/extension.js" "$BACKUP/extension.js"

if [ -f "$EXT/niveth-audio-meter.py" ]; then
    cp -f "$EXT/niveth-audio-meter.py" \
        "$BACKUP/niveth-audio-meter.py"
fi

echo "[PASS] Backup:"
echo "  $BACKUP"
echo

echo "[2/7] Disabling extension..."

gnome-extensions disable "$UUID" 2>/dev/null || true
sleep 2

echo "[3/7] Checking current audio history initialization..."

if grep -q "this\._audioHistory = new Array" "$EXT/extension.js"; then
    echo "[INFO] _audioHistory already exists."
else
    echo "[INFO] _audioHistory is missing."
    echo

    echo "[4/7] Adding _audioHistory initialization..."

    python3 - "$EXT/extension.js" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text()

if "this._audioHistory = new Array" in text:
    print("[INFO] Initialization already present.")
    raise SystemExit(0)

needle = "        this._audioTarget = 0;\n"

if needle not in text:
    print("[FAIL] Could not find:")
    print(repr(needle))
    raise SystemExit(1)

replacement = (
    "        this._audioTarget = 0;\n"
    "        this._audioHistory = new Array(WAVE_COUNT).fill(0);\n"
)

text = text.replace(needle, replacement, 1)
path.write_text(text)

print("[PASS] _audioHistory initialized.")
PY

    FIX_RESULT=$?

    if [ "$FIX_RESULT" -ne 0 ]; then
        echo
        echo "[FAIL] History fix failed."
        echo "Current file was NOT intentionally replaced."
        echo
        exit "$FIX_RESULT"
    fi
fi

echo
echo "[5/7] Verifying the fix..."

grep -n -A4 -B4 \
    "_audioHistory = new Array" \
    "$EXT/extension.js" || true

if grep -q "this\._audioHistory = new Array" "$EXT/extension.js"; then
    echo "[PASS] _audioHistory initialization found."
else
    echo "[FAIL] _audioHistory initialization is still missing."
    exit 1
fi

echo
echo "[6/7] Syncing live version to Niveth rootfs..."

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
    echo "[INFO] Live extension fixed."
fi

echo
echo "[7/7] Enabling extension..."

gnome-extensions enable "$UUID" 2>/dev/null || true

sleep 5

echo
echo "============================================================"
echo " FINAL STATUS"
echo "============================================================"
echo

gnome-extensions info "$UUID" 2>&1 || true

echo
echo "============================================================"
echo " RECENT NIVETH ERRORS"
echo "============================================================"
echo

journalctl \
    --user \
    -b \
    --no-pager \
    2>/dev/null |
grep -Ei \
    "niveth-system-monitor|NIVETH AUDIO|_audioHistory|TypeError|JavaScript|Gjs" |
tail -40 || true

echo
echo "============================================================"
echo " HISTORY FIX COMPLETE"
echo "============================================================"
echo
echo "Backup:"
echo "  $BACKUP"
echo
