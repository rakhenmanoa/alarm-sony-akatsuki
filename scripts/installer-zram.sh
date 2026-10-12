#!/bin/sh
# installer-zram.sh — Swap compressé en mémoire (zram) et locale UTF-8 pour Plasma.
# En root, depuis une copie du dépôt.
set -eu
[ "$(id -u)" -eq 0 ] || { echo "Erreur : lancer en root." >&2; exit 1; }
here="$(cd "$(dirname "$0")" && pwd)"
pacman -S --needed --noconfirm zram-generator
install -m 644 "$here/../rootfs/etc/systemd/zram-generator.conf" /etc/systemd/zram-generator.conf
systemctl daemon-reload
systemctl start systemd-zram-setup@zram0.service
# Locale : Plasma tournait en « C » (ASCII)
if ! locale -a 2>/dev/null | grep -qi 'fr_FR.utf8'; then
	sed -i 's/^#\(fr_FR.UTF-8 UTF-8\)/\1/' /etc/locale.gen
	locale-gen
fi
localectl set-locale LANG=fr_FR.UTF-8
swapon --show
echo "Terminé. Redémarrer la session Plasma (systemctl restart sddm) pour la langue."
