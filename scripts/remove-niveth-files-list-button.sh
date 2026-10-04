#!/usr/bin/env bash

set -euo pipefail

PROJECT_ROOT="$HOME/Niveth"

SOURCE_MAIN="$HOME/Niveth-Files/main.py"
HOST_MAIN="/usr/lib/niveth/apps/niveth-files/main.py"
ROOTFS_MAIN="$PROJECT_ROOT/build/rootfs/usr/lib/niveth/apps/niveth-files/main.py"

BACKUP_DIR="$PROJECT_ROOT/integration-backups/niveth-files-remove-list-button-$(date +%Y%m%d-%H%M%S)"

echo "============================================================"
echo " NIVETH FILES - REMOVE LIST VIEW BUTTON"
echo "============================================================"
echo

mkdir -p "$BACKUP_DIR"

cp "$SOURCE_MAIN" "$BACKUP_DIR/source-main.py.before"
sudo cp "$HOST_MAIN" "$BACKUP_DIR/host-main.py.before"
sudo cp "$ROOTFS_MAIN" "$BACKUP_DIR/rootfs-main.py.before"

echo "[PASS] Backups created:"
echo "       $BACKUP_DIR"

echo
echo "=== 1. REMOVE 3-LINE LIST BUTTON ==="

python3 - "$SOURCE_MAIN" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")

block = '''        self.list_view_button = Gtk.ToggleButton.new()

        self.list_view_button.set_child(
            Gtk.Image.new_from_icon_name(
                "view-list-symbolic"
            )
        )

        self.list_view_button.add_css_class(
            "view-button"
        )

        header.pack_start(
            self.list_view_button
        )

'''

count = text.count(block)

if count == 0:
    raise SystemExit(
        "ERROR: list_view_button block was not found."
    )

if count > 1:
    raise SystemExit(
        f"ERROR: Found {count} list_view_button blocks; refusing ambiguous patch."
    )

text = text.replace(block, "", 1)

if "list_view_button" in text:
    raise SystemExit(
        "ERROR: list_view_button references still remain."
    )

path.write_text(text, encoding="utf-8")

print("[PASS] 3-line List View button removed.")
PY

echo
echo "=== 2. VERIFY SOURCE ==="

python3 - <<'PY'
from pathlib import Path

p = Path.home() / "Niveth-Files/main.py"
compile(p.read_text(encoding="utf-8"), str(p), "exec")
print("[PASS] Source syntax")
PY

echo
echo "=== 3. SYNC INSTALLED HOST ==="

sudo cp "$SOURCE_MAIN" "$HOST_MAIN"
sudo rm -rf /usr/lib/niveth/apps/niveth-files/__pycache__

echo "[PASS] Host app synchronized"

echo
echo "=== 4. SYNC ROOTFS ==="

sudo cp "$SOURCE_MAIN" "$ROOTFS_MAIN"
sudo rm -rf \
    "$PROJECT_ROOT/build/rootfs/usr/lib/niveth/apps/niveth-files/__pycache__"

echo "[PASS] Rootfs synchronized"

echo
echo "=== 5. VERIFY INSTALLED COPIES ==="

python3 - <<'PY'
from pathlib import Path

for label, p in [
    (
        "Host",
        Path("/usr/lib/niveth/apps/niveth-files/main.py"),
    ),
    (
        "Rootfs",
        Path.home()
        / "Niveth/build/rootfs/usr/lib/niveth/apps/niveth-files/main.py",
    ),
]:
    text = p.read_text(encoding="utf-8")
    compile(text, str(p), "exec")

    if "list_view_button" in text:
        raise SystemExit(
            f"ERROR: list_view_button still exists in {label}."
        )

    print(f"[PASS] {label} verification")

echo
print("============================================================")
print(" LIST VIEW BUTTON REMOVED")
print("============================================================")
print()
print("3-line button : REMOVED")
print("Grid view      : KEPT")
print("Column view    : KEPT")
print("Host copy      : UPDATED")
print("Rootfs copy    : UPDATED")
print()
PY

echo "Backup:"
echo "  $BACKUP_DIR"
