#!/usr/bin/env bash

set -euo pipefail

PROJECT_ROOT="$HOME/Niveth"

SOURCE_MAIN="$HOME/Niveth-Files/main.py"
SOURCE_CSS="$HOME/Niveth-Files/styles.css"

HOST_DIR="/usr/lib/niveth/apps/niveth-files"

ROOTFS="$PROJECT_ROOT/build/rootfs"
ROOTFS_DIR="$ROOTFS/usr/lib/niveth/apps/niveth-files"

BACKUP_DIR="$PROJECT_ROOT/integration-backups/niveth-files-open-header-$(date +%Y%m%d-%H%M%S)"

echo "============================================================"
echo " NIVETH FILES - OPEN + HEADER FIX"
echo "============================================================"
echo

for f in "$SOURCE_MAIN" "$SOURCE_CSS"; do
    if [[ ! -f "$f" ]]; then
        echo "[ERROR] Missing: $f"
        exit 1
    fi
done

if [[ ! -d "$HOST_DIR" ]]; then
    echo "[ERROR] Installed Niveth Files directory not found:"
    echo "        $HOST_DIR"
    exit 1
fi

if [[ ! -d "$ROOTFS_DIR" ]]; then
    echo "[ERROR] Rootfs Niveth Files directory not found:"
    echo "        $ROOTFS_DIR"
    exit 1
fi

mkdir -p "$BACKUP_DIR"

cp "$SOURCE_MAIN" "$BACKUP_DIR/main.py.before"
cp "$SOURCE_CSS" "$BACKUP_DIR/styles.css.before"

sudo cp "$HOST_DIR/main.py" "$BACKUP_DIR/host-main.py.before"
sudo cp "$HOST_DIR/styles.css" "$BACKUP_DIR/host-styles.css.before"

sudo cp "$ROOTFS_DIR/main.py" "$BACKUP_DIR/rootfs-main.py.before"
sudo cp "$ROOTFS_DIR/styles.css" "$BACKUP_DIR/rootfs-styles.css.before"

echo "[PASS] Backups created:"
echo "       $BACKUP_DIR"

echo
echo "=== 1. FIX FILE OPEN ==="

python3 - "$SOURCE_MAIN" <<'PY'
from pathlib import Path
import re
import sys

path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")

start_marker = "    def _open_file(\n"
end_marker = "    def _file_icon(\n"

start = text.find(start_marker)
end = text.find(end_marker, start)

if start == -1:
    raise SystemExit(
        "ERROR: _open_file() not found."
    )

if end == -1:
    raise SystemExit(
        "ERROR: _file_icon() anchor not found."
    )

replacement = '''    def _open_file(
        self,
        path,
    ):

        try:

            file = Gio.File.new_for_path(
                path
            )

            Gio.AppInfo.launch_default_for_uri(
                file.get_uri(),
                None,
            )

        except Exception as exc:

            print(
                f"NIVETH: Could not open {path}: {exc}"
            )

'''

text = (
    text[:start]
    + replacement
    + text[end:]
)

path.write_text(
    text,
    encoding="utf-8",
)

print("[PASS] File opening now uses default application handler.")
PY

echo
echo "=== 2. FIX HEADER THEME ==="

python3 - "$SOURCE_MAIN" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")

if "self._niveth_header = header" not in text:

    old = '''        header = Gtk.HeaderBar()

        header.add_css_class(
            "niveth-header"
        )
'''

    new = '''        header = Gtk.HeaderBar()

        self._niveth_header = header

        header.add_css_class(
            "niveth-header"
        )
'''

    if old not in text:
        raise SystemExit(
            "ERROR: Header creation block not found."
        )

    text = text.replace(
        old,
        new,
        1,
    )

theme_old = '''        if self._dark_mode:
            self.root_widget.add_css_class("dark")
            self.root_widget.remove_css_class("light")
        else:
            self.root_widget.add_css_class("light")
            self.root_widget.remove_css_class("dark")

        self._apply_runtime_theme_css()
'''

theme_new = '''        if self._dark_mode:
            self.root_widget.add_css_class("dark")
            self.root_widget.remove_css_class("light")
        else:
            self.root_widget.add_css_class("light")
            self.root_widget.remove_css_class("dark")

        if hasattr(self, "_niveth_header"):
            self._niveth_header.remove_css_class("dark")
            self._niveth_header.remove_css_class("light")

            if self._dark_mode:
                self._niveth_header.add_css_class("dark")
            else:
                self._niveth_header.add_css_class("light")

        self._apply_runtime_theme_css()
'''

if theme_old in text:
    text = text.replace(
        theme_old,
        theme_new,
        1,
    )
