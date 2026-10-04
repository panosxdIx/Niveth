#!/usr/bin/env bash
set -euo pipefail

EXT_ID="niveth-system-monitor@nivethos"
LIVE_DIR="$HOME/.local/share/gnome-shell/extensions/$EXT_ID"
ROOTFS_DIR="$HOME/Niveth/build/rootfs/usr/share/gnome-shell/extensions/$EXT_ID"
AUDIO_HELPER="/usr/local/bin/niveth-audio-meter.py"

echo "=============================================="
echo " NIVETH SYSTEM MONITOR"
echo " CPU/RAM = horizontal bars"
echo " AUDIO    = waveform"
echo "=============================================="

mkdir -p "$LIVE_DIR"
sudo mkdir -p "$ROOTFS_DIR"

echo
echo "[1/8] Disabling extension..."
gnome-extensions disable "$EXT_ID" 2>/dev/null || true
sleep 2

echo
echo "[2/8] Writing extension.js..."

cat > "$LIVE_DIR/extension.js" <<'EOF'
import GLib from 'gi://GLib';
import Gio from 'gi://Gio';
import St from 'gi://St';
import Clutter from 'gi://Clutter';

import Main from 'resource:///org/gnome/shell/ui/main.js';

const EXT_ID = 'niveth-system-monitor@nivethos';

const WIDGET_WIDTH = 330;
const WIDGET_HEIGHT = 154;

const TOP_OFFSET = 82;
const RIGHT_OFFSET = 26;

const TRACK_WIDTH = 308;
const TRACK_HEIGHT = 4;

const WAVE_COUNT = 34;
const WAVE_WIDTH = 4;
const WAVE_GAP = 4;
const WAVE_AREA_WIDTH = 308;
const WAVE_MAX_HEIGHT = 25;

const AUDIO_HELPER = '/usr/local/bin/niveth-audio-meter.py';

export default class NivethSystemMonitor {

    constructor() {
        this._widget = null;
        this._panel = null;

        this._cpuValue = null;
        this._cpuFill = null;

        this._ramValue = null;
        this._ramFill = null;

        this._waveBox = null;
        this._waveBars = [];

        this._timer = null;
        this._audioProcess = null;
        this._audioStdout = null;

        this._audioHistory = new Array(WAVE_COUNT).fill(0);

        this._prevTotal = null;
        this._prevIdle = null;
    }

    enable() {
        this._build();

        Main.layoutManager.addChrome(this._widget, {
            trackFullscreen: true,
        });

        this._position();

        this._updateMetrics();
        this._startAudioMeter();

        this._timer = GLib.timeout_add(
            GLib.PRIORITY_DEFAULT,
            1000,
            () => {
                this._updateMetrics();
                return GLib.SOURCE_CONTINUE;
            }
        );
    }

    disable() {
        if (this._timer !== null) {
            GLib.source_remove(this._timer);
            this._timer = null;
        }

        this._stopAudioMeter();

        if (this._widget) {
            this._widget.destroy();
            this._widget = null;
        }

        this._panel = null;

        this._cpuValue = null;
        this._cpuFill = null;

        this._ramValue = null;
        this._ramFill = null;

        this._waveBox = null;
        this._waveBars = [];

        this._audioHistory = new Array(WAVE_COUNT).fill(0);

        this._prevTotal = null;
        this._prevIdle = null;
    }

    _build() {
        this._widget = new St.Widget({
            width: WIDGET_WIDTH,
            height: WIDGET_HEIGHT,
            reactive: false,
            can_focus: false,
            style_class: 'niveth-system-monitor',
        });

        this._panel = new St.BoxLayout({
            vertical: true,
            width: WIDGET_WIDTH,
            height: WIDGET_HEIGHT,
            style_class: 'monitor-panel',
        });

        this._widget.set_child(this._panel);

        const title = new St.Label({
            text: 'NIVETH SYSTEM',
            style_class: 'monitor-title',
        });

        this._panel.add_child(title);

        this._panel.add_child(
            this._createMetricRow('CPU', 'cpu')
        );

        this._panel.add_child(
            this._createMetricRow('RAM', 'ram')
        );

        this._panel.add_child(
            this._createAudioSection()
        );
    }

