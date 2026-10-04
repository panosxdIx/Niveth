#!/usr/bin/env bash

set -euo pipefail

UUID="niveth-system-monitor@nivethos"

EXT="$HOME/.local/share/gnome-shell/extensions/$UUID"
ROOTFS="$HOME/Niveth/build/rootfs"
ROOTFS_EXT="$ROOTFS/usr/share/gnome-shell/extensions/$UUID"

echo "============================================================"
echo " NIVETH SYSTEM MONITOR — V9 FIX"
echo "============================================================"
echo
echo "Fix:"
echo "  - remove unsupported raise_top()"
echo "  - keep monitor click-through"
echo "  - preserve V8 CPU/RAM/audio implementation"
echo "  - version -> 9"
echo

# ------------------------------------------------------------
# 1. Verify
# ------------------------------------------------------------

echo "[1/8] Verifying files..."

if [ ! -d "$EXT" ]; then
    echo "[FAIL] Extension directory not found:"
    echo "  $EXT"
    exit 1
fi

if [ ! -f "$EXT/extension.js" ]; then
    echo "[FAIL] extension.js not found."
    exit 1
fi

if [ ! -f "$EXT/metadata.json" ]; then
    echo "[FAIL] metadata.json not found."
    exit 1
fi

echo "[PASS] Extension files"
echo

# ------------------------------------------------------------
# 2. Backup
# ------------------------------------------------------------

echo "[2/8] Creating backup..."

BACKUP="$EXT/backup-v9-before-fix-$(date +%Y%m%d-%H%M%S)"

mkdir -p "$BACKUP"

cp -a "$EXT/extension.js" "$BACKUP/extension.js"
cp -a "$EXT/metadata.json" "$BACKUP/metadata.json"

if [ -f "$EXT/niveth-audio-meter.py" ]; then
    cp -a \
        "$EXT/niveth-audio-meter.py" \
        "$BACKUP/niveth-audio-meter.py"
fi

if [ -f "$EXT/stylesheet.css" ]; then
    cp -a \
        "$EXT/stylesheet.css" \
        "$BACKUP/stylesheet.css"
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
# 4. Patch extension.js
# ------------------------------------------------------------

echo "[4/8] Applying V9 fix..."

python3 - "$EXT/extension.js" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])

text = path.read_text()

old = """        this._widget.show();

        this._widget.raise_top();
"""

new = """        this._widget.show();

        /*
         * GNOME Shell 50 does not provide raise_top()
         * on this actor.
         *
         * Keep the monitor click-through so normal
         * application interaction is not blocked.
         */
        this._widget.set_reactive(false);
"""

if old not in text:
    if "this._widget.raise_top();" in text:
        text = text.replace(
            "        this._widget.raise_top();",
            "        this._widget.set_reactive(false);"
        )
        path.write_text(text)
        print("[PASS] Replaced raise_top()")
    elif "this._widget.set_reactive(false);" in text:
        print("[PASS] V9 fix already present")
    else:
        print("[FAIL] Could not find raise_top() or existing V9 fix")
        sys.exit(1)
else:
    text = text.replace(old, new, 1)
    path.write_text(text)
    print("[PASS] Removed unsupported raise_top()")
PY

echo

# ------------------------------------------------------------
# 5. Metadata version 9
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

data["version"] = 9

path.write_text(
    json.dumps(
        data,
        indent=2,
        ensure_ascii=False
    ) + "\n"
)

print("[PASS] metadata.json -> Version 9")
PY

echo

# ------------------------------------------------------------
# 6. Verify source
# ------------------------------------------------------------

echo "[6/8] Verifying V9 source..."

if grep -Fq "this._widget.raise_top()" "$EXT/extension.js"; then
    echo "[FAIL] raise_top() still exists."
    exit 1
fi

if ! grep -Fq "this._widget.set_reactive(false)" "$EXT/extension.js"; then
    echo "[FAIL] set_reactive(false) not found."
    exit 1
fi

if ! grep -Fq "_startMetrics()" "$EXT/extension.js"; then
    echo "[FAIL] _startMetrics() missing."
    exit 1
fi

if ! grep -Fq "_startAudioMeter()" "$EXT/extension.js"; then
    echo "[FAIL] _startAudioMeter() missing."
    exit 1
fi

if ! grep -Fq "_audioHistory" "$EXT/extension.js"; then
    echo "[FAIL] _audioHistory missing."
    exit 1
fi

if ! grep -Fq "_audioBars" "$EXT/extension.js"; then
    echo "[FAIL] _audioBars missing."
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

if [ "$VERSION" != "9" ]; then
    echo "[FAIL] Metadata version is not 9."
    exit 1
fi

echo "[PASS] No raise_top()"
echo "[PASS] click-through enabled"
echo "[PASS] metrics code present"
echo "[PASS] audio code present"
echo "[PASS] Version 9"
echo

# ------------------------------------------------------------
# 7. Sync rootfs
# ------------------------------------------------------------

echo "[7/8] Synchronizing V9 to Niveth rootfs..."

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

    echo "[INFO] Niveth rootfs extension directory does not exist."
fi

echo

# ------------------------------------------------------------
# 8. Reload extension
# ------------------------------------------------------------

echo "[8/8] Reloading extension..."

gnome-extensions enable "$UUID"

sleep 2

echo
echo "============================================================"
echo " FINAL STATUS"
echo "============================================================"

gnome-extensions info "$UUID" 2>&1 || true

echo
echo "============================================================"
echo " V9 FIX COMPLETE"
echo "============================================================"
echo
echo "Backup:"
echo "  $BACKUP"
echo
echo "Expected:"
echo "  Version: 9"
echo "  Enabled: Yes"
echo "  State: ACTIVE"
echo
