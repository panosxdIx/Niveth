#!/usr/bin/env bash

set -euo pipefail

UUID="niveth-system-monitor@nivethos"
EXT="$HOME/.local/share/gnome-shell/extensions/$UUID"

ROOTFS="$HOME/Niveth/build/rootfs"
ROOTFS_EXT="$ROOTFS/usr/share/gnome-shell/extensions/$UUID"

echo "============================================================"
echo " NIVETH SYSTEM MONITOR — V16 STAGE LAYER"
echo "============================================================"
echo
echo "Target stacking:"
echo
echo "  Wallpaper / background"
echo "          ↓"
echo "  System Monitor"
echo "          ↓"
echo "  Application windows"
echo "          ↓"
echo "  GNOME Shell UI"
echo
echo "Preserve:"
echo "  - right-side position"
echo "  - transparent background"
echo "  - bright labels"
echo "  - CPU/RAM"
echo "  - AUDIO waveform"
echo "  - click-through"
echo

# ------------------------------------------------------------
# 1. Verify
# ------------------------------------------------------------

echo "[1/10] Verifying extension..."

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

echo "[2/10] Creating backup..."

BACKUP="$EXT/backup-v16-stage-$(date +%Y%m%d-%H%M%S)"

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

echo "[3/10] Disabling System Monitor..."

gnome-extensions disable "$UUID" 2>/dev/null || true

sleep 1

echo "[PASS] Disabled"
echo

# ------------------------------------------------------------
# 4. Replace V15 stacking with stage stacking
# ------------------------------------------------------------

echo "[4/10] Installing stage-level stacking..."

python3 - "$EXT/extension.js" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text()

# ----------------------------------------------------------
# Current V15 block:
#   const windowGroup = global.get_window_group();
#   windowGroup.add_child(...)
#   set_z_position(...)
#   set_child_below_sibling(...)
#
# Replace it with:
#   global.stage.insert_child_below(widget, windowGroup)
#
# This keeps the monitor as a direct stage child, while
# placing it below the entire application window group.
# ----------------------------------------------------------

old_v15 = """        const windowGroup =
            global.get_window_group();

        windowGroup.add_child(
            this._widget
        );

        /*
         * Keep the monitor inside Mutter's window group,
         * but force it behind application window actors.
         *
         * Clutter's child ordering takes actor depth into
         * account, so a negative Z position places the
         * monitor behind normal window actors.
         */
        this._widget.set_z_position(
            -1000
        );

        windowGroup.set_child_below_sibling(
            this._widget,
            windowGroup.get_first_child()
        );
"""

new_stage = """        const stage =
            global.stage;

        const windowGroup =
            global.get_window_group();

        /*
         * Put the System Monitor directly on the stage,
         * immediately below the complete application
         * window group.
         *
         * Result:
         *
         *   background
         *       ↓
         *   System Monitor
         *       ↓
         *   window group / application windows
         *       ↓
         *   Shell UI
         */
        stage.insert_child_below(
            this._widget,
            windowGroup
        );
"""

if old_v15 in text:

    text = text.replace(
        old_v15,
        new_stage,
        1
    )

    print("[PASS] Replaced V15 window-group stacking")

elif "stage.insert_child_below" in text:

    print("[PASS] Stage-level stacking already present")

else:

    # Try to replace a V14-style block as fallback.
    old_v14 = """        const windowGroup =
            global.get_window_group();

        windowGroup.add_child(
            this._widget
        );

        windowGroup.insert_child_below(
            this._widget,
            null
        );
"""

    if old_v14 in text:

        text = text.replace(
            old_v14,
            new_stage,
            1
        )

        print("[PASS] Replaced V14 window-group stacking")

    else:

        print(
            "[FAIL] Could not locate existing stacking block."
        )

        sys.exit(1)


# ----------------------------------------------------------
# Remove any old stacking APIs from this extension.
# ----------------------------------------------------------

text = text.replace(
    "            this._widget.set_z_position(\n            -1000\n        );\n",
    ""
)

# Remove literal legacy calls if any remain.
text = text.replace(
    "this._widget.set_z_position(\n            -1000\n        );",
    ""
)

# ----------------------------------------------------------
# Remove old addChrome references if any.
# ----------------------------------------------------------

if "Main.layoutManager.addChrome" in text:

    print("[FAIL] addChrome() remains in extension.js.")
    sys.exit(1)

# ----------------------------------------------------------
# Remove reserved-space options if any.
# ----------------------------------------------------------

text = text.replace(
    "                affectsStruts: true,\n",
    ""
)

text = text.replace(
    "                affectsInputRegion: false,\n",
    ""
)

# ----------------------------------------------------------
# Preserve click-through.
# ----------------------------------------------------------

