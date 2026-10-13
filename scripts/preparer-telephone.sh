#!/bin/sh
# preparer-telephone.sh — « Patch » d'un Xperia XZ3 pour l'image publiée d'Arch :
# récupère sous LineageOS tout ce qui est propre au téléphone (firmwares et fichiers
# Sony, EFS, TA, Bluetooth, capteurs) et le dépose sur la partition d'échange de la
# carte micro-SD. Au démarrage suivant sous Arch, akatsuki-perso l'installe.
#
# LECTURE SEULE côté téléphone. Usage (sur le PC, depuis le dépôt, LineageOS démarré,
# « Débogage root » activé, carte SD préparée et dans le téléphone) :
#   scripts/preparer-telephone.sh [dossier-de-travail]     (défaut : ./akatsuki-perso)
#
# Une copie reste dans le dossier de travail du PC : la garder (sauvegarde de l'EFS,
# donc de l'IMEI) et ne JAMAIS la publier.
set -eu
die() { echo "Erreur : $*" >&2; exit 1; }
here="$(cd "$(dirname "$0")" && pwd)"
out="${1:-akatsuki-perso}"
command -v adb >/dev/null 2>&1 || die "adb introuvable sur le PC."
ash() { adb shell "$@" | tr -d '\r'; }
mkdir -p "$out"; chmod 700 "$out"
cd "$out"

echo "######## 1/4 Firmwares"
"$here/extraire-firmwares-adb.sh"
echo "######## 2/4 EFS (modem)"
"$here/copier-efs-adb.sh" efs-akatsuki
echo "######## 3/4 TA"
"$here/copier-ta-adb.sh" ta-akatsuki
echo "######## 4/4 Bluetooth et capteurs"
"$here/sauver-blobs-adb.sh" blobs-akatsuki

# Les trois premiers scripts déposent déjà leur copie sur la carte ; on y ajoute la
# partie utile des blobs (le reste — réglages thermiques, NFC… — reste sur le PC).
uuid="$(ash sm list-volumes public 2>/dev/null | awk '/^public:179/ && $2 == "mounted" { print $3; exit }')"
[ -n "$uuid" ] || die "partition d'échange de la carte non montée par Android."
sd="/storage/$uuid"
ash rm -rf "$sd/blobs-akatsuki" >/dev/null 2>&1 || true
ash mkdir -p "$sd/blobs-akatsuki"
for d in bt_firmware dsp etc-sensors persist-sensors; do
	[ -d "blobs-akatsuki/$d" ] || { echo "   (blobs-akatsuki/$d absent)"; continue; }
	adb push "blobs-akatsuki/$d" "$sd/blobs-akatsuki/" >/dev/null && echo "   $d → carte"
done
ash sync

echo
echo "== Sur la carte (vu par Android : $sd)"
for f in firmware-akatsuki efs-akatsuki ta.img blobs-akatsuki; do
	if [ "$(ash "[ -e $sd/$f ] && echo oui")" = "oui" ]; then echo "   ✓ $f"; else echo "   ✗ $f MANQUANT"; fi
done
echo
echo "Terminé. Démarrer Arch (fastboot --set-active=b && fastboot reboot) : les fichiers"
echo "sont installés au premier démarrage, puis le téléphone redémarre une fois."
echo "Copie de sauvegarde sur le PC : $(pwd) — à garder, ne jamais publier."
