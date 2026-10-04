#!/usr/bin/env bash

set -euo pipefail

PROFILE="$HOME/.config/vivaldi/Default"

echo "============================================================"
echo "        NIVETH VIVALDI BLOCKING CHECK"
echo "============================================================"
echo

echo "=== BLOCKING DIRECTORIES ==="
find "$PROFILE/AdBlockRules" -maxdepth 2 -type f -printf '%P\n' 2>/dev/null \
    | sort \
    | head -100

echo
echo "=== VIVALDI PREFERENCES: BLOCKING-RELATED KEYS ==="

python3 - "$PROFILE/Preferences.niveth-privacy-backup-20260916-221549" <<'PY'
import json
import sys

path = sys.argv[1]

with open(path, encoding="utf-8") as f:
    data = json.load(f)

KEYWORDS = (
    "adblock",
    "ad_block",
    "blocking",
    "tracker",
    "tracking",
    "content_block",
    "contentblock",
    "third_party",
    "cookie",
    "do_not_track",
    "dnt",
)

def walk(obj, path=()):
    if isinstance(obj, dict):
        for k, v in obj.items():
            p = path + (str(k),)
            joined = ".".join(p).lower()

            if any(term in joined for term in KEYWORDS):
                print(".".join(p))

            walk(v, p)

    elif isinstance(obj, list):
        for i, v in enumerate(obj):
            walk(v, path + (str(i),))

walk(data)
PY

echo
echo "=== DONE ==="
