#!/usr/bin/env python3
"""ta-mac.py — Adresses MAC d'origine du Xperia XZ3, lues dans la copie de la partition TA.

Unités MiscTA (partition 2) : 2560 (0xa00) Wi-Fi, 2568 (0xa08) Bluetooth ; 6 octets
stockés à l'envers (le dernier octet en premier).

Usage : ta-mac.py [/var/lib/miscta/ta.img]
        → WLAN_MAC=38:78:62:… BT_MAC=38:78:62:…   (à passer à scripts/build-dtb.sh)
"""
import importlib.machinery
import os
import sys

ici = os.path.dirname(os.path.abspath(__file__))
q = importlib.machinery.SourceFileLoader("qmi_ecoute", os.path.join(ici, "qmi-ecoute.py")).load_module()
ta = q.TA(sys.argv[1] if len(sys.argv) > 1 else "/var/lib/miscta/ta.img")
for nom, unite in (("WLAN_MAC", 0xA00), ("BT_MAC", 0xA08)):
    d = ta.misc().get(unite)
    if not d or len(d) != 6:
        sys.exit("unité 0x%x absente ou de taille inattendue" % unite)
    print("%s=%s" % (nom, ":".join("%02x" % b for b in reversed(d))), end=" ")
print()
