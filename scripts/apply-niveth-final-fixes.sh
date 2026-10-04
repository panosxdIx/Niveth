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
# 2. VIVALDI Niveth LIGHT / DARK
###############################################################################

VIV_SRC="$PROJECT_ROOT/desktop/defaults/vivaldi"
VIV_DST="$ROOTFS/etc/niveth/vivaldi"

mkdir -p \
    "$VIV_DST/Niveth-Light" \
    "$VIV_DST/Niveth-Dark" \
    "$ROOTFS/usr/local/bin" \
    "$ROOTFS/usr/share/applications"

if [ -f "$VIV_SRC/Niveth-Light/settings.json" ]; then
    install -m 0644 \
        "$VIV_SRC/Niveth-Light/settings.json" \
        "$VIV_DST/Niveth-Light/settings.json"
fi

if [ -f "$VIV_SRC/Niveth-Dark/settings.json" ]; then
    install -m 0644 \
        "$VIV_SRC/Niveth-Dark/settings.json" \
        "$VIV_DST/Niveth-Dark/settings.json"
fi

if [ -f "$VIV_SRC/niveth-vivaldi" ]; then
    install -m 0755 \
        "$VIV_SRC/niveth-vivaldi" \
        "$ROOTFS/usr/local/bin/niveth-vivaldi"
fi

if [ -f "$VIV_SRC/vivaldi-stable.desktop" ]; then
    install -m 0644 \
        "$VIV_SRC/vivaldi-stable.desktop" \
        "$ROOTFS/usr/share/applications/vivaldi-stable.desktop"

    python3 - "$ROOTFS/usr/share/applications/vivaldi-stable.desktop" <<'PY'
from pathlib import Path
import sys

p = Path(sys.argv[1])
s = p.read_text(encoding="utf-8")

lines = s.splitlines()

done = False
out = []

for line in lines:
    if line.startswith("Exec=") and not done:
        out.append("Exec=/usr/local/bin/niveth-vivaldi %U")
        done = True
    else:
        out.append(line)

if not done:
    out.append("Exec=/usr/local/bin/niveth-vivaldi %U")

p.write_text("\n".join(out) + "\n", encoding="utf-8")
PY
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
# 6E. VIVALDI DEFAULT PREFERENCES
###############################################################################

echo "[NIVETH FINAL FIXES] installing Vivaldi default preferences"

NIVETH_VIV_DEFAULT="$PROJECT_ROOT/desktop/defaults/vivaldi/default-preferences.json"

if [ -f "$NIVETH_VIV_DEFAULT" ]; then
    install -d -m 0755 "$ROOTFS/etc/niveth/vivaldi"
    install -m 0644 \
        "$NIVETH_VIV_DEFAULT" \
        "$ROOTFS/etc/niveth/vivaldi/default-preferences.json"

    echo "[NIVETH FINAL FIXES] Vivaldi default preferences installed"
else
    echo "[NIVETH FINAL FIXES] WARNING: Vivaldi default preferences source missing"
fi

###############################################################################
# 7. FINAL PERMISSIONS
###############################################################################

chown -R root:root \
    "$ROOTFS/etc/niveth" \
    "$ROOTFS/usr/lib/niveth/apps/niveth-app-center" \
    "$ROOTFS/usr/local/bin" \
    2>/dev/null || true

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
# 6H. VIVALDI DEFAULT PREFS SAFETY
###############################################################################

echo "[NIVETH FINAL FIXES] validating Vivaldi wrapper DEFAULT_PREFS"

VIVALDI_WRAPPER="$ROOTFS/usr/local/bin/niveth-vivaldi"

if [ -f "$VIVALDI_WRAPPER" ]; then

    if ! grep -q '^DEFAULT_PREFS=' "$VIVALDI_WRAPPER"; then

        python3 - "$VIVALDI_WRAPPER" <<'PYV'
from pathlib import Path
import re
import sys

p = Path(sys.argv[1])
s = p.read_text()

if 'DEFAULT_PREFS="$THEME_ROOT/default-preferences.json"' not in s:
    pattern = r'(^DARK_JSON="\$THEME_ROOT/Niveth-Dark/settings\.json"$)'
    s2, n = re.subn(
        pattern,
        r'\1\nDEFAULT_PREFS="$THEME_ROOT/default-preferences.json"',
        s,
        count=1,
        flags=re.MULTILINE
    )

    if n != 1:
        raise SystemExit("DARK_JSON marker missing")

    p.write_text(s2)
PYV

    fi

    if grep -q '^DEFAULT_PREFS=' "$VIVALDI_WRAPPER"; then
        echo "[NIVETH FINAL FIXES] Vivaldi DEFAULT_PREFS PASS"
    else
        echo "[NIVETH FINAL FIXES] ERROR: Vivaldi DEFAULT_PREFS missing"
        exit 1
    fi

else
    echo "[NIVETH FINAL FIXES] ERROR: Vivaldi wrapper missing"
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
# 6K. CALAMARES ALONGSIDE + VIVALDI NO-FIRST-RUN
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

echo "[NIVETH FINAL FIXES] configuring Vivaldi first-run suppression"

VIVALDI_WRAPPER="$ROOTFS/usr/local/bin/niveth-vivaldi"

if [ -f "$VIVALDI_WRAPPER" ]; then

    python3 - "$VIVALDI_WRAPPER" <<'PYV'
from pathlib import Path
import re
import sys

p = Path(sys.argv[1])
s = p.read_text(encoding="utf-8")

pattern = r'(^[ \t]*exec "\$REAL_VIVALDI")([ \t]+)(?!.*--no-first-run)(.*$)'

s2, n = re.subn(
    pattern,
    r'\1 --no-first-run \3',
    s,
    count=1,
    flags=re.MULTILINE,
)

if n == 1:
    p.write_text(s2, encoding="utf-8")
    print("[NIVETH FINAL FIXES] Vivaldi --no-first-run added")
elif "--no-first-run" in s:
    print("[NIVETH FINAL FIXES] Vivaldi --no-first-run already present")
else:
    print("[NIVETH FINAL FIXES] WARNING: Vivaldi launch line not found")
PYV

else
    echo "[NIVETH FINAL FIXES] ERROR: Vivaldi wrapper missing"
    exit 1
fi

###############################################################################
# 6F. FINAL RELEASE VALIDATION
###############################################################################

echo "[NIVETH FINAL FIXES] validating release-critical files"

if [ ! -d "$ROOTFS/usr/src" ]; then
    echo "[NIVETH FINAL FIXES] ERROR: /usr/src missing"
    exit 1
fi

if [ ! -f "$ROOTFS/etc/niveth/vivaldi/default-preferences.json" ]; then
    echo "[NIVETH FINAL FIXES] ERROR: Vivaldi default preferences missing"
    exit 1
fi

if [ ! -x "$ROOTFS/usr/local/bin/niveth-vivaldi" ]; then
    echo "[NIVETH FINAL FIXES] ERROR: Vivaldi wrapper missing"
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

echo "[NIVETH FINAL FIXES] complete"
