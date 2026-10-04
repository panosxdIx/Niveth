#!/usr/bin/env bash

set -u

echo
echo "============================================================"
echo "       NIVETH — MEGASYNC CURSOR DIAGNOSTIC"
echo "============================================================"
echo

echo "=== 1. SESSION ==="
echo "XDG_SESSION_TYPE=${XDG_SESSION_TYPE:-}"
echo "XDG_CURRENT_DESKTOP=${XDG_CURRENT_DESKTOP:-}"
echo "WAYLAND_DISPLAY=${WAYLAND_DISPLAY:-}"
echo "DISPLAY=${DISPLAY:-}"
echo

echo "=== 2. CURSOR GSETTINGS ==="
gsettings get org.gnome.desktop.interface cursor-theme 2>&1 || true
gsettings get org.gnome.desktop.interface cursor-size 2>&1 || true
echo

echo "=== 3. CURSOR ENVIRONMENT ==="
echo "XCURSOR_THEME=${XCURSOR_THEME:-}"
echo "XCURSOR_SIZE=${XCURSOR_SIZE:-}"
echo "QT_QPA_PLATFORM=${QT_QPA_PLATFORM:-}"
echo "QT_QPA_PLATFORMTHEME=${QT_QPA_PLATFORMTHEME:-}"
echo

echo "=== 4. MEGASYNC PROCESS ==="
pgrep -a megasync 2>&1 || true
echo

echo "=== 5. MEGASYNC EXECUTABLE ==="
command -v megasync 2>&1 || true
readlink -f "$(command -v megasync 2>/dev/null)" 2>/dev/null || true
echo

echo "=== 6. MEGASYNC ENVIRONMENT ==="
PID="$(pgrep -o megasync 2>/dev/null || true)"

if [ -n "$PID" ] && [ -r "/proc/$PID/environ" ]; then
    tr '\0' '\n' < "/proc/$PID/environ" |
    grep -E \
        '^(XDG_SESSION_TYPE|XDG_CURRENT_DESKTOP|WAYLAND_DISPLAY|DISPLAY|XCURSOR_THEME|XCURSOR_SIZE|QT_QPA_PLATFORM|QT_QPA_PLATFORMTHEME)=' |
    sort
else
    echo "MEGAsync process not found."
fi
echo

echo "=== 7. MEGASYNC VERSION ==="
megasync --version 2>&1 || true
echo

echo "=== 8. WAYLAND / XWAYLAND ==="
echo "Processes related to XWayland:"
pgrep -a Xwayland 2>&1 || true
echo

echo "=== 9. QT / MEGASYNC LIBRARIES ==="
if command -v megasync >/dev/null 2>&1; then
    ldd "$(command -v megasync)" 2>/dev/null |
    grep -Ei \
        'Qt|wayland|xcb|cursor' |
    head -80 || true
fi
echo

echo "=== 10. CURSOR FILES ==="
echo "Current user cursor themes:"
find \
    "$HOME/.icons" \
    "$HOME/.local/share/icons" \
    /usr/share/icons \
    -maxdepth 2 \
    -type d \
    -name 'cursors' \
    2>/dev/null |
head -80 || true

echo

echo "============================================================"
echo " END"
echo "============================================================"
