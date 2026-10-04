#!/usr/bin/env bash

set -euo pipefail

# =========================================================
# NIVETH SYSTEM MONITOR — REPAIR / ROOTFS SYNC
# =========================================================

EXT_ID="niveth-system-monitor@nivethos"

HOST_DIR="$HOME/.local/share/gnome-shell/extensions/$EXT_ID"

ROOTFS="$HOME/Niveth/build/rootfs"
ROOTFS_DIR="$ROOTFS/usr/share/gnome-shell/extensions/$EXT_ID"

SOURCE_DCONF_1="$HOME/Niveth/desktop/defaults/dconf/local.d/10-niveth"
SOURCE_DCONF_2="$HOME/Niveth/desktop/defaults/dconf/org-gnome-shell.dconf"

ROOTFS_DCONF="$ROOTFS/etc/dconf/db/local.d/00-niveth-defaults"

STAMP="$(date +%Y%m%d-%H%M%S)"

echo
echo "============================================================"
echo " NIVETH SYSTEM MONITOR — REPAIR"
echo "============================================================"
echo

# =========================================================
# 1. CHECK EXTENSION FILES
# =========================================================

echo "[1/8] Checking current extension"

for file in metadata.json extension.js stylesheet.css
do
    if [ ! -f "$HOST_DIR/$file" ]; then
        echo "[FAIL] Missing:"
        echo "$HOST_DIR/$file"
        exit 1
    fi

    echo "[PASS] $file"
done


# =========================================================
# 2. CHECK IMPORTANT CONTENT
# =========================================================

echo
echo "[2/8] Checking System Monitor content"

grep -q \
    "NivethSystemMonitorExtension" \
    "$HOST_DIR/extension.js"

grep -q \
    "_updateWaveform" \
    "$HOST_DIR/extension.js"

grep -q \
    "/proc/stat" \
    "$HOST_DIR/extension.js"

grep -q \
    "/proc/meminfo" \
    "$HOST_DIR/extension.js"

grep -q \
    "niveth-system-wave-bar" \
    "$HOST_DIR/stylesheet.css"

echo "[PASS] CPU reader"
echo "[PASS] RAM reader"
echo "[PASS] Waveform logic"
echo "[PASS] Waveform CSS"


# =========================================================
# 3. UPDATE SOURCE DCONF SAFELY
# =========================================================

echo
echo "[3/8] Updating source dconf"

python3 - "$SOURCE_DCONF_1" "$SOURCE_DCONF_2" "$EXT_ID" <<'PY'
from pathlib import Path
import ast
import re
import sys

paths = [
    Path(sys.argv[1]),
    Path(sys.argv[2]),
]

extension = sys.argv[3]

for path in paths:

    if not path.is_file():
        print(f"[INFO] Missing source dconf: {path}")
        continue

    text = path.read_text(
        encoding="utf-8"
    )

    match = re.search(
        r"^enabled-extensions=(\[.*\])$",
        text,
        re.MULTILINE
    )

    if not match:
        print(
            f"[INFO] No enabled-extensions in {path}; skipped."
        )
        continue

    enabled = ast.literal_eval(
        match.group(1)
    )

    if extension not in enabled:

        enabled.append(extension)

        new_line = (
            "enabled-extensions="
            + repr(enabled)
        )

        text = re.sub(
            r"^enabled-extensions=\[.*\]$",
            new_line,
            text,
            count=1,
            flags=re.MULTILINE
        )

        path.write_text(
            text,
            encoding="utf-8"
        )

        print(
            f"[PASS] Added {extension} to {path}"
        )

    else:

        print(
            f"[PASS] {extension} already exists in {path}"
        )
PY


# =========================================================
# 4. ROOTFS EXTENSION
# =========================================================

echo
echo "[4/8] Installing extension into rootfs"

if [ ! -d "$ROOTFS" ]; then
    echo "[FAIL] Rootfs not found:"
    echo "$ROOTFS"
    exit 1
fi

sudo mkdir -p \
    "$ROOTFS_DIR"

for file in metadata.json extension.js stylesheet.css
do

    sudo install \
        -m 0644 \
        "$HOST_DIR/$file" \
        "$ROOTFS_DIR/$file"

    echo "[PASS] Rootfs $file"
