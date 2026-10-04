#!/usr/bin/env bash

set -euo pipefail

UUID="niveth-system-monitor@nivethos"
EXT="$HOME/.local/share/gnome-shell/extensions/$UUID"

ROOTFS="$HOME/Niveth/build/rootfs"
ROOTFS_EXT="$ROOTFS/usr/share/gnome-shell/extensions/$UUID"

echo "============================================================"
echo " NIVETH SYSTEM MONITOR — V18 SAFE BACKGROUND GROUP"
echo "============================================================"
echo
echo "Goal:"
echo "  Wallpaper"
echo "      ↓"
echo "  System Monitor"
echo "      ↓"
echo "  Application windows"
echo
echo "Current known-good version:"
echo "  V17"
echo

# ------------------------------------------------------------
# 1. Verify
# ------------------------------------------------------------

echo "[1/9] Verifying extension..."

if [ ! -f "$EXT/extension.js" ]; then
    echo "[FAIL] extension.js not found:"
    echo "  $EXT/extension.js"
    exit 1
fi

if [ ! -f "$EXT/metadata.json" ]; then
    echo "[FAIL] metadata.json not found."
    exit 1
fi

echo "[PASS] Extension files found"
echo

# ------------------------------------------------------------
# 2. Verify current version before touching anything
# ------------------------------------------------------------

echo "[2/9] Checking current version..."

CURRENT_VERSION="$(
    python3 - "$EXT/metadata.json" <<'PY'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])

data = json.loads(
    path.read_text()
)

print(data.get("version"))
PY
)"

echo "Current version: $CURRENT_VERSION"

if [ "$CURRENT_VERSION" != "17" ]; then
    echo "[FAIL] Expected V17 before this test."
    echo "       Found version: $CURRENT_VERSION"
    exit 1
fi

echo "[PASS] Current version is V17"
echo

# ------------------------------------------------------------
# 3. Backup
# ------------------------------------------------------------

echo "[3/9] Creating backup..."

BACKUP="$EXT/backup-v18-safe-$(date +%Y%m%d-%H%M%S)"

mkdir -p "$BACKUP"

cp -a "$EXT/extension.js" "$BACKUP/extension.js"
cp -a "$EXT/metadata.json" "$BACKUP/metadata.json"

if [ -f "$EXT/stylesheet.css" ]; then
    cp -a "$EXT/stylesheet.css" "$BACKUP/stylesheet.css"
fi

if [ -f "$EXT/niveth-audio-meter.py" ]; then
    cp -a "$EXT/niveth-audio-meter.py" "$BACKUP/niveth-audio-meter.py"
fi

echo "[PASS] Backup:"
echo "  $BACKUP"
echo

# ------------------------------------------------------------
# 4. Disable
# ------------------------------------------------------------

echo "[4/9] Disabling System Monitor..."

gnome-extensions disable "$UUID" 2>/dev/null || true

sleep 1

echo "[PASS] Disabled"
echo

# ------------------------------------------------------------
# 5. Replace ONLY the V17 addChrome() block
# ------------------------------------------------------------

echo "[5/9] Installing background-group stacking..."

python3 - "$EXT/extension.js" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text()

old = """        Main.layoutManager.addChrome(
            this._widget,
            {
                trackFullscreen: true,
            }
        );
"""

new = """        /*
         * Place the System Monitor in GNOME Shell's
         * background group.
         *
         * LayoutManager creates _backgroundGroup inside
         * the normal Mutter window group and keeps it
         * below application window actors.
         */
        const backgroundGroup =
            Main.layoutManager._backgroundGroup;

        if (!backgroundGroup) {
            throw new Error(
                '[niveth-system-monitor@nivethos] ' +
                'GNOME background group is unavailable'
            );
        }

        backgroundGroup.add_child(
            this._widget
        );

        backgroundGroup.lower_bottom();
"""

if old not in text:
    print("[FAIL] Expected V17 addChrome() block was not found.")
    print("[FAIL] Nothing else was modified.")
    sys.exit(1)

text = text.replace(old, new, 1)

# Make absolutely sure old stacking APIs are not present.
text = text.replace(
    "                affectsStruts: true,\n",
    ""
)

