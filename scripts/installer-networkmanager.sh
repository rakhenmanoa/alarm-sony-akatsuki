#!/bin/sh
# installer-networkmanager.sh — Passe le Wi-Fi et les données mobiles du Xperia XZ3
# sous NetworkManager, pour que Plasma Mobile (plasma-nm) les affiche et les pilote.
# À lancer sur le téléphone, en root, depuis une copie du dépôt.
#
#   - NetworkManager avec iwd comme moteur Wi-Fi (iwd ne règle plus lui-même les
#     adresses IP : c'est NetworkManager qui le fait) ;
#   - usb0 laissé à systemd-networkd : la connexion SSH par USB n'est pas coupée ;
#   - données mobiles : NetworkManager passe par ModemManager ; une connexion « gsm »
#     est créée si un APN est donné en argument.
#
# Usage : scripts/installer-networkmanager.sh [APN]        (ex. : internet)
# Retour arrière : systemctl disable --now NetworkManager ; rm /etc/iwd/main.conf.nm ;
#                  réinstaller rootfs/etc/iwd/main.conf ; systemctl restart iwd

set -eu
die() { echo "Erreur : $*" >&2; exit 1; }
[ "$(id -u)" -eq 0 ] || die "lancer en root."
here="$(cd "$(dirname "$0")" && pwd)"
repo="$here/.."
apn="${1:-}"

echo "== Paquets"
pacman -S --needed --noconfirm networkmanager plasma-nm

echo "== Configuration"
install -D -m 644 "$repo/rootfs/etc/NetworkManager/conf.d/akatsuki.conf" \
	/etc/NetworkManager/conf.d/akatsuki.conf
# iwd : NetworkManager règle les adresses IP lui-même
cat > /etc/iwd/main.conf <<'EOF'
# iwd piloté par NetworkManager (installer-networkmanager.sh)
[General]
EnableNetworkConfiguration=false
EOF
# résolution DNS : NetworkManager écrit /etc/resolv.conf (sauf si systemd-resolved)
[ -L /etc/resolv.conf ] || rm -f /etc/resolv.conf

echo "== Services"
systemctl enable NetworkManager.service
systemctl restart iwd.service
systemctl restart NetworkManager.service
sleep 5
nmcli device status

if [ -n "$apn" ]; then
	echo "== Données mobiles (APN $apn)"
	nmcli connection show mobile >/dev/null 2>&1 || \
		nmcli connection add type gsm ifname '*' con-name mobile apn "$apn" \
			connection.autoconnect yes ipv6.method ignore
	nmcli connection up mobile || echo "   (connexion mobile pas encore possible : réessayer avec « nmcli connection up mobile »)"
fi

echo
echo "Terminé. Dans Plasma : choisir le réseau Wi-Fi et saisir son mot de passe"
echo "(les réseaux déjà connus d'iwd peuvent devoir être ressaisis une fois)."
echo "État : nmcli device status ; nmcli connection show"
