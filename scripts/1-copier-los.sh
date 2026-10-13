#!/bin/sh
# 1-copier-los.sh — ÉTAPE 1 : copie sur le PC tout ce qui est propre au téléphone,
# depuis LineageOS : firmwares Sony, EFS (IMEI), TA, Bluetooth, capteurs.
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
echo "######## 1/4 Firmwares";             "$here/extraire-firmwares-adb.sh" firmware-akatsuki
echo "######## 2/4 EFS (modem)";           "$here/copier-efs-adb.sh" efs-akatsuki
echo "######## 3/4 TA";                    "$here/copier-ta-adb.sh" ta-akatsuki
mv -f ta-akatsuki/ta.img ta.img && rmdir ta-akatsuki 2>/dev/null || true
echo "######## 4/4 Bluetooth et capteurs"; "$here/sauver-blobs-adb.sh" blobs-akatsuki
echo
for f in firmware-akatsuki efs-akatsuki ta.img blobs-akatsuki; do
	[ -e "$f" ] && echo "   ✓ $f" || echo "   ✗ $f MANQUANT"
done
echo "Étape 1 terminée : $(pwd). Suite : scripts/2-preparer-carte.sh"
