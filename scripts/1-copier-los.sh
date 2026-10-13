#!/bin/sh
# 1-copier-los.sh — ÉTAPE 1 : copie sur le PC tout ce qui est propre au téléphone,
# depuis LineageOS : firmwares Sony, EFS (IMEI), TA, Bluetooth, capteurs, et les
# séquences de la caméra arrière (il faut alors ouvrir l'appareil photo une fois).
#
# LECTURE SEULE côté téléphone. Sur le PC, depuis le dépôt, LineageOS démarré,
# « Débogage USB » et « Débogage root » activés :
#   scripts/1-copier-los.sh                  → ./akatsuki-perso/
#
# ⚠️ akatsuki-perso/ contient l'IMEI et des fichiers Sony : à garder (sauvegarde),
#    ne JAMAIS le publier (ignoré par git).
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
out="${1:-akatsuki-perso}"
mkdir -p "$out"; chmod 700 "$out"; cd "$out"
echo "######## 1/5 Firmwares";             "$here/extraire-firmwares-adb.sh" firmware-akatsuki
echo "######## 2/5 EFS (modem)";           "$here/copier-efs-adb.sh" efs-akatsuki
echo "######## 3/5 TA";                    "$here/copier-ta-adb.sh" ta-akatsuki
mv -f ta-akatsuki/ta.img ta.img && rmdir ta-akatsuki 2>/dev/null || true
echo "######## 4/5 Bluetooth et capteurs"; "$here/sauver-blobs-adb.sh" blobs-akatsuki
echo "######## 5/5 Caméra arrière (séquences du capteur IMX400)"
if [ -f imx400-akatsuki.bin ]; then
	echo "   déjà fait"
elif [ "${SANS_CAMERA:-0}" = 1 ] || [ ! -t 0 ]; then
	echo "   sautée (relancer plus tard : scripts/capturer-camera-adb.sh arriere)"
else
	"$here/capturer-camera-adb.sh" arriere capture-camera || true
	[ -f capture-camera/imx400-akatsuki.bin ] && mv capture-camera/imx400-akatsuki.bin . && rm -rf capture-camera
fi
echo
for f in firmware-akatsuki efs-akatsuki ta.img blobs-akatsuki imx400-akatsuki.bin; do
	[ -e "$f" ] && echo "   ✓ $f" || echo "   ✗ $f MANQUANT"
done
echo "Étape 1 terminée : $(pwd). Suite : scripts/2-preparer-carte.sh"
