#!/usr/bin/env bash
set -euo pipefail

EXT_ID="niveth-system-monitor@nivethos"

LIVE_DIR="$HOME/.local/share/gnome-shell/extensions/$EXT_ID"
ROOTFS_DIR="$HOME/Niveth/build/rootfs/usr/share/gnome-shell/extensions/$EXT_ID"

echo "=============================================="
echo " NIVETH SYSTEM MONITOR - MAIN IMPORT FIX"
echo "=============================================="

if [ ! -f "$LIVE_DIR/extension.js" ]; then
    echo "[ERROR] extension.js δεν βρέθηκε:"
    echo "$LIVE_DIR/extension.js"
    exit 1
fi

echo
echo "[1/7] Disabling extension..."

gnome-extensions disable "$EXT_ID" 2>/dev/null || true
sleep 2

echo "[PASS] Disabled"

echo
echo "[2/7] Backing up current extension.js..."

BACKUP="$LIVE_DIR/extension-before-main-fix-$(date +%Y%m%d-%H%M%S).js"

cp "$LIVE_DIR/extension.js" "$BACKUP"

echo "[PASS] Backup:"
echo "$BACKUP"

echo
echo "[3/7] Fixing Main import..."

python3 - "$LIVE_DIR/extension.js" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text()

old = "import Main from 'resource:///org/gnome/shell/ui/main.js';"
new = "import * as Main from 'resource:///org/gnome/shell/ui/main.js';"

if old in text:
    text = text.replace(old, new, 1)
    path.write_text(text)
    print("[PASS] Main import fixed")
elif new in text:
    print("[PASS] Main import was already fixed")
else:
    print("[ERROR] Expected Main import was not found")
    sys.exit(1)
PY

echo
echo "[4/7] Verifying import..."

grep -n "main.js" "$LIVE_DIR/extension.js"

echo
echo "[5/7] JavaScript syntax check..."

if command -v node >/dev/null 2>&1; then
    node --check "$LIVE_DIR/extension.js"
    echo "[PASS] JavaScript syntax"
else
    echo "[WARN] node not installed; skipping node syntax check"
fi

echo
echo "[6/7] Syncing corrected extension to Niveth rootfs..."

sudo mkdir -p "$ROOTFS_DIR"

sudo install -Dm644 \
    "$LIVE_DIR/extension.js" \
    "$ROOTFS_DIR/extension.js"

sudo install -Dm644 \
    "$LIVE_DIR/stylesheet.css" \
    "$ROOTFS_DIR/stylesheet.css"

sudo install -Dm644 \
    "$LIVE_DIR/metadata.json" \
    "$ROOTFS_DIR/metadata.json"

if [ -f "$LIVE_DIR/niveth-audio-meter.py" ]; then
    sudo install -Dm755 \
        "$LIVE_DIR/niveth-audio-meter.py" \
        "$HOME/Niveth/build/rootfs/usr/share/gnome-shell/extensions/$EXT_ID/niveth-audio-meter.py"
fi

echo "[PASS] Rootfs synchronized"

echo
echo "=== HASH CHECK ==="

LIVE_HASH="$(sha256sum "$LIVE_DIR/extension.js" | awk '{print $1}')"
ROOT_HASH="$(sudo sha256sum "$ROOTFS_DIR/extension.js" | awk '{print $1}')"

echo "LIVE : $LIVE_HASH"
echo "ROOT : $ROOT_HASH"

if [ "$LIVE_HASH" != "$ROOT_HASH" ]; then
    echo "[ERROR] Live/rootfs hash mismatch"
    exit 1
fi

echo "[PASS] Hashes match"

echo
echo "[7/7] Enabling extension..."

gnome-extensions enable "$EXT_ID"

sleep 5

echo
echo "=============================================="
echo " FINAL STATUS"
echo "=============================================="

gnome-extensions info "$EXT_ID"

echo
echo "=============================================="
echo " RECENT SYSTEM MONITOR ERRORS"
echo "=============================================="

journalctl --user -b \
    --no-pager \
    --since "30 seconds ago" 2>/dev/null |
grep -Ei \
'niveth-system-monitor@nivethos|SyntaxError|TypeError|ReferenceError|ImportError|JS ERROR|Gjs-' |
tail -50 || true

echo
echo "=============================================="
echo " DONE"
echo "=============================================="
