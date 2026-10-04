#!/usr/bin/env bash

set -u

PROJECT_ROOT="$HOME/Niveth"

DOCK="niveth-dock@nivethos"
UI="niveth-ui-test@nivethos"

DOCK_HOST="$HOME/.local/share/gnome-shell/extensions/$DOCK/extension.js"
UI_HOST="$HOME/.local/share/gnome-shell/extensions/$UI/extension.js"

echo "=================================================="
echo " Niveth Shell Theme Diagnostic"
echo "=================================================="
echo

echo "=== 1. GNOME session ==="

echo "Desktop:"
echo "${XDG_CURRENT_DESKTOP:-unknown}"

echo
echo "Session:"
echo "${XDG_SESSION_TYPE:-unknown}"

echo
echo "GNOME version:"
gnome-shell --version 2>/dev/null || true

echo
echo "=================================================="
echo " 2. Color scheme"
echo "=================================================="

echo "Before:"
gsettings get org.gnome.desktop.interface color-scheme

echo
echo "Setting prefer-dark..."
gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark'

sleep 2

echo "After prefer-dark:"
gsettings get org.gnome.desktop.interface color-scheme

echo
echo "Setting prefer-light..."
gsettings set org.gnome.desktop.interface color-scheme 'prefer-light'

sleep 2

echo "After prefer-light:"
gsettings get org.gnome.desktop.interface color-scheme

echo
echo "=================================================="
echo " 3. Enabled GNOME extensions"
echo "=================================================="

gnome-extensions list --enabled 2>/dev/null || true

echo
echo "=================================================="
echo " 4. Dock extension info"
echo "=================================================="

gnome-extensions info "$DOCK" 2>&1 || true

echo
echo "=================================================="
echo " 5. UI Test extension info"
echo "=================================================="

gnome-extensions info "$UI" 2>&1 || true

echo
echo "=================================================="
echo " 6. Actual HOST files"
echo "=================================================="

echo
echo "--- Dock path ---"
readlink -f "$DOCK_HOST" 2>/dev/null || true

echo
echo "--- UI Test path ---"
readlink -f "$UI_HOST" 2>/dev/null || true

echo
echo "=================================================="
echo " 7. Dock theme code"
echo "=================================================="

if [ -f "$DOCK_HOST" ]; then
    grep -nE \
        "nivethTheme|changed::color-scheme|_updateTheme|color-scheme|add_style_class_name|disconnect" \
        "$DOCK_HOST" || true
else
    echo "Dock file not found:"
    echo "$DOCK_HOST"
fi

echo
echo "=================================================="
echo " 8. UI Test / Top Bar theme code"
echo "=================================================="

if [ -f "$UI_HOST" ]; then
    grep -nE \
        "nivethTheme|changed::color-scheme|_updateTheme|color-scheme|add_style_class_name|disconnect" \
        "$UI_HOST" || true
else
    echo "UI Test file not found:"
    echo "$UI_HOST"
fi

echo
echo "=================================================="
echo " 9. Theme CSS"
echo "=================================================="

DOCK_CSS="$HOME/.local/share/gnome-shell/extensions/$DOCK/stylesheet.css"
UI_CSS="$HOME/.local/share/gnome-shell/extensions/$UI/stylesheet.css"

echo
echo "--- Dock CSS ---"

if [ -f "$DOCK_CSS" ]; then
    grep -nE \
        "niveth-dock\.light|niveth-dock\.dark|niveth-dock-menu\.light|niveth-dock-menu\.dark" \
        "$DOCK_CSS" || true
else
    echo "Dock CSS not found."
fi

echo
echo "--- UI Test CSS ---"

if [ -f "$UI_CSS" ]; then
    grep -nE \
        "niveth-topbar|niveth-dark" \
        "$UI_CSS" || true
else
    echo "UI Test CSS not found."
fi

echo
echo "=================================================="
echo " 10. Recent GNOME Shell logs"
echo "=================================================="

journalctl --user \
    --since "5 minutes ago" \
    --no-pager 2>/dev/null |
    grep -Ei \
        "Niveth|niveth|extension|gnome-shell|error|exception|TypeError|ReferenceError" |
    tail -n 200 || true

echo
echo "=================================================="
echo " 11. Final color scheme"
echo "=================================================="

gsettings get \
    org.gnome.desktop.interface \
    color-scheme

echo
echo "=================================================="
echo " DIAGNOSTIC COMPLETE"
echo "=================================================="
