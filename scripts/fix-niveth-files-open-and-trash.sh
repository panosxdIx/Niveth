#!/usr/bin/env bash

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

SOURCE_MAIN="$HOME/Niveth-Files/main.py"
HOST_MAIN="/usr/lib/niveth/apps/niveth-files/main.py"

ROOTFS="$PROJECT_ROOT/build/rootfs"
ROOTFS_MAIN="$ROOTFS/usr/lib/niveth/apps/niveth-files/main.py"

BACKUP_ROOT="$PROJECT_ROOT/integration-backups"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP_DIR="$BACKUP_ROOT/niveth-files-open-trash-$STAMP"

echo "============================================================"
echo "       NIVETH FILES - OPEN + TRASH FIX"
echo "============================================================"
echo

if [ ! -f "$SOURCE_MAIN" ]; then
    echo "[ERROR] Source missing:"
    echo "        $SOURCE_MAIN"
    exit 1
fi

if [ ! -f "$ROOTFS_MAIN" ]; then
    echo "[ERROR] Rootfs app missing:"
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

python3 - "$SOURCE_MAIN" <<'PY'
from pathlib import Path
import re
import sys

path = Path(sys.argv[1])

text = path.read_text(
    encoding="utf-8"
)

# =========================================================
# 1. ADD TRASH PATH CONSTANT
# =========================================================

if "NIVETH_TRASH_FILES" not in text:

    marker = 'TAG_DATA_FILE = TAG_DATA_DIR / "tags.json"\n'

    if marker not in text:
        raise SystemExit(
            "ERROR: TAG_DATA_FILE marker not found."
        )

    insertion = '''
NIVETH_TRASH_FILES = Path(
    os.path.expanduser(
        "~/.local/share/Trash/files"
    )
)

'''

    text = text.replace(
        marker,
        marker + insertion,
        1,
    )

# =========================================================
# 2. REPLACE _open_file()
# =========================================================

open_match = re.search(
    r"(?ms)^    def _open_file\(\s*$.*?(?=^    def _file_icon\(\s*$)",
    text,
)

if not open_match:
    raise SystemExit(
        "ERROR: _open_file() not found."
    )

new_open = r'''    # =========================================================
    # FILES
    # =========================================================

    def _open_file(
        self,
        path,
    ):
        """
        Open normal files through the default handler.

        Executable files are launched directly.

        Launch stdout/stderr are written to:
            ~/.cache/niveth-files/launch.log
        """

        path = os.path.abspath(
            os.path.expanduser(path)
        )

        if not os.path.isfile(path):
            return

        try:

            suffix = Path(
                path
            ).suffix.lower()

            # -------------------------------------------------
            # Executable
            # -------------------------------------------------

            if (
                suffix != ".desktop"
                and os.access(
                    path,
                    os.X_OK,
                )
            ):

                log_dir = Path(
                    os.path.expanduser(
                        "~/.cache/niveth-files"
                    )
                )

                log_dir.mkdir(
                    parents=True,
                    exist_ok=True,
                )

                log_file = (
                    log_dir
                    / "launch.log"
                )

                environment = os.environ.copy()

                with log_file.open(
                    "a",
                    encoding="utf-8",
                ) as output:

                    output.write(
                        "\n"
                        "=================================================\n"
                    )

                    output.write(
                        "NIVETH EXECUTABLE LAUNCH\n"
                    )

                    output.write(
                        f"PATH: {path}\n"
                    )

                    output.write(
                        f"TIME: {__import__('datetime').datetime.now().isoformat()}\n"
                    )

                    output.write(
                        "=================================================\n"
                    )

                    output.flush()

                    process = subprocess.Popen(
                        [path],
                        cwd=os.path.dirname(path) or None,
                        env=environment,
                        stdin=subprocess.DEVNULL,
                        stdout=output,
                        stderr=output,
                        start_new_session=True,
                    )

                print(
                    "NIVETH: Launched executable: "
                    f"{path} "
                    f"(PID {process.pid})"
                )

                return

            # -------------------------------------------------
            # .desktop
            # -------------------------------------------------

            if suffix == ".desktop":

                desktop_file = Gio.File.new_for_path(
                    path
                )

                Gio.AppInfo.launch_default_for_uri(
                    desktop_file.get_uri(),
                    None,
                )

                return

            # -------------------------------------------------
            # Normal files
            # -------------------------------------------------

            file = Gio.File.new_for_path(
                path
            )

            Gio.AppInfo.launch_default_for_uri(
                file.get_uri(),
                None,
            )

        except Exception as exc:

            print(
                "NIVETH: Could not open "
                f"{path}: {exc}"
            )

    # =========================================================
'''

