#!/bin/sh
# akatsuki-modem-essai.sh — Démarre le modem et le Wi-Fi du Xperia XZ3 sous Arch,
# en une commande, pour la session en cours (rien n'est rendu permanent).
#
# Usage (root) :  akatsuki-modem-essai.sh [start|stop|etat]
#
# start : 1. firmwares Sony visibles pour cette session (/root/fw-essai) ;
#         2. IPA ; 3. services Sony (qmi-ecoute.py, journal /root/qmi-ecoute.log) ;
#         4. tqftpserv (/root/tqftpserv.log) ; 5. rmtfs, qui démarre le modem
#            (/root/rmtfs.log) ; 6. attend wlan0.
# stop  : arrête rmtfs (donc le modem), tqftpserv et qmi-ecoute.py.
# etat  : état du modem, services QMI du modem, interfaces.

set -u
FW=/root/fw-essai
EFS=/var/lib/rmtfs
die() { echo "Erreur : $*" >&2; exit 1; }
[ "$(id -u)" -eq 0 ] || die "lancer en root."

modem() { dirname "$(grep -l 4080000 /sys/class/remoteproc/*/name 2>/dev/null | head -n1)"; }

arreter() {
	pkill -x rmtfs 2>/dev/null; pkill -x tqftpserv 2>/dev/null; pkill -f qmi-ecoute.py 2>/dev/null
	sleep 3
}

case "${1:-start}" in
start)
	[ -f "$FW/qcom/sdm845/Sony/tama/mba.mbn" ] || die "firmwares absents de $FW/qcom/sdm845/Sony/tama/."
	ls "$EFS"/modem_fs1 >/dev/null 2>&1 || die "copie de l'EFS absente de $EFS (scripts/copier-efs-adb.sh)."
	for c in rmtfs tqftpserv qmi-ecoute.py; do
		command -v "$c" >/dev/null 2>&1 || die "$c introuvable (voir docs/modem-wifi.md)."
	done
	R="$(modem)"; [ -d "$R" ] || die "modem absent du DTB (boot.img avec akatsuki-modem-wifi.dtsi ?)."
	arreter

	echo "== 1. Firmwares de la session : $FW"
	echo -n "$FW" > /sys/module/firmware_class/parameters/path
	echo "== 2. IPA"
	if [ ! -e /sys/bus/platform/drivers/ipa/1e40000.ipa ]; then
		echo 1e40000.ipa > /sys/bus/platform/drivers/ipa/bind 2>/dev/null || echo "   (IPA non liée)"
	fi
	echo "== 3. Services Sony (qmi-ecoute.py)"
	nohup qmi-ecoute.py > /root/qmi-ecoute.log 2>&1 &
	sleep 2
	echo "== 4. tqftpserv"
	nohup tqftpserv -d > /root/tqftpserv.log 2>&1 &
	echo "== 5. rmtfs (démarre le modem)"
	nohup rmtfs -o "$EFS" -s -v > /root/rmtfs.log 2>&1 &
	printf "== 6. Attente de wlan0 "
	i=0
	while [ $i -lt 40 ] && [ ! -e /sys/class/net/wlan0 ]; do printf .; sleep 1; i=$((i + 1)); done
	echo
	if [ -e /sys/class/net/wlan0 ]; then
		echo "wlan0 présente. Essai : ip link set wlan0 up && iw dev wlan0 scan | grep SSID"
	else
		echo "wlan0 absente après 40 s : voir dmesg et /root/*.log"
	fi
	echo "État du modem : $(cat "$R/state")"
	;;
stop)
	arreter
	R="$(modem)"; [ -d "$R" ] && echo "État du modem : $(cat "$R/state")"
	;;
etat)
	R="$(modem)"; [ -d "$R" ] && echo "Modem : $(cat "$R/state")"
	echo "Services annoncés par le modem (nœud 0) : $(qrtr-lookup 2>/dev/null | awk '$4 == 0' | wc -l)"
	ip -br link
	;;
*)
	echo "Usage : $0 [start|stop|etat]" >&2; exit 2 ;;
esac
