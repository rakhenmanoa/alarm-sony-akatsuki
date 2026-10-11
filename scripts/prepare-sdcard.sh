#!/bin/sh
# prepare-sdcard.sh — Prépare la carte micro-SD du Xperia XZ3 : Arch Linux ARM +
# modules du noyau pmOS + accès réseau par USB. EFFACE ENTIÈREMENT LA CARTE.
#
# Usage (en root) :
#   scripts/prepare-sdcard.sh <périphérique> <ArchLinuxARM-aarch64-latest.tar.gz> \
#       <linux-postmarketos-qcom-sdm845-VERSION.apk>
#
# Exemple :
#   sudo scripts/prepare-sdcard.sh /dev/sdb ArchLinuxARM-aarch64-latest.tar.gz \
#       linux-postmarketos-qcom-sdm845-7.1_rc1-r4.apk
#
# Variables optionnelles :
#   PARTAGE       taille de la partition d'échange exFAT vue par Android, à la fin
#                 de la carte : « 8G » par défaut, « 512M », « 16G »… ; « 0 » = pas de
#                 partition d'échange (Android proposera alors de formater la carte).
#                 Exemple : sudo PARTAGE=16G scripts/prepare-sdcard.sh …
#   FIRMWARE_DIR  dossier lib/firmware à copier (ex. firmwares de Petr Hodina)
#
# Résultat (table MBR) :
#   partition 1 : ext4 « ALARM_ROOT », Arch Linux ARM (/dev/mmcblk0p1 dans le téléphone),
#                 type MBR 0xDA et non 0x83 : LineageOS monte les partitions 0x83 (ext4)
#                 et verrait Arch ; le noyau d'Arch, lui, ignore le type ;
#   partition 2 : exFAT « XZ3_PARTAGE », 8 Gio (PARTAGE) à la fin de la carte. Android ne voit
#                 que celle-ci (il ignore le type 0xDA) : plus de message « carte
#                 non prise en charge » qui propose de formater. Arch la monte sur /mnt/partage.
# Identifiants Arch Linux ARM par défaut : alarm/alarm et root/root (à changer).

set -eu

die() { echo "Erreur : $*" >&2; exit 1; }

[ "$#" -eq 3 ] || { awk 'NR > 1 && /^#/ { sub(/^# ?/, ""); print; next } NR > 1 { exit }' "$0"; exit 2; }
dev="$1"; tarball="$2"; apk="$3"
here="$(cd "$(dirname "$0")" && pwd)"
overlay="$here/../rootfs"

[ "$(id -u)" -eq 0 ] || die "lancer en root (sudo)."
for c in lsblk sfdisk mkfs.ext4 mkfs.exfat bsdtar gzip tar findmnt; do
	command -v "$c" >/dev/null 2>&1 || die "commande manquante : $c"
done
# Taille de la partition d'échange, en secteurs de 512 octets
PARTAGE="${PARTAGE:-8G}"
case "$PARTAGE" in
	0) fat=0 ;;
	*[Gg]) n="${PARTAGE%[Gg]}"; case "$n" in ''|*[!0-9]*) die "PARTAGE invalide : $PARTAGE";; esac; fat=$((n * 2097152)) ;;
	*[Mm]) n="${PARTAGE%[Mm]}"; case "$n" in ''|*[!0-9]*) die "PARTAGE invalide : $PARTAGE";; esac; fat=$((n * 2048)) ;;
	*) die "PARTAGE invalide : $PARTAGE (exemples : 8G, 512M, 0)" ;;
esac
[ "$fat" -eq 0 ] || [ "$fat" -ge 131072 ] || die "PARTAGE trop petit (minimum 64M, ou 0)."
[ -f "$tarball" ] || die "archive Arch Linux ARM introuvable : $tarball"
[ -f "$apk" ]     || die "paquet noyau pmOS introuvable : $apk"
[ -d "$overlay" ] || die "dossier rootfs/ du dépôt introuvable : $overlay"

# ---------------------------------------------------------------- sécurité ---
[ -b "$dev" ] || die "$dev n'est pas un périphérique bloc."
devtype="$(lsblk -dno TYPE "$dev")"
[ "$devtype" = "disk" ] || die "$dev est de type « $devtype », pas un disque entier (donner /dev/sdX ou /dev/mmcblkN, pas une partition)."

