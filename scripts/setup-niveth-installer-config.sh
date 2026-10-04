#!/usr/bin/env bash

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ROOTFS="$PROJECT_ROOT/build/rootfs"
INSTALLER="$PROJECT_ROOT/installer"
BACKUP="$PROJECT_ROOT/integration-backups/niveth-installer-config-$(date +%Y%m%d-%H%M%S)"

if [[ ! -d "$ROOTFS" ]]; then
    echo "[ERROR] Rootfs not found: $ROOTFS"
    exit 1
fi

echo "=== Niveth Installer Configuration ==="

mkdir -p "$INSTALLER/modules"
mkdir -p "$INSTALLER/branding/niveth"

if [[ -d "$ROOTFS/etc/calamares" ]]; then
    mkdir -p "$BACKUP"
    cp -a "$ROOTFS/etc/calamares" "$BACKUP/"
    echo "[PASS] Backup created:"
    echo "       $BACKUP"
fi

echo
echo "=== 1. SETTINGS.CONF ==="

cat > "$INSTALLER/settings.conf" <<'SETTINGS'
---
modules-search: [ local ]

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
      - fstab
      - users
      - displaymanager
      - networkcfg
      - hwclock
      - services-systemd
      - initramfs
      - grubcfg
      - bootloader
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
echo "=== 2. BOOTLOADER CONFIG ==="

cat > "$INSTALLER/modules/bootloader.conf" <<'BOOTLOADER'
efiBootLoader: "grub"

kernel: "/vmlinuz"
img: "/initrd.img"
fallback: ""

timeout: "10"

grubInstall: "grub-install"
grubMkconfig: "grub-mkconfig"
grubCfg: "/boot/grub/grub.cfg"

efiBootloaderId: "Niveth"
BOOTLOADER

echo "[PASS] bootloader.conf"

echo
echo "=== 3. LOCALE CONFIG ==="

cat > "$INSTALLER/modules/locale.conf" <<'LOCALE'
# Niveth does not force a geographic timezone.
# Calamares will use the user's selected timezone.
#
# When the user has working network access, GeoIP may provide
# an initial timezone suggestion.

adjustLiveTimezone: true

localeGenPath: "/etc/locale.gen"

geoip:
    style: "json"
    url: "https://geoip.kde.org/v1/calamares"
    selector: ""
LOCALE

echo "[PASS] locale.conf"

echo
echo "=== 4. GRUB CONFIG ==="

cat > "$INSTALLER/modules/grubcfg.conf" <<'GRUBCFG'
overwrite: false

defaults:
    GRUB_ENABLE_CRYPTODISK: true
GRUBCFG

echo "[PASS] grubcfg.conf"

echo
echo "=== 5. Niveth BRANDING ==="

cat > "$INSTALLER/branding/niveth/branding.desc" <<'BRANDING'
---

componentName: niveth

welcomeStyleCalamares: false
welcomeExpandingLogo: false

windowSize: 1024px,680px
windowPlacement: center

strings:

    productName: "Niveth Linux"

    shortProductName: "Niveth"

    version: "0.1"

    shortVersion: "0.1"

    versionedName: "Niveth Linux 0.1"

    shortVersionedName: "Niveth 0.1"

    bootloaderEntryName: "Niveth"

    productUrl: "https://nivethos.example"

    supportUrl: ""

    knownIssuesUrl: ""

    releaseNotesUrl: ""

    donateUrl: ""

images:

style:

    sidebarBackground: "#1B1B1B"

    sidebarText: "#E6E6E6"

    sidebarTextCurrent: "#FFFFFF"

    sidebarBackgroundCurrent: "#303030"

    sidebarTextSelect: "#FFFFFF"

    sidebarTextHighlight: "#FFFFFF"
BRANDING

echo "[PASS] branding.desc"

echo
echo "=== 6. SYNC CONFIG TO ROOTFS ==="

sudo mkdir -p \
    "$ROOTFS/etc/calamares/modules" \
    "$ROOTFS/usr/share/calamares/branding/niveth"

sudo cp \
    "$INSTALLER/settings.conf" \
    "$ROOTFS/etc/calamares/settings.conf"

sudo cp \
    "$INSTALLER/modules/bootloader.conf" \
    "$ROOTFS/etc/calamares/modules/bootloader.conf"

sudo cp \
    "$INSTALLER/modules/locale.conf" \
    "$ROOTFS/etc/calamares/modules/locale.conf"

sudo cp \
    "$INSTALLER/modules/grubcfg.conf" \
    "$ROOTFS/etc/calamares/modules/grubcfg.conf"

sudo cp -a \
    "$INSTALLER/branding/niveth/." \
    "$ROOTFS/usr/share/calamares/branding/niveth/"

echo "[PASS] settings.conf synchronized"
echo "[PASS] module configs synchronized"
echo "[PASS] Niveth branding synchronized"

echo
echo "=== 7. PATCH CALAMARES DESKTOP ENTRY ==="

DESKTOP="$ROOTFS/usr/share/applications/calamares.desktop"

if [[ -f "$DESKTOP" ]]; then
    sudo sed -i \
        's/^Name=Install System$/Name=Install Niveth/; s/^GenericName=System Installer$/GenericName=Niveth System Installer/; s/^Comment=Calamares — System Installer$/Comment=Niveth Linux System Installer/' \
        "$DESKTOP"

    echo "[PASS] Installer desktop entry branded"
else
    echo "[WARN] Calamares desktop file not found"
fi

echo
echo "=== 8. VALIDATION ==="

python3 - <<PY
from pathlib import Path

files = [
    Path("$INSTALLER/settings.conf"),
    Path("$INSTALLER/modules/bootloader.conf"),
    Path("$INSTALLER/modules/locale.conf"),
    Path("$INSTALLER/modules/grubcfg.conf"),
    Path("$INSTALLER/branding/niveth/branding.desc"),
]

for path in files:
    if not path.is_file():
        raise SystemExit(f"[ERROR] Missing: {path}")
    if path.stat().st_size == 0:
        raise SystemExit(f"[ERROR] Empty: {path}")

print("[PASS] All installer source files exist")
PY

echo
echo "=== 9. VERIFY ROOTFS ==="

for path in \
    "$ROOTFS/etc/calamares/settings.conf" \
    "$ROOTFS/etc/calamares/modules/bootloader.conf" \
    "$ROOTFS/etc/calamares/modules/locale.conf" \
    "$ROOTFS/etc/calamares/modules/grubcfg.conf" \
    "$ROOTFS/usr/share/calamares/branding/niveth/branding.desc"
do
    if [[ ! -f "$path" ]]; then
        echo "[ERROR] Missing rootfs file: $path"
        exit 1
    fi
done

echo "[PASS] Rootfs installer files verified"

echo
echo "=== 10. SETTINGS SUMMARY ==="

echo
echo "--- /etc/calamares/settings.conf ---"
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
sudo cat "$ROOTFS/usr/share/calamares/branding/niveth/branding.desc"

echo
echo "======================================"
echo "NIVETH INSTALLER CONFIG INSTALLED"
echo "======================================"
echo
echo "Source:"
echo "  $INSTALLER"
echo
echo "Rootfs:"
echo "  $ROOTFS/etc/calamares"
echo
echo "Branding:"
echo "  $ROOTFS/usr/share/calamares/branding/niveth"
echo
echo "Next step: installer configuration validation."
