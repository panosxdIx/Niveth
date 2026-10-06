#!/usr/bin/env bash
set -Eeuo pipefail

ROOTFS="${1:?ROOTFS argument missing}"
SOURCE_HOME="${2:?SOURCE_HOME argument missing}"
PROJECT_ROOT="${3:?PROJECT_ROOT argument missing}"

echo "[NIVETH FINAL FIXES] ROOTFS=$ROOTFS"

[ -d "$ROOTFS" ] || {
    echo "ERROR: rootfs missing: $ROOTFS"
    exit 1
}

###############################################################################
# 1. APP CENTER
###############################################################################

APP_SRC="$SOURCE_HOME/.local/share/niveth-app-center"
APP_DST="$ROOTFS/usr/lib/niveth/apps/niveth-app-center"

if [ -d "$APP_SRC" ]; then
    mkdir -p "$APP_DST"

    rsync -a --delete \
        --exclude='backups' \
        --exclude='__pycache__' \
        "$APP_SRC/" \
        "$APP_DST/"

    chown -R root:root "$APP_DST"

    chmod 755 \
        "$APP_DST/niveth-app-center.py" \
        "$APP_DST/niveth-app-engine.py" \
        2>/dev/null || true
fi

###############################################################################
# 2. BRAVE Niveth LIGHT / DARK + NEW TAB
###############################################################################

BRAVE_SRC="$PROJECT_ROOT/desktop/defaults/brave"
BRAVE_DST="$ROOTFS/etc/niveth/brave"
BRAVE_SKEL="$ROOTFS/etc/skel"

mkdir -p     "$BRAVE_DST"     "$ROOTFS/usr/local/bin"     "$ROOTFS/usr/share/applications"     "$BRAVE_SKEL/.local/share/niveth/brave"     "$BRAVE_SKEL/.config/BraveSoftware/Brave-Browser"

# Niveth New Tab
if [ -d "$BRAVE_SRC/newtab" ]; then
    mkdir -p "$BRAVE_SKEL/.local/share/niveth/brave/newtab"

    rsync -a --delete         "$BRAVE_SRC/newtab/"         "$BRAVE_SKEL/.local/share/niveth/brave/newtab/"

    echo "[NIVETH FINAL FIXES] Brave Niveth New Tab installed"
else
    echo "[NIVETH FINAL FIXES] ERROR: Brave New Tab source missing"
    exit 1
fi

# Niveth Brave profile
if [ -d "$BRAVE_SRC/profile" ]; then
    rsync -a --delete         "$BRAVE_SRC/profile/"         "$BRAVE_SKEL/.config/BraveSoftware/Brave-Browser/"

    echo "[NIVETH FINAL FIXES] Brave profile installed"
else
    echo "[NIVETH FINAL FIXES] WARNING: Brave profile source missing"
fi

# Brave launcher
if [ -f "$BRAVE_SRC/niveth-brave" ]; then
    install -m 0755         "$BRAVE_SRC/niveth-brave"         "$ROOTFS/usr/local/bin/niveth-brave"
else
    echo "[NIVETH FINAL FIXES] ERROR: Brave launcher source missing"
    exit 1
fi

# Brave desktop entry
if [ -f "$BRAVE_SRC/brave-browser.desktop" ]; then
    install -m 0644         "$BRAVE_SRC/brave-browser.desktop"         "$ROOTFS/usr/share/applications/brave-browser.desktop"
else
    echo "[NIVETH FINAL FIXES] ERROR: Brave desktop entry source missing"
    exit 1
fi

###############################################################################
# 3. LIVE USER INPUT GROUP
###############################################################################

GROUP_FILE="$ROOTFS/etc/group"

if [ -f "$GROUP_FILE" ]; then
    python3 - "$GROUP_FILE" <<'PY'
from pathlib import Path
import sys

p = Path(sys.argv[1])
lines = p.read_text(encoding="utf-8").splitlines()

out = []
found = False

