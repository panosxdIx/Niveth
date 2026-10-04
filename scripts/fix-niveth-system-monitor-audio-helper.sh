#!/usr/bin/env bash

set -euo pipefail

# ============================================================
# NIVETH SYSTEM MONITOR
# AUDIO HELPER SYNTAX FIX
# ============================================================

EXT_ID="niveth-system-monitor@nivethos"

HOST_DIR="$HOME/.local/share/gnome-shell/extensions/$EXT_ID"
ROOTFS="$HOME/Niveth/build/rootfs"
ROOTFS_DIR="$ROOTFS/usr/share/gnome-shell/extensions/$EXT_ID"

PY="$HOST_DIR/niveth-audio-meter.py"

echo
echo "============================================================"
echo " NIVETH SYSTEM MONITOR — AUDIO HELPER FIX"
echo "============================================================"
echo

if [ ! -d "$HOST_DIR" ]; then
    echo "[FAIL] Extension directory not found:"
    echo "       $HOST_DIR"
    exit 1
fi

if [ ! -d "$ROOTFS" ]; then
    echo "[FAIL] Rootfs not found:"
    echo "       $ROOTFS"
    exit 1
fi

echo "[1/6] Writing corrected audio helper"

cat > "$PY" <<'PY'
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
    return max(
        low,
        min(high, value)
    )


def get_default_sink():

    try:

        result = subprocess.run(
            [
                "pactl",
                "get-default-sink",
            ],
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


    sample_count = (
        len(raw) //
        BYTES_PER_SAMPLE
    )


    if sample_count <= 0:
        return 0.0


    usable_bytes = (
        sample_count *
        BYTES_PER_SAMPLE
    )


    raw = raw[:usable_bytes]


    samples = struct.unpack(
        "<{}h".format(sample_count),
        raw,
    )


    square_sum = 0.0


    for sample in samples:

        normalized = (
            sample /
            32768.0
        )

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


    db = 20.0 * math.log10(
        rms
    )


    level = (
        (
            db -
            MIN_DB
        ) /
        (
            MAX_DB -
            MIN_DB
        )
    ) * 100.0


    return clamp(
        level,
        0.0,
        100.0
    )


def main():

    sink = get_default_sink()


    if sink == "@DEFAULT_SINK@":

        monitor = (
            "@DEFAULT_SINK@.monitor"
        )

    else:

        monitor = (
            sink +
            ".monitor"
        )


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

    except Exception as error:

        print(
            "0",
            flush=True
        )

        print(
            "NIVETH AUDIO ERROR: {}".format(
                error
            ),
            file=sys.stderr,
        )

        return 1


    try:

        while True:

            raw = process.stdout.read(
                FRAME_COUNT *
                BYTES_PER_SAMPLE
            )


            if not raw:
                break


            level = calculate_level(
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

chmod +x "$PY"

echo "[PASS] Audio helper written"


echo
echo "[2/6] Checking Python syntax"

python3 -m py_compile \
    "$PY"

echo "[PASS] Python syntax"


echo
echo "[3/6] Checking parecord"

if command -v parecord >/dev/null 2>&1; then
    echo "[PASS] Host parecord found"
else
    echo "[WARN] Host parecord not found"
fi


echo
echo "[4/6] Testing audio helper briefly"

TEST_OUTPUT="$(
    timeout 2 \
        "$PY" \
        2>/dev/null |
    head -n 3 ||
    true
)"

if [ -n "$TEST_OUTPUT" ]; then

    echo "[PASS] Audio helper produced data:"
    echo "$TEST_OUTPUT"

else

    echo "[INFO] No samples captured during 2-second test."
    echo "[INFO] This can happen when there is no active audio."
fi


echo
echo "[5/6] Syncing helper to rootfs"

sudo mkdir -p \
    "$ROOTFS_DIR"

sudo install -m 0755 \
    "$PY" \
    "$ROOTFS_DIR/niveth-audio-meter.py"

echo "[PASS] Rootfs audio helper"


echo
echo "[6/6] Verifying rootfs helper"

sudo python3 -m py_compile \
    "$ROOTFS_DIR/niveth-audio-meter.py"

echo "[PASS] Rootfs Python syntax"


echo
echo "============================================================"
echo " AUDIO HELPER FIX COMPLETE"
echo "============================================================"
echo
echo "The System Monitor JS remains installed."
echo
echo "Next:"
echo "  reload niveth-system-monitor@nivethos"
echo
echo "The cyan waveform will use system audio when available."
echo

