#!/usr/bin/env bash

set -euo pipefail

DAEMON="$HOME/.local/bin/niveth-sound-effects.py"
SOUNDS="$HOME/.local/share/niveth/sound-effects"

echo
echo "============================================================"
echo "        NIVETH SOUND EFFECTS — START TEST"
echo "============================================================"
echo

echo "[1/5] Checking Python modules..."

python3 - <<'PY'
import evdev
import pygame

print("[PASS] evdev imported")
print("[PASS] pygame imported")
print(f"[INFO] pygame version: {pygame.version.ver}")
print(f"[INFO] evdev module: {evdev.__file__}")
PY

echo

echo "[2/5] Checking sound files..."

for file in \
    key.wav \
    mouse-left.wav \
    mouse-right.wav \
    mouse-middle.wav
do
    if [ -f "$SOUNDS/$file" ]; then
        printf '[PASS] %-20s ' "$file"
        ls -lh "$SOUNDS/$file" | awk '{print $5}'
    else
        echo "[FAIL] Missing: $file"
        exit 1
    fi
done

echo

echo "[3/5] Checking daemon..."

if [ ! -f "$DAEMON" ]; then
    echo "[FAIL] Daemon not found:"
    echo "  $DAEMON"
    exit 1
fi

if [ ! -x "$DAEMON" ]; then
    chmod +x "$DAEMON"
fi

echo "[PASS] $DAEMON"
echo

echo "[4/5] Checking input access..."

echo "Current user:"
id

echo

echo "Mouse devices accessible to current user:"

found_mouse=0

for dev in /dev/input/event*; do

    [ -e "$dev" ] || continue

    if udevadm info \
        --query=property \
        --name="$dev" \
        2>/dev/null |
        grep -q '^ID_INPUT_MOUSE=1$'
    then

        echo "[MOUSE] $dev"
        found_mouse=1

    fi

done

if [ "$found_mouse" -eq 0 ]; then
    echo "[WARNING] No ID_INPUT_MOUSE device detected."
fi

echo

echo "[5/5] Starting Niveth Sound Effects..."
echo
echo "TEST:"
echo "  1. Press keyboard keys"
echo "  2. Left click"
echo "  3. Right click"
echo "  4. Middle click"
echo
echo "You should hear:"
echo "  key.wav"
echo "  mouse-left.wav"
echo "  mouse-right.wav"
echo "  mouse-middle.wav"
echo
echo "Stop with Ctrl+C"
echo
echo "============================================================"
echo

exec python3 "$DAEMON"
