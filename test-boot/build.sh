#!/bin/sh
# build.sh — boot.img de test : « est-ce que notre noyau démarre ? »
#
# Pas de carte SD, pas de système : noyau pmOS + DTB + un initramfs de quelques
# centaines de Ko (init.c compilé + 5 modules USB). Rien n'est écrit sur le téléphone.
#
# Usage :
#   test-boot/build.sh <paquet-noyau-pmos.apk> [sortie.img]
#
# Nécessite : clang + ld.lld (cible aarch64), python3, gzip, tar, mkbootimg, dtc.
#
# Puis, téléphone en fastboot (Volume haut + USB, LED bleue) :
#   fastboot boot boot-test-noyau.img
#   cat /dev/ttyACM0          # ou : screen /dev/ttyACM0 — journal du noyau
#   ping 172.16.42.1          # après : sudo ip addr add 172.16.42.2/24 dev <interface usb>

set -eu

[ "$#" -ge 1 ] || { awk 'NR > 1 && /^#/ { sub(/^# ?/, ""); print; next } NR > 1 { exit }' "$0"; exit 2; }
apk="$1"
out="${2:-boot-test-noyau.img}"
here="$(cd "$(dirname "$0")" && pwd)"
repo="$here/.."

for c in clang ld.lld python3 gzip tar dtc; do
	command -v "$c" >/dev/null 2>&1 || { echo "Erreur : commande manquante : $c" >&2; exit 1; }
done

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

echo "== Extraction du paquet noyau"
mkdir "$tmp/apk"
gzip -dc "$apk" | tar -xi -C "$tmp/apk" -f - 2>/dev/null || true
moddir="$(ls -d "$tmp"/apk/usr/lib/modules/* "$tmp"/apk/lib/modules/* 2>/dev/null | head -n1)"
[ -n "$moddir" ] && [ -f "$tmp/apk/boot/vmlinuz" ] || { echo "Erreur : paquet noyau pmOS invalide." >&2; exit 1; }
echo "   noyau $(basename "$moddir")"

echo "== Compilation de init (aarch64, sans libc)"
clang --target=aarch64-linux-gnu -O2 -Wall -nostdlib -static -ffreestanding \
	-fno-stack-protector -fno-builtin -fuse-ld=lld -Wl,-e,_start -Wl,--build-id=none \
	-o "$tmp/init" "$here/init.c"

echo "== Initramfs"
root="$tmp/root"
mkdir -p "$root/lib/modules"
cp "$tmp/init" "$root/init"
for m in kernel/drivers/usb/gadget/libcomposite \
         kernel/drivers/usb/gadget/function/u_serial \
         kernel/drivers/usb/gadget/function/usb_f_acm \
         kernel/drivers/usb/gadget/function/u_ether \
         kernel/drivers/usb/gadget/function/usb_f_ncm; do
	cp "$moddir/$m.ko.zst" "$root/lib/modules/"
done
python3 -I "$here/mkcpio.py" "$root" | gzip -9n > "$tmp/initramfs.img"
echo "   $(wc -c < "$tmp/initramfs.img") octets"

echo "== DTB (écran simple-framebuffer, UFS vérifié désactivé)"
"$repo/scripts/build-dtb.sh" "$tmp/apk/boot/dtbs/qcom/sdm845-sony-xperia-tama-akatsuki.dtb" \
	"$tmp/akatsuki.dtb" >/dev/null

echo "== boot.img"
"$repo/scripts/make-bootimg.sh" "$tmp/apk/boot/vmlinuz" "$tmp/akatsuki.dtb" \
	"$tmp/initramfs.img" "$out" \
	"console=tty0 console=ttyMSM0,115200 clk_ignore_unused pd_ignore_unused"
echo
echo "Prêt : $out  →  fastboot boot $out"
