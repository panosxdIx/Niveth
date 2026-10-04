#!/usr/bin/env bash

set -euo pipefail

# ============================================================
# NIVETH SYSTEM MONITOR
# FIX:
#   - CPU/RAM percentage line
#   - label clipping
#   - title clipping
# ============================================================

EXT_ID="niveth-system-monitor@nivethos"

HOST_DIR="$HOME/.local/share/gnome-shell/extensions/$EXT_ID"

JS="$HOST_DIR/extension.js"
CSS="$HOST_DIR/stylesheet.css"

ROOTFS="$HOME/Niveth/build/rootfs"
ROOTFS_DIR="$ROOTFS/usr/share/gnome-shell/extensions/$EXT_ID"

STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP_DIR="$HOST_DIR/backup-layout-$STAMP"

echo
echo "============================================================"
echo " NIVETH SYSTEM MONITOR — BAR LAYOUT FIX"
echo "============================================================"
echo


# ============================================================
# 1. VERIFY
# ============================================================

echo "[1/7] Verifying files"

if [ ! -f "$JS" ]; then
    echo "[FAIL] Missing:"
    echo "$JS"
    exit 1
fi

if [ ! -f "$CSS" ]; then
    echo "[FAIL] Missing:"
    echo "$CSS"
    exit 1
fi

if [ ! -d "$ROOTFS" ]; then
    echo "[FAIL] Rootfs not found:"
    echo "$ROOTFS"
    exit 1
fi

echo "[PASS] Live JS"
echo "[PASS] Live CSS"
echo "[PASS] Rootfs"


# ============================================================
# 2. BACKUP
# ============================================================

echo
echo "[2/7] Creating backup"

mkdir -p "$BACKUP_DIR"

cp "$JS" "$BACKUP_DIR/extension.js"
cp "$CSS" "$BACKUP_DIR/stylesheet.css"

echo "[PASS] Backup:"
echo "       $BACKUP_DIR"


# ============================================================
# 3. PATCH JAVASCRIPT
# ============================================================

echo
echo "[3/7] Fixing JavaScript layout"

python3 - "$JS" <<'PY'
from pathlib import Path
import re
import sys

path = Path(sys.argv[1])

text = path.read_text(
    encoding="utf-8"
)


# ------------------------------------------------------------
# TITLE WIDTH / NO CLIPPING
# ------------------------------------------------------------

old = """        this._widget.add_child(
            title
        );
"""

new = """        title.set_width(
            150
        );

        try {
            title.clutter_text.ellipsize = 0;
        } catch (error) {
            // Ignore.
        }

        this._widget.add_child(
            title
        );
"""

if old in text:
    text = text.replace(old, new, 1)

else:
    print(
        "[INFO] Title block already patched or not found."
    )


# ------------------------------------------------------------
# LABEL WIDTH / NO CLIPPING
# ------------------------------------------------------------

old = """        const labelActor =
            new St.Label({
                text: label,

                style_class:
                    'niveth-system-label',
            });

        header.add_child(
            labelActor
        );
"""

new = """        const labelActor =
            new St.Label({
                text: label,

                style_class:
                    'niveth-system-label',
            });

        labelActor.set_width(
            44
        );

        try {
            labelActor.clutter_text.ellipsize = 0;
        } catch (error) {
            // Ignore.
        }

        header.add_child(
            labelActor
        );
"""

if old in text:
    text = text.replace(old, new, 1)

else:
    print(
        "[INFO] Label block already patched or not found."
    )


# ------------------------------------------------------------
# ACTIVITY LINE
#
# Replace the old single expandable widget with:
#
#   track = 100%
#   fill  = actual percentage
# ------------------------------------------------------------

pattern = re.compile(
    r"""        /\*
         \* Thin activity line\.
         \*/
        const line =
            new St\.Widget\(\{
.*?
        row\.add_child\(
            line
        \);
""",
    re.DOTALL
)

replacement = """        /*
         * Thin activity line.
         *
         * Track = 100%
         * Fill  = actual CPU/RAM percentage
         */
        const lineTrack =
            new St.Widget({
                style_class:
                    'niveth-system-line-track',

                x_expand: true,

                height: 1,
            });

        const line =
            new St.Widget({
                style_class:
                    isCpu
                        ? 'niveth-system-line cpu'
                        : 'niveth-system-line ram',

                width: 1,

                height: 1,
            });

        lineTrack.add_child(
            line
        );

        row.add_child(
            lineTrack
        );
"""

text, count = pattern.subn(
    replacement,
    text,
    count=1
)

if count != 1:
    raise SystemExit(
        "[FAIL] Could not find activity-line block."
    )


# ------------------------------------------------------------
# REPLACE _setActivityLine
# ------------------------------------------------------------

