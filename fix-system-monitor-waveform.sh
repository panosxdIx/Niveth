#!/usr/bin/env bash
set -euo pipefail

EXT_ID="niveth-system-monitor@nivethos"

LIVE_DIR="$HOME/.local/share/gnome-shell/extensions/$EXT_ID"
ROOTFS_DIR="$HOME/Niveth/build/rootfs/usr/share/gnome-shell/extensions/$EXT_ID"

echo "=============================================="
echo " NIVETH SYSTEM MONITOR - AUDIO WAVEFORM FIX"
echo "=============================================="

if [ ! -f "$LIVE_DIR/extension.js" ]; then
    echo "[ERROR] extension.js not found"
    exit 1
fi

if [ ! -f "$LIVE_DIR/stylesheet.css" ]; then
    echo "[ERROR] stylesheet.css not found"
    exit 1
fi

if [ ! -f "$LIVE_DIR/niveth-audio-meter.py" ]; then
    echo "[ERROR] niveth-audio-meter.py not found"
    exit 1
fi

echo
echo "[1/8] Disabling extension..."
gnome-extensions disable "$EXT_ID" 2>/dev/null || true
sleep 2

echo
echo "[2/8] Creating backup..."

BACKUP_DIR="$LIVE_DIR/backup-waveform-fix-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$BACKUP_DIR"

cp "$LIVE_DIR/extension.js" "$BACKUP_DIR/extension.js"
cp "$LIVE_DIR/stylesheet.css" "$BACKUP_DIR/stylesheet.css"
cp "$LIVE_DIR/niveth-audio-meter.py" "$BACKUP_DIR/niveth-audio-meter.py"

echo "[PASS] Backup:"
echo "$BACKUP_DIR"

echo
echo "[3/8] Patching AUDIO waveform engine..."

python3 - "$LIVE_DIR/extension.js" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")

old = """    _pushAudioLevel(level) {
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

            const height =
                Math.max(
                    2,
                    Math.round(
                        level /
                        100 *
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
"""

new = """    _pushAudioLevel(level) {
        let normalized = Number(level);

        if (!Number.isFinite(normalized))
            normalized = 0;

        normalized =
            Math.max(
                0,
                Math.min(100, normalized)
            );

        /*
         * Increase visible dynamics.
         *
         * The PCM meter on this system normally sits
         * around the 70-85% range while music plays.
         * Stretch that range so the waveform visibly moves.
         */
        normalized =
            Math.max(
                0,
                Math.min(
                    100,
                    (normalized - 55) * 2.25
                )
            );

        this._audioHistory.push(normalized);

        while (this._audioHistory.length > WAVE_COUNT)
            this._audioHistory.shift();

        this._drawWaveform();
    }

    _fillWaveform(level) {
        const safe =
            Math.max(
                0,
                Math.min(100, Number(level) || 0)
            );

        this._audioHistory =
            new Array(WAVE_COUNT)
                .fill(safe);

        this._drawWaveform();
    }

    _drawWaveform() {
        if (!this._waveBars.length)
            return;

        /*
         * Keep the newest values aligned to the right.
         * Empty history remains at zero.
         */
        const history =
            new Array(WAVE_COUNT)
                .fill(0);

        const start =
            Math.max(
                0,
                WAVE_COUNT -
                this._audioHistory.length
            );

        for (
            let i = 0;
            i < this._audioHistory.length &&
            start + i < WAVE_COUNT;
            i++
        ) {
            history[start + i] =
                this._audioHistory[i];
        }

        for (
            let i = 0;
            i < this._waveBars.length;
            i++
        ) {
            const level =
                history[i] || 0;

            /*
             * Add a tiny interpolation bias between
             * neighboring samples so the waveform
             * looks organic instead of flat.
             */
            const previous =
                i > 0
                    ? history[i - 1]
                    : level;

            const next =
                i + 1 < history.length
                    ? history[i + 1]
                    : level;

            const smooth =
                level * 0.60 +
                previous * 0.20 +
                next * 0.20;

            const clamped =
                Math.max(
                    0,
                    Math.min(100, smooth)
                );

            const minHeight = 2;

            const height =
                Math.max(
                    minHeight,
                    Math.round(
                        minHeight +
                        (
                            clamped / 100
                        ) *
                        (
                            WAVE_MAX_HEIGHT -
                            minHeight
                        )
                    )
                );

            const bar =
                this._waveBars[i];

            /*
             * Explicit height and position.
             * CSS does not define the bar height.
             */
            bar.set_height(height);

            bar.set_y(
                Math.round(
                    (
                        WAVE_MAX_HEIGHT -
                        height
                    ) / 2
                )
            );
        }
    }
"""

