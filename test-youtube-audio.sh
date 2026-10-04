#!/usr/bin/env bash
set -euo pipefail

echo "=============================================="
echo " NIVETH AUDIO TEST"
echo "=============================================="

if ! command -v parecord >/dev/null 2>&1; then
    echo "[ERROR] parecord not found."
    exit 1
fi

if ! command -v pactl >/dev/null 2>&1; then
    echo "[ERROR] pactl not found."
    exit 1
fi

SINK="$(pactl get-default-sink)"

if [ -z "$SINK" ]; then
    echo "[ERROR] Could not determine default sink."
    exit 1
fi

MONITOR="${SINK}.monitor"

echo
echo "Default sink:"
echo "$SINK"

echo
echo "Monitor source:"
echo "$MONITOR"

echo
echo "Available monitor sources:"
pactl list short sources | grep '\.monitor' || true

if ! pactl list short sources | awk '{print $2}' | grep -Fxq "$MONITOR"; then
    echo
    echo "[ERROR] Monitor source does not exist."
    exit 1
fi

echo
echo "=============================================="
echo " PLAY YOUTUBE AUDIO NOW"
echo "=============================================="
echo
echo "The test will run for 10 seconds."
echo "Keep YouTube playing during the test."
echo

sleep 2

python3 - "$MONITOR" <<'PY'
import math
import subprocess
import sys
from array import array

monitor = sys.argv[1]

rate = 16000
channels = 1
sample_bytes = 2
chunk_samples = 1024

command = [
    "parecord",
    "--raw",
    "--format=s16le",
    f"--rate={rate}",
    f"--channels={channels}",
    "--device",
    monitor,
    "/dev/stdout",
]

try:
    process = subprocess.Popen(
        command,
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
    )
except Exception as e:
    print(f"[ERROR] Could not start parecord: {e}")
    sys.exit(1)

try:
    while True:
        raw = process.stdout.read(
            chunk_samples * sample_bytes
        )

        if not raw:
            break

        usable = (
            len(raw) //
            sample_bytes *
            sample_bytes
        )

        if usable <= 0:
            continue

        raw = raw[:usable]

        samples = array("h")
        samples.frombytes(raw)

        if sys.byteorder != "little":
            samples.byteswap()

        if not samples:
            continue

        total = 0.0

        for sample in samples:
            normalized = sample / 32768.0
            total += normalized * normalized

        rms = math.sqrt(
            total / len(samples)
        )

        if rms <= 0.00001:
            level = 0.0
        else:
            db = 20.0 * math.log10(rms)

            level = (
                (db + 80.0) /
                77.0
            ) * 100.0

        level = max(
            0.0,
            min(100.0, level)
        )

        print(
            f"AUDIO LEVEL: {level:5.1f}%",
            flush=True
        )

finally:
    try:
        process.terminate()
    except Exception:
        pass
PY

echo
echo "=============================================="
echo " TEST FINISHED"
echo "=============================================="
