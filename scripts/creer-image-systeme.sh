#!/bin/sh
# creer-image-systeme.sh — Fabrique, à partir de la carte micro-SD d'un XZ3 qui
# fonctionne (système de référence), l'archive du système à publier dans les
# Releases : tout ce qui est propre au téléphone ou à son propriétaire est retiré.
#
# Usage (sur le PC, en root, carte dans le lecteur, NON montée) :
#   sudo scripts/creer-image-systeme.sh /dev/sdX1 [sortie]   (défaut : akatsuki-systeme-AAAAMMJJ)
#   IMEI=35… (facultatif) : vérifie aussi que l'IMEI n'apparaît nulle part.
#
# Retiré : EFS, TA et écritures du modem, firmwares et fichiers Sony, configuration
# des capteurs, réglage MAC, mots de passe Wi-Fi et connexions, appairages Bluetooth,
# clés SSH, trousseau pacman, identifiant de machine, journaux, caches, /root, et le
# dossier personnel d'alarm (SMS, appels, navigateur…) sauf l'échelle de l'écran.
# Mots de passe remis à alarm/alarm et root/root.
#
# Vérifications avant de produire l'archive (échec = rien n'est produit) : aucun
# fichier Sony connu, aucune trace des adresses MAC du téléphone (lues dans sa TA),
# ni de l'IMEI si donné.
#
# Prérequis sur le PC : rsync, zstd, openssl, python3. Place libre : ~2 × le système.
set -eu
die() { echo "Erreur : $*" >&2; exit 1; }
[ "$(id -u)" -eq 0 ] || die "lancer en root (sudo)."
[ $# -ge 1 ] || die "usage : $0 /dev/sdX1 [sortie]"
part="$1"; sortie="${2:-akatsuki-systeme-$(date +%Y%m%d)}"
here="$(cd "$(dirname "$0")" && pwd)"
for c in rsync zstd openssl python3 tar; do command -v $c >/dev/null || die "$c manquant."; done
[ -b "$part" ] || die "$part n'est pas un périphérique bloc."
findmnt -S "$part" >/dev/null && die "$part est monté : le démonter d'abord."

mnt=$(mktemp -d); st=$(mktemp -d -p "$(pwd)" .systeme.XXXX)
nettoyer() { umount "$mnt" 2>/dev/null || true; rmdir "$mnt" 2>/dev/null || true; rm -rf "$st"; }
trap nettoyer EXIT
mount -o ro "$part" "$mnt"
[ -x "$mnt/usr/local/bin/akatsuki-perso" ] || \
	die "akatsuki-perso absent : lancer d'abord scripts/installer-image-generique.sh sur le téléphone."

# Adresses MAC du téléphone, pour vérifier qu'elles ne fuient pas
macs=""
if [ -f "$mnt/var/lib/miscta/ta.img" ]; then
	macs=$(python3 -I "$here/ta-mac.py" "$mnt/var/lib/miscta/ta.img" | tr ' ' '\n' | sed -n 's/^[A-Z_]*=//p')
fi

echo "== Copie du système (sans les données personnelles)"
rsync -aHAX --numeric-ids \
	--exclude=/lost+found --exclude='/mnt/partage/*' --exclude='/tmp/*' --exclude='/var/tmp/*' \
	--exclude='/proc/*' --exclude='/sys/*' --exclude='/dev/*' --exclude='/run/*' \
	--exclude='/root/*' --exclude='/home/*' \
	--exclude='/var/lib/rmtfs/*' --exclude='/var/lib/miscta/*' --exclude='/var/lib/akatsuki/*' \
	--exclude=/usr/lib/firmware/qcom/sdm845/Sony --exclude=/usr/lib/firmware/qca/Sony \
	--exclude=/usr/lib/firmware/updates --exclude=/usr/share/qcom \
	--exclude=/etc/systemd/network/10-akatsuki-wlan.link --exclude=/etc/modprobe.d/bt-debug.conf \
	--exclude='/etc/NetworkManager/system-connections/*' --exclude='/var/lib/NetworkManager/*' \
	--exclude='/var/lib/iwd/*' --exclude='/var/lib/bluetooth/*' --exclude='/var/lib/ModemManager/*' \
	--exclude='/etc/ssh/ssh_host_*' --exclude=/etc/pacman.d/gnupg \
	--exclude=/var/lib/systemd/random-seed --exclude='/var/lib/systemd/timesync/*' \
	--exclude='/var/lib/systemd/coredump/*' --exclude='/var/log/*' \
	--exclude='/var/cache/pacman/pkg/*' --exclude='/var/spool/*' \
	--exclude='*.bash_history' --exclude='/var/lib/sddm/.local/*' \
	"$mnt"/ "$st"/

echo "== Nettoyage"
: > "$st/etc/machine-id"
install -d -m 700 "$st/root"
install -d -m 700 -o 1000 -g 1000 "$st/home/alarm"
cp -a "$st/etc/skel/." "$st/home/alarm/" 2>/dev/null || true
k="home/alarm/.config/kwinoutputconfig.json"
[ -f "$mnt/$k" ] && install -D -m 644 -o 1000 -g 1000 "$mnt/$k" "$st/$k" && echo "   échelle de l'écran conservée"
chown -R 1000:1000 "$st/home/alarm"
hr=$(openssl passwd -6 root); ha=$(openssl passwd -6 alarm)
awk -F: -v OFS=: -v hr="$hr" -v ha="$ha" '$1=="root"{$2=hr} $1=="alarm"{$2=ha} {print}' \
	"$st/etc/shadow" > "$st/etc/shadow.new" && cat "$st/etc/shadow.new" > "$st/etc/shadow" && rm "$st/etc/shadow.new"
echo "   mots de passe : alarm/alarm, root/root ; identifiant de machine vidé"

echo "== Vérifications"
interdits=$(cd "$st" && find . \( -path ./proc -o -path ./sys \) -prune -o \( \
	-name 'modem_fs*' -o -name ta.img -o -path '*Sony*' -o -name 'sns_reg.conf' -o -name 'bdwlan*' \
	-o -name '*.psk' -o -name '*.nmconnection' -o -name 'ssh_host_*' -o -name '10-akatsuki-wlan.link' \) -print)
[ -z "$interdits" ] || die "fichiers propres au téléphone encore présents :
$interdits"
echo "   aucun fichier Sony, EFS, TA, clé ou mot de passe Wi-Fi"
python3 -I - "$st" ${IMEI:-} $macs <<'PY' || die "trace personnelle trouvée (voir ci-dessus) : archive NON produite."
import os, sys
racine, motifs = sys.argv[1], []
for v in sys.argv[2:]:
    if ":" in v:
        b = bytes.fromhex(v.replace(":", ""))
        motifs += [v.lower().encode(), v.upper().encode(), v.replace(":", "").lower().encode(), b, b[::-1]]
    elif v:
        motifs.append(v.encode())
if not motifs:
    print("   (pas de TA ni d'IMEI : vérification des adresses sautée)"); sys.exit(0)
trouve = 0
for d, _, fichiers in os.walk(racine):
    for f in fichiers:
        p = os.path.join(d, f)
        if os.path.islink(p) or not os.path.isfile(p) or os.path.getsize(p) > 64 << 20:
            continue
        with open(p, "rb") as h:
            data = h.read()
        for m in motifs:
            if m in data:
                print("   TROUVÉ dans", os.path.relpath(p, racine)); trouve = 1; break
sys.exit(trouve)
PY
echo "   aucune trace des adresses MAC${IMEI:+ ni de l'IMEI}"

echo "== Archive $sortie.tar.zst (plusieurs minutes)"
tar --numeric-owner --xattrs --acls -C "$st" -cf - . | zstd -T0 -19 -q -o "$sortie.tar.zst"
# GitHub refuse les fichiers de plus de 2 Gio dans une release : découpage si besoin
taille=$(stat -c %s "$sortie.tar.zst")
if [ "$taille" -gt 2000000000 ]; then
	split -b 1900M -d "$sortie.tar.zst" "$sortie.tar.zst.part"
	rm "$sortie.tar.zst"
	sha256sum "$sortie.tar.zst.part"* > "$sortie.sha256"
	echo "Découpée en $(ls "$sortie".tar.zst.part* | wc -l) morceaux (recoller : cat $sortie.tar.zst.part* > $sortie.tar.zst)"
else
	sha256sum "$sortie.tar.zst" > "$sortie.sha256"
fi
cat "$sortie.sha256"
echo "Terminé."
