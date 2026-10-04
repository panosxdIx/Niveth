#!/usr/bin/env bash

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

SOURCE_MAIN="$HOME/Niveth-Files/main.py"

ROOTFS="$PROJECT_ROOT/build/rootfs"
ROOTFS_MAIN="$ROOTFS/usr/lib/niveth/apps/niveth-files/main.py"

BACKUP_ROOT="$PROJECT_ROOT/integration-backups"

echo "============================================================"
echo "       NIVETH FILES ARCHIVE SUPPORT - FINAL FIX"
echo "============================================================"
echo

if [ ! -f "$SOURCE_MAIN" ]; then
    echo "[ERROR] Source Niveth Files missing:"
    echo "        $SOURCE_MAIN"
    exit 1
fi

if [ ! -f "$ROOTFS_MAIN" ]; then
    echo "[ERROR] Rootfs Niveth Files missing:"
    echo "        $ROOTFS_MAIN"
    exit 1
fi

echo "=== 1. FIND LAST GOOD BACKUP ==="

BACKUP_DIR="$(
    find "$BACKUP_ROOT" \
        -maxdepth 1 \
        -type d \
        -name 'niveth-files-archive-final-*' \
        -print \
        2>/dev/null \
    | sort \
    | tail -n 1
)"

if [ -z "$BACKUP_DIR" ]; then
    echo "[ERROR] Archive patch backup not found."
    exit 1
fi

if [ ! -f "$BACKUP_DIR/source-main.py.before" ]; then
    echo "[ERROR] Source backup missing:"
    echo "        $BACKUP_DIR/source-main.py.before"
    exit 1
fi

if [ ! -f "$BACKUP_DIR/rootfs-main.py.before" ]; then
    echo "[ERROR] Rootfs backup missing:"
    echo "        $BACKUP_DIR/rootfs-main.py.before"
    exit 1
fi

echo "[PASS] Backup:"
echo "       $BACKUP_DIR"

echo
echo "=== 2. RESTORE GOOD VERSION ==="

cp "$BACKUP_DIR/source-main.py.before" \
   "$SOURCE_MAIN"

sudo cp "$BACKUP_DIR/rootfs-main.py.before" \
    "$ROOTFS_MAIN"

sudo chown root:root "$ROOTFS_MAIN"
sudo chmod 0644 "$ROOTFS_MAIN"

echo "[PASS] Source restored"
echo "[PASS] Rootfs restored"

echo
echo "=== 3. VERIFY RESTORED SOURCE ==="

python3 -m py_compile "$SOURCE_MAIN"

echo "[PASS] Source syntax before archive patch"

echo
echo "=== 4. ADD ARCHIVE METHODS ==="

python3 - "$SOURCE_MAIN" <<'PY'
from pathlib import Path
import re
import sys

path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")

if "NIVETH ARCHIVE SUPPORT v4" in text:
    print("[PASS] Archive support v4 already exists.")
    raise SystemExit(0)

