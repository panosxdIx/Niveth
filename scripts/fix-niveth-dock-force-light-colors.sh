#!/usr/bin/env bash

set -euo pipefail

EXT="$HOME/.local/share/gnome-shell/extensions/niveth-dock@nivethos"
JS="$EXT/extension.js"

ROOTFS="$HOME/Niveth/build/rootfs"
ROOTFS_EXT="$ROOTFS/usr/share/gnome-shell/extensions/niveth-dock@nivethos"
ROOTFS_JS="$ROOTFS_EXT/extension.js"

if [ ! -f "$JS" ]; then
    echo "ERROR: Niveth Dock extension.js not found:"
    echo "$JS"
    exit 1
fi

STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP="$JS.backup-before-force-light-fix-$STAMP"

echo
echo "=================================================="
echo " NIVETH DOCK — ROBUST LIGHT COLOR FIX"
echo "=================================================="
echo

echo "[1/7] Creating backup"

cp "$JS" "$BACKUP"

echo "[PASS] Backup:"
echo "$BACKUP"


echo
echo "[2/7] Replacing _updateTheme() safely"

python3 - "$JS" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")

start_marker = "\n    _updateTheme() {"
end_marker = "\n    _loadFolders() {"

start = text.find(start_marker)

if start == -1:
    raise SystemExit(
        "ERROR: _updateTheme() start was not found."
    )

end = text.find(end_marker, start)

if end == -1:
    raise SystemExit(
        "ERROR: _loadFolders() after _updateTheme() was not found."
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
         * Keep the theme classes.
         */
        this._dock.remove_style_class_name('dark');
        this._dock.remove_style_class_name('light');

        this._dock.add_style_class_name(
            dark ? 'dark' : 'light'
        );

        /*
         * Force the actual Dock actor appearance.
         *
         * LIGHT:
         * Indigo / violet glass
         * Electric cyan border
         * Violet + blue glow
         *
         * DARK:
         * Same palette, deeper background.
         */
        if (dark) {
            this._dock.set_style(
                'background-color: rgba(40, 36, 104, 0.94);' +
                'border: 1px solid rgba(105, 216, 255, 0.72);' +
                'border-radius: 33px;' +
                'box-shadow:' +
                '0 12px 32px rgba(4, 4, 22, 0.52),' +
                '0 0 19px rgba(82, 157, 255, 0.32),' +
                '0 0 34px rgba(197, 104, 255, 0.23);'
            );
        } else {
            this._dock.set_style(
                'background-color: rgba(65, 49, 132, 0.94);' +
                'border: 1px solid rgba(105, 216, 255, 0.78);' +
                'border-radius: 33px;' +
                'box-shadow:' +
                '0 11px 30px rgba(37, 24, 82, 0.30),' +
                '0 0 18px rgba(90, 170, 255, 0.32),' +
                '0 0 34px rgba(201, 105, 255, 0.24);'
            );
        }

        /*
         * Force App Grid appearance too.
         */
        if (this._coreButton) {
            this._coreButton.set_style(
                dark
                    ? 'background-color: rgba(67, 53, 130, 0.80);' +
                      'border: 1px solid rgba(105, 214, 255, 0.34);' +
                      'border-radius: 17px;'
                    : 'background-color: rgba(78, 61, 150, 0.78);' +
                      'border: 1px solid rgba(105, 214, 255, 0.40);' +
                      'border-radius: 17px;'
            );
        }

        /*
         * Keep active popup menu synchronized.
         */
        if (this._activeMenu) {
            this._activeMenu.remove_style_class_name('dark');
            this._activeMenu.remove_style_class_name('light');

            this._activeMenu.add_style_class_name(
                dark ? 'dark' : 'light'
            );
        }
    }
'''

text = (
    text[:start]
    + replacement
    + text[end:]
)

path.write_text(text, encoding="utf-8")
PY

echo "[PASS] _updateTheme() replaced"


echo
echo "[3/7] Verifying JavaScript"

grep -q "this._dock.set_style(" "$JS"
grep -q "65, 49, 132" "$JS"
grep -q "105, 216, 255" "$JS"
grep -q "this._coreButton.set_style(" "$JS"
grep -q "this._isDark = dark" "$JS"

echo "[PASS] Direct Dock styling present"
echo "[PASS] Indigo Light color present"
echo "[PASS] Cyan border present"
echo "[PASS] App Grid forced styling present"
echo "[PASS] _isDark preserved"


echo
echo "[4/7] Showing patched theme function"

grep -n -A95 "^    _updateTheme()" "$JS" | head -110


echo
echo "[5/7] Syncing Niveth rootfs"

if [ -d "$ROOTFS_EXT" ]; then

    ROOTFS_BACKUP="$ROOTFS_JS.backup-before-force-light-fix-$STAMP"

    if [ -f "$ROOTFS_JS" ]; then
        sudo cp "$ROOTFS_JS" "$ROOTFS_BACKUP"
        echo "[PASS] Rootfs backup:"
        echo "$ROOTFS_BACKUP"
    fi

    sudo install -m 0644 "$JS" "$ROOTFS_JS"

    echo "[PASS] Rootfs Dock extension updated"

else
    echo "[INFO] Rootfs Dock extension not found."
    echo "[INFO] Live installation was updated only."
fi


echo
echo "[6/7] Reloading Niveth Dock"

gnome-extensions disable niveth-dock@nivethos || true

sleep 1

gnome-extensions enable niveth-dock@nivethos

sleep 2

echo "[PASS] Niveth Dock reloaded"


echo
echo "[7/7] Current GNOME mode"

gsettings get org.gnome.desktop.interface color-scheme

echo
echo "=================================================="
echo " DONE"
echo "=================================================="
echo
echo "LIGHT MODE EXPECTED:"
echo "  • Indigo/violet capsule"
echo "  • Cyan border"
echo "  • Violet/blue glow"
echo "  • Purple App Grid"
echo
echo "Backup:"
echo "$BACKUP"
echo
