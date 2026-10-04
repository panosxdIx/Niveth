#!/usr/bin/env bash

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ROOTFS="$PROJECT_ROOT/build/rootfs"
INSTALLER="$PROJECT_ROOT/installer"
NIVETH_BRANDING="$ROOTFS/etc/calamares/branding/niveth"
DEFAULT_BRANDING="$ROOTFS/usr/share/calamares/branding/default"
BACKUP="$PROJECT_ROOT/integration-backups/niveth-installer-slideshow-$(date +%Y%m%d-%H%M%S)"

SOURCE_BRANDING="$INSTALLER/branding/niveth/branding.desc"
ROOTFS_BRANDING="$NIVETH_BRANDING/branding.desc"

echo "=============================================="
echo " NIVETH INSTALLER SLIDESHOW FIX"
echo "=============================================="

if [[ ! -d "$ROOTFS" ]]; then
    echo "[ERROR] Rootfs not found:"
    echo "        $ROOTFS"
    exit 1
fi

if [[ ! -d "$DEFAULT_BRANDING" ]]; then
    echo "[ERROR] Default Calamares branding not found:"
    echo "        $DEFAULT_BRANDING"
    exit 1
fi

if [[ ! -f "$DEFAULT_BRANDING/show.qml" ]]; then
    echo "[ERROR] Default show.qml not found"
    exit 1
fi

if [[ ! -f "$DEFAULT_BRANDING/squid.png" ]]; then
    echo "[ERROR] Default squid.png not found"
    exit 1
fi

mkdir -p "$BACKUP"
mkdir -p "$INSTALLER/branding/niveth"
mkdir -p "$NIVETH_BRANDING"

echo
echo "=== 1. BACKUP ==="

if [[ -f "$SOURCE_BRANDING" ]]; then
    cp \
        "$SOURCE_BRANDING" \
        "$BACKUP/branding.desc.source"
fi

if [[ -f "$ROOTFS_BRANDING" ]]; then
    sudo cp \
        "$ROOTFS_BRANDING" \
        "$BACKUP/branding.desc.rootfs"
fi

echo "[PASS] Backup:"
echo "       $BACKUP"

echo
echo "=== 2. UPDATE BRANDING.DESc ==="

cat > "$SOURCE_BRANDING" <<'BRANDING'
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

images:
    productIcon: "squid.png"
    productLogo: "squid.png"

style:
    SidebarBackground: "#1B1B1B"
    SidebarText: "#E6E6E6"
    SidebarTextCurrent: "#FFFFFF"
    SidebarBackgroundCurrent: "#303030"

slideshow: "show.qml"
slideshowAPI: 2
BRANDING

echo "[PASS] branding.desc updated"

echo
echo "=== 3. SYNC BRANDING.DESc ==="

sudo cp \
    "$SOURCE_BRANDING" \
    "$ROOTFS_BRANDING"

echo "[PASS] branding.desc synchronized"

echo
echo "=== 4. COPY DEFAULT CALAMARES SLIDESHOW ==="

sudo cp \
    "$DEFAULT_BRANDING/show.qml" \
    "$NIVETH_BRANDING/show.qml"

sudo cp \
    "$DEFAULT_BRANDING/squid.png" \
    "$NIVETH_BRANDING/squid.png"

echo "[PASS] show.qml copied"
echo "[PASS] squid.png copied"

echo
echo "=== 5. VERIFY FILES ==="

for file in \
    "$ROOTFS_BRANDING" \
    "$NIVETH_BRANDING/show.qml" \
    "$NIVETH_BRANDING/squid.png"
do
    if [[ ! -f "$file" ]]; then
        echo "[ERROR] Missing:"
        echo "        $file"
        exit 1
    fi

    echo "[PASS] $(realpath --relative-to="$ROOTFS" "$file")"
done

echo
echo "=== 6. VERIFY SLIDESHOW CONFIG ==="

grep -q '^slideshow: "show.qml"$' \
    "$ROOTFS_BRANDING"

grep -q '^slideshowAPI: 2$' \
    "$ROOTFS_BRANDING"

echo "[PASS] slideshow=show.qml"
echo "[PASS] slideshowAPI=2"

echo
echo "=== 7. VERIFY BRANDING STRINGS ==="

grep -q '^    productName: "Niveth Linux"$' \
    "$ROOTFS_BRANDING"

grep -q '^    shortProductName: "Niveth"$' \
    "$ROOTFS_BRANDING"

grep -q '^    version: "0.1"$' \
    "$ROOTFS_BRANDING"

grep -q '^    bootloaderEntryName: "Niveth Linux"$' \
    "$ROOTFS_BRANDING"

echo "[PASS] Niveth productName"
echo "[PASS] Niveth shortProductName"
echo "[PASS] Niveth version"
echo "[PASS] Niveth bootloaderEntryName"

echo
echo "=== 8. FINAL BRANDING ==="

sudo cat "$ROOTFS_BRANDING"

echo
echo "=== 9. BRANDING FILES ==="

sudo find "$NIVETH_BRANDING" \
    -maxdepth 1 \
    -type f \
    -printf '%f\n' \
    | sort

echo
echo "=============================================="
echo " NIVETH INSTALLER SLIDESHOW FIX COMPLETE"
echo "=============================================="
echo
echo "Temporary slideshow assets are the official"
echo "Calamares defaults and can later be replaced"
echo "with Niveth artwork."
echo
echo "NO ISO BUILD PERFORMED."
