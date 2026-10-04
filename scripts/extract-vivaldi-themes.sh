#!/usr/bin/env bash

set -u

VIVALDI="$HOME/.config/vivaldi"
OUT="$HOME/Niveth/vivaldi-theme-extract.txt"

DARK_ID="b466491a-240d-4ec9-ba02-30abc5edd94d"
LIGHT_ID="cc134c1f-b0d6-43b4-9e25-af813f93de5b"

exec > >(tee "$OUT") 2>&1

echo "============================================================"
echo "NIVETH VIVALDI THEME EXTRACTION"
echo "============================================================"
echo
echo "Vivaldi profile: $VIVALDI"
echo

if [ ! -d "$VIVALDI" ]; then
    echo "ERROR: Vivaldi profile directory not found."
    exit 1
fi

echo "=== 1. THEME SCHEDULE ==="

python3 - "$VIVALDI/Default/Preferences" <<'PY'
from pathlib import Path
import json
import sys

path = Path(sys.argv[1])

if not path.is_file():
    print("Preferences file not found")
    raise SystemExit(0)

data = json.loads(path.read_text(encoding="utf-8"))

print(json.dumps(
    data.get("vivaldi", {}).get("theme", {}),
    indent=2,
    ensure_ascii=False
))
PY

echo
echo "=== 2. SEARCHING FOR DARK THEME ID ==="
echo "$DARK_ID"

grep -RIl \
    --exclude='LOCK' \
    --exclude='LOG' \
    --exclude='LOG.old' \
    --exclude='*.log' \
    --exclude='*.ldb' \
    "$DARK_ID" \
    "$VIVALDI" \
    2>/dev/null | sort | head -100

echo
echo "=== 3. SEARCHING FOR LIGHT THEME ID ==="
echo "$LIGHT_ID"

grep -RIl \
    --exclude='LOCK' \
    --exclude='LOG' \
    --exclude='LOG.old' \
    --exclude='*.log' \
    --exclude='*.ldb' \
    "$LIGHT_ID" \
    "$VIVALDI" \
    2>/dev/null | sort | head -100

echo
echo "=== 4. RELEVANT THEME FILES ==="

find "$VIVALDI" \
    -type f \
    \( \
        -iname '*theme*' \
        -o -iname '*skin*' \
        -o -iname '*appearance*' \
    \) \
    2>/dev/null | sort | head -200

echo
echo "=== 5. THEME DATA IN JSON FILES ==="

python3 - "$VIVALDI" "$DARK_ID" "$LIGHT_ID" <<'PY'
from pathlib import Path
import json
import sys

root = Path(sys.argv[1])
ids = {sys.argv[2], sys.argv[3]}

skip_parts = {
    "Cache",
    "Code Cache",
    "GPUCache",
    "DawnGraphiteCache",
    "DawnWebGPUCache",
    "Crash Reports",
}

def contains_id(value):
    if isinstance(value, str):
        return any(i in value for i in ids)
    if isinstance(value, dict):
        return any(contains_id(v) for v in value.values())
    if isinstance(value, list):
        return any(contains_id(v) for v in value)
    return False

def print_matching_paths(value, path=()):
    if isinstance(value, dict):
        for key, child in value.items():
            p = path + (str(key),)

            if "theme" in str(key).lower() or contains_id(child):
                print()
                print("PATH:", ".".join(p))
                try:
                    print(json.dumps(
                        child,
                        indent=2,
                        ensure_ascii=False
                    )[:16000])
                except Exception:
                    print(repr(child)[:16000])

            print_matching_paths(child, p)

    elif isinstance(value, list):
        for i, child in enumerate(value):
            print_matching_paths(child, path + (str(i),))

files = []

for path in root.rglob("*"):
    if not path.is_file():
        continue

    if any(part in skip_parts for part in path.parts):
        continue

    if path.name not in {
        "Preferences",
        "Local State",
        "Secure Preferences",
        "sessions.json",
        "state.json",
    } and path.suffix.lower() != ".json":
        continue

    files.append(path)

for path in sorted(files):
    try:
        data = json.loads(path.read_text(
            encoding="utf-8",
            errors="ignore"
        ))
    except Exception:
        continue

    if not contains_id(data):
        continue

    print()
    print("============================================================")
    print("FILE:", path)
    print("============================================================")

    print_matching_paths(data)
PY

echo
echo "=== 6. POSSIBLE CUSTOM VIVALDI THEME FILES ==="

find "$VIVALDI" \
    -type f \
    \( \
        -iname '*.json' \
        -o -iname '*.css' \
        -o -iname '*.theme' \
        -o -iname '*.zip' \
    \) \
    2>/dev/null | \
    grep -Ei 'theme|skin|appearance|custom' | \
    sort | head -300

echo
echo "=== 7. PERSONAL-DATA CHECK ==="

echo "This extraction report does NOT copy:"
echo "  - Cookies"
echo "  - History"
echo "  - Bookmarks"
echo "  - Passwords"
echo "  - Sessions"
echo "  - Account data"
echo

echo "Report saved to:"
echo "$OUT"

echo
echo "============================================================"
echo "END"
echo "============================================================"
