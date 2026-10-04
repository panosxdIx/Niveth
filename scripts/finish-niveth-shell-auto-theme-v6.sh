#!/usr/bin/env bash

set -euo pipefail

PROJECT_ROOT="$HOME/Niveth"
ROOTFS="$PROJECT_ROOT/build/rootfs"

HOST_EXT="$HOME/.local/share/gnome-shell/extensions"
ROOTFS_EXT="$ROOTFS/usr/share/gnome-shell/extensions"

DOCK="niveth-dock@nivethos"
UI="niveth-ui-test@nivethos"

DOCK_HOST="$HOST_EXT/$DOCK/extension.js"
UI_HOST="$HOST_EXT/$UI/extension.js"

DOCK_ROOT="$ROOTFS_EXT/$DOCK/extension.js"
UI_ROOT="$ROOTFS_EXT/$UI/extension.js"

echo "=================================================="
echo " Niveth Shell Auto Theme v6 - Finish"
echo "=================================================="
echo

if [ ! -f "$DOCK_HOST" ]; then
    echo "ERROR: Dock source not found:"
    echo "  $DOCK_HOST"
    exit 1
fi

if [ ! -f "$UI_HOST" ]; then
    echo "ERROR: UI Test source not found:"
    echo "  $UI_HOST"
    exit 1
fi

if [ ! -d "$ROOTFS" ]; then
    echo "ERROR: Rootfs not found:"
    echo "  $ROOTFS"
    exit 1
fi

echo "=== 1. Verify patched HOST files ==="

echo
echo "--- Dock ---"
grep -nE \
    "nivethTheme|changed::color-scheme|_updateTheme|color-scheme|disconnect" \
    "$DOCK_HOST"

echo
echo "--- UI Test / Top Bar ---"
grep -nE \
    "nivethTheme|changed::color-scheme|_updateTheme|color-scheme|disconnect" \
    "$UI_HOST"

echo
echo "=== 2. Verify expected theme code exists ==="

grep -q "changed::color-scheme" "$DOCK_HOST"
grep -q "_updateTheme()" "$DOCK_HOST"
grep -q "get_string(" "$DOCK_HOST"
grep -q "color-scheme" "$DOCK_HOST"

grep -q "changed::color-scheme" "$UI_HOST"
grep -q "_updateTheme()" "$UI_HOST"
grep -q "get_string(" "$UI_HOST"
grep -q "color-scheme" "$UI_HOST"

echo "Theme code verification: OK"

echo
echo "=== 3. Synchronize HOST -> ROOTFS ==="

sudo mkdir -p \
    "$ROOTFS_EXT/$DOCK" \
    "$ROOTFS_EXT/$UI"

sudo cp -f \
    "$DOCK_HOST" \
    "$DOCK_ROOT"

sudo cp -f \
    "$UI_HOST" \
    "$UI_ROOT"

sudo chown root:root \
    "$DOCK_ROOT" \
    "$UI_ROOT"

sudo chmod 644 \
    "$DOCK_ROOT" \
    "$UI_ROOT"

echo "Rootfs synchronized."

echo
echo "=== 4. Compare HOST and ROOTFS ==="

sudo cmp -s \
    "$DOCK_HOST" \
    "$DOCK_ROOT"

sudo cmp -s \
    "$UI_HOST" \
    "$UI_ROOT"

echo "HOST <-> ROOTFS: identical"

echo
echo "=== 5. Restart extensions ==="

gnome-extensions disable "$DOCK" 2>/dev/null || true
gnome-extensions disable "$UI" 2>/dev/null || true

sleep 2

gnome-extensions enable "$DOCK"
gnome-extensions enable "$UI"

sleep 4

echo
echo "=== 6. Extension status ==="

echo
echo "Dock:"
gnome-extensions info "$DOCK" 2>/dev/null | \
    grep -E 'State|Name' || true

echo
echo "UI Test / Top Bar:"
gnome-extensions info "$UI" 2>/dev/null | \
    grep -E 'State|Name' || true

echo
echo "=== 7. GNOME color scheme ==="

gsettings get \
    org.gnome.desktop.interface \
    color-scheme

echo
echo "=================================================="
echo " FINISHED"
echo "=================================================="
