#!/usr/bin/env bash

set -u

# Rootfs operations require root privileges.
# Re-exec through sudo automatically when called by the builder
# or manually as a normal user.
if [ "${EUID:-$(id -u)}" -ne 0 ]; then
    exec sudo "$0" "$@"
fi

ROOTFS="${1:?ROOTFS argument missing}"
PROJECT_ROOT="${2:?PROJECT_ROOT argument missing}"

MECH_DEB="$PROJECT_ROOT/test-mechvibes/mechvibes-dx.deb"
SOUND_SRC="$PROJECT_ROOT/desktop/sound"

fail_count=0

echo
echo "[NIVETH SOUND] ROOTFS=$ROOTFS"

if [ ! -d "$ROOTFS" ]; then
    echo "[FAIL] rootfs missing: $ROOTFS"
    exit 1
fi

echo
echo "=== MECHVIBESDX ==="

if [ -f "$MECH_DEB" ]; then

    INSTALLED="$(
        chroot "$ROOTFS" dpkg-query \
            -W \
            -f='${Status}' \
            mechvibes-dx 2>/dev/null
    )"

    case "$INSTALLED" in
        *"install ok installed"*)
            echo "[PASS] mechvibes-dx already installed"
            ;;
        *)
            echo "[INFO] Installing local MechVibesDX package..."

            cp -f \
                "$MECH_DEB" \
                "$ROOTFS/tmp/mechvibes-dx.deb"

            echo "[INFO] First installation attempt..."

            chroot "$ROOTFS" \
                env DEBIAN_FRONTEND=noninteractive \
                apt-get install -y \
                /tmp/mechvibes-dx.deb

            rc=$?

            if [ "$rc" -ne 0 ]; then
                echo "[WARN] First MechVibes installation failed."
                echo "[INFO] Running apt-get update and retrying..."

                chroot "$ROOTFS" \
                    env DEBIAN_FRONTEND=noninteractive \
                    apt-get update

                chroot "$ROOTFS" \
                    env DEBIAN_FRONTEND=noninteractive \
                    apt-get install -y \
                    /tmp/mechvibes-dx.deb

                rc=$?
            fi

            rm -f "$ROOTFS/tmp/mechvibes-dx.deb"

            if [ "$rc" -eq 0 ]; then
                echo "[PASS] mechvibes-dx installed"
            else
                echo "[FAIL] mechvibes-dx installation failed"
                fail_count=$((fail_count + 1))
            fi
            ;;
    esac
else
    echo "[FAIL] MechVibes .deb missing"
    fail_count=$((fail_count + 1))
fi

echo
echo "=== SYSTEM-WIDE MOUSE SOUND ==="

mkdir -p \
    "$ROOTFS/usr/lib/niveth/sound-effects" \
    "$ROOTFS/usr/share/niveth/sound-effects"

if [ -f "$SOUND_SRC/niveth-sound-effects.py" ]; then

    install -m 0755 \
        "$SOUND_SRC/niveth-sound-effects.py" \
        "$ROOTFS/usr/lib/niveth/sound-effects/niveth-sound-effects.py"

    python3 \
        - "$ROOTFS/usr/lib/niveth/sound-effects/niveth-sound-effects.py" \
        <<'PY'
from pathlib import Path
import sys

p = Path(sys.argv[1])
s = p.read_text(encoding="utf-8")

s = s.replace(
    'SOUND_DIR = Path.home() / ".local" / "share" / "niveth" / "sound-effects"',
    'SOUND_DIR = Path("/usr/share/niveth/sound-effects")'
)

s = s.replace(
    'SOUND_DIR = Path.home() / ".local/share/niveth/sound-effects"',
    'SOUND_DIR = Path("/usr/share/niveth/sound-effects")'
)

p.write_text(s, encoding="utf-8")
PY

    chmod 0755 \
        "$ROOTFS/usr/lib/niveth/sound-effects/niveth-sound-effects.py"

    echo "[PASS] mouse daemon"
else
    echo "[FAIL] mouse daemon source missing"
    fail_count=$((fail_count + 1))
fi

for wav in \
    mouse-left.wav \
    mouse-middle.wav \
    mouse-right.wav
do
    if [ -f "$SOUND_SRC/sound-effects/$wav" ]; then
        install -m 0644 \
            "$SOUND_SRC/sound-effects/$wav" \
            "$ROOTFS/usr/share/niveth/sound-effects/$wav"

        echo "[PASS] $wav"
    else
        echo "[FAIL] missing $wav"
        fail_count=$((fail_count + 1))
    fi
done

echo
echo "=== INPUT GROUP ==="

python3 - "$ROOTFS/etc/group" <<'PY'
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
            if x and x != "modos"
        ]

        if "niveth" not in members:
            members.append("niveth")

        fields[3] = ",".join(members)
        line = ":".join(fields)
        found = True

    out.append(line)

if not found:
    raise SystemExit("input group does not exist")

p.write_text("\n".join(out) + "\n", encoding="utf-8")
PY

echo "[PASS] input group"

echo
echo "=== MECHVIBES WRAPPER ==="

mkdir -p \
    "$ROOTFS/usr/local/bin" \
    "$ROOTFS/etc/xdg/autostart" \
    "$ROOTFS/etc/skel/.config/autostart"

if [ -x "$ROOTFS/usr/bin/mechvibes-dx" ]; then

    cat > "$ROOTFS/usr/local/bin/niveth-start-mechvibes-input" <<'EOF'
