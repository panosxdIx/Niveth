#!/usr/bin/env bash

set -euo pipefail

THEME="$HOME/.local/share/icons/retrosmart-xcursor-mac-ish-gruvbox"
CURSORS="$THEME/cursors"

STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP="$HOME/Niveth/backup-cursor-theme-$STAMP"

echo
echo "============================================================"
echo "       NIVETH CURSOR — QT/X11 COMPATIBILITY FIX"
echo "============================================================"
echo

if [ ! -d "$CURSORS" ]; then
    echo "[FAIL] Cursor directory not found:"
    echo "  $CURSORS"
    exit 1
fi

echo "[1/6] Creating backup..."

mkdir -p "$BACKUP"

cp -a \
    "$CURSORS/up-arrow" \
    "$BACKUP/up-arrow"

cp -a \
    "$CURSORS/alias" \
    "$BACKUP/alias"

if [ -e "$CURSORS/up_arrow" ] || [ -L "$CURSORS/up_arrow" ]; then
    cp -a \
        "$CURSORS/up_arrow" \
        "$BACKUP/up_arrow.before" 2>/dev/null || true
fi

if [ -e "$CURSORS/dnd-link" ] || [ -L "$CURSORS/dnd-link" ]; then
    cp -a \
        "$CURSORS/dnd-link" \
        "$BACKUP/dnd-link.before" 2>/dev/null || true
fi

echo "[PASS] Backup:"
echo "  $BACKUP"
echo

echo "[2/6] Checking source cursors..."

if [ ! -e "$CURSORS/up-arrow" ]; then
    echo "[FAIL] Missing source cursor:"
    echo "  up-arrow"
    exit 1
fi

if [ ! -e "$CURSORS/alias" ]; then
    echo "[FAIL] Missing source cursor:"
    echo "  alias"
    exit 1
fi

echo "[PASS] up-arrow"
echo "[PASS] alias"
echo

echo "[3/6] Creating Qt/X11 aliases..."

rm -f "$CURSORS/up_arrow"
rm -f "$CURSORS/dnd-link"

ln -s \
    up-arrow \
    "$CURSORS/up_arrow"

ln -s \
    alias \
    "$CURSORS/dnd-link"

echo "[PASS] up_arrow -> up-arrow"
echo "[PASS] dnd-link -> alias"
echo

echo "[4/6] Verifying aliases..."

if [ "$(readlink "$CURSORS/up_arrow")" = "up-arrow" ]; then
    echo "[PASS] up_arrow"
else
    echo "[FAIL] up_arrow"
    exit 1
fi

if [ "$(readlink "$CURSORS/dnd-link")" = "alias" ]; then
    echo "[PASS] dnd-link"
else
    echo "[FAIL] dnd-link"
    exit 1
fi

echo

echo "[5/6] Verifying complete Qt/X11 set..."

REQUIRED=(
    left_ptr
    up_arrow
    cross
    wait
    left_ptr_watch
    ibeam
    size_ver
    size_hor
    size_bdiag
    size_fdiag
    size_all
    split_v
    split_h
    pointing_hand
    forbidden
    whats_this
    openhand
    closedhand
    dnd-move
    dnd-copy
    dnd-link
    move
    copy
    link
)

FAILED=0

for cursor in "${REQUIRED[@]}"; do
    if [ -e "$CURSORS/$cursor" ]; then
        printf '[OK]   %-20s -> ' "$cursor"

        if [ -L "$CURSORS/$cursor" ]; then
            readlink "$CURSORS/$cursor"
        else
            echo "file"
        fi
    else
        echo "[MISS] $cursor"
        FAILED=1
    fi
done

if [ "$FAILED" -ne 0 ]; then
    echo
    echo "[FAIL] One or more required cursors are still missing."
    exit 1
fi

echo
echo "[PASS] Qt/X11 cursor names are present"
echo

echo "[6/6] Final information..."

echo
echo "Theme:"
echo "  $THEME"

echo
echo "New aliases:"
ls -l \
    "$CURSORS/up_arrow" \
    "$CURSORS/dnd-link"

echo
echo "Backup:"
echo "  $BACKUP"

echo
echo "============================================================"
echo " CURSOR THEME FIX COMPLETE"
echo "============================================================"
echo
echo "Now completely close MEGAsync and start it again."
echo
echo "No logout/reboot is required for this test."
echo
