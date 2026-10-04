#!/usr/bin/env bash

set -euo pipefail

SOURCE_MAIN="$HOME/Niveth-Files/main.py"
SOURCE_CSS="$HOME/Niveth-Files/styles.css"

HOST_MAIN="/usr/lib/niveth/apps/niveth-files/main.py"
HOST_CSS="/usr/lib/niveth/apps/niveth-files/styles.css"

ROOTFS_MAIN="$HOME/Niveth/build/rootfs/usr/lib/niveth/apps/niveth-files/main.py"
ROOTFS_CSS="$HOME/Niveth/build/rootfs/usr/lib/niveth/apps/niveth-files/styles.css"

BACKUP_DIR="$HOME/Niveth/integration-backups/niveth-files-header-buttons-$(date +%Y%m%d-%H%M%S)"

mkdir -p "$BACKUP_DIR"

cp "$SOURCE_MAIN" "$BACKUP_DIR/source-main.py.before"
cp "$SOURCE_CSS" "$BACKUP_DIR/source-styles.css.before"

sudo cp "$HOST_MAIN" "$BACKUP_DIR/host-main.py.before"
sudo cp "$HOST_CSS" "$BACKUP_DIR/host-styles.css.before"

sudo cp "$ROOTFS_MAIN" "$BACKUP_DIR/rootfs-main.py.before"
sudo cp "$ROOTFS_CSS" "$BACKUP_DIR/rootfs-styles.css.before"

echo "[PASS] Backups created:"
echo "       $BACKUP_DIR"

echo
echo "=== 1. PATCH RUNTIME HEADER CSS ==="

python3 - "$SOURCE_MAIN" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")

dark_old = '''            .window-root.dark .context-menu {
                background: #1C2635;
                color: #DCE7F4;
                border-color: #34465E;
            }
'''

dark_new = '''            .window-root.dark .context-menu {
                background: #1C2635;
                color: #DCE7F4;
                border-color: #34465E;
            }

            .niveth-header.dark .toolbar-button,
            .niveth-header.dark .view-button {
                background: transparent;
                background-image: none;
                color: #CBD8E7;
                border: none;
                box-shadow: none;
            }

            .niveth-header.dark .toolbar-button:hover,
            .niveth-header.dark .view-button:hover {
                background: rgba(127, 157, 184, 0.16);
            }

            .niveth-header.dark .toolbar-button:active,
            .niveth-header.dark .view-button:active {
                background: rgba(127, 157, 184, 0.22);
            }
'''

if dark_old not in text:
    raise SystemExit(
        "ERROR: Dark runtime CSS anchor not found."
    )

text = text.replace(dark_old, dark_new, 1)

light_old = '''            .window-root.light .context-menu {
                background: #FFFDF9;
                color: #29415D;
                border-color: #D7D0C5;
            }
'''

light_new = '''            .window-root.light .context-menu {
                background: #FFFDF9;
                color: #29415D;
                border-color: #D7D0C5;
            }

            .niveth-header.light .toolbar-button,
            .niveth-header.light .view-button {
                background: transparent;
                background-image: none;
                color: #496173;
                border: none;
                box-shadow: none;
            }

            .niveth-header.light .toolbar-button:hover,
            .niveth-header.light .view-button:hover {
                background: rgba(110, 151, 184, 0.12);
            }

            .niveth-header.light .toolbar-button:active,
            .niveth-header.light .view-button:active {
                background: rgba(110, 151, 184, 0.18);
            }
'''

if light_old not in text:
    raise SystemExit(
        "ERROR: Light runtime CSS anchor not found."
    )

text = text.replace(light_old, light_new, 1)

path.write_text(text, encoding="utf-8")

print("[PASS] Runtime Header button styling added.")
PY

echo
echo "=== 2. PATCH STYLES.CSS ==="

if ! grep -q "NIVETH HEADER BUTTON BACKGROUND FIX" "$SOURCE_CSS"; then
cat >> "$SOURCE_CSS" <<'CSS'

/* ============================================================
   NIVETH HEADER BUTTON BACKGROUND FIX
   ============================================================ */

.niveth-header .toolbar-button,
.niveth-header .view-button {
    background: transparent;
    background-image: none;
    border: none;
    box-shadow: none;
}

.niveth-header.dark .toolbar-button,
.niveth-header.dark .view-button {
    color: #CBD8E7;
}

.niveth-header.dark .toolbar-button:hover,
.niveth-header.dark .view-button:hover {
    background: rgba(127, 157, 184, 0.16);
}

.niveth-header.dark .toolbar-button:active,
.niveth-header.dark .view-button:active {
    background: rgba(127, 157, 184, 0.22);
}

.niveth-header.light .toolbar-button,
.niveth-header.light .view-button {
    color: #496173;
}

.niveth-header.light .toolbar-button:hover,
.niveth-header.light .view-button:hover {
    background: rgba(110, 151, 184, 0.12);
}

.niveth-header.light .toolbar-button:active,
.niveth-header.light .view-button:active {
    background: rgba(110, 151, 184, 0.18);
}

CSS
fi

echo "[PASS] styles.css updated."

echo
echo "=== 3. VERIFY SOURCE ==="

python3 - <<'PY'
from pathlib import Path

p = Path.home() / "Niveth-Files/main.py"
text = p.read_text(encoding="utf-8")
compile(text, str(p), "exec")

assert ".niveth-header.dark .toolbar-button" in text
assert ".niveth-header.light .toolbar-button" in text

print("[PASS] Source syntax")
print("[PASS] Runtime header button CSS")
PY

echo
echo "=== 4. SYNC HOST ==="

sudo cp "$SOURCE_MAIN" "$HOST_MAIN"
sudo cp "$SOURCE_CSS" "$HOST_CSS"

sudo rm -rf \
    /usr/lib/niveth/apps/niveth-files/__pycache__

echo "[PASS] Installed host copy synchronized."

echo
echo "=== 5. SYNC ROOTFS ==="

sudo cp "$SOURCE_MAIN" "$ROOTFS_MAIN"
sudo cp "$SOURCE_CSS" "$ROOTFS_CSS"

sudo rm -rf \
    "$HOME/Niveth/build/rootfs/usr/lib/niveth/apps/niveth-files/__pycache__"

echo "[PASS] Rootfs synchronized."

echo
echo "=== 6. FINAL VERIFY ==="

python3 - <<'PY'
from pathlib import Path

checks = [
    (
        "Host",
        Path("/usr/lib/niveth/apps/niveth-files/main.py"),
        Path("/usr/lib/niveth/apps/niveth-files/styles.css"),
    ),
    (
        "Rootfs",
        Path.home() / "Niveth/build/rootfs/usr/lib/niveth/apps/niveth-files/main.py",
        Path.home() / "Niveth/build/rootfs/usr/lib/niveth/apps/niveth-files/styles.css",
    ),
]

for label, main, css in checks:
    main_text = main.read_text(encoding="utf-8")
    css_text = css.read_text(encoding="utf-8")

    compile(main_text, str(main), "exec")

    if ".niveth-header.dark .toolbar-button" not in main_text:
        raise SystemExit(f"ERROR: {label} runtime CSS missing.")

    if "NIVETH HEADER BUTTON BACKGROUND FIX" not in css_text:
        raise SystemExit(f"ERROR: {label} CSS fix missing.")

    print(f"[PASS] {label}")

print()
print("============================================================")
print(" NIVETH FILES HEADER BUTTONS: FIXED")
print("============================================================")
PY

echo
echo "Backup:"
echo "  $BACKUP_DIR"
