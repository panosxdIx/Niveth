#!/usr/bin/env bash

set -Eeuo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ROOTFS="$PROJECT_ROOT/build/rootfs"

echo
echo "============================================================"
echo "             NIVETH ROOTFS VALIDATION"
echo "============================================================"
echo

if [[ ! -d "$ROOTFS" ]]; then
    echo "ERROR: rootfs does not exist:"
    echo "  $ROOTFS"
    exit 1
fi

FAILURES=0

ok() {
    echo "OK: $*"
}

warn() {
    echo "WARNING: $*"
}

fail() {
    echo "ERROR: $*"
    FAILURES=$((FAILURES + 1))
}

echo "=== SIZE ==="
du -sh "$ROOTFS"

echo
echo "=== MOUNTS ==="

if findmnt -R "$ROOTFS" 2>/dev/null | grep -q .; then
    warn "rootfs still has mounted filesystems."
    findmnt -R "$ROOTFS" 2>/dev/null || true
else
    ok "no mounts inside rootfs."
fi

echo
echo "=== DCONF FILES ==="

for path in \
    "$ROOTFS/etc/dconf/profile/user" \
    "$ROOTFS/etc/dconf/db/local.d/00-niveth-defaults"
do
    if [[ -f "$path" ]]; then
        ok "$path"
    else
        fail "missing $path"
    fi
done

echo
echo "--- dconf profile ---"
cat "$ROOTFS/etc/dconf/profile/user" 2>/dev/null || true

echo
echo "--- Niveth extension defaults ---"

ENABLED_LINE="$(
    grep '^enabled-extensions=' \
        "$ROOTFS/etc/dconf/db/local.d/00-niveth-defaults" \
        2>/dev/null || true
)"

DISABLED_LINE="$(
    grep '^disabled-extensions=' \
        "$ROOTFS/etc/dconf/db/local.d/00-niveth-defaults" \
        2>/dev/null || true
)"

echo "$DISABLED_LINE"
echo "$ENABLED_LINE"

echo
echo "=== EXPECTED NIVETH STATE ==="

EXPECTED_ENABLED=(
    "niveth-dock@nivethos"
    "niveth-ui-test@nivethos"
    "niveth-lockscreen@nivethos"
)

EXPECTED_DISABLED=(
    "niveth-topbar@nivethos"
    "niveth-app-refresh@nivethos"
    "ubuntu-dock@ubuntu.com"
)

for ext in "${EXPECTED_ENABLED[@]}"; do
    if grep -Fq "$ext" <<< "$ENABLED_LINE"; then
        ok "enabled default: $ext"
    else
        fail "expected enabled extension missing from dconf: $ext"
    fi
done

for ext in "${EXPECTED_DISABLED[@]}"; do
    if grep -Fq "$ext" <<< "$DISABLED_LINE"; then
        ok "disabled default: $ext"
    else
        fail "expected disabled extension missing from dconf: $ext"
    fi
done

echo
echo "=== ENABLED EXTENSIONS EXISTENCE ==="

ROOTFS_EXT_DIR="$ROOTFS/usr/share/gnome-shell/extensions"

if [[ ! -d "$ROOTFS_EXT_DIR" ]]; then
    fail "GNOME extension directory missing: $ROOTFS_EXT_DIR"
else
    # Extract quoted extension IDs from enabled-extensions.
    ENABLED_IDS="$(
        printf '%s\n' "$ENABLED_LINE" |
        sed \
            -e 's/^enabled-extensions=//' \
            -e "s/[][]//g" \
            -e "s/'/ /g" |
        tr ',' '\n' |
        sed 's/^ *//;s/ *$//' |
        sed '/^$/d'
    )"

    while IFS= read -r ext; do
        [[ -z "$ext" ]] && continue

        if [[ -d "$ROOTFS_EXT_DIR/$ext" ]]; then
            ok "enabled extension installed: $ext"
        else
            fail "enabled extension is NOT installed in rootfs: $ext"
        fi
    done <<< "$ENABLED_IDS"
fi

echo
echo "=== Niveth extension directories ==="

EXTENSIONS=(
    "niveth-dock@nivethos"
    "niveth-ui-test@nivethos"
    "niveth-lockscreen@nivethos"
    "niveth-topbar@nivethos"
    "niveth-app-refresh@nivethos"
    "window-gap@amirhosseinkarimi.github.io"
    "rounded-windows@marcosgt.github.io"
)