    _createMetricRow(labelText, type) {
        const row = new St.BoxLayout({
            vertical: true,
            style_class: 'metric-row',
        });

        const header = new St.BoxLayout({
            x_expand: true,
            style_class: 'metric-header',
        });

        const label = new St.Label({
            text: labelText,
            x_expand: true,
            style_class: 'metric-label',
        });

        const value = new St.Label({
            text: type === 'cpu' ? '0%' : '0.0 / 0.0 GB',
            style_class: 'metric-value',
        });

        header.add_child(label);
        header.add_child(value);

        /*
         * CPU/RAM HAVE ONLY A HORIZONTAL BAR.
         * NO VERTICAL WAVEFORM IS CREATED HERE.
         */

        const track = new St.Widget({
            width: TRACK_WIDTH,
            height: TRACK_HEIGHT,
            reactive: false,
            style_class: `metric-track ${type}-track`,
        });

        const fill = new St.Widget({
            width: 0,
            height: TRACK_HEIGHT,
            reactive: false,
            style_class: `metric-fill ${type}-fill`,
        });

        track.add_child(fill);

        row.add_child(header);
        row.add_child(track);

        if (type === 'cpu') {
            this._cpuValue = value;
            this._cpuFill = fill;
        } else {
            this._ramValue = value;
            this._ramFill = fill;
        }

        return row;
    }

    _createAudioSection() {
        const section = new St.BoxLayout({
            vertical: true,
            style_class: 'audio-section',
        });

        const header = new St.BoxLayout({
            x_expand: true,
            style_class: 'audio-header',
        });

        const label = new St.Label({
            text: 'AUDIO',
            x_expand: true,
            style_class: 'metric-label audio-label',
        });

        const value = new St.Label({
            text: 'LIVE',
            style_class: 'audio-value',
        });

        header.add_child(label);
        header.add_child(value);

        section.add_child(header);

        /*
         * ONLY AUDIO GETS VERTICAL WAVEFORM BARS.
         */

        this._waveBox = new St.BoxLayout({
            width: WAVE_AREA_WIDTH,
            height: WAVE_MAX_HEIGHT,
            style_class: 'audio-wave',
        });

        this._waveBox.set_style(
            `width: ${WAVE_AREA_WIDTH}px; height: ${WAVE_MAX_HEIGHT}px;`
        );

        this._waveBars = [];

        for (let i = 0; i < WAVE_COUNT; i++) {
            const bar = new St.Widget({
                width: WAVE_WIDTH,
                height: 2,
                reactive: false,
                style_class: 'audio-wave-bar',
            });

            bar.set_y_align(Clutter.ActorAlign.CENTER);

            this._waveBox.add_child(bar);
            this._waveBars.push(bar);
        }

        section.add_child(this._waveBox);

        return section;
    }

    _position() {
        if (!this._widget)
            return;

        const monitor = Main.layoutManager.primaryMonitor;

        const x =
            monitor.x +
            monitor.width -
            WIDGET_WIDTH -
            RIGHT_OFFSET;

        const y =
            monitor.y +
            TOP_OFFSET;

        this._widget.set_position(x, y);
    }

    _readFile(path) {
        try {
            const [ok, contents] = GLib.file_get_contents(path);

            if (!ok || !contents)
                return null;

            return new TextDecoder().decode(contents);
        } catch (e) {
            return null;
        }
    }

    _getCpuUsage() {
        const text = this._readFile('/proc/stat');

        if (!text)
            return 0;

        const firstLine = text.split('\n')[0];

        if (!firstLine.startsWith('cpu '))
            return 0;

        const parts = firstLine.trim().split(/\s+/);

        if (parts.length < 5)
            return 0;

        const user = Number(parts[1]) || 0;
        const nice = Number(parts[2]) || 0;
        const system = Number(parts[3]) || 0;
        const idle = Number(parts[4]) || 0;
        const iowait = Number(parts[5]) || 0;
        const irq = Number(parts[6]) || 0;
        const softirq = Number(parts[7]) || 0;
        const steal = Number(parts[8]) || 0;

        const idleTotal = idle + iowait;

        const total =
            user +
            nice +
            system +
            idle +
            iowait +
            irq +
            softirq +
            steal;

        if (this._prevTotal === null) {
            this._prevTotal = total;
            this._prevIdle = idleTotal;
            return 0;
        }

        const totalDelta = total - this._prevTotal;
        const idleDelta = idleTotal - this._prevIdle;

        this._prevTotal = total;
        this._prevIdle = idleTotal;

        if (totalDelta <= 0)
            return 0;

        let usage =
            100 *
            (1 - (idleDelta / totalDelta));

        usage = Math.max(
            0,
            Math.min(100, usage)
        );

        return usage;
    }