for line in lines:
    fields = line.split(":", 3)

    if len(fields) == 4 and fields[0] == "input":
        members = [
            x for x in fields[3].split(",")
            if x and x not in {"modos", "niveth"}
        ]

        if "niveth" not in members:
            members.append("niveth")

        fields[3] = ",".join(members)
        line = ":".join(fields)
        found = True

    out.append(line)

if not found:
    raise SystemExit(
        "ERROR: input group does not exist in rootfs"
    )

p.write_text("\n".join(out) + "\n", encoding="utf-8")
PY
fi

###############################################################################
# 4. GNOME — KEEP Niveth UI / DISABLE UBUNTU DOCK
###############################################################################

mkdir -p "$ROOTFS/etc/dconf/db/local.d"

cat > "$ROOTFS/etc/dconf/db/local.d/99-niveth-final" <<'DCONF'
[org/gnome/shell]
disabled-extensions=['ubuntu-dock@ubuntu.com','niveth-topbar@nivethos']
DCONF

if [ -x "$ROOTFS/usr/bin/dconf" ]; then
    chroot "$ROOTFS" /usr/bin/dconf update >/dev/null 2>&1 || true
fi

###############################################################################
# 5. MECHVIBES / MOUSE SOUND INPUT ACCESS
###############################################################################

mkdir -p \
    "$ROOTFS/usr/local/bin" \
    "$ROOTFS/etc/xdg/autostart" \
    "$ROOTFS/etc/udev/rules.d" \
    "$ROOTFS/etc/skel/.config/autostart"

if [ -x "$ROOTFS/usr/bin/mechvibes-dx" ]; then

    if [ -x "$ROOTFS/usr/bin/sg" ]; then
        cat > "$ROOTFS/usr/local/bin/niveth-start-mechvibes-input" <<'SCRIPT'
#!/usr/bin/env bash
exec /usr/bin/sg input /usr/bin/mechvibes-dx "$@"
SCRIPT

        chmod 755 \
            "$ROOTFS/usr/local/bin/niveth-start-mechvibes-input"

        cat > "$ROOTFS/etc/xdg/autostart/mechvibes-dx-niveth.desktop" <<'DESKTOP'
[Desktop Entry]
Type=Application
Name=Niveth Keyboard Sounds
Comment=Niveth keyboard sound engine
Exec=/usr/local/bin/niveth-start-mechvibes-input
Terminal=false
NoDisplay=true
X-GNOME-Autostart-enabled=true
DESKTOP

        cp -f \
            "$ROOTFS/etc/xdg/autostart/mechvibes-dx-niveth.desktop" \
            "$ROOTFS/etc/skel/.config/autostart/mechvibes-dx-niveth.desktop"
    fi
fi

MOUSE_DAEMON=""

for candidate in \
    "$ROOTFS/usr/local/bin/niveth-sound-effects.py" \
    "$ROOTFS/usr/local/bin/niveth-mouse-sounds.py" \
    "$ROOTFS/usr/lib/niveth/niveth-sound-effects.py"
do
    if [ -f "$candidate" ]; then
        MOUSE_DAEMON="$candidate"
        break
    fi
done

if [ -n "$MOUSE_DAEMON" ] && [ -x "$ROOTFS/usr/bin/sg" ]; then

    DAEMON_PATH="${MOUSE_DAEMON#"$ROOTFS"}"

    cat > "$ROOTFS/usr/local/bin/niveth-start-mouse-sounds-input" <<SCRIPT
#!/usr/bin/env bash
exec /usr/bin/python3 "$DAEMON_PATH" "\$@"
SCRIPT

    chmod 755 \
        "$ROOTFS/usr/local/bin/niveth-start-mouse-sounds-input"

    cat > "$ROOTFS/etc/xdg/autostart/niveth-mouse-sounds.desktop" <<'DESKTOP'
[Desktop Entry]
Type=Application
Name=Niveth Mouse Sounds
Comment=Niveth mouse click sound effects
Exec=/usr/local/bin/niveth-start-mouse-sounds-input
Terminal=false
NoDisplay=true
X-GNOME-Autostart-enabled=true
DESKTOP

    cp -f \
        "$ROOTFS/etc/xdg/autostart/niveth-mouse-sounds.desktop" \
        "$ROOTFS/etc/skel/.config/autostart/niveth-mouse-sounds.desktop"
