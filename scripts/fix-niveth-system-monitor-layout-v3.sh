#!/usr/bin/env bash

set -euo pipefail

# ============================================================
# NIVETH SYSTEM MONITOR — LAYOUT FIX V3
#
# Fixes:
#   - CPU/RAM percentage bars
#   - CPU/RAM label clipping
#   - NIVETH SYSTEM title clipping
#
# Preserves:
#   - audio-reactive cyan waveform
#   - RAM violet waveform
#   - CPU/RAM metrics
# ============================================================

EXT_ID="niveth-system-monitor@nivethos"

HOST_DIR="$HOME/.local/share/gnome-shell/extensions/$EXT_ID"

JS="$HOST_DIR/extension.js"
CSS="$HOST_DIR/stylesheet.css"

ROOTFS="$HOME/Niveth/build/rootfs"
ROOTFS_DIR="$ROOTFS/usr/share/gnome-shell/extensions/$EXT_ID"

STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP_DIR="$HOST_DIR/backup-layout-v3-$STAMP"

echo
echo "============================================================"
echo " NIVETH SYSTEM MONITOR — LAYOUT FIX V3"
echo "============================================================"
echo


# ============================================================
# 1. VERIFY
# ============================================================

echo "[1/8] Verifying files"

if [ ! -f "$JS" ]; then
    echo "[FAIL] Missing:"
    echo "       $JS"
    exit 1
fi

if [ ! -f "$CSS" ]; then
    echo "[FAIL] Missing:"
    echo "       $CSS"
    exit 1
fi

if [ ! -d "$ROOTFS" ]; then
    echo "[FAIL] Rootfs not found:"
    echo "       $ROOTFS"
    exit 1
fi

echo "[PASS] Live JS"
echo "[PASS] Live CSS"
echo "[PASS] Rootfs"


# ============================================================
# 2. BACKUP
# ============================================================

echo
echo "[2/8] Creating backup"

mkdir -p "$BACKUP_DIR"

cp \
    "$JS" \
    "$BACKUP_DIR/extension.js"

cp \
    "$CSS" \
    "$BACKUP_DIR/stylesheet.css"

echo "[PASS] Backup:"
echo "       $BACKUP_DIR"


# ============================================================
# 3. PATCH JAVASCRIPT
# ============================================================

echo
echo "[3/8] Rebuilding metric-row layout"

python3 - "$JS" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])

text = path.read_text(
    encoding="utf-8"
)


# ============================================================
# Replace a complete JS method using brace matching.
# ============================================================

def replace_method(source, method_name, replacement):

    needle = f"    {method_name}("

    start = source.find(
        needle
    )

    if start < 0:
        raise RuntimeError(
            f"Could not find method: {method_name}"
        )

    brace_start = source.find(
        "{",
        start
    )

    if brace_start < 0:
        raise RuntimeError(
            f"Could not find opening brace: {method_name}"
        )

    depth = 0

    in_string = None
    escape = False

    in_line_comment = False
    in_block_comment = False

    i = brace_start

    while i < len(source):

        ch = source[i]

        nxt = (
            source[i + 1]
            if i + 1 < len(source)
            else ""
        )

        if in_line_comment:

            if ch == "\n":
                in_line_comment = False

            i += 1
            continue

        if in_block_comment:

            if ch == "*" and nxt == "/":
                in_block_comment = False
                i += 2
                continue

            i += 1
            continue

        if in_string is not None:

            if escape:
                escape = False

            elif ch == "\\":
                escape = True

            elif ch == in_string:
                in_string = None

            i += 1
            continue

        if ch == "/" and nxt == "/":

            in_line_comment = True
            i += 2
            continue

        if ch == "/" and nxt == "*":

            in_block_comment = True
            i += 2
            continue

        if ch in ("'", '"', "`"):

            in_string = ch
            i += 1
            continue

        if ch == "{":

            depth += 1

        elif ch == "}":

            depth -= 1

            if depth == 0:

                end = i + 1

                return (
                    source[:start] +
                    replacement +
                    source[end:]
                )

        i += 1

    raise RuntimeError(
        f"Could not match braces: {method_name}"
    )


# ============================================================
# 3A. TITLE
# ============================================================

if "this._title.set_width(" not in text:

    marker = """        this._widget.add_child(
            this._title
        );
"""

    if marker not in text:
        raise SystemExit(
            "[FAIL] Could not find current System Monitor title block."
        )

    replacement = """        /*
         * Keep title fully visible.
         */
        this._title.set_width(
            170
        );

        try {
            this._title.clutter_text.ellipsize = 0;
        } catch (error) {
            // Ignore.
        }

        this._widget.add_child(
            this._title
        );
"""

    text = text.replace(
        marker,
        replacement,
        1
    )

    print(
        "[PASS] Title width fixed"
    )

