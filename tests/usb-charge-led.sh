#!/bin/bash
# Script de surveillance de la charge pour allumer la LED en violet
# À lancer comme service systemd root

LED_BRIGHTNESS="/sys/class/leds/rgb:status/brightness"
LED_INTENSITY="/sys/class/leds/rgb:status/multi_intensity"

# Recherche du fichier de statut de la batterie/charge
STATUS_FILE=$(find /sys/class/power_supply/ -name "status" | head -n 1)

if [ -z "$STATUS_FILE" ]; then
    echo "Erreur: Fichier status de batterie non trouvé"
    exit 1
fi

LAST_STATE=""

while true; do
    CURRENT_STATE=$(cat $STATUS_FILE)
    
    if [ "$CURRENT_STATE" != "$LAST_STATE" ]; then
        if [[ "$CURRENT_STATE" == *"Charging"* ]] || [[ "$CURRENT_STATE" == *"Full"* ]]; then
            # Allumer en Violet (Rouge + Bleu)
            echo 100 > $LED_BRIGHTNESS
            echo "255 0 255" > $LED_INTENSITY
        else
            # Éteindre
            echo 0 > $LED_BRIGHTNESS
        fi
        LAST_STATE=$CURRENT_STATE
    fi
    sleep 2
done