fi

cat > "$ROOTFS/etc/udev/rules.d/90-niveth-sound-input.rules" <<'UDEV'
SUBSYSTEM=="input", KERNEL=="event*", ENV{ID_INPUT_MOUSE}=="1", TAG+="uaccess"
SUBSYSTEM=="input", KERNEL=="event*", ENV{ID_INPUT_KEYBOARD}=="1", TAG+="uaccess"
UDEV

###############################################################################
# 6. CLEAN OLD DIRECT SOUND AUTOSTART DUPLICATES
###############################################################################

rm -f \
    "$ROOTFS/etc/skel/.config/autostart/mechvibes-dx.desktop" \
    "$ROOTFS/etc/skel/.config/autostart/mechvibes.desktop" \
    "$ROOTFS/etc/skel/.config/autostart/niveth-sound-effects.desktop" \
    2>/dev/null || true

###############################################################################
# 6B. REMOVE TUBEFEEDER TRACES
###############################################################################

# TubeFeeder is intentionally not part of Niveth.
# The application itself may already be uninstalled while Flatpak's
# local repo/appstream metadata still contains refs/icons. Since this
# rootfs is the captured Live image, remove those stale traces as well.

echo "[NIVETH FINAL FIXES] Removing TubeFeeder traces..."

if [ -d "$ROOTFS/var/lib/flatpak" ]; then
    find "$ROOTFS/var/lib/flatpak" \
        -iname '*tubefeeder*' \
        -print \
        -exec rm -rf -- {} + \
        2>/dev/null || true
fi

find "$ROOTFS/usr/share/applications" \
    "$ROOTFS/etc/skel/.config/autostart" \
    "$ROOTFS/home" \
    -iname '*tubefeeder*' \
    -print \
    -exec rm -rf -- {} + \
    2>/dev/null || true

# Remove exact Flatpak App ID references even when a path does not
# contain the application name in every component.
if [ -d "$ROOTFS/var/lib/flatpak" ]; then
    while IFS= read -r f; do
        [ -n "$f" ] || continue
        rm -f -- "$f" 2>/dev/null || true
    done < <(
        grep -RIl \
            'de\.schmidhuberj\.tubefeeder' \
            "$ROOTFS/var/lib/flatpak" \
            2>/dev/null || true
    )
fi

echo "[NIVETH FINAL FIXES] TubeFeeder traces removed"

###############################################################################
# 6C. RELEASE ARTIFACT CLEANUP
###############################################################################

echo "[NIVETH FINAL FIXES] cleaning development backup artifacts"

for CLEAN_DIR in \
    "$ROOTFS/usr/lib/niveth" \
    "$ROOTFS/usr/share/niveth"
do
    if [ -d "$CLEAN_DIR" ]; then
        find "$CLEAN_DIR" -type f \( \
            -name '*.before-*' -o \
            -name '*.backup*' -o \
            -name '*.bak' -o \
            -name '*.orig' -o \
            -name '*~' \
        \) -print -delete 2>/dev/null || true

        find "$CLEAN_DIR" -type d \( \
            -name 'backups' -o \
            -name '__pycache__' -o \
            -name '.pytest_cache' \
        \) -print -exec rm -rf -- {} + 2>/dev/null || true
    fi
done

###############################################################################
# 6D. SNAPD REQUIRED DIRECTORIES
###############################################################################

install -d -m 0755 "$ROOTFS/usr/src"
echo "[NIVETH FINAL FIXES] /usr/src present for snapd"

###############################################################################
# 6E. BRAVE DEFAULT CHECKS
###############################################################################

echo "[NIVETH FINAL FIXES] validating Brave assets"

if [ ! -x "$ROOTFS/usr/local/bin/niveth-brave" ]; then
    echo "[NIVETH FINAL FIXES] ERROR: Brave wrapper missing"
    exit 1
fi

if [ ! -f "$ROOTFS/usr/share/applications/brave-browser.desktop" ]; then
    echo "[NIVETH FINAL FIXES] ERROR: Brave desktop entry missing"
    exit 1
