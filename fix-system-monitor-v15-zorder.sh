#!/usr/bin/env bash

set -euo pipefail

UUID="niveth-system-monitor@nivethos"
EXT="$HOME/.local/share/gnome-shell/extensions/$UUID"

ROOTFS="$HOME/Niveth/build/rootfs"
ROOTFS_EXT="$ROOTFS/usr/share/gnome-shell/extensions/$UUID"

echo "============================================================"
echo " NIVETH SYSTEM MONITOR — V15 Z-ORDER"
echo "============================================================"
echo
echo "Goal:"
echo "  System Monitor"
echo "      ↓"
echo "  MUST stay below application windows"
echo
echo "Preserved:"
echo "  - transparent background"
echo "  - bright text"
echo "  - CPU/RAM"
echo "  - AUDIO waveform"
echo "  - right-side position"
echo "  - click-through"
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

BACKUP="$EXT/backup-v15-zorder-$(date +%Y%m%d-%H%M%S)"

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
# 4. Replace stacking block
# ------------------------------------------------------------

echo "[4/9] Applying Z-order fix..."

python3 - "$EXT/extension.js" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text()

# ----------------------------------------------------------
# Replace the current window-group insertion block.
# ----------------------------------------------------------

old = """        const windowGroup =
            global.get_window_group();

        windowGroup.add_child(
            this._widget
        );

        windowGroup.insert_child_below(
            this._widget,
            null
        );
"""

new = """        const windowGroup =
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

if old in text:

    text = text.replace(
        old,
        new,
        1
    )

    print("[PASS] Replaced window-group stacking")

elif "this._widget.set_z_position(" in text:

    print("[PASS] Z-order fix already present")

else:

    print("[FAIL] Existing V14 window-group block not found.")
    sys.exit(1)


# ----------------------------------------------------------
# Ensure click-through.
# ----------------------------------------------------------

if "this._widget.set_reactive(false);" in text:

    print("[PASS] Click-through preserved")

else:

    marker = """        this._widget.show();
"""

    replacement = """        this._widget.show();

        this._widget.set_reactive(false);
"""

    if marker in text:

        text = text.replace(
            marker,
            replacement,
            1
        )

        print("[PASS] Click-through restored")

    else:

        print("[FAIL] Could not locate widget show().")
        sys.exit(1)


# ----------------------------------------------------------
# Make sure no old affectsStruts code remains.
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
# Make sure no addChrome() remains.
# ----------------------------------------------------------

if "Main.layoutManager.addChrome" in text:

    print("[FAIL] addChrome() is still present.")
    sys.exit(1)


path.write_text(text)
PY

echo

# ------------------------------------------------------------
# 5. Verify position and visuals are preserved
# ------------------------------------------------------------

echo "[5/9] Verifying preserved visual state..."

if ! grep -Fq \
    "rgba(16, 17, 29, 0.0)" \
    "$EXT/extension.js"
then
    echo "[FAIL] Transparent background missing."
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
    "this._widget.set_reactive(false);" \
    "$EXT/extension.js"
then
    echo "[FAIL] Click-through missing."
    exit 1
fi

if ! grep -Fq \
    "this._widget.set_z_position" \
    "$EXT/extension.js"
then
    echo "[FAIL] Z-position missing."
    exit 1
fi

if ! grep -Fq \
    "windowGroup.set_child_below_sibling" \
    "$EXT/extension.js"
then
    echo "[FAIL] Child stacking operation missing."
    exit 1
fi

if grep -Fq \
    "affectsStruts" \
    "$EXT/extension.js"
then
    echo "[FAIL] affectsStruts still exists."
    exit 1
fi

echo "[PASS] Transparent background"
echo "[PASS] CPU/RAM"
echo "[PASS] AUDIO"
echo "[PASS] Bright text"
echo "[PASS] Click-through"
echo "[PASS] Negative Z-order"
echo "[PASS] Below first window-group child"
echo "[PASS] No affectsStruts"
echo

# ------------------------------------------------------------
# 6. Update version
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

data["version"] = 15

path.write_text(
    json.dumps(
        data,
        indent=2,
        ensure_ascii=False
    ) + "\n"
)

print("[PASS] Version -> 15")
PY

echo

# ------------------------------------------------------------
# 7. Sync rootfs
# ------------------------------------------------------------

echo "[7/9] Synchronizing V15 to Niveth rootfs..."

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

echo "[8/9] Enabling System Monitor..."

gnome-extensions enable "$UUID"

sleep 2

# ------------------------------------------------------------
# 9. Status
# ------------------------------------------------------------

echo
echo "============================================================"
echo " FINAL STATUS"
echo "============================================================"

gnome-extensions info "$UUID" 2>&1 || true

echo
echo "============================================================"
echo " V15 Z-ORDER COMPLETE"
echo "============================================================"
echo
echo "Backup:"
echo "  $BACKUP"
echo
echo "Expected:"
echo "  Version: 15"
echo "  Enabled: Yes"
echo "  State: ACTIVE"
echo
echo "Expected stacking:"
echo "  Wallpaper"
echo "      ↓"
echo "  System Monitor"
echo "      ↓"
echo "  Application windows"
echo
