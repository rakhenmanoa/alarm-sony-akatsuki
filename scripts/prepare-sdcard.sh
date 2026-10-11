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
#   FIRMWARE_DIR  dossier lib/firmware à copier (ex. firmwares de Petr Hodina)
#
# Résultat (table MBR) :
#   partition 1 : ext4 « ALARM_ROOT », Arch Linux ARM (/dev/mmcblk0p1 dans le téléphone) ;
#   partition 2 : FAT32 « XZ3_PARTAGE », 512 Mio à la fin de la carte. Android ne voit
#                 que celle-ci (il ignore les partitions Linux) : plus de message « carte
#                 non prise en charge » qui propose de formater. Arch la monte sur /mnt/partage.
# Identifiants Arch Linux ARM par défaut : alarm/alarm et root/root (à changer).

set -eu

die() { echo "Erreur : $*" >&2; exit 1; }

[ "$#" -eq 3 ] || { awk 'NR > 1 && /^#/ { sub(/^# ?/, ""); print; next } NR > 1 { exit }' "$0"; exit 2; }
dev="$1"; tarball="$2"; apk="$3"
here="$(cd "$(dirname "$0")" && pwd)"
overlay="$here/../rootfs"

[ "$(id -u)" -eq 0 ] || die "lancer en root (sudo)."
for c in lsblk sfdisk mkfs.ext4 mkfs.fat bsdtar gzip tar findmnt; do
	command -v "$c" >/dev/null 2>&1 || die "commande manquante : $c"
done
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
echo "== Partitionnement (MBR : Arch en ext4 + 512 Mio en FAT32 à la fin)"
sectors=$((size / 512))
fat=1048576                                     # 512 Mio en secteurs de 512 octets
p2start=$(( (sectors - fat) / 2048 * 2048 ))    # aligné sur 1 Mio
p1size=$((p2start - 2048))
printf 'label: dos\nstart=2048, size=%s, type=83\nstart=%s, size=%s, type=c\n' \
	"$p1size" "$p2start" "$((sectors - p2start))" | sfdisk --quiet --wipe always "$dev"
sync

# Attendre que le noyau voie les deux partitions (relecture forcée si besoin).
part=""; part2=""
for i in 1 2 3 4 5 6 7 8 9 10; do
	udevadm settle 2>/dev/null || true
	part="$(lsblk -lnpo NAME,TYPE "$dev" | awk '$2 == "part" { print $1 }' | sed -n 1p)"
	part2="$(lsblk -lnpo NAME,TYPE "$dev" | awk '$2 == "part" { print $1 }' | sed -n 2p)"
	[ -n "$part" ] && [ -b "$part" ] && [ -n "$part2" ] && [ -b "$part2" ] && break
	blockdev --rereadpt "$dev" 2>/dev/null || partx -u "$dev" 2>/dev/null || true
	sleep 1
done
[ -n "$part" ] && [ -b "$part" ] && [ -n "$part2" ] && [ -b "$part2" ] || \
	die "partitions introuvables après partitionnement (débrancher et rebrancher la carte, puis relancer)."

mkfs.fat -F 32 -n XZ3_PARTAGE "$part2" >/dev/null
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

echo "== Partition d'échange (avertissement lisible depuis Android)"
fatmnt="$(mktemp -d)"
mount "$part2" "$fatmnt"
cp "$here/../sdcard/NE-PAS-FORMATER.txt" "$fatmnt/"
umount "$fatmnt"
rmdir "$fatmnt"

sync
echo
echo "Carte prête. Noyau $kver. L'initramfs de test-boot/ monte /dev/mmcblk0p1 et lance systemd."
echo "Fichiers de démarrage copiés dans /boot/akatsuki/ sur la carte."
echo "Identifiants par défaut : alarm/alarm et root/root (à changer dès le premier accès)."
