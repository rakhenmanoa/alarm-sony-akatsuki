#!/bin/sh
# installer-horloge.sh — Heure juste au démarrage (RTC en lecture seule), en root.
# Il faut que l'heure soit juste une première fois : par NTP (connexion internet)
# ou à la main (date -s "AAAA-MM-JJ HH:MM").
set -eu
[ "$(id -u)" -eq 0 ] || { echo "Erreur : lancer en root." >&2; exit 1; }
here="$(cd "$(dirname "$0")" && pwd)"; r="$here/../rootfs"
install -m 755 "$r/usr/local/bin/akatsuki-horloge" /usr/local/bin/
for u in akatsuki-horloge.service akatsuki-horloge-sauver.service akatsuki-horloge-sauver.timer; do
	install -m 644 "$r/etc/systemd/system/$u" /etc/systemd/system/
done
systemctl daemon-reload
timedatectl set-ntp true || true
systemctl enable akatsuki-horloge.service akatsuki-horloge-sauver.timer
systemctl start akatsuki-horloge-sauver.timer
/usr/local/bin/akatsuki-horloge sauver
echo "RTC : $(cat /sys/class/rtc/rtc0/since_epoch 2>/dev/null) — heure : $(date)"
[ -f /var/lib/akatsuki/horloge-ecart ] && echo "Écart enregistré : $(cat /var/lib/akatsuki/horloge-ecart) s" || \
	echo "Heure pas encore juste : régler l'heure (NTP ou date -s) puis relancer ce script."
