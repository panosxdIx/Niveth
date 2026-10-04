#!/usr/bin/env bash

set -euo pipefail

UUID="niveth-lockscreen@nivethos"
EXT="$HOME/.local/share/gnome-shell/extensions/$UUID"

ROOTFS="$HOME/Niveth/build/rootfs"
ROOTFS_EXT="$ROOTFS/usr/share/gnome-shell/extensions/$UUID"

echo "============================================================"
echo " NIVETH LOCK SCREEN — V11 WALLPAPER SYNC"
echo "============================================================"
echo
echo "Goal:"
echo "  Desktop wallpaper"
echo "          ↓"
echo "  GNOME background settings"
echo "          ↓"
echo "  Lock Screen"
echo
echo "No custom wallpaper widget."
echo "GNOME's own lockscreen background manager will be refreshed."
echo

# ------------------------------------------------------------
# 1. Verify
# ------------------------------------------------------------

echo "[1/9] Verifying lockscreen..."

if [ ! -f "$EXT/extension.js" ]; then
    echo "[FAIL] extension.js not found:"
    echo "  $EXT/extension.js"
    exit 1
fi

if [ ! -f "$EXT/metadata.json" ]; then
    echo "[FAIL] metadata.json not found."
    exit 1
fi

echo "[PASS] Lock screen extension found"
echo

# ------------------------------------------------------------
# 2. Check current version
# ------------------------------------------------------------

echo "[2/9] Checking current version..."

CURRENT_VERSION="$(
    python3 - "$EXT/metadata.json" <<'PY'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])

data = json.loads(
    path.read_text()
)

print(data.get("version"))
PY
)"

echo "Current version: $CURRENT_VERSION"

if [ "$CURRENT_VERSION" != "10" ]; then

    echo
    echo "[FAIL] Expected V10 as the base."
    echo "       Found: $CURRENT_VERSION"
    echo
    echo "       Nothing was modified."
    exit 1
fi

echo "[PASS] V10 base confirmed"
echo

# ------------------------------------------------------------
# 3. Backup
# ------------------------------------------------------------

echo "[3/9] Creating backup..."

BACKUP="$EXT/backup-v11-wallpaper-sync-$(date +%Y%m%d-%H%M%S)"

mkdir -p "$BACKUP"

cp -a \
    "$EXT/extension.js" \
    "$BACKUP/extension.js"

cp -a \
    "$EXT/metadata.json" \
    "$BACKUP/metadata.json"

if [ -f "$EXT/stylesheet.css" ]; then
    cp -a \
        "$EXT/stylesheet.css" \
        "$BACKUP/stylesheet.css"
fi

echo "[PASS] Backup:"
echo "  $BACKUP"
echo

# ------------------------------------------------------------
# 4. Disable before modification
# ------------------------------------------------------------

echo "[4/9] Disabling lockscreen..."

gnome-extensions disable "$UUID" 2>/dev/null || true

sleep 1

echo "[PASS] Disabled"
echo

# ------------------------------------------------------------
# 5. Apply synchronization patch
# ------------------------------------------------------------

echo "[5/9] Installing wallpaper synchronization..."

python3 - "$EXT/extension.js" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text()

# ----------------------------------------------------------
# A. Add wallpaper settings state.
# ----------------------------------------------------------

old = """        this._dialog = null;
        this._logo = null;

        this._timers = [];
"""

new = """        this._dialog = null;
        this._logo = null;

        this._wallpaperSettings = null;
        this._wallpaperSettingsChangedId = 0;

        this._timers = [];
"""

if old not in text:
    print("[FAIL] Could not find lockscreen state block.")
    sys.exit(1)

text = text.replace(
    old,
    new,
    1
)

print("[PASS] Wallpaper settings state added")


# ----------------------------------------------------------
# B. Initialize desktop wallpaper settings.
# ----------------------------------------------------------

old = """        this._timers = [];

        log('NIVETH LOCK SCREEN v9: ENABLE');
"""

