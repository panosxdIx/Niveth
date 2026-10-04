#!/usr/bin/env bash

set -u

UUID="niveth-system-monitor@nivethos"
EXT="$HOME/.local/share/gnome-shell/extensions/$UUID"
ROOTFS="$HOME/Niveth/build/rootfs"
ROOTFS_EXT="$ROOTFS/usr/share/gnome-shell/extensions/$UUID"

echo
echo "============================================================"
echo " NIVETH SYSTEM MONITOR — WAVEFORM ONLY FIX"
echo "============================================================"
echo

if [ ! -f "$EXT/extension.js" ]; then
    echo "[FAIL] extension.js not found:"
    echo "  $EXT/extension.js"
    exit 1
fi

echo "[1/8] Creating backup..."

BACKUP="$EXT/backup-waveform-only-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$BACKUP"

cp -f "$EXT/extension.js" \
    "$BACKUP/extension.js"

if [ -f "$EXT/stylesheet.css" ]; then
    cp -f "$EXT/stylesheet.css" \
        "$BACKUP/stylesheet.css"
fi

echo "[PASS] Backup:"
echo "  $BACKUP"
echo

echo "[2/8] Disabling extension..."

gnome-extensions disable "$UUID" 2>/dev/null || true
sleep 2

echo "[3/8] Patching extension.js..."

python3 - "$EXT/extension.js" <<'PY'
from pathlib import Path
import re
import sys

path = Path(sys.argv[1])
text = path.read_text()

# ------------------------------------------------------------
# 1. Add a dedicated waveform count constant.
# ------------------------------------------------------------

if "const NIVETH_WAVE_COUNT = 48;" not in text:

    marker = "import * as Main from 'resource:///org/gnome/shell/ui/main.js';"

    if marker in text:
        text = text.replace(
            marker,
            marker + "\n\nconst NIVETH_WAVE_COUNT = 48;",
            1
        )
    else:
        print("[FAIL] Could not find Main import.")
        raise SystemExit(1)

# ------------------------------------------------------------
# 2. Ensure _audioHistory exists.
# ------------------------------------------------------------

if "this._audioHistory = new Array(NIVETH_WAVE_COUNT).fill(0);" not in text:

    candidates = [
        "        this._audioTarget = 0;\n",
        "        this._audioLevel = 0;\n",
        "        this._audioVisual = 0;\n",
    ]

    inserted = False

    for needle in candidates:
        if needle in text:
            text = text.replace(
                needle,
                needle +
                "        this._audioHistory = new Array(NIVETH_WAVE_COUNT).fill(0);\n",
                1
            )
            inserted = True
            break

    if not inserted:
        print("[FAIL] Could not locate audio initialization.")
        raise SystemExit(1)

# ------------------------------------------------------------
# 3. Replace _buildAudio() only.
# ------------------------------------------------------------

