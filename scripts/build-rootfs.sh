#!/usr/bin/env bash

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

CONF="$PROJECT_ROOT/project.conf"
ROOTFS="$PROJECT_ROOT/build/rootfs"

if [[ ! -f "$CONF" ]]; then
    echo "ERROR: project.conf not found:"
    echo "  $CONF"
    exit 1
fi

# shellcheck disable=SC1090
source "$CONF"

BASE_DISTRO="${BASE_DISTRO:-ubuntu}"
BASE_RELEASE="${BASE_RELEASE:-resolute}"
BASE_MIRROR="${BASE_MIRROR:-http://archive.ubuntu.com/ubuntu}"
ARCH="${PROJECT_ARCH:-amd64}"

if [[ "$BASE_DISTRO" != "ubuntu" ]]; then
    echo "ERROR: Niveth rootfs must use Ubuntu."
    exit 1
fi

if [[ "$BASE_RELEASE" != "resolute" ]]; then
    echo "ERROR: Niveth 0.1 expects Ubuntu 26.04 LTS (resolute)."
    exit 1
fi

if [[ "$DESKTOP" != "gnome" ]]; then
    echo "ERROR: Niveth 0.1 expects GNOME."
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
    debootstrap
    mount
    mountpoint
    umount
    chroot
    awk
    sed
    grep
    find
    install
    cp
    mkdir
    rm
    sort
    python3
)

for cmd in "${REQUIRED_COMMANDS[@]}"; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "ERROR: required command not found: $cmd"
        exit 1
    fi
done

mkdir -p "$PROJECT_ROOT/build"

if [[ -e "$ROOTFS" ]] && \
   [[ -n "$(find "$ROOTFS" -mindepth 1 -maxdepth 1 -print -quit 2>/dev/null)" ]]; then

    echo
    echo "ERROR: rootfs is not empty:"
    echo "  $ROOTFS"
    echo
    echo "Clean it explicitly before rebuilding:"
    echo "  sudo rm -rf '$ROOTFS'"
    echo
    exit 1
fi

mkdir -p "$ROOTFS"

RESOLV_BACKUP="$ROOTFS/etc/resolv.conf.niveth-backup"

cleanup() {
    set +e

    echo
    echo "=== Cleaning build mounts ==="

    if mountpoint -q "$ROOTFS/dev"; then
        umount -R "$ROOTFS/dev" 2>/dev/null || true
    fi

    if mountpoint -q "$ROOTFS/proc"; then
        umount "$ROOTFS/proc" 2>/dev/null || true
    fi

    if mountpoint -q "$ROOTFS/sys"; then
        umount -R "$ROOTFS/sys" 2>/dev/null || true
    fi

    rm -f "$ROOTFS/usr/sbin/policy-rc.d"

    if [[ -f "$RESOLV_BACKUP" ]]; then
        rm -f "$ROOTFS/etc/resolv.conf"
        mv "$RESOLV_BACKUP" "$ROOTFS/etc/resolv.conf" 2>/dev/null || true
    fi

    rm -f "$ROOTFS/tmp/niveth-packages.txt"
    rm -f "$ROOTFS/tmp/niveth-packages-no-vivaldi.txt"

    echo "Cleanup finished."
}

trap cleanup EXIT

echo
echo "============================================================"
echo "              Niveth Linux 0.1"
echo "                 ROOTFS BUILDER"
echo "============================================================"
echo
echo "Project      : $PROJECT_NAME"
echo "Version      : $PROJECT_VERSION"
echo "Base         : Ubuntu 26.04 LTS"
echo "Codename     : $BASE_RELEASE"
echo "Desktop      : GNOME"
echo "Architecture : $ARCH"
echo "Rootfs       : $ROOTFS"
echo

# ============================================================
# 1. DEBOOTSTRAP
# ============================================================

echo "[1/10] Creating Ubuntu base..."

debootstrap \
    --arch="$ARCH" \
    --components=main,restricted,universe,multiverse \
    --include=ca-certificates,ubuntu-standard \
    "$BASE_RELEASE" \
    "$ROOTFS" \
    "$BASE_MIRROR"

# ============================================================
# 2. APT / HOSTNAME / NETWORK
# ============================================================

echo "[2/10] Configuring base system..."

cat > "$ROOTFS/etc/apt/sources.list" <<APT_EOF
deb $BASE_MIRROR $BASE_RELEASE main restricted universe multiverse
deb $BASE_MIRROR $BASE_RELEASE-updates main restricted universe multiverse
deb $BASE_MIRROR $BASE_RELEASE-security main restricted universe multiverse
APT_EOF

echo "niveth" > "$ROOTFS/etc/hostname"

cat > "$ROOTFS/etc/hosts" <<HOSTS_EOF
127.0.0.1 localhost
127.0.1.1 niveth

