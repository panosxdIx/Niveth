#!/usr/bin/env bash
set -euo pipefail

EXT_ID="niveth-system-monitor@nivethos"

LIVE_DIR="$HOME/.local/share/gnome-shell/extensions/$EXT_ID"
ROOTFS_DIR="$HOME/Niveth/build/rootfs/usr/share/gnome-shell/extensions/$EXT_ID"

echo "============================================================"
echo " NIVETH SYSTEM MONITOR — AUDIO READER FIX"
echo "============================================================"

if [ ! -f "$LIVE_DIR/extension.js" ]; then
    echo "[ERROR] extension.js not found"
    exit 1
fi

echo
echo "[1/7] Disabling extension..."

gnome-extensions disable "$EXT_ID" 2>/dev/null || true
sleep 2

echo "[2/7] Creating backup..."

BACKUP_DIR="$LIVE_DIR/backup-audio-reader-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$BACKUP_DIR"

cp "$LIVE_DIR/extension.js" "$BACKUP_DIR/extension.js"
cp "$LIVE_DIR/stylesheet.css" "$BACKUP_DIR/stylesheet.css"
cp "$LIVE_DIR/metadata.json" "$BACKUP_DIR/metadata.json"

echo "[PASS] Backup:"
echo "$BACKUP_DIR"

echo
echo "[3/7] Replacing only _readAudioLine()..."

python3 - "$LIVE_DIR/extension.js" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")


def find_method(source, name):
    needle = f"    {name}("
    start = source.find(needle)

    if start < 0:
        raise RuntimeError(f"Method not found: {name}")

    brace_start = source.find("{", start)

    if brace_start < 0:
        raise RuntimeError(f"Opening brace not found: {name}")

    depth = 0
    quote = None
    escape = False
    line_comment = False
    block_comment = False

    i = brace_start

    while i < len(source):
        ch = source[i]
        nxt = source[i + 1] if i + 1 < len(source) else ""

        if line_comment:
            if ch == "\n":
                line_comment = False
            i += 1
            continue

        if block_comment:
            if ch == "*" and nxt == "/":
                block_comment = False
                i += 2
                continue
            i += 1
            continue

        if quote is not None:
            if escape:
                escape = False
            elif ch == "\\":
                escape = True
            elif ch == quote:
                quote = None
            i += 1
            continue

        if ch == "/" and nxt == "/":
            line_comment = True
            i += 2
            continue

        if ch == "/" and nxt == "*":
            block_comment = True
            i += 2
            continue

        if ch in ("'", '"', "`"):
            quote = ch
            i += 1
            continue

        if ch == "{":
            depth += 1

        elif ch == "}":
            depth -= 1

            if depth == 0:
                return start, i + 1

        i += 1

    raise RuntimeError(f"Could not find end of method: {name}")


def replace_method(source, name, replacement):
    start, end = find_method(source, name)
    return source[:start] + replacement + source[end:]


replacement = r"""    _readAudioLine() {

        if (
            !this._audioReader ||
            !this._audioProcess
        )
            return;

        this._audioReader.read_line_async(

            GLib.PRIORITY_DEFAULT,

            null,

            (
                stream,
                result
            ) => {

                try {

                    /*
                     * IMPORTANT:
                     *
                     * Use the UTF-8 finish function for
                     * text lines from Gio.DataInputStream.
                     */
                    const [
                        line,
                        length,
                    ] =
                        stream.read_line_finish_utf8(
                            result
                        );

                    if (
                        line === null ||
                        length === 0
                    ) {

                        this._audioTarget = 0;

                        this._audioValue?.set_text(
                            'AUDIO OFF'
                        );

                        return;
                    }

                    const value =
                        Number(
                            line.trim()
                        );

                    if (
                        !Number.isFinite(
                            value
                        )
                    ) {

                        this._readAudioLine();

                        return;
                    }

                    this._audioTarget =
                        Math.max(
                            0,
                            Math.min(
                                100,
                                value
                            )
                        );

                    /*
                     * This is deliberately visible so
                     * we can verify that the extension
                     * receives the audio stream.
                     */
                    this._audioValue?.set_text(
                        `AUDIO ${Math.round(
                            this._audioTarget
                        )}%`
                    );

                    this._readAudioLine();

                } catch (error) {

                    /*
                     * Keep the process alive if one
                     * individual read fails.
                     */
                    log(
                        `NIVETH AUDIO READ ERROR: ${error}`
                    );

                    this._audioTarget = 0;

                    this._audioValue?.set_text(
                        'AUDIO ERROR'
                    );

                    /*
                     * Retry the reader instead of
                     * permanently stopping it.
                     */
                    GLib.timeout_add(
                        GLib.PRIORITY_DEFAULT,
                        250,
                        () => {

                            if (
                                this._audioReader &&
                                this._audioProcess
                            ) {

                                this._audioValue?.set_text(
                                    'AUDIO LIVE'
                                );

                                this._readAudioLine();
                            }

                            return GLib.SOURCE_REMOVE;
                        }
                    );
                }
            }
        );
    }
"""

text = replace_method(
    text,
    "_readAudioLine",
    replacement
)

path.write_text(
    text,
    encoding="utf-8"
)

print("[PASS] _readAudioLine() replaced")
PY

echo
echo "[4/7] Verifying new reader..."

grep -n -A90 \
"_readAudioLine()" \
"$LIVE_DIR/extension.js" |
head -100

if grep -q "read_line_finish_utf8" "$LIVE_DIR/extension.js"; then
    echo "[PASS] read_line_finish_utf8() present"
else
    echo "[ERROR] UTF-8 finish function missing"
    exit 1
fi

echo
echo "[5/7] Syncing to Niveth rootfs..."

sudo mkdir -p "$ROOTFS_DIR"

sudo install -Dm644 \
    "$LIVE_DIR/extension.js" \
    "$ROOTFS_DIR/extension.js"

echo "[PASS] Rootfs extension.js synchronized"

echo
echo "[6/7] Hash verification..."

LIVE_HASH="$(
    sha256sum \
        "$LIVE_DIR/extension.js" |
    awk '{print $1}'
)"

ROOT_HASH="$(
    sudo sha256sum \
        "$ROOTFS_DIR/extension.js" |
    awk '{print $1}'
)"

echo "LIVE: $LIVE_HASH"
echo "ROOT: $ROOT_HASH"

if [ "$LIVE_HASH" != "$ROOT_HASH" ]; then
    echo "[ERROR] Hash mismatch"
    exit 1
fi

echo "[PASS] Hashes match"

echo
echo "[7/7] Enabling extension..."

gnome-extensions enable "$EXT_ID"

sleep 5

echo
echo "============================================================"
echo " FINAL STATUS"
echo "============================================================"

gnome-extensions info "$EXT_ID"

echo
echo "============================================================"
echo " AUDIO TEST"
echo "============================================================"
echo
echo "Βάλε YouTube να παίζει."
echo
echo "Το AUDIO πρέπει να δείξει:"
echo
echo "AUDIO 70%"
echo "AUDIO 76%"
echo "AUDIO 82%"
echo
echo "και από κάτω να κινείται το waveform."
echo
echo "============================================================"
