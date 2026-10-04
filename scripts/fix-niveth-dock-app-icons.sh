#!/usr/bin/env bash

set -euo pipefail

PROJECT_ROOT="$HOME/Niveth"

DOCK_DIR="$HOME/.local/share/gnome-shell/extensions/niveth-dock@nivethos"

DOCK_JS="$DOCK_DIR/extension.js"
DOCK_CSS="$DOCK_DIR/stylesheet.css"

ROOTFS_DIR="$PROJECT_ROOT/build/rootfs/usr/share/gnome-shell/extensions/niveth-dock@nivethos"
ROOTFS_JS="$ROOTFS_DIR/extension.js"
ROOTFS_CSS="$ROOTFS_DIR/stylesheet.css"

BACKUP_DIR="$PROJECT_ROOT/integration-backups/niveth-dock-icons-$(date +%Y%m%d-%H%M%S)"

echo "============================================================"
echo " NIVETH DOCK - APPLICATION ICON FIX"
echo "============================================================"
echo

for f in "$DOCK_JS" "$DOCK_CSS" "$ROOTFS_JS" "$ROOTFS_CSS"; do
    if [[ ! -f "$f" ]]; then
        echo "[ERROR] Missing:"
        echo "        $f"
        exit 1
    fi
done

mkdir -p "$BACKUP_DIR"

cp "$DOCK_JS" "$BACKUP_DIR/extension.js.before"
cp "$DOCK_CSS" "$BACKUP_DIR/stylesheet.css.before"

sudo cp "$ROOTFS_JS" "$BACKUP_DIR/rootfs-extension.js.before"
sudo cp "$ROOTFS_CSS" "$BACKUP_DIR/rootfs-stylesheet.css.before"

echo "[PASS] Backups created:"
echo "       $BACKUP_DIR"

echo
echo "=== 1. REPLACE APPLICATION ICON CREATION ==="

python3 - "$DOCK_JS" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")

start_marker = "    _createIcon() {\n"
end_marker = "    setRunning(running) {\n"

start = text.find(start_marker)
end = text.find(end_marker, start)

if start == -1:
    raise SystemExit(
        "ERROR: _createIcon() not found."
    )

if end == -1:
    raise SystemExit(
        "ERROR: setRunning() anchor not found."
    )

replacement = '''    _createIcon() {
        try {
            const appInfo =
                this.app.get_app_info?.();

            const gicon =
                appInfo?.get_icon?.();

            if (gicon) {
                return new St.Icon({
                    gicon,
                    icon_size: ICON_SIZE,
                    style_class:
                        'niveth-dock-app-icon',
                });
            }
        } catch (error) {
            console.error(
                `Niveth Dock: application icon load failed for ${this.app.get_id()}: ${error}`
            );
        }

        try {
            const actor =
                this.app.create_icon_texture(
                    ICON_SIZE
                );

            if (actor) {
                actor.add_style_class_name?.(
                    'niveth-dock-app-icon'
                );

                return actor;
            }
        } catch (error) {
            console.error(
                `Niveth Dock: icon texture fallback failed for ${this.app.get_id()}: ${error}`
            );
        }

        return new St.Icon({
            icon_name:
                'application-x-executable-symbolic',
            icon_size: ICON_SIZE,
            style_class:
                'niveth-dock-app-icon',
        });
    }

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

print("[PASS] Application icon rendering replaced.")
PY

echo
echo "=== 2. IMPROVE ICON CSS ==="

if ! grep -q "NIVETH DOCK ICON VISIBILITY FIX" "$DOCK_CSS"; then
cat >> "$DOCK_CSS" <<'CSS'

/* ============================================================
   NIVETH DOCK ICON VISIBILITY FIX
   ============================================================ */

.niveth-dock-app-icon {
    width: 32px;
    height: 32px;
    min-width: 32px;
    min-height: 32px;
    opacity: 1.0;
}

CSS
fi

echo "[PASS] Icon CSS ready."

echo
echo "=== 3. VERIFY JAVASCRIPT ==="

gjs --check "$DOCK_JS"

echo "[PASS] GJS syntax"

echo
echo "=== 4. VERIFY ICON PATHS ==="

grep -q \
    "appInfo?.get_icon?.()" \
    "$DOCK_JS"

grep -q \
    "gicon," \
    "$DOCK_JS"

grep -q \
    "create_icon_texture" \
    "$DOCK_JS"

echo "[PASS] Direct Gio.Icon rendering"
echo "[PASS] create_icon_texture fallback"
echo "[PASS] Final symbolic fallback"

echo
echo "=== 5. SYNC ROOTFS ==="

sudo cp \
    "$DOCK_JS" \
    "$ROOTFS_JS"

sudo cp \
    "$DOCK_CSS" \
    "$ROOTFS_CSS"

sudo chown root:root \
    "$ROOTFS_JS" \
    "$ROOTFS_CSS"

sudo chmod 0644 \
    "$ROOTFS_JS" \
    "$ROOTFS_CSS"

echo "[PASS] Rootfs synchronized."

echo
echo "=== 6. VERIFY ROOTFS ==="

sudo gjs --check "$ROOTFS_JS"

sudo grep -q \
    "appInfo?.get_icon?.()" \
    "$ROOTFS_JS"

sudo grep -q \
    "NIVETH DOCK ICON VISIBILITY FIX" \
    "$ROOTFS_CSS"

echo "[PASS] Rootfs GJS syntax"
echo "[PASS] Rootfs Gio.Icon rendering"
echo "[PASS] Rootfs icon CSS"

echo
echo "=== 7. RESTART NIVETH DOCK ==="

gnome-extensions disable \
    niveth-dock@nivethos \
    2>/dev/null || true

sleep 2

gnome-extensions enable \
    niveth-dock@nivethos

sleep 3

echo "[PASS] Niveth Dock restarted."

echo
echo "=== 8. FINAL STATE ==="

gnome-extensions info \
    niveth-dock@nivethos \
    | grep -E 'Name|State|Path'

echo
echo "============================================================"
echo " NIVETH DOCK APPLICATION ICONS: FIXED"
echo "============================================================"
echo
echo "Primary icon source : Gio.Icon"
echo "Texture fallback    : create_icon_texture()"
echo "Final fallback      : symbolic application icon"
echo "Icon size           : 32x32"
echo "Rootfs              : UPDATED"
echo
echo "Backup:"
echo "  $BACKUP_DIR"
echo

