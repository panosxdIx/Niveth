#!/usr/bin/env bash

set -u

UUID="niveth-system-monitor@nivethos"

EXT="$HOME/.local/share/gnome-shell/extensions/$UUID"

ROOTFS="$HOME/Niveth/build/rootfs"
ROOTFS_EXT="$ROOTFS/usr/share/gnome-shell/extensions/$UUID"

STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP="$EXT/backup-v8-before-install-$STAMP"

WAVE_COUNT=40

echo
echo "============================================================"
echo "        NIVETH SYSTEM MONITOR — V8"
echo "============================================================"
echo
echo "Design:"
echo "  CPU  -> horizontal percentage bar"
echo "  RAM  -> horizontal percentage bar"
echo "  AUDIO -> 40 vertical reactive bars"
echo
echo "============================================================"
echo

# ------------------------------------------------------------
# 1. Verify
# ------------------------------------------------------------

echo "[1/10] Verifying environment..."

if [ ! -d "$EXT" ]; then
    mkdir -p "$EXT"
fi

if [ ! -d "$ROOTFS" ]; then
    echo "[FAIL] Niveth rootfs not found:"
    echo "  $ROOTFS"
    exit 1
fi

if ! command -v python3 >/dev/null 2>&1; then
    echo "[FAIL] python3 not found."
    exit 1
fi

if ! command -v pactl >/dev/null 2>&1; then
    echo "[FAIL] pactl not found."
    exit 1
fi

if ! command -v parec >/dev/null 2>&1; then
    echo "[FAIL] parec not found."
    exit 1
fi

echo "[PASS] Extension directory"
echo "[PASS] Niveth rootfs"
echo "[PASS] python3"
echo "[PASS] pactl"
echo "[PASS] parec"
echo

# ------------------------------------------------------------
# 2. Backup
# ------------------------------------------------------------

echo "[2/10] Creating backup..."

mkdir -p "$BACKUP"

for file in \
    extension.js \
    metadata.json \
    stylesheet.css \
    niveth-audio-meter.py
do
    if [ -f "$EXT/$file" ]; then
        cp -f \
            "$EXT/$file" \
            "$BACKUP/$file"
    fi
done

echo "[PASS] Backup:"
echo "  $BACKUP"
echo

# ------------------------------------------------------------
# 3. Disable current extension
# ------------------------------------------------------------

echo "[3/10] Disabling old System Monitor..."

gnome-extensions disable "$UUID" 2>/dev/null || true

sleep 2

echo "[PASS] Disabled."
echo

# ------------------------------------------------------------
# 4. Metadata
# ------------------------------------------------------------

echo "[4/10] Writing metadata.json..."

