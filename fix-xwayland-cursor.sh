#!/usr/bin/env bash

set -euo pipefail

THEME="retrosmart-xcursor-mac-ish-gruvbox"
SIZE="32"

DEFAULT_DIR="$HOME/.icons/default"
DEFAULT_FILE="$DEFAULT_DIR/index.theme"

BACKUP_DIR="$HOME/Niveth/backup-xwayland-cursor-$(date +%Y%m%d-%H%M%S)"

echo
echo "============================================================"
echo "       NIVETH — XWAYLAND CURSOR FIX"
echo "============================================================"
echo
echo "Cursor theme:"
echo "  $THEME"
echo
echo "Cursor size:"
echo "  $SIZE"
echo

echo "[1/7] Checking cursor theme..."

THEME_DIR="$HOME/.local/share/icons/$THEME"

if [ ! -d "$THEME_DIR/cursors" ]; then
    echo "[FAIL] Cursor theme not found:"
    echo "  $THEME_DIR/cursors"
    exit 1
fi

echo "[PASS] Cursor theme exists"
echo

echo "[2/7] Creating backup..."

mkdir -p "$BACKUP_DIR"

if [ -f "$DEFAULT_FILE" ]; then
    cp -a \
        "$DEFAULT_FILE" \
        "$BACKUP_DIR/index.theme.before"
    echo "[PASS] Existing default cursor configuration backed up"
else
    echo "[INFO] No existing user default cursor configuration"
fi

echo
echo "[3/7] Creating Xcursor default theme..."

mkdir -p "$DEFAULT_DIR"

cat > "$DEFAULT_FILE" <<EOF
[Icon Theme]
Inherits=$THEME
EOF

echo "[PASS] $DEFAULT_FILE"
echo

echo "[4/7] Verifying..."

cat "$DEFAULT_FILE"

echo
echo "[5/7] Checking available cursor themes..."

find \
    "$HOME/.local/share/icons" \
    "$HOME/.icons" \
    /usr/share/icons \
    -maxdepth 2 \
    -type d \
    -name cursors \
    2>/dev/null |
grep -F "$THEME" ||
true

echo
echo "[6/7] Current GNOME cursor settings..."

gsettings get \
    org.gnome.desktop.interface \
    cursor-theme

gsettings get \
    org.gnome.desktop.interface \
    cursor-size

echo
echo "[7/7] Done."
echo
echo "============================================================"
echo " TEST"
echo "============================================================"
echo
echo "1. Completely exit MEGAsync."
echo "2. Start MEGAsync again."
echo "3. Move the cursor over MEGAsync."
echo "4. Move it to another GNOME application."
echo
echo "The GNOME cursor theme itself was NOT changed."
echo
echo "Backup:"
echo "  $BACKUP_DIR"
echo
echo "============================================================"
