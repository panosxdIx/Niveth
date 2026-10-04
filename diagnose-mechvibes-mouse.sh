#!/usr/bin/env bash

set -u

echo
echo "============================================================"
echo "       NIVETH — MECHVIBESDX MOUSE DIAGNOSTIC"
echo "============================================================"
echo

echo "=== 1. MECHVIBES CONFIG ==="

CONFIG="$HOME/.local/share/mechvibes-dx/config.json"

if [ -f "$CONFIG" ]; then
    echo "Config: $CONFIG"

    python3 - "$CONFIG" <<'PY'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])

try:
    data = json.loads(path.read_text(encoding="utf-8"))

    keys = [
        "enable_sound",
        "enable_keyboard_sound",
        "enable_mouse_sound",
        "volume",
        "mouse_volume",
        "keyboard_soundpack",
        "mouse_soundpack",
        "selected_audio_device",
    ]

    for key in keys:
        print(f"{key} = {data.get(key)!r}")

except Exception as e:
    print(f"CONFIG ERROR: {e}")
PY

else
    echo "[NOT FOUND] $CONFIG"
fi

echo

echo "=== 2. INPUT GROUP ==="
id
echo

echo "=== 3. MOUSE EVENT DEVICES ==="

for dev in /dev/input/event*; do

    [ -e "$dev" ] || continue

    if udevadm info \
        --query=property \
        --name="$dev" \
        2>/dev/null |
        grep -Eq \
        'ID_INPUT_MOUSE=1|ID_INPUT_TOUCHPAD=1'
    then
        echo
        echo "[MOUSE] $dev"

        udevadm info \
            --query=property \
            --name="$dev" \
            2>/dev/null |
        grep -E \
            '^(NAME|ID_INPUT|ID_INPUT_MOUSE|ID_INPUT_TOUCHPAD|ID_VENDOR|ID_MODEL)=' |
        sort || true
    fi

done

echo

echo "=== 4. LIBINPUT ==="

if command -v libinput >/dev/null 2>&1; then

    echo "[FOUND] libinput"

    timeout 5s \
        libinput debug-events \
        --show-keycodes \
        2>/dev/null |
    grep -E \
        'BTN_LEFT|BTN_RIGHT|BTN_MIDDLE|POINTER_BUTTON|button' |
    head -40 || true

else

    echo "[NOT FOUND] libinput"
fi

echo

echo "=== 5. EVTEST ==="

if command -v evtest >/dev/null 2>&1; then

    echo "[FOUND] evtest"

    echo
    echo "Available devices:"
    sudo evtest --query /dev/input/event0 EV_KEY KEY_LEFT 2>/dev/null || true

else

    echo "[NOT INSTALLED] evtest"
fi

echo

echo "=== 6. MECHVIBES PROCESS ==="

pgrep -a mechvibes-dx 2>/dev/null || true

echo

echo "=== 7. MECHVIBES FILES ==="

find \
    "$HOME/.local/share/mechvibes-dx" \
    -maxdepth 2 \
    -type f \
    2>/dev/null |
sort |
head -80

echo

echo "=== 8. RECENT MECHVIBES LOG FILES ==="

find \
    "$HOME/.local/share/mechvibes-dx" \
    -type f \
    \( -iname '*.log' -o -iname '*debug*' \) \
    2>/dev/null |
while read -r file; do

    echo
    echo "--- $file ---"

    tail -80 "$file" 2>/dev/null || true

done

echo

echo "=== 9. MECHVIBES TRACE TEST ==="

echo
echo "The app will be started with tracing enabled."
echo "Press LEFT CLICK, RIGHT CLICK, then a few keys."
echo "Wait 5 seconds and then close MechvibesDX."
echo

pkill mechvibes-dx 2>/dev/null || true
sleep 2

MECHVIBES_TRACE=1 \
mechvibes-dx \
>/tmp/mechvibes-trace-terminal.log \
2>&1 &

PID="$!"

echo "Started PID: $PID"

sleep 3

echo
echo ">>> NOW CLICK LEFT / RIGHT MOUSE AND TYPE A FEW KEYS <<<"
echo

sleep 5

if kill -0 "$PID" 2>/dev/null; then
    kill "$PID" 2>/dev/null || true
fi

wait "$PID" 2>/dev/null || true

echo
echo "=== TRACE TERMINAL LOG ==="

cat /tmp/mechvibes-trace-terminal.log 2>/dev/null || true

echo
echo "=== MECHVIBES TRACE FILES ==="

find /tmp \
    -maxdepth 1 \
    -type f \
    -name 'mechvibes-trace-*.log' \
    2>/dev/null |
sort |
tail -10 |
while read -r file; do
    echo
    echo "--- $file ---"
    tail -100 "$file" 2>/dev/null || true
done

echo
echo "============================================================"
echo " END"
echo "============================================================"
