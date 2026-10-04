#!/usr/bin/env bash

set -euo pipefail

DING_HOST="/usr/share/gnome-shell/extensions/ding@rastersoft.com"

ROOTFS="$HOME/Niveth/build/rootfs"
DING_ROOTFS="$ROOTFS/usr/share/gnome-shell/extensions/ding@rastersoft.com"

CHOOSER_HOST="/usr/local/bin/niveth-wallpaper-chooser.py"
CHOOSER_USER="$HOME/.local/bin/niveth-wallpaper-chooser.py"

STAMP="$(date +%Y%m%d-%H%M%S)"

echo
echo "============================================================"
echo " NIVETH DESKTOP WALLPAPER MENU"
echo " DING: Change Background -> Change Wallpaper"
echo "============================================================"
echo

# ============================================================
# 1. CHECK DING
# ============================================================

echo "[1/9] Locating DING desktopManager.js"

if [ ! -d "$DING_HOST" ]; then
    echo "[FAIL] DING extension not found:"
    echo "$DING_HOST"
    exit 1
fi

HOST_MANAGER="$(find "$DING_HOST" -type f -name 'desktopManager.js' 2>/dev/null | head -1)"

if [ -z "$HOST_MANAGER" ]; then
    echo "[FAIL] Could not find DING desktopManager.js"
    exit 1
fi

echo "[PASS] Host DING manager:"
echo "       $HOST_MANAGER"


# ============================================================
# 2. STANDARDIZE WALLPAPER CHOOSER
# ============================================================

echo
echo "[2/9] Checking Niveth wallpaper chooser"

if [ -x "$CHOOSER_HOST" ]; then

    echo "[PASS] $CHOOSER_HOST already exists"

elif [ -x "$CHOOSER_USER" ]; then

    echo "[INFO] Installing user chooser to:"
    echo "       $CHOOSER_HOST"

    sudo install -m 0755 \
        "$CHOOSER_USER" \
        "$CHOOSER_HOST"

    echo "[PASS] Niveth wallpaper chooser installed"

else

    echo "[FAIL] Niveth wallpaper chooser not found."
    echo
    echo "Checked:"
    echo "  $CHOOSER_HOST"
    echo "  $CHOOSER_USER"
    exit 1
fi


# ============================================================
# 3. BACKUP HOST DING
# ============================================================

echo
echo "[3/9] Backing up DING"

HOST_BACKUP="$HOST_MANAGER.backup-before-niveth-wallpaper-$STAMP"

sudo cp \
    "$HOST_MANAGER" \
    "$HOST_BACKUP"

echo "[PASS] Backup:"
echo "       $HOST_BACKUP"


# ============================================================
# 4. PATCH HOST DING
# ============================================================

echo
echo "[4/9] Replacing Change Background"

sudo python3 - "$HOST_MANAGER" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")

start_marker = "  this._changeBackgroundMenuItem = "
end_marker = "  this._menu.add(this._changeBackgroundMenuItem);"

start = text.find(start_marker)

if start == -1:
    raise SystemExit(
        "ERROR: DING Change Background menu block not found."
    )

end = text.find(end_marker, start)

if end == -1:
    raise SystemExit(
        "ERROR: End of Change Background menu block not found."
    )

end += len(end_marker)

replacement = """  this._changeWallpaperMenuItem = new Gtk.MenuItem({label: _("Change Wallpaper")});

  this._changeWallpaperMenuItem.connect("activate", () => {
    try {
      GLib.spawn_command_line_async("python3 /usr/local/bin/niveth-wallpaper-chooser.py");
    } catch (e) {
      log("NIVETH: Could not launch wallpaper chooser: " + e.message);
    }
  });

  this._menu.add(this._changeWallpaperMenuItem);"""

text = text[:start] + replacement + text[end:]

# Make sure GLib is imported.
if "gi://GLib" not in text:
    first_import = text.find("\n")
    text = (
        text[:first_import + 1]
        + "import GLib from 'gi://GLib';\n"
        + text[first_import + 1:]
    )

path.write_text(text, encoding="utf-8")
PY

echo "[PASS] DING desktop context menu patched"


# ============================================================
# 5. VERIFY HOST
# ============================================================

echo
echo "[5/9] Verifying host DING"

if sudo grep -q \
    'this._changeWallpaperMenuItem = new Gtk.MenuItem({label: _("Change Wallpaper")});' \
    "$HOST_MANAGER"
then
    echo "[PASS] Change Wallpaper entry exists"
else
    echo "[FAIL] Change Wallpaper entry missing"
    exit 1
fi

if sudo grep -q \
    '/usr/local/bin/niveth-wallpaper-chooser.py' \
    "$HOST_MANAGER"
then
    echo "[PASS] Niveth chooser path exists in DING"
else
    echo "[FAIL] Niveth chooser path missing"
    exit 1
fi

if sudo grep -q \
    'this._changeBackgroundMenuItem' \
    "$HOST_MANAGER"
then
    echo "[FAIL] Old Change Background code still exists"
    exit 1
else
    echo "[PASS] Old Change Background code removed"
fi


# ============================================================
# 6. LOCATE ROOTFS DING
# ============================================================

echo
echo "[6/9] Locating rootfs DING"

