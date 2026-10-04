#!/usr/bin/env bash

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

SOURCE_MAIN="$HOME/Niveth-Files/main.py"
ROOTFS="$PROJECT_ROOT/build/rootfs"
ROOTFS_MAIN="$ROOTFS/usr/lib/niveth/apps/niveth-files/main.py"

BACKUP_DIR="$PROJECT_ROOT/integration-backups/niveth-files-archive-final-$(date +%Y%m%d-%H%M%S)"

echo "============================================================"
echo "       NIVETH FILES ARCHIVE MENU PATCH"
echo "============================================================"
echo

if [ ! -f "$SOURCE_MAIN" ]; then
    echo "[ERROR] Source file missing:"
    echo "        $SOURCE_MAIN"
    exit 1
fi

if [ ! -f "$ROOTFS_MAIN" ]; then
    echo "[ERROR] Rootfs file missing:"
    echo "        $ROOTFS_MAIN"
    exit 1
fi

mkdir -p "$BACKUP_DIR"

cp "$SOURCE_MAIN" \
   "$BACKUP_DIR/source-main.py.before"

sudo cp "$ROOTFS_MAIN" \
    "$BACKUP_DIR/rootfs-main.py.before"

echo "[PASS] Backups created:"
echo "       $BACKUP_DIR"

python3 - "$SOURCE_MAIN" <<'PY'
from pathlib import Path
import re
import sys

path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")

if "NIVETH ARCHIVE SUPPORT v3" in text:
    print("[PASS] Archive support already present.")
    raise SystemExit(0)

archive_methods = r'''
    # =========================================================
    # NIVETH ARCHIVE SUPPORT v3
    # =========================================================

    def _is_archive_file(
        self,
        path,
    ):
        name = os.path.basename(path).lower()

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
            name.endswith(suffix)
            for suffix in suffixes
        )

    def _archive_manager(
        self,
        args,
    ):
        binary = "/usr/bin/file-roller"

        if not os.path.exists(binary):
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
                f"Could not start Archive Manager:\n{exc}"
            )

    def _extract_here(
        self,
        *_args,
    ):
        if len(self.selected_paths) != 1:
            return

        path = self.selected_paths[0]

        if (
            not os.path.isfile(path)
            or not self._is_archive_file(path)
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
        if len(self.selected_paths) != 1:
            return

        path = self.selected_paths[0]

        if (
            not os.path.isfile(path)
            or not self._is_archive_file(path)
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
            os.path.isfile("/usr/bin/rar")
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
                "Niveth can extract WinRAR/RAR files by default.\n"
                "Install the official RAR for Linux package to "
                "create real .rar archives."
            )
            return

        paths = [
            os.path.abspath(path)
            for path in self.selected_paths
            if os.path.exists(path)
        ]

        if not paths:
            return

        name = "archive.rar"

        command = [
            "/usr/bin/rar",
            "a",
            "-idq",
            name,
            *paths,
        ]

        try:
            subprocess.Popen(
                command,
                cwd=self.current_path,
                start_new_session=True,
                stdin=subprocess.DEVNULL,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
            )

        except Exception as exc:
            self._show_message(
                f"Could not create RAR archive:\n{exc}"
            )

'''

# ------------------------------------------------------------
# Insert archive methods before _context_open()
# ------------------------------------------------------------

anchor = re.search(
    r'(?m)^    def _context_open\b[^\n]*:\n',
    text,
)

if not anchor:
    raise SystemExit(
        "ERROR: Could not find _context_open() in current Niveth Files."
    )

text = (
    text[:anchor.start()]
    + archive_methods
    + "\n"
    + text[anchor.start():]
)

# ------------------------------------------------------------
# Add archive menu entries immediately before Rename
# ------------------------------------------------------------

rename_pattern = re.compile(
    r'''
        (?P<indent>        )
        self\._context_item\(
            \s*content,
            \s*"Rename",
            .*?
        \)
''',
    re.VERBOSE | re.DOTALL,
)

rename_match = rename_pattern.search(text)

if not rename_match:
    raise SystemExit(
        "ERROR: Could not find Rename context-menu entry."
    )

insert = '''        archive_selected = (
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

text = (
    text[:rename_match.start()]
    + insert
    + text[rename_match.start():]
)

path.write_text(
    text,
    encoding="utf-8",
)
PY

echo "[PASS] Source archive menu patched"

echo
echo "=== PYTHON CHECK ==="

python3 -m py_compile "$SOURCE_MAIN"

echo "[PASS] Source syntax"

echo
echo "=== SYNC HOST ==="

HOST_DIR="/usr/lib/niveth/apps/niveth-files"

sudo mkdir -p "$HOST_DIR"

sudo cp "$SOURCE_MAIN" \
    "$HOST_DIR/main.py"

sudo cp "$HOME/Niveth-Files/styles.css" \
    "$HOST_DIR/styles.css"

sudo rm -rf "$HOST_DIR/icons"

sudo cp -a \
    "$HOME/Niveth-Files/icons" \
    "$HOST_DIR/icons"

sudo chown -R root:root "$HOST_DIR"

sudo find "$HOST_DIR" \
    -type d \
    -exec chmod 0755 {} \;

sudo find "$HOST_DIR" \
    -type f \
    -exec chmod 0644 {} \;

sudo rm -rf "$HOST_DIR/__pycache__"

echo "[PASS] Host Niveth Files synchronized"

echo
echo "=== SYNC ROOTFS ==="

sudo cp "$SOURCE_MAIN" \
    "$ROOTFS_MAIN"

sudo chown root:root "$ROOTFS_MAIN"
sudo chmod 0644 "$ROOTFS_MAIN"

sudo rm -rf \
    "$ROOTFS/usr/lib/niveth/apps/niveth-files/__pycache__"

echo "[PASS] Rootfs Niveth Files synchronized"

echo
echo "=== VERIFY FEATURES ==="

for marker in \
    "NIVETH ARCHIVE SUPPORT v3" \
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
echo "=== VERIFY HOST TOOLS ==="

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
        echo "[PASS] $cmd"
    else
        echo "[FAIL] $cmd"
        exit 1
    fi
done

echo
echo "=== RAR ==="

if command -v rar >/dev/null 2>&1; then
    echo "[PASS] True RAR creation available"
else
    echo "[INFO] True RAR creation not installed"
    echo "       WinRAR/RAR extraction is available."
fi

echo
echo "============================================================"
echo "[DONE] Niveth Files archive support is installed."
echo "============================================================"
echo
echo "Context menu:"
echo "  Extract Here"
echo "  Extract To..."
echo "  Compress..."
echo "  Create RAR  (when official rar exists)"
echo
echo "Ubuntu host + ISO rootfs synchronized."
