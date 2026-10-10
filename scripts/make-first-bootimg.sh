#!/bin/sh
# make-first-bootimg.sh — boot.img du premier démarrage du Xperia XZ3.
#
# Le noyau pmOS intègre la carte SD (sdhci-msm), ext4 et le contrôleur USB :
# il peut monter le système directement depuis /dev/mmcblk0p1, sans initramfs.
# On lui donne donc un initramfs vide (sans /init, le noyau utilise root=).
#
# Usage :
#   scripts/make-first-bootimg.sh <vmlinuz> <fichier.dtb> <sortie.img>
#
# Exemple (DTB avec écran + charge construit par build-dtb.sh) :
#   scripts/make-first-bootimg.sh vmlinuz akatsuki-fb-charge.dtb boot-first.img
#   fastboot boot boot-first.img        # temporaire : rien n'est flashé
#
# Ligne de commande (modifiable avec la variable CMDLINE) :
#   root=/dev/mmcblk0p1 rootwait rw   système sur la carte SD
#   console=ttyMSM0,115200            port série de débogage (UART9)
#   console=tty0                      console à l'écran (simple-framebuffer)
#   clk_ignore_unused pd_ignore_unused  ne pas couper horloges et domaines
#                                     d'alimentation de l'écran au démarrage

set -eu

if [ "$#" -ne 3 ]; then
	awk 'NR > 1 && /^#/ { sub(/^# ?/, ""); print; next } NR > 1 { exit }' "$0"
	exit 2
fi

kernel="$1"; dtb="$2"; out="$3"
here="$(cd "$(dirname "$0")" && pwd)"

CMDLINE="${CMDLINE:-root=/dev/mmcblk0p1 rootwait rw console=ttyMSM0,115200 console=tty0 clk_ignore_unused pd_ignore_unused}"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# Initramfs vide : archive cpio « newc » ne contenant que l'entrée de fin
# « TRAILER!!! » (en-tête de 110 octets + nom de 11 octets, aligné sur 4).
# Champs : magie, ino, mode, uid, gid, nlink=1, mtime, taille, devmaj, devmin,
#          rdevmaj, rdevmin, namesize=0xb, check.
{
	printf '070701'
	printf '%08X' 0 0 0 0 1 0 0 0 0 0 0 11 0
	printf 'TRAILER!!!\000\000\000\000'
} | gzip -9n > "$tmp/initramfs-vide.img"

"$here/make-bootimg.sh" "$kernel" "$dtb" "$tmp/initramfs-vide.img" "$out" "$CMDLINE"
echo "Ligne de commande : $CMDLINE"
