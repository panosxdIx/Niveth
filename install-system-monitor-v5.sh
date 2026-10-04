#!/usr/bin/env bash
set -euo pipefail

EXT_ID="niveth-system-monitor@nivethos"

LIVE_DIR="$HOME/.local/share/gnome-shell/extensions/$EXT_ID"
ROOTFS_DIR="$HOME/Niveth/build/rootfs/usr/share/gnome-shell/extensions/$EXT_ID"

echo "============================================================"
echo "        NIVETH SYSTEM MONITOR — CLEAN AUDIO V5"
echo "============================================================"
echo
echo "CPU  = horizontal bar"
echo "RAM  = horizontal bar"
echo "AUDIO = vertical waveform"
echo

if [ ! -d "$LIVE_DIR" ]; then
    echo "[ERROR] Extension directory not found:"
    echo "$LIVE_DIR"
    exit 1
fi

if [ ! -f "$LIVE_DIR/niveth-audio-meter.py" ]; then
    echo "[ERROR] Audio helper not found:"
    echo "$LIVE_DIR/niveth-audio-meter.py"
    exit 1
fi

echo "[1/9] Disabling current extension..."

gnome-extensions disable "$EXT_ID" 2>/dev/null || true

sleep 2

echo "[PASS] Disabled"

echo
echo "[2/9] Creating backup..."

BACKUP_DIR="$LIVE_DIR/backup-clean-v5-$(date +%Y%m%d-%H%M%S)"

mkdir -p "$BACKUP_DIR"

cp "$LIVE_DIR/extension.js" "$BACKUP_DIR/extension.js" 2>/dev/null || true
cp "$LIVE_DIR/stylesheet.css" "$BACKUP_DIR/stylesheet.css" 2>/dev/null || true
cp "$LIVE_DIR/metadata.json" "$BACKUP_DIR/metadata.json" 2>/dev/null || true
cp "$LIVE_DIR/niveth-audio-meter.py" "$BACKUP_DIR/niveth-audio-meter.py" 2>/dev/null || true

echo "[PASS] Backup:"
echo "$BACKUP_DIR"

echo
echo "[3/9] Writing metadata.json..."

cat > "$LIVE_DIR/metadata.json" <<'EOF'
{
  "uuid": "niveth-system-monitor@nivethos",
  "name": "Niveth System Monitor",
  "description": "Minimal CPU, RAM and audio-reactive system monitor.",
  "version": 5,
  "shell-version": [
    "50"
  ],
  "session-modes": [
    "user"
  ]
}
EOF

echo "[PASS] metadata.json"

echo
echo "[4/9] Writing clean extension.js..."

cat > "$LIVE_DIR/extension.js" <<'EOF'
import Gio from 'gi://Gio';
import GLib from 'gi://GLib';
import Clutter from 'gi://Clutter';
import St from 'gi://St';

import {Extension} from 'resource:///org/gnome/shell/extensions/extension.js';
import * as Main from 'resource:///org/gnome/shell/ui/main.js';


const WIDGET_WIDTH = 330;
const WIDGET_HEIGHT = 164;

const TOP_OFFSET = 82;
const RIGHT_OFFSET = 26;

const TRACK_WIDTH = 308;
const TRACK_HEIGHT = 4;

const WAVE_COUNT = 34;
const WAVE_WIDTH = 4;
const WAVE_HEIGHT = 28;


export default class NivethSystemMonitor extends Extension {

