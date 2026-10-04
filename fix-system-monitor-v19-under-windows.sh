#!/usr/bin/env bash

set -euo pipefail

UUID="niveth-system-monitor@nivethos"

EXT="$HOME/.local/share/gnome-shell/extensions/$UUID"

ROOTFS="$HOME/Niveth/build/rootfs"
ROOTFS_EXT="$ROOTFS/usr/share/gnome-shell/extensions/$UUID"

echo "============================================================"
echo " NIVETH SYSTEM MONITOR — V19"
echo "============================================================"
echo
echo "Goal:"
echo "  Wallpaper"
echo "      ↓"
echo "  System Monitor"
echo "      ↓"
echo "  Application windows"
echo
echo "Architecture:"
echo "  GNOME _backgroundGroup"
echo "        ↓"
echo "  dedicated container"
echo "        ↓"
echo "  System Monitor"
echo
echo "Preserve:"
echo "  - top-right position"
echo "  - transparent monitor"
echo "  - bright text"
echo "  - CPU/RAM"
echo "  - AUDIO waveform"
echo "  - click-through"
echo

# ------------------------------------------------------------
# 1. Verify
# ------------------------------------------------------------

echo "[1/10] Verifying current extension..."

if [ ! -f "$EXT/extension.js" ]; then
    echo "[FAIL] extension.js not found:"
    echo "  $EXT/extension.js"
    exit 1
fi

if [ ! -f "$EXT/metadata.json" ]; then
    echo "[FAIL] metadata.json not found."
    exit 1
fi

echo "[PASS] Extension files found"
echo

# ------------------------------------------------------------
# 2. Verify V17
# ------------------------------------------------------------

echo "[2/10] Checking current version..."

CURRENT_VERSION="$(
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

echo "Current version: $CURRENT_VERSION"

if [ "$CURRENT_VERSION" != "17" ]; then
    echo
    echo "[FAIL] V19 expects the known-good V17 base."
    echo "       Current version: $CURRENT_VERSION"
    echo
    echo "       Nothing has been modified."
    exit 1
fi

echo "[PASS] V17 base confirmed"
echo

# ------------------------------------------------------------
# 3. Backup
# ------------------------------------------------------------

echo "[3/10] Creating backup..."

BACKUP="$EXT/backup-v19-before-install-$(date +%Y%m%d-%H%M%S)"

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
# 4. Disable
# ------------------------------------------------------------

echo "[4/10] Disabling System Monitor..."

gnome-extensions disable "$UUID" 2>/dev/null || true

sleep 1

echo "[PASS] Disabled"
echo

# ------------------------------------------------------------
# 5. Install V19 architecture
# ------------------------------------------------------------

echo "[5/10] Installing V19 background container..."

python3 - "$EXT/extension.js" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text()

# ----------------------------------------------------------
# A. Add background container state.
# ----------------------------------------------------------

old_state = """        this._widget = null;

        this._cpuFill = null;
"""

new_state = """        this._widget = null;
        this._backgroundContainer = null;

        this._cpuFill = null;
"""

if old_state not in text:
    print("[FAIL] Could not find V17 widget state block.")
    sys.exit(1)

text = text.replace(
    old_state,
    new_state,
    1
)

# ----------------------------------------------------------
# B. Replace V17 addChrome() with background container.
# ----------------------------------------------------------

old_chrome = """        Main.layoutManager.addChrome(
            this._widget,
            {
                trackFullscreen: true,
            }
        );
"""

new_background = """        /*
         * GNOME Shell keeps _backgroundGroup below the
         * normal application window actors.
         *
         * The extra container gives Clutter an actual
         * painted allocation while keeping the monitor
         * itself transparent.
         */
        this._backgroundContainer =
            new St.Widget({
                width: 328,
                height: 180,

                reactive: false,

                style:
                    'width: 328px;' +
                    'height: 180px;' +
                    'min-width: 328px;' +
                    'min-height: 180px;' +

                    /*
                     * Tiny paint value used only to force
                     * a real allocation in BackgroundGroup.
                     */
                    'background-color: rgba(0,0,0,0.01);'
            });

        const backgroundGroup =
            Main.layoutManager._backgroundGroup;

        if (!backgroundGroup) {
            throw new Error(
                '[niveth-system-monitor@nivethos] ' +
                'GNOME background group unavailable'
            );
        }

        backgroundGroup.add_child(
            this._backgroundContainer
        );

        this._backgroundContainer.add_child(
            this._widget
        );

        this._widget.set_position(
            0,
            0
        );

        this._widget.set_size(
            328,
            180
        );

        this._widget.set_reactive(
            false
        );
"""

if old_chrome not in text:
    print("[FAIL] Expected V17 addChrome() block was not found.")
    sys.exit(1)

text = text.replace(
    old_chrome,
    new_background,
    1
)

# ----------------------------------------------------------
# C. Replace _positionWidget() body.
# ----------------------------------------------------------

method_start = text.find(
    "    _positionWidget() {"
)

if method_start == -1:
    print("[FAIL] _positionWidget() not found.")
    sys.exit(1)

method_end = text.find(
    "    _startMetrics() {",
    method_start
)

if method_end == -1:
    print("[FAIL] End of _positionWidget() not found.")
    sys.exit(1)

