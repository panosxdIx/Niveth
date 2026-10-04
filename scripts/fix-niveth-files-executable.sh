#!/usr/bin/env bash

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

SOURCE_MAIN="$HOME/Niveth-Files/main.py"
HOST_MAIN="/usr/lib/niveth/apps/niveth-files/main.py"

ROOTFS="$PROJECT_ROOT/build/rootfs"
ROOTFS_MAIN="$ROOTFS/usr/lib/niveth/apps/niveth-files/main.py"

BACKUP_ROOT="$PROJECT_ROOT/integration-backups"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP_DIR="$BACKUP_ROOT/niveth-files-executable-fix-$STAMP"

echo "============================================================"
echo "       NIVETH FILES - EXECUTABLE FIX"
echo "============================================================"
echo

mkdir -p "$BACKUP_DIR"

cp "$SOURCE_MAIN" \
    "$BACKUP_DIR/source-main.py.before"

sudo cp "$ROOTFS_MAIN" \
    "$BACKUP_DIR/rootfs-main.py.before"

echo "[PASS] Backup:"
echo "       $BACKUP_DIR"
echo

python3 - "$SOURCE_MAIN" <<'PY'
from pathlib import Path
import re
import sys

path = Path(sys.argv[1])

text = path.read_text(
    encoding="utf-8"
)

# ---------------------------------------------------------
# Replace the executable method if it already exists.
# ---------------------------------------------------------

new_method = r'''
    # =========================================================
    # NIVETH EXECUTABLE PERMISSION SUPPORT v2
    # =========================================================

    def _toggle_executable_permission(
        self,
    ):
        if len(self.selected_paths) != 1:
            return

        path = os.path.abspath(
            self.selected_paths[0]
        )

        if not os.path.isfile(path):
            return

        try:
            if os.access(
                path,
                os.X_OK,
            ):
                subprocess.run(
                    [
                        "/bin/chmod",
                        "a-x",
                        "--",
                        path,
                    ],
                    check=True,
                )

                print(
                    "NIVETH: Removed execute permission: "
                    f"{path}"
                )

            else:
                subprocess.run(
                    [
                        "/bin/chmod",
                        "a+x",
                        "--",
                        path,
                    ],
                    check=True,
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
            subprocess.SubprocessError,
        ) as exc:
            print(
                "NIVETH: Executable permission change failed: "
                f"{path}: {exc}"
            )

'''

# Existing executable method.
method_match = re.search(
    r"(?ms)^    # =========================================================\n"
    r"    # NIVETH EXECUTABLE PERMISSION SUPPORT.*?"
    r"(?=^    def _open_file\(\s*$)",
    text,
)

if method_match:
    text = (
        text[:method_match.start()]
        + new_method
        + text[method_match.end():]
    )
else:
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
        + new_method
        + text[open_match.start():]
    )

# ---------------------------------------------------------
# Make sure the context menu uses the correct action.
# ---------------------------------------------------------

menu_match = re.search(
    r"(?ms)^    def _show_item_context_menu\(.*?(?=^    def |\Z)",
    text,
)

if not menu_match:
    raise SystemExit(
        "ERROR: _show_item_context_menu() not found."
    )

menu = menu_match.group(0)

# Remove previous executable menu block.
menu = re.sub(
    r'(?ms)^        executable_enabled = .*?'
    r'(?=^        self\._context_separator\(\s*content\s*\)\s*$)',
    '',
    menu,
    count=1,
)

executable_block = '''        executable_enabled = (
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

rename_match = re.search(
    r'(?ms)^        self\._context_item\(\s*'
    r'content,\s*'
    r'"Rename".*?\n'
    r'        \)',
    menu,
)

if not rename_match:
    raise SystemExit(
        "ERROR: Rename context item not found."
    )

insert_at = rename_match.end()

menu = (
    menu[:insert_at]
    + "\n"
    + executable_block
    + menu[insert_at:]
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

print("[PASS] Executable support v2 installed.")
PY

echo

echo "=== PYTHON CHECK ==="

python3 -m py_compile \
    "$SOURCE_MAIN"

echo "[PASS] Python syntax"
echo

echo "=== SYNC HOST ==="

sudo cp \
    "$SOURCE_MAIN" \
    "$HOST_MAIN"

sudo chown root:root \
    "$HOST_MAIN"

sudo chmod 0644 \
    "$HOST_MAIN"

sudo rm -rf \
    "/usr/lib/niveth/apps/niveth-files/__pycache__"

echo "[PASS] Host synchronized"
echo

echo "=== SYNC ROOTFS ==="

sudo cp \
    "$SOURCE_MAIN" \
    "$ROOTFS_MAIN"

sudo chown root:root \
    "$ROOTFS_MAIN"

sudo chmod 0644 \
    "$ROOTFS_MAIN"

sudo rm -rf \
    "$ROOTFS/usr/lib/niveth/apps/niveth-files/__pycache__"

echo "[PASS] Rootfs synchronized"
echo

echo "=== VERIFY ==="

grep -q \
    "NIVETH EXECUTABLE PERMISSION SUPPORT v2" \
    "$SOURCE_MAIN"

grep -q \
    '"/bin/chmod"' \
    "$SOURCE_MAIN"

grep -q \
    '"Make Executable"' \
    "$SOURCE_MAIN"

grep -q \
    '"Remove Execute Permission"' \
    "$SOURCE_MAIN"

sudo grep -q \
    "NIVETH EXECUTABLE PERMISSION SUPPORT v2" \
    "$ROOTFS_MAIN"

echo "[PASS] chmod implementation"
echo "[PASS] Make Executable"
echo "[PASS] Remove Execute Permission"
echo "[PASS] Host + rootfs synchronized"
echo

echo "============================================================"
echo "[DONE] Executable permission support fixed."
echo "============================================================"