cat > "$EXT/metadata.json" <<'EOF'
{
  "uuid": "niveth-system-monitor@nivethos",
  "name": "Niveth System Monitor",
  "description": "Minimal CPU, RAM and audio-reactive system monitor.",
  "version": 8,
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

# ------------------------------------------------------------
# 5. Audio helper
# ------------------------------------------------------------

echo "[5/10] Writing audio helper..."

cat > "$EXT/niveth-audio-meter.py" <<'PY'
#!/usr/bin/env python3

import math
import struct
import subprocess
import sys


def command_output(args):
    try:
        return subprocess.check_output(
            args,
            text=True,
            stderr=subprocess.DEVNULL,
        ).strip()
    except Exception:
        return ""


def get_audio_monitor():
    sink = command_output(
        ["pactl", "get-default-sink"]
    )

    if sink:
        return sink + ".monitor"

    source = command_output(
        ["pactl", "get-default-source"]
    )

    return source


def clamp(value, low, high):
    return max(
        low,
        min(high, value),
    )


def main():

    monitor = get_audio_monitor()

    if not monitor:
        print("0.0", flush=True)
        return 1

    command = [
        "/usr/bin/parec",
        "--device",
        monitor,
        "--format=s16le",
        "--rate=22050",
        "--channels=1",
        "--raw",
    ]

    try:
        process = subprocess.Popen(
            command,
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            bufsize=0,
        )
    except Exception as error:
        print(
            "0.0",
            flush=True,
        )

        print(
            f"Audio helper error: {error}",
            file=sys.stderr,
        )

        return 1

    samples_per_block = 441
    bytes_per_sample = 2
    block_size = (
        samples_per_block *
        bytes_per_sample
    )

    while True:

        data = process.stdout.read(
            block_size
        )

        if not data:
            break

        usable = len(data) - (
            len(data) % 2
        )

        if usable <= 0:
            continue

        data = data[:usable]

        count = usable // 2

        try:
            samples = struct.unpack(
                "<" + ("h" * count),
                data,
            )
        except Exception:
            continue

        sum_squares = 0.0

        for sample in samples:

            normalized = (
                sample / 32768.0
            )

            sum_squares += (
                normalized *
                normalized
            )

        rms = math.sqrt(
            sum_squares /
            max(1, count)
        )

        if rms <= 0:
            level = 0.0
        else:
            db = (
                20.0 *
                math.log10(rms)
            )

            level = (
                (db + 60.0) /
                60.0
            ) * 100.0

        level = clamp(
            level,
            0.0,
            100.0,
        )

        print(
            f"{level:.2f}",
            flush=True,
        )

    try:
        process.wait(timeout=1)
    except Exception:
        try:
            process.kill()
        except Exception:
            pass

    return 0


if __name__ == "__main__":
    raise SystemExit(
        main()
    )
PY

chmod +x \
    "$EXT/niveth-audio-meter.py"

python3 -m py_compile \
    "$EXT/niveth-audio-meter.py"

echo "[PASS] Audio helper syntax"
echo

# ------------------------------------------------------------
# 6. Main extension.js
# ------------------------------------------------------------

echo "[6/10] Writing extension.js..."

cat > "$EXT/extension.js" <<'JS'
import Gio from 'gi://Gio';
import GLib from 'gi://GLib';
import Clutter from 'gi://Clutter';
import St from 'gi://St';

import * as Main from 'resource:///org/gnome/shell/ui/main.js';

import {
    Extension,
} from 'resource:///org/gnome/shell/extensions/extension.js';


const UUID =
    'niveth-system-monitor@nivethos';

const WAVE_COUNT = 40;

const WAVE_WIDTH = 300;

const WAVE_HEIGHT = 56;

const WAVE_GAP = 2;

const METRIC_TRACK_WIDTH = 230;

const AUDIO_INTERVAL = 40;

const METRIC_INTERVAL = 1000;


export default class NivethSystemMonitor
    extends Extension {

    enable() {

        this._widget = null;

        this._cpuFill = null;
        this._ramFill = null;

        this._cpuValue = null;
        this._ramValue = null;

        this._audioValue = null;

        this._audioWave = null;
        this._audioBars = [];

        this._audioHistory =
            new Array(
                WAVE_COUNT
            ).fill(0);

        this._audioLevel = 0;

        this._audioReader = null;
        this._audioProcess = null;
        this._audioCancellable =
            new Gio.Cancellable();

        this._audioReadActive = false;

        this._animationTimer = 0;
        this._metricsTimer = 0;
        this._monitorChangedId = 0;

        this._lastCpuTotal = null;
        this._lastCpuIdle = null;

        this._buildWidget();

        Main.layoutManager.addChrome(
            this._widget,
            {
                trackFullscreen: true,
            }
        );

        this._positionWidget();

        this._monitorChangedId =
            Main.layoutManager.connect(
                'monitors-changed',
                () => {
                    this._positionWidget();
                }
            );

        this._startMetrics();

        this._startAudioMeter();

        this._animationTimer =
            GLib.timeout_add(
                GLib.PRIORITY_DEFAULT,
                AUDIO_INTERVAL,
                () => {

                    this._animateAudio();

                    return GLib.SOURCE_CONTINUE;
                }
            );

        log(
            `[${UUID}] V8 enabled`
        );
    }


    disable() {

        if (this._metricsTimer) {

            GLib.source_remove(
                this._metricsTimer
            );

            this._metricsTimer = 0;
        }

        if (this._animationTimer) {

            GLib.source_remove(
                this._animationTimer
            );

            this._animationTimer = 0;
        }

        if (this._monitorChangedId) {

            Main.layoutManager.disconnect(
                this._monitorChangedId
            );

            this._monitorChangedId = 0;
        }

        this._stopAudioMeter();

        if (this._widget) {

            this._widget.destroy();

            this._widget = null;
        }

        this._audioBars = [];
        this._audioWave = null;
        this._audioValue = null;

        this._cpuFill = null;
        this._ramFill = null;

        this._cpuValue = null;
        this._ramValue = null;
    }


    _buildWidget() {

        this._widget =
            new St.BoxLayout({
                vertical: true,

                style: [
                    'width: 328px',
                    'min-width: 328px',
                    'padding: 13px 14px',
                    'spacing: 9px',

                    'background-color: rgba(16, 17, 29, 0.94)',

                    'border: 1px solid rgba(112, 220, 255, 0.18)',

                    'border-radius: 14px',
                ].join(';'),
            });


        const title =
            new St.Label({
                text: 'NIVETH SYSTEM MONITOR',

                style: [
                    'font-size: 10px',
                    'font-weight: 700',
                    'letter-spacing: 1px',
                    'opacity: 0.75',
                ].join(';'),
            });

        this._widget.add_child(
            title
        );


        this._buildMetric(
            'CPU',
            'cpu'
        );

        this._buildMetric(
            'RAM',
            'ram'
        );


        this._buildAudio();
    }


    _buildMetric(
        labelText,
        key
    ) {

        const row =
            new St.BoxLayout({
                vertical: false,

                style: [
                    'spacing: 8px',
                    'width: 298px',
                    'height: 19px',
                ].join(';'),
            });


        const label =
            new St.Label({
                text: labelText,

                style: [
                    'font-size: 10px',
                    'font-weight: 700',
                    'width: 28px',
                    'min-width: 28px',
                    'opacity: 0.72',
                ].join(';'),
            });


        const track =
            new St.Widget({
                style: [
                    `width: ${METRIC_TRACK_WIDTH}px`,
                    `min-width: ${METRIC_TRACK_WIDTH}px`,
                    'height: 7px',
                    'min-height: 7px',

                    'background-color: rgba(255,255,255,0.075)',

                    'border-radius: 5px',
                ].join(';'),
            });


        const fill =
            new St.Widget({
                style: [
                    'width: 1px',
                    'min-width: 1px',
                    'height: 7px',
                    'min-height: 7px',

                    'background-color: rgba(112,220,255,0.95)',

                    'border-radius: 5px',
                ].join(';'),
            });


        track.add_child(
            fill
        );


        const value =
            new St.Label({
                text:
                    key === 'ram'
                        ? '0.0 / 0.0 GB'
                        : '0%',

                style: [
                    'font-size: 10px',
                    'font-weight: 600',
                    'width: 84px',
                    'min-width: 84px',
                    'opacity: 0.72',
                ].join(';'),
            });


        row.add_child(
            label
        );

        row.add_child(
            track
        );

        row.add_child(
            value
        );


        this._widget.add_child(
            row
        );


        if (key === 'cpu') {

            this._cpuFill = fill;

            this._cpuValue = value;

        } else {

            this._ramFill = fill;

            this._ramValue = value;
        }
    }


    _buildAudio() {

        const header =
            new St.BoxLayout({
                vertical: false,

                style: [
                    'width: 298px',
                    'height: 18px',
                    'spacing: 6px',
                ].join(';'),
            });


        const label =
            new St.Label({
                text: 'AUDIO',

                style: [
                    'font-size: 10px',
                    'font-weight: 700',
                    'width: 45px',
                    'min-width: 45px',
                    'opacity: 0.72',
                ].join(';'),
            });


        const spacer =
            new St.Widget({
                x_expand: true,
            });


        this._audioValue =
            new St.Label({
                text: 'AUDIO 0%',

                style: [
                    'font-size: 10px',
                    'font-weight: 600',
                    'opacity: 0.78',
                ].join(';'),
            });


        header.add_child(
            label
        );

        header.add_child(
            spacer
        );

        header.add_child(
            this._audioValue
        );


        this._widget.add_child(
            header
        );


        this._audioWave =
            new St.BoxLayout({
                vertical: false,

                style: [
                    `width: ${WAVE_WIDTH}px`,
                    `min-width: ${WAVE_WIDTH}px`,

                    `height: ${WAVE_HEIGHT}px`,
                    `min-height: ${WAVE_HEIGHT}px`,

                    'spacing: 2px',
                    'padding: 0px',
                    'margin: 0px',
                ].join(';'),
            });


        this._audioWave.set_x_align(
            Clutter.ActorAlign.FILL
        );

        this._audioWave.set_y_align(
            Clutter.ActorAlign.CENTER
        );


        for (
            let i = 0;
            i < WAVE_COUNT;
            i++
        ) {

            const bar =
                new St.Widget({
                    style: [
                        'width: 4px',
                        'min-width: 4px',

                        'height: 3px',
                        'min-height: 3px',

                        'background-color: rgba(112,220,255,0.30)',

                        'border-radius: 3px',

                        'margin: 0px',
                        'padding: 0px',
                    ].join(';'),
                });


            bar.set_width(
                4
            );

            bar.set_height(
                3
            );

            bar.set_y_align(
                Clutter.ActorAlign.CENTER
            );


            this._audioWave.add_child(
                bar
            );

            this._audioBars.push(
                bar
            );
        }


        this._widget.add_child(
            this._audioWave
        );
    }


    _positionWidget() {

        if (!this._widget)
            return;


        const monitor =
            Main.layoutManager.primaryMonitor;


        if (!monitor)
            return;


        const width = 328;

        const x =
            monitor.x +
            monitor.width -
            width -
            18;

        const y =
            monitor.y +
            52;


        this._widget.set_position(
            x,
            y
        );


        this._widget.show();

        this._widget.raise_top();
    }


    _startMetrics() {

        this._updateMetrics();


        this._metricsTimer =
            GLib.timeout_add(
                GLib.PRIORITY_DEFAULT,
                METRIC_INTERVAL,
                () => {

                    this._updateMetrics();

                    return GLib.SOURCE_CONTINUE;
                }
            );
    }


    _updateMetrics() {

        this._updateCpu();

        this._updateRam();
    }


    _updateCpu() {

        try {

            const [
                ok,
                contents,
            ] =
                GLib.file_get_contents(
                    '/proc/stat'
                );


            if (!ok)
                return;


            const text =
                new TextDecoder().decode(
                    contents
                );


            const line =
                text
                    .split('\n')
                    .find(
                        item =>
                            item.startsWith(
                                'cpu '
                            )
                    );


            if (!line)
                return;


            const parts =
                line
                    .trim()
                    .split(/\s+/)
                    .slice(1)
                    .map(Number);


            const idle =
                (parts[3] || 0) +
                (parts[4] || 0);


            const total =
                parts.reduce(
                    (sum, value) =>
                        sum + value,
                    0
                );


            if (
                this._lastCpuTotal !== null
            ) {

                const totalDelta =
                    total -
                    this._lastCpuTotal;


                const idleDelta =
                    idle -
                    this._lastCpuIdle;


                let percent = 0;


                if (totalDelta > 0) {

                    percent =
                        (
                            1 -
                            (
                                idleDelta /
                                totalDelta
                            )
                        ) * 100;
                }


                percent =
                    Math.max(
                        0,
                        Math.min(
                            100,
                            percent
                        )
                    );


                this._setMetric(
                    this._cpuFill,
                    this._cpuValue,
                    percent,
                    `${percent.toFixed(0)}%`
                );
            }


            this._lastCpuTotal = total;

            this._lastCpuIdle = idle;

        } catch (error) {

            logError(
                error,
                `[${UUID}] CPU update error`
            );
        }
    }


    _updateRam() {

        try {

            const [
                ok,
                contents,
            ] =
                GLib.file_get_contents(
                    '/proc/meminfo'
                );


            if (!ok)
                return;


            const text =
                new TextDecoder().decode(
                    contents
                );


            let totalKb = 0;
            let availableKb = 0;


            for (
                const line
                of text.split('\n')
            ) {

                if (
                    line.startsWith(
                        'MemTotal:'
                    )
                ) {

                    totalKb =
                        Number(
                            line
                                .split(/\s+/)[1]
                        ) || 0;
                }


                if (
                    line.startsWith(
                        'MemAvailable:'
                    )
                ) {

                    availableKb =
                        Number(
                            line
                                .split(/\s+/)[1]
                        ) || 0;
                }
            }


            if (
                totalKb <= 0
            )
                return;


            const usedKb =
                totalKb -
                availableKb;


            const percent =
                Math.max(
                    0,
                    Math.min(
                        100,
                        (
                            usedKb /
                            totalKb
                        ) * 100
                    )
                );


            const usedGb =
                usedKb /
                1024 /
                1024;


            const totalGb =
                totalKb /
                1024 /
                1024;


            this._setMetric(
                this._ramFill,
                this._ramValue,
                percent,
                `${usedGb.toFixed(1)} / ${totalGb.toFixed(1)} GB`
            );

        } catch (error) {

            logError(
                error,
                `[${UUID}] RAM update error`
            );
        }
    }


    _setMetric(
        fill,
        valueLabel,
        percent,
        text
    ) {

        if (!fill || !valueLabel)
            return;


        const width =
            Math.max(
                1,
                Math.round(
                    METRIC_TRACK_WIDTH *
                    percent /
                    100
                )
            );


        fill.set_width(
            width
        );


        valueLabel.set_text(
            text
        );
    }


    _startAudioMeter() {

        this._stopAudioMeter();


        try {

            const helper =
                GLib.build_filenamev([
                    this.path,
                    'niveth-audio-meter.py',
                ]);


            if (
                !Gio.File
                    .new_for_path(helper)
                    .query_exists(null)
            ) {

                log(
                    `[${UUID}] Audio helper missing: ${helper}`
                );

                return;
            }


            this._audioCancellable =
                new Gio.Cancellable();


            this._audioProcess =
                Gio.Subprocess.new(
                    [
                        '/usr/bin/python3',
                        helper,
                    ],

                    Gio.SubprocessFlags.STDOUT_PIPE |
                    Gio.SubprocessFlags.STDERR_PIPE
                );


            this._audioReader =
                new Gio.DataInputStream({
                    base_stream:
                        this._audioProcess
                            .get_stdout_pipe(),
                });


            this._audioReadActive = true;


            this._readAudioLine();


            log(
                `[${UUID}] Audio helper started`
            );

        } catch (error) {

            logError(
                error,
                `[${UUID}] Audio helper start error`
            );
        }
    }


    _readAudioLine() {

        if (
            !this._audioReader ||
            !this._audioReadActive
        )
            return;


        this._audioReader.read_line_async(
            GLib.PRIORITY_DEFAULT,
            this._audioCancellable,
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

                        this._audioReadActive =
                            false;

                        return;
                    }


                    const value =
                        Number.parseFloat(
                            String(line).trim()
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


                        if (
                            this._audioValue
                        ) {

                            this._audioValue.set_text(
                                `AUDIO ${Math.round(this._audioLevel)}%`
                            );
                        }
                    }


                    this._readAudioLine();

                } catch (error) {

                    if (
                        !this._audioCancellable ||
                        !this._audioCancellable.is_cancelled()
                    ) {

                        logError(
                            error,
                            `[${UUID}] Audio read error`
                        );
                    }
                }
            }
        );
    }


    _animateAudio() {

        if (
            !this._audioBars ||
            this._audioBars.length === 0
        )
            return;


        const history =
            this._audioHistory || [];


        const now =
            GLib.get_monotonic_time() /
            1000000;


        for (
            let i = 0;
            i < this._audioBars.length;
            i++
        ) {

            const historyIndex =
                history.length -
                this._audioBars.length +
                i;


            let value =
                historyIndex >= 0
                    ? history[historyIndex]
                    : 0;


            value =
                Number(value);


            if (
                !Number.isFinite(value)
            ) {

                value = 0;
            }


            let level =
                Math.max(
                    0,
                    Math.min(
                        100,
                        value
                    )
                ) / 100;


            /*
             * Very small natural motion.
             *
             * The audio level remains the
             * dominant signal.
             */
            const movement =
                (
                    Math.sin(
                        now * 8 +
                        i * 0.42
                    ) + 1
                ) / 2;


            level =
                Math.max(
                    0.035,
                    Math.min(
                        1,
                        (
                            level * 0.92
                        ) +
                        (
                            movement * 0.05
                        )
                    )
                );


            const height =
                Math.max(
                    3,
                    Math.min(
                        50,
                        Math.round(
                            3 +
                            level * 47
                        )
                    )
                );


            const alpha =
                Math.max(
                    0.30,
                    Math.min(
                        1.0,
                        0.32 +
                        level * 0.68
                    )
                );


            const bar =
                this._audioBars[i];


            if (!bar)
                continue;


            bar.set_height(
                height
            );


            bar.set_width(
                4
            );


            bar.set_y_align(
                Clutter.ActorAlign.CENTER
            );


            bar.set_style(
                [
                    'width: 4px',
                    'min-width: 4px',

                    `height: ${height}px`,
                    `min-height: ${height}px`,

                    `background-color: rgba(112,220,255,${alpha.toFixed(2)})`,

                    'border-radius: 3px',

                    'margin: 0px',
                    'padding: 0px',
                ].join(';')
            );
        }
    }


    _stopAudioMeter() {

        this._audioReadActive =
            false;


        if (
            this._audioCancellable
        ) {

            try {

                this._audioCancellable.cancel();

            } catch (error) {
            }
        }


        if (
            this._audioReader
        ) {

            try {

                this._audioReader.close(
                    null
                );

            } catch (error) {
            }
        }


        this._audioReader = null;


        if (
            this._audioProcess
        ) {

            try {

                this._audioProcess.force_exit();

            } catch (error) {
            }
        }


        this._audioProcess = null;
    }
}
JS

