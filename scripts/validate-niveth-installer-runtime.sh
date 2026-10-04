#!/usr/bin/env bash

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ROOTFS="$PROJECT_ROOT/build/rootfs"

SETTINGS="$ROOTFS/etc/calamares/settings.conf"
BRANDING="$ROOTFS/etc/calamares/branding/niveth/branding.desc"
MODULE_DIR_1="$ROOTFS/usr/lib/x86_64-linux-gnu/calamares/modules"
MODULE_DIR_2="$ROOTFS/usr/lib/calamares/modules"

echo "=============================================="
echo " NIVETH CALAMARES RUNTIME / CONFIG VALIDATION"
echo "=============================================="

if [[ ! -d "$ROOTFS" ]]; then
    echo "[ERROR] Rootfs not found:"
    echo "        $ROOTFS"
    exit 1
fi

echo
echo "=== 1. CALAMARES VERSION ==="

sudo chroot "$ROOTFS" /usr/bin/calamares --version

echo
echo "=== 2. CALAMARES HELP / CLI ==="

sudo chroot "$ROOTFS" /usr/bin/calamares --help | head -40

echo
echo "=== 3. REQUIRED CONFIG FILES ==="

for file in \
    "$SETTINGS" \
    "$BRANDING" \
    "$ROOTFS/etc/calamares/modules/bootloader.conf" \
    "$ROOTFS/etc/calamares/modules/locale.conf" \
    "$ROOTFS/etc/calamares/modules/grubcfg.conf"
do
    if [[ ! -f "$file" ]]; then
        echo "[ERROR] Missing:"
        echo "        $file"
        exit 1
    fi

    echo "[PASS] $file"
done

echo
echo "=== 4. PYTHON YAML VALIDATION ==="

python3 - <<PY
from pathlib import Path

try:
    import yaml
except Exception as exc:
    raise SystemExit(
        "[ERROR] PyYAML is not available on the host: " + str(exc)
    )

files = [
    Path("$SETTINGS"),
    Path("$BRANDING"),
    Path("$ROOTFS/etc/calamares/modules/bootloader.conf"),
    Path("$ROOTFS/etc/calamares/modules/locale.conf"),
    Path("$ROOTFS/etc/calamares/modules/grubcfg.conf"),
]

for path in files:
    try:
        with path.open("r", encoding="utf-8") as f:
            data = yaml.safe_load(f)

        if data is None:
            raise RuntimeError("empty YAML document")

        print(f"[PASS] YAML: {path}")
    except Exception as exc:
        raise SystemExit(
            f"[ERROR] YAML failed: {path}\\n        {exc}"
        )
PY

echo
echo "=== 5. SETTINGS STRUCTURE ==="

python3 - <<PY
from pathlib import Path
import yaml

path = Path("$SETTINGS")

with path.open("r", encoding="utf-8") as f:
    data = yaml.safe_load(f)

if not isinstance(data, dict):
    raise SystemExit("[ERROR] settings.conf is not a YAML map")

required = [
    "modules-search",
    "sequence",
    "branding",
    "prompt-install",
    "dont-chroot",
    "oem-setup",
]

for key in required:
    if key not in data:
        raise SystemExit(f"[ERROR] Missing settings key: {key}")
    print(f"[PASS] settings key: {key}")

if data["branding"] != "niveth":
    raise SystemExit(
        f"[ERROR] Unexpected branding: {data['branding']!r}"
    )

print("[PASS] branding=niveth")

if "local" not in data["modules-search"]:
    raise SystemExit("[ERROR] modules-search does not contain local")

print("[PASS] modules-search contains local")

if not isinstance(data["sequence"], list):
    raise SystemExit("[ERROR] sequence is not a list")

print(f"[PASS] sequence phases: {len(data['sequence'])}")

instances = data.get("instances", [])

if not isinstance(instances, list):
    raise SystemExit("[ERROR] instances is not a list")

print(f"[PASS] configured instances: {len(instances)}")
PY

echo
echo "=== 6. MODULE DIRECTORY CHECK ==="

for module in \
    bootloader \
    contextualprocess \
    finished \
    fstab \
    grubcfg \
    initramfscfg \
    initramfs \
    keyboard \
    locale \
    localecfg \
    luksbootkeyfile \
    machineid \
    mount \
    networkcfg \
    partition \
    shellprocess \
    summary \
    umount \
    unpackfs \
    users \
    welcome
do

    if [[ -d "$MODULE_DIR_1/$module" || -d "$MODULE_DIR_2/$module" ]]; then
        echo "[PASS] module: $module"
    else
        echo "[ERROR] module missing: $module"
        exit 1
    fi

done

echo
echo "=== 7. CUSTOM INSTANCE CONFIG CHECK ==="

for config in \
    before_bootloader_context.conf \
    shellprocess_before_bootloader_kerncopy.conf \
    shellprocess_logs.conf \
    shellprocess_bug-LP#1829805.conf \
    shellprocess_add386arch.conf \
    shellprocess_fixconkeys_part1.conf \
    shellprocess_fixconkeys_part2.conf
