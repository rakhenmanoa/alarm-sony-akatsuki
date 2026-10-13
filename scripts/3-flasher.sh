#!/bin/sh
# 3-flasher.sh — ÉTAPE 3 (PC) : installe l'image de démarrage dans le slot B et
# démarre Arch. LineageOS reste dans le slot A.
#
# Téléphone éteint, carte SD dedans : Volume haut + câble USB (LED bleue), puis :
#   scripts/3-flasher.sh [boot-akatsuki.img]
set -eu
die() { echo "Erreur : $*" >&2; exit 1; }
here="$(cd "$(dirname "$0")" && pwd)"
img="${1:-boot-akatsuki.img}"
[ -f "$img" ] || die "image introuvable : $img (étape 2)."
command -v fastboot >/dev/null || die "fastboot manquant."
# Garde-fou UFS sur le DTB contenu dans l'image
t=$(mktemp -d); trap 'rm -rf "$t"' EXIT
python3 - "$img" "$t/dtb" <<'PY'
import sys, struct
d = open(sys.argv[1], "rb").read()
i = d.find(bytes.fromhex("d00dfeed"))
if i < 0: sys.exit("DTB introuvable dans l'image")
n = struct.unpack(">I", d[i+4:i+8])[0]
open(sys.argv[2], "wb").write(d[i:i+n])
PY
"$here/check-dtb-ufs.sh" "$t/dtb" || die "garde-fou UFS : image refusée."
fastboot devices | grep -q . || die "aucun téléphone en fastboot (Volume haut + câble, LED bleue)."
slot=$(fastboot getvar current-slot 2>&1 | sed -n 's/^current-slot: *//p')
echo "Slot actif : $slot"
fastboot flash boot_b "$img"
fastboot erase dtbo_b
fastboot --set-active=b
fastboot reboot
echo
echo "Étape 3 terminée. Arch démarre (1 à 2 minutes la première fois)."
echo "Suite : internet par le câble (sudo scripts/partage-internet-pc.sh start), puis"
echo "  ssh alarm@172.16.42.1   (alarm)  →  su -   (root)  →"
echo "  sh /root/alarm-sony-akatsuki/scripts/4-installer-systeme.sh"
