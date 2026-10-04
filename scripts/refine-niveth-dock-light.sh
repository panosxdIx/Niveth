#!/usr/bin/env bash

set -euo pipefail

EXT="$HOME/.local/share/gnome-shell/extensions/niveth-dock@nivethos"
CSS="$EXT/stylesheet.css"

if [ ! -f "$CSS" ]; then
    echo "ERROR: stylesheet.css not found:"
    echo "$CSS"
    exit 1
fi

STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP="$CSS.backup-before-light-vaporwave-$STAMP"

echo
echo "=================================================="
echo " NIVETH DOCK — REFINED LIGHT VAPORWAVE"
echo "=================================================="
echo

echo "[1/5] Creating backup"
cp "$CSS" "$BACKUP"
echo "[PASS] $BACKUP"

echo
echo "[2/5] Writing complete stylesheet"

cat > "$CSS" <<'CSS'
/* =========================================================
 * NIVETH DOCK
 * Vaporwave Glass — Refined Light + Dark
 * ========================================================= */


/* =========================================================
 * AREA
 * ========================================================= */

.niveth-dock-area {
    background-color: transparent;
}


/* =========================================================
 * BASE DOCK
 * ========================================================= */

.niveth-dock {
    spacing: 5px;

    padding: 7px 11px;

    height: 66px;

    border-radius: 33px;

    border-width: 1px;
    border-style: solid;

    background-color: rgba(40, 36, 104, 0.94);

    border-color: rgba(105, 216, 255, 0.64);

    box-shadow:
        0 12px 30px rgba(5, 5, 25, 0.46),
        0 0 17px rgba(90, 155, 255, 0.28),
        0 0 30px rgba(197, 105, 255, 0.18);
}


/* =========================================================
 * DARK
 * ========================================================= */

.niveth-dock.dark {
    background-color: rgba(40, 36, 104, 0.94);

    border-color: rgba(105, 216, 255, 0.70);

    box-shadow:
        0 12px 32px rgba(4, 4, 22, 0.52),
        0 0 19px rgba(82, 157, 255, 0.30),
        0 0 34px rgba(197, 104, 255, 0.22);
}


/* =========================================================
 * LIGHT
 *
 * Still purple/indigo.
 * NOT white.
 * ========================================================= */

.niveth-dock.light {
    background-color: rgba(57, 48, 116, 0.92);

    border-color: rgba(118, 218, 255, 0.72);

    box-shadow:
        0 10px 28px rgba(35, 25, 80, 0.25),
        0 0 17px rgba(105, 178, 255, 0.27),
        0 0 30px rgba(205, 110, 255, 0.18);
}


/* =========================================================
 * APP GRID
 * ========================================================= */

.niveth-dock-core-button {
    width: 52px;
    height: 52px;

    padding: 0;

    border-radius: 17px;

    background-color: rgba(74, 61, 138, 0.68);

    border-width: 1px;
    border-style: solid;

    border-color: rgba(105, 210, 255, 0.25);
}


.niveth-dock-core-button:hover {
    background-color: rgba(125, 82, 185, 0.38);

    border-color: rgba(110, 220, 255, 0.50);

    box-shadow:
        0 0 13px rgba(92, 177, 255, 0.30),
        0 0 23px rgba(197, 100, 255, 0.20);
}


.niveth-dock-core-button:active {
    background-color: rgba(175, 88, 214, 0.38);

    border-color: rgba(160, 228, 255, 0.58);
}


.niveth-dock-core-glyph {
    icon-size: 22px;

    -st-icon-shadow:
        0 0 5px rgba(105, 216, 255, 0.55),
        0 0 10px rgba(197, 123, 255, 0.40);
}


/* =========================================================
 * APPLICATION BUTTONS
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
    background-color: rgba(120, 86, 190, 0.30);

    border-color: rgba(120, 218, 255, 0.40);

    box-shadow:
        0 0 13px rgba(95, 175, 255, 0.25),
        0 0 22px rgba(197, 105, 255, 0.17);
}


.niveth-dock-app-button:active,
.niveth-dock-folder-button:active {
    background-color: rgba(180, 88, 214, 0.30);

    border-color: rgba(165, 230, 255, 0.48);
}


/* =========================================================
 * ICONS
 * ========================================================= */

.niveth-dock-app-icon,
.niveth-dock-folder-icon {
    -st-icon-shadow:
        0 2px 6px rgba(0, 0, 0, 0.34),
        0 0 7px rgba(110, 190, 255, 0.18);
}


/* =========================================================
 * RUNNING INDICATOR
 * ========================================================= */

.niveth-dock-running-indicator {
    width: 8px;
    height: 3px;

    margin-top: 3px;

    border-radius: 99px;

    background-color: rgba(255, 114, 210, 0.98);

    box-shadow:
        0 0 5px rgba(255, 114, 210, 0.95),
        0 0 10px rgba(197, 123, 255, 0.90),
        0 0 17px rgba(105, 216, 255, 0.42);
}


/* =========================================================
 * APP GROUPS
 * ========================================================= */

.niveth-dock-apps {
    spacing: 3px;
}


/* =========================================================
 * FOLDERS
 * ========================================================= */

.niveth-dock-folders {
    spacing: 3px;

    margin-left: 7px;

    padding-left: 9px;

    border-left-width: 1px;
    border-left-style: solid;

    border-left-color: rgba(105, 210, 255, 0.30);
}


/* =========================================================
 * EDGE TRIGGER
 * ========================================================= */

.niveth-dock-edge-trigger {
    background-color: transparent;
}
CSS

echo "[PASS] Complete stylesheet written"

echo
echo "[3/5] Verifying Light palette"

grep -q "rgba(57, 48, 116, 0.92)" "$CSS"
grep -q "rgba(118, 218, 255, 0.72)" "$CSS"
grep -q "rgba(255, 114, 210, 0.98)" "$CSS"

echo "[PASS] Indigo Light background"
echo "[PASS] Cyan border"
echo "[PASS] Pink running indicator"

echo
echo "[4/5] Reloading Niveth Dock"

gnome-extensions disable niveth-dock@nivethos || true
sleep 1
gnome-extensions enable niveth-dock@nivethos
sleep 2

echo "[PASS] Dock reloaded"

echo
echo "[5/5] Final mode"

echo "GNOME color scheme:"
gsettings get org.gnome.desktop.interface color-scheme

echo
echo "Light Dock rule:"
grep -n -A8 "^\.niveth-dock\.light" "$CSS"

echo
echo "=================================================="
echo " LIGHT VAPORWAVE TEST READY"
echo "=================================================="
echo
echo "Backup:"
echo "$BACKUP"
echo
