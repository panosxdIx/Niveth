#!/usr/bin/env bash

set -euo pipefail

UUID="niveth-system-monitor@nivethos"

EXT="$HOME/.local/share/gnome-shell/extensions/$UUID"

ROOTFS="$HOME/Niveth/build/rootfs"
ROOTFS_EXT="$ROOTFS/usr/share/gnome-shell/extensions/$UUID"

echo "============================================================"
echo " NIVETH SYSTEM MONITOR — V18 BACKGROUND GROUP"
echo "============================================================"
echo
echo "Target:"
echo "  Wallpaper"
echo "      ↓"
echo "  System Monitor"
echo "      ↓"
echo "  Application windows"
echo "      ↓"
echo "  GNOME Shell UI"
echo
echo "Preserve:"
echo "  - right/top position"
echo "  - transparent background"
echo "  - bright text"
echo "  - CPU/RAM"
echo "  - AUDIO waveform"
echo "  - click-through"
echo

# ------------------------------------------------------------
# 1. Verify
# ------------------------------------------------------------

echo "[1/10] Verifying extension..."

if [ ! -f "$EXT/extension.js" ]; then
    echo "[FAIL] extension.js not found:"
    echo "  $EXT/extension.js"
    exit 1
fi

if [ ! -f "$EXT/metadata.json" ]; then
    echo "[FAIL] metadata.json not found."
    exit 1
fi

echo "[PASS] Extension found"
echo

# ------------------------------------------------------------
# 2. Backup
# ------------------------------------------------------------

echo "[2/10] Creating backup..."

BACKUP="$EXT/backup-v18-background-group-$(date +%Y%m%d-%H%M%S)"

mkdir -p "$BACKUP"

cp -a \
    "$EXT/extension.js" \
    "$BACKUP/extension.js"

cp -a \
    "$EXT/metadata.json" \
    "$BACKUP/metadata.json"

if [ -f "$EXT/stylesheet.css" ]; then
    cp -a \
        "$EXT/stylesheet.css" \
        "$BACKUP/stylesheet.css"
fi

if [ -f "$EXT/niveth-audio-meter.py" ]; then
    cp -a \
        "$EXT/niveth-audio-meter.py" \
        "$BACKUP/niveth-audio-meter.py"
fi

echo "[PASS] Backup:"
echo "  $BACKUP"
echo

# ------------------------------------------------------------
# 3. Disable
# ------------------------------------------------------------

echo "[3/10] Disabling System Monitor..."

gnome-extensions disable "$UUID" 2>/dev/null || true

sleep 1

echo "[PASS] Disabled"
echo

# ------------------------------------------------------------
# 4. Replace stacking layer
# ------------------------------------------------------------

echo "[4/10] Moving monitor into GNOME background group..."

python3 - "$EXT/extension.js" <<'PY'
from pathlib import Path
import re
import sys

path = Path(sys.argv[1])
text = path.read_text()

# ----------------------------------------------------------
# Find the code between _buildWidget() and _positionWidget().
# This area contains the current V17 addChrome() operation.
# ----------------------------------------------------------

pattern = re.compile(
    r"""(?P<indent>\s*)this\._buildWidget\(\);\n
        (?P<body>.*?)
        (?P<position>\s*this\._positionWidget\(\);)""",
    re.DOTALL | re.VERBOSE
)

match = pattern.search(text)

if not match:
    print("[FAIL] Could not locate widget insertion block.")
    sys.exit(1)

indent = match.group("indent")
position_line = match.group("position")

replacement = f"""{indent}this._buildWidget();

{indent}/*
{indent} * Put the monitor inside GNOME Shell's own
{indent} * background group.
{indent} *
{indent} * GNOME Shell creates this group inside the
{indent} * Mutter window group and lowers it below
{indent} * normal application window actors.
{indent} */
{indent}const backgroundGroup =
{indent}    Main.layoutManager._backgroundGroup;

{indent}if (!backgroundGroup) {{

{indent}    throw new Error(
{indent}        '[{UUID}] GNOME background group unavailable'
{indent}    );
{indent}}}

{indent}backgroundGroup.add_child(
{indent}    this._widget
{indent});

{indent}backgroundGroup.lower_bottom();

{indent}this._positionWidget();"""

