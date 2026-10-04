#!/usr/bin/env bash

set -euo pipefail

# =========================================================
# NIVETH SYSTEM MONITOR — MINIMAL
# CPU + RAM + WAVEFORM
# =========================================================

EXT_ID="niveth-system-monitor@nivethos"

HOST_DIR="$HOME/.local/share/gnome-shell/extensions/$EXT_ID"

ROOTFS="$HOME/Niveth/build/rootfs"
ROOTFS_DIR="$ROOTFS/usr/share/gnome-shell/extensions/$EXT_ID"

ROOTFS_DCONF="$ROOTFS/etc/dconf/db/local.d/00-niveth-defaults"

SOURCE_DCONF_1="$HOME/Niveth/desktop/defaults/dconf/local.d/10-niveth"
SOURCE_DCONF_2="$HOME/Niveth/desktop/defaults/dconf/org-gnome-shell.dconf"

STAMP="$(date +%Y%m%d-%H%M%S)"

echo
echo "============================================================"
echo "        NIVETH SYSTEM MONITOR — MINIMAL"
echo "============================================================"
echo

# =========================================================
# 1. CREATE EXTENSION DIRECTORY
# =========================================================

echo "[1/10] Preparing extension"

mkdir -p "$HOST_DIR"

echo "[PASS] $HOST_DIR"


# =========================================================
# 2. METADATA
# =========================================================

echo
echo "[2/10] Writing metadata.json"

cat > "$HOST_DIR/metadata.json" <<'EOF'
{
  "uuid": "niveth-system-monitor@nivethos",
  "name": "Niveth System Monitor",
  "description": "Minimal live CPU and RAM monitor with waveform visualization.",
  "version": 1,
  "shell-version": [
    "50"
  ],
  "session-modes": [
    "user"
  ]
}
EOF

echo "[PASS] metadata.json"


# =========================================================
# 3. EXTENSION
# =========================================================

echo
echo "[3/10] Writing extension.js"

cat > "$HOST_DIR/extension.js" <<'JS'
import Gio from 'gi://Gio';
import GLib from 'gi://GLib';
import Clutter from 'gi://Clutter';
import St from 'gi://St';

import {Extension} from 'resource:///org/gnome/shell/extensions/extension.js';
import * as Main from 'resource:///org/gnome/shell/ui/main.js';


const WIDGET_WIDTH = 330;
const WIDGET_HEIGHT = 116;

const TOP_OFFSET = 82;
const RIGHT_OFFSET = 26;

const WAVE_COUNT = 34;

const CPU_COLOR = '#69D8FF';
const RAM_COLOR = '#C185FF';


export default class NivethSystemMonitorExtension extends Extension {

    enable() {
        this._settings = null;
        this._settingsChangedId = 0;

        this._timerId = 0;
        this._monitorChangedId = 0;

        this._previousCpu = null;

        this._cpuHistory = [];
        this._ramHistory = [];

        this._buildWidget();
        this._loadTheme();

        this._updateMetrics();

        this._timerId =
            GLib.timeout_add_seconds(
                GLib.PRIORITY_DEFAULT,
                1,
                () => {
                    this._updateMetrics();
                    return GLib.SOURCE_CONTINUE;
                }
            );

        this._monitorChangedId =
            Main.layoutManager.connect(
                'monitors-changed',
                () => this._updatePosition()
            );

        log('NIVETH SYSTEM MONITOR: minimal enabled');
    }


    disable() {

        if (this._timerId) {
            GLib.source_remove(
                this._timerId
            );

            this._timerId = 0;
        }

        if (this._monitorChangedId) {
            try {
                Main.layoutManager.disconnect(
                    this._monitorChangedId
                );
            } catch (error) {
            }

            this._monitorChangedId = 0;
        }

        if (
            this._settings &&
            this._settingsChangedId
        ) {
            try {
                this._settings.disconnect(
                    this._settingsChangedId
                );
            } catch (error) {
            }

            this._settingsChangedId = 0;
        }

        this._settings = null;

        this._widget?.destroy();

        this._widget = null;
        this._cpuValue = null;
        this._ramValue = null;
        this._cpuLine = null;
        this._ramLine = null;

        this._cpuWaveBars = [];
        this._ramWaveBars = [];

        log('NIVETH SYSTEM MONITOR: minimal disabled');
    }


