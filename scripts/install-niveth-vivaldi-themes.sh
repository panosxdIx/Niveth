#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC_ROOT="$PROJECT_ROOT"
THEME_ROOT="$SRC_ROOT/desktop/defaults/vivaldi"
LIGHT_DIR="$THEME_ROOT/Niveth-Light"
DARK_DIR="$THEME_ROOT/Niveth-Dark"
LIGHT_JSON="$LIGHT_DIR/settings.json"
DARK_JSON="$DARK_DIR/settings.json"
WRAPPER="$THEME_ROOT/niveth-vivaldi"
DESKTOP="$THEME_ROOT/vivaldi-stable.desktop"
MANIFEST="$SRC_ROOT/desktop/niveth-components.txt"
ROOTFS="$SRC_ROOT/build/rootfs"

LIGHT_ID="cc676bd6-bb1a-4199-a3da-27484f7ced13"
DARK_ID="cc134c1f-b0d6-43b4-9e25-af813f93de5b"

mkdir -p "$LIGHT_DIR" "$DARK_DIR"

cat > "$LIGHT_JSON" <<'JSON'
{
  "accentFromPage": false,
  "accentOnWindow": false,
  "accentSaturationLimit": 1,
  "alpha": 0.84,
  "backgroundImage": "",
  "backgroundPosition": "stretch",
  "blur": 10,
  "colorAccentBg": "#6F8FA8",
  "colorBg": "#F7F9FC",
  "colorFg": "#263442",
  "colorHighlightBg": "#E8EEF4",
  "colorWindowBg": "#F1F4F8",
  "contrast": 0,
  "defaultBackground": "#F7F9FC",
  "dimBlurred": true,
  "engineVersion": 1,
  "id": "cc676bd6-bb1a-4199-a3da-27484f7ced13",
  "name": "Niveth Light",
  "preferSystemAccent": false,
  "radius": 14,
  "simpleScrollbar": true,
  "transparencyTabBar": true,
  "transparencyTabs": true,
  "url": "",
  "version": 1
}
JSON

cat > "$DARK_JSON" <<'JSON'
{
  "accentFromPage": false,
  "accentOnWindow": false,
  "accentSaturationLimit": 1,
  "alpha": 0.84,
  "backgroundImage": "",
  "backgroundPosition": "stretch",
  "blur": 10,
  "colorAccentBg": "#7F9DB8",
  "colorBg": "#182433",
  "colorFg": "#E7EDF4",
  "colorHighlightBg": "#243447",
  "colorWindowBg": "#141E2A",
  "contrast": 0,
  "defaultBackground": "#182433",
  "dimBlurred": true,
  "engineVersion": 1,
  "id": "cc134c1f-b0d6-43b4-9e25-af813f93de5b",
  "name": "Niveth Dark",
  "preferSystemAccent": false,
  "radius": 14,
  "simpleScrollbar": true,
  "transparencyTabBar": true,
  "transparencyTabs": true,
  "url": "",
  "version": 1
}
JSON

python3 - "$LIGHT_JSON" "$DARK_JSON" <<'PY'
import json
import sys
from pathlib import Path

expected = {
    sys.argv[1]: "cc676bd6-bb1a-4199-a3da-27484f7ced13",
    sys.argv[2]: "cc134c1f-b0d6-43b4-9e25-af813f93de5b",
}
for filename, expected_id in expected.items():
    data = json.loads(Path(filename).read_text())
    if data.get("id") != expected_id:
        raise SystemExit(f"ERROR: unexpected theme id in {filename}")
    if data.get("name") not in {"Niveth Light", "Niveth Dark"}:
        raise SystemExit(f"ERROR: unexpected theme name in {filename}")
print("[PASS] Niveth Light/Dark settings JSON validated")
PY

cat > "$WRAPPER" <<'EOF_WRAPPER'
#!/usr/bin/env bash
set -euo pipefail

REAL_VIVALDI="/usr/bin/vivaldi-stable"
THEME_ROOT="/etc/niveth/vivaldi"
LIGHT_JSON="$THEME_ROOT/Niveth-Light/settings.json"
DARK_JSON="$THEME_ROOT/Niveth-Dark/settings.json"
PREFS="$HOME/.config/vivaldi/Default/Preferences"
LOCK_FILE="$HOME/.config/vivaldi/.niveth-theme-seed.lock"

mkdir -p "$(dirname "$PREFS")"

if command -v flock >/dev/null 2>&1; then
    exec 9>"$LOCK_FILE"
    flock -x 9
