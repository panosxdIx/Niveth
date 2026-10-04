#!/usr/bin/env bash

set -Eeuo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ROOTFS="$PROJECT_ROOT/build/rootfs"

SOURCE_DCONF="$PROJECT_ROOT/desktop/defaults/dconf/org-gnome-shell.dconf"
ROOTFS_DCONF="$ROOTFS/etc/dconf/db/local.d/00-niveth-defaults"

if [[ "$EUID" -ne 0 ]]; then
    echo
    echo "ERROR: run this script with sudo:"
    echo "  sudo $0"
    echo
    exit 1
fi

if [[ ! -d "$ROOTFS" ]]; then
    echo "ERROR: rootfs does not exist:"
    echo "  $ROOTFS"
    exit 1
fi

if [[ ! -f "$SOURCE_DCONF" ]]; then
    echo "ERROR: source GNOME shell dconf file does not exist:"
    echo "  $SOURCE_DCONF"
    exit 1
fi

if [[ ! -f "$ROOTFS_DCONF" ]]; then
    echo "ERROR: rootfs GNOME shell dconf file does not exist:"
    echo "  $ROOTFS_DCONF"
    exit 1
fi

echo
echo "============================================================"
echo "         NIVETH ROOTFS DEFAULTS REPAIR"
echo "============================================================"
echo

TIMESTAMP="$(date +%Y%m%d-%H%M%S)"

SOURCE_BACKUP="$SOURCE_DCONF.backup-$TIMESTAMP"
ROOTFS_BACKUP="$ROOTFS_DCONF.backup-$TIMESTAMP"

cp -a "$SOURCE_DCONF" "$SOURCE_BACKUP"
cp -a "$ROOTFS_DCONF" "$ROOTFS_BACKUP"

echo "Backups created:"
echo "  $SOURCE_BACKUP"
echo "  $ROOTFS_BACKUP"
echo

python3 - "$SOURCE_DCONF" "$ROOTFS_DCONF" <<'PY'
from pathlib import Path
import ast
import re
import sys

source_path = Path(sys.argv[1])
rootfs_path = Path(sys.argv[2])

REMOVE_FROM_ENABLED = {
    "wack-lockscreen-clock@rinzler69-wastaken.github.com",
}

REQUIRED_ENABLED = {
    "niveth-dock@nivethos",
    "niveth-ui-test@nivethos",
    "niveth-lockscreen@nivethos",
}

REQUIRED_DISABLED = {
    "niveth-topbar@nivethos",
    "niveth-app-refresh@nivethos",
    "ubuntu-dock@ubuntu.com",
}


def normalize_dconf_file(path: Path):
    text = path.read_text(encoding="utf-8")

    enabled_match = re.search(
        r"^enabled-extensions=(\[.*\])$",
        text,
        re.MULTILINE,
    )

    disabled_match = re.search(
        r"^disabled-extensions=(\[.*\])$",
        text,
        re.MULTILINE,
    )

    if not enabled_match:
        raise SystemExit(
            f"ERROR: enabled-extensions not found in {path}"
        )

    if not disabled_match:
        raise SystemExit(
            f"ERROR: disabled-extensions not found in {path}"
        )

    enabled = ast.literal_eval(enabled_match.group(1))
    disabled = ast.literal_eval(disabled_match.group(1))

    if not isinstance(enabled, list):
        raise SystemExit(
            f"ERROR: enabled-extensions is not a list in {path}"
        )

    if not isinstance(disabled, list):
        raise SystemExit(
            f"ERROR: disabled-extensions is not a list in {path}"
        )

    enabled = [
        item for item in enabled
        if item not in REMOVE_FROM_ENABLED
    ]

    for item in REQUIRED_ENABLED:
        if item not in enabled:
            enabled.append(item)

    disabled = [
        item for item in disabled
        if item not in REQUIRED_ENABLED
    ]

    for item in REQUIRED_DISABLED:
        if item not in disabled:
            disabled.append(item)

    enabled_line = "enabled-extensions=" + repr(enabled)
    disabled_line = "disabled-extensions=" + repr(disabled)

    text = re.sub(
        r"^enabled-extensions=\[.*\]$",
        enabled_line,
        text,
        count=1,
        flags=re.MULTILINE,
    )

    text = re.sub(
        r"^disabled-extensions=\[.*\]$",
        disabled_line,
        text,
        count=1,
        flags=re.MULTILINE,
    )

    path.write_text(text, encoding="utf-8")

    print()
    print(f"Updated: {path}")
    print()
    print("enabled-extensions:")
    print(enabled_line)
    print()
    print("disabled-extensions:")
    print(disabled_line)
    print()


normalize_dconf_file(source_path)
normalize_dconf_file(rootfs_path)
PY

echo "============================================================"
echo "REBUILDING COMPILED DCONF DATABASE"
echo "============================================================"

rm -f \
    "$ROOTFS/etc/dconf/db/local" \
    "$ROOTFS/etc/dconf/db/local.lock" \
    "$ROOTFS/etc/dconf/db/local"

echo

chroot "$ROOTFS" /usr/bin/dconf update

echo
echo "============================================================"
echo "DCONF RESULT"
echo "============================================================"

if [[ -f "$ROOTFS/etc/dconf/db/local" ]]; then
    echo "OK: compiled dconf database exists."
    ls -lh "$ROOTFS/etc/dconf/db/local"
else
    echo "ERROR: /etc/dconf/db/local was not created."
    exit 1
fi

echo
echo "============================================================"
echo "FINAL NIVETH EXTENSION DEFAULTS"
echo "============================================================"

grep -E \
    '^enabled-extensions=|^disabled-extensions=' \
    "$ROOTFS_DCONF"

echo
echo "============================================================"
echo "CHECKING INSTALLED EXTENSIONS"
echo "============================================================"

ROOTFS_EXT_DIR="$ROOTFS/usr/share/gnome-shell/extensions"

python3 - "$ROOTFS_DCONF" "$ROOTFS_EXT_DIR" <<'PY'
from pathlib import Path
import ast
import re
import sys

dconf_path = Path(sys.argv[1])
ext_dir = Path(sys.argv[2])

text = dconf_path.read_text(encoding="utf-8")

match = re.search(
    r"^enabled-extensions=(\[.*\])$",
    text,
    re.MULTILINE,
)

if not match:
    raise SystemExit("ERROR: enabled-extensions not found.")

enabled = ast.literal_eval(match.group(1))

failures = 0

for ext in enabled:
    path = ext_dir / ext

    if path.is_dir():
        print(f"OK: {ext}")
    else:
        print(f"ERROR: enabled extension missing: {ext}")
        failures += 1

if failures:
    raise SystemExit(
        f"{failures} enabled extension(s) are missing."
    )
PY

echo
echo "============================================================"
echo "ROOTFS DEFAULTS REPAIR COMPLETE"
echo "============================================================"
echo
echo "Expected Niveth state:"
echo "  ENABLED : niveth-dock"
echo "  ENABLED : niveth-ui-test"
echo "  ENABLED : niveth-lockscreen"
echo "  DISABLED: niveth-topbar"
echo "  DISABLED: niveth-app-refresh"
echo "  DISABLED: ubuntu-dock"
echo
