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
BACKUP_DIR="$PROJECT_ROOT/integration-backups/shell-auto-theme-v6-$STAMP"

echo "=================================================="
echo " Niveth Shell Automatic Light/Dark Theme Fix v6"
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

cp -a "$DOCK_HOST" \
    "$BACKUP_DIR/niveth-dock-extension.js"

cp -a "$UI_HOST" \
    "$BACKUP_DIR/niveth-ui-test-extension.js"

echo
echo "Backup:"
echo "  $BACKUP_DIR"

echo
echo "=================================================="
echo " 2. Build Dock patch"
echo "=================================================="

python3 - "$DOCK_HOST" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")

# --------------------------------------------------
# Add GNOME color-scheme listener
# --------------------------------------------------

if "this._nivethThemeSettings" not in text:

    anchor = "this._theme.load_stylesheet(this._stylesheet);"

    pos = text.find(anchor)

    if pos == -1:
        raise SystemExit(
            "Dock: stylesheet load call not found."
        )

    end = pos + len(anchor)

    listener = """

        this._nivethThemeSettings =
            Gio.Settings.new(
                'org.gnome.desktop.interface'
            );

        this._nivethThemeChangedId =
            this._nivethThemeSettings.connect(
                'changed::color-scheme',
                () => this._updateTheme()
            );
"""

    text = (
        text[:end]
        + listener
        + text[end:]
    )

# --------------------------------------------------
# Create or replace _updateTheme()
# --------------------------------------------------

start = text.find("\n    _updateTheme() {")

if start != -1:

    end = text.find(
        "\n    _loadFolders() {",
        start
    )

    if end == -1:
        raise SystemExit(
            "Dock: _loadFolders() not found."
        )

else:

    end = text.find(
        "\n    _loadFolders() {"
    )

    if end == -1:
        raise SystemExit(
            "Dock: _loadFolders() anchor not found."
        )

    start = end

replacement = """
    _updateTheme() {
        if (!this._dock)
            return;

        let scheme = 'prefer-light';

        try {
            scheme =
                this._nivethThemeSettings.get_string(
                    'color-scheme'
                );
        } catch (error) {
            scheme = 'prefer-light';
        }

        const dark =
            scheme === 'prefer-dark';

        this._dock.remove_style_class_name(
            'dark'
        );

        this._dock.remove_style_class_name(
            'light'
        );

        this._dock.add_style_class_name(
            dark ? 'dark' : 'light'
        );

        if (this._activeMenu) {
            this._activeMenu
                .remove_style_class_name('dark');

            this._activeMenu
                .remove_style_class_name('light');

            this._activeMenu
                .add_style_class_name(
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
# Initial theme update
# --------------------------------------------------

if "this._updateTheme();" not in text:

    # Prefer after dock visibility/show.
    marker = "this._dock.show();"

    pos = text.find(marker)

    if pos != -1:
        end = pos + len(marker)

        text = (
            text[:end]
            + """

        this._updateTheme();
"""
            + text[end:]
        )

    else:

        # Fallback: immediately after signal creation.
        marker = "this._nivethThemeChangedId ="

        pos = text.find(marker)

        if pos == -1:
            raise SystemExit(
                "Dock: could not place initial theme update."
            )

        end = text.find(");", pos)

        if end == -1:
            raise SystemExit(
                "Dock: signal connection end not found."
            )

        end += 2

        text = (
            text[:end]
            + """

        this._updateTheme();
"""
            + text[end:]
        )

# --------------------------------------------------
# Disconnect listener in disable()
# --------------------------------------------------

if "this._nivethThemeSettings.disconnect(" not in text:

    disable_pos = text.find(
        "\n    disable() {"
    )

    if disable_pos == -1:
        raise SystemExit(
            "Dock: disable() not found."
        )

    disable_end = (
        disable_pos
        + len("\n    disable() {")
    )

    cleanup = """

        if (this._nivethThemeChangedId) {
            try {
                this._nivethThemeSettings.disconnect(
                    this._nivethThemeChangedId
                );
            } catch (error) {
            }

            this._nivethThemeChangedId = null;
        }
