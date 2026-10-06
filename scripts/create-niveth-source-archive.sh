#!/usr/bin/env bash
set -Eeuo pipefail

PROJECT_ROOT="${1:?PROJECT_ROOT argument missing}"
ROOTFS="${2:?ROOTFS argument missing}"

VERSION="${NIVETH_VERSION:-0.1.1}"
DEST_DIR="$ROOTFS/usr/share/src"
ARCHIVE="$DEST_DIR/niveth-linux-${VERSION}-corresponding-source.tar.gz"

mkdir -p "$DEST_DIR"

tar \
    --exclude='./.git' \
    --exclude='./build' \
    --exclude='./iso' \
    --exclude='./*.before-*' \
    --exclude='./*.bak' \
    --exclude='./backup-*' \
    --exclude='./*-backup-*' \
    --exclude='./*.log' \
    -czf "$ARCHIVE" \
    -C "$PROJECT_ROOT" \
    .

chmod 0644 "$ARCHIVE"

echo "Corresponding source archive:"
echo "$ARCHIVE"

sha256sum "$ARCHIVE"
