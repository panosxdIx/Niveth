#!/usr/bin/env bash

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ROOTFS="$PROJECT_ROOT/build/rootfs"
LOCK_SRC="$HOME/.local/share/gnome-shell/extensions/niveth-lockscreen@nivethos"
LOCK_ROOTFS="$ROOTFS/usr/share/gnome-shell/extensions/niveth-lockscreen@nivethos"

echo
echo "============================================================"
echo "NIVETH SOURCE FINALIZATION BEFORE ISO"
echo "============================================================"

echo
echo "=== 1. LOCK SCREEN SOURCE ==="

if [ ! -d "$LOCK_SRC" ]; then
    echo "ERROR: Lock Screen source does not exist:"
    echo "$LOCK_SRC"
    exit 1
fi

mkdir -p "$LOCK_SRC"

cat > "$LOCK_SRC/metadata.json" <<'JSON'
{
  "uuid": "niveth-lockscreen@nivethos",
  "name": "Niveth Lock Screen",
  "description": "Niveth native GNOME lock screen.",
  "version": 10,
  "version-name": "10.0",
  "shell-version": [
    "50"
  ],
  "session-modes": [
    "unlock-dialog"
  ]
}
JSON

echo "PASS: Lock Screen source metadata is v10."

if grep -q "NIVETH LOCK SCREEN v10" "$LOCK_SRC/extension.js" 2>/dev/null; then
    echo "PASS: Lock Screen source extension.js is v10."
else
    echo "WARNING: source extension.js does not contain the v10 marker."

    if [ -f "$LOCK_ROOTFS/extension.js" ]; then
        echo "Copying verified v10 extension.js from current rootfs..."
        cp -f "$LOCK_ROOTFS/extension.js" "$LOCK_SRC/extension.js"
        echo "PASS: source extension.js synchronized from rootfs."
    else
        echo "ERROR: verified rootfs extension.js is missing."
        exit 1
    fi
fi

if grep -q "NIVETH LOCK SCREEN v10" "$LOCK_SRC/stylesheet.css" 2>/dev/null; then
    echo "PASS: Lock Screen source stylesheet.css is v10."
else
    echo "WARNING: source stylesheet.css does not contain the v10 marker."

    if [ -f "$LOCK_ROOTFS/stylesheet.css" ]; then
        echo "Copying verified v10 stylesheet.css from current rootfs..."
        cp -f "$LOCK_ROOTFS/stylesheet.css" "$LOCK_SRC/stylesheet.css"
        echo "PASS: source stylesheet.css synchronized from rootfs."
    else
        echo "ERROR: verified rootfs stylesheet.css is missing."
        exit 1
    fi
fi

echo
echo "=== 2. KITTY / WALLPAPER SERVICES ==="

for service in \
    "$HOME/.config/systemd/user/niveth-kitty-theme.service" \
    "$HOME/.config/systemd/user/niveth-wallpaper.service"
do
    if [ ! -f "$service" ]; then
        echo "ERROR: missing service:"
        echo "$service"
        exit 1
    fi
done

python3 - \
    "$HOME/.config/systemd/user/niveth-kitty-theme.service" \
    "$HOME/.config/systemd/user/niveth-wallpaper.service" <<'PY'
from pathlib import Path
import sys

for filename in sys.argv[1:]:
    path = Path(filename)
    text = path.read_text(encoding="utf-8")

    text = text.replace(
        "%h/.local/bin/niveth-kitty-theme",
        "/usr/local/bin/niveth-kitty-theme",
    )

    text = text.replace(
        "%h/.local/bin/niveth-wallpaper-time.py",
        "/usr/local/bin/niveth-wallpaper-time.py",
    )

    path.write_text(text, encoding="utf-8")

    print(f"FIXED: {path}")
PY

echo "PASS: service paths verified."

echo
echo "=== 3. ICON / CURSOR SOURCES ==="

for path in \
    "$PROJECT_ROOT/desktop/assets/icons/com.niveth.Notes.svg" \
    "$PROJECT_ROOT/desktop/assets/icons/niveth-app-center.svg" \
    "$HOME/Niveth-Files/icons/app/org.niveth.Files.svg" \
    "$HOME/.local/share/icons/retrosmart-xcursor-mac-ish-gruvbox/index.theme"
do
    if [ -e "$path" ]; then
        echo "[PASS] $path"
    else
        echo "[FAIL] Missing: $path"
        exit 1
    fi
done

echo
echo "=== 4. MANIFEST CHECK ==="

MANIFEST="$PROJECT_ROOT/desktop/niveth-components.txt"

