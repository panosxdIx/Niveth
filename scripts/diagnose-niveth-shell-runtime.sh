#!/usr/bin/env bash

set -u

DOCK="niveth-dock@nivethos"
UI="niveth-ui-test@nivethos"

echo "=================================================="
echo " Niveth Shell Runtime Diagnostic"
echo "=================================================="
echo

echo "=== 1. Current color scheme ==="
gsettings get org.gnome.desktop.interface color-scheme

echo
echo "=== 2. Extension status ==="

gnome-extensions info "$DOCK" 2>&1 | \
    grep -E 'Name|Path|Enabled|State' || true

echo

gnome-extensions info "$UI" 2>&1 | \
    grep -E 'Name|Path|Enabled|State' || true

echo
echo "=================================================="
echo " 3. Icon files used by Top Bar"
echo "=================================================="

UI_DIR="$HOME/.local/share/gnome-shell/extensions/$UI"

echo
echo "--- UI Test directory ---"
find "$UI_DIR/icons" \
    -maxdepth 2 \
    -type f \
    -printf '%P\n' \
    2>/dev/null |
    sort || true

echo
echo "=================================================="
echo " 4. GNOME Shell Eval"
echo "=================================================="

EVAL_SCRIPT='
(() => {
    const results = [];

    function walk(actor, depth = 0) {
        if (!actor || depth > 30)
            return;

        try {
            const name = actor.constructor?.name || "";
            const style = actor.get_style_class_name?.() || "";

            if (
                style.includes("niveth-dock") ||
                style.includes("niveth-topbar")
            ) {
                results.push(
                    JSON.stringify({
                        type: name,
                        style: style,
                        visible: actor.visible,
                        mapped: actor.mapped,
                        opacity: actor.opacity,
                    })
                );
            }

            for (const child of actor.get_children?.() || [])
                walk(child, depth + 1);

        } catch (e) {
            results.push(
                "ERROR:" + String(e)
            );
        }
    }

    walk(global.stage);

    return results.join("\\n");
})()
'

echo
echo "--- Shell actors at current scheme ---"

gdbus call \
    --session \
    --dest org.gnome.Shell \
    --object-path /org/gnome/Shell \
    --method org.gnome.Shell.Eval \
    "$EVAL_SCRIPT" \
    2>&1 || true

echo
echo "=================================================="
echo " 5. Switch to DARK"
echo "=================================================="

gsettings set \
    org.gnome.desktop.interface \
    color-scheme \
    'prefer-dark'

sleep 3

echo
echo "Color scheme now:"
gsettings get \
    org.gnome.desktop.interface \
    color-scheme

echo
echo "--- Shell actors after prefer-dark ---"

gdbus call \
    --session \
    --dest org.gnome.Shell \
    --object-path /org/gnome/Shell \
    --method org.gnome.Shell.Eval \
    "$EVAL_SCRIPT" \
    2>&1 || true

echo
echo "=================================================="
echo " 6. Recent GNOME Shell errors"
echo "=================================================="

journalctl \
    --user \
    --since "2 minutes ago" \
    --no-pager \
    -o cat 2>/dev/null |
    grep -Ei \
        "niveth|argument file may be null|g_object_ref|JS ERROR|TypeError|ReferenceError|SyntaxError" |
    tail -n 120 || true

echo
echo "=================================================="
echo " 7. Switch back to LIGHT"
echo "=================================================="

gsettings set \
    org.gnome.desktop.interface \
    color-scheme \
    'prefer-light'

sleep 3

echo
echo "Color scheme now:"
gsettings get \
    org.gnome.desktop.interface \
    color-scheme

echo
echo "--- Shell actors after prefer-light ---"

gdbus call \
    --session \
    --dest org.gnome.Shell \
    --object-path /org/gnome/Shell \
    --method org.gnome.Shell.Eval \
    "$EVAL_SCRIPT" \
    2>&1 || true

echo
echo "=================================================="
echo " DIAGNOSTIC COMPLETE"
echo "=================================================="