    _getRamUsage() {
        const text = this._readFile('/proc/meminfo');

        if (!text) {
            return {
                percent: 0,
                usedGB: 0,
                totalGB: 0,
            };
        }

        let totalKB = 0;
        let availableKB = 0;

        for (const line of text.split('\n')) {

            if (line.startsWith('MemTotal:')) {
                totalKB =
                    Number(
                        line
                            .replace('MemTotal:', '')
                            .trim()
                            .split(/\s+/)[0]
                    ) || 0;
            }

            if (line.startsWith('MemAvailable:')) {
                availableKB =
                    Number(
                        line
                            .replace('MemAvailable:', '')
                            .trim()
                            .split(/\s+/)[0]
                    ) || 0;
            }
        }

        if (totalKB <= 0) {
            return {
                percent: 0,
                usedGB: 0,
                totalGB: 0,
            };
        }

        const usedKB =
            Math.max(
                0,
                totalKB - availableKB
            );

        let percent =
            (usedKB / totalKB) * 100;

        percent = Math.max(
            0,
            Math.min(100, percent)
        );

        return {
            percent,
            usedGB: usedKB / 1024 / 1024,
            totalGB: totalKB / 1024 / 1024,
        };
    }

    _setHorizontalBar(fill, percent) {
        if (!fill)
            return;

        const safe =
            Math.max(
                0,
                Math.min(100, percent)
            );

        const width =
            Math.round(
                TRACK_WIDTH *
                (safe / 100)
            );

        fill.set_width(width);
    }

    _updateMetrics() {
        if (!this._widget)
            return;

        const cpu = this._getCpuUsage();
        const ram = this._getRamUsage();

        if (this._cpuValue) {
            this._cpuValue.set_text(
                `${Math.round(cpu)}%`
            );
        }

        if (this._ramValue) {
            this._ramValue.set_text(
                `${ram.usedGB.toFixed(1)} / ${ram.totalGB.toFixed(1)} GB`
            );
        }

        /*
         * CPU = horizontal bar only
         */
        this._setHorizontalBar(
            this._cpuFill,
            cpu
        );

        /*
         * RAM = horizontal bar only
         */
        this._setHorizontalBar(
            this._ramFill,
            ram.percent
        );
    }

    _startAudioMeter() {
        this._stopAudioMeter();

        try {
            this._audioProcess =
                Gio.Subprocess.new(
                    ['python3', AUDIO_HELPER],
                    Gio.SubprocessFlags.STDOUT_PIPE |
                    Gio.SubprocessFlags.STDERR_PIPE
                );

            this._audioStdout =
                new Gio.DataInputStream({
                    base_stream:
                        this._audioProcess.get_stdout_pipe(),
                });

            this._readAudioLine();

        } catch (e) {
            this._fillWaveform(0);
        }
    }

    _readAudioLine() {
        if (!this._audioStdout)
            return;

        this._audioStdout.read_line_async(
            GLib.PRIORITY_DEFAULT,
            null,
            (stream, result) => {

                try {
                    const [line] =
                        stream.read_line_finish_utf8(
                            result
                        );

                    if (line === null) {
                        this._fillWaveform(0);
                        this._audioStdout = null;
                        return;
                    }

                    const text =
                        line.trim();

                    let level =
                        Number(text);

                    if (!Number.isFinite(level))
                        level = 0;

                    level =
                        Math.max(
                            0,
                            Math.min(100, level)
                        );

                    this._pushAudioLevel(level);

                    this._readAudioLine();

                } catch (e) {
                    this._fillWaveform(0);
                    this._audioStdout = null;
                }
            }
        );
    }

    _pushAudioLevel(level) {
        this._audioHistory.shift();
        this._audioHistory.push(level);

        this._drawWaveform();
    }

    _fillWaveform(level) {
        this._audioHistory =
            new Array(WAVE_COUNT)
                .fill(level);

        this._drawWaveform();
    }

    _drawWaveform() {
        if (!this._waveBars.length)
            return;

        for (let i = 0; i < this._waveBars.length; i++) {

            const level =
                this._audioHistory[i] || 0;

            /*
             * Small minimum height so the waveform
             * remains visible during silence.
             */
            const height =
                Math.max(
                    2,
                    Math.round(
                        (level / 100) *
                        WAVE_MAX_HEIGHT
                    )
                );

            const bar =
                this._waveBars[i];

            bar.set_height(height);

            bar.set_y(
                Math.round(
                    (WAVE_MAX_HEIGHT - height) / 2
                )
            );
        }
    }

    _stopAudioMeter() {
        if (this._audioStdout) {
            try {
                this._audioStdout.close(null);
            } catch (e) {
            }

            this._audioStdout = null;
        }

        if (this._audioProcess) {
            try {
                this._audioProcess.force_exit();
            } catch (e) {
            }

            this._audioProcess = null;
        }
    }
}
EOF

echo "[PASS] extension.js written"

echo
echo "[3/8] Writing stylesheet.css..."

cat > "$LIVE_DIR/stylesheet.css" <<'EOF'
.niveth-system-monitor {
    background: transparent;
}

.monitor-panel {
    width: 330px;
    height: 154px;

    padding: 9px 11px 10px 11px;

    background-color: rgba(18, 20, 42, 0.52);

    border: 1px solid rgba(170, 170, 255, 0.20);

    border-radius: 15px;

    box-shadow:
        0 8px 30px rgba(0, 0, 0, 0.28),
        inset 0 1px 0 rgba(255, 255, 255, 0.05);
}

