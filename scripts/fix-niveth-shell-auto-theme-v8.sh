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
BACKUP_DIR="$PROJECT_ROOT/integration-backups/shell-auto-theme-v8-$STAMP"

echo "=================================================="
echo " Niveth Shell Automatic Light/Dark Theme Fix v8"
echo "=================================================="
echo

if [ ! -f "$DOCK_HOST" ]; then
    echo "ERROR: Dock extension not found."
    exit 1
fi

if [ ! -f "$UI_HOST" ]; then
    echo "ERROR: UI Test extension not found."
    exit 1
fi

if [ ! -d "$ROOTFS" ]; then
    echo "ERROR: Rootfs not found."
    exit 1
fi

mkdir -p "$BACKUP_DIR"

echo "=== 1. Backup current HOST extensions ==="

cp -a "$DOCK_HOST" \
    "$BACKUP_DIR/niveth-dock-extension.js"

cp -a "$UI_HOST" \
    "$BACKUP_DIR/niveth-ui-test-extension.js"

echo "Backup:"
echo "  $BACKUP_DIR"

echo
echo "=================================================="
echo " 2. Patch Dock"
echo "=================================================="

python3 - "$DOCK_HOST" <<'PY'
from pathlib import Path
import sys
import re

path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")

# --------------------------------------------------
# Remove previous theme-listener declarations
# --------------------------------------------------

patterns = [
    r"""
        \n\s*this\._nivethThemeSettings\s*=
        \s*Gio\.Settings\.new\(
        \s*'org\.gnome\.desktop\.interface'
        \s*\);
    """,
    r"""
        \n\s*this\._nivethPollingThemeSettings\s*=
        \s*Gio\.Settings\.new\(
        \s*'org\.gnome\.desktop\.interface'
        \s*\);
    """,
]

for pattern in patterns:
    text = re.sub(
        pattern,
        "",
        text,
        flags=re.VERBOSE,
    )

# Remove previous color-scheme connect blocks.
text = re.sub(
    r"""
        \n\s*this\._nivethThemeChangedId\s*=
        \s*this\._nivethThemeSettings\.connect\(
        .*?
        \n\s*\);
    """,
    "",
    text,
    flags=re.VERBOSE | re.DOTALL,
)

text = re.sub(
    r"""
        \n\s*this\._colorSchemeChangedId\s*=
        \s*this\._interfaceSettings\.connect\(
        .*?
        \n\s*\);
    """,
    "",
    text,
    flags=re.VERBOSE | re.DOTALL,
)

text = re.sub(
    r"""
        \n\s*this\._nivethThemeChangedId\s*=
        \s*this\._nivethThemeSettings\.connect\(
        .*?
        \n\s*\);
    """,
    "",
    text,
    flags=re.VERBOSE | re.DOTALL,
)

text = re.sub(
    r"""
        \n\s*this\._nivethPollingThemeTimerId\s*=
        \s*GLib\.timeout_add_seconds\(
        .*?
        \n\s*\);
    """,
    "",
    text,
    flags=re.VERBOSE | re.DOTALL,
)

# Remove old theme disconnect blocks.
text = re.sub(
    r"""
        \n\s*if\s*\(\s*this\._nivethThemeChangedId\s*\)\s*\{
        .*?
        \n\s*\}
    """,
    "",
    text,
    flags=re.VERBOSE | re.DOTALL,
)

text = re.sub(
    r"""
        \n\s*if\s*\(\s*this\._colorSchemeChangedId\s*\)\s*\{
        .*?
        \n\s*\}
    """,
    "",
    text,
    flags=re.VERBOSE | re.DOTALL,
)

# --------------------------------------------------
# Replace _updateTheme()
# --------------------------------------------------

start = text.find("\n    _updateTheme() {")

if start == -1:
    raise SystemExit(
        "Dock _updateTheme() not found."
    )

