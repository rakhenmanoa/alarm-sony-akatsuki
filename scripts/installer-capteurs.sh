#!/bin/sh
# installer-capteurs.sh — Capteurs du Xperia XZ3 (SLPI), en root.
#
#   BLOBS=/mnt/partage/blobs-akatsuki scripts/installer-capteurs.sh
#
# BLOBS : dossier créé par scripts/sauver-blobs-adb.sh sous LineageOS (dsp/,
# etc-sensors/, persist-sensors/). Fichiers propriétaires : copiés seulement sur le
# téléphone, jamais dans le dépôt.
# Prérequis : DTB construit avec CAPTEURS=1, slpi.mbn installé, hexagonrpcd (AUR).
#
# Arborescence servie au SLPI par hexagonrpcd (-R) :
#   dsp/                  ← /vendor/dsp et /vendor/lib/rfsa/adsp
#   sensors/config/       ← /vendor/etc/sensors/config
#   sensors/registry/     ← /mnt/vendor/persist/sensors/registry/registry
#   sensors/sns_reg.conf  ← /vendor/etc/sensors/sns_reg_config
#   socinfo/              ← /sys/devices/soc0 d'Android (hw_platform…) : les configs
#                           JSON de Sony ne s'appliquent que si hw_platform vaut MTP,
#                           Surf ou QRD et soc_id 321 (SDM845). Sans ces fichiers,
#                           l'accéléromètre n'apparaissait pas (12/10/2026).
#                           Valeurs réglables : HW_PLATFORM=… SOC_ID=… etc.
set -eu
[ "$(id -u)" -eq 0 ] || { echo "Erreur : lancer en root." >&2; exit 1; }
here="$(cd "$(dirname "$0")" && pwd)"
b="${BLOBS:?indiquer BLOBS=dossier de sauver-blobs-adb.sh}"
d=/usr/share/qcom/sdm845/Sony/tama
[ -f /usr/lib/firmware/qcom/sdm845/Sony/tama/slpi.mbn ] || \
	echo "Attention : qcom/sdm845/Sony/tama/slpi.mbn absent (scripts/extraire-firmwares-adb.sh)."
command -v hexagonrpcd >/dev/null || { echo "Erreur : hexagonrpcd absent (yay -S hexagonrpcd)." >&2; exit 1; }

trouve() { find "$b/$1" -type "$2" -path "*$3" 2>/dev/null | head -n 1; }
mkdir -p "$d/dsp" "$d/sensors"
for src in "$b"/dsp/*; do [ -d "$src" ] && cp -a "$src"/. "$d/dsp/"; done
cfg=$(trouve etc-sensors d /config); reg=$(trouve persist-sensors d /registry/registry)
snsc=$(trouve etc-sensors f /sns_reg_config)
[ -n "$cfg" ] && [ -n "$reg" ] && [ -n "$snsc" ] || { echo "Erreur : config/registry/sns_reg_config introuvables dans $b" >&2; exit 1; }
rm -rf "$d/sensors/config" "$d/sensors/registry"
cp -a "$cfg" "$d/sensors/config"; cp -a "$reg" "$d/sensors/registry"
install -m 644 "$snsc" "$d/sensors/sns_reg.conf"
mkdir -p "$d/socinfo"
printf '%s\n' "${HW_PLATFORM:-MTP}" > "$d/socinfo/hw_platform"
printf '%s\n' "${SOC_ID:-321}" > "$d/socinfo/soc_id"
printf '%s\n' "${PLATFORM_SUBTYPE:-Unknown}" > "$d/socinfo/platform_subtype"
printf '%s\n' "${PLATFORM_SUBTYPE_ID:-0}" > "$d/socinfo/platform_subtype_id"
printf '%s\n' "${PLATFORM_VERSION:-65536}" > "$d/socinfo/platform_version"
printf '%s\n' "${REVISION:-2.1}" > "$d/socinfo/revision"
echo "Fichiers : $(find "$d" -type f | wc -l) dans $d"

pacman -S --needed --noconfirm iio-sensor-proxy
install -m 644 "$here/../rootfs/etc/systemd/system/akatsuki-hexagonrpcd-sdsp.service" /etc/systemd/system/
systemctl daemon-reload
systemctl enable akatsuki-hexagonrpcd-sdsp.service
echo "Terminé. Vérifier : ls /dev/fastrpc-sdsp ; systemctl start akatsuki-hexagonrpcd-sdsp ;"
echo "journalctl -u akatsuki-hexagonrpcd-sdsp ; monitor-sensor"
