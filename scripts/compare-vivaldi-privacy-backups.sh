#!/usr/bin/env bash

set -euo pipefail

PROFILE="$HOME/.config/vivaldi/Default"

BEFORE="$PROFILE/Preferences.niveth-backup-20260916-215634"
AFTER="$PROFILE/Preferences.niveth-privacy-backup-20260916-221549"

python3 - "$BEFORE" "$AFTER" <<'PY'
import json
import sys

before_path = sys.argv[1]
after_path = sys.argv[2]

with open(before_path, encoding="utf-8") as f:
    before = json.load(f)

with open(after_path, encoding="utf-8") as f:
    after = json.load(f)

def flatten(obj, path=()):
    result = {}

    if isinstance(obj, dict):
        for key, value in obj.items():
            p = path + (str(key),)
            result.update(flatten(value, p))

    elif isinstance(obj, list):
        for i, value in enumerate(obj):
            p = path + (str(i),)
            result.update(flatten(value, p))

    else:
        result[".".join(path)] = obj

    return result


# Dynamic/personal data we don't want to report as Niveth defaults.
EXCLUDED = (
    "last_update",
    "last_modified",
    "timestamp",
    "session",
    "history",
    "cookie",
    "password",
    "login",
    "sync",
    "metrics",
    "report_time",
    "crash",
    "window_placement",
)

before_flat = flatten(before)
after_flat = flatten(after)

changes = []

for path in sorted(set(before_flat) | set(after_flat)):
    if before_flat.get(path) == after_flat.get(path):
        continue

    low = path.lower()

    if any(term in low for term in EXCLUDED):
        continue

    changes.append(path)

print("============================================================")
print("     VIVALDI BEFORE -> PRIVACY BACKUP COMPARISON")
print("============================================================")
print()
print("BEFORE:")
print(before_path)
print()
print("AFTER:")
print(after_path)
print()
print(f"Non-volatile changed paths: {len(changes)}")
print()

for i, path in enumerate(changes, 1):
    print(f"{i:03d}. {path}")

print()
print("============================================================")
print("DONE")
print("============================================================")
PY
