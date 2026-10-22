#!/bin/bash
# OpenWrt for the Xiaomi BE3600 (RD16): prepare an OpenWrt tree and build it.
#
#   ./build.sh                    build both variants (base, podkop)
#   VARIANTS=base ./build.sh      only the base image
#   VARIANTS=podkop ./build.sh    only the podkop image
#
# Environment (all optional):
#   OPENWRT_DIR  OpenWrt tree to use; default: the current directory if it
#                is an OpenWrt tree, else ./openwrt next to this script
#                (cloned on first run)
#   STOCK_FW     stock rootfs lib/firmware (see README, "Stock Wi-Fi
#                firmware"); default ./stock/rootfs/lib/firmware
#   OUT_DIR      where the images go; default ./out
#   JOBS         parallel make jobs; default: number of CPUs
#   KEEP_TREE=1  do not reset the OpenWrt tree to BASE + patches
#   DSA_TAGGING  switch tagging on first boot: native (default) or 8021q;
#                a mode chosen later with yt921x-tagging is kept
set -euo pipefail

PROJECT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_REPO=https://github.com/fivefold3/openwrt-gl-be3600.git
BASE_BRANCH=gl-be3600
BASE=e46ea77ba4f431c72301c3d07220e454450b3070
BRANCH=xiaomi-rd16
PODKOP_TAG=v0.6.1

is_openwrt_tree() { [ -x "$1/scripts/feeds" ] && [ -f "$1/include/toplevel.mk" ]; }

if [ -n "${OPENWRT_DIR:-}" ]; then
	SRC="$OPENWRT_DIR"
elif is_openwrt_tree "$PWD"; then
	SRC="$PWD"
else
	SRC="$PROJECT/openwrt"
fi
STOCK_FW="${STOCK_FW:-$PROJECT/stock/rootfs/lib/firmware}"
OUT="${OUT_DIR:-$PROJECT/out}"
JOBS="${JOBS:-$(nproc)}"
VARIANTS="${VARIANTS:-base podkop}"
DSA_TAGGING="${DSA_TAGGING:-native}"

die() { echo "ERROR: $*" >&2; exit 1; }
log() { echo "==> $*"; }

