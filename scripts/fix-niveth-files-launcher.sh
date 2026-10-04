#!/usr/bin/env bash

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ROOTFS="$PROJECT_ROOT/build/rootfs"

HOST_MAIN="/usr/lib/niveth/apps/niveth-files/main.py"
ROOTFS_MAIN="$ROOTFS/usr/lib/niveth/apps/niveth-files/main.py"

HOST_LAUNCHER="/usr/local/bin/niveth-files"
ROOTFS_LAUNCHER="$ROOTFS/usr/local/bin/niveth-files"

SOURCE_MAIN="$HOME/Niveth-Files/main.py"

echo "============================================================"
echo "          NIVETH FILES LAUNCHER FIX"
echo "============================================================"
echo

echo "=== 1. VERIFY SOURCE ==="

if [ ! -f "$SOURCE_MAIN" ]; then
    echo "[ERROR] Source main.py missing:"
    echo "$SOURCE_MAIN"
    exit 1
fi

echo "[PASS] Source main.py"

echo
echo "=== 2. SYNC HOST Niveth Files ==="

sudo mkdir -p "$(dirname "$HOST_MAIN")"
sudo cp "$SOURCE_MAIN" "$HOST_MAIN"
sudo chown root:root "$HOST_MAIN"
sudo chmod 0644 "$HOST_MAIN"

echo "[PASS] Host Niveth Files synchronized"

echo
echo "=== 3. UPDATE HOST LAUNCHER ==="

sudo tee "$HOST_LAUNCHER" >/dev/null <<'LAUNCHER'
#!/bin/sh
exec /usr/bin/python3 /usr/lib/niveth/apps/niveth-files/main.py "$@"
LAUNCHER

sudo chown root:root "$HOST_LAUNCHER"
sudo chmod 0755 "$HOST_LAUNCHER"

echo "[PASS] Host launcher now uses:"
echo "       /usr/lib/niveth/apps/niveth-files/main.py"

echo
echo "=== 4. SYNC ROOTFS ==="

sudo mkdir -p "$(dirname "$ROOTFS_MAIN")"
sudo cp "$SOURCE_MAIN" "$ROOTFS_MAIN"
sudo chown root:root "$ROOTFS_MAIN"
sudo chmod 0644 "$ROOTFS_MAIN"

echo "[PASS] Rootfs Niveth Files synchronized"

echo
echo "=== 5. UPDATE ROOTFS LAUNCHER ==="

sudo mkdir -p "$(dirname "$ROOTFS_LAUNCHER")"

sudo tee "$ROOTFS_LAUNCHER" >/dev/null <<'LAUNCHER'
#!/bin/sh
exec /usr/bin/python3 /usr/lib/niveth/apps/niveth-files/main.py "$@"
LAUNCHER

sudo chown root:root "$ROOTFS_LAUNCHER"
sudo chmod 0755 "$ROOTFS_LAUNCHER"

echo "[PASS] Rootfs launcher updated"

echo
echo "=== 6. PYTHON CHECK ==="

python3 -m py_compile "$SOURCE_MAIN"
sudo python3 -m py_compile "$HOST_MAIN"
sudo python3 -m py_compile "$ROOTFS_MAIN"

sudo rm -rf \
    "$(dirname "$HOST_MAIN")/__pycache__" \
    "$(dirname "$ROOTFS_MAIN")/__pycache__"

echo "[PASS] Python syntax"

echo
echo "=== 7. VERIFY LAUNCHERS ==="

echo "--- HOST ---"
cat "$HOST_LAUNCHER"

echo
echo "--- ROOTFS ---"
sudo cat "$ROOTFS_LAUNCHER"

echo
echo "=== 8. VERIFY NEW EXECUTABLE HANDLER ==="

if sudo grep -q 'os.access(path, os.X_OK)' "$HOST_MAIN"; then
    echo "[PASS] Host executable double-click handler"
else
    echo "[FAIL] Host executable handler missing"
    exit 1
fi

if sudo grep -q 'os.access(path, os.X_OK)' "$ROOTFS_MAIN"; then
    echo "[PASS] Rootfs executable double-click handler"
else
    echo "[FAIL] Rootfs executable handler missing"
    exit 1
fi

echo
echo "=== 9. DESKTOP DATABASE ==="

sudo update-desktop-database /usr/share/applications 2>/dev/null || true

echo "[PASS] Desktop database refreshed"

echo
echo "============================================================"
echo "[DONE] Niveth Files launcher is now synchronized."
echo "============================================================"
echo
echo "Host:"
echo "  $HOST_MAIN"
echo
echo "Rootfs:"
echo "  $ROOTFS_MAIN"
echo
echo "Launcher:"
echo "  $HOST_LAUNCHER"
echo "  $ROOTFS_LAUNCHER"
