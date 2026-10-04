#!/usr/bin/env bash

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ROOTFS="$PROJECT_ROOT/build/rootfs"

CLEANER_SOURCE="$PROJECT_ROOT/scripts/niveth-cleaner-helper"
POWER_SOURCE="$PROJECT_ROOT/scripts/niveth-power-action"
DIALOG_SOURCE="$PROJECT_ROOT/scripts/niveth-power-dialog.py"

CLEANER_TARGET="$ROOTFS/usr/local/bin/niveth-cleaner-helper"
POWER_TARGET="$ROOTFS/usr/local/bin/niveth-power-action"
DIALOG_TARGET="$ROOTFS/usr/local/bin/niveth-power-dialog.py"

EXT="$ROOTFS/usr/share/gnome-shell/extensions/niveth-ui-test@nivethos/extension.js"

STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP_DIR="$PROJECT_ROOT/integration-backups/niveth-cleaner-power-$STAMP"

echo "============================================================"
echo " Niveth Cleaner + Power Integration"
echo "============================================================"
echo

if [ ! -d "$ROOTFS" ]; then
    echo "[FAIL] Rootfs not found:"
    echo "       $ROOTFS"
    exit 1
fi

if [ ! -f "$CLEANER_SOURCE" ]; then
    echo "[FAIL] Cleaner source not found:"
    echo "       $CLEANER_SOURCE"
    exit 1
fi

if [ ! -f "$POWER_SOURCE" ]; then
    echo "[FAIL] Power action source not found:"
    echo "       $POWER_SOURCE"
    exit 1
fi
if [ ! -f "$DIALOG_SOURCE" ]; then
    echo "[FAIL] Power dialog source not found:"
    echo "       $DIALOG_SOURCE"
    exit 1
fi

if [ ! -f "$EXT" ]; then
    echo "[FAIL] Niveth UI Test extension not found:"
    echo "       $EXT"
    exit 1
fi

if ! grep -q "power-action --restart" "$EXT" &&
   ! grep -q "gnome-session-quit --reboot" "$EXT"; then
    echo "[FAIL] Restart action was not recognized."
    exit 1
fi

if ! grep -q "power-action --shutdown" "$EXT" &&
   ! grep -q "gnome-session-quit --power-off" "$EXT"; then
    echo "[FAIL] Power Off action was not recognized."
    exit 1
fi

mkdir -p "$BACKUP_DIR"

echo "[1/4] Creating backup..."

sudo cp -a \
    "$EXT" \
    "$BACKUP_DIR/extension.js"

echo "[PASS] Backup:"
echo "       $BACKUP_DIR"
echo

echo "[2/4] Installing Cleaner + Power Action..."

sudo install -Dm0755 \
    "$CLEANER_SOURCE" \
    "$CLEANER_TARGET"

sudo install -Dm0755 \
    "$POWER_SOURCE" \
    "$POWER_TARGET"

sudo install -Dm0755 \
    "$DIALOG_SOURCE" \
    "$DIALOG_TARGET"

echo "[PASS] $CLEANER_TARGET"
echo "[PASS] $POWER_TARGET"
echo "[PASS] $DIALOG_TARGET"
echo

echo "[3/4] Verifying notification dependency..."

if [ ! -x "$ROOTFS/usr/bin/notify-send" ]; then
    echo "[FAIL] notify-send is missing from rootfs."
    exit 1
fi

echo "[PASS] notify-send"

if [ ! -x "$DIALOG_TARGET" ]; then
    echo "[FAIL] Niveth GTK power dialog is not executable."
    exit 1
fi

echo "[PASS] Niveth GTK power dialog"
echo

echo "[4/4] Verifying Power Menu integration..."

sudo grep -q \
    "/usr/local/bin/niveth-power-action --restart" \
    "$EXT"

sudo grep -q \
    "/usr/local/bin/niveth-power-action --shutdown" \
    "$EXT"

if sudo grep -q \
    "gnome-session-quit --reboot" \
    "$EXT"; then
    echo "[FAIL] Old Restart command still exists."
    exit 1
fi

if sudo grep -q \
    "gnome-session-quit --power-off" \
    "$EXT"; then
    echo "[FAIL] Old Power Off command still exists."
    exit 1
fi

echo "[PASS] Restart -> Niveth Power Action"
echo "[PASS] Power Off -> Niveth Power Action"
echo "[PASS] No old direct power commands"
echo

echo "============================================================"
echo " Niveth Cleaner + Power Integration READY"
echo "============================================================"
echo
echo "Installed:"
echo "  $CLEANER_TARGET"
echo "  $POWER_TARGET"
echo "  $DIALOG_TARGET"
echo
echo "Backup:"
echo "  $BACKUP_DIR"
