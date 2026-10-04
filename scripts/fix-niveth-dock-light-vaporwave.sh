#!/usr/bin/env bash

set -euo pipefail

EXT="$HOME/.local/share/gnome-shell/extensions/niveth-dock@nivethos"
CSS="$EXT/stylesheet.css"

if [ ! -f "$CSS" ]; then
    echo "ERROR: Cannot find:"
    echo "$CSS"
    exit 1
fi

STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP="$CSS.backup-before-light-force-$STAMP"

echo
echo "=================================================="
echo " NIVETH DOCK — FORCE LIGHT VAPORWAVE"
echo "=================================================="
echo

echo "[1/6] Creating backup"
cp "$CSS" "$BACKUP"
echo "[PASS] Backup:"
echo "$BACKUP"

echo
echo "[2/6] Writing complete stylesheet"

cat > "$CSS" <<'CSS'
/* =========================================================
 * NIVETH DOCK
 * VAPORWAVE GLASS
 * ========================================================= */

.niveth-dock-area {
    background-color: transparent;
}


/* =========================================================
 * BASE
 * ========================================================= */

.niveth-dock {
    spacing: 5px;

    padding: 7px 11px;

    height: 66px;

    border-radius: 33px;

    border-width: 1px;
    border-style: solid;

    background-color: rgba(40, 36, 104, 0.94);

    border-color: rgba(105, 216, 255, 0.68);

    box-shadow:
        0 12px 30px rgba(5, 5, 25, 0.46),
        0 0 18px rgba(90, 155, 255, 0.30),
        0 0 32px rgba(197, 105, 255, 0.20);
}


/* =========================================================
 * DARK
 * ========================================================= */

.niveth-dock.niveth-dock.dark {
    background-color: rgba(40, 36, 104, 0.94);

    border-color: rgba(105, 216, 255, 0.72);

    box-shadow:
        0 12px 32px rgba(4, 4, 22, 0.52),
        0 0 19px rgba(82, 157, 255, 0.32),
        0 0 34px rgba(197, 104, 255, 0.23);
}


/* =========================================================
 * LIGHT
 *
 * Deliberately purple/indigo.
 * NOT white.
 * ========================================================= */

.niveth-dock.niveth-dock.light {
    background-color: rgba(73, 55, 137, 0.92);

    border-color: rgba(110, 219, 255, 0.78);

    box-shadow:
        0 11px 30px rgba(37, 24, 82, 0.28),
        0 0 18px rgba(90, 170, 255, 0.30),
        0 0 34px rgba(201, 105, 255, 0.22);
}


/* =========================================================
 * APP GRID
 * ========================================================= */

.niveth-dock-core-button {
    width: 52px;
    height: 52px;

    padding: 0;

    border-radius: 17px;

    background-color: rgba(67, 53, 130, 0.78);

    border-width: 1px;
    border-style: solid;

    border-color: rgba(105, 214, 255, 0.32);
}


.niveth-dock-core-button:hover {
    background-color: rgba(132, 82, 194, 0.42);

    border-color: rgba(108, 221, 255, 0.56);

    box-shadow:
        0 0 14px rgba(93, 178, 255, 0.32),
        0 0 23px rgba(199, 102, 255, 0.22);
}


.niveth-dock-core-button:active {
    background-color: rgba(180, 88, 215, 0.42);

    border-color: rgba(165, 231, 255, 0.60);
}


.niveth-dock-core-glyph {
    icon-size: 22px;

    -st-icon-shadow:
        0 0 6px rgba(105, 216, 255, 0.58),
        0 0 12px rgba(197, 123, 255, 0.42);
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
    background-color: rgba(122, 82, 192, 0.30);

    border-color: rgba(115, 218, 255, 0.40);

    box-shadow:
        0 0 14px rgba(94, 174, 255, 0.27),
        0 0 23px rgba(198, 104, 255, 0.18);
}


.niveth-dock-app-button:active,
.niveth-dock-folder-button:active {
    background-color: rgba(181, 88, 216, 0.30);

    border-color: rgba(164, 229, 255, 0.50);
}


/* =========================================================
 * ICONS
 * ========================================================= */

.niveth-dock-app-icon,
.niveth-dock-folder-icon {
    -st-icon-shadow:
        0 2px 6px rgba(0, 0, 0, 0.34),
        0 0 8px rgba(105, 190, 255, 0.20);
}


/* =========================================================
 * RUNNING INDICATOR
 * ========================================================= */

.niveth-dock-running-indicator {
    width: 8px;
    height: 3px;

    margin-top: 3px;

    border-radius: 99px;

    background-color: rgba(255, 114, 210, 0.99);

    box-shadow:
        0 0 5px rgba(255, 114, 210, 0.98),
        0 0 10px rgba(197, 123, 255, 0.90),
        0 0 18px rgba(105, 216, 255, 0.45);
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
    border-left-color: rgba(105, 211, 255, 0.32);
}


/* =========================================================
 * EDGE
 * ========================================================= */

.niveth-dock-edge-trigger {
    background-color: transparent;
}
CSS

echo "[PASS] Complete stylesheet written"

echo
echo "[3/6] Checking Light rule"

grep -A12 "^\.niveth-dock\.niveth-dock\.light" "$CSS"

echo
echo "[4/6] Checking that no white Light background remains"

if grep -q "247, 250, 252" "$CSS"; then
    echo "[FAIL] Old white Light palette still exists"
    exit 1
fi

if grep -q "225, 233, 245" "$CSS"; then
    echo "[FAIL] Old light-gray palette still exists"
    exit 1
fi

echo "[PASS] Old white/light-gray palette removed"

echo
echo "[5/6] Reloading Niveth Dock"

gnome-extensions disable niveth-dock@nivethos || true
sleep 1
gnome-extensions enable niveth-dock@nivethos
sleep 2

echo "[PASS] Dock reloaded"

echo
echo "[6/6] Current GNOME mode"

gsettings get org.gnome.desktop.interface color-scheme

echo
echo "=================================================="
echo " LIGHT VAPORWAVE DOCK READY"
echo "=================================================="
echo
echo "Expected:"
echo "  Indigo / violet glass"
echo "  Electric cyan border"
echo "  Violet glow"
echo "  Pink active indicator"
echo
echo "Backup:"
echo "$BACKUP"
echo
