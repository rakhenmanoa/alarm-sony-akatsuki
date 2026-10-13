#!/usr/bin/env python3
"""entete-image.py <u-boot-nodtb.bin> <sortie> — Met TEXT_OFFSET à 0 dans l'en-tête
« Image » Linux de U-Boot.

Le Kconfig Snapdragon fixe la base à 0x80000000 (non réglable) : avec TEXT_BASE = 0,
l'en-tête annonce TEXT_OFFSET = 0xffffffff80000000. Le premier essai sur le XZ3
(13/10/2026) ne démarrait pas. U-Boot est indépendant de sa position : ce champ n'est
qu'une indication au chargeur de Sony, on met 0 comme un noyau Linux.
"""
import struct
import sys

d = bytearray(open(sys.argv[1], "rb").read())
if d[56:60] != b"ARMd":
    sys.exit("en-tête Image absent")
struct.pack_into("<Q", d, 8, 0)
open(sys.argv[2], "wb").write(d)
