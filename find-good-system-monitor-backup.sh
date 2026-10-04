#!/usr/bin/env bash

set -u

UUID="niveth-system-monitor@nivethos"
EXT="$HOME/.local/share/gnome-shell/extensions/$UUID"
ROOTFS="$HOME/Niveth/build/rootfs"
ROOTFS_EXT="$ROOTFS/usr/share/gnome-shell/extensions/$UUID"

echo
echo "============================================================"
echo " NIVETH SYSTEM MONITOR — FIND LAST WORKING BACKUP"
echo "============================================================"
echo

if [ ! -d "$EXT" ]; then
    echo "[FAIL] Extension directory not found:"
    echo "  $EXT"
    exit 1
fi

if ! command -v gjs >/dev/null 2>&1; then
    echo "[FAIL] gjs not found."
    exit 1
fi

echo "[1/8] Saving current state..."

CURRENT_BACKUP="$EXT/backup-before-backup-search-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$CURRENT_BACKUP"

cp -f "$EXT/extension.js" \
      "$CURRENT_BACKUP/extension.js" 2>/dev/null || true

cp -f "$EXT/stylesheet.css" \
      "$CURRENT_BACKUP/stylesheet.css" 2>/dev/null || true

cp -f "$EXT/metadata.json" \
      "$CURRENT_BACKUP/metadata.json" 2>/dev/null || true

cp -f "$EXT/niveth-audio-meter.py" \
      "$CURRENT_BACKUP/niveth-audio-meter.py" 2>/dev/null || true

echo "[PASS] Current state saved:"
echo "  $CURRENT_BACKUP"
echo

echo "[2/8] Disabling extension..."

gnome-extensions disable "$UUID" 2>/dev/null || true
sleep 2

echo
echo "[3/8] Collecting candidate backups..."

mapfile -t CANDIDATES < <(
    find "$EXT" \
        -maxdepth 1 \
        -mindepth 1 \
        -type d \
        -name 'backup-*' \
        -not -name 'backup-before-backup-search-*' \
        -printf '%T@ %p\n' 2>/dev/null |
    sort -nr |
    awk '{$1=""; sub(/^ /,""); print}'
)

if [ "${#CANDIDATES[@]}" -eq 0 ]; then
    echo "[FAIL] No backups found."
    exit 1
fi

echo "Found ${#CANDIDATES[@]} backup directories."
echo

echo "[4/8] Testing backups from newest to oldest..."
echo

GOOD_BACKUP=""

INDEX=0

for BACKUP in "${CANDIDATES[@]}"; do

    INDEX=$((INDEX + 1))

    JS="$BACKUP/extension.js"

    if [ ! -f "$JS" ]; then
        continue
    fi

    echo "------------------------------------------------------------"
    echo "TEST $INDEX"
    echo "Backup:"
    echo "  $BACKUP"

    echo "Syntax check..."

    if ! gjs --check "$JS" >/tmp/niveth-system-monitor-gjs-check.out 2>&1; then
        echo "[FAIL] JavaScript syntax"
        sed -n '1,12p' /tmp/niveth-system-monitor-gjs-check.out
        echo
        continue
    fi

    echo "[PASS] JavaScript syntax"

    echo "Checking required System Monitor methods..."

    if ! grep -q "_buildWidget" "$JS"; then
        echo "[FAIL] _buildWidget missing"
        continue
    fi

    if ! grep -q "_startAudioMeter" "$JS"; then
        echo "[FAIL] _startAudioMeter missing"
        continue
    fi

    echo "[PASS] Core methods found"

    echo "Installing candidate live..."

    cp -f \
        "$JS" \
        "$EXT/extension.js"

    if [ -f "$BACKUP/stylesheet.css" ]; then
        cp -f \
            "$BACKUP/stylesheet.css" \
            "$EXT/stylesheet.css"
    fi

    if [ -f "$BACKUP/metadata.json" ]; then
        cp -f \
            "$BACKUP/metadata.json" \
            "$EXT/metadata.json"
    fi

    if [ -f "$BACKUP/niveth-audio-meter.py" ]; then
        cp -f \
            "$BACKUP/niveth-audio-meter.py" \
            "$EXT/niveth-audio-meter.py"

        chmod +x \
            "$EXT/niveth-audio-meter.py"
    fi

    echo "Enabling candidate..."

    gnome-extensions disable "$UUID" 2>/dev/null || true
    sleep 1

    gnome-extensions enable "$UUID" 2>/dev/null || true

    sleep 4

    STATE="$(
        gnome-extensions info "$UUID" 2>/dev/null |
        awk -F': ' '/State:/ {print $2}'
    )"

    ENABLED="$(
        gnome-extensions info "$UUID" 2>/dev/null |
        awk -F': ' '/Enabled:/ {print $2}'
    )"

    echo "Enabled: ${ENABLED:-unknown}"
    echo "State:   ${STATE:-unknown}"

    if [ "$STATE" = "ACTIVE" ]; then

        echo
        echo "============================================================"
        echo " [FOUND] WORKING SYSTEM MONITOR"
        echo "============================================================"
        echo
        echo "Working backup:"
        echo "  $BACKUP"
        echo
        echo "Enabled: $ENABLED"
        echo "State:   $STATE"
        echo

        GOOD_BACKUP="$BACKUP"
        break

    fi

    echo "[FAIL] Candidate did not become ACTIVE."

    echo "Recent System Monitor error:"
    journalctl \
        --user \
        -b \
        --no-pager \
        -o cat 2>/dev/null |
    grep -Ei \
        "niveth-system-monitor|TypeError|ReferenceError|SyntaxError" |
    tail -8 || true

    echo