end = text.find(
    "\n    _loadFolders() {",
    start
)

if end == -1:
    raise SystemExit(
        "Dock _loadFolders() not found."
    )

replacement = """
    _updateTheme() {
        if (!this._dock)
            return;

        let output = '';

        try {
            const [ok, stdout] =
                GLib.spawn_command_line_sync(
                    'gsettings get org.gnome.desktop.interface color-scheme'
                );

            if (ok && stdout) {
                output =
                    new TextDecoder()
                        .decode(stdout)
                        .trim();
            }
        } catch (error) {
            output = '';
        }

        const dark =
            output.includes('prefer-dark');

        this._dock.remove_style_class_name(
            'dark'
        );

        this._dock.remove_style_class_name(
            'light'
        );

        this._dock.add_style_class_name(
            dark ? 'dark' : 'light'
        );

        this._dock.set_style(
            dark
                ? 'background-color: rgba(24, 37, 50, 0.84); border: 1px solid rgba(150, 175, 205, 0.13); box-shadow: 0 10px 36px rgba(0,0,0,0.32), 0 2px 12px rgba(0,0,0,0.10);'
                : 'background-color: rgba(247, 250, 252, 0.84); border: 1px solid rgba(255,255,255,0.72); box-shadow: 0 10px 36px rgba(23,44,63,0.20), 0 2px 12px rgba(255,255,255,0.18);'
        );

        if (this._coreButton) {
            this._coreButton.set_style(
                dark
                    ? 'background-color: rgba(34, 52, 70, 0.92);'
                    : 'background-color: rgba(255, 255, 255, 0.82);'
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
# Add updateTheme() to the existing 1-second refresh
# --------------------------------------------------

old_timer = """            () => {
                this._refreshRunningState();
                this._position();
                return GLib.SOURCE_CONTINUE;
            }
"""

if old_timer in text:

    new_timer = """            () => {
                this._refreshRunningState();
                this._updateTheme();
                this._position();
                return GLib.SOURCE_CONTINUE;
            }
