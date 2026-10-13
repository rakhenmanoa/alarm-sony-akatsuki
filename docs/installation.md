# Installer Arch Linux ARM sur un Xperia XZ3 en 4 étapes

Pour un **Xperia XZ3 (akatsuki) au bootloader déverrouillé, sous LineageOS** (slot A).
Arch Linux ARM + Plasma Mobile s'installe sur la carte micro-SD et démarre depuis le
slot B ; LineageOS reste intact.

| Étape | Où | Script |
|---|---|---|
| 1. Copier les firmwares et fichiers de LineageOS | PC + téléphone sous LineageOS | `scripts/1-copier-los.sh` |
| 2. Patcher le noyau pmOS et préparer la carte SD | PC | `scripts/2-preparer-carte.sh` |
| 3. Flasher le noyau | PC + téléphone en fastboot | `scripts/3-flasher.sh` |
| 4. Installer le reste du système depuis internet | téléphone sous Arch | `scripts/4-installer-systeme.sh` |

> ⚠️ **Ne jamais activer l'UFS** (voir le [README](../README.md)) : un DTB qui l'active
> efface la mémoire interne, bootloader compris. Les étapes 2 et 3 appliquent le
> garde-fou `check-dtb-ufs.sh` ; ne flasher que des images construites par le dépôt.

> 🔒 Le dossier `akatsuki-perso/` créé à l'étape 1 contient l'**IMEI** (EFS) et des
> fichiers Sony : le garder en sauvegarde, ne **jamais** le publier.

## Ce qu'il faut

- **PC Linux** avec : `adb`, `fastboot`, `git`, `python3`, `sfdisk`, `mkfs.ext4`,
  `mkfs.exfat` (`exfatprogs`), `bsdtar` (`libarchive`), `dtc`, `mkbootimg`, `clang` +
  `lld`, `kmod`, `curl`, `gpg`.
- **Carte micro-SD** de 16 Go ou plus (**entièrement effacée**), rapide de préférence
  (A2/U3 : tout le système est dessus).
- Le dépôt : `git clone https://github.com/rakhenmanoa/alarm-sony-akatsuki.git && cd alarm-sony-akatsuki`

## 1. Copier les firmwares et fichiers de LineageOS

Sous LineageOS : **Options pour les développeurs → Débogage USB** et **Débogage root**.
Brancher le téléphone, puis sur le PC :

```sh
scripts/1-copier-los.sh
```

Lecture seule côté téléphone. Résultat dans `akatsuki-perso/` : firmwares Sony
(modem, DSP, GPU, Wi-Fi, capteurs), EFS du modem, partition TA (SIM Sony, adresses
MAC), Bluetooth et configuration des capteurs.

