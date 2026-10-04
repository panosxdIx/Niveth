#!/usr/bin/env bash

set -euo pipefail

EXT="$HOME/.local/share/gnome-shell/extensions/niveth-dock@nivethos"
JS="$EXT/extension.js"
CSS="$EXT/stylesheet.css"

ROOTFS="$HOME/Niveth/build/rootfs"
ROOTFS_EXT="$ROOTFS/usr/share/gnome-shell/extensions/niveth-dock@nivethos"
ROOTFS_JS="$ROOTFS_EXT/extension.js"
ROOTFS_CSS="$ROOTFS_EXT/stylesheet.css"

STAMP="$(date +%Y%m%d-%H%M%S)"

if [ ! -f "$JS" ]; then
    echo "ERROR: extension.js not found:"
    echo "$JS"
    exit 1
fi

if [ ! -f "$CSS" ]; then
    echo "ERROR: stylesheet.css not found:"
    echo "$CSS"
    exit 1
fi

echo
echo "=================================================="
echo " NIVETH DOCK — FINAL DARK VAPORWAVE TUNING"
echo "=================================================="
echo

# ---------------------------------------------------------
# Backups
# ---------------------------------------------------------

echo "[1/7] Creating backups"

JS_BACKUP="$JS.backup-before-final-dark-$STAMP"
CSS_BACKUP="$CSS.backup-before-final-dark-$STAMP"

cp "$JS" "$JS_BACKUP"
cp "$CSS" "$CSS_BACKUP"

echo "[PASS] JS backup:"
echo "       $JS_BACKUP"

echo "[PASS] CSS backup:"
echo "       $CSS_BACKUP"


# ---------------------------------------------------------
# Patch JavaScript actor styling
# ---------------------------------------------------------

echo
echo "[2/7] Refining direct Dock actor colors"

python3 - "$JS" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")

old_dark = (
    "'background-color: rgba(40, 36, 104, 0.94);' +"
    "'border: 1px solid rgba(105, 216, 255, 0.72);' +"
    "'border-radius: 33px;' +"
    "'box-shadow:'"
)

new_dark = (
    "'background-color: rgba(38, 33, 91, 0.84);' +"
    "'border: 1px solid rgba(105, 216, 255, 0.74);' +"
    "'border-radius: 33px;' +"
    "'box-shadow:'"
)

if old_dark not in text:
    raise SystemExit(
        "ERROR: Expected dark Dock style block was not found."
    )

text = text.replace(old_dark, new_dark, 1)

old_dark_shadow = (
    "'0 12px 32px rgba(4, 4, 22, 0.52),'"
    "'0 0 19px rgba(82, 157, 255, 0.32),'"
    "'0 0 34px rgba(197, 104, 255, 0.23);'"
)

new_dark_shadow = (
    "'0 12px 32px rgba(4, 4, 22, 0.46),'"
    "'0 0 18px rgba(88, 165, 255, 0.28),'"
    "'0 0 30px rgba(197, 104, 255, 0.18);'"
)

if old_dark_shadow not in text:
    raise SystemExit(
        "ERROR: Expected dark Dock shadow block was not found."
    )

text = text.replace(old_dark_shadow, new_dark_shadow, 1)

path.write_text(text, encoding="utf-8")
PY

echo "[PASS] Dark JavaScript colors refined"


# ---------------------------------------------------------
# Replace complete CSS with final vaporwave version
# ---------------------------------------------------------

echo
echo "[3/7] Writing complete final stylesheet"

cat > "$CSS" <<'CSS'
/* =========================================================
 * NIVETH DOCK
 * FINAL VAPORWAVE GLASS
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

    background-color: rgba(38, 33, 91, 0.84);

    border-color: rgba(105, 216, 255, 0.74);

    box-shadow:
        0 12px 32px rgba(4, 4, 22, 0.46),
        0 0 18px rgba(88, 165, 255, 0.28),
        0 0 30px rgba(197, 104, 255, 0.18);
}


/* =========================================================
 * DARK — FINAL MOCKUP PALETTE
 * ========================================================= */

.niveth-dock.dark {
    background-color: rgba(38, 33, 91, 0.84);

    border-color: rgba(105, 216, 255, 0.74);

    box-shadow:
        0 12px 32px rgba(4, 4, 22, 0.46),
        0 0 18px rgba(88, 165, 255, 0.28),
        0 0 30px rgba(197, 104, 255, 0.18);
}


/* =========================================================
 * LIGHT
 * ========================================================= */

.niveth-dock.light {
    background-color: rgba(65, 49, 132, 0.94);

    border-color: rgba(105, 216, 255, 0.78);

    box-shadow:
        0 11px 30px rgba(37, 24, 82, 0.30),
        0 0 18px rgba(90, 170, 255, 0.32),
        0 0 34px rgba(201, 105, 255, 0.24);
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

    border-color: rgba(105, 214, 255, 0.34);
}


