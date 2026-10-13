#!/bin/sh
# installer-image-generique.sh — Prépare le système de référence (le téléphone qui
# fonctionne) à devenir l'image publiée : adresses MAC lues dans la TA au démarrage
# (image de démarrage générique, sans MAC dans le DTB), installation automatique des
# fichiers propres au téléphone déposés par scripts/preparer-telephone.sh, trousseau
# pacman recréé au premier démarrage. En root, depuis une copie du dépôt.
set -eu
[ "$(id -u)" -eq 0 ] || { echo "Erreur : lancer en root." >&2; exit 1; }
here="$(cd "$(dirname "$0")" && pwd)"; r="$here/../rootfs"
install -m 755 "$r/usr/local/bin/akatsuki-mac" "$r/usr/local/bin/akatsuki-perso" /usr/local/bin/
install -m 755 "$here/qmi-ecoute.py" /usr/local/bin/
for u in akatsuki-mac-wifi akatsuki-mac-bt akatsuki-perso akatsuki-cles-pacman; do
	install -m 644 "$r/etc/systemd/system/$u.service" /etc/systemd/system/
done
systemctl daemon-reload
systemctl enable akatsuki-mac-wifi akatsuki-mac-bt akatsuki-perso akatsuki-cles-pacman
/usr/local/bin/akatsuki-mac wifi || true
echo "Terminé. Démarrer ensuite sur l'image générique (sans WLAN_MAC/BT_MAC) et vérifier :"
echo "  ip link show wlan0 ; bluetoothctl show   → adresses d'origine"
