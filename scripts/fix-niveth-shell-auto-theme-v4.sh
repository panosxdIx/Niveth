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
BACKUP_DIR="$PROJECT_ROOT/integration-backups/shell-auto-theme-v4-$STAMP"

echo "=================================================="
echo " Niveth Shell Automatic Light/Dark Theme Fix v4"
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

echo "=== 1. Restore clean extension sources ==="

cp -f \
    "$CLEAN_BACKUP/niveth-dock-extension.js" \
    "$DOCK_HOST"

cp -f \
    "$CLEAN_BACKUP/niveth-ui-test-extension.js" \
    "$UI_HOST"

echo "Clean source restored."

echo
echo "=== 2. Backup restored source ==="

cp -a "$DOCK_HOST" "$BACKUP_DIR/niveth-dock-extension.js"
cp -a "$UI_HOST" "$BACKUP_DIR/niveth-ui-test-extension.js"

echo "Backup:"
echo "  $BACKUP_DIR"

echo
echo "=================================================="
echo " 3. Patch Dock"
echo "=================================================="

python3 - "$DOCK_HOST" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")

# --------------------------------------------------
# 1. Add GNOME interface settings + listener
# --------------------------------------------------

if "this._nivethColorSchemeChangedId" not in text:

    anchor = "this._theme.load_stylesheet(this._stylesheet);"

    pos = text.find(anchor)

    if pos == -1:
        raise SystemExit(
            "Dock: stylesheet load anchor not found."
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
# 2. Add the actual method BEFORE disable()
# --------------------------------------------------

if "\n    _syncNivethTheme() {" not in text:

    disable_pos = text.find("\n    disable()")

    if disable_pos == -1:
        raise SystemExit(
            "Dock: disable() method not found."
        )

    method = """
    _syncNivethTheme() {
        if (!this._dock)
            return;

        let scheme = 'prefer-light';

        try {
            scheme =
                this._nivethInterfaceSettings.get_string(
                    'color-scheme'
                );
        } catch (error) {
            console.error(
                `Niveth Dock: color-scheme read failed: ${error}`
            );
        }

        const dark = scheme === 'prefer-dark';

        this._dock.remove_style_class_name('dark');
        this._dock.remove_style_class_name('light');

        this._dock.add_style_class_name(
            dark ? 'dark' : 'light'
        );
    }
"""

    text = (
        text[:disable_pos]
        + method
        + text[disable_pos:]
    )

# --------------------------------------------------
# 3. Add initial synchronization call
# --------------------------------------------------

if "this._syncNivethTheme();" not in text:

    marker = "this._nivethColorSchemeChangedId ="

    pos = text.find(marker)

    if pos == -1:
        raise SystemExit(
            "Dock: color-scheme connection not found."
        )

    end = text.find(");", pos)

    if end == -1:
        raise SystemExit(
            "Dock: color-scheme connection end not found."
        )

    end += 2

    text = (
        text[:end]
        + """

        this._syncNivethTheme();
"""
        + text[end:]
    )

# --------------------------------------------------
# 4. Disconnect listener on disable()
# --------------------------------------------------

if "this._nivethInterfaceSettings.disconnect(" not in text:

    disable_pos = text.find("\n    disable()")

    if disable_pos == -1:
        raise SystemExit(
            "Dock: disable() method not found."
        )

    disable_end = disable_pos + len("\n    disable() {")

    cleanup = """

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

    text = text[:disable_end] + cleanup + text[disable_end:]

# --------------------------------------------------
# 5. Final validation
# --------------------------------------------------

required = [
    "changed::color-scheme",
    "_syncNivethTheme() {",
    "this._syncNivethTheme();",
    "this._nivethInterfaceSettings.disconnect(",
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
echo " 4. Patch Niveth UI Test / Top Bar"
echo "=================================================="

python3 - "$UI_HOST" <<'PY'
from pathlib import Path
import re
import sys

path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")

# --------------------------------------------------
# 1. Add GNOME interface settings + listener
# --------------------------------------------------

if "this._nivethColorSchemeChangedId" not in text:

    anchor = "this._createIcons();"

    pos = text.find(anchor)

    if pos == -1:
        raise SystemExit(
            "UI Test: _createIcons() anchor not found."
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
# 2. Replace time-based theme decision
# --------------------------------------------------

start = text.find("\n    _updateTheme() {")

if start == -1:
    raise SystemExit(
        "UI Test: _updateTheme() not found."
    )

end = text.find(
    "\n    _updatePosition()",
    start
)

if end == -1:
    raise SystemExit(
        "UI Test: _updatePosition() not found."
    )

block = text[start:end]

# Replace the old time-based section.
old_pattern = re.compile(
    r"""
        \s*const now = GLib\.DateTime\.new_now_local\(\);
        \s*const hour = now\.get_hour\(\);
        \s*const dark = hour >= 19 \|\| hour < 7;
    """,
    re.VERBOSE
)

new_logic = """

        let scheme = 'prefer-light';

        try {
            scheme =
                this._nivethInterfaceSettings.get_string(
                    'color-scheme'
                );
        } catch (error) {
            console.error(
                `Niveth UI Test: color-scheme read failed: ${error}`
            );
        }

        const dark = scheme === 'prefer-dark';
"""

block2, count = old_pattern.subn(
    new_logic,
    block,
    count=1
)

if count != 1:
    raise SystemExit(
        "UI Test: old time-based theme logic not found."
    )

text = text[:start] + block2 + text[end:]

# --------------------------------------------------
# 3. Disconnect listener
# --------------------------------------------------

if "this._nivethInterfaceSettings.disconnect(" not in text:

    disable_pos = text.find("\n    disable()")

    if disable_pos == -1:
        raise SystemExit(
            "UI Test: disable() not found."
        )

    disable_end = disable_pos + len("\n    disable() {")

    cleanup = """

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

    text = text[:disable_end] + cleanup + text[disable_end:]

# --------------------------------------------------
# 4. Validation
# --------------------------------------------------

required = [
    "changed::color-scheme",
    "get_string(",
    "'color-scheme'",
    "this._nivethInterfaceSettings.disconnect(",
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
echo " 5. Verify source"
echo "=================================================="

echo "--- Dock ---"
grep -nE \
    "changed::color-scheme|_syncNivethTheme|color-scheme|disconnect" \
    "$DOCK_HOST"

echo
echo "--- UI Test ---"
grep -nE \
    "changed::color-scheme|get_string|color-scheme|disconnect" \
    "$UI_HOST"

echo
echo "=================================================="
echo " 6. JavaScript syntax check"
echo "=================================================="

node --check "$DOCK_HOST"
node --check "$UI_HOST"

echo "JavaScript syntax: OK"

echo
echo "=================================================="
echo " 7. Synchronize HOST -> ROOTFS"
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
echo " 8. Restart extensions"
echo "=================================================="

gnome-extensions disable "$DOCK" 2>/dev/null || true
gnome-extensions disable "$UI" 2>/dev/null || true

sleep 2

gnome-extensions enable "$DOCK"
gnome-extensions enable "$UI"

sleep 3

echo
echo "=================================================="
echo " 9. Final state"
echo "=================================================="

echo "Current GNOME color scheme:"
gsettings get org.gnome.desktop.interface color-scheme

echo
echo "Dock:"
gnome-extensions info "$DOCK" 2>/dev/null | \
    grep -E 'State|Name' || true

echo
echo "UI Test:"
gnome-extensions info "$UI" 2>/dev/null | \
    grep -E 'State|Name' || true

echo
echo "=================================================="
echo " COMPLETE"
echo "=================================================="
