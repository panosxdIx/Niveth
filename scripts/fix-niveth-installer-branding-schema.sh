#!/usr/bin/env bash

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ROOTFS="$PROJECT_ROOT/build/rootfs"
INSTALLER="$PROJECT_ROOT/installer"
BRANDING_SOURCE="$INSTALLER/branding/niveth/branding.desc"
BRANDING_ROOTFS="$ROOTFS/etc/calamares/branding/niveth/branding.desc"
BACKUP="$PROJECT_ROOT/integration-backups/niveth-installer-branding-schema-$(date +%Y%m%d-%H%M%S)"

if [[ ! -d "$ROOTFS" ]]; then
    echo "[ERROR] Rootfs not found:"
    echo "        $ROOTFS"
    exit 1
fi

mkdir -p "$INSTALLER/branding/niveth"
mkdir -p "$BACKUP"

echo "=============================================="
echo " NIVETH INSTALLER BRANDING SCHEMA FIX"
echo "=============================================="

echo
echo "=== 1. BACKUP ==="

if [[ -f "$BRANDING_SOURCE" ]]; then
    cp "$BRANDING_SOURCE" \
        "$BACKUP/branding-source.desc"
fi

if [[ -f "$BRANDING_ROOTFS" ]]; then
    sudo cp "$BRANDING_ROOTFS" \
        "$BACKUP/branding-rootfs.desc"
fi

echo "[PASS] Backup:"
echo "       $BACKUP"

echo
echo "=== 2. WRITE CORRECT BRANDING SCHEMA ==="

cat > "$BRANDING_SOURCE" <<'BRANDING'
---
componentName: niveth

welcomeStyleCalamares: false
welcomeExpandingLogo: false

windowExpanding: noexpand
windowSize: 1024px,680px
windowPlacement: center

sidebar: widget
navigation: widget

strings:
    productName: "Niveth Linux"
    shortProductName: "Niveth"
    version: "0.1"
    shortVersion: "0.1"
    versionedName: "Niveth Linux 0.1"
    shortVersionedName: "Niveth 0.1"
    bootloaderEntryName: "Niveth Linux"
    productUrl: ""
    supportUrl: ""
    knownIssuesUrl: ""
    releaseNotesUrl: ""
    donateUrl: ""

images: {}

style:
    SidebarBackground: "#1B1B1B"
    SidebarText: "#E6E6E6"
    SidebarTextCurrent: "#FFFFFF"
    SidebarBackgroundCurrent: "#303030"
BRANDING

echo "[PASS] Source branding.desc written"

echo
echo "=== 3. SYNC TO ROOTFS ==="

sudo mkdir -p \
    "$ROOTFS/etc/calamares/branding/niveth"

sudo cp \
    "$BRANDING_SOURCE" \
    "$BRANDING_ROOTFS"

echo "[PASS] Rootfs branding synchronized"

echo
echo "=== 4. STRUCTURAL VALIDATION ==="

if ! grep -q '^strings:$' "$BRANDING_ROOTFS"; then
    echo "[ERROR] strings section missing"
    exit 1
fi

if ! grep -q '^    productName:' "$BRANDING_ROOTFS"; then
    echo "[ERROR] strings entries are not nested"
    exit 1
fi

if ! grep -q '^style:$' "$BRANDING_ROOTFS"; then
    echo "[ERROR] style section missing"
    exit 1
fi

if ! grep -q '^    SidebarBackground:' "$BRANDING_ROOTFS"; then
    echo "[ERROR] SidebarBackground is not nested"
    exit 1
fi

if ! grep -q '^    SidebarText:' "$BRANDING_ROOTFS"; then
    echo "[ERROR] SidebarText is not nested"
    exit 1
fi

echo "[PASS] strings nesting"
echo "[PASS] style nesting"
echo "[PASS] official-style key names"

echo
echo "=== 5. CHECK FOR BROKEN TOP-LEVEL STRING KEYS ==="

if grep -qE '^(productName|shortProductName|version|shortVersion|versionedName|shortVersionedName|bootloaderEntryName):' \
    "$BRANDING_ROOTFS"
then
    echo "[ERROR] Branding string was written at top level"
    exit 1
else
    echo "[PASS] No broken top-level string keys"
fi

echo
echo "=== 6. CHECK FOR BROKEN TOP-LEVEL STYLE KEYS ==="

if grep -qE '^(SidebarBackground|SidebarText|SidebarTextCurrent|SidebarBackgroundCurrent):' \
    "$BRANDING_ROOTFS"
then
    echo "[ERROR] Branding style key was written at top level"
    exit 1
else
    echo "[PASS] No broken top-level style keys"
fi

echo
echo "=== 7. SHOW FINAL BRANDING ==="

sudo cat "$BRANDING_ROOTFS"

echo
echo "=============================================="
echo " NIVETH BRANDING SCHEMA FIXED"
echo "=============================================="
echo
echo "NO ISO BUILD PERFORMED."
