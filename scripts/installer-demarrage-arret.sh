#!/bin/sh
# installer-demarrage-arret.sh — Démarrage et arrêt plus fiables sur le Xperia XZ3 :
#   - délais d'arrêt courts (15 s système, 10 s session) au lieu de 90 s ;
#   - chien de garde matériel : redémarrage automatique si le noyau se fige,
#     redémarrage forcé si l'arrêt bloque plus de 30 s ;
#   - Plasma (SDDM) attend l'écran et le GPU ;
#   - arrêt du modem borné ;
#   - services « attendre le réseau » masqués (bloquent le démarrage jusqu'à 2 min) ;
#   - à l'arrêt : Wi-Fi et modem coupés avant le modem (akatsuki-arret-reseau) ;
#   - moins de bruit : PowerDevil sans DDC/CI, générateur ostree inutile masqué,
#     seules les erreurs graves du noyau affichées à l'écran.
# En root, depuis une copie du dépôt. Retour arrière : supprimer les fichiers listés.
set -eu
[ "$(id -u)" -eq 0 ] || { echo "Erreur : lancer en root." >&2; exit 1; }
here="$(cd "$(dirname "$0")" && pwd)"
R="$here/../rootfs/etc/systemd"
for f in system.conf.d/10-akatsuki.conf user.conf.d/10-akatsuki.conf \
	system/sddm.service.d/10-akatsuki.conf system/akatsuki-modem.service.d/10-arret.conf \
	system/akatsuki-arret-reseau.service; do
	install -D -m 644 "$R/$f" "/etc/systemd/$f" && echo "   /etc/systemd/$f"
done
for u in systemd-networkd-wait-online.service NetworkManager-wait-online.service; do
	systemctl mask "$u" >/dev/null 2>&1 && echo "   masqué : $u"
done
install -D -m 644 "$here/../rootfs/etc/environment.d/90-akatsuki-powerdevil.conf" /etc/environment.d/90-akatsuki-powerdevil.conf
install -D -m 644 "$here/../rootfs/etc/sysctl.d/10-akatsuki-console.conf" /etc/sysctl.d/10-akatsuki-console.conf
sysctl -q -p /etc/sysctl.d/10-akatsuki-console.conf || true
# Générateur systemd d'ostree (tiré par flatpak) : échoue à chaque rechargement, inutile ici
if [ -e /usr/lib/systemd/system-generators/ostree-system-generator ]; then
	install -d /etc/systemd/system-generators
	ln -sf /dev/null /etc/systemd/system-generators/ostree-system-generator && echo "   masqué : ostree-system-generator"
fi
systemctl daemon-reload
systemctl enable --now akatsuki-arret-reseau.service >/dev/null 2>&1 && echo "   activé : akatsuki-arret-reseau.service"
if [ -e /dev/watchdog0 ] || [ -e /dev/watchdog ]; then
	echo "Chien de garde matériel présent : $(cat /sys/class/watchdog/watchdog0/identity 2>/dev/null)"
else
	echo "Pas de chien de garde matériel (/dev/watchdog absent) : réglage sans effet."
fi
echo "Terminé. Effet complet au prochain démarrage. Temps de démarrage : systemd-analyze blame | head"
