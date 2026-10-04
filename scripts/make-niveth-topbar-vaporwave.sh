#!/usr/bin/env bash

set -euo pipefail

UI_EXT="$HOME/.local/share/gnome-shell/extensions/niveth-ui-test@nivethos"

JS="$UI_EXT/extension.js"
CSS="$UI_EXT/stylesheet.css"

ROOTFS="$HOME/Niveth/build/rootfs"
ROOTFS_EXT="$ROOTFS/usr/share/gnome-shell/extensions/niveth-ui-test@nivethos"

ROOTFS_JS="$ROOTFS_EXT/extension.js"
ROOTFS_CSS="$ROOTFS_EXT/stylesheet.css"

STAMP="$(date +%Y%m%d-%H%M%S)"

echo
echo "=================================================="
echo " NIVETH TOP BAR — VAPORWAVE STYLE"
echo "=================================================="
echo

# ---------------------------------------------------------
# CHECKS
# ---------------------------------------------------------

if [ ! -f "$JS" ]; then
    echo "ERROR: Top Bar extension.js not found:"
    echo "$JS"
    exit 1
fi

if [ ! -f "$CSS" ]; then
    echo "ERROR: Top Bar stylesheet.css not found:"
    echo "$CSS"
    exit 1
fi

if ! grep -q "_updateTheme()" "$JS"; then
    echo "ERROR: _updateTheme() was not found."
    echo "The script will not modify the source."
    exit 1
fi

if ! grep -q "_updatePosition()" "$JS"; then
    echo "ERROR: _updatePosition() was not found."
    echo "The script will not modify the source."
    exit 1
fi

echo "[PASS] Top Bar source found"
echo "[PASS] Top Bar stylesheet found"


# ---------------------------------------------------------
# BACKUPS
# ---------------------------------------------------------

echo
echo "[1/8] Creating backups"

JS_BACKUP="$JS.backup-before-vaporwave-$STAMP"
CSS_BACKUP="$CSS.backup-before-vaporwave-$STAMP"

cp "$JS" "$JS_BACKUP"
cp "$CSS" "$CSS_BACKUP"

echo "[PASS] JS backup:"
echo "       $JS_BACKUP"

echo "[PASS] CSS backup:"
echo "       $CSS_BACKUP"


# ---------------------------------------------------------
# ADD SAFE VAPORWAVE THEME HELPER
# ---------------------------------------------------------

echo
echo "[2/8] Adding Top Bar vaporwave theme helper"

python3 - "$JS" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")

start_marker = "\n    _updateTheme() {"
end_marker = "\n    _updatePosition() {"

start = text.find(start_marker)
end = text.find(end_marker, start)

if start == -1:
    raise SystemExit(
        "ERROR: Could not locate _updateTheme()."
    )

if end == -1:
    raise SystemExit(
        "ERROR: Could not locate _updatePosition()."
    )

segment = text[start:end]

# Do not install duplicate helper.
if "_applyVaporwaveTopbarTheme()" in text:
    print("Vaporwave helper already exists.")

else:
    helper = r'''
    _applyVaporwaveTopbarTheme() {
        if (!this._bar)
            return;

        let scheme = 'prefer-dark';

        try {
            const settings =
                Gio.Settings.new(
                    'org.gnome.desktop.interface'
                );

            scheme =
                settings.get_string(
                    'color-scheme'
                );
        } catch (error) {
            scheme = 'prefer-dark';
        }

        const dark =
            scheme === 'prefer-dark';

        /*
         * Same palette as the Niveth Dock.
         *
         * Dark:
         *   indigo glass
         *   cyan edge
         *   violet glow
         *
         * Light:
         *   brighter indigo glass
         *   cyan edge
         *   violet glow
         */

        if (dark) {
            this._bar.set_style(
                'background-color: rgba(38, 33, 91, 0.84);' +
                'border: 1px solid rgba(105, 216, 255, 0.70);' +
                'border-radius: 26px;' +
                'box-shadow:' +
                '0 10px 28px rgba(4, 4, 22, 0.40),' +
                '0 0 16px rgba(88, 165, 255, 0.25),' +
                '0 0 28px rgba(197, 104, 255, 0.16);'
            );
        } else {
            this._bar.set_style(
                'background-color: rgba(65, 49, 132, 0.84);' +
                'border: 1px solid rgba(105, 216, 255, 0.74);' +
                'border-radius: 26px;' +
                'box-shadow:' +
                '0 10px 28px rgba(37, 24, 82, 0.24),' +
                '0 0 17px rgba(90, 170, 255, 0.28),' +
                '0 0 30px rgba(201, 105, 255, 0.20);'
            );
        }

        /*
         * Logo button.
         */
        if (this._logoButton) {
            this._logoButton.set_style(
                dark
                    ? 'background-color: rgba(67, 53, 130, 0.34); border-radius: 19px;'
                    : 'background-color: rgba(78, 61, 150, 0.34); border-radius: 19px;'
            );
        }

        /*
         * Icon buttons.
         */
        if (this._right) {
            for (const child of this._right.get_children()) {
                if (!child || !child.set_style)
                    continue;

                try {
                    child.set_style(
                        'background-color: transparent; border-radius: 18px;'
                    );
                } catch (error) {
                }
            }
        }
    }

'''

    # Insert helper immediately before _updatePosition().
    text = (
        text[:end]
        + "\n"
        + helper
        + text[end:]
    )

