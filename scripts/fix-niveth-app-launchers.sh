#!/usr/bin/env bash

set -euo pipefail

PROJECT_ROOT="$HOME/Niveth"
ROOTFS="$PROJECT_ROOT/build/rootfs"

NOTES_SRC="$HOME/.local/share/niveth-notes"
APPCENTER_SRC="$HOME/.local/share/niveth-app-center"
FILES_SRC="$HOME/Niveth-Files"

SYSTEM_APP_ROOT="/usr/lib/niveth/apps"
SYSTEM_BIN="/usr/local/bin"
SYSTEM_APPS="/usr/local/share/applications"

echo "=================================================="
echo " Niveth App Launcher Repair"
echo "=================================================="
echo

if [ ! -d "$ROOTFS" ]; then
    echo "ERROR: Rootfs not found:"
    echo "  $ROOTFS"
    exit 1
fi

echo "=== Checking source applications ==="

for src in "$NOTES_SRC" "$APPCENTER_SRC" "$FILES_SRC"; do
    if [ ! -e "$src" ]; then
        echo "ERROR: Missing source:"
        echo "  $src"
        exit 1
    fi
    echo "OK: $src"
done

echo
echo "=================================================="
echo " 1. Installing Niveth Notes system-wide"
echo "=================================================="

sudo mkdir -p "$SYSTEM_APP_ROOT/niveth-notes"
sudo rsync -a --delete \
    --exclude='__pycache__' \
    "$NOTES_SRC/" \
    "$SYSTEM_APP_ROOT/niveth-notes/"

sudo chown -R root:root "$SYSTEM_APP_ROOT/niveth-notes"

sudo tee "$SYSTEM_BIN/niveth-notes" >/dev/null <<'SCRIPT'
#!/usr/bin/env bash
exec /usr/bin/python3 /usr/lib/niveth/apps/niveth-notes/niveth-notes.py "$@"
SCRIPT

sudo chmod 755 "$SYSTEM_BIN/niveth-notes"

echo "Installed:"
echo "  $SYSTEM_BIN/niveth-notes"

echo
echo "=================================================="
echo " 2. Installing Niveth App Center system-wide"
echo "=================================================="

sudo mkdir -p "$SYSTEM_APP_ROOT/niveth-app-center"

sudo rsync -a --delete \
    --exclude='backups' \
    --exclude='__pycache__' \
    "$APPCENTER_SRC/" \
    "$SYSTEM_APP_ROOT/niveth-app-center/"

sudo chown -R root:root "$SYSTEM_APP_ROOT/niveth-app-center"

sudo tee "$SYSTEM_BIN/niveth-app-center" >/dev/null <<'SCRIPT'
#!/usr/bin/env bash
exec /usr/bin/python3 /usr/lib/niveth/apps/niveth-app-center/niveth-app-center.py "$@"
SCRIPT

sudo chmod 755 "$SYSTEM_BIN/niveth-app-center"

echo "Installed:"
echo "  $SYSTEM_BIN/niveth-app-center"

echo
echo "=================================================="
echo " 3. Installing Niveth Files system-wide"
echo "=================================================="

sudo mkdir -p "$SYSTEM_APP_ROOT/niveth-files"

sudo rsync -a \
    --exclude='__pycache__' \
    "$FILES_SRC/" \
    "$SYSTEM_APP_ROOT/niveth-files/"

sudo chown -R root:root "$SYSTEM_APP_ROOT/niveth-files"

sudo tee "$SYSTEM_BIN/niveth-files" >/dev/null <<'SCRIPT'
#!/usr/bin/env bash
exec /usr/bin/python3 /usr/lib/niveth/apps/niveth-files/main.py "$@"
SCRIPT

sudo chmod 755 "$SYSTEM_BIN/niveth-files"

echo "Installed:"
echo "  $SYSTEM_BIN/niveth-files"

echo
echo "=================================================="
echo " 4. Installing canonical desktop files"
echo "=================================================="

sudo mkdir -p "$SYSTEM_APPS"

sudo tee "$SYSTEM_APPS/com.niveth.Notes.desktop" >/dev/null <<'DESKTOP'
[Desktop Entry]
Version=1.0
Type=Application
Name=Niveth Notes
GenericName=Sticky Notes
Comment=Retro sticky notes for Niveth OS
Exec=/usr/local/bin/niveth-notes
TryExec=/usr/local/bin/niveth-notes
Icon=com.niveth.Notes
Terminal=false
StartupNotify=true
StartupWMClass=com.niveth.Notes
Categories=Utility;Office;
Keywords=Notes;Sticky;Memo;Niveth;
Actions=new-note;

[Desktop Action new-note]
Name=New Note
Exec=/usr/local/bin/niveth-notes
DESKTOP

sudo tee "$SYSTEM_APPS/com.niveth.AppCenter.desktop" >/dev/null <<'DESKTOP'
[Desktop Entry]
Version=1.0
Type=Application
Name=Niveth App Center
GenericName=Software Center
Comment=Discover, install and update applications
Exec=/usr/local/bin/niveth-app-center
TryExec=/usr/local/bin/niveth-app-center
Icon=niveth-app-center
Terminal=false
Categories=System;PackageManager;Utility;
StartupNotify=true
StartupWMClass=com.niveth.AppCenter
X-GNOME-UsesNotifications=false
DESKTOP

