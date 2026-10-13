# Installer Arch Linux ARM sur un Xperia XZ3 sous LineageOS, pas à pas

Ce guide part d'un **Xperia XZ3 (akatsuki) au bootloader déverrouillé, avec LineageOS
installé** (slot A), et arrive à Arch Linux ARM + Plasma Mobile sur la carte micro-SD,
démarré depuis le slot B. LineageOS reste intact : on peut y revenir à tout moment.

Durée : une demi-journée. Les commandes sont à lancer **depuis une copie du dépôt**,
sur le PC (Linux) ou sur le téléphone, comme indiqué à chaque étape.

> ⚠️ **Ne jamais activer l'UFS** (voir le [README](../README.md)) : un DTB qui l'active
> efface la mémoire interne, bootloader compris, sans retour possible. Toutes les images
> de ce dépôt passent par le garde-fou `scripts/check-dtb-ufs.sh`. Ne flasher que des
> images construites par les scripts du dépôt.

> 🔒 **Données personnelles** : l'EFS (IMEI), la TA, les firmwares et blobs Sony et les
> images contenant vos adresses MAC ne doivent **jamais** être publiés (les dossiers
> correspondants sont ignorés par git). Gardez-en une copie sur le PC.

## Vue d'ensemble

| Étape | Où | Quoi |
|---|---|---|
| 1 | LineageOS → PC | Sauvegarder firmwares, EFS, TA et blobs Sony |
| 2 | PC | Préparer la carte micro-SD |
| 3 | PC → téléphone | Premier démarrage d'Arch (SSH par USB) |
| 4 | PC | Compiler les modules (écran, tactile, caméra, Bluetooth) |
| 5 | Téléphone | Modem, Wi-Fi, SIM |
| 6 | PC → téléphone | Image complète (écran, son, caméra, capteurs…) |
| 7 | Téléphone | Plasma Mobile et applications |
| 8 | Téléphone | Son, appels, Bluetooth, capteurs, horloge, réglages |

## Ce qu'il faut

- **PC Linux** avec : `adb`, `fastboot`, `git`, `python3`, `sfdisk`, `mkfs.ext4`,
  `mkfs.exfat` (`exfatprogs`), `bsdtar` (`libarchive`), `dtc`, `mkbootimg`, `clang` +
  `lld` (LLVM 22), `curl`, `gpg`, `zstd`, `kmod`.
- **Carte micro-SD** de 16 Go ou plus (elle sera **entièrement effacée**). Une carte
  rapide (A2, U3) rend le téléphone nettement plus réactif : tout le système est dessus.
- Le paquet noyau postmarketOS **`linux-postmarketos-qcom-sdm845-7.1_rc1-r4.apk`**
  (`scripts/fetch-pmos-kernel.sh` le trouve et le télécharge).
- Le dépôt : `git clone https://github.com/rakhenmanoa/alarm-sony-akatsuki.git`

## 1. Sous LineageOS : sauvegarder ce qui est propre au téléphone

Activer **Options pour les développeurs → Débogage USB** et **Débogage root**, brancher
le téléphone, puis sur le PC :

```sh
scripts/extraire-firmwares-adb.sh   # firmwares Sony (modem, DSP, GPU, Wi-Fi, SLPI…) → firmware-akatsuki/
scripts/copier-efs-adb.sh           # données du modem (IMEI, calibration) → efs-akatsuki/
scripts/copier-ta-adb.sh            # partition TA (SIM Sony, adresses MAC) → ta-akatsuki/
scripts/sauver-blobs-adb.sh         # Bluetooth, configuration des capteurs… → blobs-akatsuki/
```

Tous ces scripts **lisent seulement** le téléphone. Ils rangent leur résultat sur le PC
et, pour les trois premiers, en copie sur la partition d'échange de la carte (une fois
celle-ci préparée : on peut les relancer après l'étape 2).

## 2. Sur le PC : préparer la carte micro-SD

Télécharger et vérifier Arch Linux ARM (aarch64 générique) :

