#!/usr/bin/env bash
#
# Niveth RootFS Audit
#
# Read-only audit of the Niveth build/rootfs.
# It checks the major components assembled recently:
#   - Niveth Cleaner
#   - Niveth Power Action / GTK dialog
#   - Niveth UI Test extension + power integration
#   - Niveth System Monitor extension
#   - required desktop/system dependencies
#   - wallpaper-service artifacts when present
#
# Usage:
#   ./scripts/check-niveth-rootfs.sh
#   ./scripts/check-niveth-rootfs.sh /path/to/rootfs
#
# Exit:
#   0 = no FAIL items
#   1 = one or more FAIL items
#   2 = invalid invocation / missing rootfs

set -u
set -o pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"
ROOTFS="${1:-$PROJECT_ROOT/build/rootfs}"

PASS_COUNT=0
WARN_COUNT=0
FAIL_COUNT=0

section() {
    printf '\n============================================================\n'
    printf ' %s\n' "$1"
    printf '============================================================\n'
}

pass() {
    PASS_COUNT=$((PASS_COUNT + 1))
    printf '[PASS] %s\n' "$1"
}

warn() {
    WARN_COUNT=$((WARN_COUNT + 1))
    printf '[WARN] %s\n' "$1"
}

fail() {
    FAIL_COUNT=$((FAIL_COUNT + 1))
    printf '[FAIL] %s\n' "$1"
}

check_file() {
    local rel="$1"
    local label="${2:-$rel}"
    if [[ -f "$ROOTFS/$rel" ]]; then
        pass "$label"
        return 0
    fi
    fail "$label missing: $ROOTFS/$rel"
    return 1
}

check_exec() {
    local rel="$1"
    local label="${2:-$rel}"
    if [[ -x "$ROOTFS/$rel" ]]; then
        pass "$label executable"
        return 0
    fi
    fail "$label missing or not executable: $ROOTFS/$rel"
    return 1
}

check_contains() {
    local file="$1"
    local pattern="$2"
    local label="$3"

    if [[ ! -f "$file" ]]; then
        fail "$label (file missing)"
        return 1
    fi

    if grep -Fq -- "$pattern" "$file"; then
        pass "$label"
        return 0
    fi

    fail "$label"
    return 1
}

check_not_contains() {
    local file="$1"
    local pattern="$2"
    local label="$3"

    if [[ ! -f "$file" ]]; then
        fail "$label (file missing)"
        return 1
    fi

    if grep -Fq -- "$pattern" "$file"; then
        fail "$label"
        return 1
    fi

    pass "$label"
    return 0
}

check_any_file() {
    local label="$1"
    shift
    local rel

    for rel in "$@"; do
        if [[ -f "$ROOTFS/$rel" ]]; then
            pass "$label: $rel"
            return 0
        fi
    done

    fail "$label missing"
    return 1
}

echo
echo "============================================================"
echo " Niveth RootFS Audit"
echo "============================================================"
echo
echo "Project : $PROJECT_ROOT"
echo "RootFS  : $ROOTFS"

if [[ ! -d "$ROOTFS" ]]; then
    echo
    echo "ERROR: RootFS does not exist."
    echo "Expected: $ROOTFS"
    exit 2
fi

section "1. ROOTFS BASIC STRUCTURE"

for d in \
    usr/bin \
    usr/local/bin \
    usr/share/gnome-shell/extensions \
    etc
do
    if [[ -d "$ROOTFS/$d" ]]; then
        pass "Directory present: /$d"
    else
        fail "Directory missing: /$d"
    fi
done

section "2. REQUIRED SYSTEM COMPONENTS"

check_exec "usr/bin/apt-get" "APT"
check_exec "usr/bin/pkexec" "PolicyKit pkexec"
check_exec "usr/bin/python3" "Python 3"
check_exec "usr/bin/notify-send" "notify-send"
check_exec "usr/bin/systemctl" "systemctl"
check_exec "usr/bin/loginctl" "loginctl"

if [[ -x "$ROOTFS/usr/bin/resolvectl" ]]; then
    pass "DNS tool: resolvectl"
elif [[ -x "$ROOTFS/usr/bin/systemd-resolve" ]]; then
    pass "DNS tool: systemd-resolve"
else
    fail "No supported DNS cache flush tool found"
fi

check_exec "usr/bin/gjs" "GJS"

section "3. NIVETH CLEANER"

CLEANER="$ROOTFS/usr/local/bin/niveth-cleaner-helper"

check_exec "usr/local/bin/niveth-cleaner-helper" "Niveth Cleaner"

for pattern in \
    "--safe-clean" \
    "--full-clean" \
    "--power-clean" \
    "browser_running()" \
    "close_running_browsers()" \
    "NIVETH_POWER_CLEAN" \
    "apt-get clean" \
    "resolvectl flush-caches" \
    "systemd-resolve --flush-caches" \
    "mozilla/firefox" \
    ".librewolf" \
    ".config/chromium" \
    ".config/google-chrome" \
    ".config/BraveSoftware/Brave-Browser" \
    ".config/vivaldi" \
    ".config/microsoft-edge" \
    ".config/opera"
