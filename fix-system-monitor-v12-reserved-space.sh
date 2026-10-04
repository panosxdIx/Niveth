#!/usr/bin/env bash

set -euo pipefail

UUID="niveth-system-monitor@nivethos"
EXT="$HOME/.local/share/gnome-shell/extensions/$UUID"

ROOTFS="$HOME/Niveth/build/rootfs"
ROOTFS_EXT="$ROOTFS/usr/share/gnome-shell/extensions/$UUID"

echo "============================================================"
echo " NIVETH SYSTEM MONITOR — V12 RESERVED SPACE"
echo "============================================================"
echo
echo "Changes:"
echo "  - reserve work area for System Monitor"
echo "  - windows no longer pass underneath monitor"
echo "  - monitor aligned to right screen edge"
echo "  - keep transparent background"
echo "  - preserve CPU / RAM / AUDIO"
echo "  - preserve click-through behavior"
echo

# ------------------------------------------------------------
# 1. Verify
# ------------------------------------------------------------

echo "[1/8] Verifying extension..."

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

echo "[2/8] Creating backup..."

BACKUP="$EXT/backup-v12-strut-$(date +%Y%m%d-%H%M%S)"

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
# 3. Disable current extension
# ------------------------------------------------------------

echo "[3/8] Disabling current System Monitor..."

gnome-extensions disable "$UUID" 2>/dev/null || true

sleep 1

echo "[PASS] Disabled"
echo

# ------------------------------------------------------------
# 4. Apply reserved-space changes
# ------------------------------------------------------------

echo "[4/8] Applying reserved-space fix..."

python3 - "$EXT/extension.js" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text()

# ----------------------------------------------------------
# A. Make addChrome reserve work area.
# ----------------------------------------------------------

old_addchrome = """        Main.layoutManager.addChrome(
            this._widget,
            {
                trackFullscreen: true,
            }
        );
"""

new_addchrome = """        Main.layoutManager.addChrome(
            this._widget,
            {
                trackFullscreen: true,
                affectsStruts: true,
                affectsInputRegion: false,
            }
        );
"""

if old_addchrome in text:
    text = text.replace(
        old_addchrome,
        new_addchrome,
        1
    )
    print("[PASS] addChrome -> affectsStruts: true")

elif "affectsStruts: true" in text:
    print("[PASS] affectsStruts already enabled")

else:
    print("[FAIL] Could not find addChrome block.")
    sys.exit(1)


# ----------------------------------------------------------
# B. Align monitor exactly to right edge.
# ----------------------------------------------------------

old_position = """        const x =
            monitor.x +
            monitor.width -
            width -
            18;
"""

new_position = """        const x =
            monitor.x +
            monitor.width -
            width;
"""

if old_position in text:
    text = text.replace(
        old_position,
        new_position,
        1
    )
    print("[PASS] Monitor aligned to right edge")

elif new_position in text:
    print("[PASS] Right-edge alignment already present")

else:
    print("[FAIL] Could not find monitor X-position block.")
    sys.exit(1)


# ----------------------------------------------------------
# C. Ensure click-through remains.
# ----------------------------------------------------------

if "this._widget.set_reactive(false);" in text:
    print("[PASS] Monitor remains click-through")

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
        print("[FAIL] Could not locate widget show()")
        sys.exit(1)


# ----------------------------------------------------------
# D. Explicitly remove chrome before destroying widget.
# ----------------------------------------------------------

old_disable = """        if (this._widget) {

            this._widget.destroy();

            this._widget = null;
        }
"""

new_disable = """        if (this._widget) {

            try {

                Main.layoutManager.removeChrome(
                    this._widget
                );

            } catch (error) {
            }

            this._widget.destroy();

            this._widget = null;
        }
"""

if old_disable in text:
    text = text.replace(
        old_disable,
        new_disable,
        1
    )
    print("[PASS] Chrome removed cleanly on disable")

elif "Main.layoutManager.removeChrome" in text:
    print("[PASS] removeChrome already present")

else:
    print("[FAIL] Could not locate disable() widget cleanup.")
    sys.exit(1)


path.write_text(text)
PY

echo

# ------------------------------------------------------------
# 5. Update version
# ------------------------------------------------------------

echo "[5/8] Updating metadata version..."

python3 - "$EXT/metadata.json" <<'PY'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])

data = json.loads(
    path.read_text()
)

data["version"] = 12

path.write_text(
    json.dumps(
        data,
        indent=2,
        ensure_ascii=False
    ) + "\n"
)

print("[PASS] Version -> 12")
PY

echo

# ------------------------------------------------------------
# 6. Verify
# ------------------------------------------------------------

echo "[6/8] Verifying V12..."

if ! grep -Fq \
    "affectsStruts: true" \
    "$EXT/extension.js"
then
    echo "[FAIL] affectsStruts: true missing."
    exit 1
fi

if ! grep -Fq \
    "affectsInputRegion: false" \
    "$EXT/extension.js"
then
    echo "[FAIL] affectsInputRegion: false missing."
    exit 1
fi

if grep -Fq \
    "width -\n            18" \
    "$EXT/extension.js"
then
    echo "[FAIL] Old right margin still present."
    exit 1
fi

if ! grep -Fq \
    "this._widget.set_reactive(false);" \
    "$EXT/extension.js"
then
    echo "[FAIL] Click-through disabled."
    exit 1
fi

if ! grep -Fq \
    "Main.layoutManager.removeChrome" \
    "$EXT/extension.js"
then
    echo "[FAIL] removeChrome() missing."
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
    echo "[FAIL] Audio meter code missing."
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

if [ "$VERSION" != "12" ]; then
    echo "[FAIL] Metadata version is not 12."
    exit 1
fi

echo "[PASS] affectsStruts: true"
echo "[PASS] affectsInputRegion: false"
echo "[PASS] right-edge alignment"
echo "[PASS] click-through"
echo "[PASS] clean chrome removal"
echo "[PASS] CPU/RAM preserved"
echo "[PASS] AUDIO preserved"
echo "[PASS] Version 12"
echo

# ------------------------------------------------------------
# 7. Synchronize Niveth rootfs
# ------------------------------------------------------------

echo "[7/8] Synchronizing V12 to Niveth rootfs..."

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

echo "[8/8] Enabling System Monitor..."

gnome-extensions enable "$UUID"

sleep 2

echo
echo "============================================================"
echo " FINAL STATUS"
echo "============================================================"

gnome-extensions info "$UUID" 2>&1 || true

echo
echo "============================================================"
echo " V12 RESERVED SPACE COMPLETE"
echo "============================================================"
echo
echo "Backup:"
echo "  $BACKUP"
echo
echo "Expected:"
echo "  Version: 12"
echo "  Enabled: Yes"
echo "  State: ACTIVE"
echo
