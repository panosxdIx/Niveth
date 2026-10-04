#!/usr/bin/env bash

set -euo pipefail

if [ -n "${SUDO_USER:-}" ]; then
    USER_NAME="$SUDO_USER"
    USER_HOME="$(getent passwd "$SUDO_USER" | cut -d: -f6)"
else
    USER_NAME="$USER"
    USER_HOME="$HOME"
fi

PROJECT_ROOT="$USER_HOME/Niveth"
ROOTFS="$PROJECT_ROOT/build/rootfs"
MANIFEST="$PROJECT_ROOT/desktop/niveth-components.txt"
BACKUP_ROOT="$PROJECT_ROOT/build/integration-backups/$(date +%Y%m%d-%H%M%S)"

ICON_SRC="$PROJECT_ROOT/desktop/assets/icons"
CURSOR_SRC="$USER_HOME/.local/share/icons/retrosmart-xcursor-mac-ish-gruvbox"

echo
echo "============================================================"
echo "NIVETH INTEGRATION REPAIR"
echo "============================================================"
echo
echo "User:        $USER_NAME"
echo "Home:        $USER_HOME"
echo "Project:     $PROJECT_ROOT"
echo "Rootfs:      $ROOTFS"
echo "Backup:      $BACKUP_ROOT"
echo

if [ ! -d "$ROOTFS" ]; then
    echo "ERROR: rootfs does not exist:"
    echo "$ROOTFS"
    exit 1
fi

mkdir -p "$BACKUP_ROOT"

backup_file() {
    local src="$1"

    if [ -e "$src" ]; then
        local rel="${src#$PROJECT_ROOT/}"
        mkdir -p "$BACKUP_ROOT/$(dirname "$rel")"
        cp -a "$src" "$BACKUP_ROOT/$rel"
    fi
}

echo "=== 1. Creating Niveth dock icons ==="

mkdir -p "$ICON_SRC"

cat > "$ICON_SRC/com.niveth.Notes.svg" <<'EOF_SVG'
<svg xmlns="http://www.w3.org/2000/svg"
     width="128" height="128" viewBox="0 0 128 128">
  <defs>
    <linearGradient id="bg" x1="0" y1="0" x2="1" y2="1">
      <stop offset="0" stop-color="#FFD86A"/>
      <stop offset="1" stop-color="#D99616"/>
    </linearGradient>
    <linearGradient id="paper" x1="0" y1="0" x2="0.9" y2="1">
      <stop offset="0" stop-color="#FFFDF4"/>
      <stop offset="1" stop-color="#F5E9C8"/>
    </linearGradient>
    <filter id="shadow" x="-30%" y="-30%" width="160%" height="160%">
      <feDropShadow dx="0" dy="5" stdDeviation="5"
                    flood-color="#17202B" flood-opacity=".28"/>
    </filter>
  </defs>

  <rect x="7" y="7" width="114" height="114" rx="28"
        fill="url(#bg)"/>

  <path d="M31 25
           H84
           L98 39
           V96
           C98 101 94 105 89 105
           H39
           C34 105 30 101 30 96
           V34
           C30 29 34 25 39 25 Z"
        fill="url(#paper)"
        filter="url(#shadow)"/>

  <path d="M84 25 V40 H99"
        fill="#E5D5AE"/>

  <rect x="43" y="53" width="43" height="7" rx="3.5"
        fill="#C9952B"/>

  <rect x="43" y="69" width="34" height="7" rx="3.5"
        fill="#D8AE4C"/>

  <rect x="43" y="85" width="25" height="7" rx="3.5"
        fill="#E4C978"/>
</svg>
EOF_SVG

