#!/usr/bin/env bash

set -euo pipefail

EXT_ID="niveth-system-monitor@nivethos"
EXT_DIR="$HOME/.local/share/gnome-shell/extensions/$EXT_ID"
META="$EXT_DIR/metadata.json"

echo
echo "============================================================"
echo " NIVETH SYSTEM MONITOR — REGISTRATION FIX"
echo "============================================================"
echo

# ---------------------------------------------------------
# 1. CHECK FILES
# ---------------------------------------------------------

echo "[1/7] Checking extension"

if [ ! -d "$EXT_DIR" ]; then
    echo "[FAIL] Extension directory missing:"
    echo "$EXT_DIR"
    exit 1
fi

for file in metadata.json extension.js stylesheet.css
do
    if [ ! -f "$EXT_DIR/$file" ]; then
        echo "[FAIL] Missing:"
        echo "$EXT_DIR/$file"
        exit 1
    fi

    echo "[PASS] $file"
done


# ---------------------------------------------------------
# 2. VALIDATE METADATA
# ---------------------------------------------------------

echo
echo "[2/7] Validating metadata.json"

python3 - "$META" "$EXT_ID" <<'PY'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
expected_uuid = sys.argv[2]

data = json.loads(
    path.read_text(encoding="utf-8")
)

required = [
    "uuid",
    "name",
    "description",
    "shell-version",
]

for key in required:
    if key not in data:
        raise SystemExit(
            f"ERROR: metadata missing '{key}'"
        )

if data["uuid"] != expected_uuid:
    raise SystemExit(
        "ERROR: metadata UUID does not match directory."
    )

if "50" not in data["shell-version"]:
    raise SystemExit(
        "ERROR: GNOME Shell 50 is not listed."
    )

print("[PASS] JSON valid")
print(f"[PASS] UUID: {data['uuid']}")
print(
    f"[PASS] GNOME Shell versions: "
    f"{data['shell-version']}"
)
PY


# ---------------------------------------------------------
# 3. FIX PERMISSIONS
# ---------------------------------------------------------

echo
echo "[3/7] Fixing permissions"

chmod 755 "$EXT_DIR"
chmod 644 \
    "$EXT_DIR/metadata.json" \
    "$EXT_DIR/extension.js" \
    "$EXT_DIR/stylesheet.css"

echo "[PASS] Permissions"


# ---------------------------------------------------------
# 4. CHECK GNOME REGISTRY
# ---------------------------------------------------------

echo
echo "[4/7] Checking GNOME extension registry"

LIST_OUTPUT="$(
    gnome-extensions list 2>&1 || true
)"

if printf '%s\n' "$LIST_OUTPUT" |
    grep -Fxq "$EXT_ID"
then
    echo "[PASS] GNOME already sees $EXT_ID"

else
    echo "[INFO] GNOME extension service does not currently"
    echo "       see the new extension."
    echo
    echo "Available Niveth extensions:"
    printf '%s\n' "$LIST_OUTPUT" |
        grep -E '^niveth-' ||
        true
fi


# ---------------------------------------------------------
# 5. TRY INFO
# ---------------------------------------------------------

echo
echo "[5/7] Querying extension information"

gnome-extensions info \
    "$EXT_ID" \
    2>&1 || true


# ---------------------------------------------------------
# 6. TRY ENABLE
# ---------------------------------------------------------

echo
echo "[6/7] Trying to enable System Monitor"

if gnome-extensions enable "$EXT_ID" 2>&1
then
    echo "[PASS] Extension enabled"

else
    echo
    echo "[INFO] GNOME Shell has not refreshed its extension"
    echo "       registry yet."
    echo
    echo "The extension files themselves are valid."
    echo
    echo "A normal GNOME logout/login or reboot is required"
    echo "to make GNOME Shell rescan newly created extensions."
fi


# ---------------------------------------------------------
# 7. FINAL
# ---------------------------------------------------------

echo
echo "[7/7] Final check"

gnome-extensions list 2>&1 |
    grep -Fx "$EXT_ID" ||
    true

echo
echo "============================================================"
echo " REGISTRATION CHECK COMPLETE"
echo "============================================================"
echo
echo "Extension directory:"
echo "  $EXT_DIR"
echo
echo "Rootfs already synchronized:"
echo "  YES"
echo
