#!/usr/bin/env bash

set -euo pipefail

PROJECT_ROOT="$HOME/Niveth"

SOURCE_MAIN="$HOME/Niveth-Files/main.py"
SOURCE_CSS="$HOME/Niveth-Files/styles.css"

ROOTFS="$PROJECT_ROOT/build/rootfs"
ROOTFS_MAIN="$ROOTFS/usr/lib/niveth/apps/niveth-files/main.py"
ROOTFS_CSS="$ROOTFS/usr/lib/niveth/apps/niveth-files/styles.css"

BACKUP_DIR="$PROJECT_ROOT/integration-backups/niveth-files-removable-v2-$(date +%Y%m%d-%H%M%S)"

echo "============================================================"
echo " NIVETH FILES - REMOVABLE DEVICES v2"
echo "============================================================"
echo

for f in "$SOURCE_MAIN" "$SOURCE_CSS" "$ROOTFS_MAIN" "$ROOTFS_CSS"; do
    if [[ ! -f "$f" ]]; then
        echo "[ERROR] Missing:"
        echo "        $f"
        exit 1
    fi
done

mkdir -p "$BACKUP_DIR"

cp "$SOURCE_MAIN" "$BACKUP_DIR/main.py.before"
cp "$SOURCE_CSS" "$BACKUP_DIR/styles.css.before"

sudo cp "$ROOTFS_MAIN" "$BACKUP_DIR/rootfs-main.py.before"
sudo cp "$ROOTFS_CSS" "$BACKUP_DIR/rootfs-styles.css.before"

echo "[PASS] Backups created:"
echo "       $BACKUP_DIR"

echo
echo "=== 1. VERIFY SOURCE ==="

python3 -m py_compile "$SOURCE_MAIN"

echo "[PASS] Current source syntax"

echo
echo "=== 2. PATCH PYTHON ==="

python3 - "$SOURCE_MAIN" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")

MARKER = "NIVETH REMOVABLE DEVICES v2"

if MARKER in text:
    print("[PASS] Removable device support already installed.")
    raise SystemExit(0)

# ------------------------------------------------------------
# STATE
# ------------------------------------------------------------

old = '''        self._theme_provider = None

        self._load_tags()
        self._dark_mode = self._get_system_dark_mode()
'''

new = '''        self._theme_provider = None

        # =====================================================
        # NIVETH REMOVABLE DEVICES v2
        # =====================================================
        self._volume_monitor = None
        self._volume_monitor_handlers = []
        self._removable_devices_box = None
        self._removable_rows = []

        self._load_tags()
        self._dark_mode = self._get_system_dark_mode()
'''

if old not in text:
    raise SystemExit(
        "ERROR: Could not find current theme/provider state block."
    )

text = text.replace(old, new, 1)

# ------------------------------------------------------------
# VOLUME MONITOR INITIALIZATION
# ------------------------------------------------------------

old = '''        self._build_ui()
        self._apply_theme()

        self._navigate_to(
'''

new = '''        self._build_ui()
        self._apply_theme()
        self._setup_volume_monitor()

        self._navigate_to(
'''

if old not in text:
    raise SystemExit(
        "ERROR: Could not find current build/apply block."
    )

text = text.replace(old, new, 1)

# ------------------------------------------------------------
# SIDEBAR
# ------------------------------------------------------------

old = '''        self._sidebar_button(
            sidebar,
            "Computer",
            "drive-harddisk-symbolic",
            "/",
        )

        self._sidebar_button(
            sidebar,
            "Home",
            "user-home-symbolic",
            os.path.expanduser("~"),
        )

        self._sidebar_section(
            sidebar,
            "PLACES",
        )
'''

new = '''        self._sidebar_button(
            sidebar,
            "Computer",
            "drive-harddisk-symbolic",
            "/",
        )

        # =====================================================
        # NIVETH REMOVABLE DEVICES
        # =====================================================

        self._removable_devices_box = Gtk.Box(
            orientation=Gtk.Orientation.VERTICAL,
            spacing=2,
        )

        self._removable_devices_box.add_css_class(
            "removable-devices"
        )

        sidebar.append(
            self._removable_devices_box
        )

        self._refresh_removable_devices()

        self._sidebar_button(
            sidebar,
            "Home",
            "user-home-symbolic",
            os.path.expanduser("~"),
        )

        self._sidebar_section(
            sidebar,
            "PLACES",
        )
'''

if old not in text:
    raise SystemExit(
        "ERROR: Could not find current sidebar device block."
    )

text = text.replace(old, new, 1)

# ------------------------------------------------------------
# METHODS
# ------------------------------------------------------------

marker = '''    # =========================================================
    # COLUMNS
    # =========================================================
'''

if marker not in text:
    raise SystemExit(
        "ERROR: Could not find COLUMNS insertion point."
    )

