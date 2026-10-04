#!/usr/bin/env bash

set -euo pipefail

UUID="niveth-system-monitor@nivethos"
EXT="$HOME/.local/share/gnome-shell/extensions/$UUID"

ROOTFS="$HOME/Niveth/build/rootfs"
ROOTFS_EXT="$ROOTFS/usr/share/gnome-shell/extensions/$UUID"

echo "============================================================"
echo " NIVETH SYSTEM MONITOR — V14 UNDER WINDOWS"
echo "============================================================"
echo
echo "New stacking model:"
echo "  Wallpaper"
echo "      ↓"
echo "  System Monitor"
echo "      ↓"
echo "  Application windows"
echo "      ↓"
echo "  GNOME Shell chrome / panel"
echo
echo "The monitor will:"
echo "  - remain on the right"
echo "  - remain transparent"
echo "  - remain click-through"
echo "  - stay below application windows"
echo "  - preserve CPU / RAM / AUDIO"
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

echo "[PASS] Extension found"
echo

# ------------------------------------------------------------
# 2. Backup
# ------------------------------------------------------------

echo "[2/9] Creating backup..."

BACKUP="$EXT/backup-v14-under-windows-$(date +%Y%m%d-%H%M%S)"

mkdir -p "$BACKUP"

cp -a \
    "$EXT/extension.js" \
    "$BACKUP/extension.js"

cp -a \
    "$EXT/metadata.json" \
    "$BACKUP/metadata.json"

if [ -f "$EXT/stylesheet.css" ]; then
    cp -a \
        "$EXT/stylesheet.css" \
        "$BACKUP/stylesheet.css"
fi

if [ -f "$EXT/niveth-audio-meter.py" ]; then
    cp -a \
        "$EXT/niveth-audio-meter.py" \
        "$BACKUP/niveth-audio-meter.py"
fi

echo "[PASS] Backup:"
echo "  $BACKUP"
echo

# ------------------------------------------------------------
# 3. Disable
# ------------------------------------------------------------

echo "[3/9] Disabling System Monitor..."

gnome-extensions disable "$UUID" 2>/dev/null || true

sleep 1

echo "[PASS] Disabled"
echo

# ------------------------------------------------------------
# 4. Move monitor into Mutter window group
# ------------------------------------------------------------

echo "[4/9] Moving monitor below application windows..."

python3 - "$EXT/extension.js" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text()

# ----------------------------------------------------------
# Remove Main.layoutManager.addChrome()
# ----------------------------------------------------------

old_addchrome = """        Main.layoutManager.addChrome(
            this._widget,
            {
                trackFullscreen: true,
            }
        );
"""

if old_addchrome in text:

    new_window_group = """        const windowGroup =
            global.get_window_group();

        windowGroup.add_child(
            this._widget
        );

        windowGroup.insert_child_below(
            this._widget,
            null
        );
"""

    text = text.replace(
        old_addchrome,
        new_window_group,
        1
    )

    print("[PASS] Removed addChrome()")
    print("[PASS] Monitor inserted into window group")

elif "global.get_window_group()" in text:

    print("[PASS] Window-group mode already present")

else:

    print("[FAIL] Could not find existing addChrome() block.")
    sys.exit(1)


# ----------------------------------------------------------
# Remove any obsolete removeChrome() cleanup.
# ----------------------------------------------------------

old_removechrome = """            try {

                Main.layoutManager.removeChrome(
                    this._widget
                );

            } catch (error) {
            }

"""

if old_removechrome in text:

    text = text.replace(
        old_removechrome,
        "",
        1
    )

    print("[PASS] Removed obsolete removeChrome()")


# ----------------------------------------------------------
# Ensure widget is explicitly removed from its parent
# before destroy.
# ----------------------------------------------------------

old_cleanup = """        if (this._widget) {

            this._widget.destroy();

            this._widget = null;
        }
"""

new_cleanup = """        if (this._widget) {

            try {

                const parent =
                    this._widget.get_parent();

                if (parent) {

                    parent.remove_child(
                        this._widget
                    );
                }

            } catch (error) {
            }

            this._widget.destroy();

            this._widget = null;
        }
"""

if old_cleanup in text:

    text = text.replace(
        old_cleanup,
        new_cleanup,
        1
    )

    print("[PASS] Added safe window-group cleanup")

elif "this._widget.get_parent()" in text:

    print("[PASS] Safe cleanup already present")

else:

    print("[FAIL] Could not find widget cleanup block.")
    sys.exit(1)


path.write_text(text)
PY

echo

# ------------------------------------------------------------
# 5. Ensure right-side position remains correct
# ------------------------------------------------------------

echo "[5/9] Verifying monitor position..."

python3 - "$EXT/extension.js" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text()

# V13 position:
# monitor.x + monitor.width - width - 18