for ext in "${EXTENSIONS[@]}"; do
    if [[ -d "$ROOTFS_EXT_DIR/$ext" ]]; then
        ok "$ext"
    else
        fail "missing extension directory: $ext"
    fi
done

echo
echo "=== FAVORITES ==="

grep '^favorite-apps=' \
    "$ROOTFS/etc/dconf/db/local.d/00-niveth-defaults" \
    2>/dev/null || true

for launcher in \
    org.niveth.Files.desktop \
    com.niveth.Notes.desktop \
    com.niveth.AppCenter.desktop \
    niveth-terminal.desktop \
    niveth-ptyxis.desktop \
    vivaldi-stable.desktop \
    kitty.desktop \
    org.kde.okular.desktop
do
    if [[ -f "$ROOTFS/usr/share/applications/$launcher" ]]; then
        ok "launcher: $launcher"
    else
        warn "favorite launcher not installed in rootfs: $launcher"
    fi
done

echo
echo "=== WALLPAPER ==="

grep -E \
    '^picture-uri(-dark)?=' \
    "$ROOTFS/etc/dconf/db/local.d/00-niveth-defaults" \
    2>/dev/null || true

if grep -RIl \
    "/home/modos/.local/share/niveth/wallpapers" \
    "$ROOTFS/etc/dconf/db/local.d" \
    >/dev/null 2>&1
then
    fail "personal /home/modos wallpaper path remains in system dconf."
else
    ok "no personal wallpaper path in system dconf."
fi

WALLPAPER_COUNT="$(
    find "$ROOTFS/usr/share/niveth/wallpapers" \
        -type f \
        2>/dev/null |
        wc -l
)"

if [[ "$WALLPAPER_COUNT" -eq 9 ]]; then
    ok "all 9 Niveth wallpapers installed."
else
    fail "expected 9 wallpapers, found $WALLPAPER_COUNT."
fi

echo
echo "=== Niveth Files ICON ==="

if [[ -f "$ROOTFS/usr/share/icons/hicolor/scalable/apps/org.niveth.Files.svg" ]]; then
    ok "org.niveth.Files.svg"
else
    fail "org.niveth.Files.svg missing."
fi

echo
echo "=== PACKAGES ==="

PACKAGES=(
    dconf-service
    dconf-cli
    gnome-shell
    kitty
    vivaldi-stable
    calamares
    casper
    linux-generic
    grub-efi-amd64
    grub-efi-amd64-bin
    grub-pc-bin
)

for pkg in "${PACKAGES[@]}"; do
    if chroot "$ROOTFS" dpkg-query \
        -W \
        -f='${Status}' \
        "$pkg" \
        2>/dev/null |
        grep -q "install ok installed"
    then

        version="$(
            chroot "$ROOTFS" dpkg-query \
                -W \
                -f='${Version}' \
                "$pkg" \
                2>/dev/null
        )"

        ok "$pkg $version"
    else
        fail "package missing: $pkg"
    fi
done

echo
echo "=== DCONF COMPILED DATABASE ==="

if [[ -f "$ROOTFS/etc/dconf/db/local" ]]; then
    ok "/etc/dconf/db/local exists."
else
    fail "/etc/dconf/db/local is missing."
fi

echo
echo "=== KERNEL ==="

if compgen -G "$ROOTFS/boot/vmlinuz-*" >/dev/null; then
    ok "kernel present."
else
    fail "kernel missing."
fi

if compgen -G "$ROOTFS/boot/initrd.img-*" >/dev/null; then
    ok "initrd present."
else
    fail "initrd missing."
fi

echo
echo "=== GRUB EFI ==="

if [[ -f "$ROOTFS/usr/lib/grub/x86_64-efi/modinfo.sh" ]]; then
    ok "GRUB x86_64-efi modules present."
else
    warn "GRUB x86_64-efi modinfo.sh not found."
fi

echo
echo "============================================================"

if [[ "$FAILURES" -eq 0 ]]; then
    echo "          ROOTFS VALIDATION: PASSED"
else
    echo "          ROOTFS VALIDATION: FAILED"
    echo "          Failures: $FAILURES"
fi

echo "============================================================"
echo

exit "$FAILURES"
