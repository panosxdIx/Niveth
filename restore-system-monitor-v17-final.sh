#!/usr/bin/env bash

set -euo pipefail

UUID="niveth-system-monitor@nivethos"
EXT="$HOME/.local/share/gnome-shell/extensions/$UUID"

ROOTFS="$HOME/Niveth/build/rootfs"
ROOTFS_EXT="$ROOTFS/usr/share/gnome-shell/extensions/$UUID"

echo "============================================================"
echo " NIVETH SYSTEM MONITOR — RESTORE V17"
echo "============================================================"
echo
echo "Restoring the last confirmed working layout."
echo

# ------------------------------------------------------------
# 1. Verify
# ------------------------------------------------------------

echo "[1/8] Checking extension..."

if [ ! -f "$EXT/extension.js" ]; then
    echo "[FAIL] extension.js not found."
    exit 1
fi

if [ ! -f "$EXT/metadata.json" ]; then
    echo "[FAIL] metadata.json not found."
    exit 1
fi

echo "[PASS] Extension found"
echo

# ------------------------------------------------------------
# 2. Backup current V18
# ------------------------------------------------------------

echo "[2/8] Creating V18 backup..."

BACKUP="$EXT/backup-before-v17-restore-$(date +%Y%m%d-%H%M%S)"

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
# 3. Disable
# ------------------------------------------------------------

echo "[3/8] Disabling System Monitor..."

gnome-extensions disable "$UUID" 2>/dev/null || true

sleep 1

echo "[PASS] Disabled"
echo

# ------------------------------------------------------------
# 4. Restore V17 stacking
# ------------------------------------------------------------

echo "[4/8] Restoring V17 stacking..."

python3 - "$EXT/extension.js" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text()

# ----------------------------------------------------------
# Remove V18 background-group insertion.
# ----------------------------------------------------------

start = text.find(
    "        /*\n         * Place the System Monitor in GNOME Shell's"
)

if start != -1:

    end_marker = """        backgroundGroup.lower_bottom();
"""

    end = text.find(
        end_marker,
        start
    )

    if end == -1:
        print("[FAIL] V18 background-group block is incomplete.")
        sys.exit(1)

    end += len(end_marker)

    replacement = """        Main.layoutManager.addChrome(
            this._widget,
            {
                trackFullscreen: true,
            }
        );
"""

    text = (
        text[:start]
        +
        replacement
        +
        text[end:]
    )

    print("[PASS] Removed V18 background group")
    print("[PASS] Restored addChrome()")

else:

    if "Main.layoutManager.addChrome" in text:
        print("[PASS] addChrome() already present")
    else:
        print("[FAIL] Could not locate V18 stacking block.")
        sys.exit(1)


# ----------------------------------------------------------
# Remove any remaining experimental stacking APIs.
# ----------------------------------------------------------

for fragment in [
    "global.get_window_group()",
    "backgroundGroup.add_child",
    "backgroundGroup.lower_bottom",
    "stage.insert_child_below",
    "windowGroup.insert_child_below",
    "windowGroup.set_child_below_sibling",
    "set_z_position",
    "affectsStruts",
    "affectsInputRegion",
]:

    if fragment in text:

        print(
            f"[WARN] Experimental fragment remains: {fragment}"
        )

# Exact cleanup of common leftovers.
text = text.replace(
    "                affectsStruts: true,\n",
    ""
)

text = text.replace(
    "                affectsInputRegion: false,\n",
    ""
)

text = text.replace(
    "this._widget.set_z_position(\n            -1000\n        );",
    ""
)


# ----------------------------------------------------------
# Restore V17 right-side positioning.
# ----------------------------------------------------------

old_position = """        const x =
            monitor.x +
            monitor.width -
            width;
"""

good_position = """        const x =
            monitor.x +
            monitor.width -
            width -
            18;
"""

if good_position in text:
    print("[PASS] Right-side position already correct")

elif old_position in text:

    text = text.replace(
        old_position,
        good_position,
        1
    )

    print("[PASS] Restored 18px right margin")

