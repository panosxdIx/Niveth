#!/usr/bin/env bash

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

SOURCE_MAIN="$HOME/Niveth-Files/main.py"
HOST_MAIN="/usr/lib/niveth/apps/niveth-files/main.py"

ROOTFS="$PROJECT_ROOT/build/rootfs"
ROOTFS_MAIN="$ROOTFS/usr/lib/niveth/apps/niveth-files/main.py"

BACKUP_ROOT="$PROJECT_ROOT/integration-backups"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP_DIR="$BACKUP_ROOT/niveth-files-empty-trash-$STAMP"

echo "============================================================"
echo "       NIVETH FILES - EMPTY TRASH"
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

MARKER = "NIVETH EMPTY TRASH SUPPORT v1"

if MARKER in text:
    print("[PASS] Empty Trash support already exists.")
    raise SystemExit(0)

# ---------------------------------------------------------
# Add method before _show_message()
# ---------------------------------------------------------

method = r'''
    # =========================================================
    # NIVETH EMPTY TRASH SUPPORT v1
    # =========================================================

    def _is_trash_view(
        self,
    ):
        try:
            return (
                os.path.abspath(
                    self.current_path
                )
                ==
                os.path.abspath(
                    str(
                        NIVETH_TRASH_FILES
                    )
                )
            )
        except Exception:
            return False

    def _empty_trash(
        self,
        *_args,
    ):
        if not self._is_trash_view():
            return

        try:
            items = list(
                NIVETH_TRASH_FILES.iterdir()
            )
        except Exception as exc:
            self._show_message(
                "Could not read Trash:\n\n"
                f"{exc}"
            )
            return

        if not items:
            self._show_message(
                "Trash is already empty."
            )
            return

        dialog = Gtk.Dialog(
            transient_for=self,
            modal=True,
            title="Empty Trash",
        )

        dialog.set_default_size(
            460,
            200,
        )

        content = dialog.get_content_area()

        content.set_spacing(14)
        content.set_margin_top(24)
        content.set_margin_bottom(24)
        content.set_margin_start(24)
        content.set_margin_end(24)

        label = Gtk.Label(
            label=(
                "Permanently delete all items "
                "from Trash?\n\n"
                f"{len(items)} item(s) will be deleted."
            ),
            wrap=True,
        )

        label.set_xalign(0)

        content.append(
            label
        )

        buttons = Gtk.Box(
            orientation=Gtk.Orientation.HORIZONTAL,
            spacing=10,
        )

        buttons.set_halign(
            Gtk.Align.END
        )

        cancel = Gtk.Button(
            label="Cancel"
        )

        empty = Gtk.Button(
            label="Empty Trash"
        )

        buttons.append(
            cancel
        )

        buttons.append(
            empty
        )

        content.append(
            buttons
        )

        cancel.connect(
            "clicked",
            lambda *_args:
                dialog.close(),
        )

        def confirm_empty(
            *_args,
        ):
            errors = []

            for item in items:
                try:
                    if item.is_dir():
                        import shutil
                        shutil.rmtree(
                            item
                        )
                    else:
                        item.unlink()
                except Exception as exc:
                    errors.append(
                        f"{item.name}: {exc}"
                    )

            dialog.close()

            self.selected_path = None
            self.selected_paths = []
            self.selection_anchor = None

            self._rebuild_columns(
                self.current_path
            )

            self._update_preview(
                None
            )

            self._update_status()

            if errors:
                self._show_message(
                    "Some Trash items could not be deleted:\n\n"
                    + "\n".join(
                        errors[:8]
                    )
                )
            else:
                print(
                    "NIVETH: Trash emptied."
                )

        empty.connect(
            "clicked",
            confirm_empty,
        )

        dialog.present()

'''

message_match = re.search(
    r"(?m)^    def _show_message\(\s*$",
    text,
)

if not message_match:
    raise SystemExit(
        "ERROR: _show_message() not found."
    )

text = (
    text[:message_match.start()]
    + method
    + text[message_match.start():]
)

# ---------------------------------------------------------
# Add Empty Trash to background context menu
# ---------------------------------------------------------

bg_match = re.search(
    r"(?ms)^    def _show_background_context_menu\(.*?(?=^    def |\Z)",
    text,
)

if not bg_match:
    raise SystemExit(
        "ERROR: Background context menu not found."
    )

menu = bg_match.group(0)

if '"Empty Trash"' not in menu:

    insertion = '''        if self._is_trash_view():
            self._context_separator(
                content
            )

            self._context_item(
                content,
                "Empty Trash",
                "user-trash-symbolic",
                self._empty_trash,
                enabled=True,
            )

'''

    menu_set_child = menu.find(
        "        menu.set_child(content)"
    )

    if menu_set_child < 0:
        raise SystemExit(
            "ERROR: Background menu insertion point not found."
        )

    menu = (
        menu[:menu_set_child]
        + insertion
        + menu[menu_set_child:]
    )

    text = (
        text[:bg_match.start()]
        + menu
        + text[bg_match.end():]
    )

# ---------------------------------------------------------
# Add marker
# ---------------------------------------------------------

text = text.replace(
    "    # =========================================================\n"
    "    # MESSAGE\n",
    "    # =========================================================\n"
    "    # MESSAGE\n",
    1,
)

# Marker placed near trash method.
trash_marker = (
    "    # =========================================================\n"
    "    # NIVETH EMPTY TRASH SUPPORT v1\n"
    "    # =========================================================\n"
)

if trash_marker not in text:
    raise SystemExit(
        "ERROR: Empty Trash marker missing after patch."
    )

path.write_text(
    text,
    encoding="utf-8",
)

print(
    "[PASS] Empty Trash method inserted."
)

print(
    "[PASS] Empty Trash context action inserted."
)
PY

echo
echo "=== PYTHON CHECK ==="

python3 -m py_compile \
    "$SOURCE_MAIN"

echo "[PASS] Python syntax"
echo

echo "=== VERIFY SOURCE ==="

grep -q \
    "NIVETH EMPTY TRASH SUPPORT v1" \
    "$SOURCE_MAIN"

grep -q \
    "def _empty_trash" \
    "$SOURCE_MAIN"

grep -q \
    '"Empty Trash"' \
    "$SOURCE_MAIN"

echo "[PASS] Empty Trash method"
echo "[PASS] Empty Trash menu"
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

echo "[PASS] Ubuntu host synchronized"
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

echo "[PASS] ISO rootfs synchronized"
echo

echo "=== VERIFY ROOTFS ==="

sudo grep -q \
    "NIVETH EMPTY TRASH SUPPORT v1" \
    "$ROOTFS_MAIN"

sudo grep -q \
    '"Empty Trash"' \
    "$ROOTFS_MAIN"

echo "[PASS] Rootfs Empty Trash support"
echo

echo "============================================================"
echo "[DONE] Niveth Files Empty Trash installed."
echo "============================================================"
echo
echo "Use:"
echo "  Open Trash"
echo "  Right-click empty area"
echo "  Empty Trash"
echo
echo "Host + ISO rootfs synchronized."
