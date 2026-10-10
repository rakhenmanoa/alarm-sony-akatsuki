# Premier démarrage : Arch Linux ARM sur carte micro-SD

> ⚠️ **À revoir après l'essai réel du 10/10/2026** (voir
> [premier-demarrage-resultats.md](premier-demarrage-resultats.md)) :
> 1. `fastboot boot` ne marche pas : utiliser le slot B avec `dtbo_b` effacé ;
> 2. le bootloader ajoute `root=/dev/dm-0` après notre ligne de commande, donc
>    l'approche « initramfs vide + `root=` » ci-dessous ne peut pas fonctionner :
>    il faut un initramfs qui monte la carte SD lui-même.

Objectif : démarrer le noyau pmOS 7.1 **sans rien flasher**, avec Arch Linux ARM sur la
carte SD, l'écran en console (simple-framebuffer) et un accès SSH par le câble USB.

Pas d'initramfs : le noyau pmOS intègre déjà le lecteur SD (`sdhci-msm`), `ext4` et le
contrôleur USB, il monte donc directement `/dev/mmcblk0p1` (`root=`). L'UFS étant
désactivé, la carte SD est le seul périphérique MMC : elle s'appelle forcément `mmcblk0`.

## Ce qu'il faut

- Une carte micro-SD de 4 Go à 512 Go (son contenu sera **effacé**) et un lecteur.
- Un PC Linux avec `sfdisk`, `mkfs.ext4`, `bsdtar` (paquet `libarchive`), `dtc`,
  `mkbootimg` (paquet `android-tools` ou `mkbootimg`), `fastboot`, et de préférence `depmod` (`kmod`).
- Le paquet noyau pmOS : `linux-postmarketos-qcom-sdm845-7.1_rc1-r4.apk`
  (si le navigateur l'a renommé en `…-7_1_rc1-r4.apk`, le renommer avec le point).

## 1. Télécharger Arch Linux ARM (aarch64 générique)

```sh
wget http://os.archlinuxarm.org/os/ArchLinuxARM-aarch64-latest.tar.gz
wget http://os.archlinuxarm.org/os/ArchLinuxARM-aarch64-latest.tar.gz.sig
gpg --keyserver keyserver.ubuntu.com --recv-keys 68B3537F39A313B3E574D06777193F152BDBE6A6
gpg --verify ArchLinuxARM-aarch64-latest.tar.gz.sig
```

La signature doit être « Good signature » de *Arch Linux ARM Build System*.
(Vérifier l'empreinte de la clé sur archlinuxarm.org si elle a changé.)

## 2. Préparer la carte SD

Repérer le bon périphérique **avant et après** avoir inséré la carte :

```sh
lsblk -o NAME,SIZE,MODEL,TRAN,RM
```

Puis (exemple avec `/dev/sdb`) :

```sh
sudo scripts/prepare-sdcard.sh /dev/sdb ArchLinuxARM-aarch64-latest.tar.gz \
    linux-postmarketos-qcom-sdm845-7.1_rc1-r4.apk
```

Le script refuse un disque non amovible, de plus de 512 Go, monté, ou contenant le
système du PC, et demande de retaper le nom du périphérique. Il :

1. crée une table GPT avec une partition ext4 `ALARM_ROOT` ;
2. extrait Arch Linux ARM ;
3. copie les 1155 modules du noyau pmOS dans `/usr/lib/modules/7.1.0-rc1-sdm845`,
   et le noyau + DTB d'origine dans `/boot/akatsuki/` (pour mémoire) ;
4. installe la configuration du dossier [`rootfs/`](../rootfs) : réseau USB, `fstab`, nom d'hôte ;
5. active `akatsuki-usb-gadget`, `systemd-networkd` et `sshd`.

Firmwares (facultatif pour ce premier essai, utiles pour le Wi-Fi, le modem, etc.) :
`FIRMWARE_DIR=/chemin/vers/lib/firmware sudo -E scripts/prepare-sdcard.sh …`

## 3. Construire le DTB et le boot.img

```sh
mkdir x && gzip -dc linux-postmarketos-qcom-sdm845-7.1_rc1-r4.apk | tar -xi -C x
scripts/build-dtb.sh x/boot/dtbs/qcom/sdm845-sony-xperia-tama-akatsuki.dtb akatsuki-fb-charge.dtb
scripts/make-first-bootimg.sh x/boot/vmlinuz akatsuki-fb-charge.dtb boot-first.img
```

`build-dtb.sh` et `make-bootimg.sh` vérifient tous deux que l'UFS reste désactivé.

## 4. Démarrer (temporairement)

1. Insérer la carte SD dans le téléphone (tiroir SIM/SD).
2. Téléphone éteint : maintenir **Volume haut** et brancher l'USB → LED **bleue**.
3. Sur le PC :

   ```sh
   fastboot boot boot-first.img
   ```

`fastboot boot` n'écrit rien : au prochain redémarrage, LineageOS revient.

## 5. Se connecter

Le téléphone apparaît comme carte réseau USB (`18d1:d001`, NCM) et distribue une
adresse au PC (172.16.42.2 à .11) :

```sh
ip addr                        # une interface usb0 / enp…u… doit apparaître
ssh alarm@172.16.42.1          # mot de passe : alarm
su -                           # mot de passe : root
passwd; passwd alarm           # changer les deux mots de passe tout de suite
```

Si le PC ne reçoit pas d'adresse : `sudo ip addr add 172.16.42.2/24 dev <interface>`.

Première tâche une fois connecté (horloge souvent fausse, clés pacman) :

```sh
date -s "2026-10-10 12:00"     # mettre la vraie date
pacman-key --init && pacman-key --populate archlinuxarm
```

## Ce qu'il faut observer

| Observation | Signification | Suite |
|---|---|---|
| Console texte Linux à l'écran | simplefb OK, noyau démarré | voir [etape1-ecran-charge.md](etape1-ecran-charge.md) |
| Messages puis blocage sur « Waiting for root device /dev/mmcblk0p1 » | lecteur SD non vu | photo de l'écran ; vérifier la carte sur le PC |
| Écran noir, mais réseau USB présent | noyau OK, framebuffer à ajuster | `dmesg` par SSH |
| Rien du tout (ni écran, ni USB) après 1–2 min | noyau ou DTB ne démarre pas | Power + Volume haut (3 vibrations) pour éteindre, me décrire ce qui s'est passé |
| `ssh` refusé, mais ping OK | sshd pas démarré | `journalctl` impossible : me le signaler |

Récupérer les journaux utiles, une fois connecté :

```sh
dmesg > dmesg.txt; journalctl -b > journal.txt
exit
scp alarm@172.16.42.1:'*.txt' .
```

## Sortir

`poweroff` en SSH, ou Power + Volume haut jusqu'à 3 vibrations. Au démarrage suivant
(normal), le téléphone revient sur LineageOS : rien n'a été écrit dans sa mémoire.