    _buildWidget() {

        this._widget = new St.BoxLayout({
            vertical: true,

            style_class:
                'niveth-system-monitor',

            x_expand: false,
            y_expand: false,
        });

        /*
         * Small title.
         */
        this._title = new St.Label({
            text: 'NIVETH SYSTEM',

            style_class:
                'niveth-system-title',

            x_align:
                Clutter.ActorAlign.START,
        });

        this._widget.add_child(
            this._title
        );


        /*
         * CPU
         */
        const cpu = this._buildMetricRow(
            'CPU'
        );

        this._cpuValue = cpu.value;
        this._cpuLine = cpu.line;
        this._cpuWaveBars = cpu.waveBars;

        this._widget.add_child(
            cpu.row
        );


        /*
         * RAM
         */
        const ram = this._buildMetricRow(
            'RAM'
        );

        this._ramValue = ram.value;
        this._ramLine = ram.line;
        this._ramWaveBars = ram.waveBars;

        this._widget.add_child(
            ram.row
        );


        Main.uiGroup.add_child(
            this._widget
        );

        this._updatePosition();
    }


    _buildMetricRow(label) {

        const row = new St.BoxLayout({
            vertical: true,

            style_class:
                'niveth-system-metric',

            x_expand: true,
        });


        /*
         * Text line:
         *
         * CPU                         24%
         */
        const header =
            new St.BoxLayout({
                vertical: false,

                style_class:
                    'niveth-system-header',
            });


        const labelActor =
            new St.Label({
                text: label,

                style_class:
                    'niveth-system-label',
            });

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
         * Thin activity line.
         */
        const line =
            new St.Widget({
                style_class:
                    label === 'CPU'
                        ? 'niveth-system-line cpu'
                        : 'niveth-system-line ram',

                x_expand: true,
            });

        row.add_child(
            line
        );


        /*
         * Waveform.
         */
        const wave =
            new St.BoxLayout({
                vertical: false,

                style_class:
                    'niveth-system-wave',

                x_expand: true,
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
                        label === 'CPU'
                            ? 'niveth-system-wave-bar cpu'
                            : 'niveth-system-wave-bar ram',
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
    }


    _loadTheme() {

        try {

            this._settings =
                Gio.Settings.new(
                    'org.gnome.desktop.interface'
                );

            this._settingsChangedId =
                this._settings.connect(
                    'changed::color-scheme',
                    () => this._updateTheme()
                );

        } catch (error) {

            this._settings = null;
        }


        this._updateTheme();
    }


    _updateTheme() {

        if (!this._widget)
            return;


        let scheme =
            'prefer-dark';


        try {

            scheme =
                this._settings?.get_string(
                    'color-scheme'
                ) ??
                'prefer-dark';

        } catch (error) {

            scheme =
                'prefer-dark';
        }


        const dark =
            scheme === 'prefer-dark';


        this._widget.remove_style_class_name(
            'dark'
        );

        this._widget.remove_style_class_name(
            'light'
        );


        this._widget.add_style_class_name(
            dark
                ? 'dark'
                : 'light'
        );
    }


    _updatePosition() {

        if (!this._widget)
            return;


        const monitor =
            Main.layoutManager.primaryMonitor;


        if (!monitor)
            return;


        this._widget.set_size(
            WIDGET_WIDTH,
            WIDGET_HEIGHT
        );


        this._widget.set_position(

            monitor.x +
                monitor.width -
                WIDGET_WIDTH -
                RIGHT_OFFSET,

            monitor.y +
                TOP_OFFSET
        );
    }


    _updateMetrics() {

        const cpu =
            this._readCpu();


        const ram =
            this._readRam();


        if (cpu !== null) {

            this._cpuValue.text =
                `${Math.round(cpu)}%`;


            this._setActivityLine(
                this._cpuLine,
                cpu
            );


            this._cpuHistory.push(
                cpu
            );


            if (
                this._cpuHistory.length >
                WAVE_COUNT
            ) {
                this._cpuHistory.shift();
            }


            this._updateWaveform(
                this._cpuWaveBars,
                this._cpuHistory
            );
        }


        if (ram !== null) {

            this._ramValue.text =
                `${ram.used.toFixed(1)} / ${ram.total.toFixed(1)} GB`;


            this._setActivityLine(
                this._ramLine,
                ram.percent
            );


            this._ramHistory.push(
                ram.percent
            );


            if (
                this._ramHistory.length >
                WAVE_COUNT
            ) {
                this._ramHistory.shift();
            }


            this._updateWaveform(
                this._ramWaveBars,
                this._ramHistory
            );
        }
    }


    _readCpu() {

        try {

            const [
                success,
                contents,
            ] =
                GLib.file_get_contents(
                    '/proc/stat'
                );


            if (!success)
                return null;


            const text =
                new TextDecoder()
                    .decode(contents);


            const line =
                text
                    .split('\n')
                    .find(
                        value =>
                            value.startsWith(
                                'cpu '
                            )
                    );


            if (!line)
                return null;


            const values =
                line
                    .trim()
                    .split(/\s+/)
                    .slice(1)
                    .map(Number);


            if (
                values.length < 5
            )
                return null;


            const user =
                values[0];

            const nice =
                values[1];

            const system =
                values[2];

            const idle =
                values[3];

            const iowait =
                values[4];

            const irq =
                values[5] ?? 0;

            const softirq =
                values[6] ?? 0;

            const steal =
                values[7] ?? 0;


            const idleTotal =
                idle +
                iowait;


            const total =
                user +
                nice +
                system +
                idle +
                iowait +
                irq +
                softirq +
                steal;


            if (!this._previousCpu) {

                this._previousCpu = {
                    idle:
                        idleTotal,

                    total,
                };

                return 0;
            }


            const idleDelta =
                idleTotal -
                this._previousCpu.idle;


            const totalDelta =
                total -
                this._previousCpu.total;


            this._previousCpu = {
                idle:
                    idleTotal,

                total,
            };


            if (
                totalDelta <= 0
            )
                return 0;


            const usage =
                100 *
                (
                    1 -
                    idleDelta /
                    totalDelta
                );


            return Math.max(
                0,
                Math.min(
                    100,
                    usage
                )
            );

        } catch (error) {

            log(
                `NIVETH SYSTEM MONITOR CPU: ${error}`
            );

            return null;
        }
    }


    _readRam() {

        try {

            const [
                success,
                contents,
            ] =
                GLib.file_get_contents(
                    '/proc/meminfo'
                );


            if (!success)
                return null;


            const text =
                new TextDecoder()
                    .decode(contents);


            const totalMatch =
                text.match(
                    /^MemTotal:\s+(\d+)\s+kB/m
                );


            const availableMatch =
                text.match(
                    /^MemAvailable:\s+(\d+)\s+kB/m
                );


            if (
                !totalMatch ||
                !availableMatch
            )
                return null;


            const totalKb =
                Number(
                    totalMatch[1]
                );


            const availableKb =
                Number(
                    availableMatch[1]
                );


            const usedKb =
                Math.max(
                    0,
                    totalKb -
                    availableKb
                );


            const totalGb =
                totalKb /
                1024 /
                1024;


            const usedGb =
                usedKb /
                1024 /
                1024;


            const percent =
                (
                    usedKb /
                    totalKb
                ) *
                100;


            return {

                total:
                    totalGb,

                used:
                    usedGb,

                percent:
                    Math.max(
                        0,
                        Math.min(
                            100,
                            percent
                        )
                    ),
            };

        } catch (error) {

            log(
                `NIVETH SYSTEM MONITOR RAM: ${error}`
            );

            return null;
        }
    }


    _setActivityLine(
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


        const width =
            Math.max(
                1,
                Math.round(
                    (
                        WIDGET_WIDTH -
                        32
                    ) *
                    safe /
                    100
                )
            );


        line.set_width(
            width
        );
    }


    _updateWaveform(
        bars,
        history
    ) {

        if (
            !bars ||
            bars.length === 0
        )
            return;


        const now =
            Date.now() /
            1000;


        for (
            let i = 0;
            i < bars.length;
            i++
        ) {

            const historyIndex =
                history.length -
                bars.length +
                i;


            let value =
                historyIndex >= 0
                    ? history[historyIndex]
                    : (
                        history.length
                            ? history[history.length - 1]
                            : 0
                    );


            if (
                !Number.isFinite(
                    value
                )
            ) {
                value = 0;
            }


            /*
             * Calm movement:
             * activity history + tiny wave.
             */
            const motion =
                (
                    Math.sin(
                        now * 2.2 +
                        i * 0.72
                    ) +
                    1
                ) /
                2;


            const normalized =
                Math.max(
                    0.08,
                    Math.min(
                        1,
                        (
                            value /
                            100
                        ) * 0.72 +
                        motion * 0.20
                    )
                );


            const height =
                Math.max(
                    5,
                    Math.round(
                        5 +
                        normalized *
                        25
                    )
                );


            bars[i].set_height(
                height
            );
        }
    }
}
JS

echo "[PASS] extension.js"


# =========================================================
# 4. COMPLETE MINIMAL CSS
# =========================================================

echo
echo "[4/10] Writing stylesheet.css"

cat > "$HOST_DIR/stylesheet.css" <<'CSS'
/* =========================================================
 * NIVETH SYSTEM MONITOR
 * Minimal CPU / RAM / Waveform
 * ========================================================= */

.niveth-system-monitor {

    padding: 7px 10px 8px 10px;

    spacing: 5px;

    border-radius: 18px;

    border-width: 1px;
    border-style: solid;

    background-color:
        rgba(18, 24, 48, 0.34);

    border-color:
        rgba(150, 185, 235, 0.16);

    box-shadow:
        0 10px 28px
            rgba(4, 7, 20, 0.18),

        0 0 18px
            rgba(100, 160, 255, 0.06);
}


/* =========================================================
 * DARK
 * ========================================================= */

.niveth-system-monitor.dark {

    background-color:
        rgba(18, 24, 48, 0.34);

    border-color:
        rgba(150, 185, 235, 0.18);
}


/* =========================================================
 * LIGHT
 * ========================================================= */

.niveth-system-monitor.light {

    background-color:
        rgba(48, 43, 92, 0.28);

    border-color:
        rgba(140, 205, 255, 0.22);
}


/* =========================================================
 * TITLE
 * ========================================================= */

.niveth-system-title {

    font-size: 9px;

    font-weight: 500;

    letter-spacing: 2px;

    color:
        rgba(232, 238, 255, 0.70);

    padding-left: 1px;

    padding-bottom: 2px;
}


/* =========================================================
 * METRIC ROW
 * ========================================================= */

.niveth-system-metric {

    spacing: 2px;
}


/* =========================================================
 * HEADER
 * ========================================================= */

.niveth-system-header {

    spacing: 5px;

    min-height: 17px;
}


/* =========================================================
 * LABEL
 * ========================================================= */

.niveth-system-label {

    font-size: 11px;

    font-weight: 500;

    letter-spacing: 1px;

    color:
        rgba(242, 244, 255, 0.84);
}


/* =========================================================
 * VALUES
 * ========================================================= */

.niveth-system-value {

    font-size: 10px;

    font-weight: 500;

    color:
        rgba(220, 228, 255, 0.78);
}


/* =========================================================
 * ACTIVITY LINES
 * ========================================================= */

.niveth-system-line {

    height: 2px;

    border-radius: 99px;

    min-width: 2px;
}


.niveth-system-line.cpu {

    background-color:
        #69D8FF;

    box-shadow:
        0 0 6px
        rgba(105, 216, 255, 0.40);
}


.niveth-system-line.ram {

    background-color:
        #C185FF;

    box-shadow:
        0 0 6px
        rgba(193, 133, 255, 0.35);
}


/* =========================================================
 * WAVEFORM
 * ========================================================= */

.niveth-system-wave {

    spacing: 2px;

    height: 29px;

    padding-top: 2px;
}


.niveth-system-wave-bar {

    width: 3px;

    min-height: 4px;

    border-radius:
        3px 3px 1px 1px;
}


.niveth-system-wave-bar.cpu {

    background-color:
        #69D8FF;

    box-shadow:
        0 0 5px
        rgba(105, 216, 255, 0.35);
}


.niveth-system-wave-bar.ram {

    background-color:
        #C185FF;

    box-shadow:
        0 0 5px
        rgba(193, 133, 255, 0.30);
}


/* =========================================================
 * LIGHT VARIANT
 * ========================================================= */

.niveth-system-monitor.light
.niveth-system-label {

    color:
        rgba(246, 243, 255, 0.88);
}


.niveth-system-monitor.light
.niveth-system-value {

    color:
        rgba(231, 226, 255, 0.86);
}
CSS

echo "[PASS] stylesheet.css"


# =========================================================
# 5. UPDATE SOURCE DCONF
# =========================================================

echo
echo "[5/10] Updating Niveth source dconf"

python3 \
    "$SOURCE_DCONF_1" \
    "$SOURCE_DCONF_2" <<'PY'
from pathlib import Path
import re
import ast
import sys

EXT = "niveth-system-monitor@nivethos"

for raw in sys.argv[1:]:
    path = Path(raw)

    if not path.is_file():
        continue

    text = path.read_text(
        encoding="utf-8"
    )

    match = re.search(
        r"^enabled-extensions=(\[.*\])$",
        text,
        re.MULTILINE
    )

    if not match:
        print(
            f"[INFO] No enabled-extensions in {path}"
        )
        continue

    enabled = ast.literal_eval(
        match.group(1)
    )

    if EXT not in enabled:
        enabled.append(EXT)

        line =
            "enabled-extensions=" +
            repr(enabled)

        text = re.sub(
            r"^enabled-extensions=\[.*\]$",
            line,
            text,
            count=1,
            flags=re.MULTILINE
        )

        path.write_text(
            text,
            encoding="utf-8"
        )

        print(
            f"[PASS] Added {EXT} to {path}"
        )

    else:
        print(
            f"[INFO] {EXT} already present in {path}"
        )
PY


# =========================================================
# 6. INSTALL ROOTFS
# =========================================================

echo
echo "[6/10] Installing into Niveth rootfs"

if [ ! -d "$ROOTFS" ]; then
    echo "[FAIL] Rootfs not found:"
    echo "$ROOTFS"
    exit 1
fi

sudo mkdir -p \
    "$ROOTFS_DIR"

sudo install -m 0644 \
    "$HOST_DIR/metadata.json" \
    "$ROOTFS_DIR/metadata.json"

sudo install -m 0644 \
    "$HOST_DIR/extension.js" \
    "$ROOTFS_DIR/extension.js"

sudo install -m 0644 \
    "$HOST_DIR/stylesheet.css" \
    "$ROOTFS_DIR/stylesheet.css"

echo "[PASS] Rootfs extension installed"


# =========================================================
# 7. UPDATE ROOTFS DCONF
# =========================================================

echo
echo "[7/10] Updating rootfs dconf"

if [ ! -f "$ROOTFS_DCONF" ]; then

    echo "[FAIL] Rootfs dconf missing:"
    echo "$ROOTFS_DCONF"
    exit 1

fi

sudo cp \
    "$ROOTFS_DCONF" \
    "$ROOTFS_DCONF.backup-before-system-monitor-$STAMP"


sudo python3 \
    - "$ROOTFS_DCONF" "$EXT_ID" <<'PY'
from pathlib import Path
import re
import ast
import sys

path = Path(sys.argv[1])
extension = sys.argv[2]

text = path.read_text(
    encoding="utf-8"
)

match = re.search(
    r"^enabled-extensions=(\[.*\])$",
    text,
    re.MULTILINE
)

if not match:
    raise SystemExit(
        "ERROR: enabled-extensions not found."
    )

enabled = ast.literal_eval(
    match.group(1)
)

if extension not in enabled:
    enabled.append(extension)

line = (
    "enabled-extensions=" +
    repr(enabled)
)

text = re.sub(
    r"^enabled-extensions=\[.*\]$",
    line,
    text,
    count=1,
    flags=re.MULTILINE
)

path.write_text(
    text,
    encoding="utf-8"
)

print(
    "Rootfs enabled-extensions updated."
)

print(line)
PY


# =========================================================
# 8. REBUILD DCONF
# =========================================================

echo
echo "[8/10] Rebuilding compiled dconf"

sudo chroot \
    "$ROOTFS" \
    /usr/bin/dconf update

echo "[PASS] dconf updated"


# =========================================================
# 9. VERIFY SOURCE ↔ ROOTFS
# =========================================================

echo
echo "[9/10] Verifying source/rootfs"

for file in \
    metadata.json \
    extension.js \
    stylesheet.css
do

    SOURCE_FILE="$HOST_DIR/$file"
    ROOT_FILE="$ROOTFS_DIR/$file"

    SOURCE_HASH="$(
        sha256sum "$SOURCE_FILE" |
        awk '{print $1}'
    )"

