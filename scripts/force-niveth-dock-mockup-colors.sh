#!/usr/bin/env bash

set -euo pipefail

EXT="$HOME/.local/share/gnome-shell/extensions/niveth-dock@nivethos"
JS="$EXT/extension.js"

if [ ! -f "$JS" ]; then
    echo "ERROR: Niveth Dock extension.js not found:"
    echo "$JS"
    exit 1
fi

STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP="$JS.backup-before-forced-mockup-colors-$STAMP"

echo
echo "=================================================="
echo " NIVETH DOCK — FORCE MOCKUP COLORS"
echo "=================================================="
echo

echo "[1/5] Backup"

cp "$JS" "$BACKUP"

echo "[PASS] Backup created:"
echo "$BACKUP"


echo
echo "[2/5] Replacing theme application logic"

python3 - "$JS" <<'PY'
from pathlib import Path
import re
import sys

path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")

pattern = re.compile(
    r"""
    \n    _updateTheme\(\) \{
    .*?
    \n    \}\n\n    _loadFolders\(\) \{
    """,
    re.S | re.X,
)

match = pattern.search(text)

if not match:
    raise SystemExit(
        "ERROR: Could not find _updateTheme() block."
    )

replacement = r'''
    _updateTheme() {
        if (!this._dock)
            return;

        let scheme = 'prefer-dark';

        try {
            scheme =
                this._nivethThemeSettings.get_string(
                    'color-scheme'
                );
        } catch (error) {
            scheme = 'prefer-dark';
        }

        const dark =
            scheme === 'prefer-dark';

        this._isDark = dark;

        /*
         * Keep the theme classes for menus and
         * other Niveth styling.
         */
        this._dock.remove_style_class_name('dark');
        this._dock.remove_style_class_name('light');

        this._dock.add_style_class_name(
            dark ? 'dark' : 'light'
        );

        /*
         * IMPORTANT:
         * Apply the mockup colors directly to the
         * Dock actor so Yaru/GNOME Light styling
         * cannot turn it white.
         */
        this._dock.set_style(
            dark
                ? 'background-color: rgba(40, 36, 104, 0.94); border: 1px solid rgba(105, 216, 255, 0.72); border-radius: 33px; box-shadow: 0 12px 32px rgba(4, 4, 22, 0.52), 0 0 19px rgba(82, 157, 255, 0.32), 0 0 34px rgba(197, 104, 255, 0.23);'
                : 'background-color: rgba(48, 39, 108, 0.92); border: 1px solid rgba(105, 216, 255, 0.78); border-radius: 33px; box-shadow: 0 11px 30px rgba(37, 24, 82, 0.28), 0 0 18px rgba(90, 170, 255, 0.30), 0 0 34px rgba(201, 105, 255, 0.22);'
        );

        /*
         * Force the App Grid button away from the
         * white Yaru Light button appearance.
         */
        if (this._coreButton) {
            this._coreButton.set_style(
                dark
                    ? 'background-color: rgba(67, 53, 130, 0.78); border: 1px solid rgba(105, 214, 255, 0.34); border-radius: 17px;'
                    : 'background-color: rgba(67, 53, 130, 0.74); border: 1px solid rgba(105, 214, 255, 0.36); border-radius: 17px;'
            );
        }

        /*
         * Keep the active menu theme synchronized.
         */
        if (this._activeMenu) {
            this._activeMenu.remove_style_class_name('dark');
            this._activeMenu.remove_style_class_name('light');

            this._activeMenu.add_style_class_name(
                dark ? 'dark' : 'light'
            );
        }
    }

    _loadFolders() {
'''

text = text[:match.start()] + replacement + text[match.end():]

path.write_text(text, encoding="utf-8")
PY

echo "[PASS] Theme logic patched"


echo
echo "[3/5] Verification"

grep -q "this._dock.set_style(" "$JS"
grep -q "40, 36, 104" "$JS"
grep -q "105, 216, 255" "$JS"
grep -q "this._isDark = dark" "$JS"

echo "[PASS] Direct Dock styling found"
echo "[PASS] Indigo mockup color found"
echo "[PASS] Cyan mockup edge found"
echo "[PASS] _isDark preserved"


echo
echo "[4/5] Reloading Niveth Dock"

gnome-extensions disable niveth-dock@nivethos || true

sleep 1

gnome-extensions enable niveth-dock@nivethos

sleep 2

echo "[PASS] Niveth Dock reloaded"


echo
echo "[5/5] Current GNOME color scheme"

gsettings get org.gnome.desktop.interface color-scheme

echo
echo "=================================================="
echo " DONE"
echo "=================================================="
echo
echo "Το Dock πλέον παίρνει το βασικό του χρώμα"
echo "απευθείας από το JavaScript actor."
echo
echo "Light:"
echo "  Indigo / violet glass"
echo "  Cyan border"
echo "  Violet + blue glow"
echo
echo "Backup:"
echo "$BACKUP"
echo
