# Arch sur le XZ3 : premiers pas (11/10/2026)

État au premier démarrage d'Arch depuis la carte SD : système sain (`systemctl --failed`
vide), 58 Go sur `/`, SSH par USB, chargeur `pmi8998-charger` détecté.

## Partition d'échange

`/mnt/partage` (partition 2 de la carte, exFAT, 8 Gio par défaut, réglable avec `PARTAGE`) est lisible depuis Arch, depuis
LineageOS (comme carte SD) et depuis un PC. Elle est montée à la première utilisation.
(Cartes préparées après le 11/10/2026 ; une carte plus ancienne n'a qu'une partition.)

## Se connecter

```sh
ssh-keygen -R 172.16.42.1     # si une ancienne clé pour cette adresse existe
ssh alarm@172.16.42.1         # alarm / alarm, puis « su - » (root / root)
passwd; passwd alarm          # changer les deux mots de passe
```

## Internet par le câble USB (partage de connexion du PC)

Le téléphone (172.16.42.1) donne au PC l'adresse **172.16.42.2** et l'utilise comme
passerelle ; le PC traduit les adresses vers sa propre connexion.

**1. Mettre à jour la configuration réseau du téléphone** (une fois ; depuis le dépôt
sur le PC, après `git pull`) :

```sh
scp rootfs/etc/systemd/network/50-usb0.network rootfs/usr/local/bin/akatsuki-usb-gadget alarm@172.16.42.1:/tmp/
ssh alarm@172.16.42.1
su -
install -m 644 /tmp/50-usb0.network /etc/systemd/network/50-usb0.network
install -m 755 /tmp/akatsuki-usb-gadget /usr/local/bin/akatsuki-usb-gadget
reboot
```

(Une carte préparée avec une version récente des scripts a déjà ces fichiers.)

**2. Sur le PC**, téléphone redémarré et connecté :

```sh
sudo scripts/partage-internet-pc.sh start
```

**3. Sur le téléphone** (root) :

```sh
ping -c3 1.1.1.1                       # la route fonctionne ?
ls -l /etc/resolv.conf                 # lien vers systemd-resolved ?
# si ce n'est pas un lien vers /run/systemd/resolve/… :
echo 'nameserver 1.1.1.1' > /etc/resolv.conf
ping -c3 archlinuxarm.org              # les noms fonctionnent ?
timedatectl set-ntp true               # mettre l'horloge à l'heure
```

## Mettre à jour et ajouter les firmwares génériques

Le noyau pmOS est compilé sans Landlock, que le bac à sable de téléchargement de
pacman 7 exige (« Landlock is not supported by the kernel », « failed to synchronize
all databases ») : désactiver ce bac à sable (déjà fait sur les cartes préparées après
le 11/10/2026). Les signatures des paquets restent vérifiées.

```sh
grep -q '^DisableSandbox' /etc/pacman.conf || sed -i '/^\[options\]/a DisableSandbox' /etc/pacman.conf
pacman-key --init && pacman-key --populate archlinuxarm
pacman -Syu
pacman -S linux-firmware-qcom wireless-regdb
```

⚠️ `pacman -Syu` peut installer le paquet noyau générique d'Arch Linux ARM
(`linux-aarch64`) et son initramfs dans `/boot` : **sans effet** sur le démarrage,
qui utilise le noyau pmOS du `boot.img` (slot B). Les modules du noyau pmOS sont dans
`/usr/lib/modules/7.1.0-rc1-sdm845` et ne sont pas touchés.

## Firmwares propres au téléphone

