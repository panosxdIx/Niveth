#!/usr/bin/env bash

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ROOTFS="$PROJECT_ROOT/build/rootfs"
MANIFEST="$PROJECT_ROOT/desktop/niveth-components.txt"

DCONF_DIR="$PROJECT_ROOT/desktop/defaults/dconf"
DCONF_FILE="$DCONF_DIR/90-niveth-wellbeing"

ROOTFS_DCONF_DIR="$ROOTFS/etc/dconf/db/local.d"
ROOTFS_DCONF_FILE="$ROOTFS_DCONF_DIR/90-niveth-wellbeing"

echo "=== Niveth Movement Break integration ==="
echo

if [ ! -d "$ROOTFS" ]; then
    echo "[ERROR] rootfs does not exist:"
    echo "        $ROOTFS"
    exit 1
fi

mkdir -p "$DCONF_DIR"

cat > "$DCONF_FILE" <<'DCONF'
[org/gnome/desktop/break-reminders]
selected-breaks=['movement']

[org/gnome/desktop/break-reminders/movement]
interval-seconds=uint32 3000
duration-seconds=uint32 480
notify=true
fade-screen=true
play-sound=true
DCONF

echo "[PASS] Source dconf created:"
echo "       $DCONF_FILE"

sudo mkdir -p "$ROOTFS_DCONF_DIR"
sudo cp "$DCONF_FILE" "$ROOTFS_DCONF_FILE"
sudo chown root:root "$ROOTFS_DCONF_FILE"
sudo chmod 0644 "$ROOTFS_DCONF_FILE"

echo "[PASS] Rootfs dconf installed:"
echo "       $ROOTFS_DCONF_FILE"

MANIFEST_LINE="COPY_FILE $DCONF_FILE /etc/dconf/db/local.d/90-niveth-wellbeing"

if ! grep -Fxq "$MANIFEST_LINE" "$MANIFEST"; then
    printf '%s\n' "$MANIFEST_LINE" >> "$MANIFEST"
    echo "[PASS] Manifest updated"
else
    echo "[PASS] Manifest entry already exists"
fi

echo
if command -v dconf >/dev/null 2>&1; then
    echo "[INFO] Updating rootfs dconf database..."
    sudo dconf update "$ROOTFS/etc/dconf/db"
    echo "[PASS] dconf database updated"
else
    echo "[WARN] Host dconf command not found."
    echo "       The build process will generate the dconf database later."
fi

echo
echo "=== Verification ==="

echo
echo "--- Source ---"
cat "$DCONF_FILE"

echo
echo "--- Rootfs ---"
sudo cat "$ROOTFS_DCONF_FILE"

echo
echo "--- Manifest ---"
grep -nF "90-niveth-wellbeing" "$MANIFEST" || true

echo
echo "--- Permissions ---"
sudo ls -l "$ROOTFS_DCONF_FILE"

echo
echo "[PASS] Movement Break integration installed."
echo
echo "Niveth default:"
echo "  Movement reminders : ON"
echo "  Interval            : 50 minutes"
echo "  Break duration      : 8 minutes"
echo "  Notification        : ON"
echo "  Fade screen         : ON"
echo "  End sound           : ON"
