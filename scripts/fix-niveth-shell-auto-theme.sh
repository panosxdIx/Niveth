#!/usr/bin/env bash

set -euo pipefail

PROJECT_ROOT="$HOME/Niveth"
ROOTFS="$PROJECT_ROOT/build/rootfs"

HOST_EXT="$HOME/.local/share/gnome-shell/extensions"
ROOTFS_EXT="$ROOTFS/usr/share/gnome-shell/extensions"

DOCK="niveth-dock@nivethos"
UI="niveth-ui-test@nivethos"

DOCK_HOST="$HOST_EXT/$DOCK/extension.js"
UI_HOST="$HOST_EXT/$UI/extension.js"

DOCK_ROOT="$ROOTFS_EXT/$DOCK/extension.js"
UI_ROOT="$ROOTFS_EXT/$UI/extension.js"

STAMP="$(date +%Y%m%d-%H%M%S)"

echo "=================================================="
echo " Niveth Shell Automatic Light/Dark Theme Fix"
echo "=================================================="
echo

if [ ! -f "$DOCK_HOST" ]; then
    echo "ERROR: Dock extension not found:"
    echo "  $DOCK_HOST"
    exit 1
fi

if [ ! -f "$UI_HOST" ]; then
    echo "ERROR: UI/Topbar extension not found:"
    echo "  $UI_HOST"
    exit 1
fi

if [ ! -d "$ROOTFS" ]; then
    echo "ERROR: Rootfs not found:"
    echo "  $ROOTFS"
    exit 1
fi

BACKUP_DIR="$PROJECT_ROOT/integration-backups/shell-auto-theme-$STAMP"
mkdir -p "$BACKUP_DIR"

echo "=== 1. Backing up current extensions ==="

cp -a "$DOCK_HOST" "$BACKUP_DIR/niveth-dock-extension.js"
cp -a "$UI_HOST" "$BACKUP_DIR/niveth-ui-test-extension.js"

echo "Backup:"
echo "  $BACKUP_DIR"

echo
echo "=================================================="
echo " 2. Patching Niveth Dock"
echo "=================================================="

python3 - "$DOCK_HOST" <<'PY'
from pathlib import Path
import re
import sys

path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")

if "changed::color-scheme" not in text:
    marker = """        try {
            this._theme.load_stylesheet(this._stylesheet);
        } catch (error) {
            console.error(`Niveth Dock: stylesheet load failed: ${error}`);
        }
"""

    if marker not in text:
        raise SystemExit("Dock enable() stylesheet block not found.")

    insert = marker + """
        this._interfaceSettings =
            Gio.Settings.new('org.gnome.desktop.interface');

        this._colorSchemeChangedId =
            this._interfaceSettings.connect(
                'changed::color-scheme',
                () => this._updateTheme()
            );
"""

    text = text.replace(marker, insert, 1)

if "this._interfaceSettings.get_string('color-scheme')" not in text:
    pattern = re.compile(
        r"""    _updateTheme\(\) \{\n.*?\n    \}\n\n    _loadFolders\(\) \{""",
        re.S,
    )

    replacement = """    _updateTheme() {
        if (!this._dock)
            return;

        let scheme = 'prefer-dark';

        try {
            scheme =
                this._interfaceSettings.get_string(
                    'color-scheme'
                );
        } catch (error) {
            scheme = 'prefer-dark';
        }

        const dark = scheme === 'prefer-dark';

        this._dock.remove_style_class_name('dark');
        this._dock.remove_style_class_name('light');

        this._dock.add_style_class_name(
            dark ? 'dark' : 'light'
        );

        if (this._activeMenu) {
            this._activeMenu.remove_style_class_name('dark');
            this._activeMenu.remove_style_class_name('light');

            this._activeMenu.add_style_class_name(
                dark ? 'dark' : 'light'
            );
        }
    }

    _loadFolders() {"""

    new_text, count = pattern.subn(replacement, text, count=1)

    if count != 1:
        raise SystemExit(
            "Dock _updateTheme() block not found. No changes made."
        )

    text = new_text

if "this._interfaceSettings" in text and "this._colorSchemeChangedId" in text:
    marker = """    disable() {
"""

    if marker not in text:
        raise SystemExit("Dock disable() not found.")

    disconnect = """    disable() {
        if (this._colorSchemeChangedId) {
            try {
                this._interfaceSettings.disconnect(
                    this._colorSchemeChangedId
                );
            } catch (error) {
            }

            this._colorSchemeChangedId = null;
        }

"""

    if "this._interfaceSettings.disconnect(" not in text:
        text = text.replace(marker, disconnect, 1)

path.write_text(text, encoding="utf-8")
PY

echo "Dock patched."

echo
echo "=================================================="
echo " 3. Patching Niveth UI Test / Top Bar"
echo "=================================================="

python3 - "$UI_HOST" <<'PY'
from pathlib import Path
import re
import sys

path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")

