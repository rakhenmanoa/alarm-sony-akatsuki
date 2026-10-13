#!/bin/sh
# installer-reactivite.sh — Réglages de réactivité (rootfs/usr/local/bin/akatsuki-reactivite)
# et montage de la carte SD sans écriture des dates d'accès (noatime). En root.
# PROFIL=reactif pour le profil « réactif » (défaut : « frais », moins de chauffe).
set -eu
[ "$(id -u)" -eq 0 ] || { echo "Erreur : lancer en root." >&2; exit 1; }
here="$(cd "$(dirname "$0")" && pwd)"; r="$here/../rootfs"
install -m 755 "$r/usr/local/bin/akatsuki-reactivite" /usr/local/bin/
install -m 644 "$r/etc/systemd/system/akatsuki-reactivite.service" /etc/systemd/system/
systemctl daemon-reload
systemctl enable akatsuki-reactivite.service
/usr/local/bin/akatsuki-reactivite "${PROFIL:-}"          # PROFIL=frais (défaut) ou reactif
# / : relatime → noatime (moins d'écritures sur la carte)
sed -i -E 's#^(/dev/mmcblk0p1[[:space:]]+/[[:space:]]+ext4[[:space:]]+)rw,relatime([[:space:]])#\1rw,noatime\2#' /etc/fstab
mount -o remount,noatime /
grep ' / ' /proc/mounts
systemctl status --no-pager akatsuki-reactivite | tail -3
