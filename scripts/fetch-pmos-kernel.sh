#!/bin/sh
# fetch-pmos-kernel.sh — Télécharge le noyau SDM845 de postmarketOS
# (paquet linux-postmarketos-qcom-sdm845) pour le reconditionner en paquet Arch.
#
# Le script lit l'index officiel (APKINDEX) pour trouver la version actuelle,
# télécharge le .apk en HTTPS dans arch/linux-sony-akatsuki-pmos/, puis met à jour
# pkgver et sha256sums dans le PKGBUILD.
#
# Usage : scripts/fetch-pmos-kernel.sh
#
# Variables optionnelles :
#   PMOS_MIRRORS   miroirs à essayer (séparés par des espaces)
#   PMOS_BRANCHES  branches à essayer (le dépôt a été renommé de "master" en "main")
#   PMOS_PKG       nom du paquet noyau

set -eu

PMOS_MIRRORS="${PMOS_MIRRORS:-https://mirror.postmarketos.org/postmarketos}"
PMOS_BRANCHES="${PMOS_BRANCHES:-main master}"
PMOS_PKG="${PMOS_PKG:-linux-postmarketos-qcom-sdm845}"
ARCH=aarch64

here="$(cd "$(dirname "$0")" && pwd)"
pkgdir="$here/../arch/linux-sony-akatsuki-pmos"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

command -v curl >/dev/null 2>&1 || { echo "Erreur : curl est requis." >&2; exit 2; }

# Lit l'APKINDEX et renvoie la version du paquet demandé.
pkg_version() {
	tar -xzOf "$1" APKINDEX 2>/dev/null | awk -v pkg="$PMOS_PKG" '
		/^P:/ { name = substr($0, 3) }
		/^V:/ && name == pkg { print substr($0, 3); exit }
		/^$/ { name = "" }'
}

found=""
for mirror in $PMOS_MIRRORS; do
	for branch in $PMOS_BRANCHES; do
		base="$mirror/$branch/$ARCH"
		printf 'Index %s ... ' "$base"
		if curl -fsSL -o "$tmp/APKINDEX.tar.gz" "$base/APKINDEX.tar.gz" 2>/dev/null; then
			ver="$(pkg_version "$tmp/APKINDEX.tar.gz")"
			if [ -n "$ver" ]; then
				echo "trouvé : $PMOS_PKG $ver"
				found="$base"
				break 2
			fi
			echo "paquet absent"
		else
			echo "inaccessible"
		fi
	done
done

if [ -z "$found" ]; then
	echo "Erreur : $PMOS_PKG introuvable sur les miroirs testés." >&2
	echo "Vérifie l'URL du miroir (variable PMOS_MIRRORS)." >&2
	exit 1
fi

apk="$PMOS_PKG-$ver.apk"
echo "Téléchargement de $apk ..."
curl -fL --progress-bar -o "$pkgdir/$apk" "$found/$apk"

sum="$(sha256sum "$pkgdir/$apk" | cut -d' ' -f1)"
# Version Alpine (7.1_rc1-r4) -> version pacman (7.1_rc1_r4), sans tiret.
pkgver="$(printf '%s' "$ver" | tr '-' '_')"

sed -i \
	-e "s/^_pmosver=.*/_pmosver=$ver/" \
	-e "s/^pkgver=.*/pkgver=$pkgver/" \
	-e "s/^sha256sums=.*/sha256sums=('$sum')/" \
	"$pkgdir/PKGBUILD"

echo
echo "OK : $pkgdir/$apk"
echo "     sha256 $sum"
echo "PKGBUILD mis à jour (pkgver=$pkgver). Construire ensuite le paquet :"
echo "     cd arch/linux-sony-akatsuki-pmos"
echo "     sed 's/^CARCH=.*/CARCH=\"aarch64\"/' /etc/makepkg.conf > /tmp/makepkg-aarch64.conf"
echo "     makepkg -A --config /tmp/makepkg-aarch64.conf"
