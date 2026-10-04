#!/usr/bin/env bash

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

SOURCE_MAIN="$HOME/Niveth-Files/main.py"
HOST_MAIN="/usr/lib/niveth/apps/niveth-files/main.py"

ROOTFS="$PROJECT_ROOT/build/rootfs"
ROOTFS_MAIN="$ROOTFS/usr/lib/niveth/apps/niveth-files/main.py"

BACKUP_ROOT="$PROJECT_ROOT/integration-backups"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP_DIR="$BACKUP_ROOT/niveth-files-executable-$STAMP"

echo "============================================================"
echo "       NIVETH FILES - EXECUTABLE CONTEXT MENU"
echo "============================================================"
echo

if [ ! -f "$SOURCE_MAIN" ]; then
    echo "[ERROR] Source missing:"
    echo "        $SOURCE_MAIN"
    exit 1
fi

if [ ! -f "$ROOTFS_MAIN" ]; then
    echo "[ERROR] Rootfs Niveth Files missing:"
    echo "        $ROOTFS_MAIN"
    exit 1
fi

mkdir -p "$BACKUP_DIR"

cp "$SOURCE_MAIN" \
    "$BACKUP_DIR/source-main.py.before"

sudo cp "$ROOTFS_MAIN" \
    "$BACKUP_DIR/rootfs-main.py.before"

echo "[PASS] Backup:"
echo "       $BACKUP_DIR"
echo

echo "=== 1. PATCH SOURCE ==="

python3 - "$SOURCE_MAIN" <<'PY'
from pathlib import Path
import re
import sys

path = Path(sys.argv[1])

text = path.read_text(
    encoding="utf-8"
)

MARKER = "NIVETH EXECUTABLE PERMISSION SUPPORT v1"

if MARKER in text:
    print(
        "[PASS] Executable support already exists."
    )
    raise SystemExit(0)

# =========================================================
# 1. INSERT EXECUTABLE TOGGLE METHOD
# =========================================================

method = r'''
    # =========================================================
    # NIVETH EXECUTABLE PERMISSION SUPPORT v1
    # =========================================================

    def _toggle_executable_permission(
        self,
    ):
        """
        Toggle execute permission for one selected file.

        Non-executable:
            Make Executable

        Executable:
            Remove Execute Permission
        """

        if len(self.selected_paths) != 1:
            print(
                "NIVETH: Executable permission requires "
                "exactly one selected file."
            )
            return

        path = os.path.abspath(
            self.selected_paths[0]
        )

        if not os.path.isfile(path):
            print(
                f"NIVETH: Not a regular file: {path}"
            )
            return

        try:
            mode = os.stat(
                path
            ).st_mode

            execute_bits = 0o111

            if mode & execute_bits:
                new_mode = (
                    mode
                    & ~execute_bits
                )

                os.chmod(
                    path,
                    new_mode,
                )

                print(
                    "NIVETH: Removed execute permission: "
                    f"{path}"
                )

            else:
                new_mode = (
                    mode
                    | execute_bits
                )

                os.chmod(
                    path,
                    new_mode,
                )

                print(
                    "NIVETH: Made executable: "
                    f"{path}"
                )

            try:
                self._update_preview(
                    path
                )
            except Exception:
                pass

            try:
                self._update_status()
            except Exception:
                pass

        except (
            OSError,
            PermissionError,
        ) as exc:
            print(
                "NIVETH: Could not change executable "
                f"permission for {path}: {exc}"
            )

'''

open_match = re.search(
    r"(?m)^    def _open_file\(\s*$",
    text,
)

if not open_match:
    raise SystemExit(
        "ERROR: _open_file() not found."
    )

text = (
    text[:open_match.start()]
    + method
    + text[open_match.start():]
)

# =========================================================
# 2. PATCH ITEM CONTEXT MENU
# =========================================================

menu_match = re.search(
    r"(?ms)^    def _show_item_context_menu\(.*?(?=^    def |\Z)",
    text,
)

if not menu_match:
    raise SystemExit(
        "ERROR: _show_item_context_menu() not found."
    )

menu = menu_match.group(0)

