#!/usr/bin/env bash

set -u

UUID="niveth-system-monitor@nivethos"
EXT="$HOME/.local/share/gnome-shell/extensions/$UUID"
ROOTFS="$HOME/Niveth/build/rootfs"
ROOTFS_EXT="$ROOTFS/usr/share/gnome-shell/extensions/$UUID"

echo
echo "=============================================="
echo " Niveth System Monitor - AUDIO renderer fix"
echo "=============================================="
echo

if [ ! -d "$EXT" ]; then
    echo "ERROR: Extension directory not found:"
    echo "  $EXT"
    echo
    exit 1
fi

if [ ! -f "$EXT/metadata.json" ]; then
    echo "ERROR: metadata.json not found:"
    echo "  $EXT/metadata.json"
    echo
    exit 1
fi

echo "[1/7] Creating backup..."
BACKUP="$EXT/backup-audio-render-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$BACKUP"

cp -f "$EXT/extension.js" "$BACKUP/extension.js" 2>/dev/null || true
cp -f "$EXT/niveth-audio-meter.py" "$BACKUP/niveth-audio-meter.py" 2>/dev/null || true

echo "Backup:"
echo "  $BACKUP"
echo

echo "[2/7] Disabling extension temporarily..."
gnome-extensions disable "$UUID" 2>/dev/null || true
sleep 1

echo "[3/7] Writing new extension.js..."

cat > "$EXT/extension.js" <<'JS'
import GLib from 'gi://GLib';
import Gio from 'gi://Gio';
import St from 'gi://St';
import Clutter from 'gi://Clutter';
import Cairo from 'cairo';

import * as Main from 'resource:///org/gnome/shell/ui/main.js';
import {Extension} from 'resource:///org/gnome/shell/extensions/extension.js';

const UUID = 'niveth-system-monitor@nivethos';

const WAVE_COUNT = 48;
const AUDIO_INTERVAL = 30;
const METRIC_INTERVAL = 1000;

export default class NivethSystemMonitorExtension extends Extension {

    enable() {
        this._audioHistory = new Array(WAVE_COUNT).fill(0.02);
        this._audioTarget = 0;
        this._audioVisual = 0;
        this._audioPhase = 0;

        this._audioProcess = null;
        this._audioReader = null;
        this._audioCancellable = null;

        this._audioAnimationId = 0;
        this._metricsTimerId = 0;
        this._monitorChangedId = 0;

        this._lastCpuTotal = null;
        this._lastCpuIdle = null;

        this._buildUi();

        Main.layoutManager.addChrome(this._widget, {
            trackFullscreen: true,
        });

        this._positionWidget();

        this._monitorChangedId =
            Main.layoutManager.connect(
                'monitors-changed',
                () => this._positionWidget()
            );

        this._startMetrics();
        this._startAudioMeter();

        this._audioAnimationId = GLib.timeout_add(
            GLib.PRIORITY_DEFAULT,
            AUDIO_INTERVAL,
            () => {
                this._animateAudio();
                return GLib.SOURCE_CONTINUE;
            }
        );

        log(`[${UUID}] enabled`);
    }

    disable() {
        log(`[${UUID}] disabling`);

        if (this._metricsTimerId) {
            GLib.source_remove(this._metricsTimerId);
            this._metricsTimerId = 0;
        }

        if (this._audioAnimationId) {
            GLib.source_remove(this._audioAnimationId);
            this._audioAnimationId = 0;
        }

        if (this._monitorChangedId) {
            Main.layoutManager.disconnect(this._monitorChangedId);
            this._monitorChangedId = 0;
        }

        this._stopAudioMeter();

        if (this._widget) {
            this._widget.destroy();
            this._widget = null;
        }

        this._audioArea = null;
        this._cpuFill = null;
        this._ramFill = null;
        this._cpuValue = null;
        this._ramValue = null;
        this._audioValue = null;
    }

