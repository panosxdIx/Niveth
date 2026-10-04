#!/usr/bin/env bash

set -euo pipefail

BASE="$HOME/.local/share/niveth/sound-effects"
BACKUP="$HOME/Niveth/backup-sounds-$(date +%Y%m%d-%H%M%S)"

echo
echo "============================================================"
echo "       NIVETH PREMIUM SOUND PACK"
echo "============================================================"
echo
echo "Creating:"
echo
echo "  Premium keyboard thock"
echo "  Premium left click"
echo "  Premium right click"
echo "  Premium middle click"
echo
echo "============================================================"
echo

# ------------------------------------------------------------
# 1. Verify
# ------------------------------------------------------------

echo "[1/5] Preparing..."

mkdir -p "$BASE"
mkdir -p "$BACKUP"

echo "[PASS] Sound directory:"
echo "  $BASE"

echo

# ------------------------------------------------------------
# 2. Backup current sounds
# ------------------------------------------------------------

echo "[2/5] Backing up current sounds..."

for file in \
    key.wav \
    mouse-left.wav \
    mouse-right.wav \
    mouse-middle.wav
do

    if [ -f "$BASE/$file" ]; then

        cp -a \
            "$BASE/$file" \
            "$BACKUP/$file"

        echo "[BACKUP] $file"

    fi

done

echo
echo "Backup:"
echo "  $BACKUP"
echo

# ------------------------------------------------------------
# 3. Generate premium sounds
# ------------------------------------------------------------

echo "[3/5] Generating premium sounds..."

python3 - "$BASE" <<'PY'
import math
import random
import struct
import sys
import wave
from pathlib import Path


BASE = Path(sys.argv[1])

RATE = 48000


def clamp(value, low=-1.0, high=1.0):
    return max(
        low,
        min(high, value)
    )


def smooth_step(x):
    x = max(
        0.0,
        min(1.0, x)
    )

    return (
        x * x *
        (3.0 - 2.0 * x)
    )


def exp_decay(t, tau):
    return math.exp(
        -t / tau
    )


def lowpass(
    signal,
    cutoff
):
    """
    Simple one-pole low-pass filter.
    """
    dt = 1.0 / RATE

    rc = 1.0 / (
        2.0 *
        math.pi *
        cutoff
    )

    alpha = dt / (
        rc + dt
    )

    out = []
    previous = 0.0

    for sample in signal:

        previous += (
            alpha *
            (sample - previous)
        )

        out.append(
            previous
        )

    return out


def generate(
    filename,
    duration,
    layers,
    noise_amount,
    master_gain,
    seed
):

    random.seed(seed)

    total = int(
        RATE *
        duration
    )

    mono = [0.0] * total

    # --------------------------------------------------------
    # Synthesis layers
    # --------------------------------------------------------

    for layer in layers:

        frequency = layer.get(
            "frequency",
            1000.0
        )

        amplitude = layer.get(
            "amplitude",
            0.2
        )

        decay = layer.get(
            "decay",
            0.020
        )

        attack = layer.get(
            "attack",
            0.0004
        )

        phase = layer.get(
            "phase",
            random.uniform(
                0.0,
                math.tau
            )
        )

        harmonic = layer.get(
            "harmonic",
            1.0
        )

        offset = layer.get(
            "offset",
            0.0
        )

        for i in range(total):

            t = (
                i / RATE
            ) - offset

            if t < 0:
                continue

            if t > duration:
                continue

            attack_env = (
                smooth_step(
                    t / attack
                )
                if attack > 0
                else 1.0
            )

            decay_env = exp_decay(
                t,
                decay
            )

            envelope = (
                attack_env *
                decay_env
            )

            fundamental = math.sin(
                math.tau *
                frequency *
                t +
                phase
            )

            partial = (
                0.0
            )

            if harmonic > 1.0:

                partial = (
                    math.sin(
                        math.tau *
                        frequency *
                        harmonic *
                        t +
                        phase *
                        0.73
                    )
                    * 0.20
                )

            mono[i] += (
                (
                    fundamental +
                    partial
                )
                *
                amplitude
                *
                envelope
            )

    # --------------------------------------------------------
    # Premium noise / material layer
    # --------------------------------------------------------

    raw_noise = []

    for i in range(total):

        envelope = exp_decay(
            i / RATE,
            0.007
        )

        raw_noise.append(
            random.uniform(
                -1.0,
                1.0
            )
            *
            envelope
        )

    # Keep only controlled high-frequency transient.
    filtered_noise = lowpass(
        raw_noise,
        7200
    )

    for i in range(total):

        t = i / RATE

        transient = (
            filtered_noise[i]
            *
            noise_amount
        )

        # Very short physical impact.
        impact = (
            math.exp(
                -t / 0.0035
            )
            *
            math.sin(
                math.tau *
                4800.0 *
                t
            )
            *
            0.045
        )

        mono[i] += (
            transient +
            impact
        )

    # --------------------------------------------------------
    # Gentle stereo spread
    # --------------------------------------------------------

    left = []
    right = []

    for i, sample in enumerate(mono):

        sample *= master_gain

        sample = clamp(
            sample
        )

        # Tiny natural stereo variation.
        left_gain = 1.0
        right_gain = 0.985

        left.append(
            clamp(
                sample *
                left_gain
            )
        )

        right.append(
            clamp(
                sample *
                right_gain
            )
        )

    frames = bytearray()

    for l, r in zip(
        left,
        right
    ):

        li = int(
            clamp(l) *
            32767
        )

        ri = int(
            clamp(r) *
            32767
        )

        frames.extend(
            struct.pack(
                "<hh",
                li,
                ri
            )
        )

    path = (
        BASE /
        filename
    )

    with wave.open(
        str(path),
        "wb"
    ) as out:

        out.setnchannels(
            2
        )

        out.setsampwidth(
            2
        )

        out.setframerate(
            RATE
        )

        out.writeframes(
            frames
        )

    print(
        f"[PASS] {filename}"
    )