.niveth-dock-core-button:hover {
    background-color: rgba(125, 82, 194, 0.40);

    border-color: rgba(108, 221, 255, 0.52);

    box-shadow:
        0 0 14px rgba(93, 178, 255, 0.30),
        0 0 23px rgba(199, 102, 255, 0.20);
}


.niveth-dock-core-button:active {
    background-color: rgba(180, 88, 215, 0.40);

    border-color: rgba(165, 231, 255, 0.58);
}


.niveth-dock-core-glyph {
    icon-size: 22px;

    -st-icon-shadow:
        0 0 6px rgba(105, 216, 255, 0.55),
        0 0 11px rgba(197, 123, 255, 0.36);
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
    background-color: rgba(122, 82, 192, 0.26);

    border-color: rgba(115, 218, 255, 0.38);

    box-shadow:
        0 0 13px rgba(94, 174, 255, 0.24),
        0 0 22px rgba(198, 104, 255, 0.15);
}


.niveth-dock-app-button:active,
.niveth-dock-folder-button:active {
    background-color: rgba(181, 88, 216, 0.28);

    border-color: rgba(164, 229, 255, 0.48);
}


/* =========================================================
 * ICONS
 * ========================================================= */

.niveth-dock-app-icon,
.niveth-dock-folder-icon {
    -st-icon-shadow:
        0 2px 6px rgba(0, 0, 0, 0.34),
        0 0 8px rgba(105, 190, 255, 0.18);
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
        0 0 10px rgba(197, 123, 255, 0.86),
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
    border-left-color: rgba(105, 211, 255, 0.30);
}


/* =========================================================
 * EDGE TRIGGER
 * ========================================================= */

.niveth-dock-edge-trigger {
    background-color: transparent;
}
CSS

echo "[PASS] Final stylesheet written"


# ---------------------------------------------------------
# Verification
# ---------------------------------------------------------

echo
echo "[4/7] Verifying final palette"

grep -q "rgba(38, 33, 91, 0.84)" "$JS"
grep -q "rgba(38, 33, 91, 0.84)" "$CSS"
grep -q "rgba(105, 216, 255, 0.74)" "$JS"
grep -q "rgba(255, 114, 210, 0.98)" "$CSS"

echo "[PASS] Dark indigo"
echo "[PASS] Cyan edge"
echo "[PASS] Pink indicator"


# ---------------------------------------------------------
# Sync rootfs
# ---------------------------------------------------------

echo
echo "[5/7] Syncing source into Niveth rootfs"

if [ -d "$ROOTFS_EXT" ]; then

    ROOTFS_JS_BACKUP="$ROOTFS_JS.backup-before-final-dark-$STAMP"
    ROOTFS_CSS_BACKUP="$ROOTFS_CSS.backup-before-final-dark-$STAMP"

    if [ -f "$ROOTFS_JS" ]; then
        sudo cp "$ROOTFS_JS" "$ROOTFS_JS_BACKUP"
        echo "[PASS] Rootfs JS backup"
    fi

    if [ -f "$ROOTFS_CSS" ]; then
        sudo cp "$ROOTFS_CSS" "$ROOTFS_CSS_BACKUP"
        echo "[PASS] Rootfs CSS backup"
    fi

    sudo install -m 0644 "$JS" "$ROOTFS_JS"
    sudo install -m 0644 "$CSS" "$ROOTFS_CSS"

    echo "[PASS] Rootfs JS updated"
    echo "[PASS] Rootfs CSS updated"

else
    echo "[INFO] Rootfs Dock extension not found."
    echo "[INFO] Live installation only."
fi


# ---------------------------------------------------------
# Reload
# ---------------------------------------------------------

echo
echo "[6/7] Reloading Niveth Dock"

gnome-extensions disable niveth-dock@nivethos || true

sleep 2

gnome-extensions enable niveth-dock@nivethos

sleep 3

echo "[PASS] Dock reloaded"


# ---------------------------------------------------------
# Final status
# ---------------------------------------------------------

echo
echo "[7/7] Final status"

echo
echo "GNOME color scheme:"
gsettings get org.gnome.desktop.interface color-scheme

echo
echo "Dock state:"
gnome-extensions info niveth-dock@nivethos 2>&1 \
    | grep -E "Enabled:|State:" || true

echo
echo "=================================================="
echo " FINAL DARK VAPORWAVE TUNING COMPLETE"
echo "=================================================="
echo
echo "Palette:"
echo "  Indigo glass"
echo "  Electric cyan border"
echo "  Violet ambient glow"
echo "  Pink running indicator"
echo
echo "Backup:"
echo "$JS_BACKUP"
echo "$CSS_BACKUP"
echo