# Recompute boundaries because helper may now exist.
start = text.find(start_marker)

if start == -1:
    raise SystemExit(
        "ERROR: _updateTheme() disappeared unexpectedly."
    )

end = text.find(
    end_marker,
    start
)

if end == -1:
    raise SystemExit(
        "ERROR: _updatePosition() anchor disappeared."
    )

segment = text[start:end]

# Add helper call to the end of _updateTheme().
if "_applyVaporwaveTopbarTheme();" not in segment:

    # Find the last class-level closing brace in this method block.
    closing = segment.rfind("\n    }")

    if closing == -1:
        raise SystemExit(
            "ERROR: Could not determine _updateTheme() end."
        )

    insertion = (
        "\n\n"
        "        this._applyVaporwaveTopbarTheme();\n"
    )

    segment = (
        segment[:closing]
        + insertion
        + segment[closing:]
    )

    text = (
        text[:start]
        + segment
        + text[end:]
    )

else:
    print("Theme helper call already exists.")

path.write_text(
    text,
    encoding="utf-8"
)

print("Top Bar vaporwave helper installed.")
PY

echo "[PASS] Top Bar theme helper installed"


# ---------------------------------------------------------
# WRITE COMPLETE CSS
# ---------------------------------------------------------

echo
echo "[3/8] Writing complete Top Bar stylesheet"

cat > "$CSS" <<'CSS'
/* =========================================================
 * NIVETH TOP BAR
 * VAPORWAVE GLASS
 * Shared visual language with Niveth Dock
 * ========================================================= */


/* =========================================================
 * MAIN BAR
 * ========================================================= */

.niveth-topbar {

    min-height: 46px;

    padding-left: 8px;
    padding-right: 8px;

    spacing: 6px;

    border-radius: 26px;

    border-width: 1px;
    border-style: solid;

    background-color: rgba(38, 33, 91, 0.84);

    border-color: rgba(105, 216, 255, 0.70);

    box-shadow:
        0 10px 28px rgba(4, 4, 22, 0.40),
        0 0 16px rgba(88, 165, 255, 0.25),
        0 0 28px rgba(197, 104, 255, 0.16);
}


/* =========================================================
 * DARK
 * ========================================================= */

.niveth-topbar.niveth-dark {

    background-color: rgba(38, 33, 91, 0.84);

    border-color: rgba(105, 216, 255, 0.70);

    box-shadow:
        0 10px 28px rgba(4, 4, 22, 0.40),
        0 0 16px rgba(88, 165, 255, 0.25),
        0 0 28px rgba(197, 104, 255, 0.16);
}


/* =========================================================
 * LIGHT
 * ========================================================= */

.niveth-topbar:not(.niveth-dark) {

    background-color: rgba(65, 49, 132, 0.84);

    border-color: rgba(105, 216, 255, 0.74);

    box-shadow:
        0 10px 28px rgba(37, 24, 82, 0.24),
        0 0 17px rgba(90, 170, 255, 0.28),
        0 0 30px rgba(201, 105, 255, 0.20);
}


/* =========================================================
 * LEFT
 * ========================================================= */

.niveth-left {

    spacing: 5px;

    padding-left: 3px;
}


/* =========================================================
 * CENTER
 * ========================================================= */

.niveth-center {

    min-width: 180px;
}


/* =========================================================
 * RIGHT
 * ========================================================= */

.niveth-right {

    spacing: 2px;

    padding-right: 2px;
}


