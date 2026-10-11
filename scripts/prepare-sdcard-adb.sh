#!/bin/sh
# prepare-sdcard-adb.sh — Prépare la carte micro-SD **dans le téléphone**, sous
# LineageOS, par adb (même résultat que prepare-sdcard.sh sur un PC).
# EFFACE ENTIÈREMENT LA CARTE SD. Ne touche jamais à la mémoire interne.
#
# Usage (sur le PC, téléphone sous LineageOS, branché, débogage USB actif) :
#   scripts/prepare-sdcard-adb.sh <ArchLinuxARM-aarch64-latest.tar.gz> \
#       <linux-postmarketos-qcom-sdm845-VERSION.apk>
#
# Prérequis côté téléphone : Options pour les développeurs → « Débogage root »
# (adb root). Outils Android utilisés : dd, blockdev, mke2fs, mkfs.exfat (ou à défaut
# newfs_msdos), toybox tar, gzip, sm.
#
# Résultat (table MBR) : partition 1 = ext4 « ALARM_ROOT » (Arch) ; partition 2 =
# exFAT « XZ3_PARTAGE », 8 Gio par défaut, à la fin. Android ne voit que la partition 2
# (il ignore les partitions Linux) : plus de « carte non prise en charge » à formater.
#
# Variable optionnelle :
#   PARTAGE   taille de la partition d'échange : « 8G » (défaut), « 512M », « 16G »… ;
#             « 0 » = pas de partition d'échange. Exemple :
#             PARTAGE=16G scripts/prepare-sdcard-adb.sh …
# Côté PC : adb, python3 (fabrique la table de partitions), gzip, tar.
# (Le sgdisk d'Android est une version réduite qui ne sait pas créer de partition.)
#
# ⚠️ Dans le téléphone, /dev/block/sda…sdf = mémoire interne UFS (Android ET
# bootloader). La carte SD est /dev/block/mmcblk0. Le script refuse tout autre
# périphérique et vérifie qu'il s'agit bien d'une carte SD avant d'effacer.

set -eu

die() { echo "Erreur : $*" >&2; exit 1; }

[ "$#" -eq 2 ] || { awk 'NR > 1 && /^#/ { sub(/^# ?/, ""); print; next } NR > 1 { exit }' "$0"; exit 2; }
tarball="$1"; apk="$2"
here="$(cd "$(dirname "$0")" && pwd)"
overlay="$here/../rootfs"
DEV=/dev/block/mmcblk0
PART=/dev/block/mmcblk0p1
PART2=/dev/block/mmcblk0p2
FATMNT=/data/local/tmp/alarm-fat
MNT=/data/local/tmp/alarm-sd
TMPTAR=/data/local/tmp/alarm-rootfs.tar.gz

command -v adb >/dev/null 2>&1 || die "adb introuvable sur le PC."
command -v python3 >/dev/null 2>&1 || die "python3 introuvable sur le PC."
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

# adb shell renvoie « \r\n » sur certaines versions : on nettoie
ash() { adb shell "$@" | tr -d '\r'; }

# ------------------------------------------------------------- adb root ---
echo "== Connexion adb (root)"
adb get-state >/dev/null 2>&1 || die "aucun téléphone vu par adb (débogage USB activé ? autorisé ?)."
adb root >/dev/null 2>&1 || true
sleep 2
adb wait-for-device
[ "$(ash id -u)" = "0" ] || die "adb n'est pas root. Activer « Débogage root » dans les options pour les développeurs."
case "$(ash getprop ro.product.device) $(ash getprop ro.product.vendor.device)" in
	*akatsuki*|*H8416*|*H9436*|*H9493*|*SO-01L*|*SOV39*|*801SO*) ;;
	*) die "ce téléphone n'est pas un Xperia XZ3 (akatsuki) : refusé." ;;
esac

