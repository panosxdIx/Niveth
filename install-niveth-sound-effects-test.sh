#!/usr/bin/env bash

set -euo pipefail

BASE="$HOME/.local/share/niveth/sound-effects"
DAEMON="$HOME/.local/bin/niveth-sound-effects.py"

echo
echo "============================================================"
echo "        NIVETH SOUND EFFECTS — TEST INSTALL"
echo "============================================================"
echo
echo "Features:"
echo "  Keyboard press"
echo "  Left mouse click"
echo "  Right mouse click"
echo "  Middle mouse click"
echo
echo "Input:"
echo "  Linux /dev/input"
echo
echo "Audio:"
echo "  pygame mixer"
echo
echo "============================================================"
echo

# ------------------------------------------------------------
# 1. Install dependencies
# ------------------------------------------------------------

echo "[1/6] Installing required packages..."

sudo apt update

sudo apt install -y \
    python3-evdev \
    python3-pygame

echo
echo "[PASS] python3-evdev"
echo "[PASS] python3-pygame"
echo

# ------------------------------------------------------------
# 2. Create directories
# ------------------------------------------------------------

echo "[2/6] Creating Niveth sound directories..."

mkdir -p "$BASE"
mkdir -p "$(dirname "$DAEMON")"

echo "[PASS] $BASE"
echo

# ------------------------------------------------------------
# 3. Create sounds
# ------------------------------------------------------------

echo "[3/6] Creating Niveth sound effects..."

python3 - "$BASE" <<'PY'
import math
import struct
import sys
import wave
from pathlib import Path

BASE = Path(sys.argv[1])

RATE = 44100


def clamp(value, low, high):
    return max(low, min(high, value))


def make_sound(
    filename,
    duration,
    frequency,
    noise_amount,
    volume,
    click_position=0.12,
):
    path = BASE / filename

    total = max(
        1,
        int(RATE * duration)
    )

    frames = bytearray()

    for i in range(total):

        t = i / RATE

        # Fast attack followed by decay.
        attack = min(
            1.0,
            t / 0.0015
        )

        decay = max(
            0.0,
            1.0 - (t / duration)
        )

        decay = decay * decay

        envelope = attack * decay

        sine = math.sin(
            2.0 *
            math.pi *
            frequency *
            t
        )

        # Small second harmonic for a more physical click.
        harmonic = 0.22 * math.sin(
            2.0 *
            math.pi *
            frequency *
            2.03 *
            t
        )

        # Deterministic pseudo-noise.
        noise_seed = (
            i * 1103515245 + 12345
        ) & 0x7fffffff

        noise = (
            (noise_seed / 1073741824.0) - 1.0
        )

        signal = (
            sine * 0.72
            + harmonic
            + noise * noise_amount
        )

        # Extra transient at the front.
        transient_time = max(
            0.0,
            click_position - t
        )

        transient = math.exp(
            -transient_time * 1600.0
        )

        signal += (
            transient *
            0.28
        )

        signal *= (
            envelope *
            volume
        )

        signal = clamp(
            signal,
            -1.0,
            1.0
        )

        sample = int(
            signal *
            32767
        )

        packed = struct.pack(
            "<hh",
            sample,
            sample
        )

        frames.extend(
            packed
        )

    with wave.open(
        str(path),
        "wb"
    ) as out:

        out.setnchannels(2)
        out.setsampwidth(2)
        out.setframerate(RATE)
        out.writeframes(frames)

    print(
        f"[PASS] {path.name}"
    )


make_sound(
    "key.wav",
    duration=0.030,
    frequency=1850.0,
    noise_amount=0.16,
    volume=0.26,
)

make_sound(
    "mouse-left.wav",
    duration=0.034,
    frequency=1250.0,
    noise_amount=0.24,
    volume=0.32,
)

make_sound(
    "mouse-right.wav",
    duration=0.042,
    frequency=920.0,
    noise_amount=0.28,
    volume=0.34,
)

make_sound(
    "mouse-middle.wav",
    duration=0.050,
    frequency=720.0,
    noise_amount=0.30,
    volume=0.36,
)

PY

echo

# ------------------------------------------------------------
# 4. Create daemon
# ------------------------------------------------------------

