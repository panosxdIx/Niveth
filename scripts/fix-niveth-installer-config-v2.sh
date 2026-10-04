#!/usr/bin/env bash

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ROOTFS="$PROJECT_ROOT/build/rootfs"
INSTALLER="$PROJECT_ROOT/installer"
BACKUP="$PROJECT_ROOT/integration-backups/niveth-installer-config-v2-$(date +%Y%m%d-%H%M%S)"

if [[ ! -d "$ROOTFS" ]]; then
    echo "[ERROR] Rootfs not found:"
    echo "        $ROOTFS"
    exit 1
fi

echo "=== NIVETH INSTALLER CONFIG V2 ==="

mkdir -p "$INSTALLER/modules"
mkdir -p "$INSTALLER/branding/niveth"
mkdir -p "$BACKUP"

echo
echo "=== 1. BACKUP CURRENT CONFIG ==="

if [[ -f "$ROOTFS/etc/calamares/settings.conf" ]]; then
    sudo cp \
        "$ROOTFS/etc/calamares/settings.conf" \
        "$BACKUP/settings.conf"
fi

if [[ -d "$ROOTFS/etc/calamares/modules" ]]; then
    sudo cp -a \
        "$ROOTFS/etc/calamares/modules" \
        "$BACKUP/modules"
fi

if [[ -d "$ROOTFS/usr/share/calamares/branding/niveth" ]]; then
    sudo cp -a \
        "$ROOTFS/usr/share/calamares/branding/niveth" \
        "$BACKUP/branding-niveth"
fi

if [[ -d "$ROOTFS/etc/calamares/branding/niveth" ]]; then
    sudo cp -a \
        "$ROOTFS/etc/calamares/branding/niveth" \
        "$BACKUP/etc-branding-niveth"
fi

echo "[PASS] Backup:"
echo "       $BACKUP"

echo
echo "=== 2. SETTINGS.CONF ==="

cat > "$INSTALLER/settings.conf" <<'SETTINGS'
---
modules-search: [ local ]

instances:

- id: before_bootloader
  module: contextualprocess
  config: before_bootloader_context.conf

- id: before_bootloader_kerncopy
  module: shellprocess
  config: shellprocess_before_bootloader_kerncopy.conf

- id: logs
  module: shellprocess
  config: shellprocess_logs.conf

- id: bug-LP#1829805
  module: shellprocess
  config: shellprocess_bug-LP#1829805.conf

- id: add386arch
  module: shellprocess
  config: shellprocess_add386arch.conf

- id: fixconkeys_part1
  module: shellprocess
  config: shellprocess_fixconkeys_part1.conf

- id: fixconkeys_part2
  module: shellprocess
  config: shellprocess_fixconkeys_part2.conf

- id: fix-oem-uid
  module: shellprocess
  config: shellprocess_fix_oem_uid.conf

sequence:

- show:
    - welcome
    - locale
    - keyboard
    - partition
    - users
    - summary

- exec:
    - partition
    - mount
    - unpackfs
    - machineid

    - locale
    - keyboard
    - localecfg

    - luksbootkeyfile
    - fstab

    - users
    - displaymanager
    - networkcfg
    - hwclock
    - services-systemd

    - shellprocess@bug-LP#1829805
    - shellprocess@fixconkeys_part1
    - shellprocess@fixconkeys_part2

    - initramfscfg
    - initramfs

    - shellprocess@before_bootloader_kerncopy
    - grubcfg
    - contextualprocess@before_bootloader
    - bootloader

    - shellprocess@add386arch

    - shellprocess@logs
    - umount

- show:
    - finished

branding: niveth

prompt-install: true
dont-chroot: false
oem-setup: false

disable-cancel: false
disable-cancel-during-exec: false
hide-back-and-next-during-exec: false

quit-at-end: false
SETTINGS

echo "[PASS] settings.conf"

echo
echo "=== 3. BOOTLOADER CONFIG ==="

cat > "$INSTALLER/modules/bootloader.conf" <<'BOOTLOADER'
---
efiBootLoader: "grub"

timeout: "10"

