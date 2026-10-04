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

CLEAN_BACKUP="$PROJECT_ROOT/integration-backups/shell-auto-theme-20260921-090805"

STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP_DIR="$PROJECT_ROOT/integration-backups/shell-auto-theme-v5-$STAMP"

echo "=================================================="
echo " Niveth Shell Automatic Light/Dark Theme Fix v5"
echo "=================================================="
echo

if [ ! -f "$CLEAN_BACKUP/niveth-dock-extension.js" ]; then
    echo "ERROR: Clean Dock backup not found:"
    echo "  $CLEAN_BACKUP/niveth-dock-extension.js"
    exit 1
fi

if [ ! -f "$CLEAN_BACKUP/niveth-ui-test-extension.js" ]; then
    echo "ERROR: Clean UI Test backup not found:"
    echo "  $CLEAN_BACKUP/niveth-ui-test-extension.js"
    exit 1
fi

if [ ! -d "$ROOTFS" ]; then
    echo "ERROR: Rootfs not found:"
    echo "  $ROOTFS"
    exit 1
fi

mkdir -p "$BACKUP_DIR"

echo "=================================================="
echo " 1. Restore clean source"
echo "=================================================="

cp -f \
    "$CLEAN_BACKUP/niveth-dock-extension.js" \
    "$DOCK_HOST"

cp -f \
    "$CLEAN_BACKUP/niveth-ui-test-extension.js" \
    "$UI_HOST"

echo "Clean sources restored."

echo
echo "Backup:"
echo "  $BACKUP_DIR"

cp -a "$DOCK_HOST" \
    "$BACKUP_DIR/niveth-dock-extension.js"

cp -a "$UI_HOST" \
    "$BACKUP_DIR/niveth-ui-test-extension.js"

echo
echo "=================================================="
echo " 2. Patch Niveth Dock"
echo "=================================================="

python3 - "$DOCK_HOST" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")

# --------------------------------------------------
# Add GNOME color-scheme listener
# --------------------------------------------------

if "this._interfaceSettings = Gio.Settings.new('org.gnome.desktop.interface');" not in text:

    marker_start = text.find(
        "this._theme.load_stylesheet(this._stylesheet);"
    )

    if marker_start == -1:
        raise SystemExit(
            "Dock: stylesheet load call not found."
        )

    marker_end = marker_start + len(
        "this._theme.load_stylesheet(this._stylesheet);"
    )

    insertion = """

        this._interfaceSettings =
            Gio.Settings.new(
                'org.gnome.desktop.interface'
            );

        this._colorSchemeChangedId =
            this._interfaceSettings.connect(
                'changed::color-scheme',
                () => this._updateTheme()
            );

"""

    text = (
        text[:marker_end]
        + insertion
        + text[marker_end:]
    )

# --------------------------------------------------
# Replace Dock _updateTheme() completely
# --------------------------------------------------

start = text.find("\n    _updateTheme() {")

if start == -1:
    raise SystemExit(
        "Dock: _updateTheme() not found."
    )

end = text.find(
    "\n    _loadFolders() {",
    start
)

if end == -1:
    raise SystemExit(
        "Dock: _loadFolders() not found after _updateTheme()."
    )

replacement = """
    _updateTheme() {
        if (!this._dock)
            return;

        let scheme = 'prefer-light';

        try {
            scheme =
                this._interfaceSettings.get_string(
                    'color-scheme'
                );
        } catch (error) {
            scheme = 'prefer-light';
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

"""

text = (
    text[:start]
    + replacement
    + text[end:]
)

# --------------------------------------------------
# Make sure initial Dock theme is applied
# after the Dock has actually been created.
# --------------------------------------------------

if "this._dock.show();\n        this._updateTheme();" not in text:

    marker = "this._dock.show();"

    pos = text.find(marker)

    if pos == -1:
        raise SystemExit(
            "Dock: this._dock.show() not found."
        )

    end = pos + len(marker)

    text = (
        text[:end]
        + """

        this._updateTheme();
"""
        + text[end:]
    )

# --------------------------------------------------
# Disconnect GNOME settings signal
# --------------------------------------------------

if "this._interfaceSettings.disconnect(" not in text:

    disable_start = text.find("\n    disable() {")

    if disable_start == -1:
        raise SystemExit(
            "Dock: disable() not found."
        )

    disable_end = disable_start + len(
        "\n    disable() {"
    )

    cleanup = """

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

    text = (
        text[:disable_end]
        + cleanup
        + text[disable_end:]
    )

# --------------------------------------------------
# Validate
# --------------------------------------------------

required = [
    "changed::color-scheme",
    "this._interfaceSettings.get_string(",
    "'color-scheme'",
    "this._dock.add_style_class_name(",
    "this._interfaceSettings.disconnect(",
]

for item in required:
    if item not in text:
        raise SystemExit(
            f"Dock validation failed: missing {item}"
        )

path.write_text(text, encoding="utf-8")
PY

echo "Dock patch complete."

echo
echo "=================================================="
echo " 3. Patch Niveth UI Test / Top Bar"
echo "=================================================="

python3 - "$UI_HOST" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")

# --------------------------------------------------
# Add GNOME color-scheme listener
# --------------------------------------------------

if "this._interfaceSettings = Gio.Settings.new('org.gnome.desktop.interface');" not in text:

    marker = """        this._createLogo();
        this._createIcons();
