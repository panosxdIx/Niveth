#!/usr/bin/env bash

set -u

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ROOTFS="$PROJECT_ROOT/build/rootfs"
MANIFEST="$PROJECT_ROOT/desktop/niveth-components.txt"

PASS=0
WARN=0
FAIL=0

pass() {
    echo "[PASS] $1"
    PASS=$((PASS + 1))
}

warn() {
    echo "[WARN] $1"
    WARN=$((WARN + 1))
}

fail() {
    echo "[FAIL] $1"
    FAIL=$((FAIL + 1))
}

check_file() {
    local file="$1"
    local label="$2"

    if [ -f "$file" ]; then
        pass "$label"
    else
        fail "$label"
    fi
}

check_dir() {
    local dir="$1"
    local label="$2"

    if [ -d "$dir" ]; then
        pass "$label"
    else
        fail "$label"
    fi
}

echo "============================================================"
echo "          NIVETH 0.1 FINAL PRE-BUILD AUDIT"
echo "============================================================"
echo

if [ ! -d "$ROOTFS" ]; then
    fail "rootfs does not exist"
    exit 1
fi

echo "=== 1. ROOTFS MOUNTS ==="

if findmnt -R "$ROOTFS" 2>/dev/null | tail -n +2 | grep -q .; then
    warn "There are active mounts inside rootfs"
    findmnt -R "$ROOTFS" 2>/dev/null
else
    pass "rootfs has no active mounts"
fi

echo
echo "=== 2. OS BRANDING ==="

if [ -f "$ROOTFS/usr/lib/os-release" ]; then
    grep -q '^PRETTY_NAME="Niveth Linux 0.1.1"$' "$ROOTFS/usr/lib/os-release" \
        && pass "Niveth os-release branding" \
        || fail "Niveth os-release branding"
else
    fail "rootfs os-release missing"
fi

echo
echo "=== 3. MOVEMENT BREAK ==="

check_file \
    "$PROJECT_ROOT/desktop/defaults/dconf/90-niveth-wellbeing" \
    "Movement Break source dconf"

check_file \
    "$ROOTFS/etc/dconf/db/local.d/90-niveth-wellbeing" \
    "Movement Break rootfs dconf"

if grep -q 'interval-seconds=uint32 3000' \
    "$ROOTFS/etc/dconf/db/local.d/90-niveth-wellbeing" 2>/dev/null; then
    pass "Movement interval = 50 minutes"
else
    fail "Movement interval is not 50 minutes"
fi

if grep -q 'duration-seconds=uint32 480' \
    "$ROOTFS/etc/dconf/db/local.d/90-niveth-wellbeing" 2>/dev/null; then
    pass "Movement duration = 8 minutes"
else
    fail "Movement duration is not 8 minutes"
fi

if grep -q "selected-breaks=\['movement'\]" \
    "$ROOTFS/etc/dconf/db/local.d/90-niveth-wellbeing" 2>/dev/null; then
    pass "Movement reminder selected"
else
    fail "Movement reminder is not selected"
fi

if grep -Rqs "break-reminders" \
    "$ROOTFS/usr/share/glib-2.0/schemas" 2>/dev/null; then
    pass "GNOME break-reminders schema present"
else
    warn "GNOME break-reminders schema was not found in schema files"
fi

echo
echo "=== 4. GNOME EXTENSIONS ==="

if [ -f "$ROOTFS/etc/dconf/db/local.d/00-niveth" ]; then
    DCONF_FILE="$ROOTFS/etc/dconf/db/local.d/00-niveth"
elif [ -f "$ROOTFS/etc/dconf/db/local.d/90-niveth" ]; then
    DCONF_FILE="$ROOTFS/etc/dconf/db/local.d/90-niveth"
else
    DCONF_FILE=""
fi

if [ -n "$DCONF_FILE" ]; then
    grep -q "niveth-dock@nivethos" "$DCONF_FILE" \
        && pass "Niveth Dock enabled by default" \
        || warn "Niveth Dock default not found"

    grep -q "niveth-ui-test@nivethos" "$DCONF_FILE" \
        && pass "Niveth UI Test enabled by default" \
        || warn "Niveth UI Test default not found"

    grep -q "niveth-lockscreen@nivethos" "$DCONF_FILE" \
        && pass "Niveth Lock Screen enabled by default" \
        || warn "Niveth Lock Screen default not found"

    grep -q "niveth-topbar@nivethos" "$DCONF_FILE" \
        && warn "Niveth Topbar appears in defaults; verify intended disabled state" \
        || pass "Niveth Topbar not enabled by default"