#!/usr/bin/env bash
exec /usr/bin/sg input /usr/bin/mechvibes-dx "$@"
EOF

    chmod 0755 \
        "$ROOTFS/usr/local/bin/niveth-start-mechvibes-input"

    cat > "$ROOTFS/etc/xdg/autostart/mechvibes-dx-niveth.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=Niveth Keyboard Sounds
Comment=Niveth keyboard sound engine
Exec=/usr/local/bin/niveth-start-mechvibes-input
Terminal=false
NoDisplay=true
Hidden=false
X-GNOME-Autostart-enabled=true
EOF

    cp -f \
        "$ROOTFS/etc/xdg/autostart/mechvibes-dx-niveth.desktop" \
        "$ROOTFS/etc/skel/.config/autostart/mechvibes-dx-niveth.desktop"

    echo "[PASS] MechVibes wrapper"
    echo "[PASS] MechVibes autostart"

else

    echo "[FAIL] /usr/bin/mechvibes-dx not found"
    fail_count=$((fail_count + 1))

fi

echo
echo "=== MOUSE SOUND WRAPPER ==="

if [ -f "$ROOTFS/usr/lib/niveth/sound-effects/niveth-sound-effects.py" ]; then

    cat > "$ROOTFS/usr/local/bin/niveth-start-mouse-sounds-input" <<'EOF'
#!/usr/bin/env bash
exec /usr/bin/python3 /usr/lib/niveth/sound-effects/niveth-sound-effects.py "$@"
EOF

    chmod 0755 \
        "$ROOTFS/usr/local/bin/niveth-start-mouse-sounds-input"

    cat > "$ROOTFS/etc/xdg/autostart/niveth-mouse-sounds.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=Niveth Mouse Sounds
Comment=Niveth premium mouse click sounds
Exec=/usr/local/bin/niveth-start-mouse-sounds-input
Terminal=false
NoDisplay=true
Hidden=false
X-GNOME-Autostart-enabled=true
EOF

    cp -f \
        "$ROOTFS/etc/xdg/autostart/niveth-mouse-sounds.desktop" \
        "$ROOTFS/etc/skel/.config/autostart/niveth-mouse-sounds.desktop"

    echo "[PASS] Mouse wrapper"
    echo "[PASS] Mouse autostart"

else

    echo "[FAIL] mouse daemon not found"
    fail_count=$((fail_count + 1))

fi

echo
echo "=== UDEV ==="

mkdir -p "$ROOTFS/etc/udev/rules.d"

cat > "$ROOTFS/etc/udev/rules.d/90-niveth-sound-input.rules" <<'EOF'
# Niveth sound effects input access
SUBSYSTEM=="input", KERNEL=="event*", ENV{ID_INPUT_MOUSE}=="1", TAG+="uaccess"
SUBSYSTEM=="input", KERNEL=="event*", ENV{ID_INPUT_KEYBOARD}=="1", TAG+="uaccess"
EOF

echo "[PASS] udev rule"

echo
echo "=== CLEAN OLD DUPLICATES ==="

rm -f \
    "$ROOTFS/etc/xdg/autostart/mechvibes-dx.desktop" \
    "$ROOTFS/etc/xdg/autostart/mechvibes.desktop" \
    "$ROOTFS/etc/xdg/autostart/niveth-sound-effects.desktop" \
    "$ROOTFS/etc/skel/.config/autostart/mechvibes-dx.desktop" \
    "$ROOTFS/etc/skel/.config/autostart/mechvibes.desktop" \
    "$ROOTFS/etc/skel/.config/autostart/niveth-sound-effects.desktop"

echo "[PASS] duplicate cleanup"

echo
echo "=== FINAL PERMISSIONS ==="

chown -R root:root \
    "$ROOTFS/usr/lib/niveth/sound-effects" \
    "$ROOTFS/usr/share/niveth/sound-effects" \
    "$ROOTFS/usr/local/bin/niveth-start-mechvibes-input" \
    "$ROOTFS/usr/local/bin/niveth-start-mouse-sounds-input" \
    2>/dev/null || true

chmod 0755 \
    "$ROOTFS/usr/lib/niveth/sound-effects/niveth-sound-effects.py" \
    "$ROOTFS/usr/local/bin/niveth-start-mechvibes-input" \
    "$ROOTFS/usr/local/bin/niveth-start-mouse-sounds-input" \
    2>/dev/null || true

echo "[PASS] permissions"

echo
echo "=== SOUND INSTALL RESULT ==="

if [ -x "$ROOTFS/usr/bin/mechvibes-dx" ]; then
    echo "PASS: mechvibes binary"
else
    echo "FAIL: mechvibes binary"
    fail_count=$((fail_count + 1))
fi

if [ -f "$ROOTFS/etc/xdg/autostart/mechvibes-dx-niveth.desktop" ]; then
    echo "PASS: mechvibes autostart"
else
    echo "FAIL: mechvibes autostart"
    fail_count=$((fail_count + 1))
fi

if [ -f "$ROOTFS/etc/xdg/autostart/niveth-mouse-sounds.desktop" ]; then
    echo "PASS: mouse autostart"
else
    echo "FAIL: mouse autostart"
    fail_count=$((fail_count + 1))
fi

echo
echo "Failures: $fail_count"

if [ "$fail_count" -ne 0 ]; then
    exit 1
fi

echo "[NIVETH SOUND] COMPLETE"
