#!/bin/sh
# appel-son.sh — Branche le son des appels automatiquement : surveille les appels de
# ModemManager et lance « appel-essai.sh start » dès qu'un appel est établi (actif),
# « stop » quand il n'y en a plus. Service : akatsuki-appel-son.service.
here="$(cd "$(dirname "$0")" && pwd)"
actif=0
while :; do
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
	sleep 1
done
