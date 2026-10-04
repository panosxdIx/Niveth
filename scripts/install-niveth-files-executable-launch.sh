#!/usr/bin/env bash

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCE_MAIN="$HOME/Niveth-Files/main.py"

ROOTFS="$PROJECT_ROOT/build/rootfs"
ROOTFS_MAIN="$ROOTFS/usr/lib/niveth/apps/niveth-files/main.py"

BACKUP_ROOT="$PROJECT_ROOT/integration-backups"
BACKUP_DIR="$BACKUP_ROOT/niveth-files-executable-$(date +%Y%m%d-%H%M%S)"

echo "============================================================"
echo "      NIVETH FILES EXECUTABLE DOUBLE-CLICK SUPPORT"
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

echo "=== BACKUP ==="

cp "$SOURCE_MAIN" \
   "$BACKUP_DIR/source-main.py.before"

sudo cp "$ROOTFS_MAIN" \
    "$BACKUP_DIR/rootfs-main.py.before"

echo "[PASS] Source backup"
echo "[PASS] Rootfs backup"
echo "       $BACKUP_DIR"

echo
echo "=== PATCH SOURCE ==="

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
        Open a selected file.

        Executable Linux files are launched directly so applications,
        AppImages and standalone executables can be opened with a
        double-click from Niveth Files.

        .desktop files continue to use the desktop environment's normal
        default handler.
        """

        path = os.path.abspath(path)

        if not os.path.isfile(path):
            return

        try:
            suffix = Path(path).suffix.lower()

            if (
                suffix != ".desktop"
                and os.access(path, os.X_OK)
            ):
                try:
                    subprocess.Popen(
                        [path],
                        cwd=os.path.dirname(path) or None,
                        start_new_session=True,
                        stdin=subprocess.DEVNULL,
                        stdout=subprocess.DEVNULL,
                        stderr=subprocess.DEVNULL,
                    )

                    print(
                        f"NIVETH: Launched executable: {path}"
                    )

                    return

                except (
                    OSError,
                    PermissionError,
                ) as exc:
                    print(
                        "NIVETH: Direct executable launch failed "
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
        "ERROR: _open_file() method was not found."
    )

updated = (
    text[:match.start()]
    + replacement
    + text[match.end():]
)

path.write_text(
    updated,
    encoding="utf-8",
)
PY

echo "[PASS] Source patched"

echo
echo "=== SOURCE PYTHON CHECK ==="

python3 -m py_compile "$SOURCE_MAIN"

echo "[PASS] Source Python syntax"

echo
echo "=== SYNC TO ROOTFS ==="

sudo cp "$SOURCE_MAIN" "$ROOTFS_MAIN"
sudo chown root:root "$ROOTFS_MAIN"
sudo chmod 0644 "$ROOTFS_MAIN"

echo "[PASS] Rootfs synchronized"

echo
echo "=== ROOTFS PYTHON CHECK ==="

sudo python3 -m py_compile "$ROOTFS_MAIN"

sudo rm -rf \
    "$ROOTFS/usr/lib/niveth/apps/niveth-files/__pycache__"

echo "[PASS] Rootfs Python syntax"

echo
echo "=== VERIFY DOUBLE-CLICK HANDLER ==="

echo "--- SOURCE ---"

grep -n -A60 '^    def _open_file' \
    "$SOURCE_MAIN"

echo
echo "--- ROOTFS ---"

sudo grep -n -A60 '^    def _open_file' \
    "$ROOTFS_MAIN"

echo
echo "=== MANIFEST ==="

if grep -qF \
    "COPY_FILE /home/modos/Niveth-Files/main.py /usr/lib/niveth/apps/niveth-files/main.py" \
    "$PROJECT_ROOT/desktop/niveth-components.txt"; then

    echo "[PASS] Niveth Files main.py already belongs to the ISO manifest"

else

    echo "[ERROR] Niveth Files main.py is missing from the ISO manifest"
    exit 1
fi

echo
echo "============================================================"
echo "[DONE] Niveth Files executable double-click support installed."
echo "============================================================"
echo
echo "Ubuntu host:"
echo "  $SOURCE_MAIN"
echo
echo "Niveth ISO rootfs:"
echo "  $ROOTFS_MAIN"
echo
echo "Backup:"
echo "  $BACKUP_DIR"
echo
echo "Supported examples:"
echo "  balena-etcher"
echo "  executable Linux binaries"
echo "  AppImages"
echo "  executable scripts"
echo
echo "NOTE:"
echo "  Restart Niveth Files before testing."