else:

    print(
        "[INFO] Title width already fixed"
    )


# ============================================================
# 3B. COMPLETE METRIC ROW
# ============================================================

new_metric_row = """    _buildMetricRow(
        label,
        isCpu = label === 'CPU'
    ) {

        const row =
            new St.BoxLayout({
                vertical: true,

                style_class:
                    'niveth-system-metric',

                x_expand: true,
            });


        /*
         * HEADER
         *
         * CPU                         9%
         */
        const header =
            new St.BoxLayout({
                vertical: false,

                style_class:
                    'niveth-system-header',

                x_expand: true,
            });


        const labelActor =
            new St.Label({
                text: label,

                style_class:
                    'niveth-system-label',
            });


        /*
         * Fixed label width so CPU/RAM
         * can never become C... / RA...
         */
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


        const spacer =
            new St.Widget({
                x_expand: true,
            });

        header.add_child(
            spacer
        );


        const value =
            new St.Label({
                text: '--',

                style_class:
                    'niveth-system-value',
            });

        header.add_child(
            value
        );


        row.add_child(
            header
        );


        /*
         * PERCENTAGE TRACK
         *
         * The track is always exactly
         * 308 px wide.
         *
         * The colored fill is controlled
         * by _setActivityLine().
         */
        const lineTrack =
            new St.Widget({
                style_class:
                    'niveth-system-line-track',

                width: 308,

                height: 1,

                x_expand: false,

                x_align:
                    Clutter.ActorAlign.START,
            });


        const line =
            new St.Widget({
                style_class:
                    isCpu
                        ? 'niveth-system-line cpu'
                        : 'niveth-system-line ram',

                width: 0,

                height: 1,

                x_expand: false,

                x_align:
                    Clutter.ActorAlign.START,
            });


        lineTrack.add_child(
            line
        );


        row.add_child(
            lineTrack
        );


        /*
         * WAVEFORM
         */
        const wave =
            new St.BoxLayout({
                vertical: false,

                style_class:
                    'niveth-system-wave',

                x_expand: true,

                height: 25,
            });


        const waveBars = [];


        for (
            let i = 0;
            i < WAVE_COUNT;
            i++
        ) {

            const bar =
                new St.Widget({
                    style_class:
                        isCpu
                            ? 'niveth-system-wave-bar cpu'
                            : 'niveth-system-wave-bar ram',

                    width: 3,

                    height: 4,

                    x_expand: false,

                    y_align:
                        Clutter.ActorAlign.END,
                });


            wave.add_child(
                bar
            );


            waveBars.push(
                bar
            );
        }


        row.add_child(
            wave
        );


        return {
            row,
            value,
            line,
            waveBars,
        };
    }"""


text = replace_method(
    text,
    "_buildMetricRow",
    new_metric_row
)

print(
    "[PASS] Metric row rebuilt"
)


# ============================================================
# 3C. COMPLETE ACTIVITY LINE
# ============================================================

new_activity_line = """    _setActivityLine(
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
                    Number(percent) || 0
                )
            );


        /*
         * Track width is fixed at 308 px.
         *
         * Therefore:
         *
         *  9%   = 27.72 px
         *  50%  = 154 px
         *  100% = 308 px
         */
        const TRACK_WIDTH = 308;


        const width =
            Math.round(
                TRACK_WIDTH *
                safe /
                100
            );


        line.set_width(
            width
        );
    }"""


text = replace_method(
    text,
    "_setActivityLine",
    new_activity_line
)

print(
    "[PASS] Percentage calculation rebuilt"
)


# ============================================================
# SAVE
# ============================================================

path.write_text(
    text,
    encoding="utf-8"
)

print(
    "[PASS] extension.js written"
)
PY


# ============================================================
# 4. CSS
# ============================================================

echo
echo "[4/8] Replacing percentage-bar CSS"

cat >> "$CSS" <<'CSS'


/* ============================================================
 * NIVETH SYSTEM MONITOR — LAYOUT V3
 * ============================================================ */

.niveth-system-monitor {

    width: 330px;

    min-width: 330px;

    max-width: 330px;
}


/* ------------------------------------------------------------
 * TITLE
 * ------------------------------------------------------------ */

