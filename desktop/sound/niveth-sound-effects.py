#!/usr/bin/env python3

import sys
import time
import threading
from pathlib import Path

try:
    import pygame
    from evdev import InputDevice, list_devices, ecodes
except ImportError as exc:
    print(f"[ERROR] Missing Python module: {exc}", file=sys.stderr)
    sys.exit(1)

SOUND_DIR = Path("/usr/share/niveth/sound-effects")

LEFT_SOUND = SOUND_DIR / "mouse-left.wav"
RIGHT_SOUND = SOUND_DIR / "mouse-right.wav"
MIDDLE_SOUND = SOUND_DIR / "mouse-middle.wav"

POINTER_BUTTONS = {
    ecodes.BTN_LEFT,
    ecodes.BTN_RIGHT,
    ecodes.BTN_MIDDLE,
}

stop_event = threading.Event()
threads = []


def device_caps(dev):
    try:
        caps = dev.capabilities(verbose=False)
        key_caps = set(caps.get(ecodes.EV_KEY, []))
        rel_caps = set(caps.get(ecodes.EV_REL, []))
        abs_caps = set(caps.get(ecodes.EV_ABS, []))
        return key_caps, rel_caps, abs_caps
    except Exception:
        return set(), set(), set()


def is_pointer_device(key_caps, rel_caps, abs_caps):
    # Physical mouse:
    #   - has at least one mouse button
    #   - and exposes relative motion
    #
    # Touchpads can expose pointer-like controls too; they are intentionally
    # excluded unless they expose a physical mouse button.
    has_mouse_button = bool(key_caps & POINTER_BUTTONS)
    has_relative_axes = ecodes.REL_X in rel_caps or ecodes.REL_Y in rel_caps

    return has_mouse_button and has_relative_axes


def load_sound(path):
    if not path.exists():
        print(f"[WARN] Missing sound: {path}", file=sys.stderr)
        return None

    try:
        return pygame.mixer.Sound(str(path))
    except Exception as exc:
        print(f"[WARN] Cannot load {path}: {exc}", file=sys.stderr)
        return None


def play(sound):
    if sound is None:
        return

    try:
        sound.play()
    except Exception:
        pass


def pointer_worker(dev_path, dev_name, left_sound, right_sound, middle_sound):
    dev = None

    try:
        dev = InputDevice(dev_path)
        print(f"[POINTER] {dev_path} -> {dev_name}")

        for event in dev.read_loop():
            if stop_event.is_set():
                break

            # Mouse buttons are delivered as EV_KEY.
            if event.type != ecodes.EV_KEY:
                continue

            # Only button-down. Ignore button release.
            if event.value != 1:
                continue

            if event.code == ecodes.BTN_LEFT:
                play(left_sound)

            elif event.code == ecodes.BTN_RIGHT:
                play(right_sound)

            elif event.code == ecodes.BTN_MIDDLE:
                play(middle_sound)

    except PermissionError:
        print(
            f"[ERROR] Permission denied: {dev_path}. "
            "The user must be in the input group."
        )
    except Exception as exc:
        print(f"[POINTER ERROR] {dev_path}: {exc}")
    finally:
        if dev is not None:
            try:
                dev.close()
            except Exception:
                pass


def main():
    global threads

    print("=== Niveth Mouse Sound Effects ===")
    print("Keyboard sounds: DISABLED in Niveth daemon")
    print("Keyboard sounds should come only from MechvibesDX.")
    print(f"Sound directory: {SOUND_DIR}")

    if not SOUND_DIR.is_dir():
        print(f"[ERROR] Sound directory does not exist: {SOUND_DIR}")
        sys.exit(1)

    try:
        pygame.mixer.pre_init(
            frequency=48000,
            size=-16,
            channels=2,
            buffer=256,
            allowedchanges=0,
        )
        pygame.init()
        pygame.mixer.set_num_channels(16)
    except Exception as exc:
        print(f"[ERROR] Audio initialization failed: {exc}", file=sys.stderr)
        sys.exit(1)

    left_sound = load_sound(LEFT_SOUND)
    right_sound = load_sound(RIGHT_SOUND)
    middle_sound = load_sound(MIDDLE_SOUND)

    if left_sound is None and right_sound is None and middle_sound is None:
        print("[ERROR] No mouse sound files could be loaded.")
        pygame.quit()
        sys.exit(1)

    seen = set()

    for path in list_devices():
        try:
            dev = InputDevice(path)
        except Exception:
            continue

        try:
            key_caps, rel_caps, abs_caps = device_caps(dev)

            # IMPORTANT:
            # We NEVER classify or listen to keyboard devices.
            # Only actual pointer devices are registered.
            if is_pointer_device(key_caps, rel_caps, abs_caps):
                if dev.path not in seen:
                    seen.add(dev.path)

                    thread = threading.Thread(
                        target=pointer_worker,
                        args=(
                            dev.path,
                            dev.name,
                            left_sound,
                            right_sound,
                            middle_sound,
                        ),
                        daemon=True,
                    )
                    thread.start()
                    threads.append(thread)

        finally:
            try:
                dev.close()
            except Exception:
                pass

    if not threads:
        print("[ERROR] No mouse/pointer input device detected.")
        pygame.quit()
        sys.exit(1)

    print(f"[OK] Listening to {len(threads)} pointer device(s)")
    print("[OK] Left / right / middle click sounds enabled")
    print("[OK] Keyboard sounds completely disabled")
    print("[OK] MechvibesDX remains responsible for keyboard sounds")
    print("[OK] Press Ctrl+C to stop.")

    try:
        while True:
            time.sleep(1)

    except KeyboardInterrupt:
        print("\nStopping...")

    finally:
        stop_event.set()
        time.sleep(0.15)

        try:
            pygame.mixer.stop()
            pygame.quit()
        except Exception:
            pass


if __name__ == "__main__":
    main()
