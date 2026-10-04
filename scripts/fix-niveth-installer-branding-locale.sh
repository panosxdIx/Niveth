#!/usr/bin/env bash

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ROOTFS="$PROJECT_ROOT/build/rootfs"
INSTALLER="$PROJECT_ROOT/installer"
BACKUP="$PROJECT_ROOT/integration-backups/niveth-installer-branding-locale-$(date +%Y%m%d-%H%M%S)"

if [[ ! -d "$ROOTFS" ]]; then
    echo "[ERROR] Rootfs not found:"
    echo "        $ROOTFS"
    exit 1
fi

mkdir -p "$BACKUP"
mkdir -p "$INSTALLER/branding/niveth"
mkdir -p "$INSTALLER/modules"

echo "=== NIVETH INSTALLER BRANDING + LOCALE FIX ==="

echo
echo "=== 1. BACKUP ==="

sudo cp \
    "$ROOTFS/etc/calamares/modules/locale.conf" \
    "$BACKUP/locale.conf"

sudo cp \
    "$ROOTFS/etc/calamares/branding/niveth/branding.desc" \
    "$BACKUP/branding.desc"

echo "[PASS] Backup:"
echo "       $BACKUP"

echo
echo "=== 2. BRANDING ==="

cat > "$INSTALLER/branding/niveth/branding.desc" <<'BRANDING'
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
shortProductName: Niveth
version: "0.1"
shortVersion: "0.1"
versionedName: "Niveth Linux 0.1"
shortVersionedName: "Niveth 0.1"
bootloaderEntryName: Niveth

productUrl: ""
supportUrl: ""
knownIssuesUrl: ""
releaseNotesUrl: ""
donateUrl: ""

style:

sidebarBackground: "#1B1B1B"
sidebarText: "#E6E6E6"
sidebarTextCurrent: "#FFFFFF"
sidebarBackgroundCurrent: "#303030"
BRANDING

echo "[PASS] branding.desc source written"

echo
echo "=== 3. LOCALE ==="

cat > "$INSTALLER/modules/locale.conf" <<'LOCALE'
---
# Use the timezone already configured in the live Niveth session.
# The user can change it in the Calamares locale page.

useSystemTimezone: true
adjustLiveTimezone: true

localeGenPath: "/etc/locale.gen"

# No external GeoIP lookup is required.
LOCALE

echo "[PASS] locale.conf source written"

echo
echo "=== 4. SYNC BRANDING ==="

sudo rm -rf \
    "$ROOTFS/etc/calamares/branding/niveth"

sudo mkdir -p \
    "$ROOTFS/etc/calamares/branding/niveth"

sudo cp \
    "$INSTALLER/branding/niveth/branding.desc" \
    "$ROOTFS/etc/calamares/branding/niveth/branding.desc"

echo "[PASS] Branding synchronized"

echo
echo "=== 5. SYNC LOCALE ==="

sudo cp \
    "$INSTALLER/modules/locale.conf" \
    "$ROOTFS/etc/calamares/modules/locale.conf"

echo "[PASS] Locale synchronized"

echo
echo "=== 6. VALIDATE REQUIRED VALUES ==="

if ! grep -q '^componentName: niveth$' \
    "$ROOTFS/etc/calamares/branding/niveth/branding.desc"
then
    echo "[ERROR] componentName missing"
    exit 1
fi

if ! grep -q '^sidebarBackground:' \
    "$ROOTFS/etc/calamares/branding/niveth/branding.desc"
then
    echo "[ERROR] sidebarBackground missing"
    exit 1
fi

if ! grep -q '^sidebarText:' \
    "$ROOTFS/etc/calamares/branding/niveth/branding.desc"
then
    echo "[ERROR] sidebarText missing"
    exit 1
fi

if ! grep -q '^useSystemTimezone: true$' \
    "$ROOTFS/etc/calamares/modules/locale.conf"
then
    echo "[ERROR] useSystemTimezone is not enabled"
    exit 1
fi

echo "[PASS] Branding keys"
echo "[PASS] System timezone mode"

echo
echo "=== 7. CHECK FOR OLD VALUES ==="

if sudo grep -Rni \
    'SidebarBackground\|SidebarTextCurrent\|SidebarBackgroundCurrent' \
    "$ROOTFS/etc/calamares/branding/niveth" \
    2>/dev/null
then
    echo "[ERROR] Old capitalized branding style keys remain"
    exit 1
else
    echo "[PASS] No old capitalized branding keys"
fi

if sudo grep -Rni \
    'geoip:' \
    "$ROOTFS/etc/calamares/modules/locale.conf" \
    2>/dev/null
then
    echo "[ERROR] GeoIP configuration still enabled"
    exit 1
else
    echo "[PASS] GeoIP disabled"
fi

if sudo grep -Rni \
    'America/New_York' \
    "$ROOTFS/etc/calamares" \
    2>/dev/null
then
    echo "[ERROR] Hard-coded New York timezone remains"
    exit 1
else
    echo "[PASS] No hard-coded New York timezone"
fi

echo
echo "=== 8. FINAL CONFIG ==="

echo
echo "--- branding.desc ---"
sudo cat \
    "$ROOTFS/etc/calamares/branding/niveth/branding.desc"

echo
echo "--- locale.conf ---"
sudo cat \
    "$ROOTFS/etc/calamares/modules/locale.conf"

echo
echo "=========================================="
echo "NIVETH BRANDING + LOCALE FIX COMPLETE"
echo "=========================================="
echo
echo "Backup:"
echo "  $BACKUP"
echo
echo "NO ISO BUILD WAS PERFORMED."
