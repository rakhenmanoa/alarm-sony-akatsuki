#!/bin/sh
# installer-u-boot-carte.sh — (téléphone, root) Met sur la carte SD ce que U-Boot
# démarre : noyau, DTB, initramfs dans /boot/akatsuki/, et le menu
# /boot/extlinux/extlinux.conf.
#
#   sh scripts/installer-u-boot-carte.sh <dossier>
#
# <dossier> : pièces produites sur le PC par
#   GARDER=dossier … test-boot/build.sh <noyau.apk> boot-akatsuki.img
# (Image, akatsuki.dtb, initramfs.img, cmdline). La version précédente est gardée
# dans /boot/akatsuki/precedent/ et proposée dans le menu de U-Boot.
#
# Ne touche pas à boot_b : tant que U-Boot n'y est pas flashé, rien ne change au
# démarrage. Essai de U-Boot sans rien flasher : fastboot boot u-boot-akatsuki.img
set -eu
die() { echo "Erreur : $*" >&2; exit 1; }
[ "$(id -u)" -eq 0 ] || die "lancer en root."
src="${1:-}"
[ -n "$src" ] && [ -d "$src" ] || die "usage : $0 <dossier avec Image, akatsuki.dtb, initramfs.img, cmdline>"
for f in Image akatsuki.dtb initramfs.img cmdline; do [ -f "$src/$f" ] || die "$src/$f manquant."; done
here="$(cd "$(dirname "$0")" && pwd)"

# Garde-fou UFS sur le DTB qui sera donné au noyau
if [ -x "$here/check-dtb-ufs.sh" ] && command -v dtc >/dev/null; then
	"$here/check-dtb-ufs.sh" "$src/akatsuki.dtb" >/dev/null || die "DTB refusé par le garde-fou UFS."
else
	die "garde-fou UFS indisponible (installer dtc : pacman -S dtc)."
fi

d=/boot/akatsuki
install -d "$d" /boot/extlinux
if [ -f "$d/Image" ]; then
	rm -rf "$d/precedent"; install -d "$d/precedent"
	cp -a "$d/Image" "$d/akatsuki.dtb" "$d/initramfs.img" "$d/cmdline" "$d/precedent/" 2>/dev/null || true
fi
install -m 644 "$src/Image" "$src/akatsuki.dtb" "$src/initramfs.img" "$src/cmdline" "$d/"

cmd=$(cat "$d/cmdline")
{
	echo "# Menu de démarrage U-Boot du Xperia XZ3 (scripts/installer-u-boot-carte.sh)"
	echo "# Volume bas maintenu au démarrage : menu de U-Boot."
	echo "default akatsuki"
	echo "timeout 2"
	echo "menu title Xperia XZ3 - Arch Linux ARM"
	echo
	echo "label akatsuki"
	echo "	menu label Arch Linux ARM"
	echo "	linux /boot/akatsuki/Image"
	echo "	fdt /boot/akatsuki/akatsuki.dtb"
	echo "	initrd /boot/akatsuki/initramfs.img"
	echo "	append $cmd"
	if [ -f "$d/precedent/Image" ]; then
		echo
		echo "label precedent"
		echo "	menu label Arch Linux ARM (noyau précédent)"
		echo "	linux /boot/akatsuki/precedent/Image"
		echo "	fdt /boot/akatsuki/precedent/akatsuki.dtb"
		echo "	initrd /boot/akatsuki/precedent/initramfs.img"
		echo "	append $(cat "$d/precedent/cmdline" 2>/dev/null || echo "$cmd")"
	fi
} > /boot/extlinux/extlinux.conf
sync
echo "Installé :"; ls -l "$d"; echo; cat /boot/extlinux/extlinux.conf