# ---------------------------------------------- sécurité : c'est la carte SD --
echo "== Vérification de la carte SD"
[ "$(ash "[ -b $DEV ] && echo oui")" = "oui" ] || die "$DEV absent : carte SD insérée ?"
sdtype="$(ash cat /sys/block/mmcblk0/device/type 2>/dev/null)"
[ "$sdtype" = "SD" ] || die "/sys/block/mmcblk0/device/type = « $sdtype » (attendu : SD) : refusé."
sectors="$(ash cat /sys/block/mmcblk0/size)"
size=$((sectors * 512))
[ "$size" -ge $((4 * 1024 * 1024 * 1024)) ] || die "carte de moins de 4 Go."
[ "$size" -le $((512 * 1024 * 1024 * 1024)) ] || die "carte de plus de 512 Go : refusé par sécurité."
[ $((sectors - fat - 2048)) -ge 8388608 ] || \
	die "carte trop petite pour une partition d'échange de $PARTAGE (Arch garde au moins 4 Gio) : essayer PARTAGE=1G ou PARTAGE=0."
name="$(ash cat /sys/block/mmcblk0/device/name 2>/dev/null)"

echo
echo "Carte SD : $DEV — $((size / 1000000000)) Go — « $name »"
if [ "$fat" -gt 0 ]; then
	echo "Partition d'échange exFAT vue par Android : $PARTAGE ; le reste pour Arch."
else
	echo "Sans partition d'échange (PARTAGE=0) : tout pour Arch."
fi
echo "(la mémoire interne du téléphone, /dev/block/sd*, n'est pas concernée)"
echo
echo "TOUT LE CONTENU DE LA CARTE SD VA ÊTRE EFFACÉ."
printf 'Pour confirmer, taper exactement « EFFACER LA CARTE SD » : '
read -r answer
[ "$answer" = "EFFACER LA CARTE SD" ] || die "confirmation incorrecte, rien n'a été modifié."

# ------------------------------------------------- démonter (Android / vold) --
echo "== Démontage de la carte par Android"
for vol in $(ash sm list-volumes public 2>/dev/null | awk '/^public:179/ { print $1 }'); do
	ash sm unmount "$vol" >/dev/null 2>&1 || true
done
sleep 2
for m in $(ash "grep -E '^/dev/block/(vold/public:179|mmcblk0)' /proc/mounts | cut -d' ' -f2"); do
	ash umount "$m" >/dev/null 2>&1 || true
done
if [ -n "$(ash "grep -E '^/dev/block/(vold/public:179|mmcblk0)' /proc/mounts")" ]; then
	die "la carte est encore montée par Android. Paramètres → Stockage → Éjecter la carte, puis relancer."
fi

# -------------------------------------------------------- partitionnement ---
if [ "$fat" -gt 0 ]; then
	echo "== Partitionnement (MBR : Arch en ext4 + partition d'échange de $PARTAGE à la fin)"
else
	echo "== Partitionnement (MBR : Arch en ext4 sur toute la carte)"
fi
# Premier Mio de la carte fabriqué sur le PC : table MBR, le reste à zéro (efface
# aussi les anciennes signatures en début de carte).
#   1 : type 0x83 (Linux), du secteur 2048 jusqu'à la partition d'échange ;
#   2 : type 0x07 (exFAT), les PARTAGE derniers octets (alignés sur 1 Mio).
mbr="$(mktemp)"
python3 -I - "$mbr" "$sectors" "$fat" <<'PY'
import struct, sys
out, sectors, fat = sys.argv[1], int(sys.argv[2]), int(sys.argv[3])
if fat:
    p2 = (sectors - fat) // 2048 * 2048
    parts = [(0x83, 2048, p2 - 2048), (0x07, p2, sectors - p2)]
else:
    parts = [(0x83, 2048, sectors - 2048)]
img = bytearray(1024 * 1024)
for i, (typ, start, count) in enumerate(parts):
    assert 0 < count <= 0xFFFFFFFF
    off = 446 + 16 * i
    img[off:off + 16] = struct.pack("<B3sB3sII", 0x00, b"\xfe\xff\xff", typ, b"\xfe\xff\xff", start, count)
img[510:512] = b"\x55\xaa"
open(out, "wb").write(img)
PY
adb push "$mbr" /data/local/tmp/alarm-mbr.bin >/dev/null
rm -f "$mbr"
ash "dd if=/data/local/tmp/alarm-mbr.bin of=$DEV bs=1048576 count=1 && sync && echo DD_OK" | grep -q DD_OK || \
	die "écriture de la table de partitions impossible."
