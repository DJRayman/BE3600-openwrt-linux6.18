#!/usr/bin/env python3
"""Xiaomi RD16: show the WAN port first in the LuCI port status row.

LuCI sorts the ports by name (lan1 lan2 lan3 wan), but on the RD16 the WAN
jack is the leftmost one. Copy the feed's 29_ports.js into the files/
overlay with WAN-role ports sorted first, so the row matches the case.

usage: luci-wan-first.py <feeds/luci dir> <files dir>
"""
import os
import sys

REL = "modules/luci-mod-status/htdocs/luci-static/resources/view/status/include/29_ports.js"
OLD = """		known_ports.sort(function(a, b) {
			return L.naturalCompare(a.device, b.device);
		});"""
NEW = """		known_ports.sort(function(a, b) {
			/* RD16: WAN is the leftmost jack */
			if ((a.role == 'wan') != (b.role == 'wan'))
				return (a.role == 'wan') ? -1 : 1;
			return L.naturalCompare(a.device, b.device);
		});"""


def main():
    src = os.path.join(sys.argv[1], REL)
    dst = os.path.join(sys.argv[2], "www/luci-static/resources/view/status/include/29_ports.js")
    s = open(src).read()
    if s.count(OLD) != 1:
        print("WARNING: LuCI 29_ports.js changed, port order left as is")
        return
    os.makedirs(os.path.dirname(dst), exist_ok=True)
    open(dst, "w").write(s.replace(OLD, NEW))
    print("LuCI ports: WAN first ->", dst)


if __name__ == "__main__":
    main()
