#!/bin/sh
# installer-camera-arriere.sh — (téléphone, root) Installe le pilote de la caméra
# arrière (IMX400) et ses séquences de registres.
#
#   KO=imx400.ko SEQ=imx400-akatsuki.bin sh scripts/installer-camera-arriere.sh
#
# KO  : module compilé (modules/precompiles/$(uname -r)/imx400.ko par défaut) ;
# SEQ : séquences construites sous LineageOS (scripts/capturer-camera-adb.sh, puis
#       scripts/imx400-sequences.py) : propres au téléphone, jamais publiées.
# Il faut aussi démarrer une image construite avec CAMERA_ARRIERE=1.
set -eu
die() { echo "Erreur : $*" >&2; exit 1; }
[ "$(id -u)" -eq 0 ] || die "lancer en root."
here="$(cd "$(dirname "$0")" && pwd)"
KO="${KO:-$here/../modules/precompiles/$(uname -r)/imx400.ko}"
SEQ="${SEQ:-}"
[ -f "$KO" ] || die "module $KO introuvable."
[ -n "$SEQ" ] && [ -f "$SEQ" ] || die "fichier de séquences absent : SEQ=…/imx400-akatsuki.bin"
head -c 8 "$SEQ" | grep -q IMX400SQ || die "$SEQ n'est pas un fichier de séquences IMX400."

d=/usr/lib/modules/$(uname -r)/updates
install -d "$d" /usr/lib/firmware/sony
install -m 644 "$KO" "$d/imx400.ko"
install -m 644 "$SEQ" /usr/lib/firmware/sony/imx400-akatsuki.bin
depmod -a
pacman -S --needed --noconfirm v4l-utils >/dev/null 2>&1 || echo "   (v4l-utils : installer plus tard pour les essais)"
modinfo -n imx400
echo "Installé. Démarrer une image CAMERA_ARRIERE=1, puis : sh scripts/tester-camera-arriere.sh"