    ROOT_HASH="$(
        sudo sha256sum "$ROOT_FILE" |
        awk '{print $1}'
    )"

    echo
    echo "$file"
    echo "  SOURCE : $SOURCE_HASH"
    echo "  ROOTFS : $ROOT_HASH"

    if [ "$SOURCE_HASH" != "$ROOT_HASH" ]; then

        echo "[FAIL] $file mismatch"
        exit 1

    fi

    echo "[PASS] identical"

done


sudo grep -q \
    "$EXT_ID" \
    "$ROOTFS_DCONF"

echo
echo "[PASS] System Monitor is enabled in rootfs dconf"


# =========================================================
# 10. ENABLE LIVE EXTENSION
# =========================================================

echo
echo "[10/10] Enabling live System Monitor"

gnome-extensions disable \
    "$EXT_ID" \
    2>/dev/null || true

sleep 2

gnome-extensions enable \
    "$EXT_ID"

sleep 4

echo
echo "Extension status:"

gnome-extensions info \
    "$EXT_ID" \
    2>&1 |
    grep -E \
        "Name:|Enabled:|State:|Path:" || true


echo
echo "============================================================"
echo "        NIVETH SYSTEM MONITOR READY"
echo "============================================================"
echo
echo "STYLE:"
echo "  Minimal"
echo "  Thin typography"
echo "  CPU cyan waveform"
echo "  RAM violet waveform"
echo "  Subtle glass"
echo
echo "LIVE:"
echo "  CPU: real /proc/stat data"
echo "  RAM: real /proc/meminfo data"
echo
echo "ROOTFS:"
echo "  Installed"
echo "  SHA256 verified"
echo "  Default enabled"
echo