cat > "$ICON_SRC/niveth-app-center.svg" <<'EOF_SVG'
<svg xmlns="http://www.w3.org/2000/svg"
     width="128" height="128" viewBox="0 0 128 128">
  <defs>
    <linearGradient id="bg" x1="0" y1="0" x2="1" y2="1">
      <stop offset="0" stop-color="#4DC6C8"/>
      <stop offset="1" stop-color="#0A7D82"/>
    </linearGradient>
    <linearGradient id="bag" x1="0" y1="0" x2="0.8" y2="1">
      <stop offset="0" stop-color="#FFFFFF"/>
      <stop offset="1" stop-color="#DCEEEF"/>
    </linearGradient>
    <filter id="shadow" x="-30%" y="-30%" width="160%" height="160%">
      <feDropShadow dx="0" dy="5" stdDeviation="5"
                    flood-color="#102B30" flood-opacity=".30"/>
    </filter>
  </defs>

  <rect x="7" y="7" width="114" height="114" rx="28"
        fill="url(#bg)"/>

  <path d="M39 48
           H89
           L94 96
           C94.5 101 90.5 105 85.5 105
           H42.5
           C37.5 105 33.5 101 34 96
           Z"
        fill="url(#bag)"
        filter="url(#shadow)"/>

  <path d="M49 48
           V39
           C49 29 55 23 64 23
           C73 23 79 29 79 39
           V48"
        fill="none"
        stroke="#FFFFFF"
        stroke-width="8"
        stroke-linecap="round"/>

  <rect x="47" y="61" width="12" height="12" rx="3"
        fill="#209EA2"/>
  <rect x="63" y="61" width="12" height="12" rx="3"
        fill="#209EA2"/>
  <rect x="47" y="77" width="12" height="12" rx="3"
        fill="#209EA2"/>
  <rect x="63" y="77" width="12" height="12" rx="3"
        fill="#E7B847"/>
</svg>
EOF_SVG

echo "PASS: Niveth Notes icon created."
echo "PASS: Niveth App Center icon created."

echo
echo "=== 2. OS BRANDING SOURCE ==="

mkdir -p "$PROJECT_ROOT/branding"

cat > "$PROJECT_ROOT/branding/os-release" <<'EOF_OS'
PRETTY_NAME="Niveth Linux 0.1"
NAME="Niveth Linux"
VERSION_ID="0.1"
VERSION="0.1"
VERSION_CODENAME=resolute
ID=niveth
ID_LIKE=ubuntu
HOME_URL="https://www.nivethos.example/"
SUPPORT_URL="https://www.nivethos.example/"
BUG_REPORT_URL="https://www.nivethos.example/"
PRIVACY_POLICY_URL="https://www.nivethos.example/"
UBUNTU_CODENAME=resolute
LOGO=niveth-logo
EOF_OS

echo "PASS: Niveth os-release source created."

echo
echo "=== 3. CURSOR ==="

if [ ! -d "$CURSOR_SRC" ]; then
    echo "ERROR: cursor theme source missing:"
    echo "$CURSOR_SRC"
    exit 1
fi

mkdir -p "$ROOTFS/usr/share/icons/retrosmart-xcursor-mac-ish-gruvbox"
rm -rf "$ROOTFS/usr/share/icons/retrosmart-xcursor-mac-ish-gruvbox/"*
cp -a "$CURSOR_SRC/." \
      "$ROOTFS/usr/share/icons/retrosmart-xcursor-mac-ish-gruvbox/"

chown -R root:root \
    "$ROOTFS/usr/share/icons/retrosmart-xcursor-mac-ish-gruvbox"

echo "PASS: cursor theme copied to rootfs."

echo
echo "=== 4. ICONS INTO ROOTFS ==="

mkdir -p "$ROOTFS/usr/share/icons/hicolor/scalable/apps"

cp -f \
    "$ICON_SRC/com.niveth.Notes.svg" \
    "$ROOTFS/usr/share/icons/hicolor/scalable/apps/com.niveth.Notes.svg"

cp -f \
    "$ICON_SRC/niveth-app-center.svg" \
    "$ROOTFS/usr/share/icons/hicolor/scalable/apps/niveth-app-center.svg"

if [ -f "$USER_HOME/Niveth-Files/icons/app/org.niveth.Files.svg" ]; then
    cp -f \
        "$USER_HOME/Niveth-Files/icons/app/org.niveth.Files.svg" \
        "$ROOTFS/usr/share/icons/hicolor/scalable/apps/org.niveth.Files.svg"
fi

chown root:root \
    "$ROOTFS/usr/share/icons/hicolor/scalable/apps/com.niveth.Notes.svg" \
    "$ROOTFS/usr/share/icons/hicolor/scalable/apps/niveth-app-center.svg" \
    "$ROOTFS/usr/share/icons/hicolor/scalable/apps/org.niveth.Files.svg" 2>/dev/null || true

chmod 0644 \
    "$ROOTFS/usr/share/icons/hicolor/scalable/apps/"*.svg

echo "PASS: Niveth dock icons copied."

echo
echo "=== 5. KITTY CONFIG ==="

KITTY_DEFAULTS="$PROJECT_ROOT/desktop/defaults/kitty"
SKEL_KITTY="$ROOTFS/etc/skel/.config/kitty"