ash rm -f /data/local/tmp/alarm-mbr.bin
ash "blockdev --rereadpt $DEV" >/dev/null 2>&1 || true
ok=""
for i in 1 2 3 4 5 6 7 8 9 10; do
	if [ "$fat" -gt 0 ]; then
		[ "$(ash "[ -b $PART ] && [ -b $PART2 ] && echo oui")" = "oui" ] && { ok=1; break; }
	else
		[ "$(ash "[ -b $PART ] && echo oui")" = "oui" ] && { ok=1; break; }
	fi
	ash "blockdev --rereadpt $DEV" >/dev/null 2>&1 || true
	sleep 1
done
[ -n "$ok" ] || die "les partitions n'apparaissent pas. Retirer et remettre la carte, puis relancer."
# Android peut tenter de monter les nouvelles partitions : on s'assure que non
for vol in $(ash sm list-volumes public 2>/dev/null | awk '/^public:179/ { print $1 }'); do
	ash sm unmount "$vol" >/dev/null 2>&1 || true
done
for m in $(ash "grep -E '^/dev/block/(vold/public:179|mmcblk0)' /proc/mounts | cut -d' ' -f2"); do
	ash umount "$m" >/dev/null 2>&1 || true
done

if [ "$fat" -gt 0 ]; then
	# Même test qu'Android (vold, Exfat::IsSupported) : outils exFAT présents ET
	# pilote exFAT dans le noyau. Sinon Android ne saurait pas monter la partition
	# et reproposerait de formater la carte : on se rabat sur FAT32.
	if [ -n "$(ash "command -v mkfs.exfat")" ] && [ -n "$(ash "command -v fsck.exfat")" ] && \
	   [ -n "$(ash "grep -wE 'exfat|sdfat' /proc/filesystems")" ]; then
		echo "== Formatage exFAT de la partition d'échange (XZ3_PARTAGE)"
		ash mkfs.exfat -L XZ3_PARTAGE "$PART2" >/dev/null || die "mkfs.exfat a échoué."
	else
		echo "== LineageOS ne gère pas l'exFAT ici : partition d'échange formatée en FAT32"
		echo "   (fichiers limités à 4 Go chacun)"
		ash newfs_msdos -F 32 -L XZ3_PARTAGE "$PART2" >/dev/null || die "newfs_msdos a échoué."
	fi
fi

echo "== Formatage ext4 (ALARM_ROOT)"
ash mke2fs -F -t ext4 -L ALARM_ROOT "$PART" >/dev/null || die "mke2fs a échoué."

echo "== Montage dans le téléphone"
ash "mkdir -p $MNT && mount -t ext4 $PART $MNT" || die "montage impossible."
cleanup() { adb shell "umount $MNT 2>/dev/null; rmdir $MNT 2>/dev/null; rm -f $TMPTAR" >/dev/null 2>&1 || true; }
trap cleanup EXIT

# ----------------------------------------------------------- Arch Linux ARM --
echo "== Envoi d'Arch Linux ARM au téléphone"
adb push "$tarball" "$TMPTAR"
echo "== Extraction sur la carte (quelques minutes)"
ash "cd $MNT && gzip -dc $TMPTAR | tar -xpf - && echo EXTRACTION_OK" | grep -q EXTRACTION_OK || \
	die "extraction de l'archive impossible."
ash rm -f "$TMPTAR"
[ "$(ash "[ -x $MNT/usr/lib/systemd/systemd ] && echo oui")" = "oui" ] || \
	die "systemd absent après extraction : archive incomplète ?"

# ------------------------------------------------------------- noyau pmOS ---
echo "== Modules du noyau pmOS"
work="$(mktemp -d)"
trap 'cleanup; rm -rf "$work"' EXIT
gzip -dc "$apk" | tar -xi -C "$work" -f - 2>/dev/null || true
for moddir in "$work/usr/lib/modules" "$work/lib/modules"; do
	[ -d "$moddir" ] && break
