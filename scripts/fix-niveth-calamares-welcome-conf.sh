#!/usr/bin/env bash

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ROOTFS="$PROJECT_ROOT/build/rootfs"
INSTALLER="$PROJECT_ROOT/installer"
SOURCE="$INSTALLER/modules/welcome.conf"
TARGET="$ROOTFS/etc/calamares/modules/welcome.conf"
BACKUP="$PROJECT_ROOT/integration-backups/niveth-welcome-conf-$(date +%Y%m%d-%H%M%S)"

if [[ ! -d "$ROOTFS" ]]; then
    echo "[ERROR] Rootfs not found:"
    echo "        $ROOTFS"
    exit 1
fi

mkdir -p "$INSTALLER/modules"
mkdir -p "$BACKUP"

echo "=============================================="
echo " NIVETH CALAMARES WELCOME.CONFIG FIX"
echo "=============================================="

echo
echo "=== 1. BACKUP ==="

if [[ -f "$SOURCE" ]]; then
    cp "$SOURCE" "$BACKUP/welcome.conf.source"
fi

if [[ -f "$TARGET" ]]; then
    sudo cp "$TARGET" "$BACKUP/welcome.conf.rootfs"
fi

echo "[PASS] Backup:"
echo "       $BACKUP"

echo
echo "=== 2. WRITE CORRECT WELCOME CONFIG ==="

cat > "$SOURCE" <<'WELCOME'
---
showSupportUrl: false
showKnownIssuesUrl: false
showReleaseNotesUrl: false
showDonateUrl: false

requirements:

    requiredStorage: 5.5
    requiredRam: 1.0

    check:
        - storage
        - ram
        - power
        - screen

    required:
        - storage
        - ram

geoip:

    style: "none"
WELCOME

echo "[PASS] Source welcome.conf written"

echo
echo "=== 3. SYNC TO ROOTFS ==="

sudo cp \
    "$SOURCE" \
    "$TARGET"

echo "[PASS] Rootfs welcome.conf synchronized"

echo
echo "=== 4. YAML VALIDATION ==="

python3 - <<PY
from pathlib import Path
import yaml

for path in [
    Path("$SOURCE"),
    Path("$TARGET"),
]:
    with path.open("r", encoding="utf-8") as f:
        data = yaml.safe_load(f)

    if not isinstance(data, dict):
        raise SystemExit(f"[ERROR] Invalid YAML document: {path}")

    if "requirements" not in data:
        raise SystemExit(f"[ERROR] requirements missing: {path}")

    req = data["requirements"]

    for key in ("requiredStorage", "requiredRam", "check", "required"):
        if key not in req:
            raise SystemExit(
                f"[ERROR] requirements.{key} missing: {path}"
            )

    if not isinstance(req["check"], list):
        raise SystemExit(f"[ERROR] requirements.check is not a list: {path}")

    if not isinstance(req["required"], list):
        raise SystemExit(f"[ERROR] requirements.required is not a list: {path}")

    print(f"[PASS] YAML/schema: {path}")
PY

echo
echo "=== 5. CHECK REQUIRED VALUES ==="

grep -q '^    requiredStorage: 5.5$' \
    "$TARGET"

grep -q '^    requiredRam: 1.0$' \
    "$TARGET"

grep -q '^    check:$' \
    "$TARGET"

grep -q '^    required:$' \
    "$TARGET"

grep -q '^        - storage$' \
    "$TARGET"

grep -q '^        - ram$' \
    "$TARGET"

grep -q '^geoip:$' \
    "$TARGET"

grep -q '^    style: "none"$' \
    "$TARGET"

echo "[PASS] requiredStorage=5.5"
echo "[PASS] requiredRam=1.0"
echo "[PASS] storage check"
echo "[PASS] RAM check"
echo "[PASS] storage required"
echo "[PASS] RAM required"
echo "[PASS] welcome GeoIP disabled"

echo
echo "=== 6. MAKE SURE INTERNET IS NOT REQUIRED ==="

if grep -qE '^[[:space:]]+- internet$' "$TARGET"; then
    echo "[ERROR] Internet is still configured as a requirement"
    exit 1
fi

if grep -q 'internetCheckUrl:' "$TARGET"; then
    echo "[ERROR] internetCheckUrl should not be present"
    exit 1
fi

echo "[PASS] Internet is optional"
echo "[PASS] No example.com fallback"

echo
echo "=== 7. FINAL WELCOME CONFIG ==="

sudo cat "$TARGET"

echo
echo "=============================================="
echo " NIVETH WELCOME CONFIG FIXED"
echo "=============================================="
echo
echo "NO ISO BUILD PERFORMED."