    _buildUi() {
        this._widget = new St.BoxLayout({
            vertical: true,
            style: [
                'background-color: rgba(18, 18, 28, 0.92)',
                'border: 1px solid rgba(255, 255, 255, 0.10)',
                'border-radius: 14px',
                'padding: 12px 14px',
                'spacing: 8px',
                'width: 320px',
            ].join(';'),
        });

        const title = new St.Label({
            text: 'SYSTEM MONITOR',
            style: [
                'font-size: 10px',
                'font-weight: 700',
                'letter-spacing: 1px',
                'opacity: 0.65',
                'margin-bottom: 2px',
            ].join(';'),
        });

        this._widget.add_child(title);

        const cpuRow = this._createMetricRow('CPU');
        this._cpuValue = cpuRow.value;
        this._cpuFill = cpuRow.fill;

        const ramRow = this._createMetricRow('RAM');
        this._ramValue = ramRow.value;
        this._ramFill = ramRow.fill;

        this._widget.add_child(cpuRow.row);
        this._widget.add_child(ramRow.row);

        const audioTitle = new St.Label({
            text: 'AUDIO',
            style: [
                'font-size: 10px',
                'font-weight: 700',
                'letter-spacing: 1px',
                'opacity: 0.65',
                'margin-top: 3px',
                'margin-bottom: 1px',
            ].join(';'),
        });

        const audioHeader = new St.BoxLayout({
            vertical: false,
            style: 'spacing: 8px;',
        });

        this._audioValue = new St.Label({
            text: 'AUDIO 0%',
            style: [
                'font-size: 10px',
                'font-weight: 600',
                'opacity: 0.75',
            ].join(';'),
        });

        audioHeader.add_child(audioTitle);
        audioHeader.add_child(new St.Widget({x_expand: true}));
        audioHeader.add_child(this._audioValue);

        this._widget.add_child(audioHeader);

        /*
         * IMPORTANT:
         * One DrawingArea handles the entire waveform.
         * This avoids the old St.Widget-height renderer.
         */
        this._audioArea = new St.DrawingArea({
            style: [
                'width: 292px',
                'height: 58px',
            ].join(';'),
        });

        this._audioArea.connect('repaint', area => {
            this._paintAudio(area);
        });

        this._widget.add_child(this._audioArea);
    }

    _createMetricRow(name) {
        const row = new St.BoxLayout({
            vertical: false,
            style: 'spacing: 8px;',
        });

        const label = new St.Label({
            text: name,
            style: [
                'font-size: 10px',
                'font-weight: 700',
                'width: 28px',
                'opacity: 0.7',
            ].join(';'),
        });

        const barBackground = new St.Widget({
            style: [
                'background-color: rgba(255,255,255,0.08)',
                'border-radius: 5px',
                'height: 8px',
                'width: 220px',
            ].join(';'),
        });

        const fill = new St.Widget({
            style: [
                'background-color: rgba(125, 220, 255, 0.95)',
                'border-radius: 5px',
                'height: 8px',
                'width: 0px',
            ].join(';'),
        });

        barBackground.add_child(fill);

        const value = new St.Label({
            text: '0%',
            style: [
                'font-size: 10px',
                'font-weight: 600',
                'width: 48px',
                'x-align: END',
                'opacity: 0.75',
            ].join(';'),
        });

        row.add_child(label);
        row.add_child(barBackground);
        row.add_child(value);

        return {
            row,
            fill,
            value,
        };
    }

    _positionWidget() {
        if (!this._widget)
            return;

        const monitor = Main.layoutManager.primaryMonitor;

        if (!monitor)
            return;

        const width = 320;
        const x = monitor.x + monitor.width - width - 18;
        const y = monitor.y + 46;

        this._widget.set_position(x, y);
        this._widget.show();
        this._widget.raise_top();
    }

