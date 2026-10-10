# Premier démarrage : Arch Linux ARM sur carte micro-SD

Objectif : Arch Linux ARM sur la carte SD du Xperia XZ3, noyau pmOS 7.1 dans le slot B
(LineageOS reste intact dans le slot A), accès **SSH par le câble USB**.
L'écran reste noir pour l'instant (voir [premier-demarrage-resultats.md](premier-demarrage-resultats.md)).

## Comment ça démarre

1. Le bootloader Sony charge `boot_b` (noyau + DTB + initramfs). `dtbo_b` doit être
   **vide**, sinon le bootloader abîme le DTB mainline.
2. L'initramfs ([`test-boot/init.c`](../test-boot/init.c)) monte `/dev/mmcblk0p1`
   (la carte SD : l'UFS étant désactivé, c'est le seul périphérique MMC) et lance
   systemd dessus. On ne peut pas utiliser `root=` : le bootloader ajoute
   `root=/dev/dm-0` après notre ligne de commande.
3. Arch démarre : gadget USB réseau (`akatsuki-usb-gadget`), `systemd-networkd`
   (téléphone en 172.16.42.1, il donne une adresse au PC), `sshd`.

**Filet de sécurité** : si la carte est absente, illisible ou sans systemd, ou si le
fichier `/etc/akatsuki-secours` existe sur la carte, l'initramfs passe en **mode
secours** : USB + serveur web `http://172.16.42.1/` avec le journal du noyau
(adresse du PC à mettre à la main : `172.16.42.2/24`).

## Ce qu'il faut (sur le PC Linux)

- Une carte micro-SD de 4 à 512 Go, **entièrement effacée** par la procédure.
- `sfdisk`, `mkfs.ext4`, `bsdtar` (paquet `libarchive`), `dtc`, `mkbootimg`,
  `clang` + `lld`, `python3`, `fastboot`, `curl`, et de préférence `depmod` (`kmod`).
- Le paquet noyau pmOS `linux-postmarketos-qcom-sdm845-7.1_rc1-r4.apk`.

## 1. Télécharger et vérifier Arch Linux ARM (aarch64 générique)

```sh
curl -LO http://os.archlinuxarm.org/os/ArchLinuxARM-aarch64-latest.tar.gz
curl -LO http://os.archlinuxarm.org/os/ArchLinuxARM-aarch64-latest.tar.gz.sig
gpg --keyserver keyserver.ubuntu.com --recv-keys 68B3537F39A313B3E574D06777193F152BDBE6A6
gpg --verify ArchLinuxARM-aarch64-latest.tar.gz.sig
```

Attendu : « Good signature » de *Arch Linux ARM Build System*. (Vérifier l'empreinte de
la clé sur archlinuxarm.org si elle a changé.)

## 2. Préparer la carte SD

Repérer la carte **avant et après** l'avoir branchée :

```sh
lsblk -o NAME,SIZE,MODEL,TRAN,RM
```

Puis, par exemple pour `/dev/sdb` :

```sh
sudo scripts/prepare-sdcard.sh /dev/sdb ArchLinuxARM-aarch64-latest.tar.gz \
    linux-postmarketos-qcom-sdm845-7.1_rc1-r4.apk
```

Le script refuse un disque non amovible, de plus de 512 Go, monté ou portant le
système du PC, et demande de retaper le nom du périphérique. Il crée une partition ext4
`ALARM_ROOT`, extrait Arch, ajoute les modules du noyau pmOS et la configuration de
[`rootfs/`](../rootfs) (réseau USB, surveillance de la connexion USB, `fstab`, nom
d'hôte), et active `sshd` et `systemd-networkd`.

## 3. Construire le boot.img

```sh
test-boot/build.sh linux-postmarketos-qcom-sdm845-7.1_rc1-r4.apk boot-arch.img
```

(Contrôle UFS fait automatiquement sur le DTB.)

## 4. Flasher dans le slot B et démarrer

Carte SD dans le téléphone. Téléphone éteint, **Volume haut + câble USB** (LED bleue) :

```sh
fastboot getvar current-slot        # doit répondre « a » (LineageOS)
fastboot flash boot_b boot-arch.img
fastboot erase dtbo_b               # déjà fait si on a suivi test-boot/
fastboot --set-active=b
fastboot reboot
```

## 5. Se connecter

Le premier démarrage d'Arch prend plus longtemps (génération des clés SSH, `depmod`).
Attendre 1 à 2 minutes, puis :

```sh
ip addr                             # une interface enp…u… avec une adresse 172.16.42.x
ssh alarm@172.16.42.1               # mot de passe : alarm
su -                                # mot de passe : root
passwd; passwd alarm                # changer les deux mots de passe tout de suite
date -s "2026-10-10 18:30"          # mettre la date (pas encore d'horloge réglée)
pacman-key --init && pacman-key --populate archlinuxarm
```

Si le PC ne reçoit pas d'adresse : `sudo ip addr add 172.16.42.2/24 dev <interface>`.
Si `http://172.16.42.1/` répond (journal du noyau), c'est le **mode secours** : la
première ligne utile du journal dit pourquoi Arch n'a pas été lancé.

## Revenir à LineageOS

Extinction forcée (Power + Volume haut jusqu'à 3 vibrations), puis Volume haut + câble
(LED bleue), et :

```sh
fastboot --set-active=a && fastboot reboot
```

(Le retour en fastboot par logiciel, `reboot bootloader`, ne marche pas encore avec le
bootloader Sony : il faut passer par les boutons.)