done
kver="$(ls "$moddir" | head -n1)"
[ -n "$kver" ] || die "aucun module dans le paquet pmOS."
rm -f "$moddir/$kver/build" "$moddir/$kver/source"
if command -v depmod >/dev/null 2>&1; then
	mkdir -p "$work/depmod/lib" "$work/depmod/usr/lib"
	ln -s "$moddir" "$work/depmod/lib/modules"
	ln -s "$moddir" "$work/depmod/usr/lib/modules"
	depmod -b "$work/depmod" "$kver" && echo "   depmod OK ($kver)"
fi
ash mkdir -p "$MNT/usr/lib/modules" "$MNT/boot/akatsuki"
adb push "$moddir/$kver" "$MNT/usr/lib/modules/" >/dev/null
adb push "$work/boot/vmlinuz" "$MNT/boot/akatsuki/vmlinuz-$kver" >/dev/null
adb push "$work/boot/dtbs/qcom/sdm845-sony-xperia-tama-akatsuki.dtb" "$MNT/boot/akatsuki/" >/dev/null
ash chown -R 0:0 "$MNT/usr/lib/modules/$kver" "$MNT/boot/akatsuki"

# ---------------------------------------------------------- configuration ---
echo "== Configuration (réseau USB, fstab, nom d'hôte)"
for e in "$overlay"/*; do
	adb push "$e" "$MNT/" >/dev/null        # fusionne avec etc/ et usr/ existants
done
ash chown -R 0:0 "$MNT/etc/systemd/network" "$MNT/etc/systemd/system" "$MNT/usr/local/bin" \
	"$MNT/etc/fstab" "$MNT/etc/hostname"
ash chmod 644 "$MNT/etc/fstab" "$MNT/etc/hostname" "$MNT/etc/systemd/network/50-usb0.network" \
	"$MNT/etc/systemd/system/akatsuki-usb-gadget.service" "$MNT/etc/systemd/system/akatsuki-usb-watch.service"
ash chmod 755 "$MNT/usr/local/bin/akatsuki-usb-gadget"
W="$MNT/etc/systemd/system/multi-user.target.wants"
ash mkdir -p "$W"
ash ln -sf /etc/systemd/system/akatsuki-usb-gadget.service "$W/akatsuki-usb-gadget.service"
ash ln -sf /etc/systemd/system/akatsuki-usb-watch.service "$W/akatsuki-usb-watch.service"
for svc in sshd systemd-networkd; do
	if [ "$(ash "[ -e $MNT/usr/lib/systemd/system/$svc.service ] && echo oui")" = "oui" ]; then
		ash ln -sf "/usr/lib/systemd/system/$svc.service" "$W/$svc.service"
	fi
done

ash mkdir -p "$MNT/mnt/partage"

ash sync
ash umount "$MNT"
ash rmdir "$MNT" 2>/dev/null || true
trap 'rm -rf "$work"' EXIT

if [ "$fat" -gt 0 ]; then
	echo "== Partition d'échange (avertissement lisible depuis Android)"
	ash mkdir -p "$FATMNT"
	if [ "$(ash "for t in exfat sdfat vfat; do mount -t \$t $PART2 $FATMNT 2>/dev/null && { echo OK; break; }; done")" = "OK" ]; then
		adb push "$here/../sdcard/NE-PAS-FORMATER.txt" "$FATMNT/" >/dev/null
		ash "sync; umount $FATMNT"
	else
		echo "   (montage impossible depuis ce noyau Android : NE-PAS-FORMATER.txt non copié ;"
		echo "    le copier plus tard depuis Arch dans /mnt/partage)"
	fi
	ash rmdir "$FATMNT" 2>/dev/null || true
fi

echo
echo "Carte SD prête (noyau $kver)."
if [ "$fat" -gt 0 ]; then
	echo "Redémarrer le téléphone (ou retirer et remettre la carte) : Android montera la"
	echo "partition d'échange ($PARTAGE) comme une carte SD normale. Ne jamais la formater"
	echo "depuis Android (voir NE-PAS-FORMATER.txt sur la carte)."
else
	echo "Sans partition d'échange, Android proposera de formater la carte : REFUSER."
fi
echo "Suite : flasher boot-arch.img dans boot_b (voir docs/premier-demarrage.md)."
echo "Identifiants par défaut : alarm/alarm et root/root (à changer dès le premier accès)."
