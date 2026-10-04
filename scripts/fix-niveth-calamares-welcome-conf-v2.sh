#!/usr/bin/env bash

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ROOTFS="$PROJECT_ROOT/build/rootfs"
INSTALLER="$PROJECT_ROOT/installer"

SOURCE="$INSTALLER/modules/welcome.conf"
TARGET="$ROOTFS/etc/calamares/modules/welcome.conf"

BACKUP="$PROJECT_ROOT/integration-backups/niveth-welcome-conf-v2-$(date +%Y%m%d-%H%M%S)"

echo "=============================================="
echo " NIVETH CALAMARES WELCOME.CONF V2"
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
echo "=== 2. WRITE WELCOME.CONF ==="

cat > "$SOURCE" <<'WELCOME'
---
showSupportUrl: false
showKnownIssuesUrl: false
showReleaseNotesUrl: false
showDonateUrl: false

requirements:

    requiredStorage: 5.5
    requiredRam: 1.0

    # This URL is only used if "internet" is added
    # to the check list.
    internetCheckUrl: "https://example.com"

    check:
        - storage
        - ram
        - power
        - screen

    # Storage is intentionally not mandatory here.
    # The partition module performs the real disk-space checks.
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
        raise SystemExit(f"[ERROR] requirements section missing: {path}")

    for key in (
        "requiredStorage",
        "requiredRam",
        "internetCheckUrl",
        "check",
        "required",
    ):
        if key not in req:
            raise SystemExit(
                f"[ERROR] requirements.{key} missing: {path}"
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
echo "=== 5. CHECK VALUES ==="

grep -q '^    requiredStorage: 5.5$' \
    "$TARGET"

grep -q '^    requiredRam: 1.0$' \
    "$TARGET"

grep -q '^    internetCheckUrl: "https://example.com"$' \
    "$TARGET"

grep -q '^    check:$' \
    "$TARGET"

grep -q '^    required:$' \
    "$TARGET"

grep -q '^        - storage$' \
    "$TARGET"

grep -q '^        - ram$' \
    "$TARGET"

grep -q '^        - ram$' \
    "$TARGET"

if grep -q '^        - storage$' "$TARGET" \
    | grep -q .
then
    :
fi

echo "[PASS] requiredStorage=5.5"
echo "[PASS] requiredRam=1.0"
echo "[PASS] internetCheckUrl defined"
echo "[PASS] storage is checked"
echo "[PASS] RAM is checked"
echo "[PASS] RAM is mandatory"

echo
echo "=== 6. VERIFY STORAGE IS NOT MANDATORY ==="

python3 - <<PY
from pathlib import Path
import yaml

path = Path("$TARGET")

with path.open("r", encoding="utf-8") as f:
    data = yaml.safe_load(f)

required = data["requirements"]["required"]

if "storage" in required:
    raise SystemExit("[ERROR] storage is still mandatory")

if "ram" not in required:
    raise SystemExit("[ERROR] ram is no longer mandatory")

print("[PASS] storage is optional at welcome stage")
print("[PASS] ram is mandatory at welcome stage")
PY

echo
echo "=== 7. VERIFY GEOIP IS DISABLED ==="

if grep -q '^geoip:' "$TARGET"; then
    echo "[ERROR] geoip section still exists"
    exit 1
fi

echo "[PASS] No geoip section"

echo
echo "=== 8. FINAL CONFIG ==="

sudo cat "$TARGET"

echo
echo "=============================================="
echo " NIVETH WELCOME.CONF V2 READY"
echo "=============================================="
echo
echo "NO ISO BUILD PERFORMED."
