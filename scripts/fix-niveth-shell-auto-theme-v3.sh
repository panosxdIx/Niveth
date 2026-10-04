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
BACKUP_DIR="$PROJECT_ROOT/integration-backups/shell-auto-theme-v3-$STAMP"

echo "=================================================="
echo " Niveth Shell Automatic Light/Dark Theme Fix v3"
echo "=================================================="
echo

if [ ! -f "$DOCK_HOST" ]; then
    echo "ERROR: Dock extension not found:"
    echo "  $DOCK_HOST"
    exit 1
fi

if [ ! -f "$UI_HOST" ]; then
    echo "ERROR: UI Test extension not found:"
    echo "  $UI_HOST"
    exit 1
fi

if [ ! -d "$ROOTFS" ]; then
    echo "ERROR: Rootfs not found:"
    echo "  $ROOTFS"
    exit 1
fi

mkdir -p "$BACKUP_DIR"

echo "=== 1. Backup ==="

cp -a "$DOCK_HOST" "$BACKUP_DIR/niveth-dock-extension.js"
cp -a "$UI_HOST" "$BACKUP_DIR/niveth-ui-test-extension.js"

echo "Backup:"
echo "  $BACKUP_DIR"

echo
echo "=================================================="
echo " 2. Patching Dock"
echo "=================================================="

python3 - "$DOCK_HOST" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")

# --------------------------------------------------
# Add settings + signal connection
# --------------------------------------------------

if "this._nivethColorSchemeChangedId" not in text:

    anchor = "this._theme.load_stylesheet(this._stylesheet);"

    pos = text.find(anchor)

    if pos == -1:
        raise SystemExit(
            "Dock stylesheet load call not found."
        )

    end = pos + len(anchor)

    injection = """

        this._nivethInterfaceSettings =
            Gio.Settings.new(
                'org.gnome.desktop.interface'
            );

        this._nivethColorSchemeChangedId =
            this._nivethInterfaceSettings.connect(
                'changed::color-scheme',
                () => this._syncNivethTheme()
            );

"""

    text = text[:end] + injection + text[end:]

# --------------------------------------------------
# Add initial sync after enable() setup
# --------------------------------------------------

if "this._syncNivethTheme();" not in text:

    marker = "this._nivethColorSchemeChangedId ="

    pos = text.find(marker)

    if pos == -1:
        raise SystemExit(
            "Could not locate Dock color scheme connection."
        )

    semicolon = text.find(");", pos)

    if semicolon == -1:
        raise SystemExit(
            "Could not locate end of Dock signal connection."
        )

    semicolon += 2

    text = (
        text[:semicolon]
        + """

        this._syncNivethTheme();
"""
        + text[semicolon:]
    )

# --------------------------------------------------
# Add new theme synchronization method
# --------------------------------------------------

if "_syncNivethTheme()" not in text:

    disable_pos = text.find("    disable()")

    if disable_pos == -1:
        raise SystemExit(
            "Dock disable() method not found."
        )

    method = """    _syncNivethTheme() {
        if (!this._dock)
            return;

        let scheme = 'prefer-dark';

        try {
            scheme =
                this._nivethInterfaceSettings.get_string(
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
    }

"""

    text = text[:disable_pos] + method + text[disable_pos:]

# --------------------------------------------------
# Disconnect signal on disable()
# --------------------------------------------------

if "_nivethInterfaceSettings.disconnect(" not in text:

    disable_pos = text.find("    disable()")

    if disable_pos == -1:
        raise SystemExit(
            "Dock disable() method not found."
        )

    cleanup = """    disable() {
        if (this._nivethColorSchemeChangedId) {
            try {
                this._nivethInterfaceSettings.disconnect(
                    this._nivethColorSchemeChangedId
                );
            } catch (error) {
            }

            this._nivethColorSchemeChangedId = null;
        }

"""

    original = "    disable() {\n"

    text = (
        text[:disable_pos]
        + cleanup
        + text[disable_pos + len(original):]
    )

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

# --------------------------------------------------
# Add GNOME settings + listener
# --------------------------------------------------

if "this._nivethInterfaceSettings" not in text:

    anchor = "this._createIcons();"

    pos = text.find(anchor)

    if pos == -1:
        raise SystemExit(
            "UI Test _createIcons() anchor not found."
        )

    end = pos + len(anchor)

    injection = """

        this._nivethInterfaceSettings =
            Gio.Settings.new(
                'org.gnome.desktop.interface'
            );

        this._nivethColorSchemeChangedId =
            this._nivethInterfaceSettings.connect(
                'changed::color-scheme',
                () => this._updateTheme()
            );

"""

    text = text[:end] + injection + text[end:]

# --------------------------------------------------
# Replace only the time calculation inside
# existing _updateTheme()
# --------------------------------------------------

start = text.find("    _updateTheme()")

if start == -1:
    raise SystemExit(
        "UI Test _updateTheme() method not found."
    )

end = text.find(
    "\n    _updatePosition()",
    start
)

if end == -1:
    raise SystemExit(
        "UI Test _updatePosition() anchor not found."
    )

block = text[start:end]

# Locate the old hour-based theme section.
pattern = re.compile(
    r"""        const now =.*?const dark =.*?;\n""",
    re.S
)

replacement = """        let scheme = 'prefer-dark';

        try {
            scheme =
                this._nivethInterfaceSettings.get_string(
                    'color-scheme'
                );
        } catch (error) {
            scheme = 'prefer-dark';
        }

        const dark = scheme === 'prefer-dark';
"""

new_block, count = pattern.subn(
    replacement,
    block,
    count=1
)

if count != 1:
    raise SystemExit(
        "Could not locate UI Test hour-based theme logic."
    )

text = text[:start] + new_block + text[end:]

# --------------------------------------------------
# Disconnect listener
# --------------------------------------------------

if "this._nivethInterfaceSettings.disconnect(" not in text:

    disable_pos = text.find("    disable()")

    if disable_pos == -1:
        raise SystemExit(
            "UI Test disable() method not found."
        )

    cleanup = """    disable() {
        if (this._nivethColorSchemeChangedId) {
            try {
                this._nivethInterfaceSettings.disconnect(
                    this._nivethColorSchemeChangedId
                );
            } catch (error) {
            }

            this._nivethColorSchemeChangedId = null;
        }

"""

    original = "    disable() {\n"

    text = (
        text[:disable_pos]
        + cleanup
        + text[disable_pos + len(original):]
    )

path.write_text(text, encoding="utf-8")
PY

echo "UI Test / Top Bar patched."

echo
echo "=================================================="
echo " 4. Verification"
echo "=================================================="

echo "--- Dock listener ---"
grep -n "changed::color-scheme" "$DOCK_HOST"

echo
echo "--- Dock sync method ---"
grep -n "_syncNivethTheme" "$DOCK_HOST"

echo
echo "--- UI Test listener ---"
grep -n "changed::color-scheme" "$UI_HOST"

echo
echo "--- UI Test color-scheme ---"
grep -n "get_string" "$UI_HOST" | grep color-scheme

echo
echo "=================================================="
echo " 5. Synchronize into rootfs"
echo "=================================================="

sudo mkdir -p \
    "$ROOTFS_EXT/$DOCK" \
    "$ROOTFS_EXT/$UI"

sudo cp -f \
    "$DOCK_HOST" \
    "$DOCK_ROOT"

sudo cp -f \
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
echo " 6. Restart extensions"
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

echo "Color scheme:"
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