    enable() {

        this._widget = null;

        this._cpuValue = null;
        this._cpuFill = null;

        this._ramValue = null;
        this._ramFill = null;

        this._audioValue = null;

        this._audioWave = null;
        this._audioBars = [];

        this._audioProcess = null;
        this._audioReader = null;

        this._audioLevel = 0;

        this._audioHistory = [];

        this._previousCpu = null;

        this._timerId = 0;
        this._monitorChangedId = 0;

        for (
            let i = 0;
            i < WAVE_COUNT;
            i++
        ) {
            this._audioHistory.push(0);
        }

        this._buildWidget();

        this._updatePosition();

        this._updateMetrics();

        this._startAudioMeter();

        this._timerId =
            GLib.timeout_add_seconds(
                GLib.PRIORITY_DEFAULT,
                1,
                () => {

                    if (!this._widget)
                        return GLib.SOURCE_REMOVE;

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
            'NIVETH SYSTEM MONITOR V5: enabled'
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

        this._stopAudioMeter();

        if (this._widget) {

            try {
                this._widget.destroy();
            } catch (error) {
            }

            this._widget = null;
        }

        this._cpuValue = null;
        this._cpuFill = null;

        this._ramValue = null;
        this._ramFill = null;

        this._audioValue = null;

        this._audioWave = null;
        this._audioBars = [];

        this._audioHistory = [];

        this._previousCpu = null;

        log(
            'NIVETH SYSTEM MONITOR V5: disabled'
        );
    }


    _buildWidget() {

        this._widget =
            new St.BoxLayout({

                vertical: true,

                width:
                    WIDGET_WIDTH,

                height:
                    WIDGET_HEIGHT,

                style_class:
                    'niveth-system-monitor',
            });


        const title =
            new St.Label({

                text:
                    'NIVETH SYSTEM',

                style_class:
                    'niveth-system-title',

                x_align:
                    Clutter.ActorAlign.START,
            });


        title.set_width(
            170
        );


        this._widget.add_child(
            title
        );


        const cpu =
            this._buildMetric(
                'CPU'
            );


        this._cpuValue =
            cpu.value;

        this._cpuFill =
            cpu.fill;


        this._widget.add_child(
            cpu.row
        );


        const ram =
            this._buildMetric(
                'RAM'
            );


        this._ramValue =
            ram.value;

        this._ramFill =
            ram.fill;


        this._widget.add_child(
            ram.row
        );


        const audio =
            this._buildAudio();


        this._audioValue =
            audio.value;

        this._audioWave =
            audio.wave;

        this._audioBars =
            audio.bars;


        this._widget.add_child(
            audio.row
        );


        Main.uiGroup.add_child(
            this._widget
        );
    }


    _buildMetric(labelText) {

        const row =
            new St.BoxLayout({

                vertical: true,

                x_expand: true,

                style_class:
                    'niveth-system-metric',
            });


        const header =
            new St.BoxLayout({

                vertical: false,

                width:
                    TRACK_WIDTH,

                style_class:
                    'niveth-system-header',
            });


        const label =
            new St.Label({

                text:
                    labelText,

                x_expand:
                    true,

                style_class:
                    'niveth-system-label',
            });


        const value =
            new St.Label({

                text:
                    labelText === 'CPU'
                        ? '0%'
                        : '0.0 / 0.0 GB',

                style_class:
                    'niveth-system-value',
            });


        header.add_child(
            label
        );


        const spacer =
            new St.Widget({
                x_expand: true,
            });


        header.add_child(
            spacer
        );


        header.add_child(
            value
        );


        /*
         * CPU/RAM:
         * horizontal track only.
         */

        const track =
            new St.Widget({

                width:
                    TRACK_WIDTH,

                height:
                    TRACK_HEIGHT,

                style_class:
                    'niveth-system-track',
            });


        const fill =
            new St.Widget({

                width:
                    0,

                height:
                    TRACK_HEIGHT,

                style_class:
                    labelText === 'CPU'
                        ? 'niveth-system-fill-cpu'
                        : 'niveth-system-fill-ram',
            });


        track.add_child(
            fill
        );


        row.add_child(
            header
        );


        row.add_child(
            track
        );


        return {
            row,
            value,
            fill,
        };
    }


    _buildAudio() {

        const row =
            new St.BoxLayout({

                vertical: true,

                x_expand: true,

                style_class:
                    'niveth-system-audio',
            });


        const header =
            new St.BoxLayout({

                vertical: false,

                width:
                    TRACK_WIDTH,

                style_class:
                    'niveth-system-header',
            });


        const label =
            new St.Label({

                text:
                    'AUDIO',

                x_expand:
                    true,

                style_class:
                    'niveth-system-label niveth-system-audio-label',
            });


        const value =
            new St.Label({

                text:
                    'LIVE',

                style_class:
                    'niveth-system-audio-value',
            });


        header.add_child(
            label
        );


        const spacer =
            new St.Widget({
                x_expand: true,
            });


        header.add_child(
            spacer
        );


        header.add_child(
            value
        );


        row.add_child(
            header
        );


        /*
         * ONLY AUDIO HAS VERTICAL BARS.
         */

        const wave =
            new St.BoxLayout({

                vertical: false,

                width:
                    TRACK_WIDTH,

                height:
                    WAVE_HEIGHT,

                style_class:
                    'niveth-system-audio-wave',
            });


        const bars = [];


        for (
            let i = 0;
            i < WAVE_COUNT;
            i++
        ) {

            const bar =
                new St.Widget({

                    width:
                        WAVE_WIDTH,

                    height:
                        2,

                    style_class:
                        'niveth-system-audio-bar',
            });


            wave.add_child(
                bar
            );


            bars.push(
                bar
            );
        }


        row.add_child(
            wave
        );


        return {
            row,
            value,
            wave,
            bars,
        };
    }


    _updatePosition() {

        if (!this._widget)
            return;


        const monitor =
            Main.layoutManager.primaryMonitor;


        if (!monitor)
            return;


        this._widget.set_position(

            monitor.x +
                monitor.width -
                WIDGET_WIDTH -
                RIGHT_OFFSET,

            monitor.y +
                TOP_OFFSET
        );
    }


    _readTextFile(path) {

        try {

            const [
                ok,
                contents,
            ] =
                GLib.file_get_contents(
                    path
                );


            if (!ok)
                return null;


            return new TextDecoder()
                .decode(contents);

        } catch (error) {

            return null;
        }
    }


    _readCpu() {

        const text =
            this._readTextFile(
                '/proc/stat'
            );


        if (!text)
            return null;


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


        if (values.length < 5)
            return null;


        const user =
            values[0] || 0;

        const nice =
            values[1] || 0;

        const system =
            values[2] || 0;

        const idle =
            values[3] || 0;

        const iowait =
            values[4] || 0;

        const irq =
            values[5] || 0;

        const softirq =
            values[6] || 0;

        const steal =
            values[7] || 0;


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
            this._previousCpu === null
        ) {

            this._previousCpu = {
                idle:
                    idleTotal,

                total:
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

            total:
                total,
        };


        if (totalDelta <= 0)
            return 0;


        let usage =
            100 *
            (
                1 -
                idleDelta /
                totalDelta
            );


        usage =
            Math.max(
                0,
                Math.min(
                    100,
                    usage
                )
            );


        return usage;
    }


    _readRam() {

        const text =
            this._readTextFile(
                '/proc/meminfo'
            );


        if (!text)
            return null;


        let totalKB = 0;
        let availableKB = 0;


        for (
            const line of text.split('\n')
        ) {

            if (
                line.startsWith(
                    'MemTotal:'
                )
            ) {

                totalKB =
                    Number(
                        line
                            .replace(
                                'MemTotal:',
                                ''
                            )
                            .trim()
                            .split(/\s+/)[0]
                    ) || 0;
            }


            if (
                line.startsWith(
                    'MemAvailable:'
                )
            ) {

                availableKB =
                    Number(
                        line
                            .replace(
                                'MemAvailable:',
                                ''
                            )
                            .trim()
                            .split(/\s+/)[0]
                    ) || 0;
            }
        }


        if (totalKB <= 0)
            return null;


        const usedKB =
            Math.max(
                0,
                totalKB -
                availableKB
            );


        const percent =
            Math.max(
                0,
                Math.min(
                    100,
                    usedKB /
                    totalKB *
                    100
                )
            );


        return {

            used:
                usedKB /
                1024 /
                1024,

            total:
                totalKB /
                1024 /
                1024,

            percent,
        };
    }


    _setBar(fill, percent) {

        if (!fill)
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
            Math.round(
                TRACK_WIDTH *
                safe /
                100
            );


        fill.set_width(
            width
        );
    }


    _updateMetrics() {

        const cpu =
            this._readCpu();


        const ram =
            this._readRam();


        if (cpu !== null) {

            this._cpuValue.set_text(
                `${Math.round(cpu)}%`
            );


            /*
             * CPU:
             * horizontal only.
             */

            this._setBar(
                this._cpuFill,
                cpu
            );
        }


        if (ram !== null) {

            this._ramValue.set_text(
                `${ram.used.toFixed(1)} / ${ram.total.toFixed(1)} GB`
            );


            /*
             * RAM:
             * horizontal only.
             */

            this._setBar(
                this._ramFill,
                ram.percent
            );
        }
    }


    _startAudioMeter() {

        this._stopAudioMeter();


        const helper =
            GLib.build_filenamev([
                this.path,
                'niveth-audio-meter.py',
            ]);


        try {

            this._audioProcess =
                Gio.Subprocess.new(

                    [
                        'python3',
                        helper,
                    ],

                    Gio.SubprocessFlags.STDOUT_PIPE |
                    Gio.SubprocessFlags.STDERR_PIPE
                );


            this._audioReader =
                Gio.DataInputStream.new(
                    this._audioProcess
                        .get_stdout_pipe()
                );


            this._audioValue.set_text(
                'LIVE'
            );


            this._readAudioLine();

        } catch (error) {

            this._audioValue.set_text(
                'OFF'
            );


            log(
                `NIVETH AUDIO START ERROR: ${error}`
            );
        }
    }


    _readAudioLine() {

        if (
            !this._audioReader ||
            !this._audioProcess
        )
            return;


        this._audioReader
            .read_line_async(

                GLib.PRIORITY_DEFAULT,

                null,

                (
                    stream,
                    result
                ) => {

                    try {

                        const [
                            line,
                        ] =
                            stream
                                .read_line_finish_utf8(
                                    result
                                );


                        if (
                            line === null
                        ) {

                            this._audioValue
                                ?.set_text(
                                    'OFF'
                                );

                            return;
                        }


                        let level =
                            Number(
                                line.trim()
                            );


                        if (
                            !Number.isFinite(
                                level
                            )
                        ) {

                            this._readAudioLine();

                            return;
                        }


                        level =
                            Math.max(
                                0,
                                Math.min(
                                    100,
                                    level
                                )
                            );


                        this._audioLevel =
                            level;


                        /*
                         * The current PCM meter on
                         * this machine is normally around
                         * 70-85% during playback.
                         *
                         * Stretch that range for a
                         * clearly visible waveform.
                         */

                        let visual =
                            (
                                level -
                                60
                            ) *
                            2.6;


                        visual =
                            Math.max(
                                0,
                                Math.min(
                                    100,
                                    visual
                                )
                            );


                        this._audioHistory.push(
                            visual
                        );


                        while (
                            this._audioHistory.length >
                            WAVE_COUNT
                        ) {

                            this._audioHistory.shift();
                        }


                        this._drawAudioWaveform();


                        this._readAudioLine();

                    } catch (error) {

                        log(
                            `NIVETH AUDIO READ ERROR: ${error}`
                        );

                        this._audioValue
                            ?.set_text(
                                'OFF'
                            );
                    }
                }
            );
    }


    _drawAudioWaveform() {

        if (
            !this._audioBars.length
        )
            return;


        for (
            let i = 0;
            i < this._audioBars.length;
            i++
        ) {

            const level =
                this._audioHistory[i] || 0;


            const previous =
                i > 0
                    ? this._audioHistory[i - 1]
                    : level;


            const next =
                i + 1 <
                this._audioHistory.length
                    ? this._audioHistory[i + 1]
                    : level;


            const smooth =
                level * 0.60 +
                previous * 0.20 +
                next * 0.20;


            const safe =
                Math.max(
                    0,
                    Math.min(
                        100,
                        smooth
                    )
                );


            const height =
                Math.max(
                    2,
                    Math.round(
                        2 +
                        safe /
                        100 *
                        (
                            WAVE_HEIGHT -
                            2
                        )
                    )
                );


            const bar =
                this._audioBars[i];


            bar.set_height(
                height
            );


            bar.set_y(
                Math.round(
                    (
                        WAVE_HEIGHT -
                        height
                    ) / 2
                )
            );
        }
    }


    _stopAudioMeter() {

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


        if (this._audioValue) {

            try {
                this._audioValue.set_text(
                    'OFF'
                );
            } catch (error) {
            }
        }
    }
}
EOF

echo "[PASS] extension.js"

echo
echo "[5/9] Writing clean stylesheet.css..."

cat > "$LIVE_DIR/stylesheet.css" <<'EOF'
.niveth-system-monitor {
    width: 330px;
    height: 164px;

    padding: 9px 11px 10px 11px;

    background-color: rgba(18, 20, 42, 0.52);

    border: 1px solid rgba(170, 170, 255, 0.20);

    border-radius: 15px;

    box-shadow:
        0 8px 30px rgba(0, 0, 0, 0.28),
        inset 0 1px 0 rgba(255, 255, 255, 0.05);
}

.niveth-system-title {
    margin-left: 1px;
    margin-bottom: 5px;

    font-size: 10px;
    font-weight: 500;

    letter-spacing: 2px;

    color: rgba(210, 210, 255, 0.72);
}

.niveth-system-metric {
    spacing: 3px;

    margin-top: 1px;
    margin-bottom: 5px;
}

.niveth-system-header {
    width: 308px;
}

.niveth-system-label {
    font-size: 11px;
    font-weight: 500;

    letter-spacing: 1px;

    color: rgba(240, 240, 255, 0.90);
}

.niveth-system-value {
    font-size: 10px;
    font-weight: 400;

    color: rgba(220, 220, 255, 0.72);
}

/*
 * CPU + RAM
 * HORIZONTAL BARS ONLY.
 */

.niveth-system-track {
    width: 308px;
    height: 4px;

    background-color: rgba(255, 255, 255, 0.10);

    border-radius: 4px;

    overflow: hidden;
}

.niveth-system-fill-cpu {
    width: 0px;
    height: 4px;

    border-radius: 4px;

    background-color: rgba(88, 218, 255, 0.95);

    box-shadow:
        0 0 7px rgba(88, 218, 255, 0.45);
}

.niveth-system-fill-ram {
    width: 0px;
    height: 4px;

    border-radius: 4px;

    background-color: rgba(190, 120, 255, 0.95);

    box-shadow:
        0 0 7px rgba(190, 120, 255, 0.40);
}

/*
 * AUDIO
 * VERTICAL WAVEFORM ONLY.
 */

.niveth-system-audio {
    spacing: 3px;

    margin-top: 1px;
}

.niveth-system-audio-label {
    color: rgba(130, 225, 255, 0.92);
}

.niveth-system-audio-value {
    font-size: 9px;

    letter-spacing: 1px;

    color: rgba(130, 225, 255, 0.60);
}

.niveth-system-audio-wave {
    width: 308px;
    height: 28px;

    spacing: 4px;

    background-color: transparent;
}

.niveth-system-audio-bar {
    width: 4px;
    height: 2px;

    min-height: 2px;

    border-radius: 3px;

    background-color: rgba(88, 218, 255, 0.95);

    box-shadow:
        0 0 6px rgba(88, 218, 255, 0.40);
}
EOF

echo "[PASS] stylesheet.css"

echo
echo "[6/9] Verifying audio helper..."

chmod +x "$LIVE_DIR/niveth-audio-meter.py"

python3 -m py_compile \
    "$LIVE_DIR/niveth-audio-meter.py"

echo "[PASS] Audio helper syntax"

echo
echo "[7/9] Syncing clean V5 into Niveth rootfs..."

sudo mkdir -p "$ROOTFS_DIR"

sudo install -Dm644 \
    "$LIVE_DIR/extension.js" \
    "$ROOTFS_DIR/extension.js"

sudo install -Dm644 \
    "$LIVE_DIR/stylesheet.css" \
    "$ROOTFS_DIR/stylesheet.css"

sudo install -Dm644 \
    "$LIVE_DIR/metadata.json" \
    "$ROOTFS_DIR/metadata.json"

sudo install -Dm755 \
    "$LIVE_DIR/niveth-audio-meter.py" \
    "$ROOTFS_DIR/niveth-audio-meter.py"

echo "[PASS] Rootfs synchronized"

echo
echo "[8/9] Verifying files..."

LIVE_JS_HASH="$(
    sha256sum \
        "$LIVE_DIR/extension.js" |
    awk '{print $1}'
)"

ROOT_JS_HASH="$(
    sudo sha256sum \
        "$ROOTFS_DIR/extension.js" |
    awk '{print $1}'
)"

