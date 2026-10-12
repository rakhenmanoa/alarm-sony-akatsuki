#!/bin/sh
# copier-ta-adb.sh — Copie la partition TA (« Trim Area ») du Xperia XZ3 pour le
# service MiscTA d'Arch (qmi-ecoute.py), qui la sert au modem.
#
# La TA contient les réglages d'usine Sony (partition 2, « misc », lue par le modem)
# et les clés DRM (partition 1). Le service d'Arch ne lit que la partition 2 et
# n'écrit JAMAIS dans cette copie (les écritures du modem vont à côté).
#
# LECTURE SEULE côté téléphone (cat de la partition vers le PC).
#
# Usage (sur le PC, depuis le dépôt, LineageOS démarré, « Débogage root » activé) :
#   scripts/copier-ta-adb.sh [dossier-de-sortie]      (défaut : ./ta-akatsuki)
#
# ⚠️ Fichier PERSONNEL et irremplaçable (clés DRM de CE téléphone) : ne jamais le
#    publier ni l'envoyer à qui que ce soit (dossier ignoré par git). Garder la copie
#    du PC comme sauvegarde.

set -eu
die() { echo "Erreur : $*" >&2; exit 1; }

out="${1:-ta-akatsuki}"
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

src=""
for d in /dev/block/bootdevice/by-name /dev/block/by-name; do
	[ "$(ash "[ -e $d/TA ] && echo oui")" = "oui" ] && { src="$d/TA"; break; }
done
[ -n "$src" ] || die "partition TA introuvable."

size="$(ash "blockdev --getsize64 \$(readlink -f $src)")"
case "$size" in ''|*[!0-9]*) die "taille de la TA illisible." ;; esac

mkdir -p "$out"
chmod 700 "$out"
echo "== Copie (lecture seule) de $src ($size octets)"
adb exec-out "cat $src" > "$out/ta.img.tmp"
got="$(wc -c < "$out/ta.img.tmp" | tr -d ' ')"
[ "$got" = "$size" ] || die "$got octets lus, $size attendus."
mv "$out/ta.img.tmp" "$out/ta.img"
chmod 600 "$out/ta.img"
echo "   → $out/ta.img"
if command -v python3 >/dev/null 2>&1; then
	python3 -I "$(dirname "$0")/qmi-ecoute.py" --ta="$out/ta.img" --ta-lister | head -8
fi

# Copie sur la partition d'échange de la carte SD (montée par Android)
uuid="$(ash sm list-volumes public 2>/dev/null | awk '/^public:179/ && $2 == "mounted" { print $3; exit }')"
if [ -n "$uuid" ] && [ "$(ash "[ -d /storage/$uuid ] && echo oui")" = "oui" ]; then
	sd="/storage/$uuid"
	if adb push "$out/ta.img" "$sd/ta.img" >/dev/null 2>&1; then
		ash sync
		echo "== Copie sur la carte SD : $sd/ta.img"
		echo "Sous Arch (root) : install -d -m 700 /var/lib/miscta && install -m 600 /mnt/partage/ta.img /var/lib/miscta/ && rm /mnt/partage/ta.img"
		exit 0
	fi
fi
echo "Pas de copie sur la carte SD. Sous Arch, copier depuis le PC :"
echo "  scp $out/ta.img alarm@172.16.42.1:/tmp/   puis (root) install -d -m 700 /var/lib/miscta && install -m 600 /tmp/ta.img /var/lib/miscta/ && rm /tmp/ta.img"
