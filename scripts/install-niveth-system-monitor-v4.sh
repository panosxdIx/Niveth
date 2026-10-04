#!/usr/bin/env bash

set -euo pipefail

# ============================================================
# NIVETH SYSTEM MONITOR — V4 COMPLETE
#
# FEATURES
#   CPU percentage
#   RAM percentage
#   CPU/RAM fixed percentage bars
#   System audio-reactive cyan waveform
#   RAM violet waveform
#   Minimal vaporwave glass
#   Full rootfs synchronization
# ============================================================

EXT_ID="niveth-system-monitor@nivethos"

HOST_DIR="$HOME/.local/share/gnome-shell/extensions/$EXT_ID"

ROOTFS="$HOME/Niveth/build/rootfs"
ROOTFS_DIR="$ROOTFS/usr/share/gnome-shell/extensions/$EXT_ID"

ROOTFS_DCONF="$ROOTFS/etc/dconf/db/local.d/00-niveth-defaults"

SOURCE_DCONF_1="$HOME/Niveth/desktop/defaults/dconf/local.d/10-niveth"
SOURCE_DCONF_2="$HOME/Niveth/desktop/defaults/dconf/org-gnome-shell.dconf"

COMPONENTS="$HOME/Niveth/desktop/niveth-components.txt"

STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP_DIR="$HOST_DIR/backups-v4-$STAMP"

echo
echo "============================================================"
echo " NIVETH SYSTEM MONITOR — V4 COMPLETE"
echo "============================================================"
echo


# ============================================================
# 1. VERIFY
# ============================================================

echo "[1/11] Verifying environment"

if [ ! -d "$HOST_DIR" ]; then
    mkdir -p "$HOST_DIR"
fi

if [ ! -d "$ROOTFS" ]; then
    echo "[FAIL] Rootfs not found:"
    echo "       $ROOTFS"
    exit 1
fi

echo "[PASS] Live extension directory"
echo "[PASS] Niveth rootfs"


# ============================================================
# 2. BACKUP
# ============================================================

echo
echo "[2/11] Creating backups"

mkdir -p "$BACKUP_DIR"

for file in \
    metadata.json \
    extension.js \
    stylesheet.css \
    niveth-audio-meter.py
do
    if [ -f "$HOST_DIR/$file" ]; then
        cp \
            "$HOST_DIR/$file" \
            "$BACKUP_DIR/$file"
    fi
done

echo "[PASS] Backup:"
echo "       $BACKUP_DIR"


# ============================================================
# 3. METADATA
# ============================================================

echo
echo "[3/11] Writing metadata"

cat > "$HOST_DIR/metadata.json" <<'EOF'
{
  "uuid": "niveth-system-monitor@nivethos",
  "name": "Niveth System Monitor",
  "description": "Minimal CPU, RAM and audio-reactive system monitor.",
  "version": 4,
  "shell-version": [
    "50"
  ],
  "session-modes": [
    "user"
  ]
}
EOF

echo "[PASS] metadata.json"


# ============================================================
# 4. AUDIO METER
# ============================================================

echo
echo "[4/11] Writing audio meter"

cat > "$HOST_DIR/niveth-audio-meter.py" <<'PY'
#!/usr/bin/env python3

import math
import struct
import subprocess
import sys


RATE = 16000
CHANNELS = 1
BYTES_PER_SAMPLE = 2
FRAME_COUNT = 1280

MIN_DB = -52.0
MAX_DB = -4.0


def clamp(value, low, high):
    return max(low, min(high, value))


def get_default_sink():
    try:
        result = subprocess.run(
            ["pactl", "get-default-sink"],
            capture_output=True,
            text=True,
            timeout=2,
            check=True,
        )

        sink = result.stdout.strip()

        if sink:
            return sink

    except Exception:
        pass

    return "@DEFAULT_SINK@"


def calculate_level(raw):
    if not raw:
        return 0.0

    sample_count = len(raw) // BYTES_PER_SAMPLE

    if sample_count <= 0:
        return 0.0

    raw = raw[
        :sample_count * BYTES_PER_SAMPLE
    ]

    samples = struct.unpack(
        "<{}h".format(sample_count),
        raw,
    )

    square_sum = 0.0

    for sample in samples:

        normalized = sample / 32768.0

        square_sum += (
            normalized *
            normalized
        )

    rms = math.sqrt(
        square_sum /
        sample_count
    )

    if rms <= 0.000001:
        return 0.0

    db = 20.0 * math.log10(rms)

    level = (
        (db - MIN_DB) /
        (MAX_DB - MIN_DB)
    ) * 100.0

    return clamp(
        level,
        0.0,
        100.0
    )