new_build_audio = r'''    _buildAudio() {

        const audioSection =
            new St.BoxLayout({
                vertical: true,
                style: [
                    'spacing: 5px',
                    'width: 292px',
                    'padding: 0px',
                    'margin: 0px',
                ].join(';'),
            });

        const audioHeader =
            new St.BoxLayout({
                vertical: false,
                style: [
                    'width: 292px',
                    'height: 18px',
                    'spacing: 4px',
                ].join(';'),
            });

        this._audioLabel =
            new St.Label({
                text: 'AUDIO',
                style: [
                    'font-size: 10px',
                    'font-weight: 700',
                    'width: 48px',
                    'min-width: 48px',
                    'natural-width: 48px',
                    'opacity: 0.72',
                ].join(';'),
            });

        const audioSpacer =
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

        audioHeader.add_child(
            this._audioLabel
        );

        audioHeader.add_child(
            audioSpacer
        );

        audioHeader.add_child(
            this._audioValue
        );

        audioSection.add_child(
            audioHeader
        );

        /*
         * Fixed waveform container.
         *
         * Width 292px
         * Height 48px
         *
         * 48 bars x 4px with 2px gaps
         * = 286px total
         */
        this._audioWave =
            new St.BoxLayout({
                vertical: false,
                style: [
                    'width: 292px',
                    'min-width: 292px',
                    'height: 48px',
                    'min-height: 48px',
                    'padding: 0px',
                    'margin: 0px',
                    'spacing: 2px',
                    'x-align: FILL',
                    'y-align: CENTER',
                ].join(';'),
            });

        this._audioWave.set_x_align(
            Clutter.ActorAlign.FILL
        );

        this._audioWave.set_y_align(
            Clutter.ActorAlign.CENTER
        );

        this._audioWaveBars = [];

        for (
            let i = 0;
            i < NIVETH_WAVE_COUNT;
            i++
        ) {

            const bar =
                new St.Widget({
                    style: [
                        'width: 4px',
                        'min-width: 4px',
                        'height: 3px',
                        'min-height: 3px',
                        'background-color: rgba(112, 220, 255, 0.95)',
                        'border-radius: 3px',
                        'margin: 0px',
                        'padding: 0px',
                    ].join(';'),
                });

            bar.set_width(4);
            bar.set_height(3);

            bar.set_x_align(
                Clutter.ActorAlign.CENTER
            );

            bar.set_y_align(
                Clutter.ActorAlign.CENTER
            );

            this._audioWave.add_child(bar);

            this._audioWaveBars.push(bar);
        }

        audioSection.add_child(
            this._audioWave
        );

        /*
         * Keep the existing audio section reference.
         */
        this._audioSection =
            audioSection;

        /*
         * Existing V6 code expects _buildAudio()
         * to add its own widget.
         */
        this._widget.add_child(
            audioSection
        );
    }

'''

pattern_build = re.compile(
    r"    _buildAudio\(\) \{.*?(?=    _startAudioMeter\(\) \{)",
    re.S
)

if not pattern_build.search(text):
    print("[FAIL] Could not locate _buildAudio().")
    raise SystemExit(1)

text = pattern_build.sub(
    new_build_audio,
    text,
    count=1
)

# ------------------------------------------------------------
# 4. Replace _updateAudioAnimation() only.
# ------------------------------------------------------------

new_update_audio = r'''    _updateAudioAnimation() {

        const bars =
            this._audioWaveBars;

        if (
            !bars ||
            bars.length === 0
        ) {
            return;
        }

        if (
            !this._audioHistory ||
            this._audioHistory.length === 0
        ) {
            return;
        }

        const now =
            Date.now() / 1000;

        for (
            let i = 0;
            i < bars.length;
            i++
        ) {

            const historyIndex =
                this._audioHistory.length -
                bars.length +
                i;

            let value =
                historyIndex >= 0
                    ? this._audioHistory[historyIndex]
                    : 0;

            value =
                Number(value);

            if (
                !Number.isFinite(value)
            ) {
                value = 0;
            }

            /*
             * Audio helper outputs 0..100.
             */
            let level =
                Math.max(
                    0,
                    Math.min(
                        100,
                        value
                    )
                ) / 100;

            /*
             * Give quiet audio a small visible
             * movement, while loud audio clearly
             * produces tall bars.
             */
            const pulse =
                (
                    Math.sin(
                        now * 7.0 +
                        i * 0.55
                    ) + 1
                ) / 2;

            level =
                Math.max(
                    0.04,
                    Math.min(
                        1,
                        level * 0.88 +
                        pulse * 0.10
                    )
                );

            /*
             * Waveform height:
             *
             * 3px minimum
             * 40px maximum
             */
            const height =
                Math.max(
                    3,
                    Math.min(
                        40,
                        Math.round(
                            3 +
                            level * 37
                        )
                    )
                );

            const bar =
                bars[i];

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

            /*
             * Make newer/louder samples brighter.
             */
            const alpha =
                0.45 +
                level * 0.50;

            bar.set_style(
                [
                    'width: 4px',
                    'min-width: 4px',
                    `height: ${height}px`,
                    `min-height: ${height}px`,
                    `background-color: rgba(112, 220, 255, ${alpha.toFixed(2)})`,
                    'border-radius: 3px',
                    'margin: 0px',
                    'padding: 0px',
                ].join(';')
            );
        }

        /*
         * Ensure the waveform itself remains visible.
         */
        if (this._audioWave) {
            this._audioWave.set_height(
                48
            );

            this._audioWave.set_width(
                292
            );
        }

        /*
         * Keep the visible AUDIO percentage.
         */
        if (this._audioValue) {

            const latest =
                this._audioHistory[
                    this._audioHistory.length - 1
                ];

            const safe =
                Math.max(
                    0,
                    Math.min(
                        100,
                        Number(latest) || 0
                    )
                );

            this._audioValue.set_text(
                `AUDIO ${Math.round(safe)}%`
            );
        }
    }

'''

