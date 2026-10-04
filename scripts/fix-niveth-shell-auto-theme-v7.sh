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
BACKUP_DIR="$PROJECT_ROOT/integration-backups/shell-auto-theme-v7-$STAMP"

echo "=================================================="
echo " Niveth Shell Automatic Light/Dark Theme Fix v7"
echo "=================================================="
echo

if [ ! -f "$CLEAN_BACKUP/niveth-dock-extension.js" ]; then
    echo "ERROR: Clean Dock backup not found."
    exit 1
fi

if [ ! -f "$CLEAN_BACKUP/niveth-ui-test-extension.js" ]; then
    echo "ERROR: Clean UI Test backup not found."
    exit 1
fi

if [ ! -d "$ROOTFS" ]; then
    echo "ERROR: Rootfs not found."
    exit 1
fi

mkdir -p "$BACKUP_DIR"

echo "=================================================="
echo " 1. Restore clean sources"
echo "=================================================="

cp -f \
    "$CLEAN_BACKUP/niveth-dock-extension.js" \
    "$DOCK_HOST"

cp -f \
    "$CLEAN_BACKUP/niveth-ui-test-extension.js" \
    "$UI_HOST"

cp -a \
    "$DOCK_HOST" \
    "$BACKUP_DIR/niveth-dock-extension.js"

cp -a \
    "$UI_HOST" \
    "$BACKUP_DIR/niveth-ui-test-extension.js"

echo "Clean sources restored."
echo
echo "Backup:"
echo "  $BACKUP_DIR"

echo
echo "=================================================="
echo " 2. Patch Dock"
echo "=================================================="

python3 - "$DOCK_HOST" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")

# --------------------------------------------------
# Create theme settings object in enable()
# --------------------------------------------------

if "this._nivethPollingThemeSettings" not in text:

    anchor = "this._theme.load_stylesheet(this._stylesheet);"

    pos = text.find(anchor)

    if pos == -1:
        raise SystemExit(
            "Dock stylesheet anchor not found."
        )

    end = pos + len(anchor)

    insert = """

        this._nivethPollingThemeSettings =
            Gio.Settings.new(
                'org.gnome.desktop.interface'
            );

"""

    text = text[:end] + insert + text[end:]

# --------------------------------------------------
# Create _updateTheme()
# --------------------------------------------------

if "\n    _updateTheme() {" in text:
    start = text.find("\n    _updateTheme() {")

    end = text.find(
        "\n    _loadFolders() {",
        start
    )

    if end == -1:
        raise SystemExit(
            "Dock _loadFolders() anchor not found."
        )
else:
    end = text.find(
        "\n    _loadFolders() {"
    )

    if end == -1:
        raise SystemExit(
            "Dock _loadFolders() anchor not found."
        )

    start = end

replacement = """
    _updateTheme() {
        if (!this._dock)
            return;

        let scheme = 'prefer-light';

        try {
            scheme =
                this._nivethPollingThemeSettings.get_string(
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
                .remove_style_class_name(
                    'dark'
                );

            this._activeMenu
                .remove_style_class_name(
                    'light'
                );

            this._activeMenu
                .add_style_class_name(
                    dark ? 'dark' : 'light'
                );
        }

        this._isDark = dark;
    }

"""

text = (
    text[:start]
    + replacement
    + text[end:]
)

# --------------------------------------------------
# Add polling timer after Dock is shown
# --------------------------------------------------

if "_nivethPollingThemeTimerId" not in text:

    marker = "this._dock.show();"

    pos = text.find(marker)

    if pos == -1:
        raise SystemExit(
            "Dock show() anchor not found."
        )

    end = pos + len(marker)

    timer = """

        this._updateTheme();

        this._nivethPollingThemeTimerId =
            GLib.timeout_add_seconds(
                GLib.PRIORITY_DEFAULT,
                1,
                () => {
                    this._updateTheme();
                    return GLib.SOURCE_CONTINUE;
                }
            );

"""

    text = (
        text[:end]
        + timer
        + text[end:]
    )

# --------------------------------------------------
# Remove timer + settings object in disable()
# --------------------------------------------------

if "_nivethPollingThemeTimerId" not in text:
    raise SystemExit(
        "Dock theme timer was not created."
    )

disable_pos = text.find(
    "\n    disable() {"
)

if disable_pos == -1:
    raise SystemExit(
        "Dock disable() not found."
    )

disable_end = (
    disable_pos
    + len("\n    disable() {")
)

