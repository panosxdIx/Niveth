#!/usr/bin/env bash

set -euo pipefail

PROJECT_ROOT="$HOME/Niveth"
ROOTFS="$PROJECT_ROOT/build/rootfs"

USER_APPS="$HOME/.local/share/applications"
SYSTEM_APPS="/usr/local/share/applications"

echo "=================================================="
echo " Niveth Dock Launcher Fix v2"
echo "=================================================="
echo

if [ ! -d "$ROOTFS" ]; then
    echo "ERROR: Rootfs not found:"
    echo "  $ROOTFS"
    exit 1
fi

echo "=== 1. Removing old user-local launcher conflicts ==="

rm -f \
    "$USER_APPS/com.niveth.Notes.desktop" \
    "$USER_APPS/com.niveth.AppCenter.desktop" \
    "$USER_APPS/org.niveth.Files.desktop"

echo "Removed old user-local desktop overrides."

echo
echo "=== 2. Removing duplicate user-local executable wrappers ==="

rm -f \
    "$HOME/.local/bin/niveth-notes" \
    "$HOME/.local/bin/niveth-app-center" \
    "$HOME/.local/bin/niveth-files"

echo "Removed old user-local executable wrappers."

echo
echo "=== 3. Verifying system launchers ==="

for file in \
    /usr/local/bin/niveth-notes \
    /usr/local/bin/niveth-app-center \
    /usr/local/bin/niveth-files
do
    if [ ! -x "$file" ]; then
        echo "ERROR: Missing or non-executable:"
        echo "  $file"
        exit 1
    fi

    ls -l "$file"
done

echo
echo "=== 4. Verifying system desktop files ==="

for file in \
    "$SYSTEM_APPS/com.niveth.Notes.desktop" \
    "$SYSTEM_APPS/com.niveth.AppCenter.desktop" \
    "$SYSTEM_APPS/org.niveth.Files.desktop"
do
    if [ ! -f "$file" ]; then
        echo "ERROR: Missing:"
        echo "  $file"
        exit 1
    fi

    echo
    echo "--- $file ---"
    grep -E '^(Name|Exec|TryExec|Icon)=' "$file" || true
done

echo
echo "=== 5. Fixing rootfs launcher ownership ==="

sudo chown root:root \
    "$ROOTFS/usr/local/bin/niveth-notes" \
    "$ROOTFS/usr/local/bin/niveth-app-center" \
    "$ROOTFS/usr/local/bin/niveth-files"

sudo chmod 755 \
    "$ROOTFS/usr/local/bin/niveth-notes" \
    "$ROOTFS/usr/local/bin/niveth-app-center" \
    "$ROOTFS/usr/local/bin/niveth-files"

echo
echo "=== 6. Fixing rootfs application ownership ==="

sudo chown -R root:root \
    "$ROOTFS/usr/lib/niveth/apps/niveth-notes" \
    "$ROOTFS/usr/lib/niveth/apps/niveth-app-center" \
    "$ROOTFS/usr/lib/niveth/apps/niveth-files"

echo
echo "=== 7. Removing generated pycache from rootfs ==="

sudo rm -rf \
    "$ROOTFS/usr/lib/niveth/apps/niveth-notes/__pycache__" \
    "$ROOTFS/usr/lib/niveth/apps/niveth-app-center/__pycache__" \
    "$ROOTFS/usr/lib/niveth/apps/niveth-files/__pycache__"

echo
echo "=== 8. Updating desktop databases ==="

update-desktop-database "$SYSTEM_APPS" 2>/dev/null || true

sudo chroot "$ROOTFS" update-desktop-database \
    /usr/local/share/applications 2>/dev/null || true

echo
echo "=== 9. Checking PATH resolution ==="

echo
echo "niveth-notes:"
command -v niveth-notes || true

echo
echo "niveth-app-center:"
command -v niveth-app-center || true

echo
echo "niveth-files:"
command -v niveth-files || true

echo
echo "=== 10. Checking desktop files available to GNOME ==="

echo
echo "System:"
ls -l \
    "$SYSTEM_APPS/com.niveth.Notes.desktop" \
    "$SYSTEM_APPS/com.niveth.AppCenter.desktop" \
    "$SYSTEM_APPS/org.niveth.Files.desktop"

echo
echo "User overrides:"
for file in \
    "$USER_APPS/com.niveth.Notes.desktop" \
    "$USER_APPS/com.niveth.AppCenter.desktop" \
    "$USER_APPS/org.niveth.Files.desktop"
do
    if [ -e "$file" ]; then
        echo "ERROR: Still exists:"
        echo "  $file"
    else
        echo "OK: absent:"
        echo "  $file"
    fi
done

echo
echo "=== 11. Verifying rootfs ==="

echo
echo "--- rootfs launchers ---"
sudo chown root:root \
    "$ROOTFS/usr/local/bin/niveth-notes" \
    "$ROOTFS/usr/local/bin/niveth-app-center" \
    "$ROOTFS/usr/local/bin/niveth-files"

sudo chmod 755 \
    "$ROOTFS/usr/local/bin/niveth-notes" \
    "$ROOTFS/usr/local/bin/niveth-app-center" \
    "$ROOTFS/usr/local/bin/niveth-files"

ls -l \
    "$ROOTFS/usr/local/bin/niveth-notes" \
    "$ROOTFS/usr/local/bin/niveth-app-center" \
    "$ROOTFS/usr/local/bin/niveth-files"

echo
echo "--- rootfs desktop files ---"
ls -l \
    "$ROOTFS/usr/local/share/applications/com.niveth.Notes.desktop" \
    "$ROOTFS/usr/local/share/applications/com.niveth.AppCenter.desktop" \
    "$ROOTFS/usr/local/share/applications/org.niveth.Files.desktop"

echo
echo "=================================================="
echo " FIX COMPLETE"
echo "=================================================="
echo
echo "IMPORTANT:"
echo "Log out of GNOME and log back in before testing the Dock."
