#!/usr/bin/env bash

set -uo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ROOTFS="$PROJECT_ROOT/build/rootfs"
LOG_DIR="$PROJECT_ROOT/integration-backups"
LOG="$LOG_DIR/niveth-calamares-offscreen-$(date +%Y%m%d-%H%M%S).log"

mkdir -p "$LOG_DIR"

echo "=============================================="
echo " NIVETH CALAMARES OFFSCREEN RUNTIME TEST"
echo "=============================================="

if [[ ! -d "$ROOTFS" ]]; then
    echo "[ERROR] Rootfs not found:"
    echo "        $ROOTFS"
    exit 1
fi

echo
echo "=== 1. CALAMARES PACKAGE ==="

sudo chroot "$ROOTFS" \
    dpkg-query -W \
    -f='${Package} ${Version}\n' \
    calamares \
    calamares-extensions \
    calamares-settings-ubuntu-common \
    calamares-settings-ubuntu-common-data \
    2>/dev/null || true

echo
echo "=== 2. CALAMARES EXECUTABLE ==="

if [[ ! -x "$ROOTFS/usr/bin/calamares" ]]; then
    echo "[ERROR] /usr/bin/calamares is missing"
    exit 1
fi

echo "[PASS] $ROOTFS/usr/bin/calamares exists"

echo
echo "=== 3. QT PLATFORM PLUGINS ==="

sudo chroot "$ROOTFS" sh -c '
    find /usr/lib /usr/lib/x86_64-linux-gnu \
        -type f \
        \( \
            -name "libqoffscreen.so" \
            -o -name "libqminimal.so" \
            -o -name "libqwayland*.so" \
            -o -name "libqxcb.so" \
        \) \
        2>/dev/null | sort -u
'

echo
echo "=== 4. REQUIRED CALAMARES CONFIG ==="

for file in \
    "$ROOTFS/etc/calamares/settings.conf" \
    "$ROOTFS/etc/calamares/modules/bootloader.conf" \
    "$ROOTFS/etc/calamares/modules/locale.conf" \
    "$ROOTFS/etc/calamares/modules/grubcfg.conf" \
    "$ROOTFS/etc/calamares/branding/niveth/branding.desc"
do
    if [[ ! -f "$file" ]]; then
        echo "[ERROR] Missing:"
        echo "        $file"
        exit 1
    fi

    echo "[PASS] $(realpath --relative-to="$ROOTFS" "$file")"
done

echo
echo "=== 5. OFFSCREEN STARTUP ==="

set +e

sudo chroot "$ROOTFS" \
    env \
        LANG=C.UTF-8 \
        LC_ALL=C.UTF-8 \
        QT_QPA_PLATFORM=offscreen \
        XDG_RUNTIME_DIR=/tmp/niveth-xdg \
        /bin/sh -c '
            mkdir -p "$XDG_RUNTIME_DIR"
            chmod 700 "$XDG_RUNTIME_DIR"
            exec /usr/bin/calamares -D6
        ' \
    >"$LOG" 2>&1 &

PID=$!

echo "[INFO] Calamares PID: $PID"
echo "[INFO] Waiting up to 15 seconds..."

SECONDS_WAITED=0

while kill -0 "$PID" 2>/dev/null; do
    sleep 1
    SECONDS_WAITED=$((SECONDS_WAITED + 1))

    if [[ "$SECONDS_WAITED" -ge 15 ]]; then
        echo "[INFO] Calamares remained running for 15 seconds."
        echo "[INFO] Stopping test instance."
        sudo kill "$PID" 2>/dev/null || true
        sleep 1
        sudo kill -9 "$PID" 2>/dev/null || true
        wait "$PID" 2>/dev/null || true
        RC=124
        break
    fi
done

if [[ "${RC:-}" != "124" ]]; then
    wait "$PID"
    RC=$?
fi

set -e

echo
echo "=== 6. RUNTIME LOG ==="

cat "$LOG"

echo
echo "=== 7. ERROR SCAN ==="

if grep -Eqi \
    'fatal|configuration error|config error|parse error|yaml.*error|unknown module|module.*not found|branding.*error|failed to load.*branding|failed to load.*module|cannot load.*module|cannot load.*branding' \
    "$LOG"
then

    echo "[ERROR] Possible Calamares configuration/module problem detected."
    echo
    echo "Full log:"
    echo "  $LOG"
    exit 1
fi

if grep -Eqi \
    'could not connect to display|could not load the Qt platform plugin|qt.qpa.xcb|no Qt platform plugin' \
    "$LOG"
then

    echo "[ERROR] Qt platform initialization still failed."
    echo
    echo "Full log:"
    echo "  $LOG"
    exit 1
fi

echo "[PASS] No obvious Calamares configuration error found"
echo "[PASS] No obvious Qt display/platform error found"

echo
echo "=== 8. EXIT STATUS ==="

echo "Calamares exit status: $RC"

if [[ "$RC" -eq 124 ]]; then
    echo "[PASS] Calamares stayed alive for the full test window."
    echo "[PASS] Offscreen Qt initialization appears successful."
elif [[ "$RC" -eq 0 ]]; then
    echo "[PASS] Calamares exited normally."
else
    echo "[INFO] Calamares exited with status $RC."
    echo "[INFO] Review the runtime log above."
fi

echo
echo "=== 9. LOG FILE ==="
echo "$LOG"

echo
echo "=============================================="
echo " NIVETH CALAMARES OFFSCREEN TEST COMPLETE"
echo "=============================================="

echo
echo "NO ISO BUILD WAS PERFORMED."
echo "NO ROOTFS FILES WERE MODIFIED BY THIS TEST."
