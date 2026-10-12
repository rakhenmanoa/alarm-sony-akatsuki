#!/bin/sh
# releve-audio-adb.sh — Relève, sous LineageOS, ce qu'il faut pour décrire la carte son
# du Xperia XZ3 dans le DTB d'Arch : arbre matériel du noyau Sony, cartes ALSA, puces
# I2C (amplis), réglages de mixage d'Android.
#
# LECTURE SEULE côté téléphone.
#
# Usage (sur le PC, depuis le dépôt, LineageOS démarré, « Débogage root » activé) :
#   scripts/releve-audio-adb.sh [dossier-de-sortie]      (défaut : ./audio-akatsuki)
# Puis envoyer l'archive audio-akatsuki.tar.gz produite (aucune donnée personnelle :
# pas d'IMEI, pas de TA ; les fichiers d'étalonnage ACDB ne sont PAS copiés).

set -eu
die() { echo "Erreur : $*" >&2; exit 1; }
out="${1:-audio-akatsuki}"
command -v adb >/dev/null 2>&1 || die "adb introuvable sur le PC."
ash() { adb shell "$@" | tr -d '\r'; }

adb get-state >/dev/null 2>&1 || die "aucun téléphone vu par adb."
adb root >/dev/null 2>&1 || true
sleep 2
adb wait-for-device
[ "$(ash id -u)" = "0" ] || die "adb n'est pas root (Options pour les développeurs → Débogage root)."

mkdir -p "$out/vendor-etc"
echo "== Arbre matériel du noyau Sony"
adb exec-out "cat /sys/firmware/fdt" > "$out/lineage-fdt.dtb"
echo "== ALSA, I2C, SLIMbus, SoundWire"
{
	echo "### /proc/asound/cards";  ash cat /proc/asound/cards
	echo "### /proc/asound/pcm";    ash cat /proc/asound/pcm
	echo "### I2C";                 ash 'for d in /sys/bus/i2c/devices/*; do echo "$d $(cat $d/name 2>/dev/null) $(basename $(readlink $d/driver 2>/dev/null) 2>/dev/null)"; done'
	echo "### SLIMbus";             ash 'ls -l /sys/bus/slimbus/devices/ 2>/dev/null'
	echo "### SoundWire";           ash 'ls -l /sys/bus/soundwire/devices/ 2>/dev/null'
	echo "### Composants ASoC";     ash 'cat /sys/kernel/debug/asoc/components 2>/dev/null'
	echo "### DAI ASoC";            ash 'cat /sys/kernel/debug/asoc/dais 2>/dev/null'
	echo "### Modules";             ash 'lsmod 2>/dev/null'
	echo "### Propriétés audio";    ash 'getprop | grep -iE "audio|snd|vendor.audio"'
	echo "### dmesg (audio)";       ash 'dmesg | grep -iE "snd|asoc|wcd|slim|tfa|cs35|amp|audio|q6|apr" | tail -200'
} > "$out/lineage-audio.txt" 2>&1
echo "== Réglages de mixage (/vendor/etc)"
for f in $(ash 'ls /vendor/etc/ | grep -iE "mixer_paths|audio_platform_info|audio_policy|sound_trigger_mixer|audio_.*\.xml|tfa|cs35"'); do
	adb pull "/vendor/etc/$f" "$out/vendor-etc/$f" >/dev/null 2>&1 && echo "   $f"
done
ash 'ls -R /vendor/etc/acdbdata /vendor/firmware 2>/dev/null' > "$out/liste-acdb-firmware.txt"
tar czf "$out.tar.gz" "$out"
echo
echo "Terminé : $out.tar.gz (à envoyer)."