/* =========================================================
 * NIVETH LOGO
 * ========================================================= */

.niveth-logo-button {

    width: 38px;
    height: 38px;

    padding: 0;

    border-radius: 19px;

    background-color: rgba(67, 53, 130, 0.34);

    border-width: 1px;
    border-style: solid;

    border-color: rgba(105, 216, 255, 0.16);
}


.niveth-logo-button:hover {

    background-color: rgba(125, 82, 194, 0.30);

    border-color: rgba(105, 216, 255, 0.38);

    box-shadow:
        0 0 10px rgba(105, 180, 255, 0.22),
        0 0 18px rgba(197, 105, 255, 0.14);
}


/* =========================================================
 * NIVETH NAME
 * ========================================================= */

.niveth-name {

    font-size: 14px;

    font-weight: 550;

    padding-left: 2px;
    padding-right: 10px;

    color: #E7E1FF;

    text-shadow:
        0 0 8px rgba(197, 123, 255, 0.16);
}


/* =========================================================
 * CLOCK
 * ========================================================= */

.niveth-clock {

    font-size: 14px;

    font-weight: 520;

    text-align: center;

    vertical-align: middle;

    padding-top: 0;
    padding-bottom: 0;

    color: #E7E1FF;

    text-shadow:
        0 0 8px rgba(105, 216, 255, 0.15);
}


/* =========================================================
 * ICON BUTTONS
 * ========================================================= */

.niveth-icon-button {

    width: 35px;
    height: 35px;

    padding: 0;

    border-radius: 18px;

    background-color: transparent;

    border-width: 1px;
    border-style: solid;

    border-color: transparent;
}


.niveth-icon-button:hover {

    background-color: rgba(122, 82, 192, 0.26);

    border-color: rgba(115, 218, 255, 0.30);

    box-shadow:
        0 0 11px rgba(94, 174, 255, 0.22),
        0 0 19px rgba(198, 104, 255, 0.14);
}


.niveth-icon-button:active {

    background-color: rgba(181, 88, 216, 0.28);

    border-color: rgba(164, 229, 255, 0.44);
}


/* =========================================================
 * POWER BUTTON
 * ========================================================= */

.niveth-power-button:hover {

    background-color: rgba(255, 114, 210, 0.18);

    border-color: rgba(255, 114, 210, 0.30);

    box-shadow:
        0 0 10px rgba(255, 114, 210, 0.28),
        0 0 18px rgba(197, 123, 255, 0.18);
}


/* =========================================================
 * DARK TEXT
 * ========================================================= */

.niveth-topbar.niveth-dark,
.niveth-topbar.niveth-dark .niveth-name,
.niveth-topbar.niveth-dark .niveth-clock {

    color: #EEE9FF;
}


/* =========================================================
 * LIGHT TEXT
 * ========================================================= */

.niveth-topbar:not(.niveth-dark),
.niveth-topbar:not(.niveth-dark) .niveth-name,
.niveth-topbar:not(.niveth-dark) .niveth-clock {

    color: #F0EAFF;
}


/* =========================================================
 * POWER / POPUP MENUS
 * ========================================================= */

.niveth-power-menu {

    min-width: 250px;

    padding: 14px;

    border-radius: 18px;

    background-color: rgba(38, 33, 91, 0.94);

    border-width: 1px;
    border-style: solid;

    border-color: rgba(105, 216, 255, 0.34);

    box-shadow:
        0 18px 46px rgba(5, 5, 25, 0.40),
        0 0 22px rgba(96, 145, 255, 0.18),
        0 0 30px rgba(197, 104, 255, 0.12);
}


/* =========================================================
 * MENU TEXT
 * ========================================================= */

.niveth-menu-title {

    font-size: 18px;

    font-weight: 600;

    padding: 2px 10px 0 10px;

    color: #F0EAFF;
}


.niveth-menu-subtitle {

    font-size: 11px;

    opacity: 0.72;

    padding: 1px 10px 12px 10px;

    color: #D9D1F5;
}


.niveth-menu-action {

    min-height: 38px;

    padding-left: 12px;
    padding-right: 12px;

    border-radius: 10px;

    color: #EEE9FF;

    background-color: transparent;
}


.niveth-menu-action:hover {

    background-color: rgba(122, 82, 192, 0.28);

    border-color: rgba(115, 218, 255, 0.24);

    box-shadow:
        0 0 10px rgba(94, 174, 255, 0.16);
}