if "GLib.source_remove(\n                this._nivethPollingThemeTimerId" not in text:

    cleanup = """

        if (this._nivethPollingThemeTimerId) {
            GLib.source_remove(
                this._nivethPollingThemeTimerId
            );

            this._nivethPollingThemeTimerId = null;
        }

        this._nivethPollingThemeSettings = null;
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
    "_nivethPollingThemeSettings",
    "_nivethPollingThemeTimerId",
    "_updateTheme() {",
    "get_string(",
    "'color-scheme'",
    "this._dock.add_style_class_name(",
    "GLib.timeout_add_seconds(",
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

print("Dock patch complete.")
PY

echo
echo "=================================================="
echo " 3. Patch Top Bar"
echo "=================================================="

python3 - "$UI_HOST" <<'PY'
from pathlib import Path
import re
import sys

path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")

# --------------------------------------------------
# Create settings object
# --------------------------------------------------

if "this._nivethPollingThemeSettings" not in text:

    anchor = "this._createIcons();"

    pos = text.find(anchor)

    if pos == -1:
        raise SystemExit(
            "UI Test _createIcons() anchor not found."
        )

    end = pos + len(anchor)

    insert = """

        this._nivethPollingThemeSettings =
            Gio.Settings.new(
                'org.gnome.desktop.interface'
            );

"""

    text = text[:end] + insert + text[end:]

# --------------------------------------------------
# Replace complete _updateTheme()
# --------------------------------------------------

start = text.find(
    "\n    _updateTheme() {"
)

if start == -1:
    raise SystemExit(
        "UI Test _updateTheme() not found."
    )

end = text.find(
    "\n    _updatePosition() {",
    start
)

if end == -1:
    raise SystemExit(
        "UI Test _updatePosition() not found."
    )

replacement = """
    _updateTheme() {
        if (!this._bar)
            return;

        let scheme = 'prefer-light';

        try {
            scheme =
                this._nivethPollingThemeSettings.get_string(
                    'color-scheme'
                );
        } catch (error) {
            scheme = 'prefer-light';
        }

        const dark =
            scheme === 'prefer-dark';

        #ERROR_MARKER

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

        try {
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

        } catch (error) {
            log(
                `NIVETH: theme icon refresh skipped: ${error}`
            );
        }

        this._updateClock();
    }

"""

# Remove the placeholder because this is shell JS,
# not a preprocessor file.
replacement = replacement.replace(
    "        #ERROR_MARKER\n\n",
    ""
)

text = (
    text[:start]
    + replacement
    + text[end:]
)

# --------------------------------------------------
# Change existing theme timer from 30s to 1s
# --------------------------------------------------

pattern = re.compile(
    r"(this\._themeTimer\s*=\s*GLib\.timeout_add_seconds\(\s*"
    r"GLib\.PRIORITY_DEFAULT,\s*)"
    r"30"
)

text, count = pattern.subn(
    r"\g<1>1",
    text,
    count=1
)

if count != 1:
    raise SystemExit(
        "UI Test existing 30-second theme timer not found."
    )

# --------------------------------------------------
# Validate
# --------------------------------------------------

required = [
    "_nivethPollingThemeSettings",
    "_updateTheme() {",
    "get_string(",
    "'color-scheme'",
    "this._bar",
    "this._themeTimer",
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

print("Top Bar patch complete.")
PY

echo
echo "=================================================="
echo " 4. JavaScript basic structure check"
echo "=================================================="

python3 - "$DOCK_HOST" "$UI_HOST" <<'PY'
from pathlib import Path
import sys

for filename in sys.argv[1:]:
    text = Path(filename).read_text(
        encoding="utf-8"
    )

    if text.count("{") != text.count("}"):
        raise SystemExit(
            f"Brace count mismatch: {filename}"
        )

    if text.count("(") != text.count(")"):
        raise SystemExit(
            f"Parenthesis count mismatch: {filename}"
        )

print("Basic structure check: OK")
PY

echo
echo "=================================================="
echo " 5. Verify polling code"
echo "=================================================="

echo "--- Dock ---"

grep -nE \
    "nivethPollingTheme|_updateTheme|color-scheme|timeout_add_seconds" \
    "$DOCK_HOST"

echo
echo "--- Top Bar ---"

grep -nE \
    "nivethPollingTheme|_updateTheme|color-scheme|_themeTimer|timeout_add_seconds" \
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

sleep 4

echo
echo "=================================================="
echo " 8. Final state"
echo "=================================================="

echo "Color scheme:"
gsettings get \
    org.gnome.desktop.interface \
    color-scheme

echo
echo "Dock:"
gnome-extensions info "$DOCK" 2>/dev/null | \
    grep -E 'Name|Enabled|State' || true

echo
echo "Top Bar:"
gnome-extensions info "$UI" 2>/dev/null | \
    grep -E 'Name|Enabled|State' || true

echo
echo "=================================================="
echo " COMPLETE"
echo "=================================================="