grubInstall: "grub-install"
grubMkconfig: "grub-mkconfig"
grubCfg: "/boot/grub/grub.cfg"

# Keep the Ubuntu-compatible EFI identifier for stability.
# Niveth branding is handled separately by branding.desc.
efiBootloaderId: "ubuntu"

installEFIFallback: true
installHybridGRUB: false
BOOTLOADER

echo "[PASS] bootloader.conf"

echo
echo "=== 4. LOCALE CONFIG ==="

cat > "$INSTALLER/modules/locale.conf" <<'LOCALE'
---
# No hard-coded geographical timezone.
# The timezone is selected by the user in the installer.

useSystemTimezone: false
adjustLiveTimezone: true

geoip:
    style: "json"
    url: "https://geoip.kde.org/v1/calamares"
    selector: ""
LOCALE

echo "[PASS] locale.conf"

echo
echo "=== 5. GRUBCFG CONFIG ==="

cat > "$INSTALLER/modules/grubcfg.conf" <<'GRUBCFG'
---
overwrite: false

defaults:
    GRUB_ENABLE_CRYPTODISK: true
GRUBCFG

echo "[PASS] grubcfg.conf"

echo
echo "=== 6. NIVETH BRANDING ==="

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

style:

    SidebarBackground: "#1B1B1B"

    SidebarText: "#E6E6E6"

    SidebarTextCurrent: "#FFFFFF"

    SidebarBackgroundCurrent: "#303030"
BRANDING

echo "[PASS] branding.desc"

echo
echo "=== 7. INSTALL BRANDING IN /etc ==="

sudo rm -rf \
    "$ROOTFS/etc/calamares/branding/niveth"

sudo mkdir -p \
    "$ROOTFS/etc/calamares/branding/niveth"

sudo cp -a \
    "$INSTALLER/branding/niveth/." \
    "$ROOTFS/etc/calamares/branding/niveth/"

echo "[PASS] Niveth branding installed:"
echo "       $ROOTFS/etc/calamares/branding/niveth"

echo
echo "=== 8. SYNC TOP-LEVEL CONFIG ==="

sudo cp \
    "$INSTALLER/settings.conf" \
    "$ROOTFS/etc/calamares/settings.conf"

echo "[PASS] settings.conf"

echo
echo "=== 9. SYNC MODULE CONFIGS ==="

sudo cp \
    "$INSTALLER/modules/bootloader.conf" \
    "$ROOTFS/etc/calamares/modules/bootloader.conf"

sudo cp \
    "$INSTALLER/modules/locale.conf" \
    "$ROOTFS/etc/calamares/modules/locale.conf"

sudo cp \
    "$INSTALLER/modules/grubcfg.conf" \
    "$ROOTFS/etc/calamares/modules/grubcfg.conf"

echo "[PASS] bootloader.conf"
echo "[PASS] locale.conf"
echo "[PASS] grubcfg.conf"

echo
echo "=== 10. PATCH CALAMARES DESKTOP ==="

DESKTOP="$ROOTFS/usr/share/applications/calamares.desktop"

if [[ -f "$DESKTOP" ]]; then

    sudo sed -i \
        -e 's/^Name=Install System$/Name=Install Niveth/' \
        -e 's/^GenericName=System Installer$/GenericName=Niveth System Installer/' \
        -e 's/^Comment=Calamares — System Installer$/Comment=Niveth Linux System Installer/' \
        "$DESKTOP"

    echo "[PASS] calamares.desktop branded"

else

    echo "[WARN] calamares.desktop not found"

fi

echo
echo "=== 11. VERIFY REQUIRED UBUNTU MODULE CONFIGS ==="

required_files=(
    "$ROOTFS/etc/calamares/modules/before_bootloader_context.conf"
    "$ROOTFS/etc/calamares/modules/shellprocess_before_bootloader_kerncopy.conf"
    "$ROOTFS/etc/calamares/modules/shellprocess_logs.conf"
    "$ROOTFS/etc/calamares/modules/shellprocess_bug-LP#1829805.conf"
    "$ROOTFS/etc/calamares/modules/shellprocess_add386arch.conf"
    "$ROOTFS/etc/calamares/modules/shellprocess_fixconkeys_part1.conf"
    "$ROOTFS/etc/calamares/modules/shellprocess_fixconkeys_part2.conf"
)

