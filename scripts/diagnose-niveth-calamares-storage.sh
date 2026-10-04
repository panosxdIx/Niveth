#!/usr/bin/env bash

set -u

PROJECT_ROOT="$HOME/Niveth"
ROOTFS="$PROJECT_ROOT/build/rootfs"

echo "=============================================="
echo " Niveth Calamares Storage Diagnostic"
echo "=============================================="
echo

if [ ! -d "$ROOTFS" ]; then
    echo "ERROR: Rootfs not found:"
    echo "$ROOTFS"
    exit 1
fi

echo "=== HOST: lsblk ==="
lsblk -o NAME,PATH,SIZE,TYPE,FSTYPE,MOUNTPOINTS
echo

echo "=== HOST: /dev disks ==="
ls -l /dev/sd* /dev/nvme* 2>/dev/null || true
echo

echo "=== HOST: /sys/block ==="
ls -lah /sys/block
echo

echo "=== ROOTFS MOUNTS ==="
findmnt -R "$ROOTFS" || true
echo

echo "=============================================="
echo " Testing inside Niveth rootfs"
echo "=============================================="
echo

echo "=== ROOTFS: lsblk ==="
sudo chroot "$ROOTFS" /bin/lsblk \
    -o NAME,PATH,SIZE,TYPE,FSTYPE,MOUNTPOINTS 2>&1 || true
echo

echo "=== ROOTFS: /dev disks ==="
sudo chroot "$ROOTFS" /bin/bash -c \
    'ls -l /dev/sd* /dev/nvme* 2>/dev/null || true'
echo

echo "=== ROOTFS: /sys/block ==="
sudo chroot "$ROOTFS" /bin/bash -c \
    'ls -lah /sys/block 2>/dev/null || true'
echo

echo "=== ROOTFS: udevadm info ==="
sudo chroot "$ROOTFS" /usr/bin/udevadm info --query=property --name=/dev/sdb 2>&1 | head -40 || true
echo

echo "=== ROOTFS: /run/udev ==="
sudo chroot "$ROOTFS" /bin/bash -c \
    'ls -ld /run/udev 2>/dev/null; ls /run/udev/data 2>/dev/null | head -20 || true'
echo

echo "=== ROOTFS: DBUS SYSTEM BUS ==="
sudo chroot "$ROOTFS" /bin/bash -c \
    'ls -l /run/dbus/system_bus_socket 2>/dev/null || true'
echo

echo "=== ROOTFS: block device permissions ==="
sudo chroot "$ROOTFS" /bin/bash -c \
    'stat /dev/sda /dev/sdb /dev/sdb2 2>/dev/null || true'
echo

echo "=== COMPLETE ==="
