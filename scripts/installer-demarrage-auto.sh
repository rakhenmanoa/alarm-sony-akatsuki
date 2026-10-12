#!/bin/sh
# installer-demarrage-auto.sh — Rend permanents le modem et le Wi-Fi du Xperia XZ3
# sous Arch : tout démarre seul au boot (à lancer sur le téléphone, en root, depuis
# une copie du dépôt : git clone https://github.com/rakhenmanoa/alarm-sony-akatsuki).
#
# Prérequis (docs/modem-wifi.md) :
#   - boot.img sans verrouillage (SANS_VERROU=1, boot-arch-wifi.img) sur le slot B ;
#   - copie de l'EFS dans /var/lib/rmtfs (scripts/copier-efs-adb.sh) ;
#   - firmwares Sony dans /root/fw-essai (scripts/extraire-firmwares-adb.sh) ;
#   - rmtfs et tqftpserv installés (scripts/installer-outils-modem.sh) ;
#   - réglages Wi-Fi Sony : /usr/lib/firmware/updates/ath10k/WCN3990/hw1.0/board-2.bin.
#
# Ce que fait le script :
#   1. installe dans /usr/lib/firmware les firmwares VALIDÉS seulement
#      (adsp, cdsp, mba, modem, wlanmdsp, ipa_fws, a630_zap) — pas venus (redémarrage
#      immédiat), ni slpi (pas encore essayé) ;
#   2. installe le module ath10k_core corrigé (sans « quiet mode ») ;
#   3. installe qmi-ecoute.py, akatsuki-modem-essai.sh, les services systemd
#      (akatsuki-qmi-sony, akatsuki-tqftpserv, akatsuki-modem), la configuration
#      d'iwd et la route USB de priorité basse ;
#   4. active ces services et iwd.
# Retour arrière : systemctl disable --now akatsuki-modem akatsuki-tqftpserv akatsuki-qmi-sony

set -eu
die() { echo "Erreur : $*" >&2; exit 1; }
[ "$(id -u)" -eq 0 ] || die "lancer en root."
here="$(cd "$(dirname "$0")" && pwd)"
repo="$here/.."
FW=/root/fw-essai/qcom/sdm845/Sony/tama
DST=/usr/lib/firmware/qcom/sdm845/Sony/tama
M=/usr/lib/modules/$(uname -r)

echo "== Vérifications"
grep -q '\[none\]' /sys/kernel/security/lockdown || \
	die "noyau verrouillé : démarrer d'abord boot-arch-wifi.img (SANS_VERROU=1)."
[ -f /var/lib/rmtfs/modem_fs1 ] || die "copie de l'EFS absente de /var/lib/rmtfs."
for c in rmtfs tqftpserv python3 zstd; do
	command -v "$c" >/dev/null 2>&1 || die "$c introuvable."
done
[ -f /usr/lib/firmware/updates/ath10k/WCN3990/hw1.0/board-2.bin ] || \
	echo "   Attention : réglages Wi-Fi Sony (board-2.bin) absents : le Wi-Fi plantera."

echo "== 1. Firmwares validés → $DST"
install -d "$DST"
for f in adsp cdsp mba modem wlanmdsp ipa_fws a630_zap; do
	if [ -f "$FW/$f.mbn" ]; then
		install -m 644 "$FW/$f.mbn" "$DST/$f.mbn" && echo "   $f.mbn"
	elif [ -f "$DST/$f.mbn" ]; then
		echo "   $f.mbn (déjà en place)"
	else
		die "$f.mbn absent de $FW."
	fi
done
for f in venus slpi; do
	[ -f "$DST/$f.mbn" ] && echo "   Attention : $DST/$f.mbn présent (non validé, à retirer en cas de souci)."
done

echo "== 2. Module ath10k_core sans « quiet mode »"
if [ -f "$M/updates/ath10k_core.ko" ]; then
	echo "   déjà en place"
else
	zstd -qdc "$M/kernel/drivers/net/wireless/ath/ath10k/ath10k_core.ko.zst" > /tmp/ath10k_core.ko
	python3 -I "$here/ath10k-sans-quiet.py" /tmp/ath10k_core.ko /tmp/ath10k_core.sans-quiet.ko
	install -D -m 644 /tmp/ath10k_core.sans-quiet.ko "$M/updates/ath10k_core.ko"
	rm -f /tmp/ath10k_core.ko /tmp/ath10k_core.sans-quiet.ko
	depmod -a
fi

echo "== 3. Programmes, services, réseau"
install -m 755 "$here/qmi-ecoute.py" "$here/akatsuki-modem-essai.sh" /usr/local/bin/
for u in akatsuki-qmi-sony akatsuki-tqftpserv akatsuki-modem; do
	install -m 644 "$repo/rootfs/etc/systemd/system/$u.service" /etc/systemd/system/
done
install -D -m 644 "$repo/rootfs/etc/iwd/main.conf" /etc/iwd/main.conf
install -m 644 "$repo/rootfs/etc/systemd/network/50-usb0.network" /etc/systemd/network/50-usb0.network
command -v iwd >/dev/null 2>&1 || [ -x /usr/lib/iwd/iwd ] || pacman -S --needed --noconfirm iwd

echo "== 4. Activation"
systemctl daemon-reload
systemctl enable akatsuki-qmi-sony.service akatsuki-tqftpserv.service akatsuki-modem.service iwd.service

echo
echo "Terminé. Redémarrer : le modem et le Wi-Fi démarreront seuls."
echo "Après le redémarrage :"
echo "  systemctl status akatsuki-modem --no-pager"
echo "  iwctl station wlan0 show"
echo "  journalctl -u akatsuki-qmi-sony -b | grep '\\[modem\\]'   # journal du modem"