.monitor-title {
    margin-left: 1px;
    margin-bottom: 5px;

    font-size: 10px;
    font-weight: 500;

    letter-spacing: 2px;

    color: rgba(210, 210, 255, 0.72);
}

.metric-row {
    spacing: 3px;

    margin-top: 1px;
    margin-bottom: 4px;
}

.metric-header {
    width: 308px;
}

.metric-label {
    font-size: 11px;
    font-weight: 500;

    letter-spacing: 1px;

    color: rgba(240, 240, 255, 0.90);
}

.metric-value {
    font-size: 10px;
    font-weight: 400;

    color: rgba(220, 220, 255, 0.72);
}

/*
 * CPU AND RAM:
 * horizontal tracks only.
 */

.metric-track {
    width: 308px;
    height: 4px;

    background-color: rgba(255, 255, 255, 0.10);

    border-radius: 4px;

    overflow: hidden;
}

.metric-fill {
    width: 0px;
    height: 4px;

    border-radius: 4px;
}

.cpu-fill {
    background-color: rgba(88, 218, 255, 0.95);

    box-shadow:
        0 0 7px rgba(88, 218, 255, 0.45);
}

.ram-fill {
    background-color: rgba(190, 120, 255, 0.95);

    box-shadow:
        0 0 7px rgba(190, 120, 255, 0.40);
}

/*
 * AUDIO:
 * vertical waveform is used ONLY here.
 */

.audio-section {
    margin-top: 3px;

    spacing: 2px;
}

.audio-header {
    width: 308px;
}

.audio-label {
    color: rgba(130, 225, 255, 0.92);
}

.audio-value {
    font-size: 9px;

    letter-spacing: 1px;

    color: rgba(130, 225, 255, 0.60);
}

.audio-wave {
    width: 308px;
    height: 25px;

    spacing: 4px;

    padding-top: 0px;
    padding-bottom: 0px;

    background-color: transparent;
}

.audio-wave-bar {
    width: 4px;
    height: 2px;

    min-height: 2px;

    border-radius: 3px;

    background-color: rgba(88, 218, 255, 0.95);

    box-shadow:
        0 0 6px rgba(88, 218, 255, 0.40);
}
EOF

echo "[PASS] stylesheet.css written"

echo
echo "[4/8] Checking JavaScript syntax..."

gjs -m "$LIVE_DIR/extension.js"

echo "[PASS] JavaScript syntax"

echo
echo "[5/8] Checking audio helper..."

if [ -f "$LIVE_DIR/$AUDIO_HELPER" ]; then
    echo "[INFO] Unexpected helper path detected."
fi

if [ -f "$AUDIO_HELPER" ]; then
    python3 -m py_compile "$AUDIO_HELPER"
    echo "[PASS] Audio helper syntax"
else
    echo "[WARN] Audio helper not found at $AUDIO_HELPER"
fi

echo
echo "[6/8] Syncing extension into Niveth rootfs..."

sudo install -Dm644 \
    "$LIVE_DIR/extension.js" \
    "$ROOTFS_DIR/extension.js"

sudo install -Dm644 \
    "$LIVE_DIR/stylesheet.css" \
    "$ROOTFS_DIR/stylesheet.css"

if [ -f "$LIVE_DIR/metadata.json" ]; then
    sudo install -Dm644 \
        "$LIVE_DIR/metadata.json" \
        "$ROOTFS_DIR/metadata.json"
fi

if [ -f "$AUDIO_HELPER" ]; then
    sudo install -Dm755 \
        "$AUDIO_HELPER" \
        "$HOME/Niveth/build/rootfs$AUDIO_HELPER"
fi

echo "[PASS] Rootfs synced"

echo
echo "[7/8] Hash verification..."

echo
echo "extension.js:"
sha256sum "$LIVE_DIR/extension.js"
sudo sha256sum "$ROOTFS_DIR/extension.js"

echo
echo "stylesheet.css:"
sha256sum "$LIVE_DIR/stylesheet.css"
sudo sha256sum "$ROOTFS_DIR/stylesheet.css"

echo
echo "[8/8] Reloading extension..."

gnome-extensions disable "$EXT_ID" 2>/dev/null || true
sleep 2

gnome-extensions enable "$EXT_ID"
sleep 5

echo
echo "=============================================="
echo " STATUS"
echo "=============================================="

gnome-extensions info "$EXT_ID"

echo
echo "=============================================="
echo " RESULT"
echo "=============================================="
echo "CPU  -> horizontal bar"
echo "RAM  -> horizontal bar"
echo "AUDIO -> vertical waveform"
echo "=============================================="