echo "[PASS] extension.js"
echo

# ------------------------------------------------------------
# 7. Basic source verification
# ------------------------------------------------------------

echo "[7/10] Verifying V8 source..."

required_strings=(
    "class NivethSystemMonitor"
    "_buildAudio()"
    "_animateAudio()"
    "_startAudioMeter()"
    "_readAudioLine()"
    "_audioHistory"
    "_audioBars"
    "WAVE_COUNT = 40"
    "AUDIO"
)

for item in "${required_strings[@]}"; do

    if grep -Fq \
        "$item" \
        "$EXT/extension.js"
    then
        echo "[PASS] $item"
    else
        echo "[FAIL] Missing: $item"
        exit 1
    fi
done

if grep -Fq \
    "audio.value" \
    "$EXT/extension.js"
then
    echo "[FAIL] Old audio.value code still exists."
    exit 1
else
    echo "[PASS] Old audio.value code removed."
fi

echo

# ------------------------------------------------------------
# 8. Rootfs synchronization
# ------------------------------------------------------------

echo "[8/10] Synchronizing V8 to Niveth rootfs..."

if [ -d "$ROOTFS_EXT" ]; then

    sudo install \
        -m 0644 \
        "$EXT/extension.js" \
        "$ROOTFS_EXT/extension.js"

    sudo install \
        -m 0644 \
        "$EXT/metadata.json" \
        "$ROOTFS_EXT/metadata.json"

    sudo install \
        -m 0644 \
        "$EXT/niveth-audio-meter.py" \
        "$ROOTFS_EXT/niveth-audio-meter.py"

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
# 9. Audio helper quick test
# ------------------------------------------------------------

