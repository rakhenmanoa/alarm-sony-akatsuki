#!/bin/sh
# audio-essai.sh — Premier essai des haut-parleurs du Xperia XZ3 (DTB AUDIO=1).
# Règle le chemin MultiMedia1 → SLIMbus 0 → WCD9340 (RX INT7/8) → WSA8815 gauche et
# droit (mêmes réglages que l'UCM du Lenovo Yoga C630, volume des amplis réduit),
# puis joue un son de test 2 × 5 s. En root, depuis une copie du dépôt.
#   scripts/audio-essai.sh            # réglages + son de test
#   scripts/audio-essai.sh reglages   # réglages seulement
set -eu
die() { echo "Erreur : $*" >&2; exit 1; }
command -v amixer >/dev/null 2>&1 || pacman -S --needed --noconfirm alsa-utils
card="$(awk '/Sony-Xperia-XZ3|sdm845/ { print $1; exit }' /proc/asound/cards)"
[ -n "$card" ] || die "carte son absente (cat /proc/asound/cards ; dmesg | grep -iE 'wcd|slim|wsa|snd')."
c() { amixer -q -c "$card" cset "name=$1" "$2" || echo "   (réglage refusé : $1)"; }

echo "== Réglages (carte $card)"
c "'SLIMBUS_0_RX Audio Mixer MultiMedia1'" 1
c "'SLIM RX0 MUX'" AIF1_PB
c "'SLIM RX1 MUX'" AIF1_PB
c "'COMP7 Switch'" 1
c "'COMP8 Switch'" 1
c "'RX INT7_1 MIX1 INP0'" RX0
c "'RX INT8_1 MIX1 INP0'" RX1
for s in SpkrLeft SpkrRight; do
	c "'$s COMP Switch'" 1
	c "'$s BOOST Switch'" 1
	c "'$s DAC Switch'" 1
	c "'$s VISENSE Switch'" 0
	c "'$s PA Volume'" 6
done
[ "${1:-}" = reglages ] && exit 0

echo "== Son de test (gauche puis droite, 2 fois)"
speaker-test -D "hw:$card,0" -c 2 -r 48000 -F S16_LE -t sine -f 440 -l 2 || true