elif (
    'self._niveth_header.add_css_class("dark")'
    not in text
):
    raise SystemExit(
        "ERROR: _apply_theme() block not found."
    )

path.write_text(
    text,
    encoding="utf-8",
)

print("[PASS] Header now receives explicit dark/light theme.")
PY

echo
echo "=== 3. ADD HEADER CSS ==="

if ! grep -q "NIVETH HEADER TITLEBAR FIX" "$SOURCE_CSS"; then

cat >> "$SOURCE_CSS" <<'CSS'

/* ============================================================
   NIVETH HEADER TITLEBAR FIX
   ============================================================ */

.niveth-header.dark {
    background: #101923;
    color: #DCE7F4;
    border-bottom: 1px solid rgba(175, 205, 235, 0.10);
}

.niveth-header.light {
    background: #F6F3EE;
    color: #29415D;
    border-bottom: 1px solid rgba(50, 80, 100, 0.10);
}

.niveth-header.dark .toolbar-button,
.niveth-header.dark .view-button {
    color: #CBD8E7;
}

.niveth-header.light .toolbar-button,
.niveth-header.light .view-button {
    color: #496173;
}

.niveth-header.dark .search {
    background: rgba(255, 255, 255, 0.065);
    color: #EDF4FB;
    border: 1px solid rgba(175, 205, 235, 0.10);
}

.niveth-header.light .search {
    background: #FFFFFF;
    color: #304353;
    border: 1px solid rgba(50, 80, 100, 0.10);
}

.niveth-header.dark .title {
    color: #EDF4FB;
}

.niveth-header.light .title {
    color: #263949;
}

CSS

fi

echo "[PASS] Header CSS ready"

echo
echo "=== 4. SOURCE SYNTAX ==="

python3 -m py_compile "$SOURCE_MAIN"

echo "[PASS] Source syntax"

echo
echo "=== 5. SYNC INSTALLED HOST APP ==="

sudo cp "$SOURCE_MAIN" \
    "$HOST_DIR/main.py"

sudo cp "$SOURCE_CSS" \
    "$HOST_DIR/styles.css"

if [[ -d "$HOME/Niveth-Files/icons" ]]; then
    sudo rm -rf "$HOST_DIR/icons"
    sudo cp -a \
        "$HOME/Niveth-Files/icons" \
        "$HOST_DIR/icons"
fi

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

echo "[PASS] Installed host copy synchronized"

echo
echo "=== 6. SYNC ROOTFS ==="

sudo cp "$SOURCE_MAIN" \
    "$ROOTFS_DIR/main.py"

sudo cp "$SOURCE_CSS" \
    "$ROOTFS_DIR/styles.css"

if [[ -d "$HOME/Niveth-Files/icons" ]]; then
    sudo rm -rf "$ROOTFS_DIR/icons"
    sudo cp -a \
        "$HOME/Niveth-Files/icons" \
        "$ROOTFS_DIR/icons"
fi

sudo chown -R root:root \
    "$ROOTFS_DIR"

sudo find "$ROOTFS_DIR" \
    -type d \
    -exec chmod 0755 {} \;

sudo find "$ROOTFS_DIR" \
    -type f \
    -exec chmod 0644 {} \;

sudo rm -rf \
    "$ROOTFS_DIR/__pycache__"

echo "[PASS] Rootfs copy synchronized"

echo
echo "=== 7. VERIFY HOST ==="

python3 -m py_compile \
    "$HOST_DIR/main.py"

grep -q \
    "Gio.AppInfo.launch_default_for_uri" \
    "$HOST_DIR/main.py"

grep -q \
    "self._niveth_header" \
    "$HOST_DIR/main.py"

grep -q \
    "NIVETH HEADER TITLEBAR FIX" \
    "$HOST_DIR/styles.css"

echo "[PASS] Host app verification"

echo
echo "=== 8. VERIFY ROOTFS ==="

sudo python3 -m py_compile \
    "$ROOTFS_DIR/main.py"

sudo grep -q \
    "Gio.AppInfo.launch_default_for_uri" \
    "$ROOTFS_DIR/main.py"

sudo grep -q \
    "self._niveth_header" \
    "$ROOTFS_DIR/main.py"

sudo grep -q \
    "NIVETH HEADER TITLEBAR FIX" \
    "$ROOTFS_DIR/styles.css"

echo "[PASS] Rootfs verification"

echo
echo "============================================================"
echo " NIVETH FILES OPEN + HEADER FIX: READY"
echo "============================================================"
echo
echo "Default image/file opening : FIXED"
echo "Header dark/light theme    : FIXED"
echo "Dock installed copy        : SYNCHRONIZED"
echo "Rootfs copy                : SYNCHRONIZED"
echo
echo "Backup:"
echo "  $BACKUP_DIR"
echo