fi

if [ ! -f "$ROOTFS/etc/skel/.local/share/niveth/brave/newtab/manifest.json" ]; then
    echo "[NIVETH FINAL FIXES] ERROR: Brave Niveth New Tab missing"
    exit 1
fi

echo "[NIVETH FINAL FIXES] Brave assets PASS"

###############################################################################
# 6G. CALAMARES SHOW QML
###############################################################################

echo "[NIVETH FINAL FIXES] installing Calamares show.qml"

NIVETH_CAL_DIR="$PROJECT_ROOT/installer/branding/niveth"

if [ -f "$NIVETH_CAL_DIR/show.qml" ]; then
    install -d -m 0755 \
        "$ROOTFS/usr/share/calamares/branding/niveth"

    install -m 0644 \
        "$NIVETH_CAL_DIR/show.qml" \
        "$ROOTFS/usr/share/calamares/branding/niveth/show.qml"

    echo "[NIVETH FINAL FIXES] Calamares show.qml installed"
else
    echo "[NIVETH FINAL FIXES] ERROR: source show.qml missing"
    exit 1
fi


###############################################################################
# 6I. CALAMARES SQUID IMAGE
###############################################################################

echo "[NIVETH FINAL FIXES] installing Calamares squid.png"

CALAMAres_DIR="$PROJECT_ROOT/installer/branding/niveth"
CALAMAres_TARGET="$ROOTFS/usr/share/calamares/branding/niveth/squid.png"

if [ -f "$CALAMAres_DIR/squid.png" ]; then

    install -d -m 0755 \
        "$ROOTFS/usr/share/calamares/branding/niveth"

    install -m 0644 \
        "$CALAMAres_DIR/squid.png" \
        "$CALAMAres_TARGET"

    echo "[NIVETH FINAL FIXES] Calamares squid.png installed"

else
    echo "[NIVETH FINAL FIXES] ERROR: source squid.png missing"
    exit 1
fi


###############################################################################
# 6J. REMOVE UBUNTU DOCK EXTENSION
###############################################################################

echo "[NIVETH FINAL FIXES] removing Ubuntu Dock extension"

UBUNTU_DOCK_DIR="$ROOTFS/usr/share/gnome-shell/extensions/ubuntu-dock@ubuntu.com"

if [ -d "$UBUNTU_DOCK_DIR" ]; then
    rm -rf -- "$UBUNTU_DOCK_DIR"
    echo "[NIVETH FINAL FIXES] Ubuntu Dock extension removed"
else
    echo "[NIVETH FINAL FIXES] Ubuntu Dock extension already absent"
fi

if [ -d "$UBUNTU_DOCK_DIR" ]; then
    echo "[NIVETH FINAL FIXES] ERROR: Ubuntu Dock still present"
    exit 1
fi


###############################################################################
# 6K. CALAMARES ALONGSIDE + BRAVE NO-FIRST-RUN
###############################################################################

echo "[NIVETH FINAL FIXES] configuring Calamares alongside installation"

PARTITION_CONF="$ROOTFS/etc/calamares/modules/partition.conf"

if [ -f "$PARTITION_CONF" ]; then

    if grep -qE '^[[:space:]]*requiredStorage[[:space:]]*:' "$PARTITION_CONF"; then
        sed -i -E \
            's/^[[:space:]]*requiredStorage[[:space:]]*:.*/requiredStorage: 5.5/' \
            "$PARTITION_CONF"
    else
        sed -i \
            '/^[[:space:]]*defaultFileSystemType:/a requiredStorage: 5.5' \
            "$PARTITION_CONF"
    fi

    echo "[NIVETH FINAL FIXES] Calamares requiredStorage=5.5"
else
    echo "[NIVETH FINAL FIXES] ERROR: partition.conf missing"
    exit 1
fi

WELCOME_CONF="$ROOTFS/etc/calamares/modules/welcome.conf"