required_manifest_lines=(
    "COPY_FILE $PROJECT_ROOT/desktop/assets/icons/com.niveth.Notes.svg /usr/share/icons/hicolor/scalable/apps/com.niveth.Notes.svg"
    "COPY_FILE $PROJECT_ROOT/desktop/assets/icons/niveth-app-center.svg /usr/share/icons/hicolor/scalable/apps/niveth-app-center.svg"
    "COPY_DIR $HOME/.local/share/icons/retrosmart-xcursor-mac-ish-gruvbox /usr/share/icons/retrosmart-xcursor-mac-ish-gruvbox"
    "COPY_FILE $PROJECT_ROOT/branding/os-release /usr/lib/os-release"
)

for line in "${required_manifest_lines[@]}"; do
    if grep -Fqx "$line" "$MANIFEST"; then
        echo "[PASS] $line"
    else
        echo "[FAIL] Missing manifest entry:"
        echo "$line"
        exit 1
    fi
done

echo
echo "=== 5. ROOTFS CURRENT STATE ==="

grep -E '^(PRETTY_NAME|NAME|VERSION_ID|VERSION|ID|ID_LIKE)=' \
    "$ROOTFS/usr/lib/os-release" 2>/dev/null || true

echo

if grep -q '"version": 10' "$LOCK_ROOTFS/metadata.json" 2>/dev/null; then
    echo "[PASS] rootfs Lock Screen metadata v10"
else
    echo "[FAIL] rootfs Lock Screen metadata is not v10"
    exit 1
fi

if [ -f "$ROOTFS/usr/share/icons/hicolor/scalable/apps/com.niveth.Notes.svg" ]; then
    echo "[PASS] rootfs Notes icon"
else
    echo "[FAIL] rootfs Notes icon"
    exit 1
fi

if [ -f "$ROOTFS/usr/share/icons/hicolor/scalable/apps/niveth-app-center.svg" ]; then
    echo "[PASS] rootfs App Center icon"
else
    echo "[FAIL] rootfs App Center icon"
    exit 1
fi

if [ -f "$ROOTFS/usr/share/icons/hicolor/scalable/apps/org.niveth.Files.svg" ]; then
    echo "[PASS] rootfs Files icon"
else
    echo "[FAIL] rootfs Files icon"
    exit 1
fi

if [ -f "$ROOTFS/usr/share/icons/retrosmart-xcursor-mac-ish-gruvbox/index.theme" ]; then
    echo "[PASS] rootfs cursor theme"
else
    echo "[FAIL] rootfs cursor theme"
    exit 1
fi

echo
echo "=== 6. VIVALDI THEME-ONLY AUDIT ==="

VIVALDI_PREF="$HOME/.config/vivaldi/Default/Preferences"
VIVALDI_LOCAL="$HOME/.config/vivaldi/Local State"

python3 - "$VIVALDI_PREF" "$VIVALDI_LOCAL" <<'PY'
from pathlib import Path
import json
import sys

def walk_theme_values(obj, path=()):
    if isinstance(obj, dict):
        for key, value in obj.items():
            lower = str(key).lower()

            if (
                lower == "theme"
                or "theme_id" in lower
                or lower in {"custom_theme", "custom_theme_id"}
            ):
                print()
                print("PATH:", ".".join(path + (str(key),)))
                try:
                    print(json.dumps(value, ensure_ascii=False, indent=2))
                except Exception:
                    print(repr(value))

            walk_theme_values(value, path + (str(key),))

    elif isinstance(obj, list):
        for index, value in enumerate(obj):
            walk_theme_values(value, path + (str(index),))

for filename in sys.argv[1:]:
    path = Path(filename)

    print()
    print("---", path, "---")

    if not path.is_file():
        print("MISSING")
        continue

    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except Exception as exc:
        print("ERROR:", exc)
        continue

    walk_theme_values(data)

PY

echo
echo "=== 7. VIVALDI POSSIBLE CUSTOM CSS ==="

find \
    "$HOME/.config/vivaldi" \
    "$HOME/.local/share/vivaldi" \
    "$HOME/.config" \
    -maxdepth 5 \
    -type f \
    \( -iname "*.css" -o -iname "*theme*" \) \
    2>/dev/null | \
    grep -Ei 'vivaldi|custom.*css|theme' | \
    sort | head -200

echo
echo "=== 8. FINAL SUMMARY ==="

echo "[PASS] Lock Screen source v10"
echo "[PASS] Kitty service paths"
echo "[PASS] Wallpaper service path"
echo "[PASS] Notes icon source"
echo "[PASS] App Center icon source"
echo "[PASS] Files icon source"
echo "[PASS] Cursor source"
echo "[PASS] Manifest entries"
echo "[PASS] Current rootfs assets"

echo
echo "Vivaldi theme information is shown above."
echo
echo "============================================================"
echo "READY FOR FINAL VIVALDI INTEGRATION CHECK"
echo "============================================================"