do
    check_contains "$CLEANER" "$pattern" "Cleaner contains: $pattern"
done

check_contains "$CLEANER" '("visits", "DELETE FROM visits")' "Chromium history visits cleanup"
check_contains "$CLEANER" '("urls", "DELETE FROM urls")' "Chromium history URLs cleanup"
check_contains "$CLEANER" '("cookies", "DELETE FROM cookies")' "Chromium cookies cleanup"
check_contains "$CLEANER" '"moz_historyvisits"' "Firefox history cleanup"
check_contains "$CLEANER" '"moz_cookies"' "Firefox cookies cleanup"

check_not_contains "$CLEANER" 'rm -rf -- "$profile/Bookmarks"' "Cleaner does not delete Chromium Bookmarks"
check_not_contains "$CLEANER" 'rm -rf -- "$profile/Login Data"' "Cleaner does not delete Chromium Login Data"
check_not_contains "$CLEANER" 'rm -rf -- "$profile/places.sqlite"' "Cleaner does not delete Firefox places.sqlite"

section "4. APT CLEANUP"

check_contains "$CLEANER" "if command -v pkexec" "Cleaner uses pkexec for APT authorization"
check_contains "$CLEANER" "pkexec apt-get clean" "Cleaner performs pkexec apt-get clean"

section "5. NIVETH POWER ACTION"

POWER="$ROOTFS/usr/local/bin/niveth-power-action"

check_exec "usr/local/bin/niveth-power-action" "Niveth Power Action"

for pattern in \
    "show_power_dialog" \
    "NIVETH_DIALOG" \
    "NIVETH_HELPER" \
    "--restart" \
    "--shutdown" \
    "--power-clean" \
    "systemctl reboot" \
    "systemctl poweroff"
do
    check_contains "$POWER" "$pattern" "Power Action contains: $pattern"
done

section "6. NIVETH GTK POWER DIALOG"

DIALOG="$ROOTFS/usr/local/bin/niveth-power-dialog.py"

check_exec "usr/local/bin/niveth-power-dialog.py" "Niveth GTK power dialog"

if [[ -f "$DIALOG" ]]; then
    if python3 - "$DIALOG" <<'PY'
import ast
import sys
from pathlib import Path

path = Path(sys.argv[1])
ast.parse(path.read_text())
print("OK")
PY
    then
        pass "Power dialog Python syntax"
    else
        fail "Power dialog Python syntax"
    fi
fi

for pattern in \
    "Clean & Restart" \
    "Restart without cleaning" \
    "Clean & Shutdown" \
    "Shutdown without cleaning" \
    "Cancel"
do
    check_contains "$DIALOG" "$pattern" "Power dialog contains: $pattern"
done

section "7. NIVETH UI TEST EXTENSION"

EXT="$ROOTFS/usr/share/gnome-shell/extensions/niveth-ui-test@nivethos"
EXT_JS="$EXT/extension.js"
EXT_META="$EXT/metadata.json"
EXT_CSS="$EXT/stylesheet.css"

check_file "usr/share/gnome-shell/extensions/niveth-ui-test@nivethos/extension.js" \
    "Niveth UI extension.js"
check_file "usr/share/gnome-shell/extensions/niveth-ui-test@nivethos/metadata.json" \
    "Niveth UI metadata.json"
check_file "usr/share/gnome-shell/extensions/niveth-ui-test@nivethos/stylesheet.css" \
    "Niveth UI stylesheet.css"

for pattern in \
    "/usr/local/bin/niveth-power-action --restart" \
    "/usr/local/bin/niveth-power-action --shutdown" \
    "text === 'Restart'" \
    "text === 'Power Off'" \
    "Suspend" \
    "Lock Screen" \
    "Log Out"
do
    check_contains "$EXT_JS" "$pattern" "Niveth UI contains: $pattern"
done

check_not_contains "$EXT_JS" \
    "gnome-session-quit --reboot" \
    "No legacy direct GNOME reboot command"

check_not_contains "$EXT_JS" \
    "gnome-session-quit --power-off" \
    "No legacy direct GNOME power-off command"

section "8. NIVETH SYSTEM MONITOR"

MON="$ROOTFS/usr/share/gnome-shell/extensions/niveth-system-monitor@nivethos"

check_file "usr/share/gnome-shell/extensions/niveth-system-monitor@nivethos/extension.js" \
    "Niveth System Monitor extension.js"
check_file "usr/share/gnome-shell/extensions/niveth-system-monitor@nivethos/metadata.json" \
    "Niveth System Monitor metadata.json"

if [[ -f "$MON/extension.js" ]]; then
    check_contains "$MON/extension.js" "_readAudioLine" \
        "System Monitor audio reader present"
fi

section "9. WALLPAPER SERVICE / THEME ARTIFACTS"

wallpaper_units=()
while IFS= read -r -d '' f; do
    wallpaper_units+=("$f")
done < <(
    find "$ROOTFS/etc/systemd" "$ROOTFS/usr/lib/systemd" "$ROOTFS/usr/share/systemd" \
        -type f -iname '*niveth*wallpaper*.service' -print0 2>/dev/null
)