if "this._widget.set_reactive(false);" not in text:

    marker = """        this._widget.show();
"""

    replacement = """        this._widget.show();

        this._widget.set_reactive(false);
"""

    if marker not in text:

        print("[FAIL] Could not add click-through.")
        sys.exit(1)

    text = text.replace(
        marker,
        replacement,
        1
    )

    print("[PASS] Click-through restored")

else:

    print("[PASS] Click-through preserved")


# ----------------------------------------------------------
# Safe cleanup.
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

    print("[PASS] Safe stage cleanup installed")

elif "this._widget.get_parent()" in text:

    print("[PASS] Safe cleanup already present")

else:

    print("[FAIL] Could not locate widget cleanup.")
    sys.exit(1)


path.write_text(text)
PY

echo

# ------------------------------------------------------------
# 5. Make sure position remains right-side
# ------------------------------------------------------------

echo "[5/10] Verifying right-side position..."

python3 - "$EXT/extension.js" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text()

desired = """        const x =
            monitor.x +
            monitor.width -
            width -
            18;
"""

current = """        const x =
            monitor.x +
            monitor.width -
            width;
"""

if desired in text:

    print("[PASS] Right-side 18px margin preserved")

elif current in text:

    text = text.replace(
        current,
        desired,
        1
    )

    path.write_text(text)

    print("[PASS] Restored right-side 18px margin")

else:

    print("[FAIL] Could not identify monitor X position.")
    sys.exit(1)
PY

echo

# ------------------------------------------------------------
# 6. Update metadata
# ------------------------------------------------------------

echo "[6/10] Updating metadata version..."

python3 - "$EXT/metadata.json" <<'PY'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])

data = json.loads(
    path.read_text()
)

data["version"] = 16

path.write_text(
    json.dumps(
        data,
        indent=2,
        ensure_ascii=False
    ) + "\n"
)

print("[PASS] Version -> 16")
PY

echo

# ------------------------------------------------------------
# 7. Source verification
# ------------------------------------------------------------

echo "[7/10] Verifying V16 source..."

check() {
    local label="$1"
    local pattern="$2"

    if grep -Fq "$pattern" "$EXT/extension.js"; then
        echo "[PASS] $label"
    else
        echo "[FAIL] $label"
        exit 1
    fi
}

check \
    "global.stage" \
    "const stage ="

check \
    "window group" \
    "global.get_window_group()"

check \
    "stage below window group" \
    "stage.insert_child_below"

check \
    "click-through" \
    "this._widget.set_reactive(false);"

check \
    "CPU/RAM" \
    "_startMetrics()"

check \
    "AUDIO" \
    "_startAudioMeter()"

check \
    "audio history" \
    "_audioHistory"

check \
    "audio bars" \
    "_audioBars"

check \
    "transparent background" \
    "rgba(16, 17, 29, 0.0)"

if grep -Fq \
    "Main.layoutManager.addChrome" \
    "$EXT/extension.js"
then
    echo "[FAIL] addChrome still present."
    exit 1
fi

if grep -Fq \
    "affectsStruts" \
    "$EXT/extension.js"
then
    echo "[FAIL] affectsStruts still present."
    exit 1
fi

if grep -Fq \
    "set_z_position" \
    "$EXT/extension.js"
then
    echo "[FAIL] Old set_z_position still present."
    exit 1
fi

if grep -Fq \
    "windowGroup.add_child" \
    "$EXT/extension.js"
then
    echo "[FAIL] Monitor is still being added to windowGroup."
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

if [ "$VERSION" != "16" ]; then
    echo "[FAIL] Version is not 16."
    exit 1
fi

echo "[PASS] No addChrome"
echo "[PASS] No affectsStruts"
echo "[PASS] No negative Z hack"
echo "[PASS] Monitor is NOT inside windowGroup"
echo "[PASS] Version 16"
echo

# ------------------------------------------------------------
# 8. Synchronize rootfs
# ------------------------------------------------------------

echo "[8/10] Synchronizing V16 to Niveth rootfs..."

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

echo "[9/10] Enabling System Monitor..."

gnome-extensions enable "$UUID"

sleep 2

# ------------------------------------------------------------
# 10. Status
# ------------------------------------------------------------

echo
echo "============================================================"
echo " FINAL STATUS"
echo "============================================================"

gnome-extensions info "$UUID" 2>&1 || true

echo
echo "============================================================"
echo " V16 STAGE LAYER COMPLETE"
echo "============================================================"
echo
echo "Backup:"
echo "  $BACKUP"
echo
echo "Expected:"
echo "  Version: 16"
echo "  Enabled: Yes"
echo "  State: ACTIVE"
echo
echo "Stacking:"
echo "  Wallpaper"
echo "      ↓"
echo "  System Monitor"
echo "      ↓"
echo "  Application windows"
echo "      ↓"
echo "  GNOME Shell UI"
echo
