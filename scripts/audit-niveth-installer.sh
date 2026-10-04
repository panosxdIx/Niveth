#!/usr/bin/env bash

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ROOTFS="$PROJECT_ROOT/build/rootfs"

echo "============================================================"
echo "          NIVETH INSTALLER / CALAMARES AUDIT"
echo "============================================================"
echo

if [[ ! -d "$ROOTFS" ]]; then
    echo "[ERROR] Rootfs not found:"
    echo "        $ROOTFS"
    exit 1
fi

echo "=== 1. CALAMARES PACKAGES ==="

sudo chroot "$ROOTFS" dpkg-query \
    -W \
    -f='${Package} ${Version}\n' \
    calamares \
    calamares-extensions \
    calamares-settings-ubuntu-common \
    calamares-settings-ubuntu-common-data \
    2>/dev/null || true

echo
echo "=== 2. CALAMARES VERSION ==="

sudo chroot "$ROOTFS" sh -c '
    if command -v calamares >/dev/null 2>&1; then
        command -v calamares
        calamares --version 2>/dev/null || true
    else
        echo "ERROR: calamares executable not found"
    fi
'

echo
echo "=== 3. CALAMARES CONFIGURATION TREE ==="

if [[ -d "$ROOTFS/etc/calamares" ]]; then
    sudo find "$ROOTFS/etc/calamares" \
        -maxdepth 4 \
        -type f \
        -print \
        2>/dev/null | sort
else
    echo "ERROR: /etc/calamares does not exist"
fi

echo
echo "=== 4. CONFIGURATION CONTENT ==="

if [[ -d "$ROOTFS/etc/calamares" ]]; then

    while IFS= read -r file; do

        echo
        echo "============================================================"
        echo "FILE: $file"
        echo "============================================================"

        sudo sed -n '1,360p' "$file"

    done < <(
        sudo find "$ROOTFS/etc/calamares" \
            -maxdepth 4 \
            -type f \
            2>/dev/null | sort
    )

fi

echo
echo "=== 5. CALAMARES MODULES ==="

MODULE_DIR="$ROOTFS/usr/lib/x86_64-linux-gnu/calamares/modules"

if [[ -d "$MODULE_DIR" ]]; then

    sudo find "$MODULE_DIR" \
        -maxdepth 2 \
        -type f \
        -print \
        2>/dev/null | sort

else

    echo "WARNING: Module directory not found:"
    echo "         $MODULE_DIR"

fi

echo
echo "=== 6. CALAMARES BRANDING ==="

if [[ -d "$ROOTFS/usr/share/calamares/branding" ]]; then

    sudo find "$ROOTFS/usr/share/calamares/branding" \
        -maxdepth 4 \
        -type f \
        -print \
        2>/dev/null | sort

else

    echo "WARNING: No Calamares branding directory found."

fi

echo
echo "=== 7. INSTALLER DESKTOP ENTRIES ==="

sudo find "$ROOTFS/usr/share/applications" \
    -type f \
    \( \
        -iname '*calamares*' \
        -o \
        -iname '*installer*' \
    \) \
    -print \
    2>/dev/null | sort

echo
echo "=== 8. INSTALLER DIRECTORY IN PROJECT ==="

if [[ -d "$PROJECT_ROOT/installer" ]]; then

    find "$PROJECT_ROOT/installer" \
        -maxdepth 6 \
        -type f \
        -print \
        2>/dev/null | sort

else

    echo "WARNING: ~/Niveth/installer does not exist."

fi

echo
echo "=== 9. PARTITION / USER / LOCATION MODULES ==="

for module in \
    welcome \
    locale \
    keyboard \
    partition \
    users \
    location \
    displaymanager \
    networkcfg \
    packages \
    summary \
    bootloader \
    initcpiocfg \
    machineid \
    services-systemd \
    finished
do

    matches="$(
        sudo find "$MODULE_DIR" \
            -maxdepth 1 \
            -type d \
            -iname "*$module*" \
            2>/dev/null \
            | sort
    )"

    if [[ -n "$matches" ]]; then
        echo
        echo "[FOUND] $module"
        echo "$matches"
    else
        echo "[NOT FOUND] $module"
    fi

done

echo
echo "=== 10. CALAMARES YAML FILES ==="

sudo find "$ROOTFS" \
    -type f \
    \( \
        -name '*.yaml' \
        -o \
        -name '*.yml' \
    \) \
    -path '*calamares*' \
    -print \
    2>/dev/null | sort

echo
echo "=== 11. CURRENT Niveth INSTALLER FILES ==="

for path in \
    "$PROJECT_ROOT/installer" \
    "$PROJECT_ROOT/desktop/defaults" \
    "$PROJECT_ROOT/branding"
do

    if [[ -e "$path" ]]; then
        echo
        echo "--- $path ---"

        find "$path" \
            -maxdepth 5 \
            -type f \
            -print \
            2>/dev/null | sort
    fi

done

echo
echo "=== 12. ROOTFS MOUNTS ==="

findmnt -R "$ROOTFS" || true

echo
echo "============================================================"
echo "              NIVETH INSTALLER AUDIT COMPLETE"
echo "============================================================"
echo
echo "NO ROOTFS CHANGES WERE MADE."
echo
echo "Report saved to:"
echo "  $HOME/niveth-installer-audit.txt"
echo

