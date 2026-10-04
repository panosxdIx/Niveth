#!/usr/bin/env bash

set -euo pipefail

PROFILE="$HOME/.config/vivaldi/Default"
BACKUP="$PROFILE/Preferences.niveth-privacy-backup-20260916-221549"
CURRENT="$PROFILE/Preferences"

OUT="$HOME/Niveth/desktop/defaults/vivaldi"

mkdir -p "$OUT"

if [ ! -f "$BACKUP" ]; then
    echo "ERROR: Privacy backup not found:"
    echo "$BACKUP"
    exit 1
fi

if [ ! -f "$CURRENT" ]; then
    echo "ERROR: Current Vivaldi Preferences not found:"
    echo "$CURRENT"
    exit 1
fi

python3 - "$BACKUP" "$CURRENT" "$OUT" <<'PY'
import json
import sys
from pathlib import Path

backup_path = Path(sys.argv[1])
current_path = Path(sys.argv[2])
out_dir = Path(sys.argv[3])

backup = json.loads(backup_path.read_text(encoding="utf-8"))
current = json.loads(current_path.read_text(encoding="utf-8"))

KEYWORDS = (
    "privacy",
    "tracking",
    "tracker",
    "adblock",
    "ad_block",
    "blocking",
    "cookie",
    "cookies",
    "third_party",
    "webrtc",
    "dns",
    "telemetry",
    "metrics",
    "safe_browsing",
    "safebrowsing",
    "phishing",
    "prediction",
    "prefetch",
    "do_not_track",
    "dnt",
)

def walk(obj, path=()):
    if isinstance(obj, dict):
        for key, value in obj.items():
            key_lower = str(key).lower()
            new_path = path + (str(key),)

            if any(term in key_lower for term in KEYWORDS):
                yield ".".join(new_path), value

            yield from walk(value, new_path)

    elif isinstance(obj, list):
        for index, value in enumerate(obj):
            yield from walk(value, path + (str(index),))


backup_items = dict(walk(backup))
current_items = dict(walk(current))

changed = {}
for path, backup_value in backup_items.items():
    current_value = current_items.get(path, object())

    if backup_value != current_value:
        changed[path] = {
            "value": backup_value,
            "current": current_value,
        }

result = {
    "source": "Preferences.niveth-privacy-backup-20260916-221549",
    "matched_backup_settings": len(backup_items),
    "changed_or_added_settings": len(changed),
    "settings": changed,
}

output = out_dir / "privacy-diff.json"
output.write_text(
    json.dumps(result, indent=2, ensure_ascii=False),
    encoding="utf-8",
)

print("============================================================")
print("        NIVETH VIVALDI PRIVACY EXTRACTION")
print("============================================================")
print()
print(f"Backup:  {backup_path}")
print(f"Current: {current_path}")
print()
print(f"Matched privacy-related backup entries: {len(backup_items)}")
print(f"Changed/added entries: {len(changed)}")
print()
print(f"Output:")
print(f"  {output}")
print()
print("=== CHANGED PRIVACY SETTINGS ===")

for path, data in changed.items():
    print()
    print(f"[{path}]")
    print("backup :", json.dumps(
        data["value"],
        ensure_ascii=False,
        separators=(",", ":")
    ))
    print("current:", json.dumps(
        data["current"],
        ensure_ascii=False,
        separators=(",", ":")
    ))

PY

chmod +x ~/Niveth/scripts/extract-vivaldi-privacy.sh
~/Niveth/scripts/extract-vivaldi-privacy.sh