if [ -f "$WELCOME_CONF" ]; then

    if grep -qE '^[[:space:]]*requiredStorage[[:space:]]*:' "$WELCOME_CONF"; then
        sed -i -E \
            's/^[[:space:]]*requiredStorage[[:space:]]*:.*/    requiredStorage: 5.5/' \
            "$WELCOME_CONF"
    else
        sed -i \
            '/^[[:space:]]*requiredRam:/i\    requiredStorage: 5.5' \
            "$WELCOME_CONF"
    fi

    sed -i \
        '/^[[:space:]]*-[[:space:]]*storage[[:space:]]*$/d' \
        "$WELCOME_CONF"

    echo "[NIVETH FINAL FIXES] Welcome requiredStorage=5.5"
    echo "[NIVETH FINAL FIXES] Welcome storage check remains disabled"
else
    echo "[NIVETH FINAL FIXES] ERROR: welcome.conf missing"
    exit 1
fi

echo "[NIVETH FINAL FIXES] Brave first-run suppression handled by Niveth launcher"

###############################################################################
# 6F. FINAL RELEASE VALIDATION
###############################################################################

echo "[NIVETH FINAL FIXES] validating release-critical files"

if [ ! -d "$ROOTFS/usr/src" ]; then
    echo "[NIVETH FINAL FIXES] ERROR: /usr/src missing"
    exit 1
fi

if [ ! -x "$ROOTFS/usr/local/bin/niveth-brave" ]; then
    echo "[NIVETH FINAL FIXES] ERROR: Brave wrapper missing"
    exit 1
fi

if [ ! -f "$ROOTFS/usr/share/applications/brave-browser.desktop" ]; then
    echo "[NIVETH FINAL FIXES] ERROR: Brave desktop entry missing"
    exit 1
fi

if [ ! -f "$ROOTFS/etc/skel/.local/share/niveth/brave/newtab/manifest.json" ]; then
    echo "[NIVETH FINAL FIXES] ERROR: Brave Niveth New Tab missing"
    exit 1
fi

if [ ! -f "$ROOTFS/usr/share/calamares/branding/niveth/show.qml" ]; then
    echo "[NIVETH FINAL FIXES] ERROR: Calamares show.qml missing"
    exit 1
fi

if [ ! -f "$ROOTFS/usr/share/calamares/branding/niveth/squid.png" ]; then
    echo "[NIVETH FINAL FIXES] ERROR: Calamares squid.png missing"
    exit 1
fi

if [ -d "$ROOTFS/usr/share/gnome-shell/extensions/ubuntu-dock@ubuntu.com" ]; then
    echo "[NIVETH FINAL FIXES] ERROR: Ubuntu Dock extension still present"
    exit 1
fi

echo "[NIVETH FINAL FIXES] release-critical validation PASS"

# 6L. FIX PORTABLE Niveth SYSTEMD USER SYMLINKS
echo "[NIVETH FINAL FIXES] fixing portable Niveth systemd user symlinks"

WALLPAPER_SERVICE="$ROOTFS/etc/skel/.config/systemd/user/niveth-wallpaper.service"
WALLPAPER_WANTS="$ROOTFS/etc/skel/.config/systemd/user/graphical-session.target.wants"

if [ -f "$WALLPAPER_SERVICE" ]; then
    mkdir -p "$WALLPAPER_WANTS"
    rm -f "$WALLPAPER_WANTS/niveth-wallpaper.service"
    ln -s "../niveth-wallpaper.service" \
        "$WALLPAPER_WANTS/niveth-wallpaper.service"
    echo "[NIVETH FINAL FIXES] wallpaper symlink fixed"
fi

KITTY_TIMER="$ROOTFS/etc/skel/.config/systemd/user/niveth-kitty-theme.timer"
KITTY_WANTS="$ROOTFS/etc/skel/.config/systemd/user/timers.target.wants"

if [ -f "$KITTY_TIMER" ]; then
    mkdir -p "$KITTY_WANTS"
    rm -f "$KITTY_WANTS/niveth-kitty-theme.timer"
    ln -s "../niveth-kitty-theme.timer" \
        "$KITTY_WANTS/niveth-kitty-theme.timer"
    echo "[NIVETH FINAL FIXES] kitty timer symlink fixed"
fi

###############################################################################

