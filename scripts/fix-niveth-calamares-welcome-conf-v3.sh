#!/usr/bin/env bash

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ROOTFS="$PROJECT_ROOT/build/rootfs"
INSTALLER="$PROJECT_ROOT/installer"

SOURCE="$INSTALLER/modules/welcome.conf"
TARGET="$ROOTFS/etc/calamares/modules/welcome.conf"

BACKUP="$PROJECT_ROOT/integration-backups/niveth-welcome-conf-v3-$(date +%Y%m%d-%H%M%S)"

echo "=============================================="
echo " NIVETH CALAMARES WELCOME.CONF V3"
echo "=============================================="

if [[ ! -d "$ROOTFS" ]]; then
    echo "[ERROR] Rootfs not found:"
    echo "        $ROOTFS"
    exit 1
fi

mkdir -p "$INSTALLER/modules"
mkdir -p "$BACKUP"

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
echo "=== 2. WRITE FINAL WELCOME.CONF ==="

cat > "$SOURCE" <<'WELCOME'
---
showSupportUrl: false
showKnownIssuesUrl: false
showReleaseNotesUrl: false
showDonateUrl: false

requirements:

    requiredRam: 1.0

    check:
        - ram
        - power
        - screen

    required:
        - ram
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
        raise SystemExit(f"[ERROR] Invalid YAML: {path}")

    req = data.get("requirements")

    if not isinstance(req, dict):
        raise SystemExit(f"[ERROR] requirements missing: {path}")

    required_keys = {
        "requiredStorage",
        "requiredRam",
        "check",
        "required",
    }

    missing = required_keys - req.keys()

    if missing:
        raise SystemExit(
            f"[ERROR] Missing requirements keys in {path}: {sorted(missing)}"
        )

    if "internet" in req["check"]:
        raise SystemExit(
            f"[ERROR] internet check is still enabled: {path}"
        )

    if "storage" in req["required"]:
        raise SystemExit(
            f"[ERROR] storage must not be mandatory: {path}"
        )

    if "ram" not in req["required"]:
        raise SystemExit(
            f"[ERROR] ram must remain mandatory: {path}"
        )

    print(f"[PASS] YAML/schema: {path}")
PY

echo
echo "=== 5. CHECK FINAL VALUES ==="

grep -q '^    requiredStorage: 5.5$' "$TARGET"
grep -q '^    requiredRam: 1.0$' "$TARGET"
grep -q '^    check:$' "$TARGET"
grep -q '^    required:$' "$TARGET"
grep -q '^        - storage$' "$TARGET"
grep -q '^        - ram$' "$TARGET"
grep -q '^        - power$' "$TARGET"
grep -q '^        - screen$' "$TARGET"

echo "[PASS] requiredStorage=5.5"
echo "[PASS] requiredRam=1.0"
echo "[PASS] storage check"
echo "[PASS] RAM check"
echo "[PASS] power check"
echo "[PASS] screen check"
echo "[PASS] RAM mandatory"

echo
echo "=== 6. VERIFY INTERNET IS NOT USED ==="

if grep -q '^        - internet$' "$TARGET"; then
    echo "[ERROR] Internet is still in requirements.check"
    exit 1
fi

if grep -q 'internetCheckUrl:' "$TARGET"; then
    echo "[ERROR] internetCheckUrl is still present"
    exit 1
fi

echo "[PASS] No Internet requirement"
echo "[PASS] No internetCheckUrl"

echo
echo "=== 7. VERIFY GEOIP IS NOT USED ==="

if grep -q '^geoip:' "$TARGET"; then
    echo "[ERROR] GeoIP section is still present"
    exit 1
fi

echo "[PASS] No GeoIP section"

echo
echo "=== 8. FINAL CONFIG ==="

sudo cat "$TARGET"

echo
echo "=============================================="
echo " NIVETH WELCOME.CONF V3 READY"
echo "=============================================="
echo
echo "NO ISO BUILD PERFORMED."
