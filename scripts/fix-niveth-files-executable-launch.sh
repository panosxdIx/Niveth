#!/usr/bin/env bash

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCE_MAIN="$HOME/Niveth-Files/main.py"
ROOTFS="$PROJECT_ROOT/build/rootfs"
ROOTFS_MAIN="$ROOTFS/usr/lib/niveth/apps/niveth-files/main.py"

BACKUP_DIR="$PROJECT_ROOT/integration-backups/niveth-files-executable-$(date +%Y%m%d-%H%M%S)"

echo "============================================================"
echo "       NIVETH FILES EXECUTABLE DOUBLE-CLICK FIX"
echo "============================================================"
echo

if [ ! -f "$SOURCE_MAIN" ]; then
    echo "[ERROR] Source Niveth Files main.py not found:"
    echo "        $SOURCE_MAIN"
    exit 1
fi

if [ ! -f "$ROOTFS_MAIN" ]; then
    echo "[ERROR] Rootfs Niveth Files main.py not found:"
    echo "        $ROOTFS_MAIN"
    exit 1
fi

mkdir -p "$BACKUP_DIR"

cp "$SOURCE_MAIN" "$BACKUP_DIR/source-main.py.before"
sudo cp "$ROOTFS_MAIN" "$BACKUP_DIR/rootfs-main.py.before"

echo "[PASS] Backups created:"
echo "       $BACKUP_DIR"

python3 - "$SOURCE_MAIN" <<'PY'
from pathlib import Path
import re
import sys

path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")

pattern = re.compile(
    r'^    def _open_file\(\n'
    r'.*?'
    r'(?=^    def |\Z)',
    re.MULTILINE | re.DOTALL,
)

replacement = '''    def _open_file(
        self,
        path,
    ):
        """
        Open a file using its normal default application.

        Executable files are launched directly so that applications such
        as AppImages and standalone Linux executables can be opened with
        a double-click from Niveth Files.
        """

        path = os.path.abspath(path)

        if not os.path.isfile(path):
            return

        try:
            if os.access(path, os.X_OK):
                try:
                    subprocess.Popen(
                        [path],
                        cwd=os.path.dirname(path) or None,
                        start_new_session=True,
                        stdout=subprocess.DEVNULL,
                        stderr=subprocess.DEVNULL,
                    )

                    print(
                        f"NIVETH: Launched executable {path}"
                    )

                    return

                except (OSError, PermissionError) as exc:
                    print(
                        f"NIVETH: Direct executable launch failed "
                        f"for {path}: {exc}"
                    )

            file = Gio.File.new_for_path(path)

            Gio.AppInfo.launch_default_for_uri(
                file.get_uri(),
                None,
            )

        except Exception as exc:
            print(
                f"NIVETH: Could not open {path}: {exc}"
            )

'''

match = pattern.search(text)

if not match:
    raise SystemExit(
        "ERROR: Could not locate _open_file() method."
    )

text = (
    text[:match.start()]
    + replacement
    + text[match.end():]
)

path.write_text(text, encoding="utf-8")
PY

echo "[PASS] Source Niveth Files updated"

python3 -m py_compile "$SOURCE_MAIN"
echo "[PASS] Source Python syntax"

sudo cp "$SOURCE_MAIN" "$ROOTFS_MAIN"
sudo chown root:root "$ROOTFS_MAIN"
sudo chmod 0644 "$ROOTFS_MAIN"

echo "[PASS] Rootfs Niveth Files updated"

sudo python3 -m py_compile "$ROOTFS_MAIN"
sudo rm -rf "$ROOTFS/usr/lib/niveth/apps/niveth-files/__pycache__"

echo "[PASS] Rootfs Python syntax"

echo
echo "=== VERIFY SOURCE ==="

grep -n -A52 '^    def _open_file' "$SOURCE_MAIN"

echo
echo "=== VERIFY ROOTFS ==="

sudo grep -n -A52 '^    def _open_file' "$ROOTFS_MAIN"

echo
echo "============================================================"
echo "[DONE] Niveth Files executable double-click support installed."
echo "============================================================"
echo
echo "Executable files will now launch directly when double-clicked."
echo
echo "Examples:"
echo "  AppImage"
echo "  standalone Linux binary"
echo "  executable script"
echo
echo "Backup:"
echo "  $BACKUP_DIR"