echo "[9/10] Testing audio helper briefly..."

timeout 3s \
    python3 \
    "$EXT/niveth-audio-meter.py" \
    > /tmp/niveth-v8-audio-test.txt \
    2>/tmp/niveth-v8-audio-error.txt \
    || true

echo "Sample audio values:"

head -8 \
    /tmp/niveth-v8-audio-test.txt \
    2>/dev/null || true

echo

if [ -s /tmp/niveth-v8-audio-test.txt ]; then
    echo "[PASS] Audio helper produces values."
else
    echo "[WARN] Audio helper produced no values."
    echo
    cat /tmp/niveth-v8-audio-error.txt \
        2>/dev/null || true
fi

echo

# ------------------------------------------------------------
# 10. Enable and verify
# ------------------------------------------------------------

echo "[10/10] Enabling V8..."

gnome-extensions disable \
    "$UUID" \
    2>/dev/null || true

sleep 2

gnome-extensions enable \
    "$UUID" \
    2>/dev/null || true

sleep 5

echo
echo "============================================================"
echo " FINAL STATUS"
echo "============================================================"

gnome-extensions info \
    "$UUID" \
    2>&1 || true

echo
echo "============================================================"
echo " RECENT SYSTEM MONITOR ERRORS"
echo "============================================================"

journalctl \
    --user \
    -b \
    --no-pager \
    -o cat \
    2>/dev/null |
grep -Ei \
    "niveth-system-monitor|NIVETH AUDIO|TypeError|ReferenceError|SyntaxError" |
tail -40 \
|| true

echo
echo "============================================================"
echo " V8 INSTALL COMPLETE"
echo "============================================================"
echo
echo "Backup:"
echo "  $BACKUP"
echo
echo "Waveform:"
echo "  40 vertical bars"
echo "  real audio history"
echo "  YouTube / music / video reactive"
echo