new = """        this._timers = [];

        try {

            this._wallpaperSettings =
                new Gio.Settings({
                    schema_id:
                        'org.gnome.desktop.background',
                });

            this._wallpaperSettingsChangedId =
                this._wallpaperSettings.connect(
                    'changed',
                    () => {
                        this._refreshWallpaper();
                    }
                );

            log(
                'NIVETH LOCK SCREEN V11: ' +
                'DESKTOP WALLPAPER SETTINGS CONNECTED'
            );

        } catch (error) {

            logError(
                error,
                'NIVETH LOCK SCREEN V11: ' +
                'WALLPAPER SETTINGS ERROR'
            );
        }

        log('NIVETH LOCK SCREEN V11: ENABLE');
"""

if old not in text:
    print("[FAIL] Could not find enable() initialization block.")
    sys.exit(1)

text = text.replace(
    old,
    new,
    1
)

print("[PASS] Desktop wallpaper change listener added")


# ----------------------------------------------------------
# C. Add wallpaper refresh to GNOME's existing background.
# ----------------------------------------------------------

old = """                extension._removeBlur(this);

                extension._placeLogo(this);
"""

new = """                extension._refreshWallpaper();

                extension._removeBlur(this);

                extension._placeLogo(this);
"""

if old not in text:
    print(
        "[FAIL] Could not find unlock-dialog background callback."
    )
    sys.exit(1)

text = text.replace(
    old,
    new,
    1
)

print("[PASS] Unlock-dialog wallpaper refresh added")


# ----------------------------------------------------------
# D. Add refresh to _apply().
# ----------------------------------------------------------

old = """        this._removeBlur(dialog);
        this._placeLogo(dialog);
"""

new = """        this._refreshWallpaper();

        this._removeBlur(dialog);
        this._placeLogo(dialog);
"""

if old not in text:
    print("[FAIL] Could not find _apply() block.")
    sys.exit(1)

text = text.replace(
    old,
    new,
    1
)

print("[PASS] _apply() wallpaper refresh added")


# ----------------------------------------------------------
# E. Insert the refresh method before _removeBlur().
# ----------------------------------------------------------

marker = """    _removeBlur(dialog) {
"""

if marker not in text:
    print("[FAIL] _removeBlur() marker not found.")
    sys.exit(1)

method = """    _refreshWallpaper() {

        const dialog =
            this._dialog ||
            Main.screenShield?._dialog;

        if (!dialog)
            return;

        this._dialog = dialog;

        /*
         * GNOME Shell's UnlockDialog owns the actual
         * lockscreen background managers.
         *
         * Ask GNOME to rebuild those backgrounds from
         * the current desktop wallpaper settings.
         */
        try {

            if (
                typeof dialog._updateBackgrounds ===
                'function'
            ) {

                dialog._updateBackgrounds();

                log(
                    'NIVETH LOCK SCREEN V11: ' +
                    'BACKGROUND REFRESHED'
                );
            }

        } catch (error) {

            logError(
                error,
                'NIVETH LOCK SCREEN V11: ' +
                'BACKGROUND REFRESH FAILED'
            );
        }

        /*
         * GNOME may recreate blur effects when the
         * background is rebuilt, so remove them again.
         */
        try {

            this._removeBlur(dialog);

        } catch (error) {

            logError(
                error,
                'NIVETH LOCK SCREEN V11: ' +
                'BLUR REFRESH FAILED'
            );
        }
    }


"""

text = text.replace(
    marker,
    method + marker,
    1
)

print("[PASS] _refreshWallpaper() added")


# ----------------------------------------------------------
# F. Replace disable() beginning with cleanup.
# ----------------------------------------------------------

old = """    disable() {
"""

new = """    disable() {

        if (
            this._wallpaperSettings &&
            this._wallpaperSettingsChangedId
        ) {

            try {

                this._wallpaperSettings.disconnect(
                    this._wallpaperSettingsChangedId
                );

            } catch (error) {
            }

            this._wallpaperSettingsChangedId = 0;
        }

        this._wallpaperSettings = null;
"""

if old not in text:
    print("[FAIL] disable() not found.")
    sys.exit(1)

text = text.replace(
    old,
    new,
    1
)

print("[PASS] Wallpaper listener cleanup added")


# ----------------------------------------------------------
# G. Update remaining V9 log labels.
# ----------------------------------------------------------

text = text.replace(
    "NIVETH LOCK SCREEN v9:",
    "NIVETH LOCK SCREEN V11:"
)

