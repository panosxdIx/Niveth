#!/usr/bin/env bash

set -u

DOCK="niveth-dock@nivethos"
UI="niveth-ui-test@nivethos"

DOCK_HOST="$HOME/.local/share/gnome-shell/extensions/$DOCK/extension.js"
UI_HOST="$HOME/.local/share/gnome-shell/extensions/$UI/extension.js"

STAMP="$(date +%Y%m%d-%H%M%S)"

BACKUP_DIR="$HOME/Niveth/integration-backups/theme-callback-diagnostic-$STAMP"

echo "=================================================="
echo " Niveth Theme Callback Diagnostic"
echo "=================================================="
echo

mkdir -p "$BACKUP_DIR"

cp -f \
    "$DOCK_HOST" \
    "$BACKUP_DIR/niveth-dock-extension.js"

cp -f \
    "$UI_HOST" \
    "$BACKUP_DIR/niveth-ui-test-extension.js"

echo "Backup:"
echo "  $BACKUP_DIR"

echo
echo "=================================================="
echo " 1. Insert temporary diagnostics"
echo "=================================================="

python3 - "$DOCK_HOST" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")

marker = "NIVETH_THEME_DIAG_DOCK"

if marker in text:
    raise SystemExit(
        "Dock diagnostic already present."
    )

old = "() => this._updateTheme()"

new = """() => {
                    log('NIVETH_THEME_DIAG_DOCK_SIGNAL');
                    this._updateTheme();
                }"""

if old not in text:
    raise SystemExit(
        "Dock theme callback not found."
    )

text = text.replace(
    old,
    new,
    1
)

old2 = """    _updateTheme() {
        if (!this._dock)
            return;
"""

new2 = """    _updateTheme() {
        if (!this._dock)
            return;

        log(
            'NIVETH_THEME_DIAG_DOCK_UPDATE'
        );
"""

if old2 not in text:
    raise SystemExit(
        "Dock _updateTheme() body not found."
    )

text = text.replace(
    old2,
    new2,
    1
)

old3 = """        const dark =
            scheme === 'prefer-dark';
"""

new3 = """        const dark =
            scheme === 'prefer-dark';

        log(
            'NIVETH_THEME_DIAG_DOCK_SCHEME='
            + scheme
            + ' dark='
            + dark
        );
"""

if old3 not in text:
    raise SystemExit(
        "Dock scheme section not found."
    )

text = text.replace(
    old3,
    new3,
    1
)

path.write_text(
    text,
    encoding="utf-8"
)
PY

python3 - "$UI_HOST" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")

marker = "NIVETH_THEME_DIAG_UI"

if marker in text:
    raise SystemExit(
        "UI diagnostic already present."
    )

old = "() => this._updateTheme()"

new = """() => {
                    log('NIVETH_THEME_DIAG_UI_SIGNAL');
                    this._updateTheme();
                }"""

if old not in text:
    raise SystemExit(
        "UI Test theme callback not found."
    )

text = text.replace(
    old,
    new,
    1
)

old2 = """    _updateTheme() {
        if (!this._bar)
            return;
"""

new2 = """    _updateTheme() {
        if (!this._bar)
            return;

        log(
            'NIVETH_THEME_DIAG_UI_UPDATE'
        );
"""

if old2 not in text:
    raise SystemExit(
        "UI Test _updateTheme() body not found."
    )

text = text.replace(
    old2,
    new2,
    1
)

old3 = """        const dark =
            scheme === 'prefer-dark';
"""

new3 = """        const dark =
            scheme === 'prefer-dark';

        log(
            'NIVETH_THEME_DIAG_UI_SCHEME='
            + scheme
            + ' dark='
            + dark
        );
"""

if old3 not in text:
    raise SystemExit(
        "UI Test scheme section not found."
    )

text = text.replace(
    old3,
    new3,
    1
)

path.write_text(
    text,
    encoding="utf-8"
)
PY

echo "Temporary diagnostics inserted."

echo
echo "=================================================="
echo " 2. Restart extensions"
echo "=================================================="

gnome-extensions disable "$DOCK" 2>/dev/null || true
gnome-extensions disable "$UI" 2>/dev/null || true

sleep 2

gnome-extensions enable "$DOCK"
gnome-extensions enable "$UI"

sleep 3

echo "Extensions restarted."

echo
echo "=================================================="
echo " 3. Automatic dark/light test"
echo "=================================================="

echo "Setting prefer-light..."
gsettings set \
    org.gnome.desktop.interface \
    color-scheme \
    'prefer-light'

sleep 2

echo "Setting prefer-dark..."
gsettings set \
    org.gnome.desktop.interface \
    color-scheme \
    'prefer-dark'

sleep 3

echo "Setting prefer-light..."
gsettings set \
    org.gnome.desktop.interface \
    color-scheme \
    'prefer-light'

sleep 3

echo
echo "Current scheme:"
gsettings get \
    org.gnome.desktop.interface \
    color-scheme

echo
echo "=================================================="
echo " 4. Relevant GNOME Shell log"
echo "=================================================="

journalctl \
    --user \
    --since "90 seconds ago" \
    --no-pager \
    -o cat 2>/dev/null |
    grep -Ei \
        "NIVETH_THEME_DIAG|Argument file may not be null|g_object_ref|JS ERROR|TypeError|ReferenceError|NIVETH: Top Bar|NIVETH LOCK SCREEN" |
    tail -n 200 || true

echo
echo "=================================================="
echo " 5. Restore original files"
echo "=================================================="

cp -f \
    "$BACKUP_DIR/niveth-dock-extension.js" \
    "$DOCK_HOST"

cp -f \
    "$BACKUP_DIR/niveth-ui-test-extension.js" \
    "$UI_HOST"

echo "Original HOST files restored."

echo
echo "=================================================="
echo " 6. Restart extensions with original code"
echo "=================================================="

gnome-extensions disable "$DOCK" 2>/dev/null || true
gnome-extensions disable "$UI" 2>/dev/null || true

sleep 2

gnome-extensions enable "$DOCK"
gnome-extensions enable "$UI"

sleep 3

gsettings set \
    org.gnome.desktop.interface \
    color-scheme \
    'prefer-light'

echo
echo "=================================================="
echo " DIAGNOSTIC COMPLETE"
echo "=================================================="

echo
echo "Backup kept at:"
echo "$BACKUP_DIR"
