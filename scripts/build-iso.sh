#!/usr/bin/env bash

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

CONF="$PROJECT_ROOT/project.conf"

if [[ ! -f "$CONF" ]]; then
    echo "ERROR: project.conf not found:"
    echo "  $CONF"
    exit 1
fi

# shellcheck disable=SC1090
source "$CONF"

PROJECT_NAME="${PROJECT_NAME:-Niveth Linux}"
PROJECT_VERSION="${PROJECT_VERSION:-0.1}"
PROJECT_ARCH="${PROJECT_ARCH:-amd64}"

BASE_RELEASE="${BASE_RELEASE:-resolute}"

ROOTFS_DIR="${ROOTFS_DIR:-$PROJECT_ROOT/build/rootfs}"
ISO_WORK_DIR="${ISO_WORK_DIR:-$PROJECT_ROOT/build/iso-work}"
ISO_OUTPUT_DIR="${ISO_OUTPUT_DIR:-$PROJECT_ROOT/iso}"

ISO_NAME="${ISO_NAME:-Niveth-0.1-amd64.iso}"
MAX_ISO_SIZE_MB="${MAX_ISO_SIZE_MB:-5120}"

ISO_PATH="$ISO_OUTPUT_DIR/$ISO_NAME"

CASPER_DIR="$ISO_WORK_DIR/casper"
GRUB_DIR="$ISO_WORK_DIR/boot/grub"
DISK_DIR="$ISO_WORK_DIR/.disk"

if [[ "$BASE_RELEASE" != "resolute" ]]; then
    echo "ERROR: Niveth 0.1 ISO expects Ubuntu 26.04 LTS (resolute)."
    exit 1
fi

if [[ "$PROJECT_ARCH" != "amd64" ]]; then
    echo "ERROR: this Niveth 0.1 ISO builder currently targets amd64."
    exit 1
fi

if [[ "$EUID" -ne 0 ]]; then
    echo
    echo "ERROR: this script must be run as root."
    echo
    echo "Use:"
    echo "  sudo $0"
    echo
    exit 1
fi

REQUIRED_COMMANDS=(
    mksquashfs
    grub-mkrescue
    xorriso
    chroot
    find
    grep
    awk
    sed
    cp
    mkdir
    rm
    sort
    du
    stat
)

for cmd in "${REQUIRED_COMMANDS[@]}"; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "ERROR: required command not found: $cmd"
        exit 1
    fi
done

if [[ ! -d "$ROOTFS_DIR" ]]; then
    echo "ERROR: rootfs does not exist:"
    echo "  $ROOTFS_DIR"
    exit 1
fi

if [[ -z "$(find "$ROOTFS_DIR" -mindepth 1 -maxdepth 1 -print -quit 2>/dev/null)" ]]; then
    echo "ERROR: rootfs is empty:"
    echo "  $ROOTFS_DIR"
    exit 1
fi

echo
echo "============================================================"
echo "                 NIVETH ISO BUILDER"
echo "============================================================"
echo
echo "Project      : $PROJECT_NAME"
echo "Version      : $PROJECT_VERSION"
echo "Base         : Ubuntu 26.04 LTS"
echo "Architecture : $PROJECT_ARCH"
echo "Rootfs       : $ROOTFS_DIR"
echo "ISO work     : $ISO_WORK_DIR"
echo "ISO output   : $ISO_PATH"
echo "Max size     : ${MAX_ISO_SIZE_MB} MB"
echo

# ============================================================
# 1. ROOTFS VALIDATION
# ============================================================

echo "[1/9] Validating rootfs..."

if findmnt -R "$ROOTFS_DIR" 2>/dev/null | grep -q .; then
    echo
    echo "ERROR: rootfs still has mounted filesystems:"
    findmnt -R "$ROOTFS_DIR"
    echo
    echo "Unmount them before building the ISO."
    exit 1
fi

if ! chroot "$ROOTFS_DIR" dpkg-query -W casper >/dev/null 2>&1; then
    echo "ERROR: casper is not installed in the rootfs."
    exit 1
fi

if ! chroot "$ROOTFS_DIR" dpkg-query -W linux-generic >/dev/null 2>&1; then
    echo "ERROR: linux-generic is not installed in the rootfs."
    exit 1
