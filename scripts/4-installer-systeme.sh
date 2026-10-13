#!/bin/sh
# 4-installer-systeme.sh — ÉTAPE 4 (téléphone, root) : installe le reste du système
# depuis internet et active tout : fichiers propres au téléphone (étape 1), modem,
# Wi-Fi, SIM, Plasma Mobile, son, appels, Bluetooth, capteurs, horloge, réglages.
#
# Prérequis : Arch démarré par l'étape 3, internet par le câble USB
# (sur le PC : sudo scripts/partage-internet-pc.sh start). Puis, sur le téléphone :
#   ssh alarm@172.16.42.1        (mot de passe : alarm)
#   su -                         (mot de passe : root)
#   sh /root/alarm-sony-akatsuki/scripts/4-installer-systeme.sh [APN]
#
# APN : point d'accès des données mobiles de l'opérateur (facultatif, réglable
# ensuite dans Plasma). Long (téléchargements, compilation de 2 paquets AUR) ; peut
# être relancé s'il s'arrête en cours de route.
set -eu
die() { echo "Erreur : $*" >&2; exit 1; }
etape() { echo; echo "######## $*"; }
[ "$(id -u)" -eq 0 ] || die "lancer en root (su -)."
here="$(cd "$(dirname "$0")" && pwd)"; repo="$here/.."
perso=/root/akatsuki-perso
APN="${1:-}"
[ -d "$perso" ] || die "$perso absent (étape 2)."
grep -q '\[none\]' /sys/kernel/security/lockdown 2>/dev/null || \
	die "noyau verrouillé : démarrer sur l'image de l'étape 2 (boot-akatsuki.img)."
getent hosts mirror.archlinuxarm.org >/dev/null || \
	die "pas d'internet : sur le PC, « sudo scripts/partage-internet-pc.sh start »."

etape "1/9 Heure (indispensable pour les téléchargements)"
timedatectl set-ntp true
i=0; while [ "$(timedatectl show -p NTPSynchronized --value)" != yes ] && [ $i -lt 60 ]; do sleep 1; i=$((i + 1)); done
date

etape "2/9 pacman et paquets de base"
grep -q '^DisableSandbox' /etc/pacman.conf || sed -i '/^\[options\]/a DisableSandbox' /etc/pacman.conf
[ -f /etc/pacman.d/gnupg/trustdb.gpg ] || { pacman-key --init; pacman-key --populate archlinuxarm; }
pacman -Syu --noconfirm
pacman -S --needed --noconfirm git python zstd base-devel sudo linux-firmware-qcom \
	wireless-regdb iwd bluez bluez-utils

etape "3/9 Fichiers propres au téléphone (firmwares, EFS, TA, Bluetooth, capteurs)"
install -m 755 "$repo/scripts/qmi-ecoute.py" "$repo/rootfs/usr/local/bin/akatsuki-mac" \
	"$repo/rootfs/usr/local/bin/akatsuki-perso" /usr/local/bin/
AKATSUKI_PERSO="$perso" SANS_REDEMARRAGE=1 /usr/local/bin/akatsuki-perso
sh "$here/installer-image-generique.sh"            # adresses MAC lues dans la TA

etape "4/9 Modem, Wi-Fi, SIM"
sh "$here/installer-outils-modem.sh"
ln -sfn "$perso/firmware-akatsuki" /root/fw-essai
sh "$here/installer-demarrage-auto.sh"

etape "5/9 Plasma Mobile"
pacman -S --needed --noconfirm mesa plasma-mobile plasma-pa kscreen konsole sddm qt6-wayland \
	plasma-keyboard hunspell-fr
pacman -S --needed --noconfirm plasma-camera || echo "   (plasma-camera indisponible)"
mkdir -p /etc/sddm.conf.d
cat > /etc/sddm.conf.d/autologin.conf <<'E'
[Autologin]
User=alarm
Session=plasma-mobile

[General]
DisplayServer=wayland
E
sh "$here/installer-plasma-mobile.sh"
if [ -n "$APN" ]; then sh "$here/installer-networkmanager.sh" "$APN"; else sh "$here/installer-networkmanager.sh"; fi
sh "$here/installer-zram.sh"
sh "$here/installer-demarrage-arret.sh"

etape "6/9 Son et appels"
sh "$here/installer-audio.sh"

etape "7/9 Paquets AUR (hexagonrpcd pour les capteurs, plasma-dialer pour les appels)"
echo 'alarm ALL=(ALL) NOPASSWD: ALL' > /etc/sudoers.d/99-akatsuki-aur
chmod 440 /etc/sudoers.d/99-akatsuki-aur
trap 'rm -f /etc/sudoers.d/99-akatsuki-aur' EXIT
aur() {
	pacman -Q "$1" >/dev/null 2>&1 && { echo "   $1 déjà installé"; return 0; }
	su - alarm -c "rm -rf ~/aur/$1 && mkdir -p ~/aur && git clone --depth 1 https://aur.archlinux.org/$1.git ~/aur/$1 && cd ~/aur/$1 && makepkg -si --noconfirm --needed"
}
aur hexagonrpcd
pacman -S --needed --noconfirm spacebar 2>/dev/null || aur spacebar
aur plasma-dialer || echo "   (plasma-dialer : à installer plus tard depuis l'AUR)"
rm -f /etc/sudoers.d/99-akatsuki-aur

etape "8/9 Bluetooth et capteurs"
bt=$(find "$perso/blobs-akatsuki/bt_firmware" -name crbtfw21.tlv 2>/dev/null | head -n 1)
[ -n "$bt" ] || bt=/usr/lib/firmware/updates/qca/crbtfw21.tlv
SONY_FW="$bt" KO="$repo/modules/precompiles/$(uname -r)" sh "$here/installer-bluetooth.sh"
BLOBS="$perso/blobs-akatsuki" sh "$here/installer-capteurs.sh"

etape "9/9 Horloge, réactivité, lampe de poche"
sh "$here/installer-horloge.sh"
sh "$here/installer-reactivite.sh"
install -m 644 "$repo/rootfs/etc/udev/rules.d/90-akatsuki-lampe.rules" /etc/udev/rules.d/
systemctl enable sddm

echo
echo "Étape 4 terminée. Changer les mots de passe (passwd ; passwd alarm), puis : reboot"
echo "Au redémarrage, Plasma Mobile s'ouvre ; Wi-Fi et données dans le panneau réseau."