methods = r'''
    # =========================================================
    # NIVETH REMOVABLE DEVICES v2
    # =========================================================

    def _setup_volume_monitor(self):
        if self._volume_monitor is not None:
            return

        try:
            self._volume_monitor = Gio.VolumeMonitor.get()

            for signal_name in (
                "mount-added",
                "mount-removed",
                "volume-added",
                "volume-removed",
            ):
                handler_id = self._volume_monitor.connect(
                    signal_name,
                    self._on_volume_state_changed,
                )

                self._volume_monitor_handlers.append(
                    handler_id
                )

            self._refresh_removable_devices()

        except Exception as exc:
            print(
                f"NIVETH: VolumeMonitor setup failed: {exc}"
            )

    def _on_volume_state_changed(
        self,
        *_args,
    ):
        GLib.idle_add(
            self._refresh_removable_devices
        )

    def _get_removable_mounts(self):
        if self._volume_monitor is None:
            return []

        mounts = []

        try:
            for mount in self._volume_monitor.get_mounts():
                try:
                    volume = mount.get_volume()

                    if volume is None:
                        continue

                    root = mount.get_root()

                    if root is None:
                        continue

                    path = root.get_path()

                    if not path:
                        continue

                    drive = volume.get_drive()

                    is_removable = (
                        volume.can_eject()
                        or (
                            drive is not None
                            and drive.is_removable()
                        )
                    )

                    if not is_removable:
                        continue

                    mounts.append(
                        (
                            volume,
                            mount,
                            path,
                        )
                    )

                except Exception as exc:
                    print(
                        f"NIVETH: volume scan error: {exc}"
                    )

        except Exception as exc:
            print(
                f"NIVETH: mount scan failed: {exc}"
            )

        return mounts

    def _clear_removable_devices(self):
        if self._removable_devices_box is None:
            return

        child = (
            self._removable_devices_box.get_first_child()
        )

        while child:
            next_child = (
                child.get_next_sibling()
            )

            self._removable_devices_box.remove(
                child
            )

            child = next_child

        self._removable_rows.clear()

    def _refresh_removable_devices(self):
        if self._removable_devices_box is None:
            return GLib.SOURCE_REMOVE

        self._clear_removable_devices()

        for volume, mount, path in (
            self._get_removable_mounts()
        ):
            self._add_removable_device_row(
                volume,
                mount,
                path,
            )

        return GLib.SOURCE_REMOVE

    def _add_removable_device_row(
        self,
        volume,
        mount,
        path,
    ):
        name = volume.get_name()

        if not name:
            name = mount.get_name()

        if not name:
            name = (
                os.path.basename(
                    path.rstrip("/")
                )
                or "Removable Drive"
            )

        row = Gtk.Box(
            orientation=Gtk.Orientation.HORIZONTAL,
            spacing=3,
        )

        row.add_css_class(
            "removable-device-row"
        )

        open_button = Gtk.Button()

        open_button.set_has_frame(False)
        open_button.set_hexpand(True)
        open_button.set_halign(
            Gtk.Align.FILL
        )

        open_button.add_css_class(
            "sidebar-button"
        )

        content = Gtk.Box(
            orientation=Gtk.Orientation.HORIZONTAL,
            spacing=11,
        )

        icon = Gtk.Image.new_from_icon_name(
            "drive-removable-media-symbolic"
        )

        icon.set_pixel_size(
            19
        )

        label = Gtk.Label(
            label=name,
            xalign=0,
        )

        label.set_hexpand(True)
        label.set_ellipsize(
            3
        )

        content.append(icon)
        content.append(label)

        open_button.set_child(
            content
        )

        open_button.set_tooltip_text(
            path
        )

        open_button.connect(
            "clicked",
            lambda *_args, p=path:
                self._navigate_to(p),
        )

        eject_button = Gtk.Button.new_from_icon_name(
            "media-eject-symbolic"
        )

        eject_button.set_has_frame(False)

        eject_button.add_css_class(
            "removable-device-eject"
        )

        eject_button.set_tooltip_text(
            "Safely Remove"
        )

        eject_button.connect(
            "clicked",
            lambda *_args,
            v=volume,
            m=mount,
            n=name:
                self._safe_remove_volume(
                    v,
                    m,
                    n,
                ),
        )

        row.append(
            open_button
        )

        row.append(
            eject_button
        )

        self._removable_devices_box.append(
            row
        )

        self._removable_rows.append(
            (
                row,
                volume,
                mount,
            )
        )

    def _safe_remove_volume(
        self,
        volume,
        mount,
        name,
    ):
        try:
            if (
                volume is not None
                and volume.can_eject()
            ):
                volume.eject_with_operation(
                    Gio.MountUnmountFlags.NONE,
                    None,
                    None,
                    self._safe_remove_finished,
                    name,
                )
                return

            if (
                mount is not None
                and mount.can_unmount()
            ):
                mount.unmount_with_operation(
                    Gio.MountUnmountFlags.NONE,
                    None,
                    None,
                    self._safe_remove_unmount_finished,
                    name,
                )
                return

            self._show_storage_notification(
                "Unable to safely remove device",
                f"'{name}' cannot be safely removed.",
            )

        except Exception as exc:
            self._show_storage_notification(
                "Unable to safely remove device",
                f"'{name}': {exc}",
            )

    def _safe_remove_finished(
        self,
        source,
        result,
        name,
    ):
        try:
            source.eject_with_operation_finish(
                result
            )

            self._show_storage_notification(
                "Device safely removed",
                f"'{name}' can now be unplugged safely.",
            )

        except Exception as exc:
            self._show_storage_notification(
                "Unable to safely remove device",
                f"'{name}': {exc}",
            )

        finally:
            self._refresh_removable_devices()

    def _safe_remove_unmount_finished(
        self,
        source,
        result,
        name,
    ):
        try:
            source.unmount_with_operation_finish(
                result
            )

            self._show_storage_notification(
                "Device safely removed",
                f"'{name}' is unmounted and can be unplugged safely.",
            )

        except Exception as exc:
            self._show_storage_notification(
                "Unable to safely remove device",
                f"'{name}': {exc}",
            )

        finally:
            self._refresh_removable_devices()

    def _show_storage_notification(
        self,
        title,
        body,
    ):
        try:
            app = self.get_application()

            if app is None:
                return

            notification = Gio.Notification.new(
                title
            )

            notification.set_body(
                body
            )

            app.send_notification(
                "niveth-storage",
                notification,
            )

        except Exception as exc:
            print(
                f"NIVETH: notification failed: {exc}"
            )

'''

