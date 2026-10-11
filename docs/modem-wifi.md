# Modem et Wi-Fi (essai du 11/10/2026)

Sur le Snapdragon 845, le Wi-Fi dépend du modem : la puce WCN3990 est pilotée par le
firmware du modem (`wlanmdsp.mbn`), et Linux (`ath10k_snoc`) ne lui parle qu'une fois
le modem démarré. Il faut donc, dans l'ordre :

| Élément | Rôle | Où |
|---|---|---|
| DTB : `remoteproc@4080000` et `wifi@18800000` activés | décrire le modem et la puce Wi-Fi | [`dts/akatsuki-modem-wifi.dtsi`](../dts/akatsuki-modem-wifi.dtsi), dans `boot-arch-modem.img` |
| `mba.mbn`, `modem.mbn`, `wlanmdsp.mbn` | firmwares Sony | déjà extraits par `scripts/extraire-firmwares-adb.sh` |
| EFS (`modemst1`, `modemst2`, `fsc`, `fsg`) | IMEI, calibration radio | **copie** prise sous LineageOS par [`scripts/copier-efs-adb.sh`](../scripts/copier-efs-adb.sh) |
| `rmtfs` | sert l'EFS au modem et le démarre (`-s`) | [`scripts/installer-outils-modem.sh`](../scripts/installer-outils-modem.sh) |
| `tqftpserv` | sert `wlanmdsp.mbn` au modem | idem |
| pd-mapper | annuaire des services | dans le noyau (`qcom_pd_mapper`) |
| `board-2.bin` (ath10k WCN3990) | réglages de la carte Wi-Fi | paquet `linux-firmware-atheros` |

**Sécurité** : `rmtfs` travaille sur une copie de l'EFS posée sur la carte SD. La
mémoire interne (UFS) n'est jamais ouverte par Arch. Le pilote du modem ne le démarre
pas tout seul (seul `rmtfs -s` le fait) : si l'essai fait planter le téléphone, il
redémarre normalement sur Arch, sans boucle.

## 1. Flasher le nouveau boot.img (slot B)

Téléphone éteint, Volume haut + câble (LED bleue) :

```sh
fastboot flash boot_b boot-arch-modem.img
fastboot --set-active=b
fastboot reboot
```

Après le démarrage, rien ne doit changer ; un nouveau coprocesseur apparaît, arrêté :

```sh
grep . /sys/class/remoteproc/*/name /sys/class/remoteproc/*/state
# …/remoteprocN/name:4080000.remoteproc   …/remoteprocN/state:offline   (numéro variable : remoteproc1 le 11/10/2026)
```

## 2. Copier l'EFS (sous LineageOS)

```sh
fastboot --set-active=a && fastboot reboot      # ou depuis Arch : retour à LineageOS
scripts/copier-efs-adb.sh                       # sur le PC, depuis le dépôt
```

Lecture seule. Résultat dans `efs-akatsuki/` sur le PC (sauvegarde à garder, **jamais
publiée** : contient l'IMEI) et sur la partition d'échange de la carte SD.

## 3. Installer les outils et l'EFS (sous Arch, root, internet par USB actif)

```sh
scp scripts/installer-outils-modem.sh alarm@172.16.42.1:/tmp/   # depuis le PC
```

```sh
sh /tmp/installer-outils-modem.sh
pacman -S --needed linux-firmware-atheros iw iwd
install -d -m 700 /var/lib/rmtfs
install -m 600 /mnt/partage/efs-akatsuki/modem_fs* /var/lib/rmtfs/
rm -r /mnt/partage/efs-akatsuki
ls /root/fw-essai/qcom/sdm845/Sony/tama/        # mba.mbn modem.mbn wlanmdsp.mbn présents ?
```

## 4. Premier démarrage du modem, à la main

Comme pour l'ADSP : firmwares visibles seulement pour la session en cours.

```sh
# session SSH 1
dmesg -w
```

```sh
# session SSH 2 (root)
echo -n /root/fw-essai > /sys/module/firmware_class/parameters/path
tqftpserv &
rmtfs -o /var/lib/rmtfs -s -v
```

Ce qu'on espère voir dans `dmesg` :

```
remoteproc remoteprocN: powering up 4080000.remoteproc
remoteproc remoteprocN: remote processor 4080000.remoteproc is now up
ath10k_snoc 18800000.wifi: qmi chip_id … board_id … soc_id …
ath10k_snoc 18800000.wifi: wcn3990 hw1.0 target 0x00000008 …
```

puis une interface `wlan0` (`ip link`). `Ctrl+C` sur `rmtfs` arrête le modem.

## 5. Wi-Fi

```sh
ip link set wlan0 up
iw dev wlan0 scan | grep SSID
systemctl start iwd
iwctl station wlan0 connect "<nom du réseau>"
networkctl status wlan0        # ou : dhcpcd wlan0 / iwd avec EnableNetworkConfiguration
```

## Lire le résultat

| Symptôme | Signification |
|---|---|
| le téléphone redémarre au `rmtfs -s` | modem refusé par TrustZone (adresses mémoire ?) : envoyer le journal du démarrage précédent (`journalctl -b -1 -k`) |
| `rmtfs` : `failed to open /dev/qcom_rmtfs_mem1` | zone rmtfs du DTB non reconnue |
| `remoteproc … fatal error` / `crashed` | firmware ou EFS refusés : envoyer `dmesg` et la sortie de `rmtfs -v` |
| modem `up`, pas de `ath10k` | `wlanmdsp.mbn` non servi : regarder la sortie de `tqftpserv` |
| `ath10k … failed to fetch board data` | `board-2.bin` sans entrée pour cette carte : variante de calibration à ajouter au DTB |
| `wlan0` présent | ✅ Wi-Fi |

Résultats :

| Étape | Résultat |
|---|---|
| démarrage avec `boot-arch-modem.img` | ✅ démarrage normal, modem vu (`remoteproc1: 4080000.remoteproc is available`), arrêté |
| modem (`rmtfs -s`) | à tester |
| Wi-Fi (`wlan0`, scan, connexion) | à tester |

Si tout fonctionne, il restera à rendre l'ensemble automatique (firmwares dans
`/usr/lib/firmware`, services `tqftpserv` et `rmtfs` activés au démarrage). Les données
mobiles (IPA) et les appels/SMS (ModemManager) viendront ensuite.
