#!/usr/bin/env bash
set -u

EXT_ID="niveth-system-monitor@nivethos"

echo "=============================================="
echo " NIVETH SYSTEM MONITOR - EXACT ERROR CHECK"
echo "=============================================="

echo
echo "[1] Disable..."
gnome-extensions disable "$EXT_ID" 2>/dev/null || true

sleep 2

echo
echo "[2] Clear marker time..."
START_TIME="$(date '+%Y-%m-%d %H:%M:%S')"
echo "Checking logs after: $START_TIME"

echo
echo "[3] Enable..."
gnome-extensions enable "$EXT_ID" 2>&1 || true

sleep 5

echo
echo "[4] Extension status..."
gnome-extensions info "$EXT_ID"

echo
echo "=============================================="
echo " EXACT GNOME SHELL ERROR"
echo "=============================================="

journalctl --user -b \
    _COMM=gnome-shell \
    --no-pager \
    -o cat \
    --since "$START_TIME" 2>/dev/null |
grep -Ei \
'niveth-system-monitor@nivethos|SyntaxError|TypeError|ReferenceError|ImportError|Gjs-CRITICAL|Gjs-WARNING|JS ERROR|Error:' |
tail -100 || true

echo
echo "=============================================="
echo " FULL EXTENSION REFERENCES"
echo "=============================================="

journalctl --user -b \
    _COMM=gnome-shell \
    --no-pager \
    -o cat \
    --since "$START_TIME" 2>/dev/null |
grep -i "niveth-system-monitor@nivethos" |
tail -100 || true

echo
echo "=============================================="
echo " END"
echo "=============================================="
