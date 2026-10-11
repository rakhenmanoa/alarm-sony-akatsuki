#!/bin/sh
# copier-efs-adb.sh — Copie les données du modem (EFS) du Xperia XZ3 pour rmtfs.
#
# Le firmware du modem garde ses réglages (IMEI, calibration radio, réseau) dans
# quatre partitions de la mémoire interne : modemst1, modemst2, fsc, fsg. Sous
# Android, le service rmtfs les lui sert ; sous Arch, rmtfs servira une COPIE de
# ces partitions, prise ici. La mémoire interne (UFS) n'est jamais touchée par Arch.
#
# LECTURE SEULE côté téléphone (cat d'une partition vers le PC).
#
# Usage (sur le PC, depuis le dépôt, LineageOS démarré, « Débogage root » activé) :
#   scripts/copier-efs-adb.sh [dossier-de-sortie]      (défaut : ./efs-akatsuki)
#
# Résultat : <sortie>/modem_fs1, modem_fs2, modem_fsc, modem_fsg (noms attendus par
# « rmtfs -o <dossier> ») et une copie sur la partition d'échange de la carte SD.
#
# ⚠️ Ces fichiers contiennent l'IMEI : ne jamais les publier (dossier ignoré par git).
#    Garder la copie du PC comme sauvegarde.

set -eu
die() { echo "Erreur : $*" >&2; exit 1; }

out="${1:-efs-akatsuki}"
command -v adb >/dev/null 2>&1 || die "adb introuvable sur le PC."

ash() { adb shell "$@" | tr -d '\r'; }

echo "== Connexion adb (root)"
adb get-state >/dev/null 2>&1 || die "aucun téléphone vu par adb."
adb root >/dev/null 2>&1 || true
sleep 2
adb wait-for-device
[ "$(ash id -u)" = "0" ] || die "adb n'est pas root (Options pour les développeurs → Débogage root)."
case "$(ash getprop ro.product.device) $(ash getprop ro.product.vendor.device)" in
	*akatsuki*|*H8416*|*H9436*|*H9493*|*SO-01L*|*SOV39*|*801SO*) ;;
	*) die "ce téléphone n'est pas un Xperia XZ3 (akatsuki)." ;;
esac

byname=""
for d in /dev/block/bootdevice/by-name /dev/block/by-name; do
	[ "$(ash "[ -e $d/modemst1 ] && echo oui")" = "oui" ] && { byname="$d"; break; }
done
[ -n "$byname" ] || die "partition modemst1 introuvable."

mkdir -p "$out"
chmod 700 "$out"
echo "== Copie (lecture seule) depuis $byname"
# partition Android → nom attendu par rmtfs
for pair in modemst1:modem_fs1 modemst2:modem_fs2 fsc:modem_fsc fsg:modem_fsg; do
	part="${pair%%:*}"; name="${pair#*:}"
	size="$(ash "blockdev --getsize64 \$(readlink -f $byname/$part)")"
	case "$size" in ''|*[!0-9]*) die "taille de $part illisible." ;; esac
	adb exec-out "cat $byname/$part" > "$out/$name.tmp"
	got="$(wc -c < "$out/$name.tmp" | tr -d ' ')"
	[ "$got" = "$size" ] || die "$part : $got octets lus, $size attendus."
	mv "$out/$name.tmp" "$out/$name"
	chmod 600 "$out/$name"
	echo "   $part → $out/$name ($size octets)"
done

# Copie sur la partition d'échange de la carte SD (montée par Android)
uuid="$(ash sm list-volumes public 2>/dev/null | awk '/^public:179/ && $2 == "mounted" { print $3; exit }')"
if [ -n "$uuid" ] && [ "$(ash "[ -d /storage/$uuid ] && echo oui")" = "oui" ]; then
	sd="/storage/$uuid"
	ash rm -rf "$sd/efs-akatsuki" >/dev/null 2>&1 || true
	if adb push "$out" "$sd/efs-akatsuki" >/dev/null 2>&1; then
		ash sync
		echo "== Copie sur la carte SD : $sd/efs-akatsuki"
		echo "Sous Arch (root) : install -d -m 700 /var/lib/rmtfs && install -m 600 /mnt/partage/efs-akatsuki/modem_fs* /var/lib/rmtfs/ && rm -r /mnt/partage/efs-akatsuki"
		exit 0
	fi
fi
echo "Pas de copie sur la carte SD. Sous Arch, copier depuis le PC :"
echo "  scp -r $out alarm@172.16.42.1:/tmp/   puis (root) install -d -m 700 /var/lib/rmtfs && install -m 600 /tmp/$(basename "$out")/modem_fs* /var/lib/rmtfs/"
