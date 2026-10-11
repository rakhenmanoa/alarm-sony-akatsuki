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

## Firmwares propres au téléphone (à faire ensuite)

Absents au premier démarrage, ils sont signés par Sony et ne sont pas dans
`linux-firmware` :

| Fichier attendu | Rôle |
|---|---|
| `qcom/sdm845/Sony/tama/adsp.mbn` | processeur audio (son, capteurs) |
| `qcom/sdm845/Sony/tama/cdsp.mbn` | processeur de calcul |
| `qcom/sdm845/Sony/tama/venus.mbn` | décodage vidéo |
| `qcom/sdm845/Sony/tama/modem.mbn`, `mba.mbn` | modem (et Wi-Fi via le modem) |
| `qcom/sdm845/Sony/tama/a630_zap.mbn` | GPU |

Sources possibles : les partitions du téléphone lui-même (`modem_a`, `vendor`, lues depuis
LineageOS), ou le dépôt de firmwares de Petr Hodina.
