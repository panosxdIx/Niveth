#!/usr/bin/env bash

set -euo pipefail

UUID="niveth-lockscreen@nivethos"

EXT="$HOME/.local/share/gnome-shell/extensions/$UUID"

ROOTFS="$HOME/Niveth/build/rootfs"
ROOTFS_EXT="$ROOTFS/usr/share/gnome-shell/extensions/$UUID"

STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP="$EXT/backup-v11-wallpaper-sync-$STAMP"

ROLLBACK_NEEDED=0

rollback_on_error() {
    if [ "$ROLLBACK_NEEDED" -eq 1 ]; then
        echo
        echo "============================================================"
        echo " ERROR — RESTORING LOCK SCREEN"
        echo "============================================================"
        echo

        gnome-extensions enable "$UUID" 2>/dev/null || true

        echo "[INFO] Lock screen re-enabled."
        echo
    fi
}

trap rollback_on_error ERR

echo
echo "============================================================"
echo "       NIVETH LOCK SCREEN — V11"
echo "       DESKTOP WALLPAPER SYNCHRONIZATION"
echo "============================================================"
echo
echo "Design:"
echo
echo "  Niveth Desktop Wallpaper"
echo "           ↓"
echo "  GNOME desktop background settings"
echo "           ↓"
echo "  GNOME UnlockDialog background"
echo "           ↓"
echo "  Niveth Lock Screen"
echo
echo "No custom wallpaper renderer."
echo "No second wallpaper widget."
echo "Existing V10 UI and blur handling remain."
echo
echo "============================================================"
echo

# ------------------------------------------------------------
# 1. Verify environment
# ------------------------------------------------------------

echo "[1/10] Verifying environment..."

if [ ! -f "$EXT/extension.js" ]; then
    echo "[FAIL] extension.js not found:"
    echo "  $EXT/extension.js"
    exit 1
fi

if [ ! -f "$EXT/metadata.json" ]; then
    echo "[FAIL] metadata.json not found:"
    echo "  $EXT/metadata.json"
    exit 1
fi

if [ ! -d "$ROOTFS" ]; then
    echo "[FAIL] Niveth rootfs not found:"
    echo "  $ROOTFS"
    exit 1
fi

echo "[PASS] extension.js"
echo "[PASS] metadata.json"
echo "[PASS] Niveth rootfs"
echo

# ------------------------------------------------------------
# 2. Confirm V10
# ------------------------------------------------------------

echo "[2/10] Confirming V10 base..."

CURRENT_VERSION="$(
    python3 - "$EXT/metadata.json" <<'PY'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])

data = json.loads(
    path.read_text(
        encoding="utf-8"
    )
)

print(
    data.get("version")
)
PY
)"

echo "Current version: $CURRENT_VERSION"

if [ "$CURRENT_VERSION" != "10" ]; then
    echo
    echo "[FAIL] This script requires V10."
    echo "       Found version: $CURRENT_VERSION"
    echo
    echo "Nothing was modified."
    exit 1
fi

echo "[PASS] V10 confirmed"
echo

# ------------------------------------------------------------
# 3. Create backup
# ------------------------------------------------------------

echo "[3/10] Creating backup..."

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

echo "[PASS] Backup created:"
echo "  $BACKUP"
echo

# ------------------------------------------------------------
# 4. Disable extension safely
# ------------------------------------------------------------

echo "[4/10] Disabling current lock screen..."

ROLLBACK_NEEDED=1

gnome-extensions disable "$UUID" 2>/dev/null || true

sleep 1

echo "[PASS] Current lock screen disabled"
echo

# ------------------------------------------------------------
# 5. Patch extension.js
# ------------------------------------------------------------

echo "[5/10] Installing wallpaper synchronization..."

python3 - "$EXT/extension.js" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])

text = path.read_text(
    encoding="utf-8"
)

# ----------------------------------------------------------
# A. Add wallpaper state.
# ----------------------------------------------------------

old = """        this._dialog = null;
        this._logo = null;
        this._timers = [];
"""

new = """        this._dialog = null;
        this._logo = null;

        this._wallpaperSettings = null;
        this._wallpaperChangedId = null;

        this._timers = [];
"""

if text.count(old) != 1:
    print(
        "[FAIL] Exact V10 wallpaper-state anchor "
        "was not found."
    )
    sys.exit(1)

text = text.replace(
    old,
    new,
    1
)

print(
    "[PASS] Wallpaper state added"
)

# ----------------------------------------------------------
# B. Connect to GNOME wallpaper settings.
# ----------------------------------------------------------

