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

PREVIOUS_BACKUP="$PROJECT_ROOT/integration-backups/shell-auto-theme-20260921-090805"

STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP_DIR="$PROJECT_ROOT/integration-backups/shell-auto-theme-v2-$STAMP"

echo "=================================================="
echo " Niveth Shell Automatic Light/Dark Theme Fix v2"
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

echo "=== 1. Restoring clean pre-v1 state ==="

if [ -f "$PREVIOUS_BACKUP/niveth-dock-extension.js" ]; then
    cp -f \
        "$PREVIOUS_BACKUP/niveth-dock-extension.js" \
        "$DOCK_HOST"
    echo "Dock restored from previous backup."
fi

if [ -f "$PREVIOUS_BACKUP/niveth-ui-test-extension.js" ]; then
    cp -f \
        "$PREVIOUS_BACKUP/niveth-ui-test-extension.js" \
        "$UI_HOST"
    echo "UI Test restored from previous backup."
fi

mkdir -p "$BACKUP_DIR"

cp -a "$DOCK_HOST" \
    "$BACKUP_DIR/niveth-dock-extension.js"

cp -a "$UI_HOST" \
    "$BACKUP_DIR/niveth-ui-test-extension.js"

echo
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
# Add GNOME color-scheme listener
# --------------------------------------------------

if "changed::color-scheme" not in text:
    marker = """        try {
            this._theme.load_stylesheet(this._stylesheet);
        } catch (error) {
            console.error(`Niveth Dock: stylesheet load failed: ${error}`);
        }
"""

    if marker not in text:
        # Try a more tolerant anchor.
        marker_start = text.find("this._theme.load_stylesheet")
        if marker_start == -1:
            raise SystemExit(
                "Dock stylesheet load call not found."
            )

        block_start = text.rfind("        try {", 0, marker_start)
        block_end = text.find("\n        }", marker_start)

        if block_start == -1 or block_end == -1:
            raise SystemExit(
                "Dock stylesheet block could not be located."
            )

        block_end += len("\n        }")

        marker = text[block_start:block_end]

    listener = """

        this._interfaceSettings =
            Gio.Settings.new('org.gnome.desktop.interface');

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
# Replace _updateTheme() robustly
# --------------------------------------------------

start = text.find("    _updateTheme()")
if start == -1:
    raise SystemExit(
        "Dock _updateTheme() function not found."
    )

next_method = text.find(
    "\n    _",
    start + len("    _updateTheme()")
)

if next_method == -1:
    raise SystemExit(
        "Could not locate the method after Dock _updateTheme()."
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
    }
"""

text = (
    text[:start]
    + replacement
    + text[next_method + 1:]
)

# --------------------------------------------------
# Ensure listener is disconnected
# --------------------------------------------------

if "this._interfaceSettings.disconnect(" not in text:
    disable_start = text.find("    disable()")
    if disable_start == -1:
        raise SystemExit(
            "Dock disable() function not found."
        )

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

    text = (
        text[:disable_start]
        + disconnect
        + text[disable_start + len("    disable() {\n"):]
    )

# --------------------------------------------------
# Ensure initial theme update happens
# --------------------------------------------------

if "this._updateTheme();" not in text:
    marker = "this._colorSchemeChangedId ="
    pos = text.find(marker)

    if pos != -1:
        semicolon = text.find(");", pos)
        if semicolon != -1:
            semicolon += 2
            text = (
                text[:semicolon]
                + "\n\n        this._updateTheme();"
                + text[semicolon:]
            )

path.write_text(text, encoding="utf-8")
PY

echo "Dock patch complete."

echo
echo "=================================================="
echo " 3. Patching UI Test / Top Bar"
echo "=================================================="

python3 - "$UI_HOST" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")

# --------------------------------------------------
# Add GNOME color-scheme listener
# --------------------------------------------------

if "changed::color-scheme" not in text:
    marker = """        this._createLogo();
        this._createIcons();
"""

    if marker not in text:
        raise SystemExit(
            "UI Test createLogo/createIcons anchor not found."
        )

    listener = """
        this._interfaceSettings =
            Gio.Settings.new('org.gnome.desktop.interface');

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
# Replace _updateTheme()
# --------------------------------------------------

start = text.find("    _updateTheme()")
if start == -1:
    raise SystemExit(
        "UI Test _updateTheme() function not found."
    )

next_method = text.find(
    "\n    _",
    start + len("    _updateTheme()")
)

if next_method == -1:
    raise SystemExit(
        "Could not locate the method after UI Test _updateTheme()."
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
"""

text = (
    text[:start]
    + replacement
    + text[next_method + 1:]
)

# --------------------------------------------------
# Ensure disconnect
# --------------------------------------------------

if "this._interfaceSettings.disconnect(" not in text:
    disable_start = text.find("    disable()")

    if disable_start == -1:
        raise SystemExit(
            "UI Test disable() function not found."
        )

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

    text = (
        text[:disable_start]
        + disconnect
        + text[disable_start + len("    disable() {\n"):]
    )

path.write_text(text, encoding="utf-8")
PY

echo "UI Test / Top Bar patch complete."

echo
echo "=================================================="
echo " 4. Verify patched code"
echo "=================================================="

grep -n "changed::color-scheme" "$DOCK_HOST"
grep -n "changed::color-scheme" "$UI_HOST"

grep -n "get_string" "$DOCK_HOST" | grep color-scheme || true
grep -n "get_string" "$UI_HOST" | grep color-scheme || true

echo
echo "=================================================="
echo " 5. Synchronize HOST -> ROOTFS"
echo "=================================================="

sudo mkdir -p \
    "$ROOTFS_EXT/$DOCK" \
    "$ROOTFS_EXT/$UI"

sudo cp -f "$DOCK_HOST" "$DOCK_ROOT"
sudo cp -f "$UI_HOST" "$UI_ROOT"

sudo chown root:root \
    "$DOCK_ROOT" \
    "$UI_ROOT"

sudo chmod 644 \
    "$DOCK_ROOT" \
    "$UI_ROOT"

echo "Rootfs synchronized."

echo
echo "=================================================="
echo " 6. Restart active extensions"
echo "=================================================="

gnome-extensions disable "$DOCK" 2>/dev/null || true
gnome-extensions disable "$UI" 2>/dev/null || true

sleep 2

gnome-extensions enable "$DOCK"
gnome-extensions enable "$UI"

sleep 3

echo
echo "=================================================="
echo " 7. Verification"
echo "=================================================="

echo "Current color scheme:"
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