# --- sanity checks -------------------------------------------------------
if grep -qi microsoft /proc/version 2>/dev/null; then
	case "$(realpath -m "$SRC")" in
	/mnt/*) die "OpenWrt tree on a Windows drive ($SRC): use the WSL filesystem, e.g. OPENWRT_DIR=~/openwrt-rd16" ;;
	esac
	echo "$PATH" | grep -q '/mnt/c/' &&
		die "PATH contains Windows paths: set appendWindowsPath=false in /etc/wsl.conf, run 'wsl --shutdown' and start the distro again"
fi
[ -d "$STOCK_FW/IPQ5332/WIFI_FW/qcn6432" ] ||
	die "stock Wi-Fi firmware not found in $STOCK_FW (see README, \"Stock Wi-Fi firmware\")"
for v in $VARIANTS; do
	case "$v" in base|podkop) ;; *) die "unknown variant '$v' (base, podkop)" ;; esac
done
case "$DSA_TAGGING" in native|8021q) ;; *) die "unknown DSA_TAGGING '$DSA_TAGGING' (native, 8021q)" ;; esac

# --- OpenWrt tree --------------------------------------------------------
if [ ! -d "$SRC/.git" ]; then
	log "cloning $BASE_REPO ($BASE_BRANCH) into $SRC"
	git clone -b "$BASE_BRANCH" "$BASE_REPO" "$SRC"
fi
cd "$SRC"
is_openwrt_tree . || die "$SRC is not an OpenWrt tree"

if [ "${KEEP_TREE:-0}" != 1 ]; then
	git cat-file -e "$BASE^{commit}" 2>/dev/null || git fetch origin "$BASE_BRANCH"
	log "resetting $SRC to $BASE + patches (branch $BRANCH)"
	git am --abort >/dev/null 2>&1 || true
	git checkout -q -B "$BRANCH" "$BASE"
	git reset -q --hard "$BASE"
	git -c user.name="build.sh" -c user.email="build@localhost" \
		am -q "$PROJECT"/patches/[0-9][0-9][0-9][0-9]-*.patch
fi

# --- feeds ---------------------------------------------------------------
[ -f feeds.conf ] || cp feeds.conf.default feeds.conf
if ! grep -q "^src-git podkop " feeds.conf; then
	echo "src-git podkop https://github.com/itdoginfo/podkop.git;$PODKOP_TAG" >> feeds.conf
fi
if [ ! -d feeds/packages ] || [ ! -d feeds/luci ]; then
	log "updating feeds"
	./scripts/feeds update -a
	./scripts/feeds install -a
fi
[ -d feeds/podkop ] || ./scripts/feeds update podkop
sh "$PROJECT/scripts/podkop-fixups.sh" "$SRC" "${PODKOP_TAG#v}"
./scripts/feeds install -p podkop podkop luci-app-podkop >/dev/null
./scripts/feeds install luci-proto-wireguard >/dev/null

# --- files/ overlay (generated, not part of git) --------------------------
log "stock Wi-Fi firmware -> files/lib/firmware"
python3 "$PROJECT/scripts/stock-wifi-fw.py" "$STOCK_FW" files/lib/firmware
python3 "$PROJECT/scripts/luci-wan-first.py" feeds/luci files
DEFAULTS=files/etc/uci-defaults/99-rd16-dsa-tagging
if [ "$DSA_TAGGING" = native ]; then
	rm -f "$DEFAULTS"
else
	log "switch tagging on first boot: $DSA_TAGGING"
	mkdir -p "${DEFAULTS%/*}"
	# only when unset, so sysupgrade keeps a mode chosen with yt921x-tagging
	cat > "$DEFAULTS" <<-EOT
	uci -q get network.globals.dsa_tagging >/dev/null && exit 0
	uci -q get network.globals >/dev/null || uci set network.globals=globals
	uci set network.globals.dsa_tagging=$DSA_TAGGING
	uci commit network
	EOT
fi

# --- build ---------------------------------------------------------------
TGT=bin/targets/qualcommbe/ipq53xx
SB_INIT=feeds/packages/net/sing-box/files/sing-box.init
mkdir -p "$OUT"

build_variant() {
	local v="$1" dst="$OUT/$1"

	log "[$v] configuring"
	cp "$PROJECT/configs/xiaomi_rd16.config" .config
	rm -f files/etc/init.d/sing-box
	if [ "$v" = podkop ]; then
		cat "$PROJECT/configs/xiaomi_rd16-podkop.config" >> .config
		# sing-box: cap the Go heap, the box has ~20-35 MiB available
		mkdir -p files/etc/init.d
		sed '/procd_set_param command/a\	procd_set_param env GOMEMLIMIT=24MiB GOGC=50' \
			"$SB_INIT" > files/etc/init.d/sing-box
		chmod 755 files/etc/init.d/sing-box
	fi
	make defconfig >/dev/null
	make -j"$JOBS" download

	log "[$v] building (log: $OUT/build-$v.log)"
	rm -f "$TGT"/*xiaomi_rd16*
	if ! make -j"$JOBS" > "$OUT/build-$v.log" 2>&1 ||
	   ! ls "$TGT"/*xiaomi_rd16*squashfs-sysupgrade.bin >/dev/null 2>&1; then
		echo "[$v] build failed, re-running with -j1 V=s into $OUT/build-$v-verbose.log"
		make -j1 V=s > "$OUT/build-$v-verbose.log" 2>&1 || true
		tail -40 "$OUT/build-$v-verbose.log"
		exit 1
	fi

	rm -rf "$dst"; mkdir -p "$dst"
	cp "$TGT"/*xiaomi_rd16*squashfs-factory.ubi "$TGT"/*xiaomi_rd16*squashfs-sysupgrade.bin "$dst/"
	# the RAM-boot image is for installation/recovery: take it from base
	[ "$v" = base ] && cp "$TGT"/*xiaomi_rd16*initramfs*.itb "$dst/"
	(cd "$dst" && sha256sum -- * > sha256sums)
	log "[$v] images in $dst"
	ls -l "$dst"
}

for v in $VARIANTS; do
	build_variant "$v"
done
rm -f files/etc/init.d/sing-box
log "done"
