#!/usr/bin/env bash

set -euo pipefail

EXT="$HOME/.local/share/gnome-shell/extensions/niveth-dock@nivethos"
JS="$EXT/extension.js"
CSS="$EXT/stylesheet.css"

if [ ! -f "$JS" ]; then
    echo "ERROR: $JS not found"
    exit 1
fi

if [ ! -f "$CSS" ]; then
    echo "ERROR: $CSS not found"
    exit 1
fi

STAMP="$(date +%Y%m%d-%H%M%S)"

cp "$JS" "$JS.backup-before-vaporwave-structure-$STAMP"
cp "$CSS" "$CSS.backup-before-vaporwave-structure-$STAMP"

echo "=== NIVETH VAPORWAVE DOCK ==="
echo

python3 - "$JS" <<'PY'
from pathlib import Path
import re
import sys

path = Path(sys.argv[1])
text = path.read_text()

# ---------------------------------------------------------
# 1. Smaller dock geometry
# ---------------------------------------------------------

old = "const CORE_SIZE = 76;"
new = "const CORE_SIZE = 52;"

if old not in text:
    raise SystemExit("ERROR: CORE_SIZE block not found")

text = text.replace(old, new, 1)

old = "const DOCK_HEIGHT = 84;"
new = "const DOCK_HEIGHT = 66;"

if old not in text:
    raise SystemExit("ERROR: DOCK_HEIGHT block not found")

text = text.replace(old, new, 1)


# ---------------------------------------------------------
# 2. Replace the old infinity core button with app grid
# ---------------------------------------------------------

pattern = re.compile(
    r"""        this\._coreButton = new St\.Button\(\{
.*?
        \}\);
        this\._coreButton\.set_size\(CORE_SIZE, CORE_SIZE\);
        this\._coreButton\.set_translation\(0, -10, 0\);
.*?
        this\._coreButton\.connect\('button-press-event', \(_actor, event\) => \{
.*?
        \}\);
""",
    re.S,
)

match = pattern.search(text)

if not match:
    raise SystemExit(
        "ERROR: Could not find the current core button block"
    )

replacement = """        this._coreButton = new St.Button({
            style_class: 'niveth-dock-core-button',
            reactive: true,
            can_focus: true,
            track_hover: true,
            child: new St.Icon({
                icon_name: 'view-app-grid-symbolic',
                icon_size: 22,
                style_class: 'niveth-dock-core-glyph',
            }),
        });

        this._coreButton.set_size(CORE_SIZE, CORE_SIZE);

        this._coreButton.connect(
            'clicked',
            () => Main.overview.toggle()
        );

        this._coreButton.connect(
            'captured-event',
            (_actor, event) => {
                if (
                    event.type() === Clutter.EventType.BUTTON_PRESS &&
                    event.get_button() === Clutter.BUTTON_SECONDARY
                ) {
                    this._openCoreMenu();
                    return Clutter.EVENT_STOP;
                }

                return Clutter.EVENT_PROPAGATE;
            }
        );

        this._coreButton.connect(
            'button-press-event',
            (_actor, event) => {
                if (event.get_button() === Clutter.BUTTON_SECONDARY) {
                    this._openCoreMenu();
                    return Clutter.EVENT_STOP;
                }

                return Clutter.EVENT_PROPAGATE;
            }
        );
"""

text = text[:match.start()] + replacement + text[match.end():]


# ---------------------------------------------------------
# 3. Put app grid FIRST instead of in the middle
# ---------------------------------------------------------

old = """        this._dock.add_child(this._leftBox);
        this._dock.add_child(this._coreButton);
        this._dock.add_child(this._rightBox);
        this._dock.add_child(this._folderBox);
"""

new = """        this._dock.add_child(this._coreButton);
        this._dock.add_child(this._leftBox);
        this._dock.add_child(this._rightBox);
        this._dock.add_child(this._folderBox);
"""

if old not in text:
    raise SystemExit(
        "ERROR: Current dock child order not found"
    )

text = text.replace(old, new, 1)

path.write_text(text)
PY

echo "[PASS] extension.js structure updated"


cat > "$CSS" <<'CSS'
/* =========================================================
 * NIVETH DOCK — VAPORWAVE GLASS
 * ========================================================= */

.niveth-dock-area {
    background-color: transparent;
}


/* =========================================================
 * MAIN GLASS CAPSULE
 * ========================================================= */

.niveth-dock {
    spacing: 5px;

    padding: 7px 11px;

    height: 66px;

    border-radius: 33px;

    border-width: 1px;
    border-style: solid;

    background-color: rgba(19, 26, 48, 0.76);

    border-color: rgba(154, 181, 235, 0.26);

    box-shadow:
        0 12px 34px rgba(5, 8, 20, 0.40),
        0 0 20px rgba(105, 95, 190, 0.10);
}


