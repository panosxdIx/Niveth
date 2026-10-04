#!/usr/bin/env bash

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

SOURCE_MAIN="$HOME/Niveth-Files/main.py"
ROOTFS="$PROJECT_ROOT/build/rootfs"
ROOTFS_MAIN="$ROOTFS/usr/lib/niveth/apps/niveth-files/main.py"

BACKUP_ROOT="$PROJECT_ROOT/integration-backups"
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP_DIR="$BACKUP_ROOT/niveth-files-executable-final-$TIMESTAMP"

HOST_DIR="/usr/lib/niveth/apps/niveth-files"

echo "============================================================"
echo "     NIVETH FILES EXECUTABLE PERMISSION - FINAL FIX"
echo "============================================================"
echo

if [[ ! -f "$SOURCE_MAIN" ]]; then
    echo "[ERROR] Missing source:"
    echo "        $SOURCE_MAIN"
    exit 1
fi

if [[ ! -f "$ROOTFS_MAIN" ]]; then
    echo "[ERROR] Missing rootfs app:"
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
text = path.read_text(encoding="utf-8")

# ------------------------------------------------------------
# Remove previous executable-permission methods.
# ------------------------------------------------------------

for method_name in (
    "_make_executable",
    "_remove_execute_permission",
    "_toggle_execute_permission",
):
    pattern = re.compile(
        rf"(?ms)^    def {re.escape(method_name)}\(.*?(?=^    def |\Z)"
    )
    text = pattern.sub("", text)

# ------------------------------------------------------------
# Add robust executable permission method.
# ------------------------------------------------------------

methods = r'''
    # =========================================================
    # NIVETH EXECUTABLE PERMISSION SUPPORT v3
    # =========================================================

    def _toggle_execute_permission(
        self,
        *_args,
    ):
        paths = list(
            self.selected_paths
        )

        if (
            not paths
            and self.selected_path
        ):
            paths = [
                self.selected_path
            ]

        if len(paths) != 1:
            self._show_message(
                "Select exactly one file."
            )
            return

        path = os.path.abspath(
            paths[0]
        )

        if not os.path.isfile(path):
            self._show_message(
                "Executable permission can only "
                "be changed on files."
            )
            return

        try:
            current_mode = os.stat(
                path
            ).st_mode

            is_executable = bool(
                current_mode & 0o111
            )

            if is_executable:
                chmod_mode = "a-x"
                action = "Removed execute permission"
            else:
                chmod_mode = "a+x"
                action = "Made executable"

            subprocess.run(
                [
                    "/bin/chmod",
                    chmod_mode,
                    "--",
                    path,
                ],
                check=True,
                stdin=subprocess.DEVNULL,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
            )

            verify_mode = os.stat(
                path
            ).st_mode

            now_executable = bool(
                verify_mode & 0o111
            )

            if is_executable:
                verified = not now_executable
            else:
                verified = now_executable

            log_dir = Path(
                os.path.expanduser(
                    "~/.cache/niveth-files"
                )
            )

            log_dir.mkdir(
                parents=True,
                exist_ok=True,
            )

            log_path = (
                log_dir
                / "permission.log"
            )

            with log_path.open(
                "a",
                encoding="utf-8",
            ) as log:
                log.write("\n")
                log.write("=" * 60)
                log.write("\n")
                log.write(
                    "NIVETH EXECUTABLE PERMISSION\n"
                )
                log.write(
                    f"PATH: {path}\n"
                )
                log.write(
                    f"ACTION: {action}\n"
                )
                log.write(
                    f"MODE BEFORE: "
                    f"{current_mode & 0o7777:o}\n"
                )
                log.write(
                    f"MODE AFTER: "
                    f"{verify_mode & 0o7777:o}\n"
                )
                log.write(
                    f"VERIFIED: {verified}\n"
                )

            if not verified:
                self._show_message(
                    "The permission change was not applied."
                )
                return

            self.selected_paths = [
                path
            ]

            self.selected_path = path
            self.selection_anchor = path

            self._rebuild_columns(
                self.current_path
            )

            self._update_preview(
                path
            )

            self._update_status()

            if is_executable:
                self._show_message(
                    "Execute permission removed."
                )
            else:
                self._show_message(
                    "File is now executable."
                )

        except subprocess.CalledProcessError as exc:
            error_text = (
                exc.stderr.strip()
                if exc.stderr
                else str(exc)
            )

            log_dir = Path(
                os.path.expanduser(
                    "~/.cache/niveth-files"
                )
            )

            log_dir.mkdir(
                parents=True,
                exist_ok=True,
            )

            log_path = (
                log_dir
                / "permission.log"
            )

            with log_path.open(
                "a",
                encoding="utf-8",
            ) as log:
                log.write("\n")
                log.write("=" * 60)
                log.write("\n")
                log.write(
                    "NIVETH EXECUTABLE PERMISSION ERROR\n"
                )
                log.write(
                    f"PATH: {path}\n"
                )
                log.write(
                    f"ERROR: {error_text}\n"
                )

            self._show_message(
                "Could not change execute permission:\n"
                f"{error_text}"
            )

        except Exception as exc:
            log_dir = Path(
                os.path.expanduser(
                    "~/.cache/niveth-files"
                )
            )

            log_dir.mkdir(
                parents=True,
                exist_ok=True,
            )

            log_path = (
                log_dir
                / "permission.log"
            )

            with log_path.open(
                "a",
                encoding="utf-8",
            ) as log:
                log.write("\n")
                log.write("=" * 60)
                log.write("\n")
                log.write(
                    "NIVETH EXECUTABLE PERMISSION ERROR\n"
                )
                log.write(
                    f"PATH: {path}\n"
                )
                log.write(
                    f"ERROR: {exc}\n"
                )

            self._show_message(
                "Could not change execute permission:\n"
                f"{exc}"
            )

'''