new_position_method = """    _positionWidget() {

        if (!this._backgroundContainer)
            return;

        const monitor =
            Main.layoutManager.primaryMonitor;

        if (!monitor)
            return;

        const width = 328;
        const height = 180;

        const x =
            monitor.x +
            monitor.width -
            width -
            18;

        const y =
            monitor.y +
            52;

        this._backgroundContainer.set_size(
            width,
            height
        );

        this._backgroundContainer.set_position(
            x,
            y
        );

        this._widget.set_position(
            0,
            0
        );

        this._widget.set_size(
            width,
            height
        );

        this._backgroundContainer.show();
        this._widget.show();
    }


"""

text = (
    text[:method_start]
    +
    new_position_method
    +
    text[method_end:]
)

# ----------------------------------------------------------
# D. Replace disable() widget cleanup.
# ----------------------------------------------------------

cleanup_start = text.find(
    "        if (this._widget) {"
)

if cleanup_start == -1:
    print("[FAIL] disable() widget cleanup not found.")
    sys.exit(1)

cleanup_end = text.find(
    "        }\n",
    cleanup_start
)

# Find the actual widget destroy statement and close its block.
destroy_pos = text.find(
    "this._widget.destroy();",
    cleanup_start
)

if destroy_pos == -1:
    print("[FAIL] widget.destroy() not found.")
    sys.exit(1)

close_pos = text.find(
    "        }\n",
    destroy_pos
)

if close_pos == -1:
    print("[FAIL] widget cleanup closing block not found.")
    sys.exit(1)

close_end = close_pos + len("        }\n")

old_cleanup = text[cleanup_start:close_end]

new_cleanup = """        if (this._backgroundContainer) {

            try {

                const parent =
                    this._backgroundContainer.get_parent();

                if (parent) {

                    parent.remove_child(
                        this._backgroundContainer
                    );
                }

            } catch (error) {
            }

            this._backgroundContainer.destroy();

            this._backgroundContainer = null;
        }

        if (this._widget) {

            this._widget.destroy();

            this._widget = null;
        }
"""

text = (
    text[:cleanup_start]
    +
    new_cleanup
    +
    text[close_end:]
)

path.write_text(text)

print("[PASS] Background container created")
print("[PASS] _backgroundGroup used")
print("[PASS] Monitor kept inside dedicated container")
print("[PASS] Positioning moved to container")
print("[PASS] Safe cleanup installed")
PY

echo

# ------------------------------------------------------------
# 6. Metadata
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

data["version"] = 19

path.write_text(
    json.dumps(
        data,
        indent=2,
        ensure_ascii=False
    ) + "\n"
)

print("[PASS] Version -> 19")
PY

echo

# ------------------------------------------------------------
# 7. Source verification
# ------------------------------------------------------------

echo "[7/10] Verifying V19 source..."

require() {

    local label="$1"
    local pattern="$2"

    if grep -Fq "$pattern" "$EXT/extension.js"; then
        echo "[PASS] $label"
    else
        echo "[FAIL] Missing: $label"
        exit 1
    fi
}

forbid() {

    local label="$1"
    local pattern="$2"

    if grep -Fq "$pattern" "$EXT/extension.js"; then
        echo "[FAIL] Forbidden: $label"
        exit 1
    else
        echo "[PASS] Removed: $label"
    fi
}

require \
    "background container" \
    "this._backgroundContainer"

require \
    "_backgroundGroup" \
    "Main.layoutManager._backgroundGroup"

require \
    "container added to background group" \
    "backgroundGroup.add_child"

require \
    "monitor inside container" \
    "this._backgroundContainer.add_child"

require \
    "container positioning" \
    "this._backgroundContainer.set_position"

require \
    "click-through" \
    "this._widget.set_reactive"

require \
    "CPU/RAM" \
    "_startMetrics()"

require \
    "AUDIO" \
    "_startAudioMeter()"

require \
    "audio history" \
    "_audioHistory"

require \
    "audio bars" \
    "_audioBars"

require \
    "transparent monitor" \
    "rgba(16, 17, 29, 0.0)"

forbid \
    "addChrome()" \
    "Main.layoutManager.addChrome"

forbid \
    "affectsStruts" \
    "affectsStruts"

forbid \
    "stage stacking" \
    "stage.insert_child_below"

forbid \
    "window group stacking" \
    "windowGroup.insert_child_below"

forbid \
    "z-position hack" \
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

if [ "$VERSION" != "19" ]; then
    echo "[FAIL] Metadata version is not 19."
    exit 1
fi

echo "[PASS] Version 19"
echo

# ------------------------------------------------------------
# 8. Rootfs sync
# ------------------------------------------------------------

echo "[8/10] Synchronizing V19 to Niveth rootfs..."

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

echo "[9/10] Enabling V19..."

gnome-extensions enable "$UUID"

sleep 2

echo "[PASS] Enabled"
echo

# ------------------------------------------------------------
# 10. Final status
# ------------------------------------------------------------

echo "============================================================"
echo " FINAL STATUS"
echo "============================================================"

gnome-extensions info "$UUID" 2>&1 || true

echo
echo "============================================================"
echo " V19 INSTALL COMPLETE"
echo "============================================================"
echo
echo "Backup:"
echo "  $BACKUP"
echo
echo "Expected:"
echo "  Version: 19"
echo "  Enabled: Yes"
echo "  State: ACTIVE"
echo
echo "Visual test:"
echo "  1. Open a normal application window."
echo "  2. Move/maximize it over the monitor area."
echo "  3. The application window should cover the monitor."
echo "  4. Move it away and the monitor should appear again."
echo