for file in "${required_files[@]}"; do
    if [[ ! -f "$file" ]]; then
        echo "[ERROR] Missing required file:"
        echo "        $file"
        exit 1
    fi

    echo "[PASS] $(basename "$file")"
done

echo
echo "=== 12. VERIFY CALAMARES MODULES ==="

required_modules=(
    bootloader
    contextualprocess
    finished
    fstab
    grubcfg
    initramfscfg
    initramfs
    keyboard
    locale
    localecfg
    luksbootkeyfile
    machineid
    mount
    networkcfg
    partition
    shellprocess
    summary
    umount
    unpackfs
    users
    welcome
)

for module in "${required_modules[@]}"; do

    if find \
        "$ROOTFS/usr/lib/x86_64-linux-gnu/calamares/modules" \
        "$ROOTFS/usr/lib/calamares/modules" \
        -maxdepth 1 \
        -type d \
        -name "$module" \
        -print -quit \
        2>/dev/null | grep -q .

    then
        echo "[PASS] module: $module"

    else
        echo "[ERROR] missing module: $module"
        exit 1
    fi

done

echo
echo "=== 13. YAML / CONFIG BASIC VALIDATION ==="

python3 - <<PY
from pathlib import Path

rootfs = Path("$ROOTFS")

files = [
    rootfs / "etc/calamares/settings.conf",
    rootfs / "etc/calamares/modules/bootloader.conf",
    rootfs / "etc/calamares/modules/locale.conf",
    rootfs / "etc/calamares/modules/grubcfg.conf",
    rootfs / "etc/calamares/branding/niveth/branding.desc",
]

for path in files:
    if not path.is_file():
        raise SystemExit(f"[ERROR] Missing: {path}")

    if path.stat().st_size == 0:
        raise SystemExit(f"[ERROR] Empty: {path}")

print("[PASS] All Niveth installer configuration files exist")
PY

echo
echo "=== 14. CHECK FOR BAD VALUES ==="

if sudo grep -Rni \
    'efiBootloaderId: "Niveth"' \
    "$ROOTFS/etc/calamares" \
    "$ROOTFS/usr/share/calamares" \
    2>/dev/null
then
    echo "[ERROR] Old Niveth EFI bootloader ID still exists"
    exit 1
else
    echo "[PASS] No unsafe Niveth EFI bootloader ID"
fi

if sudo grep -Rni \
    'America/New_York' \
    "$ROOTFS/etc/calamares" \
    2>/dev/null
then
    echo "[ERROR] Hard-coded New York timezone remains"
    exit 1
else
    echo "[PASS] No hard-coded America/New_York"
fi

echo
echo "=== 15. FINAL FILES ==="

echo
echo "--- settings.conf ---"
sudo cat "$ROOTFS/etc/calamares/settings.conf"

echo
echo "--- bootloader.conf ---"
sudo cat "$ROOTFS/etc/calamares/modules/bootloader.conf"

echo
echo "--- locale.conf ---"
sudo cat "$ROOTFS/etc/calamares/modules/locale.conf"

echo
echo "--- grubcfg.conf ---"
sudo cat "$ROOTFS/etc/calamares/modules/grubcfg.conf"

echo
echo "--- branding.desc ---"
sudo cat "$ROOTFS/etc/calamares/branding/niveth/branding.desc"

echo
echo "=========================================="
echo "NIVETH INSTALLER CONFIG V2 READY"
echo "=========================================="
echo
echo "Backup:"
echo "  $BACKUP"
echo
echo "Installer source:"
echo "  $INSTALLER"
echo
echo "Rootfs settings:"
echo "  $ROOTFS/etc/calamares/settings.conf"
echo
echo "Rootfs branding:"
echo "  $ROOTFS/etc/calamares/branding/niveth"
echo
echo "NO ISO BUILD WAS PERFORMED."
