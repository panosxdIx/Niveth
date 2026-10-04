#!/usr/bin/env bash

set -uo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOG_DIR="$PROJECT_ROOT/integration-backups"

echo "=============================================="
echo " NIVETH CALAMARES RUNTIME ANALYSIS"
echo "=============================================="

if [[ ! -d "$LOG_DIR" ]]; then
    echo "[ERROR] Log directory not found:"
    echo "        $LOG_DIR"
    exit 1
fi

LOG="$(
    find "$LOG_DIR" \
        -maxdepth 1 \
        -type f \
        -name 'niveth-calamares-offscreen-*.log' \
        -printf '%T@ %p\n' \
        2>/dev/null \
    | sort -nr \
    | head -1 \
    | cut -d' ' -f2-
)"

if [[ -z "$LOG" || ! -f "$LOG" ]]; then
    echo "[ERROR] No offscreen Calamares log found."
    echo
    echo "Available matching files:"
    find "$LOG_DIR" \
        -maxdepth 1 \
        -type f \
        -name 'niveth-calamares-offscreen-*.log' \
        -print \
        2>/dev/null \
        | sort || true
    exit 1
fi

echo
echo "Log:"
echo "  $LOG"

echo
echo "=== 1. FATAL / ERROR LINES ==="

grep -Ein \
    '(^|[[:space:]])(ERROR:|FATAL|fatal in|segmentation fault|aborted)' \
    "$LOG" \
    || echo "[PASS] No explicit fatal/error lines found"

echo
echo "=== 2. WARNING LINES ==="

grep -Ein \
    'WARNING:' \
    "$LOG" \
    | head -100 \
    || echo "[INFO] No warnings found"

echo
echo "=== 3. BRANDING ==="

grep -Ein \
    'Using Calamares branding file|Loaded branding component|slideshow|QML component complete' \
    "$LOG" \
    || true

echo
echo "=== 4. MODULE STARTUP ==="

grep -Ein \
    'module init started|all modules init done|loadModules for all modules done|ViewModule .* loading complete|CppJobModule .* loading complete' \
    "$LOG" \
    | tail -100 \
    || true

echo
echo "=== 5. VIEW STEPS ==="

grep -Ein \
    'view steps loaded|Window now visible|CalamaresWindow created' \
    "$LOG" \
    || true

echo
echo "=== 6. REQUIREMENTS ==="

grep -Ein \
    'Requirements|requirement .*satisfied|not-satisfied|enoughStorage|hasInternet|hasPower' \
    "$LOG" \
    | tail -100 \
    || true

echo
echo "=== 7. PARTITION DETECTION ==="

grep -Ein \
    'LIST OF DETECTED DEVICES|devices detected|there are .* devices left' \
    "$LOG" \
    || true

echo
echo "=== 8. DISPLAY / QT ==="

grep -Ein \
    'Could not open display|Cannot open display|could not connect to display|qt.qpa|Qt platform' \
    "$LOG" \
    || echo "[PASS] No Qt display failure detected"

echo
echo "=== 9. CONFIGURATION ERRORS ==="

if grep -Eqi \
    'key not found|configuration error|config error|parse error|yaml.*error|unknown module|module.*not found|failed to load.*module|failed to load.*branding|cannot load.*module|cannot load.*branding' \
    "$LOG"
then
    echo "[ERROR] Configuration-related error text detected."
else
    echo "[PASS] No configuration/module error text detected"
fi

echo
echo "=== 10. SUMMARY ==="

if grep -Eqi \
    'FATAL|fatal in|Segmentation fault|Aborted' \
    "$LOG"
then
    echo "[RESULT] REAL FATAL CONDITION DETECTED"
else
    echo "[RESULT] NO FATAL CALAMARES CONDITION DETECTED"
fi

if grep -Eqi \
    'Loaded branding component "niveth"' \
    "$LOG"
then
    echo "[PASS] Niveth branding loaded"
else
    echo "[ERROR] Niveth branding did not load"
fi

if grep -Eqi \
    'STARTUP: initModuleManager: all modules init done' \
    "$LOG"
then
    echo "[PASS] All modules initialized"
else
    echo "[ERROR] Module initialization did not complete"
fi

if grep -Eqi \
    'STARTUP: Window now visible and ProgressTreeView populated' \
    "$LOG"
then
    echo "[PASS] Installer window initialized"
else
    echo "[ERROR] Installer window did not initialize"
fi

if grep -Eqi \
    'QML component complete, API 2' \
    "$LOG"
then
    echo "[PASS] Slideshow initialized"
else
    echo "[ERROR] Slideshow did not initialize"
fi

echo
echo "=============================================="
echo " RUNTIME ANALYSIS COMPLETE"
echo "=============================================="