if [ -d "$KITTY_DEFAULTS" ]; then
    mkdir -p "$SKEL_KITTY"
    cp -a "$KITTY_DEFAULTS/." "$SKEL_KITTY/"
    chown -R root:root "$SKEL_KITTY"
    find "$SKEL_KITTY" -type f -exec chmod 0644 {} \;
    echo "PASS: Kitty config copied to /etc/skel."
else
    echo "WARNING: $KITTY_DEFAULTS does not exist."
fi

echo
echo "=== 6. FIXING KITTY / WALLPAPER SERVICE PATHS ==="

SERVICE_SEARCH_DIRS=(
    "$USER_HOME/.config/systemd/user"
    "$PROJECT_ROOT"
)

while IFS= read -r -d '' service_file; do
    backup_file "$service_file"

    sed -i \
        's#%h/\.local/bin/niveth-kitty-theme#/usr/local/bin/niveth-kitty-theme#g' \
        "$service_file"

    sed -i \
        's#%h/\.local/bin/niveth-wallpaper-time\.py#/usr/local/bin/niveth-wallpaper-time.py#g' \
        "$service_file"

    echo "FIXED: $service_file"
done < <(
    find "${SERVICE_SEARCH_DIRS[@]}" \
        -type f \
        \( \
            -name "niveth-kitty-theme.service" \
            -o -name "niveth-wallpaper.service" \
        \) \
        -print0 \
        2>/dev/null
)

mkdir -p "$ROOTFS/usr/lib/systemd/user"

for unit in \
    niveth-kitty-theme.service \
    niveth-wallpaper.service
do
    found=""

    for src in \
        "$USER_HOME/.config/systemd/user/$unit" \
        "$PROJECT_ROOT/desktop/defaults/systemd/$unit" \
        "$PROJECT_ROOT/desktop/systemd/$unit"
    do
        if [ -f "$src" ]; then
            found="$src"
            break
        fi
    done

    if [ -n "$found" ]; then
        cp -f "$found" "$ROOTFS/usr/lib/systemd/user/$unit"
        chmod 0644 "$ROOTFS/usr/lib/systemd/user/$unit"
        echo "Installed: $unit"
    fi
done

echo
echo "=== 7. PATCHING NIVETH FILES RIGHT-CLICK ==="

FILES_MAIN="$USER_HOME/Niveth-Files/main.py"

if [ ! -f "$FILES_MAIN" ]; then
    echo "ERROR: Niveth Files source not found:"
    echo "$FILES_MAIN"
    exit 1
fi

backup_file "$FILES_MAIN"

python3 - "$FILES_MAIN" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")

if "def _change_wallpaper_from_context(self):" not in text:
    if "import subprocess" not in text:
        lines = text.splitlines(True)

        insert_at = 0

        while insert_at < len(lines):
            stripped = lines[insert_at].strip()

            if stripped.startswith("#!") or stripped == "":
                insert_at += 1
                continue

            if stripped.startswith("from __future__"):
                insert_at += 1
                continue

            break

        lines.insert(insert_at, "import subprocess\n")
        text = "".join(lines)

    marker = "\n    def _context_item("
    method = '''
    def _change_wallpaper_from_context(self):
        chooser = "/usr/local/bin/niveth-wallpaper-chooser.py"

        try:
            subprocess.Popen(
                ["/usr/bin/python3", chooser],
                start_new_session=True,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
            )
        except Exception as exc:
            print(f"NIVETH: Could not open wallpaper chooser: {exc}")
'''

    if marker not in text:
        raise SystemExit("ERROR: could not find _context_item insertion point")

    text = text.replace(marker, method + marker, 1)

start = text.find("    def _show_background_context_menu(")
end = text.find("\n    def _context_item(", start)

if start == -1 or end == -1:
    raise SystemExit("ERROR: could not locate background context menu")

block = text[start:end]

if '"Change Wallpaper"' not in block:
    needle = '''        self._context_separator(content)

        self._context_item(
            content,
            "Select All",'''

    replacement = '''        self._context_separator(content)

        self._context_item(
            content,
            "Change Wallpaper",
            "preferences-desktop-wallpaper-symbolic",
            self._change_wallpaper_from_context,
        )

        self._context_separator(content)

        self._context_item(
            content,
            "Select All",'''

    if needle not in block:
        raise SystemExit(
            "ERROR: could not locate Select All section in background context menu"
        )

    block = block.replace(needle, replacement, 1)
    text = text[:start] + block + text[end:]

path.write_text(text, encoding="utf-8")
PY

cp -f \
    "$FILES_MAIN" \
    "$ROOTFS/usr/lib/niveth/apps/niveth-files/main.py"