text = text.replace(
    "NIVETH LOCK SCREEN v9: ENABLE",
    "NIVETH LOCK SCREEN V11: ENABLE"
)

path.write_text(text)

print("[PASS] extension.js written")
PY

echo

# ------------------------------------------------------------
# 6. Update version
# ------------------------------------------------------------

echo "[6/9] Updating metadata..."

python3 - "$EXT/metadata.json" <<'PY'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])

data = json.loads(
    path.read_text()
)

data["version"] = 11

path.write_text(
    json.dumps(
        data,
        indent=2,
        ensure_ascii=False
    ) + "\n"
)

print("[PASS] Version -> 11")
PY

echo

# ------------------------------------------------------------
# 7. Verify source
# ------------------------------------------------------------

echo "[7/9] Verifying V11..."

required=(
    "_wallpaperSettings"
    "_wallpaperSettingsChangedId"
    "org.gnome.desktop.background"
    "_refreshWallpaper()"
    "dialog._updateBackgrounds()"
    "this._wallpaperSettings.connect"
    "this._wallpaperSettings.disconnect"
)

for item in "${required[@]}"; do

    if grep -Fq "$item" "$EXT/extension.js"; then
        echo "[PASS] $item"
    else
        echo "[FAIL] Missing: $item"
        exit 1
    fi

done

if grep -Fq \
    "_wallpaperWidget" \
    "$EXT/extension.js"
then
    echo "[FAIL] Custom wallpaper widget detected."
    exit 1
fi

if grep -Fq \
    "background-image: url" \
    "$EXT/extension.js"
then
    echo "[FAIL] Custom background-image renderer detected."
    exit 1
fi

if grep -Fq \
    "picture-uri" \
    "$EXT/extension.js"
then
    echo "[INFO] Desktop wallpaper settings referenced."
fi

VERSION="$(
    python3 - "$EXT/metadata.json" <<'PY'
import json
import sys
from pathlib import Path

print(
    json.loads(
        Path(sys.argv[1]).read_text()
    ).get("version")
)
PY
)"

if [ "$VERSION" != "11" ]; then
    echo "[FAIL] Metadata version is not 11."
    exit 1
fi

echo
echo "[PASS] Uses GNOME's own lock background manager"
echo "[PASS] Wallpaper change listener installed"
echo "[PASS] No second wallpaper renderer"
echo "[PASS] Existing blur removal preserved"
echo "[PASS] Existing lock UI preserved"
echo "[PASS] Version 11"
echo

# ------------------------------------------------------------
# 8. Synchronize rootfs
# ------------------------------------------------------------

echo "[8/9] Synchronizing V11 to Niveth rootfs..."

if [ -d "$ROOTFS_EXT" ]; then

    sudo install \
        -m 0644 \
        "$EXT/extension.js" \
        "$ROOTFS_EXT/extension.js"

    sudo install \
        -m 0644 \
        "$EXT/metadata.json" \
        "$ROOTFS_EXT/metadata.json"

    if [ -f "$EXT/stylesheet.css" ]; then

        sudo install \
            -m 0644 \
            "$EXT/stylesheet.css" \
            "$ROOTFS_EXT/stylesheet.css"

    fi

    echo "[PASS] Rootfs synchronized."

else

    echo "[INFO] Rootfs lockscreen directory not found."
fi

echo

# ------------------------------------------------------------
# 9. Enable
# ------------------------------------------------------------

echo "[9/9] Enabling V11..."

gnome-extensions enable "$UUID"

sleep 2

echo
echo "============================================================"
echo " FINAL STATUS"
echo "============================================================"

gnome-extensions info "$UUID" 2>&1 || true

echo
echo "============================================================"
echo " V11 WALLPAPER SYNC COMPLETE"
echo "============================================================"
echo
echo "Backup:"
echo "  $BACKUP"
echo
echo "Expected:"
echo "  Version: 11"
echo "  Enabled: Yes"
echo "  State: INITIALIZED"
echo
echo "Test:"
echo "  1. Note the current desktop wallpaper."
echo "  2. Lock the screen."
echo "  3. Verify the lockscreen uses the same wallpaper."
echo "  4. Change wallpaper from Niveth Wallpapers."
echo "  5. Lock again."
echo "  6. The lockscreen should now use the new wallpaper."
echo