if "changed::color-scheme" not in text:
    marker = """        this._createLogo();
        this._createIcons();
"""

    if marker not in text:
        raise SystemExit(
            "UI Test createLogo/createIcons block not found."
        )

    insert = marker + """
        this._interfaceSettings =
            Gio.Settings.new('org.gnome.desktop.interface');

        this._colorSchemeChangedId =
            this._interfaceSettings.connect(
                'changed::color-scheme',
                () => this._updateTheme()
            );
"""

    text = text.replace(marker, insert, 1)

pattern = re.compile(
    r"""    _updateTheme\(\) \{\n.*?\n    \}\n\n    _updatePosition\(\) \{""",
    re.S,
)

replacement = """    _updateTheme() {
        if (!this._bar)
            return;

        let scheme = 'prefer-dark';

        try {
            scheme =
                this._interfaceSettings.get_string(
                    'color-scheme'
                );
        } catch (error) {
            scheme = 'prefer-dark';
        }

        const dark = scheme === 'prefer-dark';

        this._bar.remove_style_class_name('niveth-dark');

        this._clock
            ?.remove_style_class_name('niveth-dark');

        if (dark) {
            this._bar.add_style_class_name('niveth-dark');

            this._clock
                ?.add_style_class_name('niveth-dark');
        }

        if (this._clock) {
            this._clock.set_style(
                dark
                    ? 'color: #DCE7F4;'
                    : 'color: #29415D;'
            );
        }

        this._setIcon(
            this._logo,
            'logo',
            dark
        );

        const buttons =
            this._right.get_children();

        for (const child of buttons) {
            if (child === this._powerButton) {
                this._setIcon(
                    this._powerIcon,
                    'power',
                    dark
                );
            } else if (child._nivethIcon) {
                if (child._nivethName === 'battery') {
                    this._updateBatteryIcon();
                } else {
                    this._setIcon(
                        child._nivethIcon,
                        child._nivethName,
                        dark
                    );
                }
            }
        }

        this._updateClock();
    }

    _updatePosition() {"""

new_text, count = pattern.subn(replacement, text, count=1)

if count != 1:
    raise SystemExit(
        "UI Test _updateTheme() block not found."
    )

text = new_text

if "this._interfaceSettings.disconnect(" not in text:
    marker = """    disable() {
"""

    if marker not in text:
        raise SystemExit("UI Test disable() not found.")

    disconnect = """    disable() {
        if (this._colorSchemeChangedId) {
            try {
                this._interfaceSettings.disconnect(
                    this._colorSchemeChangedId
                );
            } catch (error) {
            }

            this._colorSchemeChangedId = null;
        }

"""

    text = text.replace(marker, disconnect, 1)

path.write_text(text, encoding="utf-8")
PY

echo "UI Test / Top Bar patched."

echo
echo "=================================================="
echo " 4. JavaScript syntax checks"
echo "=================================================="

if command -v node >/dev/null 2>&1; then
    node --check "$DOCK_HOST"
    node --check "$UI_HOST"
    echo "Node syntax check: OK"
else
    echo "node not installed; using structural checks."
    grep -q "changed::color-scheme" "$DOCK_HOST"
    grep -q "changed::color-scheme" "$UI_HOST"
    echo "Structural check: OK"
fi

echo
echo "=================================================="
echo " 5. Synchronizing into rootfs"
echo "=================================================="

sudo mkdir -p \
    "$ROOTFS_EXT/$DOCK" \
    "$ROOTFS_EXT/$UI"

sudo cp -a \
    "$DOCK_HOST" \
    "$DOCK_ROOT"

sudo cp -a \
    "$UI_HOST" \
    "$UI_ROOT"

sudo chown root:root \
    "$DOCK_ROOT" \
    "$UI_ROOT"

sudo chmod 644 \
    "$DOCK_ROOT" \
    "$UI_ROOT"

echo "Rootfs synchronized."

echo
echo "=================================================="
echo " 6. Reloading the two active extensions"
echo "=================================================="

gnome-extensions disable "$DOCK" 2>/dev/null || true
gnome-extensions disable "$UI" 2>/dev/null || true

sleep 2

gnome-extensions enable "$DOCK"
gnome-extensions enable "$UI"

sleep 3

echo
echo "=================================================="
echo " 7. Current state"
echo "=================================================="

echo "GNOME color scheme:"
gsettings get org.gnome.desktop.interface color-scheme

echo
echo "Dock:"
gnome-extensions info "$DOCK" 2>/dev/null | grep -E 'State|Name' || true

echo
echo "UI Test:"
gnome-extensions info "$UI" 2>/dev/null | grep -E 'State|Name' || true

echo
echo "=================================================="
echo " COMPLETE"
echo "=================================================="
echo
echo "The Dock and Niveth Top Bar now follow GNOME color-scheme."
echo "No reboot is required."
echo
echo "Test with:"
echo "  gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark'"
echo "  gsettings set org.gnome.desktop.interface color-scheme 'prefer-light'"
echo
echo "Then restore the normal automatic wallpaper service."