else
    warn "Could not locate main Niveth dconf defaults file"
fi

echo
echo "=== 5. LOCK SCREEN ==="

LOCK_DIR="$ROOTFS/usr/share/gnome-shell/extensions/niveth-lockscreen@nivethos"

check_file \
    "$LOCK_DIR/metadata.json" \
    "Lock Screen metadata"

check_file \
    "$LOCK_DIR/extension.js" \
    "Lock Screen extension.js"

check_file \
    "$LOCK_DIR/stylesheet.css" \
    "Lock Screen stylesheet.css"

if grep -q '"version": 10' "$LOCK_DIR/metadata.json" 2>/dev/null; then
    pass "Lock Screen metadata version 10"
else
    warn "Lock Screen metadata version is not 10"
fi

echo
echo "=== 6. CURSOR ==="

CURSOR_DIR="$ROOTFS/usr/share/icons/retrosmart-xcursor-mac-ish-gruvbox"

check_dir "$CURSOR_DIR" "Niveth cursor theme directory"

if [ -d "$CURSOR_DIR/cursors" ]; then
    CURSOR_COUNT="$(find "$CURSOR_DIR/cursors" -type f | wc -l)"
    if [ "$CURSOR_COUNT" -ge 20 ]; then
        pass "Cursor theme assets present ($CURSOR_COUNT files)"
    else
        warn "Cursor theme has only $CURSOR_COUNT cursor files"
    fi
else
    fail "Cursor assets directory missing"
fi

echo
echo "=== 7. DOCK ICONS ==="

check_file \
    "$ROOTFS/usr/share/icons/hicolor/scalable/apps/com.niveth.Notes.svg" \
    "Niveth Notes icon"

check_file \
    "$ROOTFS/usr/share/icons/hicolor/scalable/apps/niveth-app-center.svg" \
    "Niveth App Center icon"

check_file \
    "$ROOTFS/usr/share/icons/hicolor/scalable/apps/org.niveth.Files.svg" \
    "Niveth Files icon"

echo
echo "=== 8. WALLPAPERS ==="

WALL_DIR="$ROOTFS/usr/share/niveth/wallpapers"

if [ -d "$WALL_DIR" ]; then
    WALL_COUNT="$(find "$WALL_DIR" -maxdepth 1 -type f | wc -l)"
    if [ "$WALL_COUNT" -ge 9 ]; then
        pass "Wallpapers present ($WALL_COUNT files)"
    else
        warn "Only $WALL_COUNT wallpapers found"
    fi
else
    fail "Wallpaper directory missing"
fi

echo
echo "=== 9. Niveth Files WALLPAPER MENU ==="

if grep -q "Change Wallpaper" \
    "$ROOTFS/usr/local/lib/python*/site-packages/niveth_files/main.py" \
    2>/dev/null; then
    pass "Niveth Files Change Wallpaper menu"
else
    if grep -Rqs "Change Wallpaper" \
        "$ROOTFS/usr/local" \
        "$ROOTFS/usr/lib" 2>/dev/null; then
        pass "Niveth Files Change Wallpaper menu"
    else
        warn "Change Wallpaper entry not detected"
    fi
fi

echo
echo "=== 10. KITTY ==="

check_file \
    "$ROOTFS/usr/local/bin/niveth-kitty-theme" \
    "Niveth Kitty theme executable"

check_file \
    "$ROOTFS/usr/lib/niveth/kitty/niveth-context-menu.py" \
    "Niveth Kitty context menu"

if grep -Rqs "/usr/lib/niveth/kitty/niveth-context-menu.py" \
    "$ROOTFS/etc/skel" "$ROOTFS/usr/lib" "$ROOTFS/etc" 2>/dev/null; then
    pass "Kitty context-menu path found"
else
    warn "Kitty context-menu path needs manual verification"
fi

echo
echo "=== 11. WALLPAPER SERVICES ==="

check_file \
    "$ROOTFS/usr/local/bin/niveth-wallpaper-chooser.py" \
    "Wallpaper chooser"

check_file \
    "$ROOTFS/usr/local/bin/niveth-wallpaper-time.py" \
    "Wallpaper time service script"