methods = r'''
    # =========================================================
    # NIVETH ARCHIVE SUPPORT v4
    # =========================================================

    def _is_archive_file(
        self,
        path,
    ):
        name = os.path.basename(
            path
        ).lower()

        suffixes = (
            ".zip",
            ".7z",
            ".rar",
            ".tar",
            ".tar.gz",
            ".tgz",
            ".tar.bz2",
            ".tbz",
            ".tbz2",
            ".tar.xz",
            ".txz",
            ".tar.zst",
            ".tzst",
            ".tar.lz",
            ".tlz",
            ".tar.lz4",
            ".tar.lzma",
            ".cab",
            ".arj",
            ".lha",
            ".lzh",
            ".jar",
            ".war",
            ".ear",
            ".cpio",
            ".iso",
            ".gz",
            ".bz2",
            ".xz",
            ".zst",
            ".lz",
            ".lz4",
            ".lzma",
        )

        return any(
            name.endswith(
                suffix
            )
            for suffix in suffixes
        )

    def _archive_manager(
        self,
        args,
    ):
        binary = "/usr/bin/file-roller"

        if not os.path.isfile(
            binary
        ):
            self._show_message(
                "Archive Manager is not installed."
            )
            return

        try:
            subprocess.Popen(
                [
                    binary,
                    *args,
                ],
                cwd=self.current_path,
                start_new_session=True,
                stdin=subprocess.DEVNULL,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
            )

        except Exception as exc:
            self._show_message(
                "Could not start Archive Manager:\n"
                f"{exc}"
            )

    def _extract_here(
        self,
        *_args,
    ):
        if len(
            self.selected_paths
        ) != 1:
            return

        path = self.selected_paths[0]

        if (
            not os.path.isfile(path)
            or not self._is_archive_file(
                path
            )
        ):
            return

        self._archive_manager(
            [
                "--extract-here",
                path,
            ]
        )

    def _extract_to(
        self,
        *_args,
    ):
        if len(
            self.selected_paths
        ) != 1:
            return

        path = self.selected_paths[0]

        if (
            not os.path.isfile(path)
            or not self._is_archive_file(
                path
            )
        ):
            return

        self._archive_manager(
            [
                "--extract",
                path,
            ]
        )

    def _compress_selected(
        self,
        *_args,
    ):
        paths = [
            os.path.abspath(path)
            for path in self.selected_paths
            if os.path.exists(path)
        ]

        if not paths:
            return

        self._archive_manager(
            [
                "--add",
                *paths,
            ]
        )

    def _rar_available(
        self,
    ):
        return (
            os.path.isfile(
                "/usr/bin/rar"
            )
            and os.access(
                "/usr/bin/rar",
                os.X_OK,
            )
        )

    def _compress_rar(
        self,
        *_args,
    ):
        if not self._rar_available():
            self._show_message(
                "True RAR creation is not installed.\n\n"
                "RAR/WinRAR archives can still be extracted.\n"
                "Install the official RAR for Linux package "
                "to create real .rar archives."
            )
            return

        paths = [
            os.path.abspath(path)
            for path in self.selected_paths
            if os.path.exists(path)
        ]

        if not paths:
            return

        archive_path = os.path.join(
            self.current_path,
            "archive.rar",
        )

        try:
            subprocess.Popen(
                [
                    "/usr/bin/rar",
                    "a",
                    "-idq",
                    archive_path,
                    *paths,
                ],
                cwd=self.current_path,
                start_new_session=True,
                stdin=subprocess.DEVNULL,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
            )

        except Exception as exc:
            self._show_message(
                "Could not create RAR archive:\n"
                f"{exc}"
            )

'''

anchor = re.search(
    r'(?m)^    def _context_open\(',
    text,
)

if not anchor:
    raise SystemExit(
        "ERROR: Could not find _context_open() method."
    )

text = (
    text[:anchor.start()]
    + methods
    + "\n"
    + text[anchor.start():]
)

path.write_text(
    text,
    encoding="utf-8",
)
PY

echo "[PASS] Archive methods inserted"

echo
echo "=== 5. ADD ARCHIVE ITEMS TO CONTEXT MENU ==="

python3 - "$SOURCE_MAIN" <<'PY'
from pathlib import Path
import re
import sys

path = Path(sys.argv[1])
text = path.read_text(
    encoding="utf-8"
)

menu_match = re.search(
    r'(?ms)^    def _show_item_context_menu\(.*?(?=^    def |\Z)',
    text,
)

if not menu_match:
    raise SystemExit(
        "ERROR: _show_item_context_menu() not found."
    )

menu = menu_match.group(0)

if "Extract Here" in menu:
    print(
        "[PASS] Archive menu already exists."
    )
    raise SystemExit(0)

rename_pos = menu.find(
    '"Rename"'
)