/* =========================================================
 * SLIDERS
 * ========================================================= */

.niveth-power-menu slider,
.niveth-power-menu trough {

    border-radius: 99px;
}


/* =========================================================
 * EDGE CLEANUP
 * ========================================================= */

.niveth-topbar StButton {

    -st-icon-shadow:
        0 1px 5px rgba(0, 0, 0, 0.26),
        0 0 7px rgba(105, 190, 255, 0.12);
}
CSS

echo "[PASS] Complete Top Bar CSS written"


# ---------------------------------------------------------
# VERIFY
# ---------------------------------------------------------

echo
echo "[4/8] Verifying JavaScript"

grep -q "_applyVaporwaveTopbarTheme()" "$JS"
grep -q "this._applyVaporwaveTopbarTheme();" "$JS"
grep -q "65, 49, 132" "$JS"
grep -q "105, 216, 255" "$JS"

echo "[PASS] Vaporwave helper exists"
echo "[PASS] Helper is called"
echo "[PASS] Light indigo color exists"
echo "[PASS] Cyan edge exists"


echo
echo "[5/8] Verifying CSS"

grep -q "rgba(38, 33, 91, 0.84)" "$CSS"
grep -q "rgba(65, 49, 132, 0.84)" "$CSS"
grep -q "rgba(105, 216, 255, 0.70)" "$CSS"
grep -q "rgba(255, 114, 210, 0.18)" "$CSS"

echo "[PASS] Dark indigo"
echo "[PASS] Light indigo"
echo "[PASS] Cyan edge"
echo "[PASS] Pink accent"


# ---------------------------------------------------------
# ROOTFS SYNC
# ---------------------------------------------------------

echo
echo "[6/8] Syncing Top Bar into Niveth rootfs"

if [ -d "$ROOTFS" ]; then

    sudo mkdir -p "$ROOTFS_EXT"

    ROOTFS_JS_BACKUP="$ROOTFS_JS.backup-before-vaporwave-$STAMP"
    ROOTFS_CSS_BACKUP="$ROOTFS_CSS.backup-before-vaporwave-$STAMP"

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

    SOURCE_JS_HASH="$(sha256sum "$JS" | awk '{print $1}')"
    ROOTFS_JS_HASH="$(sudo sha256sum "$ROOTFS_JS" | awk '{print $1}')"

    SOURCE_CSS_HASH="$(sha256sum "$CSS" | awk '{print $1}')"
    ROOTFS_CSS_HASH="$(sudo sha256sum "$ROOTFS_CSS" | awk '{print $1}')"

    if [ "$SOURCE_JS_HASH" != "$ROOTFS_JS_HASH" ]; then
        echo "[FAIL] Rootfs extension.js hash mismatch"
        exit 1
    fi

    if [ "$SOURCE_CSS_HASH" != "$ROOTFS_CSS_HASH" ]; then
        echo "[FAIL] Rootfs stylesheet.css hash mismatch"
        exit 1
    fi

    echo "[PASS] Rootfs extension.js synchronized"
    echo "[PASS] Rootfs stylesheet.css synchronized"

else
    echo "[INFO] Niveth rootfs not found:"
    echo "$ROOTFS"
    echo "[INFO] Live Top Bar updated only."
fi


# ---------------------------------------------------------
# RELOAD
# ---------------------------------------------------------

echo
echo "[7/8] Reloading Niveth Top Bar"

gnome-extensions disable niveth-ui-test@nivethos || true

sleep 3

gnome-extensions enable niveth-ui-test@nivethos

sleep 4

echo "[PASS] Top Bar reloaded"


# ---------------------------------------------------------
# FINAL STATUS
# ---------------------------------------------------------

echo
echo "[8/8] Final status"

echo
echo "Color scheme:"
gsettings get org.gnome.desktop.interface color-scheme

echo
echo "Top Bar:"
gnome-extensions info niveth-ui-test@nivethos 2>&1 \
    | grep -E "Enabled:|State:|Path:" || true

echo
echo "=================================================="
echo " NIVETH TOP BAR VAPORWAVE COMPLETE"
echo "=================================================="
echo
echo "Visual language:"
echo "  Indigo glass"
echo "  Electric cyan border"
echo "  Violet ambient glow"
echo "  Pink power accent"
echo
echo "Backups:"
echo "  $JS_BACKUP"
echo "  $CSS_BACKUP"
echo