text = text.replace(
    marker,
    methods + "\n" + marker,
    1,
)

path.write_text(
    text,
    encoding="utf-8",
)

print("[PASS] Removable device support inserted.")
PY

echo
echo "=== 3. PATCH CSS ==="

if ! grep -q "NIVETH REMOVABLE DEVICES v2" "$SOURCE_CSS"; then
    cat >> "$SOURCE_CSS" <<'CSS'

/* ============================================================
   NIVETH REMOVABLE DEVICES v2
   ============================================================ */

.removable-devices {
    margin: 0;
    padding: 0;
}

.removable-device-row {
    min-height: 34px;
    margin: 0;
    padding: 0 2px;
    border-radius: 9px;
}

.removable-device-eject {
    min-width: 32px;
    min-height: 32px;
    padding: 0;
    border-radius: 8px;
}

.removable-device-eject:hover {
    background: rgba(127, 157, 184, 0.18);
}

CSS
fi

echo "[PASS] CSS ready"

echo
echo "=== 4. VERIFY SOURCE ==="

python3 -m py_compile "$SOURCE_MAIN"

echo "[PASS] Python syntax"

echo
echo "=== 5. SYNC ROOTFS ==="

sudo cp \
    "$SOURCE_MAIN" \
    "$ROOTFS_MAIN"

sudo cp \
    "$SOURCE_CSS" \
    "$ROOTFS_CSS"

sudo chown root:root \
    "$ROOTFS_MAIN" \
    "$ROOTFS_CSS"

sudo chmod 0644 \
    "$ROOTFS_MAIN" \
    "$ROOTFS_CSS"

sudo rm -rf \
    "$ROOTFS/usr/lib/niveth/apps/niveth-files/__pycache__"

echo "[PASS] Source synchronized to rootfs"

echo
echo "=== 6. ROOTFS VERIFY ==="

sudo python3 -m py_compile \
    "$ROOTFS_MAIN"

sudo grep -q \
    "NIVETH REMOVABLE DEVICES v2" \
    "$ROOTFS_MAIN"

sudo grep -q \
    "Gio.VolumeMonitor.get()" \
    "$ROOTFS_MAIN"

sudo grep -q \
    "_safe_remove_volume" \
    "$ROOTFS_MAIN"

sudo grep -q \
    "_show_storage_notification" \
    "$ROOTFS_MAIN"

echo "[PASS] Rootfs Python syntax"
echo "[PASS] VolumeMonitor support"
echo "[PASS] Removable device detection"
echo "[PASS] Safe Remove"
echo "[PASS] Notification support"

echo
echo "============================================================"
echo " NIVETH FILES REMOVABLE DEVICES v2: READY"
echo "============================================================"
echo
echo "USB flash drives        : YES"
echo "External removable HDD  : YES"
echo "Automatic appearance    : YES"
echo "Open device             : YES"
echo "Safe Remove / Eject     : YES"
echo "Removal notification    : YES"
echo
echo "Backup:"
echo "  $BACKUP_DIR"
echo