done


# =========================================================
# 5. ROOTFS DCONF
# =========================================================

echo
echo "[5/8] Updating rootfs dconf"

if [ ! -f "$ROOTFS_DCONF" ]; then
    echo "[FAIL] Rootfs dconf not found:"
    echo "$ROOTFS_DCONF"
    exit 1
fi

sudo cp \
    "$ROOTFS_DCONF" \
    "$ROOTFS_DCONF.backup-before-system-monitor-repair-$STAMP"


sudo python3 - "$ROOTFS_DCONF" "$EXT_ID" <<'PY'
from pathlib import Path
import ast
import re
import sys

path = Path(sys.argv[1])
extension = sys.argv[2]

text = path.read_text(
    encoding="utf-8"
)

match = re.search(
    r"^enabled-extensions=(\[.*\])$",
    text,
    re.MULTILINE
)

if not match:
    raise SystemExit(
        "ERROR: enabled-extensions not found in rootfs dconf."
    )

enabled = ast.literal_eval(
    match.group(1)
)

if extension not in enabled:
    enabled.append(extension)

new_line = (
    "enabled-extensions="
    + repr(enabled)
)

text = re.sub(
    r"^enabled-extensions=\[.*\]$",
    new_line,
    text,
    count=1,
    flags=re.MULTILINE
)

path.write_text(
    text,
    encoding="utf-8"
)

print("[PASS] Rootfs enabled-extensions updated.")
print(new_line)
PY


# =========================================================
# 6. REBUILD DCONF
# =========================================================

echo
echo "[6/8] Rebuilding compiled dconf"

sudo chroot \
    "$ROOTFS" \
    /usr/bin/dconf update

if [ ! -f "$ROOTFS/etc/dconf/db/local" ]; then
    echo "[FAIL] Compiled dconf database missing."
    exit 1
fi

echo "[PASS] Compiled dconf database exists"


# =========================================================
# 7. VERIFY SOURCE ↔ ROOTFS
# =========================================================

echo
echo "[7/8] Verifying source and rootfs"

for file in metadata.json extension.js stylesheet.css
do

    SOURCE_FILE="$HOST_DIR/$file"
    ROOT_FILE="$ROOTFS_DIR/$file"

    SOURCE_HASH="$(
        sha256sum "$SOURCE_FILE" |
        awk '{print $1}'
    )"

    ROOT_HASH="$(
        sudo sha256sum "$ROOT_FILE" |
        awk '{print $1}'
    )"

    echo
    echo "$file"
    echo "  SOURCE : $SOURCE_HASH"
    echo "  ROOTFS : $ROOT_HASH"

    if [ "$SOURCE_HASH" != "$ROOT_HASH" ]; then
        echo "[FAIL] $file mismatch"
        exit 1
    fi

    echo "[PASS] identical"
done


sudo grep -q \
    "$EXT_ID" \
    "$ROOTFS_DCONF"

echo
echo "[PASS] Extension present in rootfs dconf"


sudo test -f \
    "$ROOTFS_DIR/extension.js"

sudo test -f \
    "$ROOTFS_DIR/stylesheet.css"

echo "[PASS] Rootfs extension files exist"


# =========================================================
# 8. ENABLE LIVE EXTENSION
# =========================================================

echo
echo "[8/8] Reloading live System Monitor"

gnome-extensions disable \
    "$EXT_ID" \
    2>/dev/null || true

sleep 2

gnome-extensions enable \
    "$EXT_ID"

sleep 5

echo
echo "============================================================"
echo " NIVETH SYSTEM MONITOR — REPAIR COMPLETE"
echo "============================================================"
echo

echo "Extension:"
gnome-extensions info \
    "$EXT_ID" \
    2>&1 |
    grep -E \
        "Name:|Enabled:|State:|Path:" || true

echo
echo "GNOME color scheme:"
gsettings get \
    org.gnome.desktop.interface \
    color-scheme

echo
echo "Rootfs extension:"
echo "  $ROOTFS_DIR"

echo
echo "Expected:"
echo "  CPU       → live value"
echo "  RAM       → live value"
echo "  Waveform  → live waveform"
echo
echo "============================================================"
