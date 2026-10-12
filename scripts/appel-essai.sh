#!/bin/sh
# appel-essai.sh — Essai à la main du son des appels (image boot-arch-appels.img).
# Pendant un appel décroché : relie la voix du modem au SLIMbus 0 (haut-parleurs,
# micro DMIC0) dans l'ADSP, puis ouvre et démarre le PCM VoiceMMode1 sans données
# (voix-hostless.py : la voix ne passe pas par Linux). En root.
#   scripts/appel-essai.sh start     # après avoir décroché
#   scripts/appel-essai.sh stop      # après avoir raccroché
set -u
here="$(cd "$(dirname "$0")" && pwd)"
card="$(awk '/Sony-Xperia-XZ3/ { print $1; exit }' /proc/asound/cards)"
[ -n "$card" ] || { echo "Erreur : carte Sony-Xperia-XZ3 absente." >&2; exit 1; }
dev="$(awk -F'[-:]' '/VoiceMMode1/ { print $2+0; exit }' /proc/asound/pcm)"
[ -n "$dev" ] || { echo "Erreur : PCM VoiceMMode1 absent (image boot-arch-appels.img ?)." >&2; exit 1; }
c() { amixer -q -c "$card" cset "name=$1" "$2" || echo "   (réglage refusé : $1)"; }
P=/run/appel-essai

case "${1:-}" in
start)
	"$here/audio-essai.sh" reglages >/dev/null      # haut-parleurs (codec, amplis)
	c "'DMIC MUX0'" DMIC0
	c "'ADC MUX0'" DMIC
	c "'AIF1_CAP Mixer SLIM TX0'" 1
	c "'CDC_IF TX0 MUX'" DEC0
	c "'SLIMBUS_0_RX Voice Mixer VoiceMMode1'" 1
	c "'VoiceMMode1 Capture Mixer SLIMBUS_0_TX'" 1
	mkdir -p $P
	for debit in 8000; do
		python3 "$here/voix-hostless.py" "hw:$card,$dev" $debit > $P/voix.log 2>&1 & echo $! > $P/voix.pid
		sleep 2
		if kill -0 "$(cat $P/voix.pid)" 2>/dev/null; then
			cat $P/voix.log
			echo "Parlez / écoutez ; puis : $0 stop"
			exit 0
		fi
		echo "   $debit Hz refusé : $(cat $P/voix.log)"
	done
	echo "Aucun débit accepté : dmesg | tail -20"; exit 1 ;;
stop)
	kill "$(cat $P/voix.pid 2>/dev/null)" 2>/dev/null; sleep 1
	c "'SLIMBUS_0_RX Voice Mixer VoiceMMode1'" 0
	c "'VoiceMMode1 Capture Mixer SLIMBUS_0_TX'" 0
	echo "Session voix fermée." ;;
*) echo "Usage : $0 start|stop" ;;
esac
