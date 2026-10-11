#!/bin/sh
# installer-outils-modem.sh — Installe sous Arch (sur le téléphone, en root) les
# services nécessaires au modem et au Wi-Fi du Xperia XZ3 :
#
#   qrtr       bibliothèque du bus de messages Qualcomm (QRTR) ;
#   rmtfs      sert au modem ses données (EFS) — ici, des COPIES dans /var/lib/rmtfs ;
#   tqftpserv  sert au modem les fichiers qu'il demande (wlanmdsp.mbn pour le Wi-Fi).
#
# Le pd-mapper n'est pas nécessaire : il est dans le noyau (module qcom_pd_mapper).
#
# Paquets Arch Linux ARM s'ils existent, sinon compilation depuis les sources
# linux-msm (installées dans /usr/local). Aucun service n'est activé : les premiers
# essais se font à la main (docs/modem-wifi.md).
#
# Usage (root, internet par USB actif) :  sh installer-outils-modem.sh

set -eu
die() { echo "Erreur : $*" >&2; exit 1; }
[ "$(id -u)" -eq 0 ] || die "lancer en root."

if pacman -Si qrtr rmtfs tqftpserv >/dev/null 2>&1; then
	echo "== Paquets disponibles : installation par pacman"
	pacman -S --needed --noconfirm qrtr rmtfs tqftpserv
else
	echo "== Paquets absents des dépôts : compilation depuis les sources linux-msm"
	pacman -S --needed --noconfirm base-devel git meson ninja systemd-libs zstd xz
	src=/usr/local/src/linux-msm
	mkdir -p "$src"
	for r in qrtr rmtfs tqftpserv; do
		if [ -d "$src/$r/.git" ]; then
			git -C "$src/$r" pull --ff-only -q
		else
			git clone -q --depth 1 "https://github.com/linux-msm/$r" "$src/$r"
		fi
	done

	# Arch ne cherche pas les bibliothèques dans /usr/local/lib par défaut
	echo /usr/local/lib > /etc/ld.so.conf.d/usr-local.conf

	echo "== qrtr"
	(cd "$src/qrtr" && rm -rf build && meson setup build --prefix=/usr/local && ninja -C build && ninja -C build install)
	ldconfig

	echo "== rmtfs"
	if [ -f "$src/rmtfs/meson.build" ]; then
		(cd "$src/rmtfs" && rm -rf build && meson setup build --prefix=/usr/local && ninja -C build && ninja -C build install)
	else
		make -C "$src/rmtfs" clean >/dev/null 2>&1 || true
		make -C "$src/rmtfs" CFLAGS="-Wall -O2 -I/usr/local/include" LDFLAGS="-L/usr/local/lib -lqrtr -ludev -lpthread"
		install -D -m 755 "$src/rmtfs/rmtfs" /usr/local/bin/rmtfs
	fi

	echo "== tqftpserv"
	(cd "$src/tqftpserv" && rm -rf build && PKG_CONFIG_PATH=/usr/local/lib/pkgconfig meson setup build --prefix=/usr/local && ninja -C build && ninja -C build install)
	ldconfig
fi

# Les fichiers de service livrés par les sources ne doivent pas démarrer tout seuls
systemctl disable rmtfs.service rmtfs-dir.service tqftpserv.service >/dev/null 2>&1 || true

echo
for c in rmtfs tqftpserv qrtr-lookup; do
	printf '%-10s %s\n' "$c" "$(command -v "$c" || echo 'ABSENT')"
done
echo "Suite : docs/modem-wifi.md (copie de l'EFS, puis premier essai du modem)."
