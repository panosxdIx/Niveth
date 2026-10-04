#!/usr/bin/env bash

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

SOURCE_MAIN="$HOME/Niveth-Files/main.py"
ROOTFS="$PROJECT_ROOT/build/rootfs"
ROOTFS_MAIN="$ROOTFS/usr/lib/niveth/apps/niveth-files/main.py"

PACKAGE_MANIFEST="$PROJECT_ROOT/packages/support.txt"

BACKUP_ROOT="$PROJECT_ROOT/integration-backups"
BACKUP_DIR="$BACKUP_ROOT/niveth-files-archive-$(date +%Y%m%d-%H%M%S)"

PACKAGES=(
    file-roller
    7zip
    7zip-rar
    zip
    unzip
    tar
    gzip
    bzip2
    xz-utils
    zstd
)

MOUNTED_DEV=0
MOUNTED_DEV_PTS=0
MOUNTED_PROC=0
MOUNTED_SYS=0
MOUNTED_RUN=0

cleanup() {
    echo
    echo "=== ROOTFS CLEANUP ==="

    sudo umount "$ROOTFS/run" 2>/dev/null || true
    sudo umount "$ROOTFS/sys" 2>/dev/null || true
    sudo umount "$ROOTFS/proc" 2>/dev/null || true
    sudo umount "$ROOTFS/dev/pts" 2>/dev/null || true
    sudo umount "$ROOTFS/dev" 2>/dev/null || true
}

trap cleanup EXIT

echo "============================================================"
echo "       NIVETH FILES ARCHIVE SUPPORT"
echo "============================================================"
echo

if [ ! -f "$SOURCE_MAIN" ]; then
    echo "[ERROR] Missing source:"
    echo "        $SOURCE_MAIN"
    exit 1
fi

if [ ! -f "$ROOTFS_MAIN" ]; then
    echo "[ERROR] Missing rootfs app:"
    echo "        $ROOTFS_MAIN"
    exit 1
fi

if [ ! -f "$PACKAGE_MANIFEST" ]; then
    echo "[ERROR] Missing package manifest:"
    echo "        $PACKAGE_MANIFEST"
    exit 1
fi

mkdir -p "$BACKUP_DIR"

cp "$SOURCE_MAIN" \
   "$BACKUP_DIR/source-main.py.before"

sudo cp "$ROOTFS_MAIN" \
    "$BACKUP_DIR/rootfs-main.py.before"

cp "$PACKAGE_MANIFEST" \
   "$BACKUP_DIR/support.txt.before"

echo "[PASS] Backups created"
echo "       $BACKUP_DIR"

echo
echo "=== 1. UPDATE PACKAGE MANIFEST ==="

for package in "${PACKAGES[@]}"; do
    if ! grep -Eq \
        "^[[:space:]]*$package([[:space:]]|$)" \
        "$PACKAGE_MANIFEST"; then

        printf '%s\n' "$package" >> "$PACKAGE_MANIFEST"
        echo "[PASS] Added $package"

    else
        echo "[PASS] $package already present"
    fi
done

echo
echo "=== 2. INSTALL HOST TOOLS ==="

sudo apt-get update

sudo apt-get install -y \
    "${PACKAGES[@]}"

echo "[PASS] Host archive tools installed"

echo
echo "=== 3. MOUNT ROOTFS ==="

sudo mount --bind /dev "$ROOTFS/dev"

sudo mount --bind /dev/pts "$ROOTFS/dev/pts"

sudo mount -t proc proc "$ROOTFS/proc"

sudo mount -t sysfs sysfs "$ROOTFS/sys"

sudo mount --bind /run "$ROOTFS/run"

echo "[PASS] rootfs mounted"

echo
echo "=== 4. INSTALL ROOTFS TOOLS ==="

sudo chroot "$ROOTFS" /bin/bash -c '
    set -e

    export DEBIAN_FRONTEND=noninteractive

    apt-get update

    apt-get install -y \
        file-roller \
        7zip \
        7zip-rar \
        zip \
        unzip \
        tar \
        gzip \
        bzip2 \
        xz-utils \
        zstd
'