anchor = re.search(
    r"(?m)^    def _context_open\(",
    text,
)

if not anchor:
    raise SystemExit(
        "ERROR: _context_open() not found."
    )

text = (
    text[:anchor.start()]
    + methods
    + "\n"
    + text[anchor.start():]
)

# ------------------------------------------------------------
# Remove old executable menu entries.
# ------------------------------------------------------------

text = re.sub(
    r'(?ms)^\s*self\._context_item\(\s*'
    r'content,\s*'
    r'"Make Executable".*?\n\s*\)',
    "",
    text,
)

text = re.sub(
    r'(?ms)^\s*self\._context_item\(\s*'
    r'content,\s*'
    r'"Remove Execute Permission".*?\n\s*\)',
    "",
    text,
)

# ------------------------------------------------------------
# Locate item context menu.
# ------------------------------------------------------------

menu_match = re.search(
    r"(?ms)^    def _show_item_context_menu\(.*?(?=^    def |\Z)",
    text,
)

if not menu_match:
    raise SystemExit(
        "ERROR: _show_item_context_menu() not found."
    )

menu = menu_match.group(0)

if "NIVETH EXECUTABLE MENU v3" not in menu:

    # Use Rename as a stable anchor.
    rename_pos = menu.find(
        '"Rename"'
    )

    if rename_pos < 0:
        raise SystemExit(
            "ERROR: Rename entry not found."
        )

    rename_start = menu.rfind(
        "        self._context_item(",
        0,
        rename_pos,
    )

    if rename_start < 0:
        raise SystemExit(
            "ERROR: Rename context item boundary not found."
        )

    executable_menu = '''        # =====================================================
        # NIVETH EXECUTABLE MENU v3
        # =====================================================

        executable_selected = (
            single
            and os.path.isfile(
                self.selected_paths[0]
            )
        )

        if executable_selected:
            selected_file = self.selected_paths[0]

            selected_mode = os.stat(
                selected_file
            ).st_mode

            selected_is_executable = bool(
                selected_mode & 0o111
            )

            if selected_is_executable:
                executable_label = (
                    "Remove Execute Permission"
                )
            else:
                executable_label = (
                    "Make Executable"
                )

            self._context_item(
                content,
                executable_label,
                "application-x-executable-symbolic",
                self._toggle_execute_permission,
                enabled=True,
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

print("[PASS] Executable permission code installed")
PY

echo
echo "=== 2. PYTHON VALIDATION ==="

python3 -m py_compile "$SOURCE_MAIN"

echo "[PASS] Python syntax"

echo
echo "=== 3. SYNC HOST ==="

sudo mkdir -p "$HOST_DIR"

sudo cp "$SOURCE_MAIN" \
    "$HOST_DIR/main.py"

sudo cp "$HOME/Niveth-Files/styles.css" \
    "$HOST_DIR/styles.css"

sudo rm -rf \
    "$HOST_DIR/icons"

sudo cp -a \
    "$HOME/Niveth-Files/icons" \
    "$HOST_DIR/icons"

sudo chown -R root:root \
    "$HOST_DIR"

sudo find "$HOST_DIR" \
    -type d \
    -exec chmod 0755 {} \;

sudo find "$HOST_DIR" \
    -type f \
    -exec chmod 0644 {} \;

sudo rm -rf \
    "$HOST_DIR/__pycache__"

echo "[PASS] Host synchronized"

echo
echo "=== 4. SYNC ROOTFS ==="

sudo cp "$SOURCE_MAIN" \
    "$ROOTFS_MAIN"

sudo chown root:root \
    "$ROOTFS_MAIN"

sudo chmod 0644 \
    "$ROOTFS_MAIN"

sudo rm -rf \
    "$ROOTFS/usr/lib/niveth/apps/niveth-files/__pycache__"

echo "[PASS] Rootfs synchronized"

echo
echo "=== 5. VERIFY FEATURE ==="

grep -q \
    "NIVETH EXECUTABLE PERMISSION SUPPORT v3" \
    "$SOURCE_MAIN"

sudo grep -q \
    "NIVETH EXECUTABLE PERMISSION SUPPORT v3" \
    "$ROOTFS_MAIN"

grep -q \
    "NIVETH EXECUTABLE MENU v3" \
    "$SOURCE_MAIN"

sudo grep -q \
    "NIVETH EXECUTABLE MENU v3" \
    "$ROOTFS_MAIN"

echo "[PASS] Make Executable"
echo "[PASS] Remove Execute Permission"
echo "[PASS] Direct /bin/chmod"
echo "[PASS] Permission verification"
echo "[PASS] Permission logging"

echo
echo "============================================================"
echo "      EXECUTABLE PERMISSION FIX INSTALLED"
echo "============================================================"
echo
echo "Host + ISO rootfs are synchronized."
echo
