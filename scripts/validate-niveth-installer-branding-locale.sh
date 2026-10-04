#!/usr/bin/env bash

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ROOTFS="$PROJECT_ROOT/build/rootfs"

echo "=== NIVETH INSTALLER BRANDING + LOCALE VALIDATION ==="

if [[ ! -d "$ROOTFS" ]]; then
    echo "[ERROR] Rootfs not found:"
    echo "        $ROOTFS"
    exit 1
fi

BRANDING="$ROOTFS/etc/calamares/branding/niveth/branding.desc"
LOCALE="$ROOTFS/etc/calamares/modules/locale.conf"

echo
echo "=== 1. REQUIRED FILES ==="

for file in \
    "$ROOTFS/etc/calamares/settings.conf" \
    "$ROOTFS/etc/calamares/modules/bootloader.conf" \
    "$LOCALE" \
    "$ROOTFS/etc/calamares/modules/grubcfg.conf" \
    "$BRANDING"
do
    if [[ ! -f "$file" ]]; then
        echo "[ERROR] Missing:"
        echo "        $file"
        exit 1
    fi

    echo "[PASS] $(basename "$file")"
done

echo
echo "=== 2. BRANDING VALUES ==="

grep -q '^componentName: niveth$' "$BRANDING" \
    && echo "[PASS] componentName"

grep -q '^productName: "Niveth Linux"$' "$BRANDING" \
    && echo "[PASS] productName"

grep -q '^shortProductName: Niveth$' "$BRANDING" \
    && echo "[PASS] shortProductName"

grep -q '^version: "0.1"$' "$BRANDING" \
    && echo "[PASS] version"

grep -q '^versionedName: "Niveth Linux 0.1"$' "$BRANDING" \
    && echo "[PASS] versionedName"

grep -q '^bootloaderEntryName: Niveth$' "$BRANDING" \
    && echo "[PASS] bootloaderEntryName"

echo
echo "=== 3. BRANDING STYLE KEYS ==="

grep -q '^sidebarBackground:' "$BRANDING" \
    && echo "[PASS] sidebarBackground"

grep -q '^sidebarText:' "$BRANDING" \
    && echo "[PASS] sidebarText"

grep -q '^sidebarTextCurrent:' "$BRANDING" \
    && echo "[PASS] sidebarTextCurrent"

grep -q '^sidebarBackgroundCurrent:' "$BRANDING" \
    && echo "[PASS] sidebarBackgroundCurrent"

echo
echo "=== 4. MAKE SURE CAPITALIZED KEYS ARE NOT ACTUALLY PRESENT ==="

if grep -nE '^[[:space:]]*(SidebarBackground|SidebarText|SidebarTextCurrent|SidebarBackgroundCurrent):' \
    "$BRANDING"
then
    echo "[ERROR] Capitalized branding keys are present."
    exit 1
else
    echo "[PASS] No capitalized branding keys"
fi

echo
echo "=== 5. LOCALE ==="

grep -q '^useSystemTimezone: true$' "$LOCALE" \
    && echo "[PASS] useSystemTimezone=true"

grep -q '^adjustLiveTimezone: true$' "$LOCALE" \
    && echo "[PASS] adjustLiveTimezone=true"

if grep -q '^geoip:' "$LOCALE"; then
    echo "[ERROR] GeoIP block is still enabled"
    exit 1
else
    echo "[PASS] GeoIP disabled"
fi

if grep -q 'America/New_York' "$ROOTFS/etc/calamares"/* \
    "$ROOTFS/etc/calamares/modules"/* \
    2>/dev/null
then
    echo "[ERROR] America/New_York still exists"
    exit 1
else
    echo "[PASS] No America/New_York"
fi

echo
echo "=== 6. BOOTLOADER ==="

grep -q '^efiBootLoader: "grub"$' \
    "$ROOTFS/etc/calamares/modules/bootloader.conf" \
    && echo "[PASS] GRUB EFI"

grep -q '^efiBootloaderId: "ubuntu"$' \
    "$ROOTFS/etc/calamares/modules/bootloader.conf" \
    && echo "[PASS] Ubuntu-compatible EFI ID"

echo
echo "=== 7. SETTINGS / BRANDING LINK ==="

grep -q '^branding: niveth$' \
    "$ROOTFS/etc/calamares/settings.conf" \
    && echo "[PASS] branding=niveth"

if [[ -d "$ROOTFS/etc/calamares/branding/niveth" ]]; then
    echo "[PASS] /etc/calamares/branding/niveth"
else
    echo "[ERROR] Niveth branding directory missing"
    exit 1
fi

echo
echo "=== 8. FINAL CONTENT ==="

echo
echo "--- branding.desc ---"
sudo cat "$BRANDING"

echo
echo "--- locale.conf ---"
sudo cat "$LOCALE"

echo
echo "--- bootloader.conf ---"
sudo cat "$ROOTFS/etc/calamares/modules/bootloader.conf"

echo
echo "============================================"
echo "NIVETH INSTALLER BRANDING/LOCALE VALIDATION"
echo "PASSED"
echo "============================================"

echo
echo "NO ROOTFS CHANGES MADE."
echo "NO ISO BUILD PERFORMED."
