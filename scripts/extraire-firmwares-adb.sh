#!/bin/sh
# extraire-firmwares-adb.sh — Récupère les firmwares propres au Xperia XZ3 dans le
# téléphone lui-même (LineageOS, adb root), les convertit au format attendu par le
# noyau mainline et les dépose sur la partition d'échange de la carte SD.
#
# LECTURE SEULE côté téléphone : rien n'est modifié dans ses partitions.
#
# Usage (sur le PC, depuis le dépôt, LineageOS démarré, « Débogage root » activé) :
#   scripts/extraire-firmwares-adb.sh [dossier-de-sortie]     (défaut : ./firmware-akatsuki)
#
# Résultat :
#   <sortie>/qcom/sdm845/Sony/tama/*.mbn    (adsp, cdsp, venus, a630_zap, modem…)
#   <sortie>/qca/Sony/tama/crnv21.bin       (réglages Bluetooth)
#   <sortie>/updates/ath10k/WCN3990/hw1.0/board-2.bin   (réglages Wi-Fi Sony)
#   et une copie dans firmware-akatsuki/ sur la partition d'échange de la carte SD.
# Ensuite, sous Arch (root) :
#   cp -a /mnt/partage/firmware-akatsuki/. /usr/lib/firmware/ && reboot
#
# Ces fichiers sont signés par Qualcomm/Sony pour CE modèle : ils restent sur ton
# PC et ton téléphone (le dossier de sortie est ignoré par git).

set -eu
die() { echo "Erreur : $*" >&2; exit 1; }

here="$(cd "$(dirname "$0")" && pwd)"
out="${1:-firmware-akatsuki}"
squash="$here/pil-squasher.py"

command -v adb >/dev/null 2>&1 || die "adb introuvable sur le PC."
command -v python3 >/dev/null 2>&1 || die "python3 introuvable sur le PC."
[ -f "$squash" ] || die "pil-squasher.py introuvable : $squash"

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

# Où Android range les firmwares (partitions modem, bluetooth, vendor)
DIRS="/vendor/firmware_mnt/image /firmware/image /vendor/firmware /vendor/bt_firmware/image /bt_firmware/image /vendor/firmware/wlan"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
mkdir -p "$out/qcom/sdm845/Sony/tama" "$out/qca/Sony/tama"
dst="$out/qcom/sdm845/Sony/tama"

# Récupère tous les fichiers « nom.* » (nom.mdt, nom.b00…, nom.mbn) trouvés dans DIRS
pull_all() {
	name="$1"
	found=""
	for d in $DIRS; do
		for f in $(ash "ls $d/$name.* 2>/dev/null"); do
			adb pull "$f" "$work/" >/dev/null 2>&1 && found=1
		done
		[ -n "$found" ] && { echo "   $name ← $d"; return 0; }
	done
	return 1
}

# Firmwares des processeurs : .mdt découpé → .mbn d'un seul tenant
convert() {
	name="$1"; target="${2:-$1}"
	if ! pull_all "$name"; then
		echo "   $name : introuvable dans le téléphone (ignoré)"
		return 0
	fi
	if [ -f "$work/$name.mdt" ]; then
		python3 -I "$squash" "$dst/$target.mbn" "$work/$name.mdt"
	elif [ -f "$work/$name.mbn" ]; then
		cp "$work/$name.mbn" "$dst/$target.mbn"
	elif [ -f "$work/$name.elf" ]; then
		cp "$work/$name.elf" "$dst/$target.mbn"
	else
		echo "   $name : format inattendu (ni .mdt, ni .mbn), ignoré"
		return 0
	fi
	echo "   → qcom/sdm845/Sony/tama/$target.mbn ($(wc -c < "$dst/$target.mbn") octets)"
}

echo "== Extraction (lecture seule)"
convert adsp
convert cdsp
convert venus
convert a630_zap
convert mba
convert modem
convert slpi
convert ipa_fws
# Wi-Fi (chargé par le modem) : fichier simple, pas découpé
if pull_all wlanmdsp; then
	cp "$work/wlanmdsp.mbn" "$dst/wlanmdsp.mbn" && echo "   → qcom/sdm845/Sony/tama/wlanmdsp.mbn"
fi
# Bluetooth : réglages propres à la carte (le reste vient de linux-firmware-qcom)
if pull_all crnv21; then
	cp "$work/crnv21.bin" "$out/qca/Sony/tama/crnv21.bin" && echo "   → qca/Sony/tama/crnv21.bin"
fi
# Wi-Fi : réglages de carte Sony (antennes, puissances) → board-2.bin pour ath10k.
# Rangé sous updates/ : le noyau le préfère à celui de linux-firmware (réglages
# génériques, avec lesquels le firmware Wi-Fi plante, constaté le 11/10/2026).
for bd in /vendor/etc/wifi/bdwlan.bin /vendor/firmware/wlan/qca_cld/bdwlan.bin /vendor/firmware_mnt/image/bdwlan.bin; do
	adb pull "$bd" "$work/bdwlan.bin" >/dev/null 2>&1 || continue
	python3 -I "$here/ath10k-board2.py" "$out/updates/ath10k/WCN3990/hw1.0/board-2.bin" "$work/bdwlan.bin" >/dev/null && \
		echo "   bdwlan.bin ← $bd" && echo "   → updates/ath10k/WCN3990/hw1.0/board-2.bin"
	break
done

n="$(find "$out" -type f | wc -l)"
[ "$n" -gt 0 ] || die "aucun firmware récupéré."
echo
echo "$n fichier(s) dans $out/"

# Copie sur la partition d'échange de la carte SD (montée par Android)
uuid="$(ash sm list-volumes public 2>/dev/null | awk '/^public:179/ && $2 == "mounted" { print $3; exit }')"
copied=""
if [ -n "$uuid" ]; then
	# /storage/<UUID> : chemin normal d'écriture sur la carte pour adb. Le montage brut
	# /mnt/media_rw/<UUID> est refusé par SELinux (« secure_mkdirs() failed: Operation
	# not permitted », constaté le 11/10/2026) ; essayé seulement en secours.
	for sd in "/storage/$uuid" "/mnt/media_rw/$uuid"; do
		[ "$(ash "[ -d $sd ] && echo oui")" = "oui" ] || continue
		echo "== Copie sur la carte SD ($sd/firmware-akatsuki)"
		ash rm -rf "$sd/firmware-akatsuki" >/dev/null 2>&1 || true
		if adb push "$out" "$sd/firmware-akatsuki" >/dev/null 2>&1 && \
		   [ "$(ash "[ -f $sd/firmware-akatsuki/qcom/sdm845/Sony/tama/adsp.mbn ] && echo oui")" = "oui" ]; then
			ash sync
			copied=1
			break
		fi
		echo "   copie refusée sur $sd"
		ash rm -rf "$sd/firmware-akatsuki" >/dev/null 2>&1 || true
	done
fi
if [ -n "$copied" ]; then
	echo "Sous Arch (root) : cp -a /mnt/partage/firmware-akatsuki/. /usr/lib/firmware/ && reboot"
else
	echo "Pas de copie sur la carte SD. Sous Arch, copier depuis le PC :"
	echo "  scp -r $out alarm@172.16.42.1:/tmp/   puis (root) cp -a /tmp/$(basename "$out")/. /usr/lib/firmware/ && reboot"
fi
