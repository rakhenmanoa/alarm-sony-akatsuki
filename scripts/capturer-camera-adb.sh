#!/bin/sh
# capturer-camera-adb.sh — (PC, téléphone sous LineageOS) Enregistre les écritures
# I2C du pilote caméra de Sony pendant qu'Android démarre l'appareil photo, puis les
# décode en liste (registre, valeur) avec decoder-cci.py.
#
# Le noyau de LineageOS n'a ni kprobes ni traceur de fonctions, mais le pilote CCI de
# Qualcomm journalise chaque paquet I2C si le bit CAM_CCI (0x4000) de debug_mdl est
# mis. Les écritures du pilote Sony (sony_camera_i2c_write) passent toutes par là.
#
# Prérequis : Options pour les développeurs → Débogage USB + Débogage root.
# Usage : scripts/capturer-camera-adb.sh [arriere|avant] [dossier]
# Ne modifie rien de durable : debug_mdl est remis à 0 à la fin, et le niveau de
# la console (dmesg -n 1) revient à la normale au prochain redémarrage.
set -eu
cam="${1:-arriere}"; out="${2:-capture-camera}"
here="$(cd "$(dirname "$0")" && pwd)"
p=/sys/module/cam_debug_util/parameters/debug_mdl
die() { echo "Erreur : $*" >&2; exit 1; }

adb root >/dev/null; sleep 2; adb wait-for-device
adb shell "[ -w $p ]" || die "$p absent ou non inscriptible (adb root ?)."
mkdir -p "$out"
nom="$out/camera-$cam-$(date +%Y%m%d-%H%M%S)"

remise() { adb shell "echo 0 > $p" 2>/dev/null || true; [ -n "${pid:-}" ] && kill "$pid" 2>/dev/null || true; }
trap remise EXIT INT TERM

adb shell 'am force-stop org.lineageos.aperture' 2>/dev/null || true
adb shell 'am force-stop com.android.camera2' 2>/dev/null || true
sleep 1
adb shell 'dmesg -n 1' 2>/dev/null || true      # moins d'impression sur la console série
adb shell "echo 0x4000 > $p; cat $p"
adb shell 'dmesg -w' > "$nom.kmsg.txt" &
pid=$!
adb logcat -c 2>/dev/null || true
sleep 1

echo
echo ">>> Ouvre l'appareil photo ($cam) sur le téléphone, attends l'aperçu, prends UNE photo,"
echo ">>> puis ferme l'application. Ensuite appuie sur Entrée ici."
adb shell 'am start -a android.media.action.STILL_IMAGE_CAMERA' >/dev/null 2>&1 || true
read -r _
sleep 2
remise; pid=
trap - EXIT INT TERM
adb logcat -d -b main -b system 2>/dev/null | grep -i -E 'cammw|imx400|imx258|sony_camera|SensorModule|CamX|camera' \
	> "$nom.logcat.txt" || true

python3 "$here/decoder-cci.py" "$nom.kmsg.txt" > "$nom.registres.txt"
if [ "$cam" = arriere ]; then
	python3 "$here/imx400-sequences.py" "$nom.registres.txt" "$out/imx400-akatsuki.bin" || true
fi
echo
head -n 1 "$nom.registres.txt"
echo "Lignes CCI : $(grep -c 'cam_cci' "$nom.kmsg.txt" || true)"
echo "Fichiers : $nom.kmsg.txt  $nom.registres.txt  $nom.logcat.txt"
[ -f "$out/imx400-akatsuki.bin" ] && echo "Séquences du pilote imx400 : $out/imx400-akatsuki.bin (propre au téléphone, ne pas publier)"
