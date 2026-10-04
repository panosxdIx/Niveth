#!/usr/bin/env bash

set -euo pipefail

UUID="niveth-system-monitor@nivethos"
EXT="$HOME/.local/share/gnome-shell/extensions/$UUID"

ROOTFS="$HOME/Niveth/build/rootfs"
ROOTFS_EXT="$ROOTFS/usr/share/gnome-shell/extensions/$UUID"

echo "============================================================"
echo " NIVETH SYSTEM MONITOR — V13 ROLLBACK"
echo "============================================================"
echo
echo "Restoring the previous working layout:"
echo "  - no affectsStruts"
echo "  - monitor back to right side"
echo "  - transparent background preserved"
echo "  - CPU/RAM preserved"
echo "  - AUDIO waveform preserved"
echo "  - click-through preserved"
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
# 2. Backup current state
# ------------------------------------------------------------

echo "[2/8] Creating backup..."

BACKUP="$EXT/backup-v13-rollback-$(date +%Y%m%d-%H%M%S)"

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
# 3. Disable extension
# ------------------------------------------------------------

echo "[3/8] Disabling System Monitor..."

gnome-extensions disable "$UUID" 2>/dev/null || true

sleep 1

echo "[PASS] Disabled"
echo

# ------------------------------------------------------------
# 4. Restore previous layout
# ------------------------------------------------------------

echo "[4/8] Restoring previous working layout..."

python3 - "$EXT/extension.js" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text()

# ----------------------------------------------------------
# Restore simple addChrome() without affectsStruts.
# ----------------------------------------------------------

old = """        Main.layoutManager.addChrome(
            this._widget,
            {
                trackFullscreen: true,
                affectsStruts: true,
                affectsInputRegion: false,
            }
        );
"""

new = """        Main.layoutManager.addChrome(
            this._widget,
            {
                trackFullscreen: true,
            }
        );
"""

if old in text:
    text = text.replace(old, new, 1)
    print("[PASS] Removed affectsStruts")
else:
    text = text.replace(
        "                affectsStruts: true,\n",
        "",
        1
    )
    text = text.replace(
        "                affectsInputRegion: false,\n",
        "",
        1
    )
    print("[PASS] Reserved-space options removed")


# ----------------------------------------------------------
# Restore right-side position with 18px margin.
# ----------------------------------------------------------

old_x = """        const x =
            monitor.x +
            monitor.width -
            width;
"""

new_x = """        const x =
            monitor.x +
            monitor.width -
            width -
            18;
"""

if old_x in text:
    text = text.replace(old_x, new_x, 1)
    print("[PASS] Restored 18px right margin")
elif new_x in text:
    print("[PASS] Right-side position already restored")
else:
    print("[FAIL] Could not find monitor X-position block")
    sys.exit(1)


# ----------------------------------------------------------
# Keep click-through.
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
        print("[PASS] Restored click-through")
    else:
        print("[FAIL] Could not restore click-through")
        sys.exit(1)


# ----------------------------------------------------------
# Keep safe removeChrome() cleanup if present.
# ----------------------------------------------------------

if "Main.layoutManager.removeChrome" in text:
    print("[PASS] Safe removeChrome() cleanup preserved")
else:
    old_disable = """        if (this._widget) {

            this._widget.destroy();

            this._widget = null;
        }
"""

    new_disable = """        if (this._widget) {

            this._widget.destroy();

            this._widget = null;
        }
"""

    if old_disable in text:
        print("[PASS] Standard widget cleanup present")


path.write_text(text)
PY

echo

# ------------------------------------------------------------
# 5. Metadata version
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

data["version"] = 13

path.write_text(
    json.dumps(
        data,
        indent=2,
        ensure_ascii=False
    ) + "\n"
)

print("[PASS] Version -> 13")
PY

echo

# ------------------------------------------------------------
# 6. Verify
# ------------------------------------------------------------

echo "[6/8] Verifying rollback..."

if grep -Fq "affectsStruts: true" "$EXT/extension.js"; then
    echo "[FAIL] affectsStruts still exists."
    exit 1
fi

if grep -Fq "affectsInputRegion: false" "$EXT/extension.js"; then
    echo "[FAIL] affectsInputRegion still exists."
    exit 1
fi

if ! grep -Fq \
    "monitor.width -" \
    "$EXT/extension.js"
then
    echo "[FAIL] Monitor position code missing."
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

if [ "$VERSION" != "13" ]; then
    echo "[FAIL] Version is not 13."
    exit 1
fi

echo "[PASS] affectsStruts removed"
echo "[PASS] Right-side position restored"
echo "[PASS] Transparent background preserved"
echo "[PASS] CPU/RAM preserved"
echo "[PASS] AUDIO preserved"
echo "[PASS] Click-through preserved"
echo "[PASS] Version 13"
echo

# ------------------------------------------------------------
# 7. Synchronize rootfs
# ------------------------------------------------------------

echo "[7/8] Synchronizing V13 to Niveth rootfs..."

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
echo " V13 ROLLBACK COMPLETE"
echo "============================================================"
echo
echo "Backup:"
echo "  $BACKUP"
echo