echo "[4/6] Creating Niveth Sound Effects daemon..."

cat > "$DAEMON" <<'PY'
#!/usr/bin/env python3

import signal
import sys
import threading
import time
from pathlib import Path

import pygame
from evdev import InputDevice
from evdev import ecodes
from evdev import list_devices


BASE = (
    Path.home()
    / ".local"
    / "share"
    / "niveth"
    / "sound-effects"
)


SOUND_FILES = {
    "key":
        BASE / "key.wav",

    "left":
        BASE / "mouse-left.wav",

    "right":
        BASE / "mouse-right.wav",

    "middle":
        BASE / "mouse-middle.wav",
}


KEYBOARD_MARKERS = {
    ecodes.KEY_A,
    ecodes.KEY_Z,
    ecodes.KEY_SPACE,
    ecodes.KEY_ENTER,
    ecodes.KEY_ESC,
}


MOUSE_BUTTONS = {
    ecodes.BTN_LEFT:
        "left",

    ecodes.BTN_RIGHT:
        "right",

    ecodes.BTN_MIDDLE:
        "middle",
}


stop_event = threading.Event()

sounds = {}

audio_lock = threading.Lock()


def log(message):
    print(
        f"[NIVETH SOUND] {message}",
        flush=True,
    )


def is_keyboard_device(device):
    try:
        capabilities = device.capabilities()

    except Exception:
        return False

    keys = set(
        capabilities.get(
            ecodes.EV_KEY,
            []
        )
    )

    return bool(
        keys.intersection(
            KEYBOARD_MARKERS
        )
    )


def is_pointer_device(device):
    try:
        capabilities = device.capabilities()

    except Exception:
        return False

    keys = set(
        capabilities.get(
            ecodes.EV_KEY,
            []
        )
    )

    return (
        ecodes.BTN_LEFT in keys
        or ecodes.BTN_RIGHT in keys
        or ecodes.BTN_MIDDLE in keys
    )


def play_sound(name):
    sound = sounds.get(name)

    if sound is None:
        return

    with audio_lock:
        try:
            channel = (
                pygame.mixer.find_channel(
                    force=True
                )
            )

            if channel is not None:
                channel.play(sound)

        except Exception as error:
            log(
                f"Audio playback error: {error}"
            )


def keyboard_loop(device):
    log(
        f"Keyboard listener: "
        f"{device.path} "
        f"({device.name})"
    )

    try:

        for event in device.read_loop():

            if stop_event.is_set():
                break

            if event.type != ecodes.EV_KEY:
                continue

            # Only key-down.
            # Ignore release and autorepeat.
            if event.value != 1:
                continue

            play_sound("key")

    except OSError as error:
        log(
            f"Keyboard device closed: "
            f"{device.path}: {error}"
        )

    except Exception as error:
        log(
            f"Keyboard listener error: "
            f"{device.path}: {error}"
        )

    finally:
        try:
            device.close()
        except Exception:
            pass


def pointer_loop(device):
    log(
        f"Mouse listener: "
        f"{device.path} "
        f"({device.name})"
    )

    try:

        for event in device.read_loop():

            if stop_event.is_set():
                break

            if event.type != ecodes.EV_KEY:
                continue

            if event.value != 1:
                continue

            sound_name = MOUSE_BUTTONS.get(
                event.code
            )

            if sound_name:
                play_sound(
                    sound_name
                )

                log(
                    f"Mouse event: "
                    f"{sound_name}"
                )

    except OSError as error:
        log(
            f"Mouse device closed: "
            f"{device.path}: {error}"
        )

    except Exception as error:
        log(
            f"Mouse listener error: "
            f"{device.path}: {error}"
        )

    finally:
        try:
            device.close()
        except Exception:
            pass


def signal_handler(_signal, _frame):
    log(
        "Stopping..."
    )

    stop_event.set()


def load_audio():
    log(
        "Initializing audio..."
    )

    pygame.mixer.pre_init(
        frequency=44100,
        size=-16,
        channels=2,
        buffer=256,
    )

    pygame.mixer.init()

    pygame.mixer.set_num_channels(
        32
    )

    for name, path in SOUND_FILES.items():

        if not path.is_file():
            log(
                f"Missing sound file: {path}"
            )

            continue

        try:

            sounds[name] = (
                pygame.mixer.Sound(
                    str(path)
                )
            )

            log(
                f"Loaded sound: "
                f"{name} -> {path.name}"
            )

        except Exception as error:

            log(
                f"Failed to load "
                f"{path.name}: {error}"
            )

    if not sounds:
        raise RuntimeError(
            "No sound files could be loaded."
        )