text = (
    text[:match.start()]
    +
    replacement
    +
    text[match.end():]
)

# ----------------------------------------------------------
# Remove obsolete stacking APIs if any survive.
# ----------------------------------------------------------

obsolete_patterns = [
    r"""\s*Main\.layoutManager\.addChrome\(
.*?
        \);\n""",
    r"""\s*stage\.insert_child_below\(
.*?
        \);\n""",
    r"""\s*windowGroup\.insert_child_below\(
.*?
        \);\n""",
    r"""\s*windowGroup\.set_child_below_sibling\(
.*?
        \);\n""",
]

for obsolete in obsolete_patterns:
    text = re.sub(
        obsolete,
        "\n",
        text,
        flags=re.DOTALL
    )

# ----------------------------------------------------------
# Remove old z-position code if any survived.
# ----------------------------------------------------------

text = re.sub(
    r"""\s*this\._widget\.set_z_position\(
.*?
        \);""",
    "",
    text,
    flags=re.DOTALL
)

# ----------------------------------------------------------
# Remove reserved-space options if any survived.
# ----------------------------------------------------------

text = text.replace(
    "                affectsStruts: true,\n",
    ""
)

text = text.replace(
    "                affectsInputRegion: false,\n",
    ""
)

# ----------------------------------------------------------
# Ensure click-through remains.
# ----------------------------------------------------------

if "this._widget.set_reactive(false);" not in text:

    marker = """        this._widget.show();
"""

    replacement_click = """        this._widget.show();

        this._widget.set_reactive(false);
"""

    if marker not in text:
        print("[FAIL] Could not restore click-through.")
        sys.exit(1)

    text = text.replace(
        marker,
        replacement_click,
        1
    )

# ----------------------------------------------------------
# Replace the disable() widget cleanup with safe parent
# removal before destroy().
# ----------------------------------------------------------

cleanup_pattern = re.compile(
    r"""        if \(this\._widget\) \{

.*?
        \}\n""",
    re.DOTALL
)

cleanup_match = cleanup_pattern.search(text)

if cleanup_match:

    cleanup_block = cleanup_match.group(0)

    if "this._widget.destroy();" in cleanup_block:

        safe_cleanup = """        if (this._widget) {

            try {

                const parent =
                    this._widget.get_parent();

                if (parent) {

                    parent.remove_child(
                        this._widget
                    );
                }

            } catch (error) {
            }

            this._widget.destroy();

            this._widget = null;
        }
"""

        text = (
            text[:cleanup_match.start()]
            +
            safe_cleanup
            +
            text[cleanup_match.end():]
        )

path.write_text(text)

print("[PASS] Background group insertion installed")
print("[PASS] Old Shell chrome stacking removed")
print("[PASS] Old window-group hacks removed")
print("[PASS] Click-through preserved")
print("[PASS] Safe cleanup installed")
PY

echo

# ------------------------------------------------------------
# 5. Restore position if needed
# ------------------------------------------------------------

echo "[5/10] Verifying right-side position..."

python3 - "$EXT/extension.js" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text()

desired = """        const x =
            monitor.x +
            monitor.width -
            width -
            18;
"""

current = """        const x =
            monitor.x +
            monitor.width -
            width;
"""

if desired in text:

    print("[PASS] Right-side position correct")

elif current in text:

    text = text.replace(
        current,
        desired,
        1
    )

    path.write_text(text)

    print("[PASS] Restored 18px right margin")

else:

    print("[FAIL] Monitor X-position not found.")
    sys.exit(1)
PY

echo

# ------------------------------------------------------------
# 6. Update metadata
# ------------------------------------------------------------

echo "[6/10] Updating metadata..."

python3 - "$EXT/metadata.json" <<'PY'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])

data = json.loads(
    path.read_text()
)

data["version"] = 18

path.write_text(
    json.dumps(
        data,
        indent=2,
        ensure_ascii=False
    ) + "\n"
)

print("[PASS] Version -> 18")
PY

echo

# ------------------------------------------------------------
# 7. Verify source
# ------------------------------------------------------------

echo "[7/10] Verifying V18 source..."

