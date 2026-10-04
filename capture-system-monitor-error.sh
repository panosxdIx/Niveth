#!/usr/bin/env bash
set -u

EXT_ID="niveth-system-monitor@nivethos"
LOG_FILE="/tmp/niveth-system-monitor-live.log"

echo "=============================================="
echo " NIVETH SYSTEM MONITOR - LIVE ERROR CAPTURE"
echo "=============================================="

rm -f "$LOG_FILE"

echo
echo "[1/5] Disabling extension..."
gnome-extensions disable "$EXT_ID" 2>/dev/null || true
sleep 3

echo
echo "[2/5] Starting live GNOME Shell log capture..."

journalctl --user \
    -f \
    -o short-precise \
    2>/dev/null |
grep --line-buffered -Ei \
'niveth-system-monitor|JS ERROR|Gjs-|SyntaxError|TypeError|ReferenceError|ImportError|Error:' \
> "$LOG_FILE" &

JOURNAL_PID=$!

sleep 2

echo
echo "[3/5] Enabling extension..."
gnome-extensions enable "$EXT_ID" 2>&1 || true

echo
echo "[4/5] Waiting for extension initialization..."
sleep 8

kill "$JOURNAL_PID" 2>/dev/null || true
wait "$JOURNAL_PID" 2>/dev/null || true

echo
echo "[5/5] Extension status..."
gnome-extensions info "$EXT_ID"

echo
echo "=============================================="
echo " LIVE ERROR CAPTURE"
echo "=============================================="

if [ -s "$LOG_FILE" ]; then
    cat "$LOG_FILE"
else
    echo "[NO NEW LOG ENTRY CAPTURED]"
fi

echo
echo "=============================================="
echo " IMPORTANT SOURCE CHECK"
echo "=============================================="

echo
echo "--- imports ---"
grep -nE '^import ' \
"$HOME/.local/share/gnome-shell/extensions/$EXT_ID/extension.js" \
|| true

echo
echo "--- Main usage ---"
grep -n 'Main\.' \
"$HOME/.local/share/gnome-shell/extensions/$EXT_ID/extension.js" \
| head -30 \
|| true

echo
echo "=============================================="
echo " END"
echo "=============================================="
