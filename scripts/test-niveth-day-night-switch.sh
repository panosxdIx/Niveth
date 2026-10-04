#!/usr/bin/env bash

set -euo pipefail

CONFIG="$HOME/.config/niveth/wallpaper-pairs.json"
BACKUP="/tmp/niveth-wallpaper-pairs-test-backup.json"

echo "=================================================="
echo " Niveth Day/Night Switch Test"
echo "=================================================="
echo

if [ ! -f "$CONFIG" ]; then
    echo "ERROR: Config not found:"
    echo "  $CONFIG"
    exit 1
fi

cp "$CONFIG" "$BACKUP"

restore() {
    echo
    echo "=== Restoring original configuration ==="

    if [ -f "$BACKUP" ]; then
        cp "$BACKUP" "$CONFIG"
    fi

    systemctl --user restart niveth-wallpaper.service
    sleep 3

    rm -f "$BACKUP"

    echo
    echo "Restored."
}

trap restore EXIT

echo "=== TEST 1: FORCE DARK ==="

python3 - "$CONFIG" <<'PY'
import json
import sys

path = sys.argv[1]

with open(path, "r", encoding="utf-8") as f:
    data = json.load(f)

data["day_start"] = "00:00"
data["night_start"] = "00:00"

with open(path, "w", encoding="utf-8") as f:
    json.dump(data, f, indent=2)
PY

systemctl --user restart niveth-wallpaper.service

sleep 3

echo
echo "--- Dark test result ---"
echo "Color scheme:"
gsettings get org.gnome.desktop.interface color-scheme

echo
echo "Wallpaper:"
gsettings get org.gnome.desktop.background picture-uri

echo
echo "Dark wallpaper:"
gsettings get org.gnome.desktop.background picture-uri-dark

echo
echo "Service:"
systemctl --user is-active niveth-wallpaper.service

echo
echo "=================================================="
echo " TEST 2: FORCE LIGHT"
echo "=================================================="

python3 - "$CONFIG" <<'PY'
import json
import sys

path = sys.argv[1]

with open(path, "r", encoding="utf-8") as f:
    data = json.load(f)

data["day_start"] = "00:00"
data["night_start"] = "23:59"

with open(path, "w", encoding="utf-8") as f:
    json.dump(data, f, indent=2)
PY

systemctl --user restart niveth-wallpaper.service

sleep 3

echo
echo "--- Light test result ---"
echo "Color scheme:"
gsettings get org.gnome.desktop.interface color-scheme

echo
echo "Wallpaper:"
gsettings get org.gnome.desktop.background picture-uri

echo
echo "Dark wallpaper:"
gsettings get org.gnome.desktop.background picture-uri-dark

echo
echo "Service:"
systemctl --user is-active niveth-wallpaper.service

echo
echo "=================================================="
echo " TEST FINISHED"
echo "=================================================="
echo
echo "Original configuration will now be restored."
