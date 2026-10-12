#!/bin/sh
# alleger-plasma.sh — Libère de la mémoire sur le Xperia XZ3 sous Plasma Mobile en
# désactivant des services de bureau inutiles sur un téléphone (relevé du 12/10/2026 :
# ~350 Mo). En root. Retour arrière : voir la fin du script.
#
# Désactivés au démarrage de la session (fichiers ~/.config/autostart/*.desktop
# « Hidden=true », réversibles) :
#   DiscoverNotifier (notifications de mises à jour : sous Arch, c'est pacman)
#   xembedsniproxy, gmenudbusmenuproxy (icônes X11 et menu global : inutiles ici)
#   kalendarac, calindac (rappels d'agenda) — sauf AGENDA=1
#   kdeconnectd (liaison avec un PC/téléphone) — sauf KDECONNECT=1
# Système : packagekit masqué (sert à Discover ; utiliser pacman), réglages zram.
set -eu
[ "$(id -u)" -eq 0 ] || { echo "Erreur : lancer en root." >&2; exit 1; }
here="$(cd "$(dirname "$0")" && pwd)"
U=alarm
H=$(getent passwd $U | cut -d: -f6)
A="$H/.config/autostart"
install -d -o $U -g $U "$A"

cacher() { # cacher <fichier .desktop>
	for d in /etc/xdg/autostart /usr/share/autostart; do
		[ -f "$d/$1" ] || continue
		printf '[Desktop Entry]\nHidden=true\n' > "$A/$1"
		chown $U:$U "$A/$1"
		echo "   démarrage auto désactivé : $1"
		return
	done
}
cacher org.kde.discover.notifier.desktop
[ "${AGENDA:-0}" = 1 ] || { cacher org.kde.kalendarac.desktop; cacher org.kde.calindac.desktop; }
[ "${KDECONNECT:-0}" = 1 ] || cacher org.kde.kdeconnect.daemon.desktop

# Services de session Plasma (unités systemd utilisateur)
for u in plasma-xembedsniproxy.service plasma-gmenudbusmenuproxy.service; do
	systemctl --user -M $U@ mask "$u" >/dev/null 2>&1 && echo "   masqué (session) : $u"
done

systemctl mask --now packagekit.service >/dev/null 2>&1 && echo "   masqué : packagekit"
install -m 644 "$here/../rootfs/etc/sysctl.d/90-akatsuki-zram.conf" /etc/sysctl.d/
sysctl -q --system
echo
echo "Terminé : redémarrer le téléphone (reboot)."
echo "Retour arrière : rm $A/<fichier>.desktop ; systemctl --user -M $U@ unmask <unité> ;"
echo "                 systemctl unmask packagekit ; rm /etc/sysctl.d/90-akatsuki-zram.conf"