done

echo

if [ -z "$GOOD_BACKUP" ]; then

    echo "============================================================"
    echo " [FAIL] NO WORKING BACKUP FOUND"
    echo "============================================================"
    echo
    echo "Restoring the state from before the search..."

    cp -f \
        "$CURRENT_BACKUP/extension.js" \
        "$EXT/extension.js"

    if [ -f "$CURRENT_BACKUP/stylesheet.css" ]; then
        cp -f \
            "$CURRENT_BACKUP/stylesheet.css" \
            "$EXT/stylesheet.css"
    fi

    if [ -f "$CURRENT_BACKUP/metadata.json" ]; then
        cp -f \
            "$CURRENT_BACKUP/metadata.json" \
            "$EXT/metadata.json"
    fi

    if [ -f "$CURRENT_BACKUP/niveth-audio-meter.py" ]; then
        cp -f \
            "$CURRENT_BACKUP/niveth-audio-meter.py" \
            "$EXT/niveth-audio-meter.py"

        chmod +x \
            "$EXT/niveth-audio-meter.py"
    fi

    gnome-extensions disable "$UUID" 2>/dev/null || true
    sleep 1
    gnome-extensions enable "$UUID" 2>/dev/null || true

    exit 1
fi

echo "[5/8] Synchronizing the working version to rootfs..."

if [ -d "$ROOTFS_EXT" ]; then

    sudo cp -f \
        "$EXT/extension.js" \
        "$ROOTFS_EXT/extension.js"

    if [ -f "$EXT/stylesheet.css" ]; then
        sudo cp -f \
            "$EXT/stylesheet.css" \
            "$ROOTFS_EXT/stylesheet.css"
    fi

    if [ -f "$EXT/metadata.json" ]; then
        sudo cp -f \
            "$EXT/metadata.json" \
            "$ROOTFS_EXT/metadata.json"
    fi

    if [ -f "$EXT/niveth-audio-meter.py" ]; then
        sudo cp -f \
            "$EXT/niveth-audio-meter.py" \
            "$ROOTFS_EXT/niveth-audio-meter.py"

        sudo chmod +x \
            "$ROOTFS_EXT/niveth-audio-meter.py"
    fi

    echo "[PASS] Rootfs synchronized."

else
    echo "[INFO] Rootfs extension directory not found."
fi

echo
echo "[6/8] Final extension status..."

gnome-extensions info "$UUID" 2>&1 || true

echo
echo "[7/8] Checking AUDIO implementation..."

echo
grep -nE \
    "_buildAudio|_audioHistory|_updateAudioAnimation|_startAudioMeter|_audioWaveBars|_cpuWaveBars|_ramWaveBars" \
    "$EXT/extension.js" |
head -120 || true

echo
echo "[8/8] Recent errors after successful restore..."

journalctl \
    --user \
    -b \
    --no-pager \
    -o cat 2>/dev/null |
grep -Ei \
    "niveth-system-monitor|NIVETH AUDIO|TypeError|ReferenceError|SyntaxError" |
tail -30 || true

echo
echo "============================================================"
echo " WORKING BACKUP RESTORED"
echo "============================================================"
echo
echo "Backup:"
echo "  $GOOD_BACKUP"
echo
echo "Current safety backup:"
echo "  $CURRENT_BACKUP"
echo
