#!/usr/bin/env bash

set -euo pipefail

PROJECT_ROOT="$HOME/Niveth"
ROOTFS="$PROJECT_ROOT/build/rootfs"

SOURCE="$HOME/.local/bin/niveth-wallpaper-time.py"
SYSTEM_SCRIPT="/usr/local/bin/niveth-wallpaper-time.py"
USER_SERVICE_DIR="$HOME/.config/systemd/user"
USER_SERVICE="$USER_SERVICE_DIR/niveth-wallpaper.service"

echo "=================================================="
echo " Niveth Automatic Wallpaper Service Fix"
echo "=================================================="
echo

if [ ! -f "$SOURCE" ]; then
    echo "ERROR: Wallpaper script not found:"
    echo "  $SOURCE"
    exit 1
fi

if [ ! -d "$ROOTFS" ]; then
    echo "ERROR: Rootfs not found:"
    echo "  $ROOTFS"
    exit 1
fi

echo "=== 1. Installing wallpaper script system-wide on host ==="

sudo install -D -m 755 \
    "$SOURCE" \
    "$SYSTEM_SCRIPT"

echo "Installed:"
echo "  $SYSTEM_SCRIPT"

echo
echo "=== 2. Creating corrected user service ==="

mkdir -p "$USER_SERVICE_DIR"

cat > "$USER_SERVICE" <<'SERVICE'
[Unit]
Description=Niveth Automatic Wallpaper
After=graphical-session.target
PartOf=graphical-session.target

[Service]
Type=simple
ExecStart=/usr/bin/python3 /usr/local/bin/niveth-wallpaper-time.py
Restart=on-failure
RestartSec=5

[Install]
WantedBy=graphical-session.target
SERVICE

echo "$USER_SERVICE"

echo
echo "=== 3. Reloading user systemd ==="

systemctl --user daemon-reload

echo
echo "=== 4. Restarting wallpaper service ==="

systemctl --user stop niveth-wallpaper.service 2>/dev/null || true
systemctl --user reset-failed niveth-wallpaper.service 2>/dev/null || true
systemctl --user start niveth-wallpaper.service
systemctl --user enable niveth-wallpaper.service

echo
echo "=== 5. Synchronizing wallpaper script into Niveth rootfs ==="

sudo install -D -m 755 \
    "$SOURCE" \
    "$ROOTFS/usr/local/bin/niveth-wallpaper-time.py"

echo "Rootfs script:"
echo "  $ROOTFS/usr/local/bin/niveth-wallpaper-time.py"

echo
echo "=== 6. Creating Niveth wallpaper service for new users ==="

sudo mkdir -p \
    "$ROOTFS/etc/skel/.config/systemd/user"

sudo tee \
    "$ROOTFS/etc/skel/.config/systemd/user/niveth-wallpaper.service" \
    >/dev/null <<'SERVICE'
[Unit]
Description=Niveth Automatic Wallpaper
After=graphical-session.target
PartOf=graphical-session.target

[Service]
Type=simple
ExecStart=/usr/bin/python3 /usr/local/bin/niveth-wallpaper-time.py
Restart=on-failure
RestartSec=5

[Install]
WantedBy=graphical-session.target
SERVICE

sudo chmod 644 \
    "$ROOTFS/etc/skel/.config/systemd/user/niveth-wallpaper.service"

echo
echo "=== 7. Verifying wallpaper script ==="

python3 -m py_compile "$SOURCE"

echo "Host script syntax: OK"

echo
echo "=== 8. Current service status ==="

systemctl --user status niveth-wallpaper.service \
    --no-pager \
    -l 2>&1 || true

echo
echo "=== 9. Current GNOME state ==="

echo "Color scheme:"
gsettings get org.gnome.desktop.interface color-scheme

echo
echo "Light wallpaper:"
gsettings get org.gnome.desktop.background picture-uri

echo
echo "Dark wallpaper:"
gsettings get org.gnome.desktop.background picture-uri-dark

echo
echo "=================================================="
echo " WALLPAPER SERVICE FIX COMPLETE"
echo "=================================================="