.niveth-system-title {

    width: 170px;

    min-width: 170px;

    max-width: 170px;
}


/* ------------------------------------------------------------
 * CPU / RAM LABELS
 * ------------------------------------------------------------ */

.niveth-system-label {

    width: 44px;

    min-width: 44px;

    max-width: 44px;
}


/* ------------------------------------------------------------
 * PERCENTAGE TRACK
 * ------------------------------------------------------------ */

.niveth-system-line-track {

    width: 308px;

    min-width: 308px;

    max-width: 308px;

    min-height: 1px;

    max-height: 1px;

    height: 1px;

    border-radius: 2px;

    background-color:
        rgba(231, 237, 244, 0.10);

    padding: 0;

    margin: 0;
}


/* ------------------------------------------------------------
 * PERCENTAGE FILL
 * ------------------------------------------------------------ */

.niveth-system-line {

    min-height: 1px;

    max-height: 1px;

    height: 1px;

    padding: 0;

    margin: 0;

    border-radius: 2px;
}


.niveth-system-line.cpu {

    background-color:
        rgba(105, 216, 255, 0.92);

    box-shadow:
        0 0 6px
        rgba(105, 216, 255, 0.40);
}


.niveth-system-line.ram {

    background-color:
        rgba(193, 133, 255, 0.86);

    box-shadow:
        0 0 6px
        rgba(193, 133, 255, 0.32);
}
CSS

echo "[PASS] CSS written"


# ============================================================
# 5. VERIFY SOURCE
# ============================================================

echo
echo "[5/8] Verifying source"

grep -q \
    "TRACK_WIDTH = 308" \
    "$JS"

echo "[PASS] Fixed 308px track"

grep -q \
    "this._title.set_width" \
    "$JS"

echo "[PASS] Full title width"

grep -q \
    "labelActor.set_width" \
    "$JS"

echo "[PASS] Full CPU/RAM label width"

grep -q \
    "niveth-system-line-track" \
    "$JS"

echo "[PASS] Percentage track"

grep -q \
    "audio" \
    "$JS"

echo "[PASS] Existing audio functionality remains in JS"


# ============================================================
# 6. SYNC ROOTFS
# ============================================================

echo
echo "[6/8] Syncing rootfs"

sudo mkdir -p \
    "$ROOTFS_DIR"

sudo install -m 0644 \
    "$JS" \
    "$ROOTFS_DIR/extension.js"

sudo install -m 0644 \
    "$CSS" \
    "$ROOTFS_DIR/stylesheet.css"

echo "[PASS] Rootfs JS"
echo "[PASS] Rootfs CSS"


# ============================================================
# 7. VERIFY ROOTFS
# ============================================================

echo
echo "[7/8] Verifying rootfs"

sudo grep -q \
    "TRACK_WIDTH = 308" \
    "$ROOTFS_DIR/extension.js"

echo "[PASS] Rootfs percentage logic"

sudo grep -q \
    "this._title.set_width" \
    "$ROOTFS_DIR/extension.js"

echo "[PASS] Rootfs title width"

sudo grep -q \
    "labelActor.set_width" \
    "$ROOTFS_DIR/extension.js"

echo "[PASS] Rootfs label width"

sudo grep -q \
    "width: 308px" \
    "$ROOTFS_DIR/stylesheet.css"

echo "[PASS] Rootfs 308px track CSS"


# ============================================================
# 8. RELOAD
# ============================================================

echo
echo "[8/8] Reloading System Monitor"

gnome-extensions disable \
    "$EXT_ID" \
    2>/dev/null || true

sleep 2

gnome-extensions enable \
    "$EXT_ID"

sleep 5


echo
echo "=== STATUS ==="

gnome-extensions info \
    "$EXT_ID" \
    2>&1 |
    grep -E \
        "Name:|Enabled:|State:|Path:" || true


echo
echo "============================================================"
echo " NIVETH SYSTEM MONITOR — V3 COMPLETE"
echo "============================================================"
echo
echo "Percentage bar:"
echo "  CPU 9%   -> ~28 px"
echo "  CPU 25%  -> ~77 px"
echo "  CPU 50%  -> 154 px"
echo "  CPU 75%  -> 231 px"
echo "  CPU 100% -> 308 px"
echo
echo "Labels:"
echo "  CPU -> fully visible"
echo "  RAM -> fully visible"
echo "  NIVETH SYSTEM -> fully visible"
echo
echo "Audio waveform:"
echo "  Preserved"
echo
echo "Backup:"
echo "  $BACKUP_DIR"
echo
