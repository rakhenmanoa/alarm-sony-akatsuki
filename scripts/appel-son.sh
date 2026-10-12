#!/bin/bash
# appel-son.sh — Branche le son des appels automatiquement : surveille les appels de
# ModemManager et lance « appel-essai.sh start » dès qu'un appel est établi (actif),
# « stop » quand il n'y en a plus. Service : akatsuki-appel-son.service.
#
# Réagit aux signaux D-Bus de ModemManager (gdbus monitor) au lieu d'interroger
# mmcli chaque seconde : l'ancienne boucle prenait ~5 % de processeur en
# permanence et réveillait le téléphone sans arrêt (relevé du 12/10/2026).
here="$(cd "$(dirname "$0")" && pwd)"
actif=0

verifier() {
	if mmcli -m any --voice-list-calls 2>/dev/null | grep -q '(active)'; then
		if [ $actif = 0 ]; then
			echo "appel établi : son branché"
			timeout 20 "$here/appel-essai.sh" start && actif=1
		fi
	elif [ $actif = 1 ]; then
		echo "appel terminé : son débranché"
		timeout 20 "$here/appel-essai.sh" stop
		actif=0
	fi
}

while :; do
	verifier
	# Un appel qui change d'état émet un signal sur /org/freedesktop/ModemManager1/Call/N.
	# Pendant un appel, vérification de secours toutes les 5 s.
	while :; do
		if read -r -t 5 ligne; then
			case "$ligne" in *Call*|*Voice*) verifier ;; esac
		else
			[ $? -gt 128 ] || break		# fin de gdbus (ModemManager redémarré)
			[ $actif = 1 ] && verifier
		fi
	done < <(gdbus monitor --system --dest org.freedesktop.ModemManager1 2>/dev/null)
	sleep 2
done
