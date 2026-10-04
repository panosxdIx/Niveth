#!/usr/bin/env bash

set -euo pipefail

PROJECT_ROOT="$HOME/Niveth"
ROOTFS="$PROJECT_ROOT/build/rootfs"

if [ ! -d "$ROOTFS" ]; then
    echo "ERROR: Rootfs does not exist:"
    echo "  $ROOTFS"
    exit 1
fi

if [ "${XDG_SESSION_TYPE:-}" != "wayland" ]; then
    echo "ERROR: This test must be started from a Wayland session."
    echo "Current session: ${XDG_SESSION_TYPE:-unset}"
    exit 1
fi

if [ -z "${XDG_RUNTIME_DIR:-}" ]; then
    echo "ERROR: XDG_RUNTIME_DIR is not set."
    exit 1
fi

if [ -z "${WAYLAND_DISPLAY:-}" ]; then
    echo "ERROR: WAYLAND_DISPLAY is not set."
    exit 1
fi

HOST_RUNTIME="$XDG_RUNTIME_DIR"

cleanup() {
    echo
    echo "=============================================="
    echo " Cleaning up Niveth test mounts"
    echo "=============================================="

    for target in \
        "$ROOTFS/run" \
        "$ROOTFS/sys" \
        "$ROOTFS/proc" \
        "$ROOTFS/dev"
    do
        if mountpoint -q "$target"; then
            sudo umount -R "$target" 2>/dev/null || true
        fi
    done
}

trap cleanup EXIT INT TERM

echo "=============================================="
echo " Niveth Calamares Visible Test v2"
echo "=============================================="
echo

echo "Rootfs:"
echo "  $ROOTFS"
echo

echo "Wayland:"
echo "  $WAYLAND_DISPLAY"
echo

echo "Runtime:"
echo "  $HOST_RUNTIME"
echo

echo "=============================================="
echo " Mounting host runtime into rootfs"
echo "=============================================="

sudo mkdir -p \
    "$ROOTFS/dev" \
    "$ROOTFS/proc" \
    "$ROOTFS/sys" \
    "$ROOTFS/run"

echo "[1/4] /dev"
sudo mount --rbind /dev "$ROOTFS/dev"
sudo mount --make-rslave "$ROOTFS/dev"

echo "[2/4] /proc"
sudo mount -t proc proc "$ROOTFS/proc"

echo "[3/4] /sys"
sudo mount --rbind /sys "$ROOTFS/sys"
sudo mount --make-rslave "$ROOTFS/sys"

echo "[4/4] /run"
sudo mount --rbind /run "$ROOTFS/run"
sudo mount --make-rslave "$ROOTFS/run"

echo
echo "=============================================="
echo " Verifying rootfs hardware visibility"
echo "=============================================="
echo

echo "--- rootfs mount tree ---"
findmnt -R "$ROOTFS" || true

echo
echo "--- rootfs lsblk ---"
sudo chroot "$ROOTFS" /usr/bin/lsblk \
    -o NAME,PATH,SIZE,TYPE,FSTYPE,MOUNTPOINTS || true

echo
echo "--- rootfs /dev disks ---"
sudo chroot "$ROOTFS" /bin/bash -c \
    'ls -l /dev/sda /dev/sda1 /dev/sda2 /dev/sda3 \
            /dev/sdb /dev/sdb1 /dev/sdb2 /dev/sdb3 /dev/sdb4 \
            2>/dev/null || true'

echo
echo "--- rootfs /sys/block ---"
sudo chroot "$ROOTFS" /bin/bash -c \
    'ls -1 /sys/block 2>/dev/null || true'

echo
echo "--- rootfs /sys/dev/block ---"
sudo chroot "$ROOTFS" /bin/bash -c \
    'ls -1 /sys/dev/block 2>/dev/null | head -40 || true'

echo
echo "--- rootfs udev: /dev/sdb ---"
sudo chroot "$ROOTFS" /usr/bin/udevadm \
    info --query=property --name=/dev/sdb 2>&1 | head -30 || true

echo
echo "--- rootfs /run/udev ---"
sudo chroot "$ROOTFS" /bin/bash -c \
    'ls -ld /run/udev 2>/dev/null || true'
sudo chroot "$ROOTFS" /bin/bash -c \
    'ls /run/udev/data 2>/dev/null | head -20 || true'

echo
echo "--- dbus socket ---"
sudo chroot "$ROOTFS" /bin/bash -c \
    'ls -l /run/dbus/system_bus_socket 2>/dev/null || true'

echo
echo "=============================================="
echo " Hardware check finished"
echo "=============================================="
echo
echo "The terminal output above must show:"
echo "  /dev/sda"
echo "  /dev/sdb"
echo "  sda / sdb under /sys/block"
echo "  udev information for /dev/sdb"
echo
echo "Only after that will Calamares start."
echo
echo "IMPORTANT: This is a visual test."
echo "DO NOT click Install."
echo "DO NOT create, delete, format or resize partitions."
echo

read -r -p "Press ENTER to launch Calamares..."

echo
echo "=============================================="
echo " Launching Calamares"
echo "=============================================="
echo

sudo env \
    HOME=/root \
    USER=root \
    LOGNAME=root \
    PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
    XDG_RUNTIME_DIR="$HOST_RUNTIME" \
    WAYLAND_DISPLAY="$WAYLAND_DISPLAY" \
    QT_QPA_PLATFORM=wayland \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    chroot "$ROOTFS" \
    /usr/bin/calamares -D6