def main():

    sink = get_default_sink()

    if sink == "@DEFAULT_SINK@":
        monitor = "@DEFAULT_SINK@.monitor"
    else:
        monitor = sink + ".monitor"

    command = [
        "parecord",
        "--raw",
        "--format=s16le",
        "--rate={}".format(RATE),
        "--channels={}".format(CHANNELS),
        "--latency-msec=80",
        "--device={}".format(monitor),
    ]

    try:

        process = subprocess.Popen(
            command,
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            bufsize=0,
        )

    except Exception:

        print("0", flush=True)

        return 1


    try:

        while True:

            raw =
                process.stdout.read(
                    FRAME_COUNT *
                    BYTES_PER_SAMPLE
                )

            if not raw:
                break

            level =
                calculate_level(
                    raw
                )

            print(
                "{:.2f}".format(level),
                flush=True
            )

    except (
        BrokenPipeError,
        KeyboardInterrupt,
    ):
        pass

    finally:

        try:
            process.terminate()
        except Exception:
            pass


    return 0


if __name__ == "__main__":
    sys.exit(main())
PY

chmod +x \
    "$HOST_DIR/niveth-audio-meter.py"

python3 -m py_compile \
    "$HOST_DIR/niveth-audio-meter.py"

echo "[PASS] Audio helper syntax"


# ============================================================
# 5. COMPLETE EXTENSION.JS
# ============================================================

echo
echo "[5/11] Writing complete extension.js"

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

const TRACK_WIDTH = 308;

const WAVE_COUNT = 34;