if (( ${#wallpaper_units[@]} > 0 )); then
    pass "Niveth wallpaper service artifact present"
    for f in "${wallpaper_units[@]}"; do
        printf '       %s\n' "${f#"$ROOTFS"}"
    done
else
    warn "No Niveth wallpaper service unit found in rootfs (not enough evidence to mark FAIL)"
fi

bg_count=0
if [[ -d "$ROOTFS/usr/share/backgrounds" ]]; then
    bg_count="$(find "$ROOTFS/usr/share/backgrounds" -type f \
        \( -iname '*niveth*' -o -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.webp' \) \
        2>/dev/null | wc -l)"
fi

if (( bg_count > 0 )); then
    pass "Wallpaper/background assets present: $bg_count file(s)"
else
    warn "No wallpaper assets found under /usr/share/backgrounds"
fi

section "10. CLEANER NOT EXPOSED AS A LAUNCHER APP"

launcher_hits=0
while IFS= read -r -d '' f; do
    if grep -qiE 'niveth-cleaner|niveth-power-action|niveth-power-dialog' "$f" 2>/dev/null; then
        printf '       Launcher reference: %s\n' "${f#"$ROOTFS"}"
        launcher_hits=$((launcher_hits + 1))
    fi
done < <(
    find "$ROOTFS/usr/share/applications" "$ROOTFS/usr/local/share/applications" \
        -type f -name '*.desktop' -print0 2>/dev/null
)

if (( launcher_hits == 0 )); then
    pass "Cleaner/Power helper is not exposed as a desktop launcher"
else
    fail "Found $launcher_hits launcher file(s) referencing Cleaner/Power helper"
fi

section "11. FILE PERMISSIONS"

for rel in \
    usr/local/bin/niveth-cleaner-helper \
    usr/local/bin/niveth-power-action \
    usr/local/bin/niveth-power-dialog.py
do
    if [[ -f "$ROOTFS/$rel" && -x "$ROOTFS/$rel" ]]; then
        perms="$(stat -c '%A %U:%G' "$ROOTFS/$rel" 2>/dev/null || true)"
        pass "Executable permissions OK: /$rel ($perms)"
    elif [[ -e "$ROOTFS/$rel" ]]; then
        fail "Not executable: /$rel"
    fi
done

section "12. ROOTFS SEARCH FOR BROKEN LEGACY POWER REFERENCES"

legacy_hits=0
while IFS= read -r line; do
    printf '%s\n' "$line"
    legacy_hits=$((legacy_hits + 1))
done < <(
    grep -RniE \
        'gnome-session-quit --reboot|gnome-session-quit --power-off' \
        "$ROOTFS/usr/share/gnome-shell/extensions" \
        --include='extension.js' 2>/dev/null || true
)

if (( legacy_hits == 0 )); then
    pass "No legacy direct reboot/power-off commands in GNOME extensions"
else
    fail "Legacy direct reboot/power-off command(s) found in GNOME extensions"
fi

section "13. SOURCE -> ROOTFS INTEGRITY (WHEN SOURCE EXISTS)"

for pair in \
    "scripts/niveth-cleaner-helper|usr/local/bin/niveth-cleaner-helper" \
    "scripts/niveth-power-action|usr/local/bin/niveth-power-action" \
    "scripts/niveth-power-dialog.py|usr/local/bin/niveth-power-dialog.py"
do
    src="${pair%%|*}"
    dst="${pair##*|}"

    if [[ -f "$PROJECT_ROOT/$src" && -f "$ROOTFS/$dst" ]]; then
        src_hash="$(sha256sum "$PROJECT_ROOT/$src" | awk '{print $1}')"
        dst_hash="$(sha256sum "$ROOTFS/$dst" | awk '{print $1}')"

        if [[ "$src_hash" == "$dst_hash" ]]; then
            pass "Hash match: $src -> /$dst"
        else
            fail "Hash mismatch: $src -> /$dst"
            printf '       source: %s\n' "$src_hash"
            printf '       rootfs : %s\n' "$dst_hash"
        fi
    else
        warn "Source/rootfs pair not available for hash check: $src -> /$dst"
    fi
done

section "14. ROOTFS BASH SYNTAX CHECK"

if [[ -f "$CLEANER" ]]; then
    if bash -n "$CLEANER" 2>/dev/null; then
        pass "Cleaner Bash syntax"
    else
        fail "Cleaner Bash syntax"
    fi
fi

echo
echo "============================================================"
echo " AUDIT SUMMARY"
echo "============================================================"
printf '[PASS] %d\n' "$PASS_COUNT"
printf '[WARN] %d\n' "$WARN_COUNT"
printf '[FAIL] %d\n' "$FAIL_COUNT"
echo

if (( FAIL_COUNT > 0 )); then
    echo "RESULT: ROOTFS HAS FAILURES"
    exit 1
fi

if (( WARN_COUNT > 0 )); then
    echo "RESULT: ROOTFS PASSED CORE CHECKS WITH WARNINGS"
else
    echo "RESULT: ROOTFS PASSED ALL CHECKS"
fi

exit 0