/* =========================================================
 * LIGHT MODE
 * ========================================================= */

.niveth-dock.light {
    background-color: rgba(225, 233, 245, 0.76);

    border-color: rgba(255, 255, 255, 0.55);

    box-shadow:
        0 12px 32px rgba(60, 70, 95, 0.16),
        0 0 20px rgba(150, 135, 230, 0.10);
}


/* =========================================================
 * DARK MODE
 * ========================================================= */

.niveth-dock.dark {
    background-color: rgba(18, 25, 46, 0.78);

    border-color: rgba(155, 180, 240, 0.28);

    box-shadow:
        0 12px 36px rgba(4, 7, 18, 0.46),
        0 0 22px rgba(130, 105, 230, 0.12);
}


/* =========================================================
 * APP GRID BUTTON
 * ========================================================= */

.niveth-dock-core-button {
    width: 52px;
    height: 52px;

    padding: 0;

    border-radius: 17px;

    background-color: transparent;

    border-width: 1px;
    border-style: solid;
    border-color: transparent;
}


.niveth-dock-core-button:hover {
    background-color: rgba(255, 255, 255, 0.09);

    border-color: rgba(190, 175, 250, 0.24);

    box-shadow:
        0 0 14px rgba(165, 125, 235, 0.18);
}


.niveth-dock-core-glyph {
    icon-size: 22px;

    -st-icon-shadow:
        0 1px 4px rgba(0, 0, 0, 0.25),
        0 0 8px rgba(150, 145, 240, 0.18);
}


/* =========================================================
 * APP BUTTONS
 * ========================================================= */

.niveth-dock-app-button,
.niveth-dock-folder-button {

    width: 52px;
    height: 52px;

    padding: 6px;

    border-radius: 17px;

    background-color: transparent;

    border-width: 1px;
    border-style: solid;
    border-color: transparent;
}


.niveth-dock-app-button:hover,
.niveth-dock-folder-button:hover {

    background-color: rgba(255, 255, 255, 0.085);

    border-color: rgba(195, 180, 245, 0.22);

    box-shadow:
        0 0 13px rgba(175, 125, 235, 0.17);
}


.niveth-dock-app-button:active,
.niveth-dock-folder-button:active {

    background-color: rgba(255, 255, 255, 0.13);
}


/* =========================================================
 * ICONS
 * ========================================================= */

.niveth-dock-app-icon,
.niveth-dock-folder-icon {

    -st-icon-shadow:
        0 2px 7px rgba(0, 0, 0, 0.28),
        0 0 7px rgba(160, 145, 235, 0.14);
}


/* =========================================================
 * RUNNING INDICATOR
 * ========================================================= */

.niveth-dock-running-indicator {

    width: 7px;
    height: 3px;

    margin-top: 3px;

    border-radius: 99px;

    background-color: rgba(208, 182, 255, 0.95);

    box-shadow:
        0 0 7px rgba(210, 165, 255, 0.75),
        0 0 13px rgba(145, 120, 245, 0.42);
}


/* =========================================================
 * FAVORITE / RUNNING APPS
 * ========================================================= */

.niveth-dock-apps {
    spacing: 3px;
}


/* =========================================================
 * FOLDERS / SEPARATOR
 * ========================================================= */

.niveth-dock-folders {

    spacing: 3px;

    margin-left: 7px;

    padding-left: 9px;

    border-left-width: 1px;
    border-left-style: solid;
    border-left-color: rgba(190, 180, 230, 0.23);
}


/* =========================================================
 * EDGE TRIGGER
 * ========================================================= */

.niveth-dock-edge-trigger {
    background-color: transparent;
}
CSS

echo "[PASS] stylesheet.css replaced"

echo
echo "[3] Verify JavaScript text"

grep -nE \
    "CORE_SIZE|DOCK_HEIGHT|view-app-grid-symbolic|_dock.add_child" \
    "$JS" \
    | head -40

echo
echo "[4] Verify old infinity core is gone"

if grep -q "text: '∞'" "$JS"; then
    echo "[FAIL] Old infinity button still present"
    exit 1
else
    echo "[PASS] Infinity core removed"
fi

echo
echo "[5] Reload extension"

gnome-extensions disable niveth-dock@nivethos || true
sleep 1
gnome-extensions enable niveth-dock@nivethos

echo
echo "=== DONE ==="
echo
echo "Backup:"
echo "$JS.backup-before-vaporwave-structure-$STAMP"
echo "$CSS.backup-before-vaporwave-structure-$STAMP"
