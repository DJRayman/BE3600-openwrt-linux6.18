#!/usr/bin/env python3
"""Install the stock Xiaomi RD16 Q6 WLAN firmware into an OpenWrt files/ overlay.

The RD16 runs its Q6 firmware in the QSDK 256 MiB memory profile; the GL-BE3600
firmware shipped in files/ by the base tree is built for 1 GiB boards. This
replaces it with the firmware from the stock RD16 rootfs (slot B dump) and
builds board-2.bin files that carry the stock board data (bdwlan) under the
names ath12k looks up, so the reference/GL board data never wins.

usage: stock-wifi-fw.py <stock rootfs lib/firmware dir> <files/lib/firmware dir>
"""
import os
import shutil
import struct
import sys

MAGIC = b"QCA-ATH12K-BOARD\0"


def pad4(b):
    return b + b"\0" * (-len(b) % 4)


def ie(ie_id, data):
    return struct.pack("<II", ie_id, len(data)) + pad4(data)


def board2(entries):
    """entries: list of (list of names, bdf bytes)"""
    out = pad4(MAGIC)
    for names, data in entries:
        body = b"".join(ie(0, n.encode()) for n in names) + ie(1, data)
        out += ie(0, body)            # ATH12K_BD_IE_BOARD
    return out


def names(board_id):
    # bus=ahb for both the IPQ5332 AHB radio and the QCN6432 hybrid device;
    # chip id is reported by firmware (0 on the RD16 2.4 GHz radio), the
    # fallback lookup uses the default board id 0xff.
    n = []
    for chip in range(4):
        n.append("bus=ahb,qmi-chip-id=%d,qmi-board-id=%d" % (chip, board_id))
        n.append("bus=ahb,qmi-chip-id=%d,qmi-board-id=255" % chip)
    return n


def real(path):
    if not os.path.exists(path):
        raise SystemExit("missing: %s" % path)
    return path


def copy_set(src_dir, prefixes, dst_dir):
    os.makedirs(dst_dir, exist_ok=True)
    for f in sorted(os.listdir(src_dir)):
        if any(f.startswith(p) for p in prefixes):
            shutil.copyfile(real(os.path.join(src_dir, f)), os.path.join(dst_dir, f))


def main():
    stock, dst = sys.argv[1], sys.argv[2]
    wifi_fw = os.path.join(stock, "IPQ5332", "WIFI_FW")
    # stock lib/firmware/qcn6432/* are symlinks into IPQ5332/WIFI_FW/qcn6432
    qcn = os.path.join(wifi_fw, "qcn6432")
    if not os.path.isdir(qcn):
        raise SystemExit("no " + qcn)

    ipq_dst = os.path.join(dst, "ath12k", "IPQ5332", "hw1.0")
    qcn_dst = os.path.join(dst, "ath12k", "QCN6432", "hw1.0")
    for d in (ipq_dst, qcn_dst):
        if os.path.isdir(d):
            shutil.rmtree(d)

    # Root PD + 2.4 GHz user PD + its M3 image
    copy_set(wifi_fw, ("q6_fw0.", "q6_fw1.", "iu_fw."), ipq_dst)
    shutil.copyfile(real(os.path.join(wifi_fw, "regdb.bin")),
                    os.path.join(ipq_dst, "regdb.bin"))
    bdf24 = open(real(os.path.join(wifi_fw, "bdwlan.b13")), "rb").read()
    open(os.path.join(ipq_dst, "board-2.bin"), "wb").write(board2([(names(0x13), bdf24)]))
    open(os.path.join(ipq_dst, "board.bin"), "wb").write(bdf24)

    # 5 GHz QCN6432 user PD (its q6_fw2 lives next to q6_fw0 in stock) + M3
    copy_set(wifi_fw, ("q6_fw2.",), qcn_dst)
    copy_set(qcn, ("iu_fw.",), qcn_dst)
    shutil.copyfile(real(os.path.join(wifi_fw, "regdb.bin")),
                    os.path.join(qcn_dst, "regdb.bin"))
    bdf5 = open(real(os.path.join(qcn, "bdwlan.b0060")), "rb").read()
    open(os.path.join(qcn_dst, "board-2.bin"), "wb").write(board2([(names(0x60), bdf5)]))
    open(os.path.join(qcn_dst, "board.bin"), "wb").write(bdf5)

    for d in (ipq_dst, qcn_dst):
        print(d, len(os.listdir(d)), "files")


if __name__ == "__main__":
    main()