"""

    if marker not in text:
        raise SystemExit(
            "UI Test: createLogo/createIcons anchor not found."
        )

    listener = """
        this._interfaceSettings =
            Gio.Settings.new(
                'org.gnome.desktop.interface'
            );

        this._colorSchemeChangedId =
            this._interfaceSettings.connect(
                'changed::color-scheme',
                () => this._updateTheme()
            );

"""

    text = text.replace(
        marker,
        marker + listener,
        1
    )

# --------------------------------------------------
# Replace the WHOLE _updateTheme() method.
# This avoids depending on its internal formatting.
# --------------------------------------------------

start = text.find("\n    _updateTheme() {")

if start == -1:
    raise SystemExit(
        "UI Test: _updateTheme() not found."
    )

end = text.find(
    "\n    _updatePosition() {",
    start
)

if end == -1:
    raise SystemExit(
        "UI Test: _updatePosition() not found."
    )

replacement = """
    _updateTheme() {
        if (!this._bar)
            return;

        let scheme = 'prefer-light';

        try {
            scheme =
                this._interfaceSettings.get_string(
                    'color-scheme'
                );
        } catch (error) {
            scheme = 'prefer-light';
        }

        const dark = scheme === 'prefer-dark';

        this._bar
            .remove_style_class_name(
                'niveth-dark'
            );

        this._clock
            ?.remove_style_class_name(
                'niveth-dark'
            );

        if (dark) {
            this._bar
                .add_style_class_name(
                    'niveth-dark'
                );

            this._clock
                ?.add_style_class_name(
                    'niveth-dark'
                );
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
            if (
                child ===
                this._powerButton
            ) {
                this._setIcon(
                    this._powerIcon,
                    'power',
                    dark
                );
            } else if (
                child._nivethIcon
            ) {
                this._setIcon(
                    child._nivethIcon,
                    child._nivethName,
                    dark
                );
            }
        }

        this._updateClock();
    }

"""

text = (
    text[:start]
    + replacement
    + text[end:]
)

# --------------------------------------------------
# Disconnect signal on disable()
# --------------------------------------------------

if "this._interfaceSettings.disconnect(" not in text:

    disable_start = text.find("\n    disable() {")

    if disable_start == -1:
        raise SystemExit(
            "UI Test: disable() not found."
        )

    disable_end = disable_start + len(
        "\n    disable() {"
    )

    cleanup = """

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

    text = (
        text[:disable_end]
        + cleanup
        + text[disable_end:]
    )

# --------------------------------------------------
# Validate
# --------------------------------------------------

required = [
    "changed::color-scheme",
    "this._interfaceSettings.get_string(",
    "'color-scheme'",
    "this._bar",
    "this._setIcon(",
    "this._interfaceSettings.disconnect(",
]

for item in required:
    if item not in text:
        raise SystemExit(
            f"UI Test validation failed: missing {item}"
        )

path.write_text(text, encoding="utf-8")
PY

echo "UI Test / Top Bar patch complete."

echo
echo "=================================================="
echo " 4. JavaScript syntax check"
echo "=================================================="

node --check "$DOCK_HOST"
node --check "$UI_HOST"

echo "JavaScript syntax: OK"

echo
echo "=================================================="
echo " 5. Verify theme code"
echo "=================================================="

echo "--- DOCK ---"
grep -nE \
    "changed::color-scheme|get_string|color-scheme|_updateTheme|disconnect" \
    "$DOCK_HOST"

echo
echo "--- UI TEST / TOP BAR ---"
grep -nE \
    "changed::color-scheme|get_string|color-scheme|_updateTheme|disconnect" \
    "$UI_HOST"

echo
echo "=================================================="
echo " 6. Synchronize HOST -> ROOTFS"
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
echo " 7. Restart active extensions"
echo "=================================================="

gnome-extensions disable "$DOCK" 2>/dev/null || true
gnome-extensions disable "$UI" 2>/dev/null || true

sleep 2

gnome-extensions enable "$DOCK"
gnome-extensions enable "$UI"

sleep 3

echo
echo "=================================================="
echo " 8. Final state"
echo "=================================================="

echo "GNOME color scheme:"
gsettings get org.gnome.desktop.interface color-scheme

echo
echo "Dock:"
gnome-extensions info "$DOCK" 2>/dev/null | \
    grep -E 'State|Name' || true

echo
echo "UI Test / Top Bar:"
gnome-extensions info "$UI" 2>/dev/null | \
    grep -E 'State|Name' || true

echo
echo "=================================================="
echo " COMPLETE"
echo "=================================================="
