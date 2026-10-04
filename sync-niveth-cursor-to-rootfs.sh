#!/usr/bin/env bash

set -euo pipefail

THEME_NAME="retrosmart-xcursor-mac-ish-gruvbox"

SOURCE_THEME="$HOME/.local/share/icons/$THEME_NAME"

ROOTFS="$HOME/Niveth/build/rootfs"

ROOTFS_THEME="$ROOTFS/usr/share/icons/$THEME_NAME"
ROOTFS_DEFAULT="$ROOTFS/usr/share/icons/default"

ROOTFS_SKEL_DEFAULT="$ROOTFS/etc/skel/.icons/default"

STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP="$HOME/Niveth/backup-rootfs-cursor-$STAMP"

echo
echo "============================================================"
echo "       NIVETH — SYNC CURSOR THEME TO ROOTFS"
echo "============================================================"
echo
echo "Theme:"
echo "  $THEME_NAME"
echo
echo "Source:"
echo "  $SOURCE_THEME"
echo
echo "Rootfs:"
echo "  $ROOTFS"
echo
echo "============================================================"
echo

# ------------------------------------------------------------
# 1. Verify source
# ------------------------------------------------------------

echo "[1/8] Verifying source cursor theme..."

if [ ! -d "$SOURCE_THEME" ]; then
    echo "[FAIL] Source theme not found:"
    echo "  $SOURCE_THEME"
    exit 1
fi

if [ ! -d "$SOURCE_THEME/cursors" ]; then
    echo "[FAIL] Source cursors directory not found:"
    echo "  $SOURCE_THEME/cursors"
    exit 1
fi

if [ ! -f "$SOURCE_THEME/index.theme" ]; then
    echo "[FAIL] Source index.theme not found."
    exit 1
fi

if [ ! -e "$SOURCE_THEME/cursors/up_arrow" ]; then
    echo "[FAIL] up_arrow alias missing from source."
    exit 1
fi

if [ ! -e "$SOURCE_THEME/cursors/dnd-link" ]; then
    echo "[FAIL] dnd-link alias missing from source."
    exit 1
fi

echo "[PASS] Source theme"
echo "[PASS] cursors directory"
echo "[PASS] index.theme"
echo "[PASS] up_arrow"
echo "[PASS] dnd-link"
echo

# ------------------------------------------------------------
# 2. Verify rootfs
# ------------------------------------------------------------

echo "[2/8] Verifying rootfs..."

if [ ! -d "$ROOTFS" ]; then
    echo "[FAIL] Rootfs not found:"
    echo "  $ROOTFS"
    exit 1
fi

echo "[PASS] Rootfs exists"
echo

# ------------------------------------------------------------
# 3. Create backup
# ------------------------------------------------------------

echo "[3/8] Creating rootfs backup..."

mkdir -p "$BACKUP"

if [ -d "$ROOTFS_THEME" ]; then

    sudo cp -a \
        "$ROOTFS_THEME" \
        "$BACKUP/$THEME_NAME"

    echo "[PASS] Existing system cursor theme backed up"

else

    echo "[INFO] No existing rootfs cursor theme"
fi

if [ -f "$ROOTFS_DEFAULT/index.theme" ]; then

    mkdir -p "$BACKUP/system-default"

    sudo cp -a \
        "$ROOTFS_DEFAULT/index.theme" \
        "$BACKUP/system-default/index.theme"

    echo "[PASS] Existing system default cursor configuration backed up"

else

    echo "[INFO] No existing system default cursor configuration"
fi

if [ -f "$ROOTFS_SKEL_DEFAULT/index.theme" ]; then

    mkdir -p "$BACKUP/skel-default"

    sudo cp -a \
        "$ROOTFS_SKEL_DEFAULT/index.theme" \
        "$BACKUP/skel-default/index.theme"

    echo "[PASS] Existing /etc/skel cursor configuration backed up"

else

    echo "[INFO] No existing /etc/skel cursor configuration"
fi

echo
echo "Backup:"
echo "  $BACKUP"
echo

# ------------------------------------------------------------
# 4. Copy cursor theme
# ------------------------------------------------------------

echo "[4/8] Installing cursor theme into rootfs..."

sudo mkdir -p \
    "$ROOTFS/usr/share/icons"