"""

    text = text.replace(
        old_timer,
        new_timer,
        1
    )

else:
    print(
        "WARNING: Dock 1-second refresh callback anchor not found."
    )

# Initial update.
if "this._updateTheme();" not in text:
    marker = "this._dock.show();"

    pos = text.find(marker)

    if pos != -1:
        end = pos + len(marker)

        text = (
            text[:end]
            + "\n        this._updateTheme();"
            + text[end:]
        )

required = [
    "_updateTheme() {",
    "gsettings get org.gnome.desktop.interface color-scheme",
    "this._dock.set_style(",
    "this._coreButton.set_style(",
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

print("Dock v8 patch complete.")
PY

echo
echo "=================================================="
echo " 3. Patch Top Bar"
echo "=================================================="

python3 - "$UI_HOST" <<'PY'
from pathlib import Path
import sys
import re

path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")

# --------------------------------------------------
# Remove previous color-scheme listener objects
# --------------------------------------------------

text = re.sub(
    r"""
        \n\s*this\._nivethThemeSettings\s*=
        \s*Gio\.Settings\.new\(
        \s*'org\.gnome\.desktop\.interface'
        \s*\);
    """,
    "",
    text,
    flags=re.VERBOSE,
)

text = re.sub(
    r"""
        \n\s*this\._interfaceSettings\s*=
        \s*Gio\.Settings\.new\(
        \s*'org\.gnome\.desktop\.interface'
        \s*\);
    """,
    "",
    text,
    flags=re.VERBOSE,
)

# Remove signal connect blocks.
text = re.sub(
    r"""
        \n\s*this\._nivethThemeChangedId\s*=
        \s*this\._nivethThemeSettings\.connect\(
        .*?
        \n\s*\);
    """,
    "",
    text,
    flags=re.VERBOSE | re.DOTALL,
)

text = re.sub(
    r"""
        \n\s*this\._colorSchemeChangedId\s*=
        \s*this\._interfaceSettings\.connect\(
        .*?
        \n\s*\);
    """,
    "",
    text,
    flags=re.VERBOSE | re.DOTALL,
)

# Remove old disconnect blocks.
text = re.sub(
    r"""
        \n\s*if\s*\(\s*this\._nivethThemeChangedId\s*\)\s*\{
        .*?
        \n\s*\}
    """,
    "",
    text,
    flags=re.VERBOSE | re.DOTALL,
)

text = re.sub(
    r"""
        \n\s*if\s*\(\s*this\._colorSchemeChangedId\s*\)\s*\{
        .*?
        \n\s*\}
    """,
    "",
    text,
    flags=re.VERBOSE | re.DOTALL,
)

# --------------------------------------------------
# Replace entire _updateTheme()
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

        let output = '';

        try {
            const [ok, stdout] =
                GLib.spawn_command_line_sync(
                    'gsettings get org.gnome.desktop.interface color-scheme'
                );

            if (ok && stdout) {
                output =
                    new TextDecoder()
                        .decode(stdout)
                        .trim();
            }
        } catch (error) {
            output = '';
        }

        const dark =
            output.includes('prefer-dark');

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

        this._bar.set_style(
            dark
                ? 'background-color: rgba(24, 36, 55, 0.84); border: 1px solid rgba(150, 175, 205, 0.13); color: #DCE7F4; box-shadow: 0 10px 36px rgba(0,0,0,0.30);'
                : 'background-color: rgba(247, 249, 252, 0.84); border: 1px solid rgba(255,255,255,0.72); color: #29415D; box-shadow: 0 10px 36px rgba(73,103,131,0.18);'
        );

        if (this._clock) {
            this._clock.set_style(
                dark
                    ? 'color: #DCE7F4;'
                    : 'color: #29415D;'
            );
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
# Existing 1-second clock timer also updates theme
# --------------------------------------------------

old_timer = """            () => {
                this._updateClock();
                return GLib.SOURCE_CONTINUE;
            }
"""

new_timer = """            () => {
                this._updateClock();
                this._updateTheme();
                return GLib.SOURCE_CONTINUE;
            }
"""

if old_timer not in text:
    raise SystemExit(
        "Top Bar 1-second clock timer not found."
    )

text = text.replace(
    old_timer,
    new_timer,
    1
)

required = [
    "_updateTheme() {",
    "gsettings get org.gnome.desktop.interface color-scheme",
    "this._bar.set_style(",
    "this._clock.set_style(",
]

for item in required:
    if item not in text:
        raise SystemExit(
            f"Top Bar validation failed: {item}"
        )

path.write_text(
    text,
    encoding="utf-8"
)

print("Top Bar v8 patch complete.")
PY

echo
echo "=================================================="
echo " 4. Basic source validation"
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
            f"Brace mismatch: {filename}"
        )

    if text.count("(") != text.count(")"):
        raise SystemExit(
            f"Parenthesis mismatch: {filename}"
        )

print("Basic structure validation: OK")
PY

echo
echo "=================================================="
echo " 5. Verify V8"
echo "=================================================="

echo "--- Dock ---"

grep -nE \
    "gsettings get|_updateTheme|set_style|_refreshRunningState" \
    "$DOCK_HOST"

echo
echo "--- Top Bar ---"

grep -nE \
    "gsettings get|_updateTheme|set_style|_updateClock" \
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
echo " 8. Final status"
echo "=================================================="

gsettings get \
    org.gnome.desktop.interface \
    color-scheme

echo

gnome-extensions info "$DOCK" 2>/dev/null | \
    grep -E 'Name|Enabled|State' || true

echo

gnome-extensions info "$UI" 2>/dev/null | \
    grep -E 'Name|Enabled|State' || true

echo
echo "=================================================="
echo " COMPLETE"
echo "=================================================="
