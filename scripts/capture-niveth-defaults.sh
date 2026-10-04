#!/usr/bin/env bash

set -u

PROJECT_ROOT="$HOME/Niveth"
OUT="$PROJECT_ROOT/desktop/defaults"

echo "============================================================"
echo "            NIVETH DEFAULTS CAPTURE"
echo "============================================================"
echo

mkdir -p "$OUT/dconf"
mkdir -p "$OUT/gnome"
mkdir -p "$OUT/extensions"
mkdir -p "$OUT/kitty"

echo "[1/7] Preparing output..."
rm -f \
    "$OUT/gnome/favorite-apps.txt" \
    "$OUT/gnome/extensions-enabled.txt" \
    "$OUT/gnome/basic-settings.txt"

echo "[2/7] Capturing GNOME default settings..."

for schema in \
    org.gnome.desktop.interface \
    org.gnome.desktop.background \
    org.gnome.desktop.wm.preferences \
    org.gnome.desktop.screensaver \
    org.gnome.desktop.sound \
    org.gnome.mutter \
    org.gnome.shell
do
    safe_name="${schema//./-}"

    dconf dump "/${schema//./\/}/" \
        > "$OUT/dconf/${safe_name}.dconf" \
        2>/dev/null || true
done

echo "[3/7] Capturing GNOME favorites..."

gsettings get org.gnome.shell favorite-apps \
    > "$OUT/gnome/favorite-apps.txt" \
    2>/dev/null || true

echo "[4/7] Capturing enabled extensions..."

gnome-extensions list --enabled \
    2>/dev/null \
    | sort \
    > "$OUT/gnome/extensions-enabled.txt" || true

echo "[5/7] Capturing relevant basic settings..."

{
    echo "[interface]"
    gsettings get org.gnome.desktop.interface gtk-theme 2>/dev/null || true
    gsettings get org.gnome.desktop.interface icon-theme 2>/dev/null || true
    gsettings get org.gnome.desktop.interface cursor-theme 2>/dev/null || true
    gsettings get org.gnome.desktop.interface color-scheme 2>/dev/null || true
    gsettings get org.gnome.desktop.interface font-name 2>/dev/null || true
    gsettings get org.gnome.desktop.interface document-font-name 2>/dev/null || true
    gsettings get org.gnome.desktop.interface monospace-font-name 2>/dev/null || true

    echo
    echo "[background]"
    gsettings get org.gnome.desktop.background picture-uri 2>/dev/null || true
    gsettings get org.gnome.desktop.background picture-uri-dark 2>/dev/null || true
    gsettings get org.gnome.desktop.background picture-options 2>/dev/null || true

    echo
    echo "[mutter]"
    gsettings get org.gnome.mutter dynamic-workspaces 2>/dev/null || true
    gsettings get org.gnome.mutter edge-tiling 2>/dev/null || true
    gsettings get org.gnome.mutter center-new-windows 2>/dev/null || true

    echo
    echo "[shell]"
    gsettings get org.gnome.shell enabled-extensions 2>/dev/null || true
    gsettings get org.gnome.shell favorite-apps 2>/dev/null || true
} > "$OUT/gnome/basic-settings.txt"

echo "[6/7] Capturing Niveth extension settings..."

for uuid in \
    niveth-dock@nivethos \
    niveth-topbar@nivethos \
    niveth-ui-test@nivethos \
    niveth-lockscreen@nivethos \
    niveth-app-refresh@nivethos
do
    dir="$HOME/.local/share/gnome-shell/extensions/$uuid"

    if [ ! -d "$dir" ]; then
        continue
    fi

    {
        echo "============================================================"
        echo "EXTENSION: $uuid"
        echo "============================================================"
        echo

        if [ -f "$dir/metadata.json" ]; then
            echo "--- metadata.json ---"
            cat "$dir/metadata.json"
            echo
        fi

        if [ -f "$dir/stylesheet.css" ]; then
            echo "--- stylesheet.css ---"
            cat "$dir/stylesheet.css"
            echo
        fi

        if [ -f "$dir/extension.js" ]; then
            echo "--- extension.js size ---"
            wc -l "$dir/extension.js"
            echo
        fi
    } > "$OUT/extensions/$uuid-audit.txt"

    dconf dump "/org/gnome/shell/extensions/${uuid//./\/}/" \
        > "$OUT/extensions/$uuid.dconf" \
        2>/dev/null || true
done

echo "[7/7] Capturing Kitty Niveth configuration..."

for file in \
    "$HOME/.config/kitty/kitty.conf" \
    "$HOME/.config/kitty/niveth-dark.conf" \
    "$HOME/.config/kitty/niveth-light.conf" \
    "$HOME/.config/kitty/niveth-context-menu.py"
do
    if [ -f "$file" ]; then
        cp -a "$file" "$OUT/kitty/"
    fi
done

echo
echo "============================================================"
echo "            NIVETH DEFAULTS CAPTURE COMPLETE"
echo "============================================================"
echo
echo "Output:"
echo "  $OUT"
echo

echo "=== FILES ==="
find "$OUT" -type f -printf '%P\n' | sort

echo
echo "=== SIZE ==="
du -sh "$OUT"

echo
echo "Next step:"
echo "Send me the output of:"
echo
echo "    find ~/Niveth/desktop/defaults -type f -print | sort"
echo
echo "and:"
echo
echo "    cat ~/Niveth/desktop/defaults/gnome/basic-settings.txt"
echo
