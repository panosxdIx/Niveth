#!/usr/bin/env bash

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$PROJECT_ROOT/project.conf"

echo "========================================"
echo " Niveth Linux 0.1 - Preflight"
echo "========================================"
echo
echo "Project:      $PROJECT_NAME"
echo "Version:      $PROJECT_VERSION"
echo "Architecture: $PROJECT_ARCH"
echo "Base:         $BASE_DISTRO $BASE_RELEASE"
echo "Desktop:      $DESKTOP"
echo "Installer:    $INSTALLER"
echo

required_tools=(
    debootstrap
    mksquashfs
    xorriso
    grub-mkstandalone
)

missing=()

for tool in "${required_tools[@]}"; do
    if command -v "$tool" >/dev/null 2>&1; then
        printf 'OK       %s -> %s\n' "$tool" "$(command -v "$tool")"
    else
        printf 'MISSING  %s\n' "$tool"
        missing+=("$tool")
    fi
done

echo

if ((${#missing[@]})); then
    echo "Missing build tools:"
    printf '  %s\n' "${missing[@]}"
    echo
    echo "Preflight: FAILED"
    exit 1
fi

echo "Preflight: OK"
