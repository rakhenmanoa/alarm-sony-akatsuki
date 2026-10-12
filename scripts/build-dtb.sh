#!/bin/sh
# build-dtb.sh — Construit le DTB modifié du Xperia XZ3 avec l'outil officiel dtc.
#
# Principe : on part du DTB du noyau pmOS (qui correspond exactement à ce noyau),
# on le décompile, on y ajoute un ou plusieurs fragments de dts/, puis on recompile.
# Le garde-fou UFS est appliqué sur l'entrée et sur la sortie.
#
# Usage :
#   scripts/build-dtb.sh <entrée.dtb> <sortie.dtb> [fragment.dtsi ...]
#
# Sans fragment, tous les fragments de dts/ (écran-charge, reboot-mode, mémoire Sony, modem-wifi) sont utilisés.
# ECRAN=dsi ajoute akatsuki-ecran-dsi.dtsi et akatsuki-tactile.dtsi (vrai écran et tactile, modules requis).
# AUDIO=1 ajoute akatsuki-audio.dtsi (codec WCD9340, haut-parleurs WSA8815).
# CAMERA=1 ajoute akatsuki-camera-avant.dtsi (IMX258, module imx258 requis).
#
# Exemple :
#   scripts/build-dtb.sh x/boot/dtbs/qcom/sdm845-sony-xperia-tama-akatsuki.dtb \
#       akatsuki-fb-charge.dtb

set -eu

if [ "$#" -lt 2 ]; then
	awk 'NR > 1 && /^#/ { sub(/^# ?/, ""); print; next } NR > 1 { exit }' "$0"
	exit 2
fi

here="$(cd "$(dirname "$0")" && pwd)"
in="$1"; out="$2"; shift 2
[ "$#" -gt 0 ] || set -- "$here/../dts/akatsuki-ecran-charge.dtsi" "$here/../dts/akatsuki-reboot-mode.dtsi" "$here/../dts/akatsuki-memoire-sony.dtsi" "$here/../dts/akatsuki-modem-wifi.dtsi"
# ECRAN=dsi : vrai écran (panneau LGD, DSC) à la place du framebuffer simple
if [ "${ECRAN:-}" = dsi ]; then set -- "$@" "$here/../dts/akatsuki-ecran-dsi.dtsi" "$here/../dts/akatsuki-tactile.dtsi"; fi
if [ "${AUDIO:-0}" = 1 ]; then set -- "$@" "$here/../dts/akatsuki-audio.dtsi"; fi
if [ "${CAMERA:-0}" != 0 ]; then set -- "$@" "$here/../dts/akatsuki-camera-avant.dtsi"; fi
if [ "${CAMERA:-0}" = diag ]; then set -- "$@" "$here/../dts/akatsuki-camera-diag.dtsi"; fi

command -v dtc >/dev/null 2>&1 || { echo "Erreur : dtc est requis (paquet dtc)." >&2; exit 2; }
[ -f "$in" ] || { echo "Erreur : fichier introuvable : $in" >&2; exit 2; }
for frag in "$@"; do
	[ -f "$frag" ] || { echo "Erreur : fragment introuvable : $frag" >&2; exit 2; }
done

echo "== Garde-fou UFS sur l'entrée"
"$here/check-dtb-ufs.sh" "$in"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

dtc -q -I dtb -O dts "$in" -o "$tmp/base.dts"

if ! grep -q 'model = "Sony Xperia XZ3"' "$tmp/base.dts"; then
	echo "Erreur : ce DTB n'est pas celui du Xperia XZ3." >&2
	exit 1
fi

# Fichier maître : base décompilée puis fragments, dans l'ordre donné.
{
	printf '/include/ "%s"\n' "$tmp/base.dts"
	for frag in "$@"; do
		printf '/include/ "%s"\n' "$(cd "$(dirname "$frag")" && pwd)/$(basename "$frag")"
	done
} > "$tmp/main.dts"

echo "== Compilation"
dtc -q -I dts -O dtb "$tmp/main.dts" -o "$tmp/out.dtb"

echo "== Garde-fou UFS sur la sortie"
"$here/check-dtb-ufs.sh" "$tmp/out.dtb"

cp "$tmp/out.dtb" "$out"
echo
echo "DTB écrit : $out"
echo "Différences avec l'entrée :"
dtc -q -I dtb -O dts "$out" -o "$tmp/out.dts"
diff "$tmp/base.dts" "$tmp/out.dts" || true
