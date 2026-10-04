#!/usr/bin/env bash

set -u

echo
echo "============================================================"
echo "       NIVETH — KEYBOARD SOUNDS PRO CHECK"
echo "============================================================"
echo

echo "=== SYSTEM ==="
cat /etc/os-release | grep -E '^(PRETTY_NAME|VERSION_ID)=' || true
echo
uname -m
echo

echo "=== INPUT GROUP ==="
id
echo
getent group input || true
echo

echo "=== AUDIO ==="
command -v pactl || true
pactl info 2>/dev/null |
grep -E 'Server Name|Default Sink|Default Source' || true
echo

echo "=== KEYBOARD SOUNDS PRO ==="
if command -v keyboardsounds >/dev/null 2>&1; then
    echo "[FOUND] keyboardsounds"
    keyboardsounds --version 2>&1 || true
elif command -v keyboard-sounds >/dev/null 2>&1; then
    echo "[FOUND] keyboard-sounds"
    keyboard-sounds --version 2>&1 || true
else
    echo "[NOT INSTALLED]"
fi
echo

echo "=== PACKAGE ==="
dpkg -l 2>/dev/null |
grep -Ei 'keyboard.*sound|keyboardsounds' |
head -20 || true
echo

echo "=== INPUT DEVICES ==="
if [ -d /dev/input ]; then
    ls -l /dev/input 2>/dev/null || true
fi
echo

echo "============================================================"
echo " END"
echo "============================================================"
