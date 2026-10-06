#!/usr/bin/env bash
set -euo pipefail

PROFILE="${1:-/tmp/niveth-brave-noflag-test}"
PREFERENCES="$PROFILE/Default/Preferences"

if [[ ! -f "$PREFERENCES" ]]; then
    echo "ERROR: Brave Preferences not found:"
    echo "$PREFERENCES"
    exit 1
fi

# Safety backup
cp -a "$PREFERENCES" "$PREFERENCES.before-niveth-theme"

python3 - "$PREFERENCES" <<'PY'
import json
import sys

path = sys.argv[1]

with open(path, "r", encoding="utf-8") as f:
    data = json.load(f)

theme = data.setdefault("browser", {}).setdefault("theme", {})

# Niveth purple / vaporwave base
# Chromium stores the color as signed 32-bit ARGB.
theme["user_color2"] = -5673729   # #A96CFF
theme["color_variant2"] = 2       # Vibrant
theme["color_scheme2"] = 0        # System / Device

with open(path, "w", encoding="utf-8") as f:
    json.dump(data, f, ensure_ascii=False, separators=(",", ":"))

print("Niveth Brave theme applied")
print("  Color   : #A96CFF")
print("  Variant : Vibrant")
print("  Scheme  : System / Device")
PY

echo
echo "=== RESULT ==="

python3 - "$PREFERENCES" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as f:
    d = json.load(f)

print(d.get("browser", {}).get("theme", {}))
PY