pattern_update = re.compile(
    r"    _updateAudioAnimation\(\) \{.*?(?=    _stopAudioMeter\(\) \{)",
    re.S
)

if not pattern_update.search(text):
    print("[FAIL] Could not locate _updateAudioAnimation().")
    raise SystemExit(1)

text = pattern_update.sub(
    new_update_audio,
    text,
    count=1
)

# ------------------------------------------------------------
# 5. Make the audio read path update the history safely.
# ------------------------------------------------------------

history_guard = r'''        if (!this._audioHistory)
            this._audioHistory =
                new Array(NIVETH_WAVE_COUNT).fill(0);

'''

if (
    "if (!this._audioHistory)" not in text
    and "this._audioHistory.push(" in text
):

    text = text.replace(
        "                        this._audioHistory.push(",
        history_guard +
        "                        this._audioHistory.push(",
        1
    )

path.write_text(text)

print("[PASS] _buildAudio() replaced.")
print("[PASS] _updateAudioAnimation() replaced.")
print("[PASS] _audioHistory ensured.")
print("[PASS] Waveform count: 48.")
PY

PATCH_RESULT=$?

if [ "$PATCH_RESULT" -ne 0 ]; then
    echo
    echo "[FAIL] Patch failed."
    echo "Restoring original file from backup..."

    cp -f \
        "$BACKUP/extension.js" \
        "$EXT/extension.js"

    gnome-extensions enable "$UUID" 2>/dev/null || true

    exit "$PATCH_RESULT"
fi

echo

echo "[4/8] Checking important waveform code..."

grep -n \
    "NIVETH_WAVE_COUNT" \
    "$EXT/extension.js" |
head -20 || true

echo

grep -n \
    "_buildAudio" \
    "$EXT/extension.js" |
head -10 || true

echo

grep -n \
    "_updateAudioAnimation" \
    "$EXT/extension.js" |
head -10 || true

echo

echo "[5/8] Syncing to Niveth rootfs..."

if [ -d "$ROOTFS_EXT" ]; then

    cp -f \
        "$EXT/extension.js" \
        "$ROOTFS_EXT/extension.js"

    if [ -f "$EXT/niveth-audio-meter.py" ]; then
        cp -f \
            "$EXT/niveth-audio-meter.py" \
            "$ROOTFS_EXT/niveth-audio-meter.py"

        chmod +x \
            "$ROOTFS_EXT/niveth-audio-meter.py"
    fi

    echo "[PASS] Rootfs synchronized."

else
    echo "[INFO] Rootfs extension directory not found."
fi

echo

echo "[6/8] Enabling extension..."

gnome-extensions enable "$UUID" 2>/dev/null || true

sleep 5

echo

echo "[7/8] Extension status..."

gnome-extensions info "$UUID" 2>&1 || true

echo

echo "[8/8] Recent System Monitor errors..."

journalctl \
    --user \
    -b \
    --no-pager \
    -o cat 2>/dev/null |
grep -Ei \
    "niveth-system-monitor|NIVETH AUDIO|_audioHistory|TypeError|ReferenceError|SyntaxError" |
tail -50 || true

echo
echo "============================================================"
echo " WAVEFORM PATCH COMPLETE"
echo "============================================================"
echo
echo "Backup:"
echo "  $BACKUP"
echo
echo "AUDIO waveform:"
echo "  48 vertical bars"
echo "  3px -> 40px height"
echo "  real audio history"
echo "  animated"
echo