chown root:root \
    "$ROOTFS/usr/lib/niveth/apps/niveth-files/main.py"

chmod 0644 \
    "$ROOTFS/usr/lib/niveth/apps/niveth-files/main.py"

echo "PASS: Niveth Files now has Change Wallpaper in background context menu."

echo
echo "=== 8. LOCK SCREEN METADATA ==="

LOCK_SOURCE="$PROJECT_ROOT/desktop/defaults/extensions/niveth-lockscreen@nivethos"
LOCK_ROOTFS="$ROOTFS/usr/share/gnome-shell/extensions/niveth-lockscreen@nivethos"

if [ -f "$LOCK_SOURCE/metadata.json" ]; then
    backup_file "$LOCK_SOURCE/metadata.json"

    python3 - "$LOCK_SOURCE/metadata.json" <<'PY'
from pathlib import Path
import json
import sys

path = Path(sys.argv[1])
data = json.loads(path.read_text(encoding="utf-8"))

data["version"] = 10
data["version-name"] = "10.0"

path.write_text(
    json.dumps(data, indent=2, ensure_ascii=False) + "\n",
    encoding="utf-8",
)
PY

    echo "PASS: Lock Screen source metadata set to v10."
fi

if [ -f "$LOCK_ROOTFS/metadata.json" ]; then
    python3 - "$LOCK_ROOTFS/metadata.json" <<'PY'
from pathlib import Path
import json
import sys

path = Path(sys.argv[1])
data = json.loads(path.read_text(encoding="utf-8"))

data["version"] = 10
data["version-name"] = "10.0"

path.write_text(
    json.dumps(data, indent=2, ensure_ascii=False) + "\n",
    encoding="utf-8",
)
PY

    echo "PASS: rootfs Lock Screen metadata set to v10."
fi

echo
echo "=== 9. DCONF EXTENSION DEFAULTS ==="

DCONF_DEFAULTS="$ROOTFS/etc/dconf/db/local.d/00-niveth-defaults"

if [ -f "$DCONF_DEFAULTS" ]; then
    backup_file "$DCONF_DEFAULTS"

    python3 - "$DCONF_DEFAULTS" <<'PY'
from pathlib import Path
import re
import sys

path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")

enabled = (
    "['ding@rastersoft.com', "
    "'tiling-assistant@ubuntu.com', "
    "'window-gap@amirhosseinkarimi.github.io', "
    "'rounded-windows@marcosgt.github.io', "
    "'niveth-dock@nivethos', "
    "'niveth-ui-test@nivethos', "
    "'niveth-lockscreen@nivethos']"
)

disabled = (
    "['niveth-topbar@nivethos', "
    "'ubuntu-dock@ubuntu.com', "
    "'niveth-app-refresh@nivethos']"
)

text, n1 = re.subn(
    r"^enabled-extensions=.*$",
    f"enabled-extensions={enabled}",
    text,
    flags=re.MULTILINE,
)

text, n2 = re.subn(
    r"^disabled-extensions=.*$",
    f"disabled-extensions={disabled}",
    text,
    flags=re.MULTILINE,
)

if n1 == 0 or n2 == 0:
    raise SystemExit("ERROR: extension defaults could not be located")

path.write_text(text, encoding="utf-8")
PY

    echo "PASS: dconf extension defaults repaired."
fi

echo
echo "=== 10. Niveth OS RELEASE IN ROOTFS ==="

cp -f \
    "$PROJECT_ROOT/branding/os-release" \
    "$ROOTFS/usr/lib/os-release"

if [ -L "$ROOTFS/etc/os-release" ]; then
    echo "Keeping /etc/os-release symlink."
else
    cp -f \
        "$PROJECT_ROOT/branding/os-release" \
        "$ROOTFS/etc/os-release"
fi

chmod 0644 \
    "$ROOTFS/usr/lib/os-release" \
    "$ROOTFS/etc/os-release" 2>/dev/null || true

echo "PASS: OS identity set to Niveth Linux 0.1."

echo
echo "=== 11. WALLPAPERS ==="

WALLPAPER_DIR="$ROOTFS/usr/share/niveth/wallpapers"

if [ -d "$WALLPAPER_DIR" ]; then
    chown -R root:root "$ROOTFS/usr/share/niveth"
    find "$ROOTFS/usr/share/niveth" \
        -type d \
        -exec chmod 0755 {} \;

    find "$ROOTFS/usr/share/niveth" \
        -type f \
        -exec chmod 0644 {} \;

    echo "Wallpaper count:"
    find "$WALLPAPER_DIR" -type f | wc -l