name="$(basename "$dev")"
removable="$(cat "/sys/block/$name/removable" 2>/dev/null || echo 0)"
mmctype="$(cat "/sys/block/$name/device/type" 2>/dev/null || echo)"
if [ "$removable" != "1" ] && [ "$mmctype" != "SD" ]; then
	die "$dev n'est ni amovible ni une carte SD : refusé par sécurité."
fi

size="$(lsblk -bdno SIZE "$dev")"
[ "$size" -le $((512 * 1024 * 1024 * 1024)) ] || die "$dev fait plus de 512 Go : refusé par sécurité."
[ "$size" -ge $((4 * 1024 * 1024 * 1024)) ] || die "$dev fait moins de 4 Go : trop petit."
# Arch doit garder au moins 4 Gio
[ $((size / 512 - fat - 2048)) -ge 8388608 ] || \
	die "carte trop petite pour une partition d'échange de $PARTAGE (Arch garde au moins 4 Gio) : essayer PARTAGE=1G ou PARTAGE=0."

if lsblk -lnpo MOUNTPOINT "$dev" | grep -q .; then
	die "une partition de $dev est montée. La démonter d'abord (umount)."
fi
rootdisk="$(lsblk -no PKNAME "$(findmnt -no SOURCE /)" 2>/dev/null || true)"
[ "$rootdisk" != "$name" ] || die "$dev contient le système de ce PC !"

echo "Carte cible :"
lsblk -o NAME,SIZE,MODEL,TRAN,RM,TYPE "$dev"
echo
echo "TOUT LE CONTENU DE $dev VA ÊTRE EFFACÉ."
printf 'Pour confirmer, retaper exactement « %s » : ' "$dev"
read -r answer
[ "$answer" = "$dev" ] || die "confirmation incorrecte, rien n'a été modifié."

# ------------------------------------------------------------ partitionnement --
sectors=$((size / 512))
if [ "$fat" -gt 0 ]; then
	echo "== Partitionnement (MBR : Arch en ext4 + $PARTAGE en exFAT à la fin)"
	p2start=$(( (sectors - fat) / 2048 * 2048 ))    # aligné sur 1 Mio
	printf 'label: dos\nstart=2048, size=%s, type=da\nstart=%s, size=%s, type=7\n' \
		"$((p2start - 2048))" "$p2start" "$((sectors - p2start))" | sfdisk --quiet --wipe always "$dev"
	nparts=2
else
	echo "== Partitionnement (MBR : Arch en ext4 sur toute la carte, sans partition d'échange)"
	printf 'label: dos\nstart=2048, type=da\n' | sfdisk --quiet --wipe always "$dev"
	nparts=1
fi
sync

# Attendre que le noyau voie les partitions (relecture forcée si besoin).
part=""; part2=""
for i in 1 2 3 4 5 6 7 8 9 10; do
	udevadm settle 2>/dev/null || true
	part="$(lsblk -lnpo NAME,TYPE "$dev" | awk '$2 == "part" { print $1 }' | sed -n 1p)"
	part2="$(lsblk -lnpo NAME,TYPE "$dev" | awk '$2 == "part" { print $1 }' | sed -n 2p)"
	if [ -n "$part" ] && [ -b "$part" ]; then
		[ "$nparts" -eq 1 ] && break
		[ -n "$part2" ] && [ -b "$part2" ] && break
	fi
	blockdev --rereadpt "$dev" 2>/dev/null || partx -u "$dev" 2>/dev/null || true
	sleep 1
done
[ -n "$part" ] && [ -b "$part" ] || die "partition introuvable après partitionnement (débrancher et rebrancher la carte, puis relancer)."
if [ "$nparts" -eq 2 ]; then
	[ -n "$part2" ] && [ -b "$part2" ] || die "partition d'échange introuvable (débrancher et rebrancher la carte, puis relancer)."
	mkfs.exfat -L XZ3_PARTAGE "$part2" >/dev/null
fi
mkfs.ext4 -q -F -L ALARM_ROOT "$part"