###############################################################################
# 6N. REMOVE KDUMP FROM ISO
###############################################################################

echo "[NIVETH FINAL FIXES] removing kdump from ISO"

# Do not run apt/dpkg maintainer scripts inside this snapshot.
# The snapshot does not have /dev, /proc and /sys mounted at this stage.
# Disable kdump and remove its generated payload instead.
mkdir -p "$ROOTFS/etc/default"

cat > "$ROOTFS/etc/default/kdump-tools" <<'EOF'
USE_KDUMP=0
KDUMP_KERNELVER=
KDUMP_COREDIR="/var/crash"
EOF

rm -rf \
    "$ROOTFS/var/lib/kdump" \
    "$ROOTFS/etc/kdump"

# Remove any generated kdump initramfs links/files if present.
find "$ROOTFS/var/lib" -maxdepth 2 \
    \( -name 'initrd.img-kdump*' -o -name 'vmlinuz-kdump*' \) \
    -delete 2>/dev/null || true

# Remove crashkernel boot parameters from GRUB configuration.
find "$ROOTFS/etc/default" "$ROOTFS/etc/default/grub.d" \
    -type f -print 2>/dev/null | while read -r f; do
    sed -i -E 's/[[:space:]]*crashkernel=[^[:space:]"'\'']+//g' "$f"
done

if [ -d "$ROOTFS/var/lib/kdump" ]; then
    echo "[NIVETH FINAL FIXES] ERROR: /var/lib/kdump still exists"
    exit 1
fi

grep -q '^USE_KDUMP=0$' "$ROOTFS/etc/default/kdump-tools"

echo "[NIVETH FINAL FIXES] kdump removed from ISO"
echo "[NIVETH FINAL FIXES] kdump cleanup PASS"

# 6M. BRAVE SYSTEMD LIGHT / DARK TIMERS
###############################################################################

echo "[NIVETH FINAL FIXES] installing Brave systemd theme timers"

BRAVE_SYSTEMD_SRC="$PROJECT_ROOT/desktop/defaults/brave/systemd/user"
BRAVE_SYSTEMD_DST="$ROOTFS/etc/skel/.config/systemd/user"
BRAVE_TIMER_WANTS="$BRAVE_SYSTEMD_DST/timers.target.wants"

mkdir -p \
    "$BRAVE_SYSTEMD_DST" \
    "$BRAVE_TIMER_WANTS"

for unit in \
    niveth-brave-light.service \
    niveth-brave-light.timer \
    niveth-brave-dark.service \
    niveth-brave-dark.timer
do
    if [ ! -f "$BRAVE_SYSTEMD_SRC/$unit" ]; then
        echo "[NIVETH FINAL FIXES] ERROR: Brave systemd unit missing: $unit"
        exit 1
    fi

    install -m 0644 \
        "$BRAVE_SYSTEMD_SRC/$unit" \
        "$BRAVE_SYSTEMD_DST/$unit"

    echo "[NIVETH FINAL FIXES] installed $unit"
done

# Timer activation links
rm -f \
    "$BRAVE_TIMER_WANTS/niveth-brave-light.timer" \
    "$BRAVE_TIMER_WANTS/niveth-brave-dark.timer"

ln -s \
    "../niveth-brave-light.timer" \
    "$BRAVE_TIMER_WANTS/niveth-brave-light.timer"

ln -s \
    "../niveth-brave-dark.timer" \
    "$BRAVE_TIMER_WANTS/niveth-brave-dark.timer"

echo "[NIVETH FINAL FIXES] Brave theme timers enabled in skel"

echo "[NIVETH FINAL FIXES] validating Brave systemd files"

for unit in \
    niveth-brave-light.service \
    niveth-brave-light.timer \
    niveth-brave-dark.service \
    niveth-brave-dark.timer
do
    if [[ ! -f "$ROOTFS/etc/skel/.config/systemd/user/$unit" ]]; then
        echo "[NIVETH FINAL FIXES] ERROR: missing Brave systemd unit: $unit"
        exit 1
    fi
done

for timer in \
    niveth-brave-light.timer \
    niveth-brave-dark.timer