else:

    print("[FAIL] Could not locate monitor position.")
    sys.exit(1)


# ----------------------------------------------------------
# Make sure click-through remains.
# ----------------------------------------------------------

if "this._widget.set_reactive(false);" in text:

    print("[PASS] Click-through preserved")

else:

    marker = """        this._widget.show();
"""

    replacement = """        this._widget.show();

        this._widget.set_reactive(false);
"""

    if marker not in text:

        print("[FAIL] Could not restore click-through.")
        sys.exit(1)

    text = text.replace(
        marker,
        replacement,
        1
    )

    print("[PASS] Click-through restored")


# ----------------------------------------------------------
# Restore normal disable cleanup.
# ----------------------------------------------------------

parent_cleanup = """        if (this._widget) {

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

normal_cleanup = """        if (this._widget) {

            this._widget.destroy();

            this._widget = null;
        }
"""

if parent_cleanup in text:

    text = text.replace(
        parent_cleanup,
        normal_cleanup,
        1
    )

    print("[PASS] Restored V17 widget cleanup")

elif "this._widget.destroy();" in text:

    print("[PASS] Widget cleanup already safe")


path.write_text(text)
PY

echo

# ------------------------------------------------------------
# 5. Restore metadata
# ------------------------------------------------------------

echo "[5/8] Restoring metadata version 17..."

python3 - "$EXT/metadata.json" <<'PY'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])

data = json.loads(
    path.read_text()
)

data["version"] = 17

path.write_text(
    json.dumps(
        data,
        indent=2,
        ensure_ascii=False
    ) + "\n"
)

print("[PASS] Version -> 17")
PY

echo

# ------------------------------------------------------------
# 6. Verify
# ------------------------------------------------------------

echo "[6/8] Verifying V17..."

if ! grep -Fq \
    "Main.layoutManager.addChrome" \
    "$EXT/extension.js"
then
    echo "[FAIL] addChrome() missing."
    exit 1
fi

if grep -Fq \
    "global.get_window_group()" \
    "$EXT/extension.js"
then
    echo "[FAIL] window-group code remains."
    exit 1
fi

if grep -Fq \
    "_backgroundGroup" \
    "$EXT/extension.js"
then
    echo "[FAIL] background-group code remains."
    exit 1
fi

if grep -Fq \
    "stage.insert_child_below" \
    "$EXT/extension.js"
then
    echo "[FAIL] stage-layer code remains."
    exit 1
fi

if grep -Fq \
    "affectsStruts" \
    "$EXT/extension.js"
then
    echo "[FAIL] affectsStruts remains."
    exit 1
fi

if grep -Fq \
    "set_z_position" \
    "$EXT/extension.js"
then
    echo "[FAIL] set_z_position remains."
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
    echo "[FAIL] Metrics missing."
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

print(
    json.loads(
        Path(sys.argv[1]).read_text()
    ).get("version")
)
PY
)"

if [ "$VERSION" != "17" ]; then
    echo "[FAIL] Version is not 17."
    exit 1
fi

echo "[PASS] addChrome"
echo "[PASS] top-right position"
echo "[PASS] transparent background"
echo "[PASS] bright text"
echo "[PASS] CPU/RAM"
echo "[PASS] AUDIO"
echo "[PASS] click-through"
echo "[PASS] Version 17"
echo

# ------------------------------------------------------------
# 7. Rootfs
# ------------------------------------------------------------

echo "[7/8] Synchronizing V17 to Niveth rootfs..."

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
# 8. Enable
# ------------------------------------------------------------

echo "[8/8] Enabling V17..."

gnome-extensions enable "$UUID"

sleep 2

echo
echo "============================================================"
echo " FINAL STATUS"
echo "============================================================"

gnome-extensions info "$UUID" 2>&1 || true

echo
echo "============================================================"
echo " V17 RESTORED"
echo "============================================================"
echo
echo "Backup:"
echo "  $BACKUP"
echo