::1 localhost ip6-localhost ip6-loopback
HOSTS_EOF

mkdir -p "$ROOTFS/etc"

if [[ -e "$ROOTFS/etc/resolv.conf" ]]; then
    cp -a "$ROOTFS/etc/resolv.conf" "$RESOLV_BACKUP"
fi

rm -f "$ROOTFS/etc/resolv.conf"

cat > "$ROOTFS/etc/resolv.conf" <<RESOLV_EOF
nameserver 1.1.1.1
nameserver 8.8.8.8
RESOLV_EOF

# ============================================================
# 3. MOUNTS
# ============================================================

echo "[3/10] Mounting runtime filesystems..."

mount --rbind /dev "$ROOTFS/dev"
mount --make-rslave "$ROOTFS/dev"

mount -t proc proc "$ROOTFS/proc"

mount -t sysfs sysfs "$ROOTFS/sys"
mount --make-rslave "$ROOTFS/sys"

# ============================================================
# 4. SERVICE BLOCKING
# ============================================================

echo "[4/10] Preventing services from starting during chroot..."

cat > "$ROOTFS/usr/sbin/policy-rc.d" <<POLICY_EOF
#!/bin/sh
exit 101
POLICY_EOF

chmod 0755 "$ROOTFS/usr/sbin/policy-rc.d"

# ============================================================
# 5. APT UPDATE
# ============================================================

echo "[5/10] Updating package indexes..."

chroot "$ROOTFS" /bin/bash -c '
    export DEBIAN_FRONTEND=noninteractive
    apt-get update
'

# ============================================================
# 6. PACKAGE INSTALLATION
# ============================================================

echo "[6/10] Installing Ubuntu + GNOME + Niveth + live boot dependencies..."

PACKAGE_FILES=(
    "$PROJECT_ROOT/packages/base.txt"
    "$PROJECT_ROOT/packages/gnome.txt"
    "$PROJECT_ROOT/packages/niveth-apps.txt"
    "$PROJECT_ROOT/packages/support.txt"
    "$PROJECT_ROOT/packages/build-tools.txt"
    "$PROJECT_ROOT/packages/optional-hardware.txt"
    "$PROJECT_ROOT/packages/installer.txt"
    "$PROJECT_ROOT/packages/live-boot.txt"
)

TMP_PACKAGE_LIST="$PROJECT_ROOT/build/rootfs-packages.txt"
TMP_PACKAGE_LIST_NO_VIVALDI="$PROJECT_ROOT/build/rootfs-packages-no-vivaldi.txt"

: > "$TMP_PACKAGE_LIST"

for package_file in "${PACKAGE_FILES[@]}"; do

    if [[ ! -f "$package_file" ]]; then
        echo
        echo "ERROR: package manifest missing:"
        echo "  $package_file"
        exit 1
    fi

    awk '
        /^[[:space:]]*#/ { next }
        NF == 0 { next }
        { print $1 }
    ' "$package_file" >> "$TMP_PACKAGE_LIST"

done

sort -u "$TMP_PACKAGE_LIST" -o "$TMP_PACKAGE_LIST"

grep -v '^vivaldi-stable$' \
    "$TMP_PACKAGE_LIST" \
    > "$TMP_PACKAGE_LIST_NO_VIVALDI"

echo
echo "=== Package list ==="
cat "$TMP_PACKAGE_LIST"

echo
echo "=== Copying package list into rootfs ==="

cp "$TMP_PACKAGE_LIST_NO_VIVALDI" \
   "$ROOTFS/tmp/niveth-packages-no-vivaldi.txt"

chroot "$ROOTFS" /bin/bash -c '
    export DEBIAN_FRONTEND=noninteractive

    apt-get install -y \
        $(cat /tmp/niveth-packages-no-vivaldi.txt)

    rm -f /tmp/niveth-packages-no-vivaldi.txt
'

# ============================================================
# 7. VIVALDI
# ============================================================

echo "[7/10] Installing Vivaldi..."

install -d -m 0755 \
    "$ROOTFS/usr/share/keyrings"

chroot "$ROOTFS" /bin/bash -c '
    set -Eeuo pipefail

    export DEBIAN_FRONTEND=noninteractive

    wget -qO- \
        https://repo.vivaldi.com/stable/linux_signing_key.pub \
        | gpg --dearmor \
        > /usr/share/keyrings/vivaldi-browser.gpg

    chmod 0644 /usr/share/keyrings/vivaldi-browser.gpg

    cat > /etc/apt/sources.list.d/vivaldi.sources <<VIVALDI_EOF
Types: deb
URIs: https://repo.vivaldi.com/stable/deb/
Suites: stable
Components: main
Architectures: amd64
Signed-By: /usr/share/keyrings/vivaldi-browser.gpg
VIVALDI_EOF

    apt-get update

    apt-get install -y vivaldi-stable
