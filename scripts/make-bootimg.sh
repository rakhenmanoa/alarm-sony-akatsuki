#!/bin/sh
# make-bootimg.sh — Assemble un boot.img pour le Xperia XZ3 (akatsuki).
#
# Offsets repris du portage Mobile NixOS de Petr Hodina (famille sdm845-mainline).
# Le DTB est vérifié par check-dtb-ufs.sh avant tout assemblage.
#
# Usage :
#   scripts/make-bootimg.sh <Image.gz> <fichier.dtb> <initramfs> <sortie.img> ["cmdline"]
#
# Exemple (rootfs Arch sur la carte SD) :
#   scripts/make-bootimg.sh Image.gz sdm845-sony-xperia-tama-akatsuki.dtb \
#       initramfs.img boot-arch.img "root=LABEL=ALARM_ROOT rootwait rw"
#
# Puis, téléphone en fastboot (Volume haut + USB, LED bleue) :
#   fastboot boot boot-arch.img      # démarrage temporaire, rien n'est écrit

set -eu

if [ "$#" -lt 4 ]; then
	sed -n '2,16p' "$0" | sed 's/^# \{0,1\}//'
	exit 2
fi

kernel="$1"; dtb="$2"; initramfs="$3"; out="$4"
cmdline="${5:-rootwait}"
here="$(cd "$(dirname "$0")" && pwd)"

for f in "$kernel" "$dtb" "$initramfs"; do
	[ -f "$f" ] || { echo "Erreur : fichier introuvable : $f" >&2; exit 2; }
done

if ! command -v mkbootimg >/dev/null 2>&1; then
	echo "Erreur : 'mkbootimg' est introuvable (paquet android-tools ou mkbootimg)." >&2
	exit 2
fi

# Garde-fou UFS : on refuse d'assembler un boot.img dangereux.
"$here/check-dtb-ufs.sh" "$dtb"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# Le bootloader Sony attend le DTB collé à la suite du noyau (appended DTB).
cat "$kernel" "$dtb" > "$tmp/Image.gz-dtb"

mkbootimg \
	--kernel "$tmp/Image.gz-dtb" \
	--ramdisk "$initramfs" \
	--base 0x00000000 \
	--kernel_offset 0x00008000 \
	--ramdisk_offset 0x01000000 \
	--second_offset 0x00000000 \
	--tags_offset 0x00000100 \
	--pagesize 4096 \
	--cmdline "$cmdline" \
	-o "$out"

echo "boot.img créé : $out"
echo "Test sans risque : fastboot boot $out"