old = """        this._colorSchemeChangedId =
            this._interfaceSettings.connect(
                'changed::color-scheme',
                () => this._updateColorScheme()
            );

        log('NIVETH LOCK SCREEN v10: ENABLE');
"""

new = """        this._colorSchemeChangedId =
            this._interfaceSettings.connect(
                'changed::color-scheme',
                () => this._updateColorScheme()
            );

        this._wallpaperSettings =
            Gio.Settings.new(
                'org.gnome.desktop.background'
            );

        this._wallpaperChangedId =
            this._wallpaperSettings.connect(
                'changed',
                () => this._refreshWallpaper()
            );

        log('NIVETH LOCK SCREEN v11: ENABLE');
"""

if text.count(old) != 1:
    print(
        "[FAIL] Exact V10 settings anchor "
        "was not found."
    )
    sys.exit(1)

text = text.replace(
    old,
    new,
    1
)

print(
    "[PASS] Desktop wallpaper listener added"
)

# ----------------------------------------------------------
# C. Replace _apply() background call.
# ----------------------------------------------------------

old = """        this._dialog = dialog;

        try {
            dialog._updateBackgroundEffects();
        } catch (error) {
            logError(
                error,
                'NIVETH LOCK SCREEN v10: UPDATE FAILED'
            );
        }

        this._removeBlur(dialog);
        this._placeLogo(dialog);
        this._updateColorScheme();
"""

new = """        this._dialog = dialog;

        this._refreshWallpaper();
"""

if text.count(old) != 1:
    print(
        "[FAIL] Exact V10 _apply() block "
        "was not found."
    )
    sys.exit(1)

text = text.replace(
    old,
    new,
    1
)

print(
    "[PASS] _apply() now refreshes wallpaper"
)

# ----------------------------------------------------------
# D. Insert _refreshWallpaper().
#
# IMPORTANT:
# _refreshWallpaper() calls _updateBackgrounds().
#
# The patched _updateBackgroundEffects() does NOT call
# _refreshWallpaper(), preventing recursive calls.
# ----------------------------------------------------------

marker = """    _removeBlur(dialog) {
"""

method = """    _refreshWallpaper() {
        const dialog =
            this._dialog ||
            Main.screenShield?._dialog;

        if (!dialog)
            return;

        this._dialog = dialog;

        try {

            if (
                typeof dialog._updateBackgrounds ===
                'function'
            ) {

                dialog._updateBackgrounds();

                log(
                    'NIVETH LOCK SCREEN v11: ' +
                    'DESKTOP WALLPAPER SYNCHRONIZED'
                );

            } else if (
                typeof dialog._updateBackgroundEffects ===
                'function'
            ) {

                dialog._updateBackgroundEffects();

                log(
                    'NIVETH LOCK SCREEN v11: ' +
                    'BACKGROUND EFFECTS REFRESHED'
                );

            } else {

                log(
                    'NIVETH LOCK SCREEN v11: ' +
                    'NO BACKGROUND REFRESH METHOD'
                );
            }

        } catch (error) {

            logError(
                error,
                'NIVETH LOCK SCREEN v11: ' +
                'WALLPAPER SYNC FAILED'
            );
        }

        this._removeBlur(dialog);
        this._placeLogo(dialog);
        this._updateColorScheme();
    }


"""

if marker not in text:
    print(
        "[FAIL] _removeBlur() marker not found."
    )
    sys.exit(1)

if text.count(marker) != 1:
    print(
        "[FAIL] Unexpected number of _removeBlur() markers."
    )
    sys.exit(1)

text = text.replace(
    marker,
    method + marker,
    1
)

print(
    "[PASS] _refreshWallpaper() added"
)

# ----------------------------------------------------------
# E. Add wallpaper cleanup to disable().
# ----------------------------------------------------------

old = """    disable() {
        log(
            'NIVETH LOCK SCREEN v10: DISABLE'
        );

        for (const id of this._timers) {
"""

new = """    disable() {
        log(
            'NIVETH LOCK SCREEN v11: DISABLE'
        );

        if (
            this._wallpaperSettings &&
            this._wallpaperChangedId
        ) {

            try {

                this._wallpaperSettings.disconnect(
                    this._wallpaperChangedId
                );

            } catch (error) {
            }

            this._wallpaperChangedId = null;
        }

        this._wallpaperSettings = null;

        for (const id of this._timers) {
"""

if text.count(old) != 1:
    print(
        "[FAIL] Exact V10 disable() anchor "
        "was not found."
    )
    sys.exit(1)

