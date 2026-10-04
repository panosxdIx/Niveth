#!/usr/bin/env bash

set -euo pipefail

# ============================================================
# NIVETH SYSTEM MONITOR — BAR FIX V2
#
# Fixes:
#   - CPU percentage line
#   - RAM percentage line
#   - label clipping
#   - title clipping
#
# Preserves:
#   - audio-reactive cyan waveform
#   - RAM violet waveform
#   - CPU / RAM readings
# ============================================================

EXT_ID="niveth-system-monitor@nivethos"

HOST_DIR="$HOME/.local/share/gnome-shell/extensions/$EXT_ID"

JS="$HOST_DIR/extension.js"
CSS="$HOST_DIR/stylesheet.css"

ROOTFS="$HOME/Niveth/build/rootfs"
ROOTFS_DIR="$ROOTFS/usr/share/gnome-shell/extensions/$EXT_ID"

STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP_DIR="$HOST_DIR/backup-bars-v2-$STAMP"

echo
echo "============================================================"
echo " NIVETH SYSTEM MONITOR — BAR FIX V2"
echo "============================================================"
echo


# ============================================================
# 1. VERIFY
# ============================================================

echo "[1/8] Verifying files"

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
echo "[2/8] Creating backup"

mkdir -p "$BACKUP_DIR"

cp "$JS" "$BACKUP_DIR/extension.js"
cp "$CSS" "$BACKUP_DIR/stylesheet.css"

echo "[PASS] Backup:"
echo "       $BACKUP_DIR"


# ============================================================
# 3. PATCH JS
# ============================================================

echo
echo "[3/8] Patching JavaScript"

python3 - "$JS" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])

text = path.read_text(
    encoding="utf-8"
)


# ============================================================
# HELPER: replace one complete JS method by brace matching
# ============================================================

def replace_method(source, method_name, replacement):
    needle = f"    {method_name}("

    start = source.find(needle)

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
            f"Could not find opening brace for: {method_name}"
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
        f"Could not match braces for: {method_name}"
    )


# ============================================================
# 3A. TITLE
# ============================================================

if "title.set_width(" not in text:

    marker = """        this._widget.add_child(
            title
        );
"""

    replacement = """        title.set_width(
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

    if marker not in text:
        raise SystemExit(
            "[FAIL] Could not find title insertion point."
        )

    text = text.replace(
        marker,
        replacement,
        1
    )

    print("[PASS] Title width fixed")

else:

    print("[INFO] Title width already fixed")


# ============================================================
# 3B. LABELS
# ============================================================

if "labelActor.set_width(" not in text:

    marker = """        header.add_child(
            labelActor
        );
"""

    replacement = """        labelActor.set_width(
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

    if marker not in text:
        raise SystemExit(
            "[FAIL] Could not find label insertion point."
        )

    text = text.replace(
        marker,
        replacement,
        1
    )

    print("[PASS] Label width fixed")

else:

    print("[INFO] Label width already fixed")


# ============================================================
# 3C. ACTIVITY LINE
# ============================================================

if "niveth-system-line-track" not in text:

    marker = """        row.add_child(
            line
        );
"""

    marker_start = text.find(
        marker
    )

    if marker_start < 0:
        raise SystemExit(
            "[FAIL] Could not find activity line insertion point."
        )

    search_start = text.rfind(
        "        const line =",
        0,
        marker_start
    )

    if search_start < 0:
        raise SystemExit(
            "[FAIL] Could not locate activity line block."
        )

    block_end = marker_start + len(marker)

    new_block = """        /*
         * Thin activity line.
         *
         * Track = 100%
         * Fill  = actual percentage
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

    text = (
        text[:search_start] +
        new_block +
        text[block_end:]
    )

    print("[PASS] Activity line converted to track + fill")

else:

    print("[INFO] Activity line already uses track + fill")


# ============================================================
# 3D. REPLACE _setActivityLine
# ============================================================

new_method = """    _setActivityLine(
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

        let trackWidth = 308;

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
    }"""


text = replace_method(
    text,
    "_setActivityLine",
    new_method
)

print(
    "[PASS] _setActivityLine replaced safely"
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
# 4. PATCH CSS
# ============================================================

echo
echo "[4/8] Patching stylesheet"

if ! grep -q \
    "NIVETH SYSTEM MONITOR — BAR FIX V2" \
    "$CSS"
then

cat >> "$CSS" <<'CSS'


/* ============================================================
 * NIVETH SYSTEM MONITOR — BAR FIX V2
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


.niveth-system-title {

    width: 150px;
}


.niveth-system-label {

    width: 44px;
}
CSS

echo "[PASS] CSS additions written"

else

echo "[INFO] V2 CSS already present"

fi


# ============================================================
# 5. VERIFY SOURCE
# ============================================================

echo
echo "[5/8] Verifying source"

grep -q \
    "niveth-system-line-track" \
    "$JS"

echo "[PASS] Track found"

grep -q \
    "line.get_parent()" \
    "$JS"

echo "[PASS] Percentage calculation found"

grep -q \
    "title.set_width" \
    "$JS"

echo "[PASS] Title width found"

grep -q \
    "labelActor.set_width" \
    "$JS"

echo "[PASS] Label width found"

grep -q \
    "NIVETH SYSTEM MONITOR — BAR FIX V2" \
    "$CSS"

echo "[PASS] CSS V2 found"


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

echo "[PASS] Rootfs extension.js updated"
echo "[PASS] Rootfs stylesheet.css updated"


# ============================================================
# 7. VERIFY ROOTFS
# ============================================================

echo
echo "[7/8] Verifying rootfs"

sudo grep -q \
    "niveth-system-line-track" \
    "$ROOTFS_DIR/extension.js"

echo "[PASS] Rootfs track"

sudo grep -q \
    "line.get_parent()" \
    "$ROOTFS_DIR/extension.js"

echo "[PASS] Rootfs percentage calculation"

sudo grep -q \
    "NIVETH SYSTEM MONITOR — BAR FIX V2" \
    "$ROOTFS_DIR/stylesheet.css"

echo "[PASS] Rootfs CSS"


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
echo " NIVETH SYSTEM MONITOR — BAR FIX V2 COMPLETE"
echo "============================================================"
echo
echo "CPU 9%  -> ~9% line"
echo "CPU 50% -> ~50% line"
echo "CPU 100% -> full line"
echo
echo "RAM uses the same percentage-fill logic."
echo
echo "Audio waveform remains enabled."
echo
echo "Backup:"
echo "  $BACKUP_DIR"
echo
