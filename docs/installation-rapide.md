# Installation rapide (images toutes prêtes des Releases)

Pour un **Xperia XZ3 (akatsuki) au bootloader déverrouillé, sous LineageOS** (slot A).
Les Releases du dépôt contiennent un système Arch Linux ARM + Plasma Mobile déjà
configuré et une image de démarrage générique : il ne reste qu'à y ajouter les fichiers
propres à **votre** téléphone (firmwares Sony, EFS, TA), récupérés sous LineageOS.

Installation en 4 étapes, sans les images du système : [installation.md](installation.md).

> ⚠️ Ne flasher que l'image de démarrage des Releases ou une image construite par les
> scripts du dépôt (garde-fou UFS : voir le [README](../README.md)).

## Ce qu'il faut

- PC Linux avec `adb`, `fastboot`, `sfdisk`, `mkfs.ext4`, `mkfs.exfat` (`exfatprogs`),
  `bsdtar` (`libarchive`), `zstd`, `python3`, `git`.
- Carte micro-SD de 16 Go ou plus (effacée), rapide de préférence (A2/U3).
- Le dépôt : `git clone https://github.com/rakhenmanoa/alarm-sony-akatsuki.git`
- Depuis la page **Releases** : `akatsuki-systeme-AAAAMMJJ.tar.zst` (ou ses morceaux
  `.part00`, `.part01`…), `boot-akatsuki-generique.img`, le fichier `.sha256`, et le
  paquet noyau `linux-postmarketos-qcom-sdm845-7.1_rc1-r4.apk`.

## 1. Vérifier les téléchargements

```sh
sha256sum -c akatsuki-systeme-*.sha256
cat akatsuki-systeme-*.tar.zst.part* > akatsuki-systeme.tar.zst   # seulement si découpée
```

## 2. Préparer la carte (sur le PC)

Repérer la carte avec `lsblk`, puis :

```sh
sudo scripts/prepare-sdcard.sh /dev/sdX akatsuki-systeme.tar.zst \
    linux-postmarketos-qcom-sdm845-7.1_rc1-r4.apk
```

(Le script accepte l'archive du système à la place de celle d'Arch Linux ARM.)

## 3. Ajouter les fichiers propres au téléphone (sous LineageOS)

Carte dans le téléphone, LineageOS démarré, **Options pour les développeurs →
Débogage USB** et **Débogage root** activés :

```sh
scripts/preparer-telephone.sh
```

Le script lit seulement le téléphone (firmwares, EFS, TA, Bluetooth, capteurs) et dépose
tout sur la partition d'échange de la carte. **Garder** le dossier `akatsuki-perso/`
créé sur le PC (sauvegarde de l'EFS, donc de l'IMEI) et **ne jamais le publier**.

## 4. Flasher l'image de démarrage et démarrer

Téléphone éteint : **Volume haut + câble USB** (LED bleue).

```sh
fastboot getvar current-slot                      # « a » (LineageOS)
fastboot flash boot_b boot-akatsuki-generique.img
fastboot erase dtbo_b
fastboot --set-active=b
fastboot reboot
```

Au premier démarrage, Arch installe les fichiers déposés à l'étape 3, efface de la carte
l'EFS et la TA, puis **redémarre une fois tout seul**. Plasma Mobile s'ouvre ensuite.

## 5. Premiers réglages

Par le câble USB (`ssh alarm@172.16.42.1`, mot de passe `alarm`) ou dans Konsole :

```sh
su -                            # mot de passe : root
passwd; passwd alarm            # changer les deux mots de passe
nmtui                           # Wi-Fi (ou le panneau réseau de Plasma)
```

Données mobiles : dans le panneau réseau de Plasma, ou
`nmcli connection add type gsm ifname '*' con-name mobile apn <APN>`.

Vérifier : Wi-Fi et données, SMS (Spacebar), appels, son, Bluetooth
(`bluetoothctl show`), rotation, lampe de poche. État des fonctions : [README](../README.md#état).

## Revenir à LineageOS

Extinction forcée (**Power + Volume haut** jusqu'à 3 vibrations), **Volume haut + câble**,
puis `fastboot --set-active=a && fastboot reboot`. Retour à Arch : `--set-active=b`.