do

    if [[ -f "$ROOTFS/etc/calamares/modules/$config" ]]; then
        echo "[PASS] instance config: $config"
    else
        echo "[ERROR] instance config missing: $config"
        exit 1
    fi

done

echo
echo "=== 8. BOOTLOADER CONFIG CHECK ==="

grep -q '^efiBootLoader: "grub"$' \
    "$ROOTFS/etc/calamares/modules/bootloader.conf"

grep -q '^efiBootloaderId: "ubuntu"$' \
    "$ROOTFS/etc/calamares/modules/bootloader.conf"

grep -q '^installEFIFallback: true$' \
    "$ROOTFS/etc/calamares/modules/bootloader.conf"

echo "[PASS] GRUB"
echo "[PASS] EFI identifier"
echo "[PASS] EFI fallback"

echo
echo "=== 9. LOCALE CONFIG CHECK ==="

grep -q '^useSystemTimezone: true$' \
    "$ROOTFS/etc/calamares/modules/locale.conf"

grep -q '^adjustLiveTimezone: true$' \
    "$ROOTFS/etc/calamares/modules/locale.conf"

if grep -q '^geoip:' \
    "$ROOTFS/etc/calamares/modules/locale.conf"
then
    echo "[ERROR] GeoIP is enabled"
    exit 1
else
    echo "[PASS] No GeoIP dependency"
fi

echo "[PASS] useSystemTimezone=true"
echo "[PASS] adjustLiveTimezone=true"

echo
echo "=== 10. BRANDING SCHEMA KEYS ==="

python3 - <<PY
from pathlib import Path
import yaml

branding = Path("$BRANDING")

with branding.open("r", encoding="utf-8") as f:
    data = yaml.safe_load(f)

required_top = [
    "componentName",
    "welcomeStyleCalamares",
    "welcomeExpandingLogo",
    "windowExpanding",
    "windowSize",
    "windowPlacement",
    "sidebar",
    "navigation",
    "strings",
    "style",
]

for key in required_top:
    if key not in data:
        raise SystemExit(
            f"[ERROR] branding.desc missing top-level key: {key}"
        )
    print(f"[PASS] branding key: {key}")

strings = data["strings"]

for key in [
    "productName",
    "shortProductName",
    "version",
    "shortVersion",
    "versionedName",
    "shortVersionedName",
    "bootloaderEntryName",
]:
    if key not in strings:
        raise SystemExit(
            f"[ERROR] branding strings missing: {key}"
        )
    print(f"[PASS] branding string: {key}")
PY

echo
echo "=== 11. COMPARE NIVETH BRANDING WITH DEFAULT SCHEMA ==="

DEFAULT_BRANDING="$ROOTFS/usr/share/calamares/branding/default/branding.desc"

if [[ ! -f "$DEFAULT_BRANDING" ]]; then
    echo "[ERROR] Default Calamares branding.desc missing"
    exit 1
fi

echo "[PASS] Default branding.desc exists:"
echo "       $DEFAULT_BRANDING"

echo
echo "--- Default style keys ---"

grep -E '^[A-Za-z][A-Za-z0-9]*:' \
    "$DEFAULT_BRANDING" |
    grep -E 'Sidebar|sidebar' |
    head -20 || true

echo
echo "--- Niveth style keys ---"

grep -E '^[A-Za-z][A-Za-z0-9]*:' \
    "$BRANDING" |
    grep -E 'Sidebar|sidebar' |
    head -20 || true

echo
echo "=== 12. CALAMARES CONFIG DIRECTORY TEST ==="

TESTDIR="$(mktemp -d)"

cleanup() {
    rm -rf "$TESTDIR"
}

trap cleanup EXIT

sudo cp \
    "$SETTINGS" \
    "$TESTDIR/settings.conf"

sudo cp -a \
    "$ROOTFS/etc/calamares/modules" \
    "$TESTDIR/modules"

sudo mkdir -p \
    "$TESTDIR/branding/niveth"

sudo cp \
    "$BRANDING" \
    "$TESTDIR/branding/niveth/branding.desc"

echo "[PASS] Temporary Calamares configuration tree created:"
echo "       $TESTDIR"

echo
echo "=== 13. ROOTFS CALAMARES CLI TEST ==="

sudo chroot "$ROOTFS" \
    /usr/bin/calamares \
    --version

echo "[PASS] Calamares executable runs inside rootfs"

echo
echo "=== 14. SESSION LOG LOCATION ==="

echo "Calamares normally writes its session log under:"
echo "  ~/.cache/calamares/session.log"

echo
echo "=============================================="
echo " NIVETH CALAMARES STATIC VALIDATION PASSED"
echo "=============================================="
echo
echo "NO ROOTFS CHANGES WERE MADE."
echo "NO ISO BUILD WAS PERFORMED."
echo
echo "Next test:"
echo "actual Calamares startup with -D6."
