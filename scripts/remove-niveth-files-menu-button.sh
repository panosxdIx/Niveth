#!/usr/bin/env bash

set -euo pipefail

SOURCE_MAIN="$HOME/Niveth-Files/main.py"
HOST_MAIN="/usr/lib/niveth/apps/niveth-files/main.py"
ROOTFS_MAIN="$HOME/Niveth/build/rootfs/usr/lib/niveth/apps/niveth-files/main.py"

BACKUP_DIR="$HOME/Niveth/integration-backups/niveth-files-remove-menu-$(date +%Y%m%d-%H%M%S)"

mkdir -p "$BACKUP_DIR"

cp "$SOURCE_MAIN" "$BACKUP_DIR/source-main.py.before"
sudo cp "$HOST_MAIN" "$BACKUP_DIR/host-main.py.before"
sudo cp "$ROOTFS_MAIN" "$BACKUP_DIR/rootfs-main.py.before"

echo "[PASS] Backups created:"
echo "       $BACKUP_DIR"

python3 - "$SOURCE_MAIN" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")

start_marker = '        menu_button = Gtk.MenuButton()\n'
end_marker = '''        header.pack_end(
            menu_button
        )

'''

start = text.find(start_marker)
end = text.find(end_marker, start)

if start == -1:
    raise SystemExit(
        "ERROR: Menu button start block not found."
    )

if end == -1:
    raise SystemExit(
        "ERROR: Menu button end block not found."
    )

end += len(end_marker)

text = text[:start] + text[end:]

if "open-menu-symbolic" in text:
    raise SystemExit(
        "ERROR: open-menu-symbolic still exists after patch."
    )

if "menu_button" in text:
    raise SystemExit(
        "ERROR: menu_button references still remain."
    )

path.write_text(text, encoding="utf-8")

print("[PASS] Header menu button removed.")
PY

echo
echo "=== SOURCE CHECK ==="

python3 - <<'PY'
from pathlib import Path

p = Path.home() / "Niveth-Files/main.py"
compile(p.read_text(encoding="utf-8"), str(p), "exec")

text = p.read_text(encoding="utf-8")

assert "open-menu-symbolic" not in text
assert "menu_button" not in text

print("[PASS] Source syntax")
print("[PASS] No menu button")
PY

echo
echo "=== SYNC HOST ==="

sudo cp "$SOURCE_MAIN" "$HOST_MAIN"
sudo rm -rf /usr/lib/niveth/apps/niveth-files/__pycache__

echo "[PASS] Installed Niveth Files updated"

echo
echo "=== SYNC ROOTFS ==="

sudo cp "$SOURCE_MAIN" "$ROOTFS_MAIN"
sudo rm -rf \
    "$HOME/Niveth/build/rootfs/usr/lib/niveth/apps/niveth-files/__pycache__"

echo "[PASS] Rootfs updated"

echo
echo "=== FINAL VERIFY ==="

python3 - <<'PY'
from pathlib import Path

files = [
    Path("/usr/lib/niveth/apps/niveth-files/main.py"),
    Path.home() / "Niveth/build/rootfs/usr/lib/niveth/apps/niveth-files/main.py",
]

for p in files:
    text = p.read_text(encoding="utf-8")
    compile(text, str(p), "exec")

    if "open-menu-symbolic" in text:
        raise SystemExit(f"ERROR: menu icon remains in {p}")

    if "menu_button" in text:
        raise SystemExit(f"ERROR: menu button remains in {p}")

    print(f"[PASS] {p}")

EOF_STATUS=$?

if [[ $EOF_STATUS -ne 0 ]]; then
    exit "$EOF_STATUS"
fi

echo
echo "============================================================"
echo " NIVETH FILES MENU BUTTON REMOVED"
echo "============================================================"
echo
echo "3-line menu button : REMOVED"
echo "Source             : UPDATED"
echo "Installed app      : UPDATED"
echo "Rootfs             : UPDATED"
echo
echo "Backup:"
echo "  $BACKUP_DIR"
