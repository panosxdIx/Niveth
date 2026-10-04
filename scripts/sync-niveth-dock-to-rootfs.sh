#!/usr/bin/env bash

set -euo pipefail

SOURCE_EXT="$HOME/.local/share/gnome-shell/extensions/niveth-dock@nivethos"

ROOTFS="$HOME/Niveth/build/rootfs"
ROOTFS_EXT="$ROOTFS/usr/share/gnome-shell/extensions/niveth-dock@nivethos"

SOURCE_JS="$SOURCE_EXT/extension.js"
SOURCE_CSS="$SOURCE_EXT/stylesheet.css"

ROOTFS_JS="$ROOTFS_EXT/extension.js"
ROOTFS_CSS="$ROOTFS_EXT/stylesheet.css"

STAMP="$(date +%Y%m%d-%H%M%S)"

echo
echo "=================================================="
echo " NIVETH DOCK — SOURCE → ROOTFS SYNC"
echo "=================================================="
echo

# ---------------------------------------------------------
# CHECK SOURCE
# ---------------------------------------------------------

echo "[1/7] Checking source files"

if [ ! -f "$SOURCE_JS" ]; then
    echo "[FAIL] Source extension.js not found:"
    echo "$SOURCE_JS"
    exit 1
fi

if [ ! -f "$SOURCE_CSS" ]; then
    echo "[FAIL] Source stylesheet.css not found:"
    echo "$SOURCE_CSS"
    exit 1
fi

echo "[PASS] Source extension.js"
echo "[PASS] Source stylesheet.css"


# ---------------------------------------------------------
# CHECK ROOTFS
# ---------------------------------------------------------

echo
echo "[2/7] Checking rootfs"

if [ ! -d "$ROOTFS" ]; then
    echo "[FAIL] Rootfs not found:"
    echo "$ROOTFS"
    exit 1
fi

sudo mkdir -p "$ROOTFS_EXT"

echo "[PASS] Rootfs exists"
echo "[PASS] Rootfs Dock directory exists"


# ---------------------------------------------------------
# BACKUPS
# ---------------------------------------------------------

echo
echo "[3/7] Creating rootfs backups"

ROOTFS_JS_BACKUP="$ROOTFS_JS.backup-before-final-sync-$STAMP"
ROOTFS_CSS_BACKUP="$ROOTFS_CSS.backup-before-final-sync-$STAMP"

if [ -f "$ROOTFS_JS" ]; then
    sudo cp "$ROOTFS_JS" "$ROOTFS_JS_BACKUP"
    echo "[PASS] Rootfs JS backup:"
    echo "       $ROOTFS_JS_BACKUP"
else
    echo "[INFO] No previous rootfs extension.js"
fi

if [ -f "$ROOTFS_CSS" ]; then
    sudo cp "$ROOTFS_CSS" "$ROOTFS_CSS_BACKUP"
    echo "[PASS] Rootfs CSS backup:"
    echo "       $ROOTFS_CSS_BACKUP"
else
    echo "[INFO] No previous rootfs stylesheet.css"
fi


# ---------------------------------------------------------
# SYNC
# ---------------------------------------------------------

echo
echo "[4/7] Copying current Dock into rootfs"

sudo install -m 0644 "$SOURCE_JS" "$ROOTFS_JS"
sudo install -m 0644 "$SOURCE_CSS" "$ROOTFS_CSS"

echo "[PASS] extension.js copied"
echo "[PASS] stylesheet.css copied"


# ---------------------------------------------------------
# HASH COMPARISON
# ---------------------------------------------------------

echo
echo "[5/7] Comparing SHA256"

SOURCE_JS_HASH="$(sha256sum "$SOURCE_JS" | awk '{print $1}')"
ROOTFS_JS_HASH="$(sudo sha256sum "$ROOTFS_JS" | awk '{print $1}')"

SOURCE_CSS_HASH="$(sha256sum "$SOURCE_CSS" | awk '{print $1}')"
ROOTFS_CSS_HASH="$(sudo sha256sum "$ROOTFS_CSS" | awk '{print $1}')"

echo
echo "extension.js"
echo "  SOURCE : $SOURCE_JS_HASH"
echo "  ROOTFS : $ROOTFS_JS_HASH"

if [ "$SOURCE_JS_HASH" != "$ROOTFS_JS_HASH" ]; then
    echo "[FAIL] extension.js differs"
    exit 1
fi

echo "[PASS] extension.js identical"

echo
echo "stylesheet.css"
echo "  SOURCE : $SOURCE_CSS_HASH"
echo "  ROOTFS : $ROOTFS_CSS_HASH"

if [ "$SOURCE_CSS_HASH" != "$ROOTFS_CSS_HASH" ]; then
    echo "[FAIL] stylesheet.css differs"
    exit 1
fi

echo "[PASS] stylesheet.css identical"


# ---------------------------------------------------------
# VERIFY IMPORTANT VAPORWAVE CONTENT
# ---------------------------------------------------------

echo
echo "[6/7] Verifying important Niveth Dock content"

sudo grep -q "background-color: rgba(38, 33, 91, 0.84)" "$ROOTFS_JS"
sudo grep -q "background-color: rgba(65, 49, 132, 0.94)" "$ROOTFS_JS"
sudo grep -q "rgba(105, 216, 255, 0.74)" "$ROOTFS_JS"
sudo grep -q "rgba(255, 114, 210, 0.98)" "$ROOTFS_CSS"

echo "[PASS] Dark indigo"
echo "[PASS] Light indigo"
echo "[PASS] Cyan border"
echo "[PASS] Pink indicator"


# ---------------------------------------------------------
# FINAL
# ---------------------------------------------------------

echo
echo "[7/7] Final paths"

echo
echo "SOURCE:"
echo "  $SOURCE_JS"
echo "  $SOURCE_CSS"

echo
echo "ROOTFS:"
echo "  $ROOTFS_JS"
echo "  $ROOTFS_CSS"

echo
echo "=================================================="
echo " ROOTFS SYNC COMPLETE"
echo "=================================================="
echo
echo "Το rootfs έχει πλέον ακριβώς τα ίδια"
echo "extension.js + stylesheet.css με το live Dock."
echo