do
    if [[ ! -L "$ROOTFS/etc/skel/.config/systemd/user/timers.target.wants/$timer" ]]; then
        echo "[NIVETH FINAL FIXES] ERROR: Brave timer not enabled: $timer"
        exit 1
    fi
done

echo "[NIVETH FINAL FIXES] Brave systemd validation PASS"

###############################################################################
# 7. Niveth LICENSE / COPYRIGHT / SOURCE COMPLIANCE
###############################################################################

echo "[NIVETH FINAL FIXES] installing Niveth licensing documents"

NIVETH_DOC="$ROOTFS/usr/share/doc/niveth"

install -d -m 0755 "$NIVETH_DOC"
install -d -m 0755 "$NIVETH_DOC/LICENSES"

install -m 0644 \
    "$PROJECT_ROOT/LICENSE" \
    "$NIVETH_DOC/LICENSE"

install -m 0644 \
    "$PROJECT_ROOT/COPYRIGHT.md" \
    "$NIVETH_DOC/COPYRIGHT.md"

install -m 0644 \
    "$PROJECT_ROOT/BRANDING-NOTICE.md" \
    "$NIVETH_DOC/BRANDING-NOTICE.md"

install -m 0644 \
    "$PROJECT_ROOT/THIRD-PARTY-NOTICES.md" \
    "$NIVETH_DOC/THIRD-PARTY-NOTICES.md"

install -m 0644 \
    "$PROJECT_ROOT/SOURCE-CODE.md" \
    "$NIVETH_DOC/SOURCE-CODE.md"

install -m 0644 \
    "$PROJECT_ROOT/LICENSES/GPL-3.0.txt" \
    "$NIVETH_DOC/LICENSES/GPL-3.0.txt"

if [[ -x "$PROJECT_ROOT/scripts/generate-license-inventory.sh" ]]; then
    "$PROJECT_ROOT/scripts/generate-license-inventory.sh" \
        "$ROOTFS"
fi

if [[ -x "$PROJECT_ROOT/scripts/create-niveth-source-archive.sh" ]]; then
    "$PROJECT_ROOT/scripts/create-niveth-source-archive.sh" \
        "$PROJECT_ROOT" \
        "$ROOTFS"
fi

chown -R root:root "$NIVETH_DOC" "$ROOTFS/usr/share/src"

echo "[NIVETH FINAL FIXES] licensing/source compliance files installed"

# Remove stale corresponding-source archives from older Niveth versions.
# Keep only the archive matching the current release version.
find "$ROOTFS/usr/share/src"     -maxdepth 1     -type f     -name 'niveth-linux-*-corresponding-source.tar.gz'     ! -name 'niveth-linux-0.1.1-corresponding-source.tar.gz'     -delete 2>/dev/null || true

echo "[NIVETH FINAL FIXES] validating licensing files"

for legal_file in \
    "$ROOTFS/usr/share/doc/niveth/LICENSE" \
    "$ROOTFS/usr/share/doc/niveth/COPYRIGHT.md" \
    "$ROOTFS/usr/share/doc/niveth/BRANDING-NOTICE.md" \
    "$ROOTFS/usr/share/doc/niveth/THIRD-PARTY-NOTICES.md" \
    "$ROOTFS/usr/share/doc/niveth/SOURCE-CODE.md" \
    "$ROOTFS/usr/share/doc/niveth/LICENSES/GPL-3.0.txt" \
    "$ROOTFS/usr/share/doc/niveth/license-inventory.tsv"
do
    if [[ ! -f "$legal_file" ]]; then
        echo "[NIVETH FINAL FIXES] ERROR: missing legal file: $legal_file"
        exit 1
    fi
done

if ! find "$ROOTFS/usr/share/src" \
    -maxdepth 1 \
    -type f \
    -name 'niveth-linux-*-corresponding-source.tar.gz' \
    -print -quit 2>/dev/null | grep -q .
then
    echo "[NIVETH FINAL FIXES] ERROR: corresponding source archive missing"
    exit 1
fi

echo "[NIVETH FINAL FIXES] licensing validation PASS"

echo "[NIVETH FINAL FIXES] complete"
