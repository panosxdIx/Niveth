#!/usr/bin/env bash

set -u

OUT="$HOME/Niveth/ubuntu-inventory-$(date +%Y%m%d-%H%M%S).txt"

{
echo "============================================================"
echo " NIVETH UBUNTU HOST INVENTORY"
echo "============================================================"
date
echo

echo "==================== OS ===================="
. /etc/os-release
echo "PRETTY_NAME=$PRETTY_NAME"
echo "VERSION_ID=$VERSION_ID"
echo "KERNEL=$(uname -r)"
echo "ARCH=$(uname -m)"
echo "HOSTNAME=$(hostname)"
echo

echo "==================== SESSION ===================="
echo "XDG_CURRENT_DESKTOP=${XDG_CURRENT_DESKTOP:-}"
echo "XDG_SESSION_DESKTOP=${XDG_SESSION_DESKTOP:-}"
echo "XDG_SESSION_TYPE=${XDG_SESSION_TYPE:-}"
echo "WAYLAND_DISPLAY=${WAYLAND_DISPLAY:-}"
echo "DISPLAY=${DISPLAY:-}"
echo

echo "==================== HARDWARE ===================="
lscpu | sed -n '1,20p' || true
echo
lsblk -o NAME,SIZE,FSTYPE,LABEL,MOUNTPOINTS || true
echo
lspci 2>/dev/null | grep -Ei \
'VGA|3D|Display|Audio|Network|Ethernet|Wireless|USB controller' || true
echo

echo "==================== MANUAL APT PACKAGES ===================="
apt-mark showmanual 2>/dev/null | sort || true
echo

echo "==================== INSTALLED Niveth/DEVELOPMENT PACKAGES ===================="
dpkg-query -W -f='${binary:Package}\t${Version}\t${db:Status-Status}\n' 2>/dev/null |
grep -Ei \
'niveth|kitty|vivaldi|gtk|glib|adwaita|gnome|wayland|xwayland|hypr|waybar|wofi|thunar|gvfs|portal|polkit|network-manager|pipewire|wireplumber|okular|qt|python3|pygobject|pyqt|flatpak|calamares|git|meson|ninja|xorriso|debootstrap|squashfs|grub|nvidia' |
sort || true
echo

echo "==================== SNAP ===================="
snap list 2>/dev/null || true
echo

echo "==================== FLATPAK ===================="
flatpak list --app --columns=application,name,version,branch,origin 2>/dev/null || true
echo

echo "==================== DESKTOP FILES ===================="
find "$HOME/.local/share/applications" \
     /usr/share/applications \
     -maxdepth 1 \
     -type f \
     -name '*.desktop' \
     -printf '%p\n' 2>/dev/null |
sort |
grep -Ei \
'vivaldi|kitty|niveth|okular|notes|files|app-center|ptyxis|chrome|firefox|browser' || true
echo

echo "==================== GNOME EXTENSIONS ===================="
gnome-extensions list 2>/dev/null | sort || true
echo
gnome-extensions list --enabled 2>/dev/null | sort | sed 's/^/ENABLED: /' || true
echo

echo "==================== GNOME EXTENSION DIRECTORIES ===================="
find "$HOME/.local/share/gnome-shell/extensions" \
     "$HOME/.local/share/gnome-shell" \
     -maxdepth 2 \
     -type d \
     -iname '*niveth*' \
     -print 2>/dev/null |
sort || true
echo

echo "==================== Niveth USER BIN ===================="
find "$HOME/.local/bin" \
     -maxdepth 1 \
     -type f \
     -printf '%f\n' 2>/dev/null |
sort |
grep -Ei 'niveth|kitty|wallpaper|post-install' || true
echo

echo "==================== Niveth USER DATA ===================="
find "$HOME/.local/share" \
     -maxdepth 2 \
     -type d \
     -iname '*niveth*' \
     -print 2>/dev/null |
sort || true
echo

echo "==================== Niveth CONFIG ===================="
find "$HOME/.config" \
     -maxdepth 3 \
     \( -iname '*niveth*' -o -path '*/kitty/*' \) \
     -type f \
     -printf '%p\n' 2>/dev/null |
sort || true
echo

echo "==================== KITTY ===================="
command -v kitty 2>/dev/null || true
command -v kitten 2>/dev/null || true
kitty --version 2>/dev/null || true
echo
echo "--- kitty.conf relevant lines ---"
grep -nE \
'allow_remote_control|listen_on|niveth-context-menu|mouse_map.*right' \
"$HOME/.config/kitty/kitty.conf" 2>/dev/null || true
echo

echo "==================== Niveth TERMINAL ===================="
echo "--- script ---"
ls -lh "$HOME/.config/kitty/niveth-context-menu.py" 2>/dev/null || true
python3 -m py_compile "$HOME/.config/kitty/niveth-context-menu.py" \
    2>/dev/null && echo "syntax: OK" || echo "syntax: FAILED"
echo

echo "--- terminal launcher ---"
ls -lh \
"$HOME/.local/bin/niveth-terminal" \
"$HOME/.local/share/applications/niveth-terminal.desktop" \
2>/dev/null || true
echo

echo "==================== Niveth APPS ===================="
for p in \
    "$HOME/Niveth-Files" \
    "$HOME/.local/share/niveth-files" \
    "$HOME/.local/share/niveth-notes" \
    "$HOME/.local/share/niveth-app-center" \
    "$HOME/.local/share/niveth"
do
    echo
    echo "### $p"
    if [ -e "$p" ]; then
        du -sh "$p" 2>/dev/null || true
        find "$p" -maxdepth 2 -type f -printf '%p\n' 2>/dev/null |
        sort | head -100
    else
        echo "NOT FOUND"
    fi
done
echo

echo "==================== WALLPAPERS ===================="
for p in \
    "$HOME/.local/share/niveth/wallpapers" \
    "$HOME/Pictures/niveth wallpapers" \
    "$HOME/.config/variety" \
    "$HOME/.local/bin/niveth-wallpaper-chooser.py" \
    "$HOME/.local/bin/niveth-wallpaper-time.py"
do
    echo
    echo "### $p"
    if [ -e "$p" ]; then
        du -sh "$p" 2>/dev/null || true
        find "$p" -maxdepth 2 -type f -printf '%p\n' 2>/dev/null |
        sort | head -150
    else
        echo "NOT FOUND"
    fi
done
echo

echo "==================== VIVALDI ===================="
dpkg-query -W -f='${binary:Package}\t${Version}\t${db:Status-Status}\n' \
    vivaldi-stable 2>/dev/null || true
echo
find "$HOME/.config/vivaldi" \
     "$HOME/Documents/vivaldi themes" \
     -maxdepth 3 \
     -type f \
     -printf '%p\n' 2>/dev/null |
sort |
grep -Ei 'Niveth|theme|Preference|vivaldi' |
head -200 || true
echo

echo "==================== CUSTOM SYSTEMD USER SERVICES ===================="
systemctl --user list-unit-files --type=service 2>/dev/null |
grep -Ei 'niveth|kitty|wallpaper|theme' || true
echo
systemctl --user list-timers --all 2>/dev/null |
grep -Ei 'niveth|kitty|wallpaper|theme' || true
echo

echo "==================== FONTS ===================="
fc-list : family 2>/dev/null |
sort -u |
grep -Ei 'Noto|DejaVu|Noto Color|Ubuntu|Yaru' |
head -100 || true
echo

echo "==================== GRAPHICS / NVIDIA ===================="
command -v nvidia-smi >/dev/null 2>&1 && nvidia-smi || true
echo
dpkg-query -W -f='${binary:Package}\t${Version}\n' 2>/dev/null |
grep -Ei '^nvidia|^libnvidia|^mesa' |
sort || true
echo

echo "==================== AUDIO ===================="
dpkg-query -W -f='${binary:Package}\t${Version}\n' 2>/dev/null |
grep -Ei 'pipewire|wireplumber|pulseaudio|alsa' |
sort || true
echo

echo "==================== NETWORK ===================="
dpkg-query -W -f='${binary:Package}\t${Version}\n' 2>/dev/null |
grep -Ei 'network-manager|network-manager-gnome|wpasupplicant|bluez' |
sort || true
echo

echo "==================== PORTALS ===================="
dpkg-query -W -f='${binary:Package}\t${Version}\n' 2>/dev/null |
grep -Ei 'xdg-desktop-portal' |
sort || true
echo

echo "==================== CURRENT SERVICES ===================="
systemctl --type=service --state=running 2>/dev/null |
grep -Ei 'NetworkManager|gdm|pipewire|wireplumber|bluetooth|cups' || true
echo

echo "==================== DISK USAGE ===================="
df -h / "$HOME"
echo

echo "==================== Niveth SNAPSHOT ===================="
if [ -d "$HOME/Niveth-desktop-snapshot-20260919" ]; then
    du -sh "$HOME/Niveth-desktop-snapshot-20260919"
    find "$HOME/Niveth-desktop-snapshot-20260919" -maxdepth 2 \
        -type f -printf '%p\n' 2>/dev/null |
    sort | head -150
fi
echo

echo "==================== END ===================="
} | tee "$OUT"

echo
echo "Inventory saved to:"
echo "$OUT"