"""

    text = (
        text[:disable_end]
        + cleanup
        + text[disable_end:]
    )

# --------------------------------------------------
# Validate Dock completely before writing
# --------------------------------------------------

required = [
    "this._nivethThemeSettings =",
    "changed::color-scheme",
    "_updateTheme() {",
    "get_string(",
    "'color-scheme'",
    "this._dock.add_style_class_name(",
    "this._nivethThemeSettings.disconnect(",
]

for item in required:
    if item not in text:
        raise SystemExit(
            f"Dock validation failed: {item}"
        )

path.write_text(
    text,
    encoding="utf-8"
)

print("Dock patch prepared successfully.")
PY

echo "Dock patch complete."

echo
echo "=================================================="
echo " 3. Build UI Test / Top Bar patch"
echo "=================================================="

python3 - "$UI_HOST" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")

# --------------------------------------------------
# Add GNOME color-scheme listener
# --------------------------------------------------

if "this._nivethThemeSettings" not in text:

    marker = """        this._createLogo();
        this._createIcons();
"""

    if marker not in text:
        raise SystemExit(
            "UI Test: createLogo/createIcons anchor not found."
        )

    listener = """
        this._nivethThemeSettings =
            Gio.Settings.new(
                'org.gnome.desktop.interface'
            );

        this._nivethThemeChangedId =
            this._nivethThemeSettings.connect(
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
# Create or replace _updateTheme()
# --------------------------------------------------

start = text.find(
    "\n    _updateTheme() {"
)

if start == -1:

    end = text.find(
        "\n    _updatePosition() {"
    )

    if end == -1:
        raise SystemExit(
            "UI Test: _updatePosition() anchor not found."
        )

    start = end

else:

    end = text.find(
        "\n    _updatePosition() {",
        start
    )

    if end == -1:
        raise SystemExit(
            "UI Test: _updatePosition() anchor not found."
        )

replacement = """
    _updateTheme() {
        if (!this._bar)
            return;

        let scheme = 'prefer-light';

        try {
            scheme =
                this._nivethThemeSettings.get_string(
                    'color-scheme'
                );
        } catch (error) {
            scheme = 'prefer-light';
        }

        const dark =
            scheme === 'prefer-dark';

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
# Disconnect listener
# --------------------------------------------------

if "this._nivethThemeSettings.disconnect(" not in text:

    disable_pos = text.find(
        "\n    disable() {"
    )

    if disable_pos == -1:
        raise SystemExit(
            "UI Test: disable() not found."
        )

    disable_end = (
        disable_pos
        + len("\n    disable() {")
    )

    cleanup = """

        if (this._nivethThemeChangedId) {
            try {
                this._nivethThemeSettings.disconnect(
                    this._nivethThemeChangedId
                );
            } catch (error) {
            }

            this._nivethThemeChangedId = null;
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
    "this._nivethThemeSettings =",
    "changed::color-scheme",
    "_updateTheme() {",
    "get_string(",
    "'color-scheme'",
    "this._setIcon(",
    "this._nivethThemeSettings.disconnect(",
]

for item in required:
    if item not in text:
        raise SystemExit(
            f"UI Test validation failed: {item}"
        )

path.write_text(
    text,
    encoding="utf-8"
)

print("UI Test patch prepared successfully.")
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
echo " 5. Verify HOST source"
echo "=================================================="

echo "--- DOCK ---"

grep -nE \
    "nivethTheme|changed::color-scheme|_updateTheme|color-scheme|disconnect" \
    "$DOCK_HOST"

echo
echo "--- UI TEST ---"

grep -nE \
    "nivethTheme|changed::color-scheme|_updateTheme|color-scheme|disconnect" \
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
echo " 7. Restart extensions"
echo "=================================================="

gnome-extensions disable "$DOCK" 2>/dev/null || true
gnome-extensions disable "$UI" 2>/dev/null || true

sleep 2

gnome-extensions enable "$DOCK"
gnome-extensions enable "$UI"

sleep 3

echo
echo "=================================================="
echo " 8. Final status"
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
