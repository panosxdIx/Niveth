#!/usr/bin/env bash

set -euo pipefail

HOST="$(find /usr/share/gnome-shell/extensions/ding@rastersoft.com \
    -type f -name 'desktopManager.js' 2>/dev/null | head -1)"

ROOTFS="$HOME/Niveth/build/rootfs"
ROOT="$(find "$ROOTFS/usr/share/gnome-shell/extensions/ding@rastersoft.com" \
    -type f -name 'desktopManager.js' 2>/dev/null | head -1)"

echo
echo "=============================================="
echo " NIVETH DING WALLPAPER ROOTFS CHECK"
echo "=============================================="
echo

if [ -z "$HOST" ]; then
    echo "[FAIL] Host DING desktopManager.js not found"
    exit 1
fi

if [ -z "$ROOT" ]; then
    echo "[FAIL] Rootfs DING desktopManager.js not found"
    exit 1
fi

echo "[1/4] Host:"
echo "  $HOST"

echo
echo "[2/4] Rootfs:"
echo "  $ROOT"

echo
echo "[3/4] Checking Change Wallpaper"

sudo grep -q 'Change Wallpaper' "$HOST"
sudo grep -q 'Change Wallpaper' "$ROOT"

if sudo grep -q 'Change Background' "$ROOT"; then
    echo "[FAIL] Rootfs still contains Change Background"
    exit 1
fi

echo "[PASS] Rootfs contains Change Wallpaper"
echo "[PASS] Rootfs has no Change Background"

echo
echo "[4/4] SHA256"

HOST_HASH="$(sudo sha256sum "$HOST" | awk '{print $1}')"
ROOT_HASH="$(sudo sha256sum "$ROOT" | awk '{print $1}')"

echo "HOST   : $HOST_HASH"
echo "ROOTFS : $ROOT_HASH"

if [ "$HOST_HASH" != "$ROOT_HASH" ]; then
    echo "[FAIL] Host and rootfs are different"
    exit 1
fi

echo
echo "=============================================="
echo " PASS — CHANGE WALLPAPER IS IN ROOTFS"
echo "=============================================="
echo
