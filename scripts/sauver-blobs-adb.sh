#!/bin/sh
# sauver-blobs-adb.sh — Met de côté, depuis LineageOS, les fichiers Sony/Qualcomm qui
# pourront servir plus tard sous Arch (capteurs, Bluetooth, vidéo…), tant que
# LineageOS est encore là. LECTURE SEULE côté téléphone.
#
# Usage (sur le PC, depuis le dépôt, LineageOS démarré, « Débogage root » activé) :
#   scripts/sauver-blobs-adb.sh [dossier-de-sortie]      (défaut : ./blobs-akatsuki)
#
# Copié :
#   firmware/            /vendor/firmware et /vendor/firmware_mnt/image (tous les
#                        firmwares : modem, DSP, venus, slpi, Bluetooth, GPU…)
#   bt_firmware/         partition bluetooth (si présente)
#   dsp/                 /vendor/dsp et /vendor/lib/rfsa/adsp (bibliothèques des DSP,
#                        pour hexagonrpcd : capteurs par le SLPI)
#   etc-sensors/         /vendor/etc/sensors (configuration des capteurs)
#   persist-sensors/     /mnt/vendor/persist/sensors (étalonnage des capteurs)
#   etc/                 quelques réglages (thermique, Wi-Fi, Bluetooth, NFC, gps.conf)
# Pas copié : TA, EFS (scripts dédiés), applications TrustZone (empreintes), ACDB.
#
# ⚠️ Fichiers propriétaires : ne jamais les publier (dossier ignoré par git).

set -eu
die() { echo "Erreur : $*" >&2; exit 1; }
out="${1:-blobs-akatsuki}"
command -v adb >/dev/null 2>&1 || die "adb introuvable sur le PC."
ash() { adb shell "$@" | tr -d '\r'; }

adb get-state >/dev/null 2>&1 || die "aucun téléphone vu par adb."
adb root >/dev/null 2>&1 || true
sleep 2
adb wait-for-device
[ "$(ash id -u)" = "0" ] || die "adb n'est pas root (Options pour les développeurs → Débogage root)."

mkdir -p "$out"
chmod 700 "$out"
copie() { # copie <chemin-téléphone> <sous-dossier>
	if [ "$(ash "[ -e '$1' ] && echo oui")" = "oui" ]; then
		mkdir -p "$out/$2"
		adb pull "$1" "$out/$2/" >/dev/null 2>&1 && echo "   $1 → $2/" || echo "   $1 : copie incomplète"
	else
		echo "   $1 : absent"
	fi
}

echo "== Firmwares"
copie /vendor/firmware firmware
copie /vendor/firmware_mnt/image firmware
copie /vendor/bt_firmware bt_firmware
copie /vendor/dsp dsp
copie /vendor/lib/rfsa/adsp dsp
echo "== Capteurs"
copie /vendor/etc/sensors etc-sensors
copie /mnt/vendor/persist/sensors persist-sensors
echo "== Réglages"
for f in $(ash 'ls -d /vendor/etc/thermal* /vendor/etc/wifi /vendor/etc/bluetooth /vendor/etc/libnfc* /vendor/etc/gps* /vendor/etc/izat.conf /vendor/etc/sap.conf 2>/dev/null'); do
	copie "$f" etc
done
# Supprimer les applications TrustZone (inutilisables sous Linux mainline)
find "$out" -name 'fpctzfingerprint*' -delete 2>/dev/null || true
du -sh "$out"
echo "Terminé : $out (à garder sur le PC, ne pas publier)."