echo "[PASS] Rootfs archive tools installed"

echo
echo "=== 5. PATCH Niveth Files ==="

python3 - "$SOURCE_MAIN" <<'PY'
from pathlib import Path
import re
import sys

path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")

if "NIVETH ARCHIVE SUPPORT v2" in text:
    print("[INFO] Archive support already installed.")
    raise SystemExit(0)

archive_methods = r'''
    # =========================================================
    # NIVETH ARCHIVE SUPPORT v2
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

    def _start_file_roller(
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

        self._start_file_roller(
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

        self._start_file_roller(
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

        self._start_file_roller(
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
                "RAR creation is not installed.\n\n"
                "Niveth can extract RAR files by default.\n"
                "To create true WinRAR-compatible .rar files, "
                "install the official RAR for Linux package."
            )
            return

        paths = [
            os.path.abspath(path)
            for path in self.selected_paths
            if os.path.exists(path)
        ]

        if not paths:
            return

        default_name = "archive.rar"

        command = [
            "/usr/bin/rar",
            "a",
            "-idq",
            default_name,
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

anchor = re.search(
    r'(?m)^    def _context_open\(\n',
    text,
)

if not anchor:
    raise SystemExit(
        "ERROR: _context_open() anchor not found."
    )

text = (
    text[:anchor.start()]
    + archive_methods
    + "\n"
    + text[anchor.start():]
)

anchor_pattern = re.compile(
    r'''
        (?P<indent>        )
        self\._context_item\(
            content,\s*"Copy",\s*"edit-copy-symbolic",
            self\._copy_selected,
            enabled=count > 0,
        \)
''',
    re.VERBOSE,
)

match = anchor_pattern.search(text)

if not match:
    raise SystemExit(
        "ERROR: Copy menu item anchor not found."
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
    text[:match.start()]
    + insert
    + text[match.start():]
)

path.write_text(
    text,
    encoding="utf-8",
)
PY

echo "[PASS] Source patched"

echo
echo "=== 6. PYTHON CHECK ==="

python3 -m py_compile "$SOURCE_MAIN"

echo "[PASS] Source syntax"

echo
echo "=== 7. SYNC HOST APP ==="

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

echo "[PASS] Host app synchronized"

echo
echo "=== 8. SYNC ROOTFS APP ==="

sudo cp "$SOURCE_MAIN" \
    "$ROOTFS_MAIN"

sudo chown root:root "$ROOTFS_MAIN"
sudo chmod 0644 "$ROOTFS_MAIN"

sudo rm -rf \
    "$ROOTFS/usr/lib/niveth/apps/niveth-files/__pycache__"

echo "[PASS] Rootfs app synchronized"

echo
echo "=== 9. VERIFY FEATURES ==="

for marker in \
    "NIVETH ARCHIVE SUPPORT v2" \
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
echo "=== 10. VERIFY TOOLS ==="

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
    command -v "$cmd" >/dev/null 2>&1
    echo "[PASS] Host: $cmd"
done

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
        command -v "$cmd" >/dev/null 2>&1
        echo "[PASS] Rootfs: $cmd"
    done
'

echo
echo "=== 11. RAR STATUS ==="

if command -v rar >/dev/null 2>&1; then
    echo "[PASS] Host RAR creation available"
    rar
else
    echo "[INFO] Host RAR creation not installed"
    echo "       RAR extraction remains available through 7zip-rar."
fi

if sudo chroot "$ROOTFS" /bin/bash -c \
    'command -v rar >/dev/null 2>&1'
then
    echo "[PASS] Rootfs RAR creation available"
else
    echo "[INFO] Rootfs RAR creation not bundled"
    echo "       This avoids bundling the proprietary RAR trial binary."
fi

echo
echo "============================================================"
echo "[DONE] Niveth Files archive support installed."
echo "============================================================"
echo
echo "Default:"
echo "  Extract Here"
echo "  Extract To..."
echo "  Compress..."
echo
echo "RAR:"
echo "  RAR extraction       : YES"
echo "  RAR creation         : optional official RAR install"
echo
echo "Ubuntu host + ISO app are synchronized."
