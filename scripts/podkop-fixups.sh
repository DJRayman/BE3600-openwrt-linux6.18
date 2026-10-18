#!/bin/sh
# Adjust the itdoginfo/podkop feed for this build.
# usage: podkop-fixups.sh <openwrt dir> <podkop version, e.g. 0.6.1>
set -e
FEED="$1/feeds/podkop"
VER="$2"
[ -d "$FEED/podkop" ] || { echo "no $FEED/podkop"; exit 1; }

# 1. "+sing-box" selects a package that sing-box-tiny PROVIDES, which Kconfig
#    reports as a recursive dependency. Make it a plain dependency; the
#    podkop config fragment selects the full sing-box itself.
sed -i 's/^\(\s*DEPENDS:=\)+sing-box /\1sing-box /' "$FEED/podkop/Makefile"

# 2. The feed derives its version from the date ("dev_17102026"), which apk
#    rejects ("package version is invalid"). Pin the release number.
for mk in "$FEED/podkop/Makefile" "$FEED/luci-app-podkop/Makefile"; do
	sed -i "s/^PKG_VERSION[[:space:]]*[:?]\?=.*/PKG_VERSION:=$VER/" "$mk"
done

# 3. podkop runs "sing-box version" for every status request the LuCI page
#    polls; on a 256 MiB box the calls pile up (9 sing-box processes, each
#    faulting in a ~30 MiB Go binary) and end in an OOM. Cache the output,
#    refreshed whenever the sing-box binary changes.
HELP="$FEED/podkop/files/usr/lib/helpers.sh"
if ! grep -q podkop_sing_box_version "$HELP"; then
	cat >> "$HELP" <<'EOS'

# cached "sing-box version" (openwrt-xiaomi-rd16 build)
podkop_sing_box_version() {
    local cache=/tmp/podkop-sing-box-version tmp
    if [ ! -s "$cache" ] || [ /usr/bin/sing-box -nt "$cache" ]; then
        tmp="$cache.$$"
        sing-box version > "$tmp" 2> /dev/null && mv -f "$tmp" "$cache"
        rm -f "$tmp"
    fi
    cat "$cache" 2> /dev/null
}
EOS
fi
sed -i 's/\$(sing-box version |/$(podkop_sing_box_version |/g' \
	"$FEED/podkop/files/usr/bin/podkop"
