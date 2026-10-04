#!/usr/bin/env bash

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ROOTFS="$PROJECT_ROOT/build/rootfs"
INSTALLER="$PROJECT_ROOT/installer"
MODULE_SRC="$INSTALLER/modules"
MODULE_DST="$ROOTFS/etc/calamares/modules"
BACKUP="$PROJECT_ROOT/integration-backups/niveth-calamares-module-configs-$(date +%Y%m%d-%H%M%S)"

if [[ ! -d "$ROOTFS" ]]; then
    echo "[ERROR] Rootfs not found:"
    echo "        $ROOTFS"
    exit 1
fi

mkdir -p "$MODULE_SRC"
mkdir -p "$MODULE_DST"
mkdir -p "$BACKUP"

echo "=============================================="
echo " NIVETH CALAMARES MODULE CONFIGURATION"
echo "=============================================="

echo
echo "=== 1. BACKUP EXISTING CONFIGS ==="

for name in \
    welcome.conf \
    keyboard.conf \
    partition.conf \
    users.conf \
    unpackfs.conf \
    luksbootkeyfile.conf \
    displaymanager.conf \
    services-systemd.conf \
    initramfs.conf
do
    if [[ -f "$MODULE_DST/$name" ]]; then
        sudo cp \
            "$MODULE_DST/$name" \
            "$BACKUP/$name"
        echo "[BACKUP] $name"
    fi
done

echo
echo "=== 2. WELCOME.CONF ==="

cat > "$MODULE_SRC/welcome.conf" <<'WELCOME'
---
showSupportUrl: false
showKnownIssuesUrl: false
showReleaseNotesUrl: false
showDonateUrl: false

requirements:
    requiredStorage: 5.5
    requiredRam: 1.0

check:
    - storage
    - ram
    - power
    - internet
    - root
    - screen

required:
    - ram
WELCOME

echo "[PASS] welcome.conf"

echo
echo "=== 3. KEYBOARD.CONF ==="

cat > "$MODULE_SRC/keyboard.conf" <<'KEYBOARD'
---
xOrgConfFileName: "/etc/X11/xorg.conf.d/00-keyboard.conf"

convertedKeymapPath: "/lib/kbd/keymaps/xkb"

writeEtcDefaultKeyboard: true

useLocale1: true

guessLayout: true

configure:
    kwin: false
    gnome: false
KEYBOARD

echo "[PASS] keyboard.conf"

echo
echo "=== 4. PARTITION.CONF ==="

cat > "$MODULE_SRC/partition.conf" <<'PARTITION'
---
userSwapChoices:
    - none
    - file

initialPartitioningChoice: none
initialSwapChoice: file

drawNestedPartitions: true
alwaysShowPartitionLabels: true

allowManualPartitioning: true

defaultFileSystemType: "ext4"

availableFileSystemTypes:
    - ext4
    - btrfs
    - xfs

defaultPartitionTableType: gpt

luksGeneration: luks1
PARTITION

echo "[PASS] partition.conf"

echo
echo "=== 5. USERS.CONF ==="

cat > "$MODULE_SRC/users.conf" <<'USERS'
---
defaultGroups:
    - sudo
    - adm
    - cdrom
    - dip
    - plugdev
    - users
    - audio
    - video

allowWeakPasswords: false
allowWeakPasswordsDefault: false

autologinGroup: autologin

sudoGroup: sudo
USERS

echo "[PASS] users.conf"

echo
echo "=== 6. UNPACKFS.CONF ==="

cat > "$MODULE_SRC/unpackfs.conf" <<'UNPACKFS'
---
unpack:
    - source: "/cdrom/casper/filesystem.squashfs"
      sourcefs: squashfs
      destination: ""
UNPACKFS

echo "[PASS] unpackfs.conf"

echo
echo "=== 7. LUKSBOOTKEYFILE.CONF ==="

cat > "$MODULE_SRC/luksbootkeyfile.conf" <<'LUKSBOOT'
---
luks2Hash: default
LUKSBOOT

echo "[PASS] luksbootkeyfile.conf"

echo
echo "=== 8. DISPLAYMANAGER.CONF ==="