fi

if ! chroot "$ROOTFS_DIR" dpkg-query -W grub-pc-bin >/dev/null 2>&1; then
    echo "ERROR: grub-pc-bin is not installed in the rootfs."
    exit 1
fi

if ! chroot "$ROOTFS_DIR" dpkg-query -W grub-efi-amd64-bin >/dev/null 2>&1; then
    echo "ERROR: grub-efi-amd64-bin is not installed in the rootfs."
    exit 1
fi

if ! chroot "$ROOTFS_DIR" dpkg-query -W calamares >/dev/null 2>&1; then
    echo "ERROR: Calamares is not installed in the rootfs."
    exit 1
fi

KERNEL_SOURCE="$(
    find "$ROOTFS_DIR/boot" \
        -maxdepth 1 \
        -type f \
        -name 'vmlinuz-*' \
        -printf '%p\n' \
        | sort -V \
        | tail -n 1
)"

INITRD_SOURCE="$(
    find "$ROOTFS_DIR/boot" \
        -maxdepth 1 \
        -type f \
        -name 'initrd.img-*' \
        -printf '%p\n' \
        | sort -V \
        | tail -n 1
)"

if [[ -z "$KERNEL_SOURCE" ]]; then
    echo "ERROR: no vmlinuz-* found in rootfs /boot."
    exit 1
fi

if [[ -z "$INITRD_SOURCE" ]]; then
    echo "ERROR: no initrd.img-* found in rootfs /boot."
    exit 1
fi

echo "Kernel:"
echo "  $KERNEL_SOURCE"

echo "Initramfs:"
echo "  $INITRD_SOURCE"

echo

# ============================================================
# 2. CLEAN ISO WORKSPACE
# ============================================================

echo "[2/9] Preparing ISO workspace..."

rm -rf "$ISO_WORK_DIR"

mkdir -p \
    "$ISO_WORK_DIR" \
    "$CASPER_DIR" \
    "$GRUB_DIR" \
    "$DISK_DIR" \
    "$ISO_OUTPUT_DIR"

rm -f "$ISO_PATH"

# ============================================================
# 3. LIVE FILESYSTEM
# ============================================================

echo "[3/9] Creating live filesystem..."

echo "Copying kernel..."
cp -L \
    "$KERNEL_SOURCE" \
    "$CASPER_DIR/vmlinuz"

echo "Copying initramfs..."
cp -L \
    "$INITRD_SOURCE" \
    "$CASPER_DIR/initrd"

echo "Creating filesystem.manifest..."

chroot "$ROOTFS_DIR" dpkg-query \
    -W \
    --showformat='${Package} ${Version}\n' \
    | sort \
    > "$CASPER_DIR/filesystem.manifest"

echo "Creating filesystem.size..."

du -sx \
    --block-size=1 \
    "$ROOTFS_DIR" \
    | awk '{print $1}' \
    > "$CASPER_DIR/filesystem.size"

echo "Creating squashfs..."

mksquashfs \
    "$ROOTFS_DIR" \
    "$CASPER_DIR/filesystem.squashfs" \
    -comp xz \
    -b 1M \
    -noappend

# ============================================================
# 4. DISK METADATA
# ============================================================

echo "[4/9] Creating Niveth disk metadata..."

cat > "$DISK_DIR/info" <<DISKINFO_EOF
niveth Linux $PROJECT_VERSION - Ubuntu 26.04 LTS
DISKINFO_EOF

cat > "$DISK_DIR/release_notes" <<RELEASE_EOF
Niveth Linux $PROJECT_VERSION

Base:
Ubuntu 26.04 LTS

Desktop:
GNOME

Architecture:
amd64
RELEASE_EOF

# ============================================================
# 5. GRUB CONFIGURATION
# ============================================================

echo "[5/9] Creating GRUB configuration..."

cat > "$GRUB_DIR/grub.cfg" <<'GRUB_EOF'
set default=0
set timeout=8

if loadfont unicode ; then
    terminal_output gfxterm
fi

insmod all_video
insmod gfxterm
insmod font

if background_color 0,0,0 ; then
    clear
fi

menuentry "Niveth Linux 0.1 — Try Niveth" {
    linux /casper/vmlinuz \
        boot=casper \
        quiet \
        splash \
        username=niveth \
        userfullname="Niveth Live Session" \
        hostname=niveth \
        ---
    initrd /casper/initrd
}

