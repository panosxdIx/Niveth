#!/usr/bin/env bash

set -euo pipefail

PROFILE="$HOME/.config/vivaldi/Default"
BACKUP="$PROFILE/Preferences.niveth-privacy-backup-20260916-221549"
CURRENT="$PROFILE/Preferences"

OUT="$HOME/Niveth/desktop/defaults/vivaldi"

mkdir -p "$OUT"

if [[ ! -f "$BACKUP" ]]; then
    echo "ERROR: Backup not found:"
    echo "$BACKUP"
    exit 1
fi

if [[ ! -f "$CURRENT" ]]; then
    echo "ERROR: Current Preferences not found:"
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

# Runtime / personal / volatile data that must NEVER become Niveth defaults.
EXCLUDED_EXACT = {
    "gaia_cookie",
    "account_tracker_service_last_update",
    "commerce_daily_metrics_last_update_time",
    "profile.last_time_password_store_metrics_reported",
    "profile.content_settings.exceptions.permission_autoblocking_data",
    "safebrowsing.metrics_last_log_time",
    "safebrowsing.event_timestamps",
    "safebrowsing.saw_interstitial_sber2",
}

EXCLUDED_TERMS = (
    "cookie_store",
    "session",
    "last_update",
    "last_modified",
    "last_time",
    "metrics",
    "daily_metrics",
    "report_time",
    "reporting_time",
    "gaia_cookie",
    "account_tracker",
    "login",
    "password",
    "sync",
    "history",
    "recent",
    "tabs",
    "windows",
)

PRIVACY_TERMS = (
    "privacy",
    "tracker",
    "tracking",
    "adblock",
    "ad_block",
    "blocking",
    "block",
    "cookie",
    "third_party",
    "do_not_track",
    "dnt",
    "safe_browsing",
    "safebrowsing",
    "phishing",
    "prediction",
    "prefetch",
    "webrtc",
    "dns",
    "telemetry",
    "fingerprint",
)

def flatten(obj, path=()):
    result = {}

    if isinstance(obj, dict):
        for key, value in obj.items():
            new_path = path + (str(key),)
            result.update(flatten(value, new_path))

    elif isinstance(obj, list):
        for index, value in enumerate(obj):
            new_path = path + (str(index),)
            result.update(flatten(value, new_path))

    else:
        result[".".join(path)] = obj

    return result


def excluded(path):
    p = path.lower()

    if path in EXCLUDED_EXACT:
        return True

    for term in EXCLUDED_TERMS:
        if term in p:
            return True

    return False


def looks_privacy_related(path):
    p = path.lower()
    return any(term in p for term in PRIVACY_TERMS)


backup_flat = flatten(backup)
current_flat = flatten(current)

all_paths = sorted(set(backup_flat) | set(current_flat))

changed = {}
privacy_candidates = {}

for path in all_paths:
    if path not in backup_flat:
        continue

    if path not in current_flat:
        continue

    if backup_flat[path] == current_flat[path]:
        continue

    if excluded(path):
        continue

    item = {
        "backup": backup_flat[path],
        "current": current_flat[path],
    }

    changed[path] = item

    if looks_privacy_related(path):
        privacy_candidates[path] = item


result = {
    "source": backup_path.name,
    "description": "Niveth-safe Vivaldi privacy candidate extraction",
    "changed_nonvolatile_settings": changed,
    "privacy_candidates": privacy_candidates,
}

output = out_dir / "privacy-diff-v2.json"

output.write_text(
    json.dumps(result, indent=2, ensure_ascii=False),
    encoding="utf-8",
)

print("============================================================")
print("       NIVETH VIVALDI PRIVACY EXTRACTION V2")
print("============================================================")
print()
print(f"Backup:  {backup_path}")
print(f"Current: {current_path}")
print()
print(f"Changed non-volatile settings: {len(changed)}")
print(f"Privacy candidates:             {len(privacy_candidates)}")
print()
print(f"Output:")
print(f"  {output}")
print()
print("=== PRIVACY CANDIDATES ===")

if not privacy_candidates:
    print()
    print("No privacy candidates found.")
else:
    for path, item in privacy_candidates.items():
        print()
        print(f"[{path}]")
        print(
            "backup :",
            json.dumps(
                item["backup"],
                ensure_ascii=False,
                separators=(",", ":"),
            ),
        )
        print(
            "current:",
            json.dumps(
                item["current"],
                ensure_ascii=False,
                separators=(",", ":"),
            ),
        )

print()
print("=== DONE ===")
PY

chmod +x ~/Niveth/scripts/extract-vivaldi-privacy-v2.sh
~/Niveth/scripts/extract-vivaldi-privacy-v2.sh
