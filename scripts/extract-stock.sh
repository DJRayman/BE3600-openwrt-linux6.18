#!/bin/sh
# Extract lib/firmware from a raw dump of the stock system partition
# (slot B, "rootfs_1" = mtd20). The Q6 Wi-Fi firmware and board data are
# Qualcomm/Xiaomi binaries: they are taken from YOUR router, never from git.
#
# usage: extract-stock.sh <rootfs_1.bin> [out dir, default ./stock]
# needs: ubireader_extract_images (pip/pipx install ubi_reader), unsquashfs
set -e
DUMP="$1"
OUT="${2:-./stock}"
[ -f "$DUMP" ] || { echo "usage: $0 <rootfs_1.bin> [out dir]"; exit 1; }
for t in ubireader_extract_images unsquashfs; do
	command -v "$t" >/dev/null || { echo "missing: $t"; exit 1; }
done

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
ubireader_extract_images -o "$TMP" "$DUMP" >/dev/null
IMG=$(find "$TMP" -name '*ubi_rootfs*' -type f | head -1)
[ -n "$IMG" ] || { echo "no ubi_rootfs volume in $DUMP"; find "$TMP" -type f; exit 1; }

rm -rf "$OUT/rootfs"
mkdir -p "$OUT"
unsquashfs -q -d "$OUT/rootfs" "$IMG" lib/firmware >/dev/null
FW="$OUT/rootfs/lib/firmware"
[ -d "$FW/IPQ5332/WIFI_FW/qcn6432" ] || { echo "no IPQ5332/WIFI_FW/qcn6432 in $FW"; exit 1; }
echo "stock firmware: $FW"