# ============================================================
# KEYBOARD
# ============================================================

generate(
    "key.wav",

    duration=0.055,

    layers=[
        {
            "frequency": 1680.0,
            "amplitude": 0.22,
            "decay": 0.012,
            "attack": 0.00025,
            "harmonic": 1.83,
        },
        {
            "frequency": 540.0,
            "amplitude": 0.12,
            "decay": 0.018,
            "attack": 0.00030,
            "harmonic": 2.11,
        },
        {
            "frequency": 175.0,
            "amplitude": 0.075,
            "decay": 0.025,
            "attack": 0.00050,
            "harmonic": 1.44,
        },
    ],

    noise_amount=0.11,

    master_gain=0.78,

    seed=1001
)


# ============================================================
# LEFT CLICK
# ============================================================

generate(
    "mouse-left.wav",

    duration=0.042,

    layers=[
        {
            "frequency": 2100.0,
            "amplitude": 0.25,
            "decay": 0.010,
            "attack": 0.00018,
            "harmonic": 1.73,
        },
        {
            "frequency": 820.0,
            "amplitude": 0.10,
            "decay": 0.015,
            "attack": 0.00025,
            "harmonic": 2.17,
        },
        {
            "frequency": 260.0,
            "amplitude": 0.055,
            "decay": 0.018,
            "attack": 0.00040,
            "harmonic": 1.50,
        },
    ],

    noise_amount=0.16,

    master_gain=0.72,

    seed=2001
)


# ============================================================
# RIGHT CLICK
# ============================================================

generate(
    "mouse-right.wav",

    duration=0.050,

    layers=[
        {
            "frequency": 1350.0,
            "amplitude": 0.22,
            "decay": 0.013,
            "attack": 0.00018,
            "harmonic": 1.81,
        },
        {
            "frequency": 610.0,
            "amplitude": 0.12,
            "decay": 0.019,
            "attack": 0.00030,
            "harmonic": 2.07,
        },
        {
            "frequency": 210.0,
            "amplitude": 0.075,
            "decay": 0.023,
            "attack": 0.00050,
            "harmonic": 1.37,
        },
    ],

    noise_amount=0.18,

    master_gain=0.70,

    seed=2002
)


# ============================================================
# MIDDLE CLICK
# ============================================================

generate(
    "mouse-middle.wav",

    duration=0.058,

    layers=[
        {
            "frequency": 980.0,
            "amplitude": 0.20,
            "decay": 0.016,
            "attack": 0.00020,
            "harmonic": 1.79,
        },
        {
            "frequency": 430.0,
            "amplitude": 0.13,
            "decay": 0.022,
            "attack": 0.00032,
            "harmonic": 2.03,
        },
        {
            "frequency": 145.0,
            "amplitude": 0.090,
            "decay": 0.029,
            "attack": 0.00055,
            "harmonic": 1.42,
        },
    ],

    noise_amount=0.20,

    master_gain=0.68,

    seed=2003
)

PY

echo "[PASS] Premium sound generation"
echo

# ------------------------------------------------------------
# 4. Verify WAV files
# ------------------------------------------------------------

echo "[4/5] Verifying sound files..."

for file in \
    key.wav \
    mouse-left.wav \
    mouse-right.wav \
    mouse-middle.wav
do

    if [ ! -f "$BASE/$file" ]; then
        echo "[FAIL] Missing $file"
        exit 1
    fi

    printf '[PASS] %-20s ' "$file"

    python3 - "$BASE/$file" <<'PY'
import sys
import wave

path = sys.argv[1]

with wave.open(
    path,
    "rb"
) as w:

    print(
        f"{w.getframerate()}Hz "
        f"{w.getnchannels()}ch "
        f"{w.getsampwidth()*8}bit "
        f"{w.getnframes()} frames"
    )
PY

done

echo

# ------------------------------------------------------------
# 5. Final
# ------------------------------------------------------------

echo "[5/5] Premium pack ready."

echo
echo "============================================================"
echo " NIVETH PREMIUM SOUND PACK READY"
echo "============================================================"
echo
echo "Keyboard:"
echo "  key.wav"
echo
echo "Mouse:"
echo "  mouse-left.wav"
echo "  mouse-right.wav"
echo "  mouse-middle.wav"
echo
echo "Backup:"
echo "  $BACKUP"
echo
echo "============================================================"
echo
echo "Start the daemon with:"
echo
echo "  ~/Niveth/start-niveth-sound-effects-test.sh"
echo
echo "============================================================"