sudo rm -rf \
    "$ROOTFS_THEME"

sudo cp -a \
    "$SOURCE_THEME" \
    "$ROOTFS_THEME"

echo "[PASS] Theme copied to:"
echo "  $ROOTFS_THEME"
echo

# ------------------------------------------------------------
# 5. Create system-wide Xcursor default
# ------------------------------------------------------------

echo "[5/8] Installing system Xcursor default..."

sudo mkdir -p \
    "$ROOTFS_DEFAULT"

sudo tee \
    "$ROOTFS_DEFAULT/index.theme" \
    >/dev/null <<EOF
[Icon Theme]
Inherits=$THEME_NAME
EOF

echo "[PASS] System default cursor:"
echo "  $ROOTFS_DEFAULT/index.theme"
echo

# ------------------------------------------------------------
# 6. Create /etc/skel default
# ------------------------------------------------------------

echo "[6/8] Installing new-user cursor default..."

sudo mkdir -p \
    "$ROOTFS_SKEL_DEFAULT"

sudo tee \
    "$ROOTFS_SKEL_DEFAULT/index.theme" \
    >/dev/null <<EOF
[Icon Theme]
Inherits=$THEME_NAME
EOF

echo "[PASS] /etc/skel cursor default:"
echo "  $ROOTFS_SKEL_DEFAULT/index.theme"
echo

# ------------------------------------------------------------
# 7. Verify rootfs
# ------------------------------------------------------------

echo "[7/8] Verifying rootfs installation..."

if [ ! -d "$ROOTFS_THEME/cursors" ]; then
    echo "[FAIL] Rootfs cursors directory missing."
    exit 1
fi

if [ ! -e "$ROOTFS_THEME/cursors/up_arrow" ]; then
    echo "[FAIL] Rootfs up_arrow missing."
    exit 1
fi

if [ ! -e "$ROOTFS_THEME/cursors/dnd-link" ]; then
    echo "[FAIL] Rootfs dnd-link missing."
    exit 1
fi

if ! grep -Fxq \
    "[Icon Theme]" \
    "$ROOTFS_DEFAULT/index.theme"
then
    echo "[FAIL] Invalid system default index.theme."
    exit 1
fi

if ! grep -Fxq \
    "Inherits=$THEME_NAME" \
    "$ROOTFS_DEFAULT/index.theme"
then
    echo "[FAIL] System default does not inherit Niveth theme."
    exit 1
fi

if ! grep -Fxq \
    "Inherits=$THEME_NAME" \
    "$ROOTFS_SKEL_DEFAULT/index.theme"
then
    echo "[FAIL] /etc/skel default does not inherit Niveth theme."
    exit 1
fi

echo
echo "[PASS] Rootfs theme"
echo "[PASS] Rootfs up_arrow"
echo "[PASS] Rootfs dnd-link"
echo "[PASS] System default cursor"
echo "[PASS] /etc/skel default cursor"
echo

echo "=== ROOTFS CURSOR ALIASES ==="

printf '%-20s -> ' "up_arrow"
readlink "$ROOTFS_THEME/cursors/up_arrow" 2>/dev/null || true

printf '%-20s -> ' "dnd-link"
readlink "$ROOTFS_THEME/cursors/dnd-link" 2>/dev/null || true

echo

echo "=== SYSTEM DEFAULT ==="
sudo cat \
    "$ROOTFS_DEFAULT/index.theme"

echo

echo "=== SKEL DEFAULT ==="
sudo cat \
    "$ROOTFS_SKEL_DEFAULT/index.theme"

echo

# ------------------------------------------------------------
# 8. Final
# ------------------------------------------------------------

echo "[8/8] Final status..."

echo
echo "============================================================"
echo " CURSOR THEME SYNC COMPLETE"
echo "============================================================"
echo
echo "Installed into Niveth rootfs:"
echo
echo "  /usr/share/icons/$THEME_NAME"
echo "  /usr/share/icons/default/index.theme"
echo "  /etc/skel/.icons/default/index.theme"
echo
echo "Qt/X11 aliases:"
echo
echo "  up_arrow -> up-arrow"
echo "  dnd-link -> alias"
echo
echo "Backup:"
echo "  $BACKUP"
echo
echo "============================================================"