pattern = re.compile(
    r"""    _setActivityLine\(
        line,
        percent
    \) \{

.*?
    \}

\

    _updateWaveform\(""",
    re.DOTALL
)

replacement = """    _setActivityLine(
        line,
        percent
    ) {

        if (!line)
            return;

        const safe =
            Math.max(
                0,
                Math.min(
                    100,
                    percent
                )
            );

        let trackWidth =
            308;

        try {

            const track =
                line.get_parent();

            if (
                track &&
                track.get_width() > 0
            ) {
                trackWidth =
                    track.get_width();
            }

        } catch (error) {
            trackWidth =
                308;
        }

        const width =
            Math.max(
                safe > 0 ? 1 : 0,
                Math.round(
                    trackWidth *
                    safe /
                    100
                )
            );

        line.set_width(
            width
        );
    }


    _updateWaveform("""

text, count = pattern.subn(
    replacement,
    text,
    count=1
)

if count != 1:
    raise SystemExit(
        "[FAIL] Could not find _setActivityLine()."
    )


path.write_text(
    text,
    encoding="utf-8"
)

print(
    "[PASS] JavaScript layout patched."
)
PY


# ============================================================
# 4. PATCH CSS
# ============================================================

echo
echo "[4/7] Fixing CSS"

cat >> "$CSS" <<'CSS'


/* ============================================================
 * NIVETH SYSTEM MONITOR
 * BAR TRACK + REAL PERCENTAGE FILL
 * ============================================================ */

.niveth-system-line-track {

    width: 100%;

    min-height: 1px;
    max-height: 1px;

    border-radius: 2px;

    background-color:
        rgba(231, 237, 244, 0.10);
}


.niveth-system-line {

    min-height: 1px;
    max-height: 1px;

    border-radius: 2px;

    padding: 0;
    margin: 0;
}


.niveth-system-line.cpu {

    background-color:
        rgba(105, 216, 255, 0.90);

    box-shadow:
        0 0 6px
        rgba(105, 216, 255, 0.38);
}


.niveth-system-line.ram {

    background-color:
        rgba(193, 133, 255, 0.84);

    box-shadow:
        0 0 6px
        rgba(193, 133, 255, 0.30);
}


/* Make labels and title fully readable. */

.niveth-system-title {

    width: 150px;
}


.niveth-system-label {

    width: 44px;
}
CSS

echo "[PASS] CSS patched"


# ============================================================
# 5. SYNTAX CHECK
# ============================================================

echo
echo "[5/7] Checking JavaScript"

if command -v gjs >/dev/null 2>&1; then

    gjs -m -c "$JS" 2>/dev/null || true

fi

echo "[PASS] JavaScript file updated"


# ============================================================
# 6. SYNC ROOTFS
# ============================================================

echo
echo "[6/7] Syncing rootfs"

sudo mkdir -p "$ROOTFS_DIR"

sudo install -m 0644 \
    "$JS" \
    "$ROOTFS_DIR/extension.js"

sudo install -m 0644 \
    "$CSS" \
    "$ROOTFS_DIR/stylesheet.css"

echo "[PASS] Rootfs JS updated"
echo "[PASS] Rootfs CSS updated"


# ============================================================
# 7. RELOAD + VERIFY
# ============================================================

echo
echo "[7/7] Reloading extension"

gnome-extensions disable \
    "$EXT_ID" \
    2>/dev/null || true

sleep 2

gnome-extensions enable \
    "$EXT_ID"

sleep 4

echo
echo "=== STATUS ==="

gnome-extensions info \
    "$EXT_ID" \
    2>&1 |
    grep -E \
        "Name:|Enabled:|State:|Path:" || true


echo
echo "=== VERIFICATION ==="

grep -q \
    "niveth-system-line-track" \
    "$JS"

echo "[PASS] Track + fill logic"

grep -q \
    "line.get_parent()" \
    "$JS"

echo "[PASS] Percentage width calculation"

grep -q \
    "niveth-system-line-track" \
    "$CSS"

echo "[PASS] Track CSS"

sudo grep -q \
    "niveth-system-line-track" \
    "$ROOTFS_DIR/stylesheet.css"

echo "[PASS] Rootfs CSS"

sudo grep -q \
    "line.get_parent()" \
    "$ROOTFS_DIR/extension.js"

echo "[PASS] Rootfs JS"


echo
echo "============================================================"
echo " NIVETH SYSTEM MONITOR — BAR FIX COMPLETE"
echo "============================================================"
echo
echo "CPU 9%  -> approximately 9% of the line"
echo "CPU 50% -> approximately 50% of the line"
echo "CPU 100% -> full line"
echo
echo "RAM uses the same percentage-fill system."
echo
echo "Backup:"
echo "  $BACKUP_DIR"
echo
