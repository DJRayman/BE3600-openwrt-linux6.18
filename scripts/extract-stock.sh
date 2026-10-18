#!/bin/sh
# Extract lib/firmware of the stock Xiaomi RD16 system. The Q6 Wi-Fi firmware
# and board data are Qualcomm/Xiaomi binaries: they come from your router or
# from Xiaomi's own firmware package, never from git.
#
# usage: extract-stock.sh <input> [out dir, default ./stock]
#   <input> is either
#     - a raw dump of the stock system partition (slot B, "rootfs_1"), or
#     - a Xiaomi firmware package, miwifi_rd16_firmware_*.bin (HDR1 container;
#       ubi_reader finds the UBI image inside it)
# needs: ubireader_extract_images (pipx install ubi_reader), unsquashfs
set -e
IN="$1"
OUT="${2:-./stock}"
TESTED="WLAN.WBE.1.3.r4-00038"

[ -f "$IN" ] || { echo "usage: $0 <rootfs_1.bin | miwifi_rd16_firmware_*.bin> [out dir]"; exit 1; }
for t in ubireader_extract_images unsquashfs; do
	command -v "$t" >/dev/null || { echo "missing: $t"; exit 1; }
done

case "$(head -c 4 "$IN")" in
HDR1) echo "input: Xiaomi firmware package (HDR1)" ;;
UBI#) echo "input: raw UBI dump" ;;
*)    echo "input: unknown format, trying anyway" ;;
esac

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
ubireader_extract_images -o "$TMP" "$IN" >/dev/null
IMG=$(find "$TMP" -name '*vol-ubi_rootfs*' -type f | head -1)
[ -n "$IMG" ] || { echo "no ubi_rootfs volume found in $IN, volumes:"; find "$TMP" -type f; exit 1; }

rm -rf "$OUT/rootfs"
mkdir -p "$OUT"
unsquashfs -q -d "$OUT/rootfs" "$IMG" lib/firmware >/dev/null
FW="$OUT/rootfs/lib/firmware"
[ -d "$FW/IPQ5332/WIFI_FW/qcn6432" ] || {
	echo "no IPQ5332/WIFI_FW/qcn6432 in $FW - is this an RD16 (BE3600 without 2.5G) image?"
	exit 1
}

VER=$(cat "$FW"/IPQ5332/WIFI_FW/q6_fw0.b* 2>/dev/null | strings -n 20 |
	grep -m1 -o 'WLAN\.[A-Za-z0-9.]*-[0-9]*' || true)
echo "stock firmware: $FW"
echo "Q6 WLAN firmware: ${VER:-unknown}"
case "$VER" in
"$TESTED"*) ;;
*) echo "NOTE: this port was verified with $TESTED; another version may need other memory regions or boot-args" ;;
esac