fi

echo
echo "=== 12. FIXING PROJECT COMPONENT MANIFEST ==="

if [ ! -f "$MANIFEST" ]; then
    echo "ERROR: manifest missing:"
    echo "$MANIFEST"
    exit 1
fi

ensure_manifest_line() {
    local line="$1"

    if ! grep -Fqx "$line" "$MANIFEST"; then
        printf '%s\n' "$line" >> "$MANIFEST"
        echo "ADDED: $line"
    else
        echo "EXISTS: $line"
    fi
}

backup_file "$MANIFEST"

ensure_manifest_line \
    "COPY_DIR $CURSOR_SRC /usr/share/icons/retrosmart-xcursor-mac-ish-gruvbox"

ensure_manifest_line \
    "COPY_FILE $ICON_SRC/com.niveth.Notes.svg /usr/share/icons/hicolor/scalable/apps/com.niveth.Notes.svg"

ensure_manifest_line \
    "COPY_FILE $ICON_SRC/niveth-app-center.svg /usr/share/icons/hicolor/scalable/apps/niveth-app-center.svg"

ensure_manifest_line \
    "COPY_FILE $PROJECT_ROOT/branding/os-release /usr/lib/os-release"

ensure_manifest_line \
    "COPY_DIR $KITTY_DEFAULTS /etc/skel/.config/kitty"

echo
echo "=== 13. ICON CACHE ==="

if chroot "$ROOTFS" gtk-update-icon-cache -f -t /usr/share/icons/hicolor >/dev/null 2>&1; then
    echo "PASS: hicolor icon cache updated."
else
    echo "WARNING: hicolor icon cache could not be regenerated."
fi

echo
echo "=== 14. DCONF COMPILE ==="

if chroot "$ROOTFS" dconf update >/dev/null 2>&1; then
    echo "PASS: dconf database rebuilt."
else
    echo "WARNING: dconf update failed."
fi

echo
echo "=== 15. DESKTOP DATABASE ==="

if chroot "$ROOTFS" update-desktop-database /usr/share/applications >/dev/null 2>&1; then
    echo "PASS: desktop database updated."
else
    echo "WARNING: update-desktop-database failed."
fi

echo
echo "=== 16. VERIFY ==="

echo
echo "--- OS release ---"
grep -E '^(PRETTY_NAME|NAME|VERSION_ID|VERSION|ID|ID_LIKE)=' \
    "$ROOTFS/usr/lib/os-release"

echo
echo "--- Dock icons ---"
for icon in \
    "$ROOTFS/usr/share/icons/hicolor/scalable/apps/com.niveth.Notes.svg" \
    "$ROOTFS/usr/share/icons/hicolor/scalable/apps/niveth-app-center.svg" \
    "$ROOTFS/usr/share/icons/hicolor/scalable/apps/org.niveth.Files.svg"
do
    if [ -f "$icon" ]; then
        echo "[PASS] $icon"
    else
        echo "[FAIL] $icon"
    fi
done

echo
echo "--- Cursor ---"
if [ -f "$ROOTFS/usr/share/icons/retrosmart-xcursor-mac-ish-gruvbox/index.theme" ]; then
    echo "[PASS] retrosmart cursor theme"
else
    echo "[FAIL] retrosmart cursor theme"
fi

echo
echo "--- Kitty ---"
grep -nE \
    'ExecStart=.*niveth-(kitty-theme|wallpaper-time)' \
    "$ROOTFS/usr/lib/systemd/user/"*.service \
    2>/dev/null || true

echo
echo "--- Change Wallpaper ---"
if grep -q '"Change Wallpaper"' \
    "$ROOTFS/usr/lib/niveth/apps/niveth-files/main.py"
then
    echo "[PASS] Change Wallpaper context menu entry"
else
    echo "[FAIL] Change Wallpaper context menu entry"
fi

echo
echo "--- Lock Screen ---"
cat "$ROOTFS/usr/share/gnome-shell/extensions/niveth-lockscreen@nivethos/metadata.json" \
    2>/dev/null | grep -E '"version"|"version-name"' || true

echo
echo "--- Dconf extensions ---"
grep -E '^(enabled-extensions|disabled-extensions)=' \
    "$DCONF_DEFAULTS" \
    2>/dev/null || true

echo
echo "============================================================"
echo "REPAIR COMPLETE"
echo "============================================================"
echo
echo "Backup:"
echo "$BACKUP_ROOT"
echo