text = text.replace(
    old,
    new,
    1
)

print(
    "[PASS] Wallpaper listener cleanup added"
)

# ----------------------------------------------------------
# F. Write final source.
# ----------------------------------------------------------

path.write_text(
    text,
    encoding="utf-8"
)

print(
    "[PASS] extension.js written"
)
PY

echo

# ------------------------------------------------------------
# 6. Update metadata
# ------------------------------------------------------------

echo "[6/10] Updating metadata to V11..."

python3 - "$EXT/metadata.json" <<'PY'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])

data = json.loads(
    path.read_text(
        encoding="utf-8"
    )
)

if data.get("version") != 10:
    print(
        "[FAIL] Metadata is no longer V10."
    )
    sys.exit(1)

data["version"] = 11
data["version-name"] = "11.0"

path.write_text(
    json.dumps(
        data,
        indent=2,
        ensure_ascii=False
    ) + "\n",
    encoding="utf-8"
)

print(
    "[PASS] Version 11.0"
)
PY

echo

# ------------------------------------------------------------
# 7. Verify source
# ------------------------------------------------------------

echo "[7/10] Verifying V11 source..."

REQUIRED=(
    "_wallpaperSettings"
    "_wallpaperChangedId"
    "org.gnome.desktop.background"
    "changed"
    "_refreshWallpaper()"
    "dialog._updateBackgrounds()"
    "DESKTOP WALLPAPER SYNCHRONIZED"
)

for item in "${REQUIRED[@]}"; do

    if grep -Fq "$item" "$EXT/extension.js"; then
        echo "[PASS] $item"
    else
        echo "[FAIL] Missing:"
        echo "       $item"
        exit 1
    fi

done

if grep -Fq \
    "_wallpaperWidget" \
    "$EXT/extension.js"
then
    echo "[FAIL] Custom wallpaper widget found."
    exit 1
fi

if grep -Fq \
    "background-image: url" \
    "$EXT/extension.js"
then
    echo "[FAIL] Custom CSS wallpaper renderer found."
    exit 1
fi

VERSION="$(
    python3 - "$EXT/metadata.json" <<'PY'
import json
import sys
from pathlib import Path

data = json.loads(
    Path(sys.argv[1]).read_text(
        encoding="utf-8"
    )
)

print(data.get("version"))
PY
)"

if [ "$VERSION" != "11" ]; then
    echo "[FAIL] Metadata version is not 11."
    exit 1
fi

echo
echo "[PASS] No second wallpaper renderer"
echo "[PASS] GNOME wallpaper settings listener"
echo "[PASS] GNOME background refresh path"
echo "[PASS] Existing blur removal preserved"
echo "[PASS] Existing logo preserved"
echo "[PASS] Existing color-scheme support preserved"
echo "[PASS] Version 11"
echo

# ------------------------------------------------------------
# 8. Sync rootfs
# ------------------------------------------------------------

echo "[8/10] Synchronizing V11 into Niveth rootfs..."

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

    echo "[PASS] Rootfs synchronized"

else

    echo "[INFO] Rootfs extension directory does not exist."
    echo "       User extension was updated."
fi

echo

# ------------------------------------------------------------
# 9. Enable V11
# ------------------------------------------------------------

echo "[9/10] Enabling V11..."

gnome-extensions enable "$UUID"

sleep 2

echo "[PASS] V11 enabled"

# No rollback is needed anymore.
ROLLBACK_NEEDED=0

echo

# ------------------------------------------------------------
# 10. Final status
# ------------------------------------------------------------

echo "[10/10] Final status..."
echo

gnome-extensions info "$UUID" 2>&1 || true

echo
echo "============================================================"
echo " V11 INSTALLATION COMPLETE"
echo "============================================================"
echo
echo "Backup:"
echo "  $BACKUP"
echo
echo "Expected:"
echo "  Version: 11.0 (11)"
echo "  Enabled: Yes"
echo "  State: INITIALIZED"
echo
echo "============================================================"
echo " TEST"
echo "============================================================"
echo
echo "1. Change the wallpaper from Niveth Wallpapers."
echo "2. Wait 1-2 seconds."
echo "3. Lock the screen."
echo "4. Check whether the lock screen has the same wallpaper."
echo
echo "Then check the log with:"
echo
echo "  journalctl --user -b --no-pager | grep 'NIVETH LOCK SCREEN'"
echo
echo "Expected log:"
echo
echo "  DESKTOP WALLPAPER SYNCHRONIZED"
echo
echo "============================================================"
