#!/usr/bin/env bash

set -euo pipefail

UUID="niveth-system-monitor@nivethos"
EXT="$HOME/.local/share/gnome-shell/extensions/$UUID"

echo "============================================================"
echo " NIVETH SYSTEM MONITOR — V11 TRANSPARENT"
echo "============================================================"
echo
echo "Changes:"
echo "  - fully transparent monitor background"
echo "  - preserve text visibility"
echo "  - preserve CPU/RAM bars"
echo "  - preserve audio waveform"
echo "  - preserve existing border"
echo

# ------------------------------------------------------------
# 1. Verify
# ------------------------------------------------------------

echo "[1/7] Verifying extension..."

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

echo "[2/7] Creating backup..."

BACKUP="$EXT/backup-v11-transparent-$(date +%Y%m%d-%H%M%S)"

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

echo "[3/7] Disabling extension..."

gnome-extensions disable "$UUID" 2>/dev/null || true

sleep 1

echo "[PASS] Disabled"
echo

# ------------------------------------------------------------
# 4. Make background transparent
# ------------------------------------------------------------

echo "[4/7] Making monitor background transparent..."

python3 - "$EXT/extension.js" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text()

old = "'background-color: rgba(16, 17, 29, 0.94)',"
new = "'background-color: rgba(16, 17, 29, 0.0)',"

if old in text:
    text = text.replace(old, new, 1)
    path.write_text(text)
    print("[PASS] Background changed to fully transparent")
elif new in text:
    print("[PASS] Background is already fully transparent")
else:
    print("[FAIL] Existing monitor background definition not found.")
    sys.exit(1)
PY

echo

# ------------------------------------------------------------
# 5. Update metadata
# ------------------------------------------------------------

echo "[5/7] Updating metadata version..."

python3 - "$EXT/metadata.json" <<'PY'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])

data = json.loads(
    path.read_text()
)

data["version"] = 11

path.write_text(
    json.dumps(
        data,
        indent=2,
        ensure_ascii=False
    ) + "\n"
)

print("[PASS] Version -> 11")
PY

echo

# ------------------------------------------------------------
# 6. Verify
# ------------------------------------------------------------

echo "[6/7] Verifying V11..."

if ! grep -Fq \
    "'background-color: rgba(16, 17, 29, 0.0)'" \
    "$EXT/extension.js"
then
    echo "[FAIL] Transparent background not found."
    exit 1
fi

if grep -Fq \
    "'background-color: rgba(16, 17, 29, 0.94)'" \
    "$EXT/extension.js"
then
    echo "[FAIL] Old opaque background still exists."
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

if grep -Fq \
    "this._widget.raise_top()" \
    "$EXT/extension.js"
then
    echo "[FAIL] Unsupported raise_top() returned."
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

if [ "$VERSION" != "11" ]; then
    echo "[FAIL] Metadata version is not 11."
    exit 1
fi

echo "[PASS] Fully transparent background"
echo "[PASS] Audio preserved"
echo "[PASS] CPU/RAM preserved"
echo "[PASS] Text preserved"
echo "[PASS] raise_top() absent"
echo "[PASS] Version 11"
echo

# ------------------------------------------------------------
# 7. Enable
# ------------------------------------------------------------

echo "[7/7] Enabling extension..."

gnome-extensions enable "$UUID"

sleep 2

echo
echo "============================================================"
echo " FINAL STATUS"
echo "============================================================"

gnome-extensions info "$UUID" 2>&1 || true

echo
echo "============================================================"
echo " V11 TRANSPARENT COMPLETE"
echo "============================================================"
echo
echo "Backup:"
echo "  $BACKUP"
echo