text = text.replace(
    "                affectsInputRegion: false,\n",
    ""
)

path.write_text(text)

print("[PASS] Replaced addChrome() with background group")
PY

echo

# ------------------------------------------------------------
# 6. Update metadata to V18
# ------------------------------------------------------------

echo "[6/9] Updating metadata..."

python3 - "$EXT/metadata.json" <<'PY'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])

data = json.loads(
    path.read_text()
)

data["version"] = 18

path.write_text(
    json.dumps(
        data,
        indent=2,
        ensure_ascii=False
    ) + "\n"
)

print("[PASS] Version -> 18")
PY

echo

# ------------------------------------------------------------
# 7. Verify source
# ------------------------------------------------------------

echo "[7/9] Verifying V18..."

required=(
    "Main.layoutManager._backgroundGroup"
    "backgroundGroup.add_child"
    "backgroundGroup.lower_bottom"
    "this._widget.set_reactive(false);"
    "_audioHistory"
    "_audioBars"
    "_startMetrics()"
    "_startAudioMeter()"
    "rgba(16, 17, 29, 0.0)"
)

for item in "${required[@]}"; do
    if grep -Fq "$item" "$EXT/extension.js"; then
        echo "[PASS] $item"
    else
        echo "[FAIL] Missing: $item"
        exit 1
    fi
done

for forbidden in \
    "Main.layoutManager.addChrome" \
    "affectsStruts" \
    "stage.insert_child_below" \
    "windowGroup.insert_child_below" \
    "set_z_position"
do
    if grep -Fq "$forbidden" "$EXT/extension.js"; then
        echo "[FAIL] Forbidden code still present: $forbidden"
        exit 1
    fi
done

echo "[PASS] No addChrome()"
echo "[PASS] No affectsStruts"
echo "[PASS] No stage stacking"
echo "[PASS] No z-position hack"

VERSION="$(
    python3 - "$EXT/metadata.json" <<'PY'
import json
import sys
from pathlib import Path

print(
    json.loads(
        Path(sys.argv[1]).read_text()
    ).get("version")
)
PY
)"

if [ "$VERSION" != "18" ]; then
    echo "[FAIL] Metadata version is not 18."
    exit 1
fi

echo "[PASS] Version 18"
echo

# ------------------------------------------------------------
# 8. Synchronize rootfs
# ------------------------------------------------------------

echo "[8/9] Synchronizing V18 to Niveth rootfs..."

if [ -d "$ROOTFS_EXT" ]; then

    sudo install \
        -m 0644 \
        "$EXT/extension.js" \
        "$ROOTFS_EXT/extension.js"

    sudo install \
        -m 0644 \
        "$EXT/metadata.json" \
        "$ROOTFS_EXT/metadata.json"

    if [ -f "$EXT/niveth-audio-meter.py" ]; then
        sudo install \
            -m 0644 \
            "$EXT/niveth-audio-meter.py" \
            "$ROOTFS_EXT/niveth-audio-meter.py"
    fi

    if [ -f "$EXT/stylesheet.css" ]; then
        sudo install \
            -m 0644 \
            "$EXT/stylesheet.css" \
            "$ROOTFS_EXT/stylesheet.css"
    fi

    echo "[PASS] Rootfs synchronized."

else
    echo "[INFO] Rootfs extension directory not found."
fi

echo

# ------------------------------------------------------------
# 9. Enable and report status
# ------------------------------------------------------------

echo "[9/9] Enabling V18..."

gnome-extensions enable "$UUID"

sleep 2

echo
echo "============================================================"
echo " FINAL STATUS"
echo "============================================================"

gnome-extensions info "$UUID" 2>&1 || true

echo
echo "============================================================"
echo " V18 SAFE INSTALL COMPLETE"
echo "============================================================"
echo
echo "Backup:"
echo "  $BACKUP"
echo
echo "Expected:"
echo "  Version: 18"
echo "  Enabled: Yes"
echo "  State: ACTIVE"
echo
echo "Expected behavior:"
echo "  - Monitor remains normal size"
echo "  - Monitor remains top-right"
echo "  - Background stays transparent"
echo "  - CPU/RAM/AUDIO continue working"
echo "  - Application windows render above monitor"
echo