Signés par Qualcomm/Sony pour ce modèle, absents de `linux-firmware`, mais **déjà
présents dans le téléphone** (partitions `modem`, `bluetooth`, `vendor` de LineageOS).
Android les range découpés (`.mdt` + `.b00`, `.b01`…) ; le noyau mainline attend un
fichier `.mbn` d'un seul tenant : [`scripts/pil-squasher.py`](../scripts/pil-squasher.py)
les recolle (même principe que l'outil `pil-squasher` de Linaro).

**1. Sous LineageOS** (« Débogage root » activé), sur le PC depuis le dépôt :

```sh
scripts/extraire-firmwares-adb.sh
```

Lecture seule côté téléphone. Résultat dans `firmware-akatsuki/` sur le PC (ignoré par
git : ces fichiers ne doivent pas être publiés) et copie sur la partition d'échange de
la carte SD.

**2. Sous Arch** (root) :

```sh
cp -a /mnt/partage/firmware-akatsuki/. /usr/lib/firmware/
reboot
```

| Fichier | Rôle | Utilisé par le DTB actuel |
|---|---|---|
| `qcom/sdm845/Sony/tama/adsp.mbn` | processeur audio et capteurs | oui |
| `qcom/sdm845/Sony/tama/cdsp.mbn` | processeur de calcul | oui |
| `qcom/sdm845/Sony/tama/venus.mbn` | vidéo | oui — ⚠️ fait redémarrer le téléphone, ne pas installer |
| `qcom/sdm845/Sony/tama/a630_zap.mbn` | GPU | oui |
| `qca/Sony/tama/crnv21.bin` | réglages Bluetooth | oui |
| `mba.mbn`, `modem.mbn`, `wlanmdsp.mbn` | modem, Wi-Fi | à partir de `boot-arch-modem.img` : voir [modem-wifi.md](modem-wifi.md) |
| `slpi.mbn`, `ipa_fws.mbn` | capteurs, réseau du modem | pas encore |

Après redémarrage, vérifier :

```sh
cat /sys/class/remoteproc/*/name /sys/class/remoteproc/*/state
dmesg | grep -iE 'remoteproc|venus|zap|bluetooth|firmware'
```

### ⚠️ Redémarrage en boucle avec les firmwares (11/10/2026)

Premier essai : après la copie des firmwares dans `/usr/lib/firmware`, le téléphone
redémarre environ 2 s après le début du chargement des pilotes, sans message.
Cause probable : les réserves CMA et « fastrpc » du DTB pmOS recouvrent deux zones de
RAM protégées par TrustZone sur Sony Tama (rmtfs à `0xfdc01000`, debug à
`0xffb00000`) ; corrigé par [`dts/akatsuki-memoire-sony.dtsi`](../dts/akatsuki-memoire-sony.dtsi)
(boot.img reconstruit). À confirmer sur le téléphone.

**Sortir de la boucle** (LineageOS, `adb root`) : monter la partition d'Arch et mettre
les firmwares hors du chemin de recherche du noyau :

```sh
adb shell "mkdir -p /data/local/tmp/arch && mount -t ext4 /dev/block/mmcblk0p1 /data/local/tmp/arch"
adb shell "mv /data/local/tmp/arch/usr/lib/firmware/qcom/sdm845/Sony /data/local/tmp/arch/root/firmwares-sony-desactives"
adb shell "umount /data/local/tmp/arch"
```

**Essayer sans risque de boucle** : laisser les firmwares hors de `/usr/lib/firmware`
et ne les rendre visibles au noyau que pour la session en cours
(`/sys/module/firmware_class/parameters/path`, effacé au redémarrage). Si un
coprocesseur fait planter le téléphone, il redémarre normalement.

```sh
mkdir -p /root/fw-essai/qcom/sdm845
mv /root/firmwares-sony-desactives /root/fw-essai/qcom/sdm845/Sony
echo -n /root/fw-essai > /sys/module/firmware_class/parameters/path
# dans une 2e session SSH : dmesg -w
grep . /sys/class/remoteproc/*/name          # repérer adsp, cdsp…
echo start > /sys/class/remoteproc/remoteprocN/state
```

**Résultats du 11/10/2026** (DTB avec `akatsuki-memoire-sony.dtsi`) :

| Coprocesseur | Démarrage manuel | Remarque |
|---|---|---|
| ADSP (`remoteproc0`) | ✅ `remote processor adsp is now up` | services audio APR présents ; carte son pas encore décrite dans le DTB (`No dais found in DT`) |
| CDSP (`remoteproc1`, `remoteproc2` avec le modem activé) | ✅ `remote processor cdsp is now up` | 8 canaux de calcul fastrpc |
| Venus (vidéo) | ❌ redémarrage instantané | aucune trace (pas même la ligne `non legacy binding` dans le journal persistant) : coupure par TrustZone ou blocage matériel, cause à chercher |
| GPU (`a630_zap.mbn`) | pas encore testé | |

N'installer pour de bon que ce qui est validé :

```sh
mkdir -p /usr/lib/firmware/qcom/sdm845/Sony/tama
cp /root/fw-essai/qcom/sdm845/Sony/tama/adsp.mbn /root/fw-essai/qcom/sdm845/Sony/tama/cdsp.mbn \
   /usr/lib/firmware/qcom/sdm845/Sony/tama/
```

**Ne pas** mettre `venus.mbn` dans `/usr/lib/firmware` : le pilote le chargerait à
chaque démarrage et le téléphone redémarrerait en boucle.

## Batterie (11/10/2026)

Avec la jauge activée dans le DTB (`fuel-gauge@4000`), `/sys/class/power_supply/`
contient `pmi8998-charger` et `qcom-battery` :

```sh
cat /sys/class/power_supply/qcom-battery/capacity      # pourcentage
cat /sys/class/power_supply/qcom-battery/voltage_now   # µV
cat /sys/class/power_supply/qcom-battery/temp          # dixièmes de °C
```

Premier relevé : 99 %, 4,252 V, −2,4 mA (fin de charge), 32 °C ; chargeur en USB
standard (SDP, 500 mA max), santé « Good ».

## Son (12/10/2026, essai)

Matériel relevé sous LineageOS (`scripts/releve-audio-adb.sh`) : codec **WCD9340**
sur le SLIMbus de l'ADSP, deux amplis **WSA8815** sur le SoundWire du codec (pas
d'ampli sur I2C), micros numériques DMIC0 et DMIC3, pas de prise jack (casque par
l'USB-C). Même matériel que le Lenovo Yoga C630 : [`dts/akatsuki-audio.dtsi`](../dts/akatsuki-audio.dtsi)
reprend sa description. Image : `ECRAN=dsi AUDIO=1 SANS_VERROU=1 test-boot/build.sh …`.
Essai des haut-parleurs : [`scripts/audio-essai.sh`](../scripts/audio-essai.sh).

**Validé le 12/10/2026 : les haut-parleurs fonctionnent** (`audio-essai.sh`). Profil UCM
pour PipeWire et Plasma : `scripts/installer-audio.sh`.

**Son dans Plasma (Firefox) validé le 12/10/2026.** Deux réglages nécessaires
(`installer-audio.sh`) :
- profil UCM `Sony/akatsuki` (chargé par le nom de carte `Sony-Xperia-XZ3`) ;
- WirePlumber `51-akatsuki-q6asm.conf` : périodes de 1024 × 4, 16 bits, sans minuterie.
  Sans lui : `q6asm-dai … Error queuing playback buffer -16` — chaque période part vers
  l'ADSP par glink, qui n'a qu'un petit nombre de tampons réservés (« intents ») ; avec
  les petites périodes de PipeWire, ils sont épuisés (`-EBUSY`) et le son est haché.