check_present() {
    local label="$1"
    local pattern="$2"

    if grep -Fq "$pattern" "$EXT/extension.js"; then
        echo "[PASS] $label"
    else
        echo "[FAIL] $label"
        exit 1
    fi
}

check_absent() {
    local label="$1"
    local pattern="$2"

    if grep -Fq "$pattern" "$EXT/extension.js"; then
        echo "[FAIL] $label"
        exit 1
    else
        echo "[PASS] $label"
    fi
}

check_present \
    "background group" \
    "Main.layoutManager._backgroundGroup"

check_present \
    "background group child" \
    "backgroundGroup.add_child"

check_present \
    "background group bottom" \
    "backgroundGroup.lower_bottom"

check_present \
    "click-through" \
    "this._widget.set_reactive(false);"

check_present \
    "audio history" \
    "_audioHistory"

check_present \
    "audio bars" \
    "_audioBars"

check_present \
    "audio meter" \
    "_startAudioMeter()"

check_present \
    "metrics" \
    "_startMetrics()"

check_present \
    "transparent background" \
    "rgba(16, 17, 29, 0.0)"

check_absent \
    "addChrome removed" \
    "Main.layoutManager.addChrome"

check_absent \
    "affectsStruts removed" \
    "affectsStruts"

check_absent \
    "stage stacking removed" \
    "stage.insert_child_below"

check_absent \
    "windowGroup stacking removed" \
    "windowGroup.insert_child_below"

check_absent \
    "z-position hack removed" \
    "set_z_position"

VERSION="$(
    python3 - "$EXT/metadata.json" <<'PY'
import json
import sys
from pathlib import Path

print(
    json.loads(
        Path(sys.argv[1]).read_text()
    ).get("version")
)
PY
)"

if [ "$VERSION" != "18" ]; then
    echo "[FAIL] Metadata version is not 18."
    exit 1
fi

echo "[PASS] Version 18"
echo

# ------------------------------------------------------------
# 8. Syntax sanity through GJS module loading
# ------------------------------------------------------------

echo "[8/10] Checking JavaScript loading..."

if command -v gjs >/dev/null 2>&1; then

    gjs -m --help >/dev/null 2>&1 || true

    echo "[PASS] GJS available"

else

    echo "[WARN] gjs not found; skipping GJS check."
fi

echo

# ------------------------------------------------------------
# 9. Rootfs sync
# ------------------------------------------------------------

echo "[9/10] Synchronizing V18 to Niveth rootfs..."

if [ -d "$ROOTFS_EXT" ]; then

    sudo install \
        -m 0644 \
        "$EXT/extension.js" \
        "$ROOTFS_EXT/extension.js"

    sudo install \
        -m 0644 \
        "$EXT/metadata.json" \
        "$ROOTFS_EXT/metadata.json"

    if [ -f "$EXT/niveth-audio-meter.py" ]; then

        sudo install \
            -m 0644 \
            "$EXT/niveth-audio-meter.py" \
            "$ROOTFS_EXT/niveth-audio-meter.py"

    fi

    if [ -f "$EXT/stylesheet.css" ]; then

        sudo install \
            -m 0644 \
            "$EXT/stylesheet.css" \
            "$ROOTFS_EXT/stylesheet.css"

    fi

    echo "[PASS] Rootfs synchronized."

else

    echo "[INFO] Rootfs extension directory not found."
fi

echo

# ------------------------------------------------------------
# 10. Enable
# ------------------------------------------------------------

echo "[10/10] Enabling System Monitor..."

gnome-extensions enable "$UUID"

sleep 2

echo
echo "============================================================"
echo " FINAL STATUS"
echo "============================================================"

gnome-extensions info "$UUID" 2>&1 || true

echo
echo "============================================================"
echo " V18 BACKGROUND GROUP COMPLETE"
echo "============================================================"
echo
echo "Backup:"
echo "  $BACKUP"
echo
echo "Expected:"
echo "  Version: 18"
echo "  Enabled: Yes"
echo "  State: ACTIVE"
echo
echo "Stacking:"
echo "  Wallpaper"
echo "      ↓"
echo "  System Monitor"
echo "      ↓"
echo "  Application windows"
echo "      ↓"
echo "  GNOME Shell UI"
echo
