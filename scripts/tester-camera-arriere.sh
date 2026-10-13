#!/bin/sh
# tester-camera-arriere.sh — (téléphone, root) Premier essai de la caméra arrière :
# relie IMX400 → CSIPHY0 → CSID0 → VFE0 (RDI0) et enregistre quelques images brutes
# (RAW10 compacté), sans libcamera. Fermer l'appareil photo avant.
#
#   sh scripts/tester-camera-arriere.sh [dossier]          (défaut : /root/imx400-essai)
#   W=5056 H=3792 EXPO=… GAIN=… sh scripts/tester-camera-arriere.sh
#
# EXPO : exposition en lignes (défaut : maximum du mode) ; GAIN : gain analogique
# 0…960 (défaut 480, soit ×1,9). Envoyer le dossier produit (journal + images).
set -u
out="${1:-/root/imx400-essai}"
W="${W:-2528}"; H="${H:-1896}"; GAIN="${GAIN:-480}"
mkdir -p "$out"
command -v media-ctl >/dev/null || { echo "Installer v4l-utils (pacman -S v4l-utils)"; exit 1; }

dmesg | grep -i -E "imx400|camss|cci|csiphy|csid|vfe" > "$out/dmesg-avant.txt"
media-ctl -p > "$out/media.txt" 2>&1
cap=$(sed -n 's/^- entity [0-9]*: \(imx400 [^ ]*\) .*/\1/p' "$out/media.txt" | head -n 1)
if [ -z "$cap" ]; then
	echo "Capteur IMX400 absent du graphe média : voir $out/dmesg-avant.txt"
	grep -i imx400 "$out/dmesg-avant.txt"
	exit 1
fi
echo "Capteur : $cap ($W x $H)"

f="SRGGB10_1X10/${W}x${H}"
media-ctl -r
media-ctl -l '"msm_csiphy0":1->"msm_csid0":0[1],"msm_csid0":1->"msm_vfe0_rdi0":0[1]' || exit 1
media-ctl -V "\"$cap\":0[fmt:$f],\"msm_csiphy0\":0[fmt:$f],\"msm_csid0\":0[fmt:$f],\"msm_vfe0_rdi0\":0[fmt:$f]" || exit 1
sd=$(media-ctl -e "$cap"); dev=$(media-ctl -e msm_vfe0_video0)
v4l2-ctl -d "$sd" --list-ctrls > "$out/controles.txt" 2>&1
max=$(sed -n 's/.*exposure .*max=\([0-9]*\).*/\1/p' "$out/controles.txt" | head -n 1)
v4l2-ctl -d "$sd" --set-ctrl "exposure=${EXPO:-${max:-1000}},analogue_gain=$GAIN"
v4l2-ctl -d "$sd" --list-ctrls >> "$out/controles.txt" 2>&1

echo "Enregistrement de 4 images (après 8 ignorées)…"
timeout 20 v4l2-ctl -d "$dev" --set-fmt-video="width=$W,height=$H,pixelformat=pRAA" \
	--stream-mmap --stream-skip=8 --stream-count=4 --stream-to="$out/imx400-${W}x${H}.raw" \
	> "$out/v4l2-ctl.txt" 2>&1
echo "v4l2-ctl : $?"; tail -n 3 "$out/v4l2-ctl.txt"
dmesg | grep -i -E "imx400|camss|cci|csiphy|csid|vfe" > "$out/dmesg-apres.txt"
ls -l "$out"
echo "Envoyer le dossier $out (journal, contrôles, images brutes)."