fi

/usr/bin/python3 - "$LIGHT_JSON" "$DARK_JSON" "$PREFS" <<'PY'
import json
import os
import sys
from pathlib import Path

light_file = Path(sys.argv[1])
dark_file = Path(sys.argv[2])
prefs_file = Path(sys.argv[3])

LIGHT_ID = "cc676bd6-bb1a-4199-a3da-27484f7ced13"
DARK_ID = "cc134c1f-b0d6-43b4-9e25-af813f93de5b"
SEED_VERSION = 1

light = json.loads(light_file.read_text())
dark = json.loads(dark_file.read_text())

if not prefs_file.exists():
    prefs = {}
else:
    try:
        prefs = json.loads(prefs_file.read_text())
    except Exception:
        # Do not destroy an unreadable Vivaldi profile.
        raise SystemExit(0)

vivaldi = prefs.setdefault("vivaldi", {})
themes = vivaldi.setdefault("themes", {})
user_themes = themes.setdefault("user", [])
if not isinstance(user_themes, list):
    user_themes = []

expected_schedule = {
    "enabled": 2,
    "o_s": {
        "dark": DARK_ID,
        "light": LIGHT_ID,
    },
    "timeline": [
        {"hours": 7, "id": 0, "minutes": 0, "themeId": LIGHT_ID, "undeletable": True},
        {"hours": 19, "id": 1, "minutes": 0, "themeId": DARK_ID, "undeletable": True},
    ],
}

extensions_theme = prefs.setdefault("extensions", {}).setdefault("theme", {})

already_seeded = (
    vivaldi.get("niveth_theme_seed_version") == SEED_VERSION
    and extensions_theme.get("system_theme") == 1
    and themes.get("schedule") == expected_schedule
    and any(isinstance(x, dict) and x.get("id") == LIGHT_ID for x in user_themes)
    and any(isinstance(x, dict) and x.get("id") == DARK_ID for x in user_themes)
)

if already_seeded:
    raise SystemExit(0)

# Replace/add only the two Niveth themes. All other user themes remain untouched.
merged = []
seen = set()
for item in user_themes:
    if not isinstance(item, dict):
        merged.append(item)
        continue
    item_id = item.get("id")
    if item_id == LIGHT_ID:
        merged.append(light)
        seen.add(LIGHT_ID)
    elif item_id == DARK_ID:
        merged.append(dark)
        seen.add(DARK_ID)
    else:
        merged.append(item)
if LIGHT_ID not in seen:
    merged.append(light)
if DARK_ID not in seen:
    merged.append(dark)

themes["user"] = merged
themes["schedule"] = expected_schedule
extensions_theme["system_theme"] = 1
vivaldi["niveth_theme_seed_version"] = SEED_VERSION

prefs_file.parent.mkdir(parents=True, exist_ok=True)
tmp = prefs_file.with_suffix(".niveth-tmp")
tmp.write_text(json.dumps(prefs, ensure_ascii=False, separators=(",", ":")) + "\n")
os.replace(tmp, prefs_file)
PY

if [[ -x "$REAL_VIVALDI" ]]; then
    exec "$REAL_VIVALDI" --no-first-run "$@"
fi

exec /usr/bin/vivaldi-stable "$@"
EOF_WRAPPER
chmod 0755 "$WRAPPER"

# Start from the packaged desktop entry, then change only the launcher executable.
DESKTOP_SOURCE=""
for candidate in \
    "$ROOTFS/usr/share/applications/vivaldi-stable.desktop" \
    "/usr/share/applications/vivaldi-stable.desktop"; do
    if [[ -f "$candidate" ]]; then
        DESKTOP_SOURCE="$candidate"
        break
    fi
done

if [[ -z "$DESKTOP_SOURCE" ]]; then
    echo "ERROR: could not find vivaldi-stable.desktop" >&2
    echo "Checked:" >&2
    echo "  $ROOTFS/usr/share/applications/vivaldi-stable.desktop" >&2
    echo "  /usr/share/applications/vivaldi-stable.desktop" >&2
    exit 1
fi

cp -f "$DESKTOP_SOURCE" "$DESKTOP"
sed -E -i 's|^Exec=/usr/bin/vivaldi-stable(.*)$|Exec=/usr/local/bin/niveth-vivaldi\1|' "$DESKTOP"
sed -E -i 's|^Exec=/usr/bin/vivaldi(.*)$|Exec=/usr/local/bin/niveth-vivaldi\1|' "$DESKTOP"

