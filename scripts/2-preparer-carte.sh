#!/bin/sh
# 2-preparer-carte.sh — ÉTAPE 2 (PC, root) : construit l'image de démarrage (noyau
# pmOS corrigé + DTB du XZ3, garde-fou UFS) et prépare la carte micro-SD : Arch
# Linux ARM, modules du noyau pmOS et nos modules précompilés, copie du dépôt et des
# fichiers propres au téléphone (étape 1), dans la partition d'Arch (pas sur la
# partition d'échange lisible par Android).
#
#   sudo scripts/2-preparer-carte.sh /dev/sdX ArchLinuxARM-aarch64-latest.tar.gz \
#        linux-postmarketos-qcom-sdm845-7.1_rc1-r4.apk [akatsuki-perso]
#
# Produit boot-akatsuki.img (générique : sans adresse MAC, lues dans la TA au
# démarrage) pour l'étape 3. LA CARTE EST ENTIÈREMENT EFFACÉE.
set -eu
die() { echo "Erreur : $*" >&2; exit 1; }
[ "$(id -u)" -eq 0 ] || die "lancer en root (sudo)."
[ $# -ge 3 ] || die "usage : $0 /dev/sdX <ArchLinuxARM-aarch64-latest.tar.gz> <noyau-pmos.apk> [akatsuki-perso]"
dev="$1"; tarball="$2"; apk="$3"; perso="${4:-akatsuki-perso}"
here="$(cd "$(dirname "$0")" && pwd)"; repo="$here/.."
for f in "$tarball" "$apk"; do [ -f "$f" ] || die "introuvable : $f"; done
[ -d "$perso" ] || die "dossier de l'étape 1 introuvable : $perso"
command -v git >/dev/null || die "git manquant."
# Modules précompilés et correctifs : valables pour ce noyau pmOS exactement
attendu=d0b4b950a500cede73fe5ce094060b1f9d608e3b4cbcb9d59bf2d876b2dc9804
if [ "$(sha256sum "$apk" | cut -d' ' -f1)" != "$attendu" ] && [ "${FORCER:-0}" != 1 ]; then
	die "$apk n'est pas linux-postmarketos-qcom-sdm845-7.1_rc1-r4 (SHA-256 différent) :
modules précompilés et correctifs non garantis (FORCER=1 pour passer outre)."
fi

echo "######## Image de démarrage"
ECRAN=dsi AUDIO=1 CAMERA=1 VIBREUR=1 FLASH=1 CAPTEURS=1 SANS_VERROU=1 \
	"$repo/test-boot/build.sh" "$apk" boot-akatsuki.img

echo "######## Carte micro-SD"
"$here/prepare-sdcard.sh" "$dev" "$tarball" "$apk"

case "$dev" in *[0-9]) p1="${dev}p1" ;; *) p1="${dev}1" ;; esac
mnt=$(mktemp -d)
trap 'umount "$mnt" 2>/dev/null || true; rmdir "$mnt" 2>/dev/null || true' EXIT
mount "$p1" "$mnt"

echo "######## Fichiers propres au téléphone → /root/akatsuki-perso"
install -d -m 700 "$mnt/root/akatsuki-perso"
cp -a "$perso"/. "$mnt/root/akatsuki-perso/"
chown -R 0:0 "$mnt/root/akatsuki-perso"; chmod -R go-rwx "$mnt/root/akatsuki-perso"

echo "######## Dépôt → /root/alarm-sony-akatsuki (fichiers suivis par git seulement)"
install -d "$mnt/root/alarm-sony-akatsuki"
git -C "$repo" archive HEAD | tar -x -C "$mnt/root/alarm-sony-akatsuki"

echo "######## Modules précompilés (écran, tactile, caméra, Bluetooth)"
kver=$(ls "$mnt/usr/lib/modules" | head -n 1)
src="$repo/modules/precompiles/$kver"
[ -d "$src" ] || die "pas de modules précompilés pour le noyau $kver."
install -D -m 644 "$src"/*.ko -t "$mnt/usr/lib/modules/$kver/updates/"
command -v depmod >/dev/null && depmod -b "$mnt" "$kver"

sync
echo
echo "Étape 2 terminée : carte prête, image boot-akatsuki.img."
echo "Suite : carte dans le téléphone, puis scripts/3-flasher.sh"