    _startMetrics() {
        this._updateMetrics();

        this._metricsTimerId = GLib.timeout_add(
            GLib.PRIORITY_DEFAULT,
            METRIC_INTERVAL,
            () => {
                this._updateMetrics();
                return GLib.SOURCE_CONTINUE;
            }
        );
    }

    _updateMetrics() {
        try {
            const [okCpu, bytesCpu] =
                GLib.file_get_contents('/proc/stat');

            if (okCpu) {
                const cpuText = new TextDecoder().decode(bytesCpu);
                const cpuLine =
                    cpuText
                        .split('\n')
                        .find(line => line.startsWith('cpu '));

                if (cpuLine) {
                    const parts = cpuLine.trim().split(/\s+/);
                    const values = parts
                        .slice(1)
                        .map(Number)
                        .filter(value => Number.isFinite(value));

                    const idle =
                        (values[3] || 0) +
                        (values[4] || 0);

                    const total = values.reduce(
                        (sum, value) => sum + value,
                        0
                    );

                    if (this._lastCpuTotal !== null) {
                        const deltaTotal =
                            total - this._lastCpuTotal;

                        const deltaIdle =
                            idle - this._lastCpuIdle;

                        let usage = 0;

                        if (deltaTotal > 0) {
                            usage =
                                100 *
                                (1 - (deltaIdle / deltaTotal));
                        }

                        usage =
                            Math.max(
                                0,
                                Math.min(100, usage)
                            );

                        this._setBar(
                            this._cpuFill,
                            this._cpuValue,
                            usage,
                            `${usage.toFixed(0)}%`
                        );
                    }

                    this._lastCpuTotal = total;
                    this._lastCpuIdle = idle;
                }
            }

            const [okMem, bytesMem] =
                GLib.file_get_contents('/proc/meminfo');

            if (okMem) {
                const memText =
                    new TextDecoder().decode(bytesMem);

                let memTotal = 0;
                let memAvailable = 0;

                for (const line of memText.split('\n')) {
                    if (line.startsWith('MemTotal:')) {
                        memTotal =
                            Number(
                                line
                                    .split(/\s+/)[1]
                                    ?.trim()
                            ) || 0;
                    }

                    if (line.startsWith('MemAvailable:')) {
                        memAvailable =
                            Number(
                                line
                                    .split(/\s+/)[1]
                                    ?.trim()
                            ) || 0;
                    }
                }

                if (memTotal > 0) {
                    const used = memTotal - memAvailable;
                    const ratio = used / memTotal;
                    const percent = Math.max(
                        0,
                        Math.min(100, ratio * 100)
                    );

                    const usedGb = used / 1024 / 1024;
                    const totalGb = memTotal / 1024 / 1024;

                    this._setBar(
                        this._ramFill,
                        this._ramValue,
                        percent,
                        `${usedGb.toFixed(1)} / ${totalGb.toFixed(1)} GB`
                    );
                }
            }

        } catch (error) {
            logError(error, `[${UUID}] metrics error`);
        }
    }

    _setBar(fill, valueLabel, percent, text) {
        if (!fill || !valueLabel)
            return;

        const width = 220 * (percent / 100);

        fill.set_width(
            Math.max(2, width)
        );

        valueLabel.set_text(text);
    }

    _startAudioMeter() {
        try {
            const helper =
                GLib.build_filenamev([
                    this.path,
                    'niveth-audio-meter.py',
                ]);

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
                        this._audioProcess.get_stdout_pipe(),
                });

            this._readAudioLine();