if grep -Rqs "/usr/local/bin/niveth-wallpaper-time.py" \
    "$ROOTFS/etc/systemd" "$ROOTFS/usr/lib/systemd" 2>/dev/null; then
    pass "Wallpaper service path is corrected"
else
    warn "Wallpaper service path needs verification"
fi

echo
echo "=== 12. BRAVE Niveth THEME / NEW TAB ==="

check_file     "$ROOTFS/usr/local/bin/niveth-brave"     "Niveth Brave wrapper"

check_file     "$ROOTFS/usr/share/applications/brave-browser.desktop"     "Niveth Brave launcher"

check_file     "$ROOTFS/etc/skel/.local/share/niveth/brave/newtab/manifest.json"     "Niveth Brave New Tab manifest"

check_file     "$ROOTFS/etc/skel/.local/share/niveth/brave/newtab/newtab.html"     "Niveth Brave New Tab page"

check_file     "$ROOTFS/etc/skel/.local/share/niveth/brave/themes/light/manifest.json"     "Niveth Brave Light theme"

check_file     "$ROOTFS/etc/skel/.local/share/niveth/brave/themes/dark/manifest.json"     "Niveth Brave Dark theme"

echo
echo "=== 13. BRAVE PROFILE ==="

if [ -d "$ROOTFS/etc/skel/.config/BraveSoftware/Brave-Browser" ]; then
    pass "Niveth Brave default profile present in /etc/skel"
else
    fail "Niveth Brave default profile missing from /etc/skel"
fi

echo "=== 14. MANIFEST ==="

check_file "$MANIFEST" "Niveth components manifest"

echo
echo
echo "=== 14B. LICENSING / SOURCE COMPLIANCE ==="

check_file     "$ROOTFS/usr/share/doc/niveth/LICENSE"     "Niveth GPL license"

check_file     "$ROOTFS/usr/share/doc/niveth/COPYRIGHT.md"     "Niveth copyright notice"

check_file     "$ROOTFS/usr/share/doc/niveth/BRANDING-NOTICE.md"     "Niveth branding notice"

check_file     "$ROOTFS/usr/share/doc/niveth/THIRD-PARTY-NOTICES.md"     "Third-party notices"

check_file     "$ROOTFS/usr/share/doc/niveth/SOURCE-CODE.md"     "Corresponding source notice"

check_file     "$ROOTFS/usr/share/doc/niveth/LICENSES/GPL-3.0.txt"     "GPL-3.0 license text"

check_file     "$ROOTFS/usr/share/doc/niveth/license-inventory.tsv"     "Release license inventory"

if find "$ROOTFS/usr/share/src"     -maxdepth 1     -type f     -name 'niveth-linux-*-corresponding-source.tar.gz'     -print -quit 2>/dev/null | grep -q .
then
    pass "Niveth corresponding source archive"
else
    fail "Niveth corresponding source archive missing"
fi

echo "=== 15. BRAVE SOURCE ASSETS ==="

check_file     "$PROJECT_ROOT/desktop/defaults/brave/brave-browser.desktop"     "Brave desktop entry source"

check_file     "$PROJECT_ROOT/desktop/defaults/brave/niveth-brave"     "Brave launcher source"

check_file     "$PROJECT_ROOT/desktop/defaults/brave/newtab/manifest.json"     "Brave New Tab manifest source"

check_file     "$PROJECT_ROOT/desktop/defaults/brave/newtab/newtab.html"     "Brave New Tab page source"

check_file     "$PROJECT_ROOT/desktop/defaults/brave/newtab/script.js"     "Brave New Tab script source"

check_file     "$PROJECT_ROOT/desktop/defaults/brave/newtab/assets/light-wallpaper.png"     "Brave New Tab Light wallpaper"

check_file     "$PROJECT_ROOT/desktop/defaults/brave/newtab/assets/dark-wallpaper.png"     "Brave New Tab Dark wallpaper"

check_dir     "$PROJECT_ROOT/desktop/defaults/brave/profile"     "Brave default profile source"

echo "============================================================"
echo "AUDIT RESULT"
echo "============================================================"

echo "PASS : $PASS"
echo "WARN : $WARN"
echo "FAIL : $FAIL"
echo

if [ "$FAIL" -eq 0 ]; then
    echo "[READY] No blocking failures found."
    echo "        Next step: cleanup old build artifacts and build final ISO."
else
    echo "[BLOCKED] Fix the FAIL items before final ISO build."
    exit 1
fi