if rename_pos < 0:
    raise SystemExit(
        "ERROR: Rename entry not found in context menu."
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

archive_menu = '''        archive_selected = (
            count > 0
        )

        archive_extract_enabled = (
            single
            and os.path.isfile(
                self.selected_paths[0]
            )
            and self._is_archive_file(
                self.selected_paths[0]
            )
        )

        if archive_extract_enabled:
            self._context_item(
                content,
                "Extract Here",
                "package-x-generic-symbolic",
                self._extract_here,
                enabled=True,
            )

            self._context_item(
                content,
                "Extract To...",
                "folder-open-symbolic",
                self._extract_to,
                enabled=True,
            )

            self._context_separator(
                content
            )

        self._context_item(
            content,
            "Compress...",
            "package-x-generic-symbolic",
            self._compress_selected,
            enabled=archive_selected,
        )

        if archive_selected and self._rar_available():
            self._context_item(
                content,
                "Create RAR",
                "package-x-generic-symbolic",
                self._compress_rar,
                enabled=True,
            )

        self._context_separator(
            content
        )

'''

menu = (
    menu[:rename_start]
    + archive_menu
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
PY

echo "[PASS] Archive context menu inserted"

echo
echo "=== 6. PYTHON VALIDATION ==="

python3 -m py_compile "$SOURCE_MAIN"

echo "[PASS] Source Python syntax"

echo
echo "=== 7. SYNC HOST APP ==="

HOST_DIR="/usr/lib/niveth/apps/niveth-files"

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

echo "[PASS] Host Niveth Files synchronized"

echo
echo "=== 8. SYNC ROOTFS ==="

sudo cp "$SOURCE_MAIN" \
    "$ROOTFS_MAIN"

sudo chown root:root "$ROOTFS_MAIN"
sudo chmod 0644 "$ROOTFS_MAIN"

sudo rm -rf \
    "$ROOTFS/usr/lib/niveth/apps/niveth-files/__pycache__"

echo "[PASS] Rootfs Niveth Files synchronized"

echo
echo "=== 9. VERIFY ARCHIVE FEATURE ==="

for marker in \
    "NIVETH ARCHIVE SUPPORT v4" \
    "Extract Here" \
    "Extract To..." \
    "Compress..." \
    "_rar_available" \
    "_compress_rar"
do
    grep -q "$marker" "$SOURCE_MAIN"
    sudo grep -q "$marker" "$ROOTFS_MAIN"

    echo "[PASS] $marker"
done

echo
echo "=== 10. VERIFY ARCHIVE TOOLS ==="

for cmd in \
    file-roller \
    7z \
    zip \
    unzip \
    tar \
    gzip \
    bzip2 \
    xz \
    zstd
do
    if command -v "$cmd" >/dev/null 2>&1; then
        echo "[PASS] Host: $cmd"
    else
        echo "[FAIL] Host: $cmd"
        exit 1
    fi
done

echo
echo "=== 11. VERIFY ROOTFS TOOLS ==="

sudo chroot "$ROOTFS" /bin/bash -c '
    for cmd in \
        file-roller \
        7z \
        zip \
        unzip \
        tar \
        gzip \
        bzip2 \
        xz \
        zstd
    do
        command -v "$cmd" >/dev/null 2>&1 || exit 1
        echo "[PASS] Rootfs: $cmd"
    done
'

echo
echo "=== 12. RAR STATUS ==="

if command -v rar >/dev/null 2>&1; then
    echo "[PASS] Host true RAR creation available"
else
    echo "[INFO] Host true RAR creation not installed"
    echo "       RAR/WinRAR extraction is available."
fi

echo
echo "============================================================"
echo "[DONE] Niveth Files archive support installed successfully."
echo "============================================================"
echo
echo "Context menu:"
echo "  Extract Here"
echo "  Extract To..."
echo "  Compress..."
echo "  Create RAR  (when /usr/bin/rar exists)"
echo
echo "Host + ISO rootfs synchronized."