if (
    "Make Executable" in menu
    or
    "Remove Execute Permission" in menu
):
    print(
        "[PASS] Executable context menu already exists."
    )
    raise SystemExit(0)

rename_pos = menu.find(
    '"Rename"'
)

if rename_pos < 0:
    raise SystemExit(
        "ERROR: Rename menu item not found."
    )

rename_start = menu.rfind(
    "        self._context_item(",
    0,
    rename_pos,
)

if rename_start < 0:
    raise SystemExit(
        "ERROR: Rename context-item boundary not found."
    )

executable_menu = '''        executable_enabled = (
            single
            and os.path.isfile(
                self.selected_paths[0]
            )
        )

        executable_label = (
            "Remove Execute Permission"
            if (
                executable_enabled
                and os.access(
                    self.selected_paths[0],
                    os.X_OK,
                )
            )
            else
            "Make Executable"
        )

        self._context_item(
            content,
            executable_label,
            "application-x-executable-symbolic",
            self._toggle_executable_permission,
            enabled=executable_enabled,
        )

        self._context_separator(
            content
        )

'''

menu = (
    menu[:rename_start]
    + executable_menu
    + menu[rename_start:]
)

text = (
    text[:menu_match.start()]
    + menu
    + text[menu_match.end():]
)

path.write_text(
    text,
    encoding="utf-8",
)

print(
    "[PASS] Executable permission method inserted."
)

print(
    "[PASS] Executable context menu inserted."
)
PY

echo

echo "=== 2. PYTHON VALIDATION ==="

python3 -m py_compile \
    "$SOURCE_MAIN"

echo "[PASS] Source Python syntax"
echo

echo "=== 3. VERIFY SOURCE ==="

grep -q \
    "NIVETH EXECUTABLE PERMISSION SUPPORT v1" \
    "$SOURCE_MAIN"

grep -q \
    "Make Executable" \
    "$SOURCE_MAIN"

grep -q \
    "Remove Execute Permission" \
    "$SOURCE_MAIN"

grep -q \
    "_toggle_executable_permission" \
    "$SOURCE_MAIN"

echo "[PASS] Make Executable"
echo "[PASS] Remove Execute Permission"
echo "[PASS] Toggle method"
echo

echo "=== 4. SYNC UBUNTU HOST ==="

sudo mkdir -p \
    "$(dirname "$HOST_MAIN")"

sudo cp \
    "$SOURCE_MAIN" \
    "$HOST_MAIN"

sudo chown root:root \
    "$HOST_MAIN"

sudo chmod 0644 \
    "$HOST_MAIN"

sudo rm -rf \
    "/usr/lib/niveth/apps/niveth-files/__pycache__"

echo "[PASS] Ubuntu host synchronized"
echo

echo "=== 5. SYNC ISO ROOTFS ==="

sudo cp \
    "$SOURCE_MAIN" \
    "$ROOTFS_MAIN"

sudo chown root:root \
    "$ROOTFS_MAIN"

sudo chmod 0644 \
    "$ROOTFS_MAIN"

sudo rm -rf \
    "$ROOTFS/usr/lib/niveth/apps/niveth-files/__pycache__"

echo "[PASS] ISO rootfs synchronized"
echo

echo "=== 6. VERIFY HOST + ROOTFS ==="

grep -q \
    "NIVETH EXECUTABLE PERMISSION SUPPORT v1" \
    "$HOST_MAIN"

sudo grep -q \
    "NIVETH EXECUTABLE PERMISSION SUPPORT v1" \
    "$ROOTFS_MAIN"

grep -q \
    "Make Executable" \
    "$HOST_MAIN"

sudo grep -q \
    "Make Executable" \
    "$ROOTFS_MAIN"

grep -q \
    "Remove Execute Permission" \
    "$HOST_MAIN"

sudo grep -q \
    "Remove Execute Permission" \
    "$ROOTFS_MAIN"

echo "[PASS] Host verified"
echo "[PASS] Rootfs verified"
echo

echo "============================================================"
echo "[DONE] Niveth Files executable context menu installed."
echo "============================================================"
echo
echo "Normal file:"
echo "  Make Executable"
echo
echo "Executable file:"
echo "  Remove Execute Permission"
echo
echo "Ubuntu host + ISO rootfs synchronized."