def discover_devices():
    keyboard_devices = []
    pointer_devices = []

    paths = list_devices()

    log(
        f"Found {len(paths)} input devices"
    )

    for path in paths:

        try:
            device = InputDevice(path)

            keyboard = (
                is_keyboard_device(
                    device
                )
            )

            pointer = (
                is_pointer_device(
                    device
                )
            )

            if keyboard:

                keyboard_devices.append(
                    device
                )

                log(
                    f"Keyboard: "
                    f"{path} "
                    f"-> {device.name}"
                )

            elif pointer:

                pointer_devices.append(
                    device
                )

                log(
                    f"Mouse: "
                    f"{path} "
                    f"-> {device.name}"
                )

            else:

                device.close()

        except PermissionError:

            log(
                f"Permission denied: "
                f"{path}"
            )

        except Exception as error:

            log(
                f"Skipping {path}: "
                f"{error}"
            )

    return (
        keyboard_devices,
        pointer_devices,
    )


def main():

    signal.signal(
        signal.SIGINT,
        signal_handler,
    )

    signal.signal(
        signal.SIGTERM,
        signal_handler,
    )

    log(
        "Starting Niveth Sound Effects"
    )

    log(
        f"Sound directory: {BASE}"
    )

    load_audio()

    (
        keyboard_devices,
        pointer_devices,
    ) = discover_devices()

    if not keyboard_devices:
        log(
            "WARNING: "
            "No keyboard devices detected."
        )

    if not pointer_devices:
        log(
            "WARNING: "
            "No mouse devices detected."
        )

    threads = []

    for device in keyboard_devices:

        thread = threading.Thread(
            target=keyboard_loop,
            args=(device,),
            daemon=True,
        )

        thread.start()

        threads.append(
            thread
        )

    for device in pointer_devices:

        thread = threading.Thread(
            target=pointer_loop,
            args=(device,),
            daemon=True,
        )

        thread.start()

        threads.append(
            thread
        )

    log(
        "Ready."
    )

    log(
        "Press keys and click the mouse."
    )

    try:

        while not stop_event.is_set():

            time.sleep(
                0.5
            )

    except KeyboardInterrupt:

        stop_event.set()

    for thread in threads:

        thread.join(
            timeout=1.0
        )

    try:
        pygame.mixer.quit()
    except Exception:
        pass

    log(
        "Stopped."
    )


if __name__ == "__main__":
    try:
        main()

    except Exception as error:

        log(
            f"FATAL: {error}"
        )

        try:
            pygame.mixer.quit()
        except Exception:
            pass

        sys.exit(1)
PY

chmod +x "$DAEMON"

echo "[PASS] $DAEMON"
echo

# ------------------------------------------------------------
# 5. Verify Python modules
# ------------------------------------------------------------

echo "[5/6] Verifying Python modules..."

python3 - <<'PY'
import evdev
import pygame

print(
    "[PASS] evdev",
    evdev.__version__
)

print(
    "[PASS] pygame",
    pygame.version.ver
)
PY

echo

# ------------------------------------------------------------
# 6. Verify sounds
# ------------------------------------------------------------

echo "[6/6] Verifying sound files..."

find "$BASE" \
    -maxdepth 1 \
    -type f \
    -name '*.wav' \
    -printf '%f %s bytes\n' |
sort

echo
echo "============================================================"
echo " Niveth Sound Effects test is ready"
echo "============================================================"
echo
echo "Daemon:"
echo "  $DAEMON"
echo
echo "Sounds:"
echo "  $BASE"
echo
echo "The daemon will now start in foreground."
echo
echo "TEST:"
echo "  - press several keyboard keys"
echo "  - left click"
echo "  - right click"
echo "  - middle click"
echo
echo "Stop with:"
echo "  Ctrl+C"
echo
echo "============================================================"
echo

exec python3 "$DAEMON"
