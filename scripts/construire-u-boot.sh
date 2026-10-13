#!/bin/sh
# construire-u-boot.sh — (PC) Compile U-Boot pour le Xperia XZ3 et l'emballe en image
# de démarrage Android que le chargeur de Sony accepte (à la place du noyau).
#
#   scripts/construire-u-boot.sh [sortie.img]          (défaut : u-boot-akatsuki.img)
#
# U-Boot lit ensuite /boot/extlinux/extlinux.conf sur la carte micro-SD (noyau, DTB,
# initramfs : scripts/installer-u-boot-carte.sh) : un nouveau noyau ne demande plus de
# reflasher boot_b.
#
# SÉCURITÉ : U-Boot est compilé SANS pilote UFS/SCSI ni fastboot (u-boot/akatsuki.config)
# et son DTB passe le garde-fou check-dtb-ufs.sh. Essai sans risque :
#   fastboot boot u-boot-akatsuki.img
#
# Nécessite : git, make, clang + ld.lld + outils llvm (cible aarch64), flex, bison,
# python3, dtc, mkbootimg, gzip. Variables : UBOOT_TAG (défaut v2026.07),
# UBOOT_SRC (dossier des sources, défaut ./u-boot-src).
set -eu
here="$(cd "$(dirname "$0")" && pwd)"; repo="$here/.."
out="${1:-u-boot-akatsuki.img}"
tag="${UBOOT_TAG:-v2026.07}"
src="${UBOOT_SRC:-$PWD/u-boot-src}"
die() { echo "Erreur : $*" >&2; exit 1; }
for c in git make clang ld.lld llvm-objcopy flex bison python3 dtc mkbootimg gzip; do
	command -v "$c" >/dev/null || die "$c est requis."
done

if [ ! -d "$src/.git" ]; then
	git clone --depth 1 -b "$tag" https://github.com/u-boot/u-boot.git "$src"
fi
cp "$repo/u-boot/akatsuki.config" "$repo/u-boot/akatsuki.env" "$src/board/qualcomm/"

# Outils croisés : llvm à la place de binutils aarch64, clang avec son assembleur intégré
outils="$(mktemp -d)"; trap 'rm -rf "$outils"' EXIT
for t in ar nm objcopy objdump readelf strip; do ln -s "$(command -v llvm-$t)" "$outils/aarch64-linux-gnu-$t"; done
ln -s "$(command -v ld.lld)" "$outils/aarch64-linux-gnu-ld"
printf '#!/bin/sh\nexec %s "$@" -fintegrated-as\n' "$(command -v clang)" > "$outils/clang-ias"
command -v xxd >/dev/null || cp "$repo/u-boot/xxd-mini.py" "$outils/xxd"
chmod +x "$outils"/*
export PATH="$outils:$PATH"

m() { make -C "$src" O=.akatsuki CROSS_COMPILE=aarch64-linux-gnu- CC=clang-ias "$@"; }
m -s qcom_defconfig akatsuki.config
for s in CONFIG_UFS CONFIG_UFS_QCOM CONFIG_SCSI CONFIG_PHY_QCOM_QMP_UFS CONFIG_FASTBOOT; do
	grep -q "^$s=y" "$src/.akatsuki/.config" && die "$s activé dans la configuration de U-Boot : refus."
done
m -s -j"$(nproc)"

b="$src/.akatsuki"
dtb="$b/dts/upstream/src/arm64/qcom/sdm845-sony-xperia-tama-akatsuki.dtb"
tmp="$(mktemp -d)"; trap 'rm -rf "$outils" "$tmp"' EXIT
{ dtc -q -I dtb -O dts "$dtb"; cat "$repo/u-boot/akatsuki-u-boot.dtsi"; } > "$tmp/u-boot.dts"
dtc -q -I dts -O dtb -o "$tmp/u-boot.dtb" "$tmp/u-boot.dts"
"$here/check-dtb-ufs.sh" "$tmp/u-boot.dtb"

# TEXT_OFFSET à 0 dans l'en-tête Image (voir u-boot/entete-image.py)
python3 "$repo/u-boot/entete-image.py" "$b/u-boot-nodtb.bin" "$tmp/u-boot.bin"
gzip -9nc "$tmp/u-boot.bin" > "$tmp/u-boot.gz"
# Le chargeur de Sony peut refuser une image sans ramdisk : archive cpio vide (fin seule)
python3 -c 'import sys,gzip; h=b"070701"+b"%08X"*13 % (0,0,0,0,1,0,0,0,0,0,0,11,0)+b"TRAILER!!!\0"; h+=b"\0"*(-len(h)%4); h+=b"\0"*(-len(h)%512); sys.stdout.buffer.write(gzip.compress(h,9,mtime=0))' > "$tmp/ramdisk"
"$here/make-bootimg.sh" "$tmp/u-boot.gz" "$tmp/u-boot.dtb" "$tmp/ramdisk" "$out" "u-boot" >/dev/null
echo "U-Boot $tag : $out ($(sha256sum "$out" | cut -c1-8))"
echo "Essai sans risque : fastboot boot $out"
