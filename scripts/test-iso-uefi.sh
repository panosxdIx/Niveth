#!/usr/bin/env bash

set -Eeuo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ISO="$PROJECT_ROOT/iso/Niveth-0.1.1-amd64.iso"

if [[ ! -f "$ISO" ]]; then
    echo "ERROR: ISO not found:"
    echo "  $ISO"
    exit 1
fi

QEMU="$(command -v qemu-system-x86_64 || true)"

if [[ -z "$QEMU" ]]; then
    echo "ERROR: qemu-system-x86_64 not found."
    exit 1
fi

OVMF_CODE=""

for candidate in \
    /usr/share/OVMF/OVMF_CODE_4M.fd \
    /usr/share/OVMF/OVMF_CODE.fd \
    /usr/share/edk2/ovmf/OVMF_CODE_4M.fd \
    /usr/share/edk2/ovmf/x64/OVMF_CODE.fd
do
    if [[ -f "$candidate" ]]; then
        OVMF_CODE="$candidate"
        break
    fi
done

if [[ -z "$OVMF_CODE" ]]; then
    echo "ERROR: OVMF firmware not found."
    exit 1
fi

OVMF_VARS_TEMPLATE=""

for candidate in \
    /usr/share/OVMF/OVMF_VARS_4M.fd \
    /usr/share/OVMF/OVMF_VARS.fd \
    /usr/share/edk2/ovmf/OVMF_VARS_4M.fd \
    /usr/share/edk2/ovmf/x64/OVMF_VARS.fd
do
    if [[ -f "$candidate" ]]; then
        OVMF_VARS_TEMPLATE="$candidate"
        break
    fi
done

if [[ -z "$OVMF_VARS_TEMPLATE" ]]; then
    echo "ERROR: OVMF variable template not found."
    exit 1
fi

WORK_DIR="$PROJECT_ROOT/build/qemu-uefi"
VARS="$WORK_DIR/OVMF_VARS.fd"

mkdir -p "$WORK_DIR"

if [[ ! -f "$VARS" ]]; then
    cp "$OVMF_VARS_TEMPLATE" "$VARS"
fi

echo
echo "============================================================"
echo "            NIVETH UEFI QEMU TEST"
echo "============================================================"
echo
echo "ISO:"
echo "  $ISO"
echo
echo "QEMU:"
echo "  $QEMU"
echo
echo "OVMF:"
echo "  $OVMF_CODE"
echo
echo "Input:"
echo "  virtio-tablet-pci (absolute pointer)"
echo "  virtio-keyboard-pci"
echo
echo "Display:"
echo "  GTK"
echo "  Cursor forced ON"
echo "  Mouse/keyboard grab on hover OFF"
echo
echo "Release grab:"
echo "  Ctrl+Alt+G"
echo
echo "============================================================"
echo

exec "$QEMU" \
    -enable-kvm \
    -machine q35 \
    -cpu host \
    -smp 4 \
    -m 4096 \
    -drive "if=pflash,format=raw,readonly=on,file=$OVMF_CODE" \
    -drive "if=pflash,format=raw,file=$VARS" \
    -cdrom "$ISO" \
    -boot order=d \
    -display gtk,show-cursor=on,grab-on-hover=off,zoom-to-fit=on \
    -device virtio-vga \
    -device virtio-tablet-pci \
    -device virtio-keyboard-pci