cat > "$MODULE_SRC/displaymanager.conf" <<'DISPLAYMANAGER'
---
displaymanagers:
    - gdm

basicSetup: false

sysconfigSetup: false

greetd:

lightdm:

sddm:
DISPLAYMANAGER

echo "[PASS] displaymanager.conf"

echo
echo "=== 9. SERVICES-SYSTEMD.CONF ==="

cat > "$MODULE_SRC/services-systemd.conf" <<'SERVICES'
---
units: []
SERVICES

echo "[PASS] services-systemd.conf"

echo
echo "=== 10. INITRAMFS.CONF ==="

cat > "$MODULE_SRC/initramfs.conf" <<'INITRAMFS'
---
kernel: "all"
be_unsafe: false
INITRAMFS

echo "[PASS] initramfs.conf"

echo
echo "=== 11. SYNC TO ROOTFS ==="

for name in \
    welcome.conf \
    keyboard.conf \
    partition.conf \
    users.conf \
    unpackfs.conf \
    luksbootkeyfile.conf \
    displaymanager.conf \
    services-systemd.conf \
    initramfs.conf
do
    sudo cp \
        "$MODULE_SRC/$name" \
        "$MODULE_DST/$name"

    echo "[PASS] synced: $name"
done

echo
echo "=== 12. VERIFY ALL FILES ==="

for name in \
    welcome.conf \
    keyboard.conf \
    partition.conf \
    users.conf \
    unpackfs.conf \
    luksbootkeyfile.conf \
    displaymanager.conf \
    services-systemd.conf \
    initramfs.conf
do
    if [[ ! -f "$MODULE_DST/$name" ]]; then
        echo "[ERROR] Missing:"
        echo "        $MODULE_DST/$name"
        exit 1
    fi
done

echo "[PASS] All module configs exist"

echo
echo "=== 13. BASIC YAML VALIDATION ==="

python3 - <<PY
from pathlib import Path
import yaml

root = Path("$MODULE_SRC")

files = [
    "welcome.conf",
    "keyboard.conf",
    "partition.conf",
    "users.conf",
    "unpackfs.conf",
    "luksbootkeyfile.conf",
    "displaymanager.conf",
    "services-systemd.conf",
    "initramfs.conf",
]

for name in files:
    path = root / name

    with path.open("r", encoding="utf-8") as f:
        data = yaml.safe_load(f)

    if data is None:
        raise SystemExit(f"[ERROR] Empty YAML: {name}")

    print(f"[PASS] YAML: {name}")
PY

echo
echo "=== 14. CRITICAL VALUE CHECK ==="

grep -q '^defaultFileSystemType: "ext4"$' \
    "$MODULE_DST/partition.conf"

grep -q '^defaultPartitionTableType: gpt$' \
    "$MODULE_DST/partition.conf"

grep -q '^luksGeneration: luks1$' \
    "$MODULE_DST/partition.conf"

grep -q '^    - gdm$' \
    "$MODULE_DST/displaymanager.conf"

grep -q '^kernel: "all"$' \
    "$MODULE_DST/initramfs.conf"

grep -q '^    - source: "/cdrom/casper/filesystem.squashfs"$' \
    "$MODULE_DST/unpackfs.conf"

grep -q '^    - sudo$' \
    "$MODULE_DST/users.conf"

echo "[PASS] ext4 default"
echo "[PASS] GPT default"
echo "[PASS] LUKS1"
echo "[PASS] GDM"
echo "[PASS] initramfs=all"
echo "[PASS] casper filesystem.squashfs"
echo "[PASS] sudo default group"

echo
echo "=== 15. SHOW CONFIG FILES ==="

for name in \
    welcome.conf \
    keyboard.conf \
    partition.conf \
    users.conf \
    unpackfs.conf \
    luksbootkeyfile.conf \
    displaymanager.conf \
    services-systemd.conf \
    initramfs.conf
do
    echo
    echo "----- $name -----"
    sudo cat "$MODULE_DST/$name"
done

echo
echo "=============================================="
echo " NIVETH CALAMARES MODULE CONFIGS READY"
echo "=============================================="
echo
echo "Backup:"
echo "  $BACKUP"
echo
echo "NO ISO BUILD PERFORMED."
