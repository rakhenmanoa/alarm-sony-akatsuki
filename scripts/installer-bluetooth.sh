#!/bin/sh
# installer-bluetooth.sh — Bluetooth du Xperia XZ3 (WCN3990), en root.
#
#   SONY_FW=/chemin/crbtfw21.tlv KO=/chemin/dossier-des-modules scripts/installer-bluetooth.sh
#
# SONY_FW : firmware Bluetooth de Sony (/vendor/bt_firmware/image/crbtfw21.tlv sous
#   LineageOS). Celui de linux-firmware annonce des commandes Bluetooth 5 qu'il
#   refuse ensuite (0x2031). Installé dans /usr/lib/firmware/updates/qca/, que le
#   noyau lit en premier : pacman ne l'écrase pas.
# KO : dossier contenant btqca.ko et hci_uart.ko construits avec modules/bt-qca/.
# Les deux sont facultatifs si déjà installés.
set -eu
[ "$(id -u)" -eq 0 ] || { echo "Erreur : lancer en root." >&2; exit 1; }
here="$(cd "$(dirname "$0")" && pwd)"
fw=/usr/lib/firmware/updates/qca/crbtfw21.tlv
mods=/usr/lib/modules/$(uname -r)/updates

if [ -n "${SONY_FW:-}" ]; then
	install -D -m 644 "$SONY_FW" "$fw"
fi
[ -f "$fw" ] || { echo "Erreur : $fw absent (indiquer SONY_FW=…)." >&2; exit 1; }
# Remettre le fichier de linux-firmware s'il avait été déplacé à la main
[ -f /usr/lib/firmware/qca/crbtfw21.tlv ] || [ ! -f /root/crbtfw21-linuxfw.tlv ] || \
	mv /root/crbtfw21-linuxfw.tlv /usr/lib/firmware/qca/crbtfw21.tlv

if [ -n "${KO:-}" ]; then
	install -D -m 644 "$KO/btqca.ko" "$mods/btqca.ko"
	install -D -m 644 "$KO/hci_uart.ko" "$mods/hci_uart.ko"
	depmod -a
fi
case "$(modinfo -n hci_uart)" in
	*/updates/*) ;;
	*) echo "Erreur : hci_uart modifié absent (indiquer KO=…)." >&2; exit 1 ;;
esac
install -m 644 "$here/../rootfs/etc/modprobe.d/akatsuki-bluetooth.conf" /etc/modprobe.d/
rm -f /etc/modprobe.d/bt-debug.conf

pacman -S --needed --noconfirm bluez bluez-utils
systemctl enable bluetooth.service
echo "Terminé. Redémarrer, puis : bluetoothctl show"