if [ ! -d "$ROOTFS" ]; then
    echo "[FAIL] Rootfs not found:"
    echo "$ROOTFS"
    exit 1
fi

ROOTFS_MANAGER="$(find "$DING_ROOTFS" -type f -name 'desktopManager.js' 2>/dev/null | head -1)"

if [ -z "$ROOTFS_MANAGER" ]; then
    echo "[FAIL] Could not find rootfs DING desktopManager.js"
    exit 1
fi

echo "[PASS] Rootfs DING manager:"
echo "       $ROOTFS_MANAGER"


# ============================================================
# 7. SYNC HOST -> ROOTFS
# ============================================================

echo
echo "[7/9] Synchronizing DING into rootfs"

ROOTFS_BACKUP="$ROOTFS_MANAGER.backup-before-niveth-wallpaper-$STAMP"

if [ -f "$ROOTFS_MANAGER" ]; then
    sudo cp \
        "$ROOTFS_MANAGER" \
        "$ROOTFS_BACKUP"

    echo "[PASS] Rootfs backup:"
    echo "       $ROOTFS_BACKUP"
fi

sudo install -m 0644 \
    "$HOST_MANAGER" \
    "$ROOTFS_MANAGER"

echo "[PASS] Rootfs DING patched"

# Make sure chooser exists in rootfs.
if [ -x "$ROOTFS/usr/local/bin/niveth-wallpaper-chooser.py" ]; then

    echo "[PASS] Rootfs Niveth wallpaper chooser exists"

elif [ -f "$CHOOSER_HOST" ]; then

    sudo install -m 0755 \
        "$CHOOSER_HOST" \
        "$ROOTFS/usr/local/bin/niveth-wallpaper-chooser.py"

    echo "[PASS] Rootfs wallpaper chooser installed"

else

    echo "[FAIL] Could not install rootfs wallpaper chooser"
    exit 1
fi


# ============================================================
# 8. HASH + CONTENT VERIFICATION
# ============================================================

echo
echo "[8/9] Verifying host/rootfs integrity"

HOST_HASH="$(sudo sha256sum "$HOST_MANAGER" | awk '{print $1}')"
ROOTFS_HASH="$(sudo sha256sum "$ROOTFS_MANAGER" | awk '{print $1}')"

echo
echo "DING desktopManager.js"
echo "  HOST   : $HOST_HASH"
echo "  ROOTFS : $ROOTFS_HASH"

if [ "$HOST_HASH" != "$ROOTFS_HASH" ]; then
    echo "[FAIL] Host/rootfs DING hashes differ"
    exit 1
fi

echo "[PASS] Host/rootfs DING files are identical"

sudo grep -q \
    'this._changeWallpaperMenuItem = new Gtk.MenuItem({label: _("Change Wallpaper")});' \
    "$ROOTFS_MANAGER"

sudo grep -q \
    '/usr/local/bin/niveth-wallpaper-chooser.py' \
    "$ROOTFS_MANAGER"

sudo grep -q \
    'Change Wallpaper' \
    "$ROOTFS_MANAGER"

if sudo grep -q \
    'this._changeBackgroundMenuItem' \
    "$ROOTFS_MANAGER"
then
    echo "[FAIL] Old Change Background remains in rootfs"
    exit 1
fi

echo "[PASS] Rootfs contains Change Wallpaper"
echo "[PASS] Rootfs contains Niveth chooser"
echo "[PASS] Rootfs has no old Change Background code"

ROOTFS_CHOOSER_HASH="$(sudo sha256sum \
    "$ROOTFS/usr/local/bin/niveth-wallpaper-chooser.py" \
    | awk '{print $1}')"

HOST_CHOOSER_HASH="$(sha256sum \
    "$CHOOSER_HOST" \
    | awk '{print $1}')"

echo
echo "Wallpaper chooser"
echo "  HOST   : $HOST_CHOOSER_HASH"
echo "  ROOTFS : $ROOTFS_CHOOSER_HASH"

if [ "$HOST_CHOOSER_HASH" = "$ROOTFS_CHOOSER_HASH" ]; then
    echo "[PASS] Wallpaper chooser identical"
else
    echo "[WARN] Wallpaper chooser differs"
fi


# ============================================================
# 9. RESTART DING + FINAL STATUS
# ============================================================

echo
echo "[9/9] Restarting DING"

gnome-extensions disable ding@rastersoft.com 2>/dev/null || true

sleep 3

gnome-extensions enable ding@rastersoft.com

sleep 5

echo
echo "DING status:"
gnome-extensions info ding@rastersoft.com 2>&1 \
    | grep -E "Name:|Enabled:|State:|Path:" || true

echo
echo "Wallpaper chooser:"
ls -lh "$CHOOSER_HOST"

echo
echo "============================================================"
echo " COMPLETE"
echo "============================================================"
echo
echo "Desktop menu:"
echo "  Change Background...  -> REMOVED"
echo "  Change Wallpaper      -> ADDED"
echo
echo "Niveth chooser:"
echo "  $CHOOSER_HOST"
echo
echo "Rootfs DING:"
echo "  $ROOTFS_MANAGER"
echo
echo "Host/rootfs SHA256:"
echo "  $HOST_HASH"
echo
