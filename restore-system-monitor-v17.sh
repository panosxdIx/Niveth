#!/usr/bin/env bash

set -euo pipefail

UUID="niveth-system-monitor@nivethos"

EXT="$HOME/.local/share/gnome-shell/extensions/$UUID"

ROOTFS="$HOME/Niveth/build/rootfs"
ROOTFS_EXT="$ROOTFS/usr/share/gnome-shell/extensions/$UUID"

echo "============================================================"
echo " NIVETH SYSTEM MONITOR — V17 RESTORE"
echo "============================================================"
echo
echo "Restore target:"
echo "  - visible"
echo "  - top-right"
echo "  - transparent"
echo "  - CPU/RAM working"
echo "  - AUDIO waveform working"
echo "  - bright text"
echo "  - click-through"
echo "  - no affectsStruts"
echo "  - no windowGroup stacking"
echo

# ------------------------------------------------------------
# 1. Verify
# ------------------------------------------------------------

echo "[1/9] Verifying extension..."

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
# 2. Backup current V16
# ------------------------------------------------------------

echo "[2/9] Creating backup of current state..."

BACKUP="$EXT/backup-v17-before-restore-$(date +%Y%m%d-%H%M%S)"

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

echo "[3/9] Disabling extension..."

gnome-extensions disable "$UUID" 2>/dev/null || true

sleep 1

echo "[PASS] Disabled"
echo

# ------------------------------------------------------------
# 4. Restore addChrome layout
# ------------------------------------------------------------

echo "[4/9] Restoring working GNOME Shell chrome layout..."

python3 - "$EXT/extension.js" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text()

# ----------------------------------------------------------
# Remove V16 stage/window-group block.
# ----------------------------------------------------------

stage_block = """        const stage =
            global.stage;

        const windowGroup =
            global.get_window_group();

        /*
         * Put the System Monitor directly on the stage,
         * immediately below the complete application
         * window group.
         *
         * Result:
         *
         *   background
         *       ↓
         *   System Monitor
         *       ↓
         *   window group / application windows
         *       ↓
         *   Shell UI
         */
        stage.insert_child_below(
            this._widget,
            windowGroup
        );
"""

chrome_block = """        Main.layoutManager.addChrome(
            this._widget,
            {
                trackFullscreen: true,
            }
        );
"""

if stage_block in text:

    text = text.replace(
        stage_block,
        chrome_block,
        1
    )

    print("[PASS] Removed V16 stage layer")
    print("[PASS] Restored addChrome()")

else:

    # More tolerant cleanup if formatting differs.
    if "stage.insert_child_below" in text:

        start = text.find(
            "        const stage ="
        )

        end = text.find(
            "        this._positionWidget();",
            start
        )

        if start == -1 or end == -1:

            print(
                "[FAIL] Could not locate V16 stage block."
            )

            sys.exit(1)

        text = (
            text[:start]
            +
            chrome_block
            +
            "\n"
            +
            text[end:]
        )

        print("[PASS] Replaced V16 stage block")

    elif "Main.layoutManager.addChrome" in text:

        print("[PASS] addChrome() already present")

    else:

        print(
            "[FAIL] Could not locate stacking implementation."
        )

        sys.exit(1)


# ----------------------------------------------------------
# Remove all obsolete stacking code.
# ----------------------------------------------------------

text = text.replace(
    "this._widget.set_z_position(",
    "// removed set_z_position("
)

# If a z-position block survived, remove the exact known block.
text = text.replace(
    """this._widget.set_z_position(
            -1000
        );""",
    ""
)

text = text.replace(
    "        windowGroup.add_child(\n            this._widget\n        );\n",
    ""
)

text = text.replace(
    """        windowGroup.insert_child_below(
            this._widget,
            null
        );
""",
    ""
)

text = text.replace(
    """        windowGroup.set_child_below_sibling(
            this._widget,
            windowGroup.get_first_child()
        );
""",
    ""
)

text = text.replace(
    "                affectsStruts: true,\n",
    ""
)

text = text.replace(
    "                affectsInputRegion: false,\n",
    ""
)


# ----------------------------------------------------------
# Remove stage/windowGroup remnants accidentally left behind.
# ----------------------------------------------------------

lines = text.splitlines()

cleaned = []

for line in lines:

    if line.strip() in {
        "const stage =",
        "const windowGroup =",
    }:
        continue

    cleaned.append(line)

text = "\n".join(cleaned) + "\n"


# ----------------------------------------------------------
# Ensure click-through.
# ----------------------------------------------------------

if "this._widget.set_reactive(false);" not in text:

    marker = """        this._widget.show();
"""

    replacement = """        this._widget.show();

        this._widget.set_reactive(false);
"""

    if marker not in text:

        print(
            "[FAIL] Could not restore click-through."
        )

        sys.exit(1)

    text = text.replace(
        marker,
        replacement,
        1
    )

    print("[PASS] Click-through restored")

else:

    print("[PASS] Click-through already present")


# ----------------------------------------------------------
# Restore safe normal widget cleanup.
# ----------------------------------------------------------

start_marker = "        if (this._widget) {"

start = text.find(start_marker)