if """        const x =
            monitor.x +
            monitor.width -
            width -
            18;
""" in text:

    print("[PASS] Right-side position preserved")

elif """        const x =
            monitor.x +
            monitor.width -
            width;
""" in text:

    old = """        const x =
            monitor.x +
            monitor.width -
            width;
"""

    new = """        const x =
            monitor.x +
            monitor.width -
            width -
            18;
"""

    text = text.replace(
        old,
        new,
        1
    )

    path.write_text(text)

    print("[PASS] Restored 18px right margin")

else:

    print("[FAIL] Could not identify monitor position.")
    sys.exit(1)
PY

echo

# ------------------------------------------------------------
# 6. Update metadata
# ------------------------------------------------------------

echo "[6/9] Updating metadata version..."

python3 - "$EXT/metadata.json" <<'PY'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])

data = json.loads(
    path.read_text()
)

data["version"] = 14

path.write_text(
    json.dumps(
        data,
        indent=2,
        ensure_ascii=False
    ) + "\n"
)

print("[PASS] Version -> 14")
PY

echo

# ------------------------------------------------------------
# 7. Verify
# ------------------------------------------------------------

echo "[7/9] Verifying V14..."

if ! grep -Fq \
    "global.get_window_group()" \
    "$EXT/extension.js"
then
    echo "[FAIL] global.get_window_group() missing."
    exit 1
fi

if ! grep -Fq \
    "windowGroup.insert_child_below" \
    "$EXT/extension.js"
then
    echo "[FAIL] insert_child_below() missing."
    exit 1
fi

if grep -Fq \
    "Main.layoutManager.addChrome" \
    "$EXT/extension.js"
then
    echo "[FAIL] addChrome() still exists."
    exit 1
fi

if grep -Fq \
    "affectsStruts" \
    "$EXT/extension.js"
then
    echo "[FAIL] affectsStruts still exists."
    exit 1
fi

if grep -Fq \
    "Main.layoutManager.removeChrome" \
    "$EXT/extension.js"
then
    echo "[FAIL] removeChrome() still exists."
    exit 1
fi

if ! grep -Fq \
    "this._widget.set_reactive(false);" \
    "$EXT/extension.js"
then
    echo "[FAIL] Click-through missing."
    exit 1
fi

if ! grep -Fq \
    "_audioHistory" \
    "$EXT/extension.js"
then
    echo "[FAIL] Audio history missing."
    exit 1
fi

if ! grep -Fq \
    "_audioBars" \
    "$EXT/extension.js"
then
    echo "[FAIL] Audio bars missing."
    exit 1
fi

if ! grep -Fq \
    "_startMetrics()" \
    "$EXT/extension.js"
then
    echo "[FAIL] Metrics code missing."
    exit 1
fi

if ! grep -Fq \
    "_startAudioMeter()" \
    "$EXT/extension.js"
then
    echo "[FAIL] Audio meter missing."
    exit 1
fi

if ! grep -Fq \
    "rgba(16, 17, 29, 0.0)" \
    "$EXT/extension.js"
then
    echo "[FAIL] Transparent background missing."
    exit 1
fi

VERSION="$(
    python3 - "$EXT/metadata.json" <<'PY'
import json
import sys
from pathlib import Path

data = json.loads(
    Path(sys.argv[1]).read_text()
)

print(data.get("version"))
PY
)"

if [ "$VERSION" != "14" ]; then
    echo "[FAIL] Metadata version is not 14."
    exit 1
fi

echo "[PASS] Window group"
echo "[PASS] Below all window-group children"
echo "[PASS] addChrome removed"
echo "[PASS] affectsStruts removed"
echo "[PASS] click-through preserved"
echo "[PASS] transparent background preserved"
echo "[PASS] right-side position preserved"
echo "[PASS] CPU/RAM preserved"
echo "[PASS] AUDIO preserved"
echo "[PASS] Version 14"
echo

# ------------------------------------------------------------
# 8. Synchronize Niveth rootfs
# ------------------------------------------------------------

echo "[8/9] Synchronizing V14 to Niveth rootfs..."

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
# 9. Enable
# ------------------------------------------------------------

echo "[9/9] Enabling System Monitor..."

gnome-extensions enable "$UUID"

sleep 2

echo
echo "============================================================"
echo " FINAL STATUS"
echo "============================================================"

gnome-extensions info "$UUID" 2>&1 || true

echo
echo "============================================================"
echo " V14 UNDER-WINDOWS COMPLETE"
echo "============================================================"
echo
echo "Backup:"
echo "  $BACKUP"
echo
echo "Expected:"
echo "  Version: 14"
echo "  Enabled: Yes"
echo "  State: ACTIVE"
echo
echo "Expected behavior:"
echo "  Monitor stays at top-right."
echo "  Monitor remains transparent."
echo "  Application windows render above it."
echo "  Clicking through the monitor remains possible."
echo