text = (
    text[:open_match.start()]
    + new_open
    + text[open_match.end():]
)

# =========================================================
# 3. REPLACE _navigate_to()
# =========================================================

navigate_match = re.search(
    r"(?ms)^    def _navigate_to\(\s*$.*?(?=^    def _go_back\(\s*$)",
    text,
)

if not navigate_match:
    raise SystemExit(
        "ERROR: _navigate_to() not found."
    )

new_navigate = r'''    # =========================================================
    # NAVIGATION
    # =========================================================

    def _navigate_to(
        self,
        path,
        add_history=True,
    ):

        # -----------------------------------------------------
        # Niveth Trash
        # -----------------------------------------------------

        if (
            isinstance(
                path,
                str,
            )
            and path.startswith(
                "trash://"
            )
        ):

            try:

                NIVETH_TRASH_FILES.mkdir(
                    parents=True,
                    exist_ok=True,
                )

            except Exception as exc:

                print(
                    "NIVETH: Could not prepare Trash: "
                    f"{exc}"
                )

                return

            path = str(
                NIVETH_TRASH_FILES
            )

        # -----------------------------------------------------
        # Normal filesystem path
        # -----------------------------------------------------

        path = os.path.abspath(
            os.path.expanduser(
                path
            )
        )

        if not os.path.isdir(path):
            return

        if add_history:

            if (
                not self.history
                or self.history[
                    self.history_index
                ] != path
            ):

                self.history = (
                    self.history[
                        :self.history_index + 1
                    ]
                    + [path]
                )

                self.history_index = (
                    len(self.history) - 1
                )

        self.current_path = path

        self.selected_path = None
        self.selected_paths = []
        self.selection_anchor = None

        self._rebuild_columns(
            path
        )

        self._update_preview(
            None
        )

        self._update_status()

        self._update_navigation_buttons()

    # =========================================================
'''

text = (
    text[:navigate_match.start()]
    + new_navigate
    + text[navigate_match.end():]
)

# =========================================================
# 4. CHANGE SIDEBAR TRASH TARGET
# =========================================================

text = text.replace(
    '"trash:///"',
    'str(NIVETH_TRASH_FILES)',
)

# =========================================================
# 5. ADD MARKER
# =========================================================

if "NIVETH OPEN + TRASH SUPPORT v1" not in text:

    marker_method = (
        "    # =========================================================\n"
        "    # FILES\n"
        "    # =========================================================\n"
    )

    text = text.replace(
        marker_method,
        (
            "    # =========================================================\n"
            "    # NIVETH OPEN + TRASH SUPPORT v1\n"
            "    # =========================================================\n\n"
            + marker_method
        ),
        1,
    )

path.write_text(
    text,
    encoding="utf-8",
)

print(
    "[PASS] Open + Trash support patched."
)
PY

echo
echo "=== 2. PYTHON VALIDATION ==="

python3 -m py_compile \
    "$SOURCE_MAIN"

echo "[PASS] Python syntax"
echo

echo "=== 3. VERIFY SOURCE ==="

grep -q \
    "NIVETH OPEN + TRASH SUPPORT v1" \
    "$SOURCE_MAIN"

grep -q \
    "NIVETH_TRASH_FILES" \
    "$SOURCE_MAIN"

grep -q \
    "NIVETH EXECUTABLE LAUNCH" \
    "$SOURCE_MAIN"

grep -q \
    "start_new_session=True" \
    "$SOURCE_MAIN"

echo "[PASS] Trash path"
echo "[PASS] Executable launcher"
echo "[PASS] Launch log"
echo

echo "=== 4. SYNC HOST ==="

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

echo "=== 5. SYNC ROOTFS ==="

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

echo "=== 6. VERIFY ROOTFS ==="

sudo grep -q \
    "NIVETH OPEN + TRASH SUPPORT v1" \
    "$ROOTFS_MAIN"

sudo grep -q \
    "NIVETH_TRASH_FILES" \
    "$ROOTFS_MAIN"

echo "[PASS] Rootfs verified"
echo

echo "============================================================"
echo "[DONE] Niveth Files Open + Trash support installed."
echo "============================================================"
echo
echo "Executable launch log:"
echo "  ~/.cache/niveth-files/launch.log"
echo
echo "Trash:"
echo "  ~/.local/share/Trash/files"
echo
echo "Host + ISO rootfs synchronized."