'

# ============================================================
# 8. NIVETH COMPONENTS
# ============================================================

echo "[8/10] Installing Niveth custom components..."

COMPONENT_MANIFEST="$PROJECT_ROOT/desktop/niveth-components.txt"

if [[ ! -f "$COMPONENT_MANIFEST" ]]; then
    echo
    echo "ERROR: custom component manifest missing:"
    echo "  $COMPONENT_MANIFEST"
    exit 1
fi

while IFS= read -r line; do

    case "$line" in

        ""|\#*)
            continue
            ;;

        COPY_FILE\ *)
            src="${line#COPY_FILE }"
            src="${src%% *}"
            dst="${line#COPY_FILE "$src" }"

            if [[ ! -f "$src" ]]; then
                echo
                echo "ERROR: source file missing:"
                echo "  $src"
                exit 1
            fi

            mkdir -p \
                "$ROOTFS$(dirname "$dst")"

            cp -a \
                "$src" \
                "$ROOTFS$dst"
            ;;

        COPY_DIR\ *)
            src="${line#COPY_DIR }"
            src="${src%% *}"
            dst="${line#COPY_DIR "$src" }"

            if [[ ! -d "$src" ]]; then
                echo
                echo "ERROR: source directory missing:"
                echo "  $src"
                exit 1
            fi

            mkdir -p \
                "$ROOTFS$dst"

            cp -a \
                "$src/." \
                "$ROOTFS$dst/"

            # Never ship development-only artifacts in release images.
            find "$ROOTFS$dst" \
                -type f \
                \( \
                    -name '*.backup*' \
                    -o -name '*.before-*' \
                    -o -name '*.pyc' \
                \) \
                -delete

            find "$ROOTFS$dst" \
                -type d \
                \( \
                    -name '__pycache__' \
                    -o -name 'backup' \
                    -o -name 'backups' \
                    -o -name 'integration-backups' \
                \) \
                -prune \
                -exec rm -rf {} +

            ;;

        *)
            echo
            echo "WARNING: unknown manifest line:"
            echo "  $line"
            ;;

    esac

done < "$COMPONENT_MANIFEST"

# ============================================================
# 9. NIVETH GNOME DEFAULTS + USER SERVICES
# ============================================================

echo "[9/10] Configuring Niveth desktop defaults..."

# ------------------------------------------------------------
# dconf profile
# ------------------------------------------------------------

mkdir -p \
    "$ROOTFS/etc/dconf/profile" \
    "$ROOTFS/etc/dconf/db/local.d"

cat > "$ROOTFS/etc/dconf/profile/user" <<'DCONF_PROFILE_EOF'
user-db:user
system-db:local
DCONF_PROFILE_EOF

# ------------------------------------------------------------
# Generate system-wide Niveth dconf database
# from the captured current desktop state.
# ------------------------------------------------------------

python3 - "$PROJECT_ROOT" "$ROOTFS" <<'PY'
from pathlib import Path
import sys

project_root = Path(sys.argv[1])
rootfs = Path(sys.argv[2])

defaults = project_root / "desktop/defaults/dconf"
output = rootfs / "etc/dconf/db/local.d/00-niveth-defaults"

sources = [
    ("org-gnome-desktop-background.dconf", "org/gnome/desktop/background"),
    ("org-gnome-desktop-interface.dconf", "org/gnome/desktop/interface"),
    ("org-gnome-desktop-screensaver.dconf", "org/gnome/desktop/screensaver"),
    ("org-gnome-desktop-sound.dconf", "org/gnome/desktop/sound"),
    ("org-gnome-desktop-wm-preferences.dconf", "org/gnome/desktop/wm/preferences"),
    ("org-gnome-mutter.dconf", "org/gnome/mutter"),
    ("org-gnome-shell.dconf", "org/gnome/shell"),
]

result = []

for filename, root_section in sources:
    source = defaults / filename

    if not source.exists():
        raise SystemExit(f"ERROR: missing dconf default: {source}")

    current_section = None

    for raw_line in source.read_text(encoding="utf-8").splitlines():
        line = raw_line.rstrip()

        if not line:
            continue

        if line.startswith("[") and line.endswith("]"):
            section = line[1:-1]

            if section == "/":
                current_section = root_section
            else:
                clean = section.strip("/")
                current_section = (
                    f"{root_section}/{clean}"
                    if clean
                    else root_section
                )

            result.append("")
            result.append(f"[{current_section}]")
            continue

        if current_section is None:
            continue

        if "welcome-dialog-last-shown-version" in line:
            continue

        line = line.replace(
            "file:///home/modos/.local/share/niveth/wallpapers/",
            "file:///usr/share/niveth/wallpapers/"
        )

        result.append(line)