            log(
                `[${UUID}] audio helper started: ${helper}`
            );

        } catch (error) {
            logError(
                error,
                `[${UUID}] failed to start audio helper`
            );
        }
    }

    _readAudioLine() {
        if (!this._audioReader)
            return;

        this._audioReader.read_line_async(
            GLib.PRIORITY_DEFAULT,
            this._audioCancellable,
            (stream, result) => {

                try {
                    const [line] =
                        this._audioReader
                            .read_line_finish_utf8(result);

                    if (line === null) {
                        return;
                    }

                    const value =
                        Number.parseFloat(
                            String(line).trim()
                        );

                    if (Number.isFinite(value)) {
                        this._handleAudioLevel(value);
                    }

                    this._readAudioLine();

                } catch (error) {
                    if (
                        !this._audioCancellable ||
                        !this._audioCancellable.is_cancelled()
                    ) {
                        logError(
                            error,
                            `[${UUID}] audio read error`
                        );
                    }
                }
            }
        );
    }

    _handleAudioLevel(levelPercent) {
        const level =
            Math.max(
                0,
                Math.min(1, levelPercent / 100)
            );

        this._audioTarget = level;

        this._audioHistory.push(level);

        if (this._audioHistory.length > WAVE_COUNT) {
            this._audioHistory.shift();
        }

        if (this._audioValue) {
            this._audioValue.set_text(
                `AUDIO ${Math.round(levelPercent)}%`
            );
        }

        if (this._audioArea) {
            this._audioArea.queue_repaint();
        }
    }

    _animateAudio() {
        this._audioVisual +=
            (this._audioTarget - this._audioVisual) * 0.28;

        this._audioPhase += 0.16;

        if (this._audioPhase > Math.PI * 2) {
            this._audioPhase -= Math.PI * 2;
        }

        if (this._audioArea) {
            this._audioArea.queue_repaint();
        }
    }

    _paintAudio(area) {
        let cr = null;

        try {
            cr = area.get_context();

            const [width, height] =
                area.get_surface_size();

            if (width <= 0 || height <= 0)
                return;

            /*
             * Clear previous frame.
             */
            cr.save();
            cr.setOperator(Cairo.Operator.CLEAR);
            cr.paint();
            cr.restore();

            /*
             * Background track.
             */
            cr.save();

            cr.setSourceRGBA(
                1.0,
                1.0,
                1.0,
                0.045
            );

            cr.rectangle(
                0,
                Math.floor(height / 2) - 1,
                width,
                2
            );

            cr.fill();

            cr.restore();

            const count = this._audioHistory.length;

            if (count === 0)
                return;

            const gap = 3;
            const barWidth =
                Math.max(
                    2,
                    (width - gap * (WAVE_COUNT - 1))
                    / WAVE_COUNT
                );

            const maxBarHeight =
                Math.max(6, height - 6);

            /*
             * Draw latest audio data as vertical waveform.
             *
             * The phase makes the visual continuously travel,
             * while the actual audio level controls amplitude.
             */
            for (let i = 0; i < count; i++) {
                const sample =
                    this._audioHistory[i] ?? 0;

                const normalized =
                    Math.max(
                        0,
                        Math.min(1, sample)
                    );

                const phase =
                    this._audioPhase +
                    i * 0.47;

                const movement =
                    0.35 +
                    0.65 *
                    Math.abs(Math.sin(phase));

                const strength =
                    Math.max(
                        0.035,
                        normalized * movement
                    );

                const barHeight =
                    Math.max(
                        2,
                        strength * maxBarHeight
                    );

                const x =
                    i * (barWidth + gap);

                const y =
                    (height - barHeight) / 2;

                /*
                 * Dynamic opacity:
                 * louder audio = brighter bar.
                 */
                const alpha =
                    0.38 +
                    0.52 *
                    Math.min(1, normalized + 0.15);

                cr.save();

                cr.setSourceRGBA(
                    0.49,
                    0.86,
                    1.0,
                    alpha
                );

                cr.rectangle(
                    x,
                    y,
                    barWidth,
                    barHeight
                );

                cr.fill();

                cr.restore();
            }

        } catch (error) {
            logError(
                error,
                `[${UUID}] audio repaint error`
            );
        } finally {
            if (cr) {
                /*
                 * Required for Cairo contexts returned
                 * by St.DrawingArea.get_context().
                 */
                cr.$dispose();
            }
        }
    }

    _stopAudioMeter() {
        try {
            if (this._audioCancellable) {
                this._audioCancellable.cancel();
            }
        } catch (error) {
            logError(
                error,
                `[${UUID}] audio cancellable error`
            );
        }

        try {
            if (this._audioReader) {
                this._audioReader.close(null);
            }
        } catch (error) {
            logError(
                error,
                `[${UUID}] audio reader close error`
            );
        }

        this._audioReader = null;

        try {
            if (this._audioProcess) {
                this._audioProcess.force_exit();
            }
        } catch (error) {
            logError(
                error,
                `[${UUID}] audio process stop error`
            );
        }

        this._audioProcess = null;
        this._audioCancellable = null;
    }
}
JS

