#!/usr/bin/env bash
set -euo pipefail

THEMES="$HOME/.local/share/niveth/brave/themes"
CURRENT="$THEMES/current"

SCHEME="$(gsettings get org.gnome.desktop.interface color-scheme 2>/dev/null || true)"

case "$SCHEME" in
    "'prefer-dark'")
        TARGET="$THEMES/dark"
        MODE="dark"
        ;;
    *)
        TARGET="$THEMES/light"
        MODE="light"
        ;;
esac

if [[ ! -f "$TARGET/manifest.json" ]]; then
    echo "ERROR: Missing Niveth $MODE theme: $TARGET" >&2
    exit 1
fi

ln -sfn "$MODE" "$CURRENT"

echo "Niveth Brave theme:"
echo "  mode   = $MODE"
echo "  target = $TARGET"
echo "  current -> $(readlink "$CURRENT")"