if old not in text:
    raise SystemExit(
        "[ERROR] Existing waveform methods were not found."
    )

text = text.replace(old, new, 1)

path.write_text(text, encoding="utf-8")

print("[PASS] Waveform engine updated")
PY

echo
echo "[4/8] Removing CSS height override from audio bars..."

python3 - "$LIVE_DIR/stylesheet.css" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")

old = """ .audio-wave-bar {
    width: 4px;
    height: 2px;

    min-height: 2px;

    border-radius: 3px;

    background-color: rgba(88, 218, 255, 0.95);

    box-shadow:
        0 0 6px rgba(88, 218, 255, 0.40);
}
"""

if old not in text:
    old = """.audio-wave-bar {
    width: 4px;
    height: 2px;

    min-height: 2px;

    border-radius: 3px;

    background-color: rgba(88, 218, 255, 0.95);

    box-shadow:
        0 0 6px rgba(88, 218, 255, 0.40);
}
"""

new = """.audio-wave-bar {
    width: 4px;

    min-height: 2px;

    border-radius: 3px;

    background-color: rgba(88, 218, 255, 0.95);

    box-shadow:
        0 0 6px rgba(88, 218, 255, 0.40);
}
"""

if old not in text:
    raise SystemExit(
        "[ERROR] audio-wave-bar CSS block not found."
    )

text = text.replace(old, new, 1)

path.write_text(text, encoding="utf-8")

print("[PASS] CSS audio bar height override removed")
PY

echo
echo "[5/8] Checking source..."

grep -n "_pushAudioLevel" "$LIVE_DIR/extension.js"
grep -n "_drawWaveform" "$LIVE_DIR/extension.js"
grep -n "audio-wave-bar" "$LIVE_DIR/stylesheet.css"

echo
echo "[6/8] Testing Python helper syntax..."

python3 -m py_compile \
    "$LIVE_DIR/niveth-audio-meter.py"

echo "[PASS] Audio helper syntax"

echo
echo "[7/8] Syncing to Niveth rootfs..."

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
echo "=== HASH CHECK ==="

LIVE_JS="$(sha256sum "$LIVE_DIR/extension.js" | awk '{print $1}')"
ROOT_JS="$(sudo sha256sum "$ROOTFS_DIR/extension.js" | awk '{print $1}')"

LIVE_CSS="$(sha256sum "$LIVE_DIR/stylesheet.css" | awk '{print $1}')"
ROOT_CSS="$(sudo sha256sum "$ROOTFS_DIR/stylesheet.css" | awk '{print $1}')"

echo
echo "extension.js"
echo " LIVE: $LIVE_JS"
echo " ROOT: $ROOT_JS"

echo
echo "stylesheet.css"
echo " LIVE: $LIVE_CSS"
echo " ROOT: $ROOT_CSS"

if [ "$LIVE_JS" != "$ROOT_JS" ]; then
    echo "[ERROR] extension.js mismatch"
    exit 1
fi

if [ "$LIVE_CSS" != "$ROOT_CSS" ]; then
    echo "[ERROR] stylesheet.css mismatch"
    exit 1
fi

echo
echo "[PASS] Hashes match"

echo
echo "[8/8] Installation complete"

echo
echo "=============================================="
echo " IMPORTANT"
echo "=============================================="
echo
echo "GNOME Shell caches extension JavaScript."
echo
echo "Κάνε τώρα:"
echo
echo "LOGOUT -> LOGIN"
echo
echo "Μετά έλεγξε:"
echo
echo "gnome-extensions info $EXT_ID"
echo
echo "Expected:"
echo "Enabled: Yes"
echo "State: ACTIVE"
echo
echo "=============================================="
echo " FINAL DESIGN"
echo "=============================================="
echo
echo "CPU  = horizontal bar only"
echo "RAM  = horizontal bar only"
echo "AUDIO = animated vertical waveform"
echo
echo "=============================================="
