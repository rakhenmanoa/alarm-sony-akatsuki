#!/bin/sh
# installer-audio.sh — Profil UCM du Xperia XZ3 (haut-parleurs, micro) pour PipeWire
# et Plasma. Prérequis : boot.img avec AUDIO=1 (dts/akatsuki-audio.dtsi).
# En root, depuis une copie du dépôt.
set -eu
[ "$(id -u)" -eq 0 ] || { echo "Erreur : lancer en root." >&2; exit 1; }
here="$(cd "$(dirname "$0")" && pwd)"
U=/usr/share/alsa/ucm2
pacman -S --needed --noconfirm alsa-ucm-conf alsa-utils pipewire pipewire-pulse wireplumber
install -d "$U/Sony/akatsuki" "$U/conf.d/sdm845"
install -m 644 "$here/../rootfs$U/Sony/akatsuki/akatsuki.conf" "$here/../rootfs$U/Sony/akatsuki/HiFi.conf" "$U/Sony/akatsuki/"
ln -sf ../../Sony/akatsuki/akatsuki.conf "$U/conf.d/sdm845/Sony-Xperia-XZ3.conf"
# PipeWire : périodes adaptées à l'ADSP (sinon « Error queuing playback buffer -16 »)
install -D -m 644 "$here/../rootfs/etc/wireplumber/wireplumber.conf.d/51-akatsuki-q6asm.conf" \
	/etc/wireplumber/wireplumber.conf.d/51-akatsuki-q6asm.conf
# Son des appels
install -m 755 "$here/audio-essai.sh" "$here/appel-essai.sh" "$here/appel-son.sh" "$here/voix-hostless.py" /usr/local/bin/
install -m 644 "$here/../rootfs/etc/systemd/system/akatsuki-appel-son.service" /etc/systemd/system/
systemctl daemon-reload
systemctl enable --now akatsuki-appel-son.service
card="$(awk '/Sony-Xperia-XZ3/ { print $1; exit }' /proc/asound/cards)"
[ -n "$card" ] && alsaucm -c "$card" list _verbs || echo "Carte Sony-Xperia-XZ3 absente : démarrer l'image AUDIO=1."
echo "Terminé. Redémarrer la session (ou le téléphone) pour que PipeWire relise le profil."