if ! grep -q '^Exec=/usr/local/bin/niveth-vivaldi' "$DESKTOP"; then
    echo "ERROR: failed to patch Vivaldi desktop launcher" >&2
    exit 1
fi

# Keep the source manifest deterministic: remove prior Niveth Vivaldi integration lines, then add one set.
if [[ -f "$MANIFEST" ]]; then
    tmp_manifest="$(mktemp)"
    grep -vE 'desktop/defaults/vivaldi/|/etc/niveth/vivaldi/|/usr/local/bin/niveth-vivaldi|/usr/share/applications/vivaldi-stable.desktop' \
        "$MANIFEST" > "$tmp_manifest" || true
    mv "$tmp_manifest" "$MANIFEST"
else
    touch "$MANIFEST"
fi

cat >> "$MANIFEST" <<EOF_MANIFEST
COPY_FILE $THEME_ROOT/Niveth-Light/settings.json /etc/niveth/vivaldi/Niveth-Light/settings.json
COPY_FILE $THEME_ROOT/Niveth-Dark/settings.json /etc/niveth/vivaldi/Niveth-Dark/settings.json
COPY_FILE $THEME_ROOT/niveth-vivaldi /usr/local/bin/niveth-vivaldi
COPY_FILE $THEME_ROOT/vivaldi-stable.desktop /usr/share/applications/vivaldi-stable.desktop
EOF_MANIFEST

# Sync the current build rootfs too, so it can be tested before the final ISO build.
if [[ -d "$ROOTFS" ]]; then
    echo "[INFO] syncing Vivaldi integration into current rootfs..."
    sudo mkdir -p "$ROOTFS/etc/niveth/vivaldi/Niveth-Light" "$ROOTFS/etc/niveth/vivaldi/Niveth-Dark"
    sudo install -m 0644 "$LIGHT_JSON" "$ROOTFS/etc/niveth/vivaldi/Niveth-Light/settings.json"
    sudo install -m 0644 "$DARK_JSON" "$ROOTFS/etc/niveth/vivaldi/Niveth-Dark/settings.json"
    sudo install -m 0755 "$WRAPPER" "$ROOTFS/usr/local/bin/niveth-vivaldi"
    sudo install -m 0644 "$DESKTOP" "$ROOTFS/usr/share/applications/vivaldi-stable.desktop"

    if command -v update-desktop-database >/dev/null 2>&1 && [[ -d "$ROOTFS/usr/share/applications" ]]; then
        sudo update-desktop-database "$ROOTFS/usr/share/applications" >/dev/null 2>&1 || true
    elif [[ -x "$ROOTFS/usr/bin/update-desktop-database" ]]; then
        sudo chroot "$ROOTFS" /usr/bin/update-desktop-database /usr/share/applications >/dev/null 2>&1 || true
    fi
fi

echo
printf '%s\n' '=== Niveth Vivaldi themes ==='
printf 'Light: %s\n' "$LIGHT_JSON"
printf 'Dark : %s\n' "$DARK_JSON"
printf 'Wrap : %s\n' "$WRAPPER"
printf 'Desk : %s\n' "$DESKTOP"
printf 'Manifest: %s\n' "$MANIFEST"

echo
printf '%s\n' '=== Theme IDs ==='
grep -E '"(id|name)"' "$LIGHT_JSON"
grep -E '"(id|name)"' "$DARK_JSON"

echo
printf '%s\n' '=== Manifest entries ==='
grep -nE 'desktop/defaults/vivaldi/|/etc/niveth/vivaldi/|niveth-vivaldi|vivaldi-stable.desktop' "$MANIFEST"

if [[ -d "$ROOTFS" ]]; then
    echo
    printf '%s\n' '=== Rootfs verification ==='
    sudo test -f "$ROOTFS/etc/niveth/vivaldi/Niveth-Light/settings.json" && echo '[PASS] rootfs Niveth Light'
    sudo test -f "$ROOTFS/etc/niveth/vivaldi/Niveth-Dark/settings.json" && echo '[PASS] rootfs Niveth Dark'
    sudo test -x "$ROOTFS/usr/local/bin/niveth-vivaldi" && echo '[PASS] rootfs Vivaldi wrapper'
    sudo grep -q '^Exec=/usr/local/bin/niveth-vivaldi' "$ROOTFS/usr/share/applications/vivaldi-stable.desktop" && echo '[PASS] rootfs Vivaldi desktop launcher'
fi

echo
echo '[DONE] Vivaldi Niveth Light/Dark integration installed.'