while result and not result[0].strip():
    result.pop(0)

while result and not result[-1].strip():
    result.pop()

output.write_text(
    "\n".join(result) + "\n",
    encoding="utf-8"
)

print(f"Created: {output}")
PY

# ------------------------------------------------------------
# Make sure the compiled local database is regenerated.
# ------------------------------------------------------------

if chroot "$ROOTFS" command -v dconf >/dev/null 2>&1; then
    chroot "$ROOTFS" dconf update || true
fi

# ------------------------------------------------------------
# Niveth user services
# ------------------------------------------------------------

if [[ -f "$ROOTFS/usr/lib/niveth/systemd/niveth-kitty-theme.service" ]]; then

    install -d \
        "$ROOTFS/usr/lib/systemd/user"

    cp -a \
        "$ROOTFS/usr/lib/niveth/systemd/niveth-kitty-theme.service" \
        "$ROOTFS/usr/lib/systemd/user/niveth-kitty-theme.service"

fi

if [[ -f "$ROOTFS/usr/lib/niveth/systemd/niveth-kitty-theme.timer" ]]; then

    install -d \
        "$ROOTFS/usr/lib/systemd/user"

    cp -a \
        "$ROOTFS/usr/lib/niveth/systemd/niveth-kitty-theme.timer" \
        "$ROOTFS/usr/lib/systemd/user/niveth-kitty-theme.timer"

fi

if [[ -f "$ROOTFS/usr/lib/niveth/systemd/niveth-wallpaper.service" ]]; then

    install -d \
        "$ROOTFS/usr/lib/systemd/user"

    cp -a \
        "$ROOTFS/usr/lib/niveth/systemd/niveth-wallpaper.service" \
        "$ROOTFS/usr/lib/systemd/user/niveth-wallpaper.service"

fi


if [[ -f "$ROOTFS/usr/lib/niveth/systemd/niveth-sound-effects.service" ]]; then

    install -d \
        "$ROOTFS/usr/lib/systemd/user"

    cp -a \
        "$ROOTFS/usr/lib/niveth/systemd/niveth-sound-effects.service" \
        "$ROOTFS/usr/lib/systemd/user/niveth-sound-effects.service"

fi

# Enable user units globally for newly created users.
if chroot "$ROOTFS" systemctl --version >/dev/null 2>&1; then

    chroot "$ROOTFS" systemctl --global enable \
        niveth-kitty-theme.timer >/dev/null 2>&1 || true

    chroot "$ROOTFS" systemctl --global enable \
        niveth-wallpaper.service >/dev/null 2>&1 || true

    chroot "$ROOTFS" systemctl --global enable \
        niveth-sound-effects.service >/dev/null 2>&1 || true

fi

# ------------------------------------------------------------
# Executable permissions
# ------------------------------------------------------------

find "$ROOTFS/usr/local/bin" \
    -type f \
    -exec chmod 0755 {} \; \
    2>/dev/null || true

find "$ROOTFS/usr/lib/niveth" \
    -type f \
    -name '*.py' \
    -exec chmod 0644 {} \; \
    2>/dev/null || true

# ============================================================
# 10. FINALIZATION
# ============================================================

echo "[10/10] Finalizing Niveth rootfs..."

# Application metadata
if chroot "$ROOTFS" \
    command -v update-desktop-database >/dev/null 2>&1; then

    chroot "$ROOTFS" \
        update-desktop-database \
        /usr/share/applications \
        >/dev/null 2>&1 || true
fi

# Icon cache
if chroot "$ROOTFS" \
    command -v gtk-update-icon-cache >/dev/null 2>&1; then

    chroot "$ROOTFS" \
        gtk-update-icon-cache \
        -f \
        -t \
        /usr/share/icons/hicolor \
        >/dev/null 2>&1 || true
fi

# Clean package cache.
chroot "$ROOTFS" /bin/bash -c '
    export DEBIAN_FRONTEND=noninteractive
    apt-get clean
    rm -rf /var/lib/apt/lists/*
'

echo
echo "============================================================"
echo "        Niveth rootfs created successfully"
echo "============================================================"
echo
echo "Rootfs:"
echo "  $ROOTFS"
echo
echo "Base:"
echo "  Ubuntu 26.04 LTS"
echo
echo "Desktop:"
echo "  GNOME"
echo
echo "Default Niveth extensions:"
echo "  ENABLED : niveth-dock"
echo "  ENABLED : niveth-ui-test"
echo "  ENABLED : niveth-lockscreen"
echo "  DISABLED: niveth-topbar"
echo "  DISABLED: niveth-app-refresh"
echo
echo "The ISO has NOT been created yet."
echo
