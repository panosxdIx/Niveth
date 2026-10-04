#!/usr/bin/env bash

set -u

echo "=================================================="
echo " Niveth Dock Applications Diagnostic"
echo "=================================================="
echo

echo "=== GNOME FAVORITE APPS ==="
gsettings get org.gnome.shell favorite-apps 2>&1 || true
echo

echo "=================================================="
echo " Desktop files"
echo "=================================================="

DESKTOPS=(
    "com.niveth.Notes.desktop"
    "com.niveth.AppCenter.desktop"
    "org.niveth.Files.desktop"
    "niveth-ptyxis.desktop"
    "kitty.desktop"
    "vivaldi-stable.desktop"
)

for desktop in "${DESKTOPS[@]}"; do
    echo
    echo "--------------------------------------------------"
    echo "[$desktop]"
    echo "--------------------------------------------------"

    FOUND=0

    for dir in \
        "$HOME/.local/share/applications" \
        "/usr/local/share/applications" \
        "/usr/share/applications"
    do
        if [ -f "$dir/$desktop" ]; then
            FOUND=1
            echo "FOUND: $dir/$desktop"
            echo
            echo "Exec:"
            grep -E '^Exec=' "$dir/$desktop" || echo "  <NO Exec= LINE>"
            echo
            echo "TryExec:"
            grep -E '^TryExec=' "$dir/$desktop" || true
            echo
            echo "Type:"
            grep -E '^Type=' "$dir/$desktop" || true
            echo
            echo "Name:"
            grep -E '^Name=' "$dir/$desktop" | head -1 || true
            echo
            echo "Full file:"
            sed -n '1,160p' "$dir/$desktop"
        fi
    done

    if [ "$FOUND" -eq 0 ]; then
        echo "NOT FOUND anywhere."
    fi
done

echo
echo "=================================================="
echo " Niveth application files"
echo "=================================================="

echo
echo "--- Niveth Notes ---"
ls -lah \
    "$HOME/.local/share/niveth-notes/niveth-notes.py" \
    "$HOME/.local/bin/niveth-notes" \
    2>/dev/null || true

echo
echo "--- Niveth App Center ---"
find \
    "$HOME/.local/share/niveth-app-center" \
    "$HOME/.local/bin" \
    -maxdepth 2 \
    -iname '*niveth*app*center*' \
    -o -iname 'niveth-app-center*' \
    2>/dev/null | sort || true

echo
echo "--- Niveth Files ---"
ls -lah \
    "$HOME/Niveth-Files/main.py" \
    "$HOME/.local/bin/niveth-files" \
    2>/dev/null || true

echo
echo "--- Niveth Terminal ---"
ls -lah \
    "$HOME/.local/bin/niveth-terminal" \
    "$HOME/.local/bin/niveth-ptyxis" \
    2>/dev/null || true

echo
echo "=================================================="
echo " Executable permissions"
echo "=================================================="

for file in \
    "$HOME/.local/bin/niveth-app-center" \
    "$HOME/.local/bin/niveth-files" \
    "$HOME/.local/bin/niveth-terminal" \
    "$HOME/.local/bin/niveth-notes"
do
    if [ -e "$file" ]; then
        ls -l "$file"
        file "$file" || true
    fi
done

echo
echo "=================================================="
echo " Python syntax checks"
echo "=================================================="

for file in \
    "$HOME/.local/share/niveth-notes/niveth-notes.py" \
    "$HOME/Niveth-Files/main.py"
do
    if [ -f "$file" ]; then
        echo
        echo "--- $file ---"
        python3 -m py_compile "$file" 2>&1 || true
    fi
done

echo
echo "=================================================="
echo " Command resolution"
echo "=================================================="

for cmd in \
    niveth-app-center \
    niveth-files \
    niveth-terminal \
    niveth-notes \
    kitty \
    vivaldi-stable
do
    echo
    echo "--- $cmd ---"
    command -v "$cmd" 2>&1 || true
done

echo
echo "=================================================="
echo " COMPLETE"
echo "=================================================="