export default class NivethSystemMonitorExtension
    extends Extension {


    enable() {

        this._settings = null;
        this._settingsChangedId = 0;

        this._timerId = 0;
        this._monitorChangedId = 0;

        this._audioProcess = null;
        this._audioReader = null;

        this._audioConnected = false;
        this._audioLevel = 0;

        this._previousCpu = null;

        this._cpuHistory = [];
        this._ramHistory = [];
        this._audioHistory = [];

        for (
            let i = 0;
            i < WAVE_COUNT;
            i++
        ) {
            this._audioHistory.push(0);
        }

        this._buildWidget();
        this._loadTheme();

        this._updateMetrics();
        this._startAudioMeter();

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

        log(
            'NIVETH SYSTEM MONITOR V4: enabled'
        );
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

        this._stopAudioMeter();


        if (this._widget) {

            try {
                this._widget.destroy();
            } catch (error) {
            }

            this._widget = null;
        }


        this._cpuValue = null;
        this._ramValue = null;

        this._cpuLine = null;
        this._ramLine = null;

        this._cpuWaveBars = [];
        this._ramWaveBars = [];

        this._cpuHistory = [];
        this._ramHistory = [];
        this._audioHistory = [];


        log(
            'NIVETH SYSTEM MONITOR V4: disabled'
        );
    }


    _buildWidget() {

        this._widget =
            new St.BoxLayout({

                vertical: true,

                style_class:
                    'niveth-system-monitor',

                width:
                    WIDGET_WIDTH,

                height:
                    WIDGET_HEIGHT,
            });


        this._title =
            new St.Label({

                text:
                    'NIVETH SYSTEM',

                style_class:
                    'niveth-system-title',

                x_align:
                    Clutter.ActorAlign.START,
            });


        this._title.set_width(
            170
        );


        try {

            this._title
                .clutter_text
                .ellipsize = 0;

        } catch (error) {
        }


        this._widget.add_child(
            this._title
        );


        const cpu =
            this._buildMetricRow(
                'CPU',
                true
            );


        this._cpuValue =
            cpu.value;

        this._cpuLine =
            cpu.line;

        this._cpuWaveBars =
            cpu.waveBars;


        this._widget.add_child(
            cpu.row
        );


        const ram =
            this._buildMetricRow(
                'RAM',
                false
            );


        this._ramValue =
            ram.value;

        this._ramLine =
            ram.line;

        this._ramWaveBars =
            ram.waveBars;


        this._widget.add_child(
            ram.row
        );


        Main.uiGroup.add_child(
            this._widget
        );


        this._updatePosition();
    }


    _buildMetricRow(
        label,
        isCpu
    ) {

        const row =
            new St.BoxLayout({

                vertical: true,

                style_class:
                    'niveth-system-metric',

                x_expand: true,
            });


        const header =
            new St.BoxLayout({

                vertical: false,

                style_class:
                    'niveth-system-header',

                x_expand: true,
            });


        const labelActor =
            new St.Label({

                text:
                    label,

                style_class:
                    'niveth-system-label',
            });


        labelActor.set_width(
            44
        );


        try {

            labelActor
                .clutter_text
                .ellipsize = 0;

        } catch (error) {
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

                text:
                    '--',

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
         * Fixed percentage track.
         *
         * Track  = 308px
         * Fill   = actual percentage
         */
        const lineTrack =
            new St.Widget({

                style_class:
                    'niveth-system-line-track',

                width:
                    TRACK_WIDTH,

                height:
                    1,

                x_expand:
                    false,

                x_align:
                    Clutter.ActorAlign.START,
            });


        const line =
            new St.Widget({

                style_class:
                    isCpu
                        ? 'niveth-system-line cpu'
                        : 'niveth-system-line ram',

                width:
                    0,

                height:
                    1,

                x_expand:
                    false,

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
         * Waveform.
         */
        const wave =
            new St.BoxLayout({

                vertical:
                    false,

                style_class:
                    'niveth-system-wave',

                x_expand:
                    true,

                height:
                    25,
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

                    width:
                        3,

                    height:
                        4,

                    x_expand:
                        false,

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


        this._widget
            .remove_style_class_name(
                'dark'
            );

        this._widget
            .remove_style_class_name(
                'light'
            );


        this._widget
            .add_style_class_name(
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


            /*
             * Audio replaces the cyan
             * CPU waveform while available.
             *
             * CPU remains as fallback.
             */
            if (
                this._audioConnected
            ) {

                this._updateWaveform(
                    this._cpuWaveBars,
                    this._audioHistory,
                    true
                );

            } else {

                this._updateWaveform(
                    this._cpuWaveBars,
                    this._cpuHistory,
                    false
                );
            }
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
                this._ramHistory,
                false
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
                    .decode(
                        contents
                    );


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


            if (
                !this._previousCpu
            ) {

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
                `NIVETH CPU: ${error}`
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
                    .decode(
                        contents
                    );


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
                ) * 100;


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
                `NIVETH RAM: ${error}`
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
                    Number(percent) || 0
                )
            );


        const width =
            Math.round(
                TRACK_WIDTH *
                safe /
                100
            );


        line.set_width(
            width
        );
    }


    _updateWaveform(
        bars,
        history,
        audioMode
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
                            ? history[
                                history.length - 1
                            ]
                            : 0
                    );


            if (
                !Number.isFinite(value)
            ) {

                value = 0;
            }


            let normalized =
                Math.max(
                    0,
                    Math.min(
                        1,
                        value / 100
                    )
                );


            if (audioMode) {

                const motion =
                    (
                        Math.sin(
                            now * 8.0 +
                            i * 0.55
                        ) + 1
                    ) / 2;


                normalized =
                    Math.max(
                        0.04,
                        Math.min(
                            1,
                            normalized * 0.82 +
                            motion * 0.08
                        )
                    );

            } else {

                const motion =
                    (
                        Math.sin(
                            now * 2.0 +
                            i * 0.70
                        ) + 1
                    ) / 2;


                normalized =
                    Math.max(
                        0.08,
                        Math.min(
                            1,
                            normalized * 0.75 +
                            motion * 0.18
                        )
                    );
            }


            const minHeight =
                audioMode
                    ? 3
                    : 4;


            const maxHeight =
                audioMode
                    ? 24
                    : 20;


            const height =
                Math.max(
                    minHeight,
                    Math.round(
                        minHeight +
                        normalized *
                        maxHeight
                    )
                );


            bars[i].set_height(
                height
            );


            bars[i].set_y_align(
                Clutter.ActorAlign.END
            );
        }
    }


    _startAudioMeter() {

        this._stopAudioMeter();


        const helper =
            `${this.path}/niveth-audio-meter.py`;


        try {

            this._audioProcess =
                Gio.Subprocess.new(

                    [helper],

                    Gio.SubprocessFlags.STDOUT_PIPE |
                    Gio.SubprocessFlags.STDERR_PIPE
                );


            this._audioReader =
                Gio.DataInputStream.new(
                    this._audioProcess
                        .get_stdout_pipe()
                );


            this._audioConnected = true;

            this._readAudioLine();

        } catch (error) {

            this._audioProcess = null;
            this._audioReader = null;

            this._audioConnected = false;

            log(
                `NIVETH AUDIO START: ${error}`
            );
        }
    }


    _readAudioLine() {

        if (
            !this._audioReader ||
            !this._audioProcess
        )
            return;


        this._audioReader.read_line_async(
            GLib.PRIORITY_DEFAULT,
            null,
            (stream, result) => {

                try {

                    const [
                        line,
                        length,
                    ] =
                        stream.read_line_finish(
                            result
                        );


                    if (
                        line === null ||
                        length <= 0
                    ) {

                        this._audioConnected =
                            false;

                        return;
                    }


                    const value =
                        Number(
                            new TextDecoder()
                                .decode(
                                    line
                                )
                                .trim()
                        );


                    if (
                        Number.isFinite(value)
                    ) {

                        this._audioLevel =
                            Math.max(
                                0,
                                Math.min(
                                    100,
                                    value
                                )
                            );


                        this._audioHistory.push(
                            this._audioLevel
                        );


                        if (
                            this._audioHistory.length >
                            WAVE_COUNT
                        ) {

                            this._audioHistory.shift();
                        }


                        this._updateWaveform(
                            this._cpuWaveBars,
                            this._audioHistory,
                            true
                        );
                    }


                    this._readAudioLine();

                } catch (error) {

                    this._audioConnected =
                        false;

                    log(
                        `NIVETH AUDIO READ: ${error}`
                    );
                }
            }
        );
    }


    _stopAudioMeter() {

        this._audioConnected =
            false;


        if (this._audioReader) {

            try {
                this._audioReader.close(null);
            } catch (error) {
            }

            this._audioReader = null;
        }


        if (this._audioProcess) {

            try {
                this._audioProcess.force_exit();
            } catch (error) {
            }

            this._audioProcess = null;
        }
    }
}
JS

echo "[PASS] extension.js"


# ============================================================
# 6. COMPLETE CSS
# ============================================================

echo
echo "[6/11] Writing complete stylesheet"

cat > "$HOST_DIR/stylesheet.css" <<'CSS'
/* ============================================================
 * NIVETH SYSTEM MONITOR V4
 * ============================================================ */

.niveth-system-monitor {

    width: 330px;

    min-width: 330px;

    max-width: 330px;

    height: 116px;

    min-height: 116px;

    max-height: 116px;

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


/* ============================================================
 * TITLE
 * ============================================================ */

.niveth-system-title {

    width: 170px;

    min-width: 170px;

    max-width: 170px;

    font-size: 8pt;

    font-weight: 400;

    letter-spacing: 1.5px;

    color:
        rgba(231, 237, 244, 0.68);
}


/* ============================================================
 * METRIC
 * ============================================================ */

.niveth-system-metric {

    spacing: 2px;

    x-expand: true;
}


.niveth-system-header {

    min-height: 14px;

    max-height: 14px;
}


.niveth-system-label {

    width: 44px;

    min-width: 44px;

    max-width: 44px;

    font-size: 8pt;

    font-weight: 400;

    letter-spacing: 0.7px;

    color:
        rgba(231, 237, 244, 0.82);
}


.niveth-system-value {

    font-size: 8pt;

    font-weight: 400;

    color:
        rgba(231, 237, 244, 0.80);
}


/* ============================================================
 * PERCENTAGE TRACK
 * ============================================================ */

.niveth-system-line-track {

    width: 308px;

    min-width: 308px;

    max-width: 308px;

    height: 1px;

    min-height: 1px;

    max-height: 1px;

    border-radius: 2px;

    background-color:
        rgba(231, 237, 244, 0.10);
}


.niveth-system-line {

    height: 1px;

    min-height: 1px;

    max-height: 1px;

    border-radius: 2px;

    padding: 0;

    margin: 0;
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


/* ============================================================
 * WAVEFORM
 * ============================================================ */

.niveth-system-wave {

    spacing: 2px;

    height: 25px;

    min-height: 25px;

    max-height: 25px;

    padding-top: 1px;
}


.niveth-system-wave-bar {

    width: 3px;

    min-width: 3px;

    max-width: 3px;

    min-height: 3px;

    border-radius:
        3px 3px 1px 1px;
}


.niveth-system-wave-bar.cpu {

    background-color:
        #69D8FF;

    box-shadow:
        0 0 5px
        rgba(105, 216, 255, 0.38);
}


.niveth-system-wave-bar.ram {

    background-color:
        #C185FF;

    box-shadow:
        0 0 5px
        rgba(193, 133, 255, 0.30);
}


/* ============================================================
 * LIGHT
 * ============================================================ */

.niveth-system-monitor.light {

    background-color:
        rgba(36, 29, 67, 0.30);

    border-color:
        rgba(150, 185, 235, 0.20);
}


.niveth-system-monitor.light
.niveth-system-title {

    color:
        rgba(246, 243, 255, 0.78);
}


.niveth-system-monitor.light
.niveth-system-label {

    color:
        rgba(246, 243, 255, 0.90);
}


.niveth-system-monitor.light
.niveth-system-value {

    color:
        rgba(231, 226, 255, 0.88);
}


/* ============================================================
 * DARK
 * ============================================================ */

.niveth-system-monitor.dark {

    background-color:
        rgba(18, 24, 48, 0.34);

    border-color:
        rgba(150, 185, 235, 0.16);
}
CSS

echo "[PASS] stylesheet.css"


# ============================================================
# 7. PACKAGE CHECK
# ============================================================

echo
echo "[7/11] Checking audio package"

if ! command -v parecord >/dev/null 2>&1; then

    echo "[INFO] Installing pulseaudio-utils on host"

    sudo apt-get update

    sudo apt-get install \
        -y \
        pulseaudio-utils

else

    echo "[PASS] Host parecord"
fi


if [ -f "$COMPONENTS" ]; then

    if ! grep -qxF \
        "pulseaudio-utils" \
        "$COMPONENTS"
    then

        printf '%s\n' \
            "pulseaudio-utils" \
            >> "$COMPONENTS"

        echo "[PASS] Added pulseaudio-utils to Niveth components"

    else

        echo "[INFO] pulseaudio-utils already in Niveth components"

    fi

else

    echo "[WARN] Niveth components file not found:"
    echo "       $COMPONENTS"

fi


# ============================================================
# 8. SOURCE DCONF
# ============================================================

echo
echo "[8/11] Updating source dconf"

python3 - \
    "$SOURCE_DCONF_1" \
    "$SOURCE_DCONF_2" <<'PY'
from pathlib import Path
import ast
import re
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

    try:

        enabled =
            ast.literal_eval(
                match.group(1)
            )

    except Exception as exc:

        print(
            f"[WARN] Could not parse {path}: {exc}"
        )

        continue


    if EXT not in enabled:

        enabled.append(
            EXT
        )


    replacement =
        "enabled-extensions=" +
        repr(enabled)


    text =
        re.sub(
            r"^enabled-extensions=\[.*\]$",
            replacement,
            text,
            count=1,
            flags=re.MULTILINE
        )


    path.write_text(
        text,
        encoding="utf-8"
    )


    print(
        f"[PASS] {EXT} enabled in {path}"
    )
PY


# ============================================================
# 9. INSTALL ROOTFS
# ============================================================

echo
echo "[9/11] Installing System Monitor into rootfs"

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


sudo install -m 0755 \
    "$HOST_DIR/niveth-audio-meter.py" \
    "$ROOTFS_DIR/niveth-audio-meter.py"


echo "[PASS] Rootfs extension files"


# ------------------------------------------------------------
# ROOTFS AUDIO PACKAGE
# ------------------------------------------------------------

if sudo chroot \
    "$ROOTFS" \
    /usr/bin/bash -c \
    'command -v parecord >/dev/null 2>&1'
then

    echo "[PASS] Rootfs parecord"

else

    echo "[INFO] Installing pulseaudio-utils into rootfs"

    sudo chroot \
        "$ROOTFS" \
        /usr/bin/apt-get install \
        -y \
        pulseaudio-utils

fi


# ------------------------------------------------------------
# ROOTFS DCONF
# ------------------------------------------------------------

if [ ! -f "$ROOTFS_DCONF" ]; then

    echo "[FAIL] Rootfs dconf file not found:"
    echo "       $ROOTFS_DCONF"

    exit 1

fi


sudo cp \
    "$ROOTFS_DCONF" \
    "$ROOTFS_DCONF.backup-before-monitor-v4-$STAMP"


sudo python3 - \
    "$ROOTFS_DCONF" <<'PY'
from pathlib import Path
import ast
import re
import sys

path = Path(
    sys.argv[1]
)

ext =
    "niveth-system-monitor@nivethos"


text =
    path.read_text(
        encoding="utf-8"
    )


match =
    re.search(
        r"^enabled-extensions=(\[.*\])$",
        text,
        re.MULTILINE
    )


if not match:

    raise SystemExit(
        "[FAIL] Rootfs enabled-extensions missing"
    )


enabled =
    ast.literal_eval(
        match.group(1)
    )


if ext not in enabled:

    enabled.append(
        ext
    )


replacement =
    "enabled-extensions=" +
    repr(enabled)


text =
    re.sub(
        r"^enabled-extensions=\[.*\]$",
        replacement,
        text,
        count=1,
        flags=re.MULTILINE
    )


path.write_text(
    text,
    encoding="utf-8"
)


print(
    "[PASS] Rootfs dconf extension enabled"
)
PY


sudo chroot \
    "$ROOTFS" \
    /usr/bin/dconf update

echo "[PASS] Rootfs dconf rebuilt"


# ============================================================
# 10. VERIFY SOURCE ↔ ROOTFS
# ============================================================

echo
echo "[10/11] Verifying source ↔ rootfs"

for file in \
    metadata.json \
    extension.js \
    stylesheet.css \
    niveth-audio-meter.py
do

    SOURCE_HASH="$(
        sha256sum \
            "$HOST_DIR/$file" |
        awk '{print $1}'
    )"


    ROOT_HASH="$(
        sudo sha256sum \
            "$ROOTFS_DIR/$file" |
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


# ------------------------------------------------------------
# IMPORTANT FEATURES
# ------------------------------------------------------------

grep -q \
    "_startAudioMeter" \
    "$HOST_DIR/extension.js"

echo "[PASS] Audio waveform engine"

grep -q \
    "TRACK_WIDTH = 308" \
    "$HOST_DIR/extension.js"

echo "[PASS] Fixed percentage track"

grep -q \
    "this._title.set_width" \
    "$HOST_DIR/extension.js"

echo "[PASS] Full title"

grep -q \
    "labelActor.set_width" \
    "$HOST_DIR/extension.js"

echo "[PASS] Full CPU/RAM labels"


sudo grep -q \
    "_startAudioMeter" \
    "$ROOTFS_DIR/extension.js"

echo "[PASS] Rootfs audio engine"

sudo grep -q \
    "TRACK_WIDTH = 308" \
    "$ROOTFS_DIR/extension.js"

echo "[PASS] Rootfs percentage track"


# ============================================================
# 11. LIVE RELOAD
# ============================================================

echo
echo "[11/11] Reloading live System Monitor"

gnome-extensions disable \
    "$EXT_ID" \
    2>/dev/null || true

sleep 2

gnome-extensions enable \
    "$EXT_ID"

sleep 5


echo
echo "=== FINAL STATUS ==="

gnome-extensions info \
    "$EXT_ID" \
    2>&1 |
    grep -E \
        "Name:|Enabled:|State:|Path:" || true


echo
echo "============================================================"
echo " NIVETH SYSTEM MONITOR V4 — COMPLETE"
echo "============================================================"
echo
echo "CPU:"
echo "  Real CPU percentage"
echo
echo "RAM:"
echo "  Real RAM percentage"
echo
echo "PERCENTAGE BAR:"
echo "  9%   -> ~28px"
echo "  50%  -> 154px"
echo "  100% -> 308px"
echo
echo "CYAN WAVEFORM:"
echo "  Real system audio"
echo "  YouTube / music / video"
echo
echo "PURPLE WAVEFORM:"
echo "  RAM activity"
echo
echo "TEXT:"
echo "  Full NIVETH SYSTEM"
echo "  Full CPU"
echo "  Full RAM"
echo
echo "ROOTFS:"
echo "  Installed"
echo "  SHA256 verified"
echo "  dconf updated"
echo
echo "BACKUP:"
echo "  $BACKUP_DIR"
echo
echo "============================================================"
echo