menuentry "Niveth Linux 0.1 — Compatibility Mode" {
    linux /casper/vmlinuz \
        boot=casper \
        nomodeset \
        username=niveth \
        userfullname="Niveth Live Session" \
        hostname=niveth \
        ---
    initrd /casper/initrd
}

menuentry "Reboot" {
    reboot
}

menuentry "Power Off" {
    halt
}
GRUB_EOF

# Replace version-specific hardcoded text with project version.
sed -i \
    "s/Niveth Linux 0\\.1/Niveth Linux ${PROJECT_VERSION}/g" \
    "$GRUB_DIR/grub.cfg"

# ============================================================
# 6. ISO README
# ============================================================

echo "[6/9] Adding ISO information..."

cat > "$ISO_WORK_DIR/NIVETH-README.txt" <<README_EOF
Niveth Linux $PROJECT_VERSION

Base:
Ubuntu 26.04 LTS

Desktop:
GNOME

Architecture:
amd64

Live boot:
Casper

Installer:
Calamares

Browser:
Vivaldi

Terminal:
Kitty

This ISO is a live Niveth Linux image.
README_EOF

# ============================================================
# 7. CREATE ISO
# ============================================================

echo "[7/9] Building bootable ISO..."

grub-mkrescue \
    --product-name="$PROJECT_NAME" \
    --product-version="$PROJECT_VERSION" \
    -o "$ISO_PATH" \
    "$ISO_WORK_DIR"

# ============================================================
# 8. ISO VALIDATION
# ============================================================

echo "[8/9] Validating ISO..."

if [[ ! -f "$ISO_PATH" ]]; then
    echo "ERROR: ISO was not created:"
    echo "  $ISO_PATH"
    exit 1
fi

ISO_BYTES="$(stat -c '%s' "$ISO_PATH")"
MAX_BYTES="$((MAX_ISO_SIZE_MB * 1024 * 1024))"

echo
echo "ISO size:"
du -h "$ISO_PATH"

echo
echo "ISO bytes:"
echo "  $ISO_BYTES"

echo
echo "Maximum allowed:"
echo "  $MAX_BYTES"

if (( ISO_BYTES > MAX_BYTES )); then
    echo
    echo "ERROR: ISO exceeds the ${MAX_ISO_SIZE_MB} MB limit."
    echo "  ISO:     $ISO_BYTES bytes"
    echo "  Maximum: $MAX_BYTES bytes"
    exit 1
fi

echo
echo "=== ISO volume information ==="
xorriso \
    -indev "$ISO_PATH" \
    -pvd_info \
    2>/dev/null \
    | sed -n \
        -e '/Volume id/Ip' \
        -e '/Volume set id/Ip' \
        -e '/Publisher/Ip' \
        -e '/Application id/Ip' \
        -e '/System id/Ip'

echo
echo "=== El Torito information ==="
xorriso \
    -indev "$ISO_PATH" \
    -report_el_torito plain \
    2>/dev/null \
    | sed -n '1,120p'

echo
echo "=== ISO CASPER CONTENT ==="
xorriso \
    -indev "$ISO_PATH" \
    -ls /casper \
    2>/dev/null

echo
echo "=== ISO GRUB CONTENT ==="
xorriso \
    -indev "$ISO_PATH" \
    -ls /boot/grub \
    2>/dev/null

# ============================================================
# 9. CHECKSUMS
# ============================================================

echo "[9/9] Creating checksums..."

(
    cd "$ISO_OUTPUT_DIR"
    sha256sum "$ISO_NAME" > "${ISO_NAME}.sha256"
    md5sum "$ISO_NAME" > "${ISO_NAME}.md5"
)

echo
echo "============================================================"
echo "              Niveth ISO created successfully"
echo "============================================================"
echo
echo "ISO:"
echo "  $ISO_PATH"
echo
echo "SHA256:"
cat "$ISO_OUTPUT_DIR/${ISO_NAME}.sha256"
echo
echo "MD5:"
cat "$ISO_OUTPUT_DIR/${ISO_NAME}.md5"
echo
echo "The ISO is within the configured size limit."
echo