LIVE_CSS_HASH="$(
    sha256sum \
        "$LIVE_DIR/stylesheet.css" |
    awk '{print $1}'
)"

ROOT_CSS_HASH="$(
    sudo sha256sum \
        "$ROOTFS_DIR/stylesheet.css" |
    awk '{print $1}'
)"

echo
echo "extension.js"
echo " LIVE: $LIVE_JS_HASH"
echo " ROOT: $ROOT_JS_HASH"

echo
echo "stylesheet.css"
echo " LIVE: $LIVE_CSS_HASH"
echo " ROOT: $ROOT_CSS_HASH"

if [ "$LIVE_JS_HASH" != "$ROOT_JS_HASH" ]; then
    echo "[ERROR] extension.js mismatch"
    exit 1
fi

if [ "$LIVE_CSS_HASH" != "$ROOT_CSS_HASH" ]; then
    echo "[ERROR] stylesheet.css mismatch"
    exit 1
fi

echo
echo "[PASS] Live/rootfs files identical"

echo
echo "[9/9] Enabling clean V5..."

gnome-extensions enable "$EXT_ID" 2>/dev/null || true

sleep 5

echo
echo "============================================================"
echo " FINAL STATUS"
echo "============================================================"

gnome-extensions info "$EXT_ID"

echo
echo "============================================================"
echo " FINAL DESIGN"
echo "============================================================"
echo
echo "CPU  -> horizontal bar ONLY"
echo "RAM  -> horizontal bar ONLY"
echo "AUDIO -> vertical waveform ONLY"
echo
echo "No CPU waveform."
echo "No RAM waveform."
echo "Only AUDIO uses vertical bars."
echo
echo "============================================================"
