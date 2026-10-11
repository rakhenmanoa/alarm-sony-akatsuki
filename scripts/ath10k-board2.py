#!/usr/bin/env python3
"""ath10k-board2.py <sortie/board-2.bin> <bdwlan.bin> [nom …]

Fabrique un fichier board-2.bin pour le pilote Wi-Fi ath10k à partir des réglages
de carte (« board data ») d'Android, ici bdwlan.bin de Sony pour le Xperia XZ3.

Format (drivers/net/wireless/ath/ath10k/core.c, hw.h) :
  "QCA-ATH10K-BOARD\\0" complété à 4 octets, puis des éléments
  { u32 id ; u32 longueur ; données complétées à 4 octets } :
    id 0 (BOARD) contenant : id 0 (NAME) « bus=… », … puis id 1 (DATA) les réglages.

Le pilote cherche, dans l'ordre :
  bus=snoc,qmi-board-id=ff,qmi-chip-id=30214,variant=<variante du DTB>
  bus=snoc,qmi-board-id=ff,qmi-chip-id=30214
  bus=snoc,qmi-board-id=ff
(identifiants lus le 11/10/2026 : « qmi chip_id 0x30214 … board_id 0xff »).
Sans nom donné, les trois sont inscrits (variante « Sony_akatsuki »).

Installé dans /usr/lib/firmware/updates/ath10k/WCN3990/hw1.0/board-2.bin, il passe
avant celui de linux-firmware (ordre de recherche du noyau), sans toucher au paquet.
"""
import os
import struct
import sys

MAGIC = b"QCA-ATH10K-BOARD\0"
NOMS = [
    "bus=snoc,qmi-board-id=ff,qmi-chip-id=30214,variant=Sony_akatsuki",
    "bus=snoc,qmi-board-id=ff,qmi-chip-id=30214",
    "bus=snoc,qmi-board-id=ff",
]


def ie(ident, data):
    pad = (-len(data)) % 4
    return struct.pack("<II", ident, len(data)) + data + b"\0" * pad


def main():
    if len(sys.argv) < 3:
        raise SystemExit(__doc__)
    dst, src = sys.argv[1], sys.argv[2]
    noms = sys.argv[3:] or NOMS
    data = open(src, "rb").read()
    if not data:
        raise SystemExit("bdwlan vide : %s" % src)
    corps = b"".join(ie(0, n.encode("ascii")) for n in noms) + ie(1, data)
    out = MAGIC + b"\0" * ((-len(MAGIC)) % 4) + ie(0, corps)
    os.makedirs(os.path.dirname(os.path.abspath(dst)), exist_ok=True)
    tmp = dst + ".tmp"
    with open(tmp, "wb") as f:
        f.write(out)
    os.replace(tmp, dst)
    print("%s : %d octets de réglages, %d nom(s)" % (dst, len(data), len(noms)))


if __name__ == "__main__":
    main()