À la fin, le script ouvre l'appareil photo de LineageOS : prendre **une** photo avec la
caméra arrière, fermer l'application, appuyer sur Entrée. Il enregistre ainsi les
réglages du capteur arrière (`imx400-akatsuki.bin`, sans lequel la caméra arrière
n'est pas activée). `SANS_CAMERA=1` pour sauter cette étape.

## 2. Patcher le noyau pmOS et préparer la carte SD

Télécharger Arch Linux ARM et le noyau postmarketOS. Les modules précompilés et les
correctifs du dépôt valent pour **`linux-postmarketos-qcom-sdm845-7.1_rc1-r4.apk`**
exactement (SHA-256 `d0b4b950…9804`) : le prendre dans les **Releases** du dépôt
(postmarketOS ne garde que sa dernière version).

```sh
curl -LO http://os.archlinuxarm.org/os/ArchLinuxARM-aarch64-latest.tar.gz
curl -LO http://os.archlinuxarm.org/os/ArchLinuxARM-aarch64-latest.tar.gz.sig
gpg --keyserver keyserver.ubuntu.com --recv-keys 68B3537F39A313B3E574D06777193F152BDBE6A6
gpg --verify ArchLinuxARM-aarch64-latest.tar.gz.sig        # « Good signature »
sha256sum linux-postmarketos-qcom-sdm845-7.1_rc1-r4.apk    # d0b4b950a500cede…9804
```

Carte dans le PC (repérer son nom avec `lsblk` avant et après l'avoir branchée) :

```sh
sudo scripts/2-preparer-carte.sh /dev/sdX ArchLinuxARM-aarch64-latest.tar.gz \
    linux-postmarketos-qcom-sdm845-7.1_rc1-r4.apk
```

Le script :
- construit `boot-akatsuki.img` : noyau pmOS sans verrouillage, DTB du XZ3 (écran,
  tactile, son, caméra, capteurs, flash, LED, vibreur, Bluetooth), garde-fou UFS ;
  aucune adresse MAC dedans (elles sont lues dans la TA au démarrage) ;
- prépare la carte : Arch Linux ARM, modules du noyau, nos modules précompilés
  (écran, tactile, caméra, Bluetooth), copie du dépôt et de `akatsuki-perso/`
  (dans la partition d'Arch, invisible pour Android), partition d'échange de 8 Go.

## 3. Flasher le noyau

Carte dans le téléphone. Téléphone éteint : **Volume haut + câble USB** (LED bleue).

```sh
scripts/3-flasher.sh
```

(`fastboot flash boot_b`, `fastboot erase dtbo_b`, `fastboot --set-active=b`, redémarrage.)
Le premier démarrage d'Arch prend 1 à 2 minutes.

## 4. Installer le reste du système depuis internet

Donner internet au téléphone par le câble, sur le PC :

```sh
sudo scripts/partage-internet-pc.sh start
```

Puis se connecter au téléphone et lancer l'installation :

```sh
ssh alarm@172.16.42.1                 # mot de passe : alarm
su -                                  # mot de passe : root
sh /root/alarm-sony-akatsuki/scripts/4-installer-systeme.sh <APN>
```

`<APN>` : point d'accès des données mobiles de votre opérateur (facultatif, réglable
ensuite dans Plasma). Le script (une à deux heures) met Arch à jour, installe les
fichiers de l'étape 1, le modem, le Wi-Fi, Plasma Mobile, le son, les appels et SMS,
le Bluetooth, les capteurs, l'horloge et les réglages de réactivité. Il peut être
relancé s'il s'arrête en cours de route.

Pour finir :

```sh
passwd; passwd alarm                  # changer les deux mots de passe
reboot
```

Plasma Mobile s'ouvre. Wi-Fi et données mobiles : panneau réseau de Plasma.

## Vérifier

| Fonction | Essai |
|---|---|
| Wi-Fi, données | panneau réseau de Plasma ; `nmcli` |
| SIM, SMS, appels | `mmcli -m any` ; Spacebar, plasma-dialer |
| Son | lecture dans Plasma ; son pendant un appel |
| Bluetooth | `bluetoothctl show` → `Powered: yes`, adresse d'origine |
| Capteurs, rotation | `monitor-sensor` ; rotation automatique |
| Caméra avant | plasma-camera |
| Caméra arrière | `cam -l` (deux caméras) ; plasma-camera |
| Lampe, LED | tuile « Lampe de poche » ; `/sys/class/leds/rgb:status` |
| Horloge | éteindre, attendre, rallumer sans réseau : l'heure doit être juste |

État de chaque fonction : [README](../README.md#état). Détail de ce que font les
scripts, et dépannage : [installation-manuelle.md](installation-manuelle.md).

## Revenir à LineageOS

Extinction forcée (**Power + Volume haut** jusqu'à 3 vibrations), **Volume haut +
câble** (LED bleue), puis `fastboot --set-active=a && fastboot reboot`.
Retour à Arch : `fastboot --set-active=b && fastboot reboot`. Ne jamais formater la
carte depuis Android.