mnt="$(mktemp -d)"
apkdir="$(mktemp -d)"
cleanup() { umount "$mnt" 2>/dev/null || true; rmdir "$mnt" 2>/dev/null || true; rm -rf "$apkdir"; }
trap cleanup EXIT
mount "$part" "$mnt"

# -------------------------------------------------------------- Arch Linux ARM --
echo "== Extraction d'Arch Linux ARM (quelques minutes)"
bsdtar -xpf "$tarball" -C "$mnt"

# ------------------------------------------------------------ noyau pmOS -------
echo "== Modules et fichiers de démarrage du noyau pmOS"
gzip -dc "$apk" | tar -xi -C "$apkdir" -f - 2>/dev/null
for moddir in "$apkdir/usr/lib/modules" "$apkdir/lib/modules"; do
	[ -d "$moddir" ] && break
done
kver="$(ls "$moddir" | head -n1)"
[ -n "$kver" ] || die "aucun module dans le paquet pmOS."
mkdir -p "$mnt/usr/lib/modules"
cp -a "$moddir/$kver" "$mnt/usr/lib/modules/"
rm -f "$mnt/usr/lib/modules/$kver/build" "$mnt/usr/lib/modules/$kver/source"
mkdir -p "$mnt/boot/akatsuki"
cp "$apkdir/boot/vmlinuz" "$mnt/boot/akatsuki/vmlinuz-$kver"
cp "$apkdir/boot/dtbs/qcom/sdm845-sony-xperia-tama-akatsuki.dtb" "$mnt/boot/akatsuki/"

if command -v depmod >/dev/null 2>&1; then
	depmod -b "$mnt" "$kver" && echo "   depmod OK ($kver)"
else
	echo "   (depmod absent sur ce PC : lancer « depmod -a » au premier démarrage)"
fi

if [ -n "${FIRMWARE_DIR:-}" ]; then
	echo "== Firmwares depuis $FIRMWARE_DIR"
	mkdir -p "$mnt/usr/lib/firmware"
	cp -a "$FIRMWARE_DIR"/. "$mnt/usr/lib/firmware/"
fi

# ----------------------------------------------------------- configuration -----
echo "== Configuration (réseau USB, fstab, nom d'hôte)"
cp -a "$overlay"/. "$mnt"/
chmod 755 "$mnt/usr/local/bin/akatsuki-usb-gadget"

wants="$mnt/etc/systemd/system/multi-user.target.wants"
mkdir -p "$wants"
ln -sf /etc/systemd/system/akatsuki-usb-gadget.service "$wants/akatsuki-usb-gadget.service"
ln -sf /etc/systemd/system/akatsuki-usb-watch.service "$wants/akatsuki-usb-watch.service"
for svc in sshd systemd-networkd; do
	[ -e "$mnt/usr/lib/systemd/system/$svc.service" ] && ln -sf "/usr/lib/systemd/system/$svc.service" "$wants/$svc.service"
done

mkdir -p "$mnt/mnt/partage"

# pacman 7 télécharge dans un bac à sable qui exige Landlock ; le noyau pmOS est
# compilé sans (CONFIG_SECURITY_LANDLOCK non défini) : « failed to synchronize ».
if [ -f "$mnt/etc/pacman.conf" ] && ! grep -q '^DisableSandbox' "$mnt/etc/pacman.conf"; then
	sed -i '/^\[options\]/a DisableSandbox' "$mnt/etc/pacman.conf"
fi

if [ "$nparts" -eq 2 ]; then
	echo "== Partition d'échange (avertissement lisible depuis Android)"
	fatmnt="$(mktemp -d)"
	mount "$part2" "$fatmnt"
	cp "$here/../sdcard/NE-PAS-FORMATER.txt" "$fatmnt/"
	umount "$fatmnt"
	rmdir "$fatmnt"
else
	echo "Attention : sans partition d'échange, Android proposera de formater la carte : refuser."
fi

sync
echo
echo "Carte prête. Noyau $kver. L'initramfs de test-boot/ monte /dev/mmcblk0p1 et lance systemd."
echo "Fichiers de démarrage copiés dans /boot/akatsuki/ sur la carte."
echo "Identifiants par défaut : alarm/alarm et root/root (à changer dès le premier accès)."
