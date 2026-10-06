#!/usr/bin/env bash
set -Eeuo pipefail

ROOTFS="${1:?ROOTFS argument missing}"
OUT="${2:-$ROOTFS/usr/share/doc/niveth/license-inventory.tsv}"

DOC_DIR="$(dirname "$OUT")"
mkdir -p "$DOC_DIR"

{
    printf 'TYPE\tNAME\tVERSION\tLICENSE_SOURCE\n'

    if [[ -f "$ROOTFS/var/lib/dpkg/status" ]]; then
        dpkg-query \
            --admindir="$ROOTFS/var/lib/dpkg" \
            -W \
            -f='${binary:Package}\t${Version}\n' 2>/dev/null |
        while IFS=$'\t' read -r pkg version; do
            base="${pkg%%:*}"

            copyright="$ROOTFS/usr/share/doc/$base/copyright"

            if [[ -f "$copyright" ]]; then
                printf 'dpkg\t%s\t%s\t%s\n' \
                    "$pkg" \
                    "$version" \
                    "/usr/share/doc/$base/copyright"
            else
                printf 'dpkg\t%s\t%s\tMISSING-COPYRIGHT-FILE\n' \
                    "$pkg" \
                    "$version"
            fi
        done
    fi

    # Snap inventory
    if [[ -d "$ROOTFS/snap" ]]; then
        find "$ROOTFS/snap" -mindepth 1 -maxdepth 1 \
            -type d -printf '%f\n' 2>/dev/null |
        sort |
        while read -r snap; do
            [[ "$snap" == "bin" ]] && continue
            [[ "$snap" == "snap" ]] && continue
            printf 'snap\t%s\t\t%s\n' \
                "$snap" \
                "/snap/$snap"
        done
    fi

    # Flatpak inventory
    for base in \
        "$ROOTFS/var/lib/flatpak/app" \
        "$ROOTFS/var/lib/flatpak/runtime"
    do
        [[ -d "$base" ]] || continue

        find "$base" -mindepth 1 -maxdepth 2 \
            -type d -printf '%p\n' 2>/dev/null |
        sed "s#^$ROOTFS##" |
        sort -u |
        while read -r item; do
            printf 'flatpak\t%s\t\t%s\n' \
                "$(basename "$item")" \
                "$item"
        done
    done

    # Non-package software trees requiring release review.
    for dir in \
        "$ROOTFS/opt" \
        "$ROOTFS/usr/local" \
        "$ROOTFS/usr/lib/niveth" \
        "$ROOTFS/usr/share/niveth"
    do
        [[ -d "$dir" ]] || continue

        find "$dir" -type f \
            \( -iname 'LICENSE' \
               -o -iname 'LICENSE.*' \
               -o -iname 'COPYING' \
               -o -iname 'COPYING.*' \
               -o -iname 'NOTICE' \
               -o -iname 'NOTICE.*' \
               -o -iname 'copyright' \) \
            -print 2>/dev/null |
        sed "s#^$ROOTFS##" |
        sort -u |
        while read -r item; do
            printf 'notice-file\t%s\t\t%s\n' \
                "$(basename "$item")" \
                "$item"
        done
    done

} > "$OUT"

echo "License inventory generated:"
echo "$OUT"
echo "Entries: $(wc -l < "$OUT")"
