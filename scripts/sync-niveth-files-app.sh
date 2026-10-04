#!/usr/bin/env bash

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

SOURCE_DIR="$HOME/Niveth-Files"

HOST_DIR="/usr/lib/niveth/apps/niveth-files"

ROOTFS="$PROJECT_ROOT/build/rootfs"
ROOTFS_DIR="$ROOTFS/usr/lib/niveth/apps/niveth-files"

HOST_LAUNCHER="/usr/local/bin/niveth-files"
ROOTFS_LAUNCHER="$ROOTFS/usr/local/bin/niveth-files"

echo "============================================================"
echo "             NIVETH FILES APP SYNC"
echo "============================================================"
echo

if [ ! -f "$SOURCE_DIR/main.py" ]; then
    echo "[ERROR] Missing:"
    echo "       $SOURCE_DIR/main.py"
    exit 1
fi

if [ ! -f "$SOURCE_DIR/styles.css" ]; then
    echo "[ERROR] Missing:"
    echo "       $SOURCE_DIR/styles.css"
    exit 1
fi

if [ ! -d "$SOURCE_DIR/icons" ]; then
    echo "[ERROR] Missing:"
    echo "       $SOURCE_DIR/icons"
    exit 1
fi

echo "=== SOURCE ==="
echo "[PASS] main.py"
echo "[PASS] styles.css"
echo "[PASS] icons/"

echo
echo "=== HOST APP ==="

sudo mkdir -p "$HOST_DIR"

sudo cp "$SOURCE_DIR/main.py" \
    "$HOST_DIR/main.py"

sudo cp "$SOURCE_DIR/styles.css" \
    "$HOST_DIR/styles.css"

sudo rm -rf "$HOST_DIR/icons"

sudo cp -a "$SOURCE_DIR/icons" \
    "$HOST_DIR/icons"

sudo chown -R root:root "$HOST_DIR"
sudo find "$HOST_DIR" -type d -exec chmod 0755 {} \;
sudo find "$HOST_DIR" -type f -exec chmod 0644 {} \;

echo "[PASS] Host Niveth Files synchronized"

echo
echo "=== HOST LAUNCHER ==="

sudo tee "$HOST_LAUNCHER" >/dev/null <<'LAUNCHER'
#!/bin/sh
exec /usr/bin/python3 /usr/lib/niveth/apps/niveth-files/main.py "$@"
LAUNCHER

sudo chown root:root "$HOST_LAUNCHER"
sudo chmod 0755 "$HOST_LAUNCHER"

echo "[PASS] Host launcher"

echo
echo "=== ROOTFS APP ==="

sudo mkdir -p "$ROOTFS_DIR"

sudo cp "$SOURCE_DIR/main.py" \
    "$ROOTFS_DIR/main.py"

sudo cp "$SOURCE_DIR/styles.css" \
    "$ROOTFS_DIR/styles.css"

sudo rm -rf "$ROOTFS_DIR/icons"

sudo cp -a "$SOURCE_DIR/icons" \
    "$ROOTFS_DIR/icons"

sudo chown -R root:root "$ROOTFS_DIR"
sudo find "$ROOTFS_DIR" -type d -exec chmod 0755 {} \;
sudo find "$ROOTFS_DIR" -type f -exec chmod 0644 {} \;

echo "[PASS] Rootfs Niveth Files synchronized"

echo
echo "=== ROOTFS LAUNCHER ==="

sudo mkdir -p "$(dirname "$ROOTFS_LAUNCHER")"

sudo tee "$ROOTFS_LAUNCHER" >/dev/null <<'LAUNCHER'
#!/bin/sh
exec /usr/bin/python3 /usr/lib/niveth/apps/niveth-files/main.py "$@"
LAUNCHER

sudo chown root:root "$ROOTFS_LAUNCHER"
sudo chmod 0755 "$ROOTFS_LAUNCHER"

echo "[PASS] Rootfs launcher"

echo
echo "=== PYTHON CHECK ==="

python3 -m py_compile \
    "$SOURCE_DIR/main.py"

sudo python3 -m py_compile \
    "$HOST_DIR/main.py"

sudo python3 -m py_compile \
    "$ROOTFS_DIR/main.py"

sudo rm -rf \
    "$HOST_DIR/__pycache__" \
    "$ROOTFS_DIR/__pycache__"

echo "[PASS] Python syntax"

echo
echo "=== ICON CHECK ==="

SOURCE_ICON_COUNT="$(find "$SOURCE_DIR/icons" -type f | wc -l)"
HOST_ICON_COUNT="$(sudo find "$HOST_DIR/icons" -type f | wc -l)"
ROOTFS_ICON_COUNT="$(sudo find "$ROOTFS_DIR/icons" -type f | wc -l)"

echo "Source icons : $SOURCE_ICON_COUNT"
echo "Host icons   : $HOST_ICON_COUNT"
echo "Rootfs icons : $ROOTFS_ICON_COUNT"

if [ "$SOURCE_ICON_COUNT" -gt 0 ] &&
   [ "$HOST_ICON_COUNT" -eq "$SOURCE_ICON_COUNT" ] &&
   [ "$ROOTFS_ICON_COUNT" -eq "$SOURCE_ICON_COUNT" ]; then
    echo "[PASS] All Niveth Files icons synchronized"
else
    echo "[ERROR] Icon counts do not match"
    exit 1
fi

echo
echo "=== IMPORTANT ICONS ==="

for icon in \
    niveth-folder-dark.svg \
    niveth-folder-light.svg
do
    if [ -f "$HOST_DIR/icons/$icon" ]; then
        echo "[PASS] Host $icon"
    else
        echo "[FAIL] Host $icon"
        exit 1
    fi

    if [ -f "$ROOTFS_DIR/icons/$icon" ]; then
        echo "[PASS] Rootfs $icon"
    else
        echo "[FAIL] Rootfs $icon"
        exit 1
    fi
done

echo
echo "=== DESKTOP DATABASE ==="

sudo update-desktop-database \
    /usr/share/applications \
    2>/dev/null || true

update-desktop-database \
    "$HOME/.local/share/applications" \
    2>/dev/null || true

echo "[PASS] Desktop database refreshed"

echo
echo "============================================================"
echo "[DONE] Niveth Files application fully synchronized."
echo "============================================================"
echo
echo "Host:"
echo "  $HOST_DIR"
echo
echo "Rootfs:"
echo "  $ROOTFS_DIR"
echo
echo "Launcher:"
echo "  $HOST_LAUNCHER"
echo "  $ROOTFS_LAUNCHER"