if start != -1:

    end = text.find(
        "        }\n",
        start
    )

    # Find the closing section more robustly.
    if "this._widget.destroy();" in text[start:start + 1000]:

        destroy_pos = text.find(
            "            this._widget.destroy();",
            start
        )

        if destroy_pos != -1:

            close_pos = text.find(
                "        }\n",
                destroy_pos
            )

            if close_pos != -1:

                block_end = close_pos + len(
                    "        }\n"
                )

                cleanup = """        if (this._widget) {

            this._widget.destroy();

            this._widget = null;
        }
"""

                existing_prefix = text[start:block_end]

                if (
                    "get_parent()" in existing_prefix
                    or
                    "remove_child(" in existing_prefix
                ):

                    text = (
                        text[:start]
                        +
                        cleanup
                        +
                        text[block_end:]
                    )

                    print(
                        "[PASS] Restored normal widget cleanup"
                    )


path.write_text(text)
PY

echo

# ------------------------------------------------------------
# 5. Restore right position
# ------------------------------------------------------------

echo "[5/9] Restoring top-right position..."

python3 - "$EXT/extension.js" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text()

bad = """        const x =
            monitor.x +
            monitor.width -
            width;
"""

good = """        const x =
            monitor.x +
            monitor.width -
            width -
            18;
"""

if good in text:

    print("[PASS] Top-right position already correct")

elif bad in text:

    text = text.replace(
        bad,
        good,
        1
    )

    path.write_text(text)

    print("[PASS] Restored 18px right margin")

else:

    print("[FAIL] Could not identify monitor X position.")
    sys.exit(1)
PY

echo

# ------------------------------------------------------------
# 6. Metadata
# ------------------------------------------------------------

echo "[6/9] Updating metadata..."

python3 - "$EXT/metadata.json" <<'PY'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])

data = json.loads(
    path.read_text()
)

data["version"] = 17

path.write_text(
    json.dumps(
        data,
        indent=2,
        ensure_ascii=False
    ) + "\n"
)

print("[PASS] Version -> 17")
PY

echo

# ------------------------------------------------------------
# 7. Verify
# ------------------------------------------------------------

echo "[7/9] Verifying V17..."

if ! grep -Fq \
    "Main.layoutManager.addChrome" \
    "$EXT/extension.js"
then
    echo "[FAIL] addChrome() missing."
    exit 1
fi

if grep -Fq \
    "stage.insert_child_below" \
    "$EXT/extension.js"
then
    echo "[FAIL] stage layer still exists."
    exit 1
fi

if grep -Fq \
    "affectsStruts" \
    "$EXT/extension.js"
then
    echo "[FAIL] affectsStruts still exists."
    exit 1
fi

if grep -Fq \
    "set_z_position" \
    "$EXT/extension.js"
then
    echo "[FAIL] z-position code still exists."
    exit 1
fi

if grep -Fq \
    "windowGroup.add_child" \
    "$EXT/extension.js"
then
    echo "[FAIL] windowGroup insertion still exists."
    exit 1
fi

if grep -Fq \
    "windowGroup.set_child_below_sibling" \
    "$EXT/extension.js"
then
    echo "[FAIL] windowGroup stacking still exists."
    exit 1
fi

if ! grep -Fq \
    "this._widget.set_reactive(false);" \
    "$EXT/extension.js"
then
    echo "[FAIL] Click-through missing."
    exit 1
fi

if ! grep -Fq \
    "_audioHistory" \
    "$EXT/extension.js"
then
    echo "[FAIL] Audio history missing."
    exit 1
fi

if ! grep -Fq \
    "_audioBars" \
    "$EXT/extension.js"
then
    echo "[FAIL] Audio bars missing."
    exit 1
fi

if ! grep -Fq \
    "_startMetrics()" \
    "$EXT/extension.js"
then
    echo "[FAIL] Metrics missing."
    exit 1
fi

if ! grep -Fq \
    "_startAudioMeter()" \
    "$EXT/extension.js"
then
    echo "[FAIL] Audio meter missing."
    exit 1
fi

if ! grep -Fq \
    "rgba(16, 17, 29, 0.0)" \
    "$EXT/extension.js"
then
    echo "[FAIL] Transparent background missing."
    exit 1
fi

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

if [ "$VERSION" != "17" ]; then
    echo "[FAIL] Version is not 17."
    exit 1
fi

echo "[PASS] addChrome restored"
echo "[PASS] stage layer removed"
echo "[PASS] affectsStruts removed"
echo "[PASS] z-position removed"
echo "[PASS] windowGroup stacking removed"
echo "[PASS] click-through preserved"
echo "[PASS] transparent background preserved"
echo "[PASS] CPU/RAM preserved"
echo "[PASS] AUDIO preserved"
echo "[PASS] Version 17"
echo

# ------------------------------------------------------------
# 8. Rootfs synchronization
# ------------------------------------------------------------

echo "[8/9] Synchronizing V17 to Niveth rootfs..."

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
# 9. Enable
# ------------------------------------------------------------

echo "[9/9] Enabling System Monitor..."

gnome-extensions enable "$UUID"

sleep 2

echo
echo "============================================================"
echo " FINAL STATUS"
echo "============================================================"

gnome-extensions info "$UUID" 2>&1 || true

echo
echo "============================================================"
echo " V17 RESTORE COMPLETE"
echo "============================================================"
echo
echo "Backup:"
echo "  $BACKUP"
echo
echo "Expected:"
echo "  Version: 17"
echo "  Enabled: Yes"
echo "  State: ACTIVE"
echo