```sh
curl -LO http://os.archlinuxarm.org/os/ArchLinuxARM-aarch64-latest.tar.gz
curl -LO http://os.archlinuxarm.org/os/ArchLinuxARM-aarch64-latest.tar.gz.sig
gpg --keyserver keyserver.ubuntu.com --recv-keys 68B3537F39A313B3E574D06777193F152BDBE6A6
gpg --verify ArchLinuxARM-aarch64-latest.tar.gz.sig     # « Good signature »
```

Carte dans le PC (repérer son nom avec `lsblk` avant et après l'avoir branchée) :

```sh
sudo scripts/prepare-sdcard.sh /dev/sdX ArchLinuxARM-aarch64-latest.tar.gz \
    linux-postmarketos-qcom-sdm845-7.1_rc1-r4.apk
```

Ou carte **dans le téléphone**, LineageOS démarré (adb root) :
`scripts/prepare-sdcard-adb.sh ArchLinuxARM-aarch64-latest.tar.gz linux-postmarketos-qcom-sdm845-7.1_rc1-r4.apk`.

La carte contient ensuite Arch (ext4, invisible pour Android) et une partition
d'échange exFAT de 8 Go (`/mnt/partage` sous Arch, carte SD normale sous Android ;
`PARTAGE=16G` pour changer la taille). Détails : [premier-demarrage.md](premier-demarrage.md).

Relancer au besoin les scripts de l'étape 1 pour copier firmwares, EFS et TA sur la
partition d'échange.

## 3. Premier démarrage d'Arch

Construire une première image (noyau pmOS **sans verrouillage**, pour accepter nos
modules plus tard) :

```sh
SANS_VERROU=1 test-boot/build.sh linux-postmarketos-qcom-sdm845-7.1_rc1-r4.apk boot-arch.img
```

Carte SD dans le téléphone. Téléphone éteint : **Volume haut + câble USB** (LED bleue),
puis :

```sh
fastboot getvar current-slot        # doit répondre « a » (LineageOS)
fastboot flash boot_b boot-arch.img
fastboot erase dtbo_b               # obligatoire : sinon le bootloader abîme le DTB
fastboot --set-active=b
fastboot reboot
```

Attendre 1 à 2 minutes (premier démarrage), puis se connecter par le câble USB :

```sh
ssh alarm@172.16.42.1               # mot de passe : alarm
su -                                # mot de passe : root
passwd; passwd alarm                # changer les deux mots de passe
date -s "2026-10-13 08:00"          # mettre la date du jour
```

Internet par le câble (sur le PC) : `sudo scripts/partage-internet-pc.sh start`. Puis
sur le téléphone, en root :

```sh
grep -q '^DisableSandbox' /etc/pacman.conf || sed -i '/^\[options\]/a DisableSandbox' /etc/pacman.conf
pacman-key --init && pacman-key --populate archlinuxarm
pacman -Syu
pacman -S --needed git python linux-firmware-qcom wireless-regdb zstd base-devel
git clone https://github.com/rakhenmanoa/alarm-sony-akatsuki.git /root/alarm-sony-akatsuki
```

Récupérer la configuration du noyau pour l'étape 4 (sur le PC) :

```sh
ssh alarm@172.16.42.1 'zcat /proc/config.gz' > config-akatsuki
```

Si le PC ne reçoit pas d'adresse : `sudo ip addr add 172.16.42.2/24 dev <interface>`.
Si `http://172.16.42.1/` affiche un journal du noyau, c'est le **mode secours** :
la carte n'a pas été trouvée ou Arch n'a pas pu démarrer (voir
[premier-demarrage.md](premier-demarrage.md)).

## 4. Sur le PC : compiler les modules manquants

Le noyau pmOS n'a pas les pilotes de l'écran et du tactile du XZ3, et ceux de la caméra
et du Bluetooth demandent des correctifs. On les compile pour ce noyau exact :

```sh
scripts/preparer-arbre-noyau.sh config-akatsuki noyau-7.1-rc1
noyau-7.1-rc1/construire-module.sh modules/panel-lgd-lh599qh3-edb1   # écran
noyau-7.1-rc1/construire-module.sh modules/atmel_mxt_ts              # tactile
noyau-7.1-rc1/construire-module.sh modules/imx258                    # caméra avant
```