sudo tee "$SYSTEM_APPS/org.niveth.Files.desktop" >/dev/null <<'DESKTOP'
[Desktop Entry]
Version=1.0
Type=Application
Name=Niveth Files
GenericName=File Manager
Comment=Simpler spaces for a calmer you
Exec=/usr/local/bin/niveth-files %U
TryExec=/usr/local/bin/niveth-files
Icon=org.niveth.Files
Terminal=false
Categories=System;FileManager;Utility;
MimeType=inode/directory;
StartupNotify=true
StartupWMClass=org.niveth.Files
DESKTOP

sudo chmod 644 \
    "$SYSTEM_APPS/com.niveth.Notes.desktop" \
    "$SYSTEM_APPS/com.niveth.AppCenter.desktop" \
    "$SYSTEM_APPS/org.niveth.Files.desktop"

echo
echo "=================================================="
echo " 5. Synchronizing the same files into Niveth rootfs"
echo "=================================================="

sudo mkdir -p \
    "$ROOTFS/usr/lib/niveth/apps/niveth-notes" \
    "$ROOTFS/usr/lib/niveth/apps/niveth-app-center" \
    "$ROOTFS/usr/lib/niveth/apps/niveth-files" \
    "$ROOTFS/usr/local/bin" \
    "$ROOTFS/usr/local/share/applications"

sudo rsync -a --delete \
    --exclude='__pycache__' \
    "$NOTES_SRC/" \
    "$ROOTFS/usr/lib/niveth/apps/niveth-notes/"

sudo rsync -a --delete \
    --exclude='backups' \
    --exclude='__pycache__' \
    "$APPCENTER_SRC/" \
    "$ROOTFS/usr/lib/niveth/apps/niveth-app-center/"

sudo rsync -a \
    --exclude='__pycache__' \
    "$FILES_SRC/" \
    "$ROOTFS/usr/lib/niveth/apps/niveth-files/"

sudo tee "$ROOTFS/usr/local/bin/niveth-notes" >/dev/null <<'SCRIPT'
#!/usr/bin/env bash
exec /usr/bin/python3 /usr/lib/niveth/apps/niveth-notes/niveth-notes.py "$@"
SCRIPT

sudo tee "$ROOTFS/usr/local/bin/niveth-app-center" >/dev/null <<'SCRIPT'
#!/usr/bin/env bash
exec /usr/bin/python3 /usr/lib/niveth/apps/niveth-app-center/niveth-app-center.py "$@"
SCRIPT

sudo tee "$ROOTFS/usr/local/bin/niveth-files" >/dev/null <<'SCRIPT'
#!/usr/bin/env bash
exec /usr/bin/python3 /usr/lib/niveth/apps/niveth-files/main.py "$@"
SCRIPT

sudo chmod 755 \
    "$ROOTFS/usr/local/bin/niveth-notes" \
    "$ROOTFS/usr/local/bin/niveth-app-center" \
    "$ROOTFS/usr/local/bin/niveth-files"

sudo rsync -a \
    "$SYSTEM_APPS/com.niveth.Notes.desktop" \
    "$SYSTEM_APPS/com.niveth.AppCenter.desktop" \
    "$SYSTEM_APPS/org.niveth.Files.desktop" \
    "$ROOTFS/usr/local/share/applications/"

sudo chown -R root:root \
    "$ROOTFS/usr/lib/niveth/apps/niveth-notes" \
    "$ROOTFS/usr/lib/niveth/apps/niveth-app-center" \
    "$ROOTFS/usr/lib/niveth/apps/niveth-files"

sudo chmod 644 \
    "$ROOTFS/usr/local/share/applications/com.niveth.Notes.desktop" \
    "$ROOTFS/usr/local/share/applications/com.niveth.AppCenter.desktop" \
    "$ROOTFS/usr/local/share/applications/org.niveth.Files.desktop"

echo
echo "=================================================="
echo " 6. Refreshing desktop database"
echo "=================================================="

update-desktop-database "$SYSTEM_APPS" 2>/dev/null || true
sudo chroot "$ROOTFS" update-desktop-database \
    /usr/local/share/applications 2>/dev/null || true

echo
echo "=================================================="
echo " 7. Verification"
echo "=================================================="

echo
echo "--- Host commands ---"
command -v niveth-notes || true
command -v niveth-app-center || true
command -v niveth-files || true

echo
echo "--- Host targets ---"
ls -l \
    /usr/local/bin/niveth-notes \
    /usr/local/bin/niveth-app-center \
    /usr/local/bin/niveth-files

echo
echo "--- Rootfs targets ---"
sudo chroot "$ROOTFS" ls -l \
    /usr/local/bin/niveth-notes \
    /usr/local/bin/niveth-app-center \
    /usr/local/bin/niveth-files

echo
echo "--- Python syntax ---"
python3 -m py_compile \
    "$ROOTFS/usr/lib/niveth/apps/niveth-notes/niveth-notes.py"

python3 -m py_compile \
    "$ROOTFS/usr/lib/niveth/apps/niveth-app-center/niveth-app-center.py"

python3 -m py_compile \
    "$ROOTFS/usr/lib/niveth/apps/niveth-files/main.py"

echo
echo "=================================================="
echo " Niveth launcher repair COMPLETE"
echo "=================================================="
echo
echo "IMPORTANT:"
echo "  Do NOT rebuild the ISO yet."
echo "  First test the applications from the GNOME Dock."