echo "extension.js written."
echo

echo "[4/7] Writing audio helper..."

cat > "$EXT/niveth-audio-meter.py" <<'PY'
#!/usr/bin/env python3

import math
import struct
import subprocess
import sys


def run_command(args):
    try:
        return subprocess.check_output(
            args,
            text=True,
            stderr=subprocess.DEVNULL,
        ).strip()
    except Exception:
        return ""


def find_monitor_source():
    sink = run_command(["pactl", "get-default-sink"])

    if sink:
        return f"{sink}.monitor"

    source = run_command(["pactl", "get-default-source"])

    if source:
        return source

    return ""


def clamp(value, low, high):
    return max(low, min(high, value))


def main():
    source = find_monitor_source()

    if not source:
        print("0", flush=True)
        return 1

    command = [
        "/usr/bin/parec",
        "--device",
        source,
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
        print("0", flush=True)
        print(
            f"niveth audio helper error: {error}",
            file=sys.stderr,
        )
        return 1

    bytes_per_sample = 2
    samples_per_block = 882
    block_size = samples_per_block * bytes_per_sample

    while True:
        data = process.stdout.read(block_size)

        if not data:
            break

        usable = len(data) - (len(data) % 2)

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
            value = sample / 32768.0
            sum_squares += value * value

        rms = math.sqrt(
            sum_squares / max(1, count)
        )

        if rms <= 0:
            level = 0.0
        else:
            db = 20.0 * math.log10(rms)

            # Map roughly -60dB .. 0dB to 0 .. 100.
            level = ((db + 60.0) / 60.0) * 100.0

        level = clamp(level, 0.0, 100.0)

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
    raise SystemExit(main())
PY

chmod +x "$EXT/niveth-audio-meter.py"

echo "niveth-audio-meter.py written."
echo

echo "[5/7] Checking files..."
ls -lh "$EXT/extension.js"
ls -lh "$EXT/niveth-audio-meter.py"
echo

echo "[6/7] Syncing to Niveth rootfs when available..."

if [ -d "$ROOTFS_EXT" ]; then
    cp -f "$EXT/extension.js" "$ROOTFS_EXT/extension.js"
    cp -f "$EXT/niveth-audio-meter.py" \
        "$ROOTFS_EXT/niveth-audio-meter.py"

    chmod +x "$ROOTFS_EXT/niveth-audio-meter.py"

    echo "Rootfs synced:"
    echo "  $ROOTFS_EXT"
else
    echo "Rootfs extension directory not present:"
    echo "  $ROOTFS_EXT"
    echo "Skipping rootfs sync."
fi

echo

echo "[7/7] Enabling extension..."

gnome-extensions enable "$UUID" 2>/dev/null || true

sleep 3

echo
echo "=============================================="
echo " RESULT"
echo "=============================================="
echo

gnome-extensions info "$UUID" 2>/dev/null || true

echo
echo "Files:"
echo "  $EXT/extension.js"
echo "  $EXT/niveth-audio-meter.py"
echo

echo "Backup:"
echo "  $BACKUP"
echo

echo "=============================================="
echo " DONE"
echo "=============================================="
echo
echo "Play YouTube now and watch:"
echo
echo "  AUDIO xx%"
echo
echo "The vertical waveform should now animate."
echo