Bluetooth (`btqca.ko`, `hci_uart.ko`) : suivre [modules/bt-qca/README.md](../modules/bt-qca/README.md)
(copie des sources du noyau + correctif).

Copier les `.ko` sur le téléphone et les installer (root) :

```sh
scp modules/*/*.ko <dossier-bt>/btqca.ko <dossier-bt>/hci_uart.ko alarm@172.16.42.1:/tmp/   # PC
M=/usr/lib/modules/$(uname -r)                                                            # téléphone
install -D -m 644 /tmp/panel-lgd-lh599qh3-edb1.ko /tmp/atmel_mxt_ts.ko /tmp/imx258.ko -t $M/updates/
depmod -a
```

(`btqca.ko` et `hci_uart.ko` sont installés à l'étape 8 par `installer-bluetooth.sh`.)

## 5. Sur le téléphone : modem, Wi-Fi et SIM

En root, internet par USB actif :

```sh
cd /root/alarm-sony-akatsuki
sh scripts/installer-outils-modem.sh                        # qrtr, rmtfs, tqftpserv
install -d -m 700 /var/lib/rmtfs
install -m 600 /mnt/partage/efs-akatsuki/modem_fs* /var/lib/rmtfs/
install -d -m 700 /var/lib/miscta
install -m 600 /mnt/partage/ta.img /var/lib/miscta/
cp -a /mnt/partage/firmware-akatsuki /root/fw-essai         # firmwares Sony
cp -a /root/fw-essai/updates /usr/lib/firmware/             # réglages Wi-Fi Sony (board-2.bin)
cp -a /root/fw-essai/qca /usr/lib/firmware/                 # réglages Bluetooth (crnv21.bin)
sh scripts/installer-demarrage-auto.sh                      # firmwares validés, Wi-Fi corrigé, services
```

Puis supprimer les copies de la partition d'échange, qui est lisible par Android et
par n'importe quel PC : `rm -r /mnt/partage/efs-akatsuki /mnt/partage/ta.img`.

Relever les adresses MAC d'origine pour l'étape 6 :

```sh
python3 scripts/ta-mac.py /var/lib/miscta/ta.img      # → WLAN_MAC=… BT_MAC=…
```

Détails, essais et dépannage : [modem-wifi.md](modem-wifi.md).

## 6. Image complète

Sur le PC, avec les adresses relevées (elles ne sont écrites que dans l'image, jamais
dans le dépôt) :

```sh
WLAN_MAC=xx:xx:xx:xx:xx:xx BT_MAC=xx:xx:xx:xx:xx:xx \
ECRAN=dsi AUDIO=1 CAMERA=1 VIBREUR=1 FLASH=1 CAPTEURS=1 SANS_VERROU=1 \
  test-boot/build.sh linux-postmarketos-qcom-sdm845-7.1_rc1-r4.apk boot-akatsuki.img
```

| Option | Ajoute |
|---|---|
| `ECRAN=dsi` | vrai écran (panneau LGD) et tactile |
| `AUDIO=1` | codec, haut-parleurs, micro, voix des appels |
| `CAMERA=1` | caméra avant (IMX258) |
| `VIBREUR=1` | vibreur et Bluetooth (UART à 4 fils) |
| `FLASH=1` | flash / lampe de poche et LED de notification |
| `CAPTEURS=1` | SLPI (accéléromètre, lumière, proximité, boussole) |
| `SANS_VERROU=1` | noyau sans verrouillage (modules corrigés acceptés) |

Le garde-fou UFS est appliqué à la construction. **Image personnelle** (adresses MAC) :
ne pas la partager. Essai sans risque, puis installation :

```sh
fastboot boot boot-akatsuki.img          # essai : rien n'est écrit
fastboot flash boot_b boot-akatsuki.img  # une fois l'essai réussi
```

## 7. Plasma Mobile

En root sur le téléphone :

```sh
pacman -S --needed mesa plasma-mobile plasma-pa kscreen konsole sddm qt6-wayland plasma-keyboard hunspell-fr
mkdir -p /etc/sddm.conf.d
cat > /etc/sddm.conf.d/autologin.conf <<'EOF'
[Autologin]
User=alarm
Session=plasma-mobile

[General]
DisplayServer=wayland
EOF
cd /root/alarm-sony-akatsuki
sh scripts/installer-plasma-mobile.sh          # composants et applications KDE mobiles
sh scripts/installer-networkmanager.sh internet  # Wi-Fi et données mobiles dans Plasma (APN en argument)
sh scripts/installer-zram.sh                   # mémoire compressée, langue française
sh scripts/installer-demarrage-arret.sh        # arrêts et démarrages plus fiables
systemctl enable --now sddm
```

Échelle de l'écran, en tant qu'`alarm` en SSH :

```sh
export WAYLAND_DISPLAY=wayland-0 XDG_RUNTIME_DIR=/run/user/1000
kscreen-doctor output.DSI-1.scale.3
```

Applications d'appel et de SMS (AUR, en tant qu'`alarm`) : installer
[yay](https://aur.archlinux.org/packages/yay), puis `yay -S plasma-dialer spacebar`.
Caméra : `pacman -S --needed plasma-camera` (libcamera).

`linux-aarch64` (installé par `pacman -Syu`) ne sert pas : le téléphone démarre sur le
noyau du `boot.img`. On peut le retirer : `pacman -Rns linux-aarch64`.

## 8. Son, appels, Bluetooth, capteurs et réglages

En root, depuis `/root/alarm-sony-akatsuki` :

```sh
sh scripts/installer-audio.sh                  # profil son, réglage PipeWire, son des appels

# Bluetooth : firmware de Sony (sauvé à l'étape 1) + modules de l'étape 4
SONY_FW=/chemin/vers/blobs-akatsuki/bt_firmware/…/crbtfw21.tlv KO=/tmp \
  sh scripts/installer-bluetooth.sh

# Capteurs : firmware du SLPI, puis config et étalonnage Sony
install -D -m 644 /root/fw-essai/qcom/sdm845/Sony/tama/slpi.mbn \
  /usr/lib/firmware/qcom/sdm845/Sony/tama/slpi.mbn
# en tant qu'alarm (yay refuse root) : yay -S hexagonrpcd
BLOBS=/chemin/vers/blobs-akatsuki sh scripts/installer-capteurs.sh

sh scripts/installer-horloge.sh                # heure juste au démarrage (l'heure doit être juste à ce moment)
sh scripts/installer-reactivite.sh             # processeur, GPU et carte SD plus réactifs
install -m 644 rootfs/etc/udev/rules.d/90-akatsuki-lampe.rules /etc/udev/rules.d/   # lampe de poche dans Plasma
reboot
```

Copier les dossiers `bt_firmware`, `dsp`, `etc-sensors` et `persist-sensors` de
`blobs-akatsuki` du PC vers le téléphone (`scp -r` ou `tar … | ssh …`), et les
supprimer du téléphone une fois installés.

## Vérifier

| Fonction | Commande ou essai |
|---|---|
| Wi-Fi, données | panneau réseau de Plasma ; `nmcli` |
| SIM, SMS, appels | `mmcli -m any` ; Spacebar, plasma-dialer |
| Son | lecture dans Plasma ; son pendant un appel |
| Bluetooth | `bluetoothctl show` → `Powered: yes` et la vraie adresse |
| Capteurs, rotation | `monitor-sensor` ; rotation automatique dans Plasma |
| Caméra avant | `cam -l` ; plasma-camera |
| Lampe, LED | tuile « Lampe de poche » ; `/sys/class/leds/rgb:status` |
| Horloge | éteindre, attendre, rallumer sans réseau : l'heure doit être juste |

État détaillé de chaque fonction : tableau du [README](../README.md#état).

## Revenir à LineageOS

Extinction forcée (**Power + Volume haut** jusqu'à 3 vibrations), puis **Volume haut +
câble** (LED bleue) :

```sh
fastboot --set-active=a && fastboot reboot
```

Pour revenir à Arch : `fastboot --set-active=b && fastboot reboot`. Le slot B garde
l'image d'Arch tant qu'on ne le réécrit pas ; la carte SD reste lisible sous Android
seulement pour sa partition d'échange (ne **jamais** formater la carte depuis Android).
