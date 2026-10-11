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
# …/remoteprocN/name:4080000.remoteproc   …/remoteprocN/state:offline   (11/10/2026 : remoteproc0 = adsp, remoteproc1 = modem, remoteproc2 = cdsp)
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
| modem (`rmtfs -s`) | ⚠️ `now up`, EFS lu (fs1, fs2, fsg, fsc ; `fsg_oem_1/2` refusés), zone `0xfdc01000` acceptée ; puis `fatal error without message` **40 s après chaque démarrage**, en boucle. Seuls les services de base du modem (66, 43) apparaissent dans `qrtr-lookup` |
| IPA (`boot-arch-ipa.img`) | ✅ `IPA driver setup completed successfully`, reçoit les événements du modem ; **mais le modem plante toujours 40 s après son démarrage** : ce n'était pas la cause. `tqftpserv` ne reçoit aucune demande. `tqftpserv -d` : aucune demande. Sous LineageOS, le modem lit l'EFS puis, 0,2 s après, demande `readwrite/ota_firewall/ruleset` et `wlanmdsp.mbn` en TFTP, et le Wi-Fi démarre 1 s plus tard ; sous Arch, il s'arrête entre la lecture de l'EFS et le TFTP. `fsg_oem_1/2` n'existent pas dans le téléphone (refusés aussi sous LineageOS). Adresses mémoire identiques à LineageOS. Vidage mémoire du modem (devcoredump) : vide (zéros, mémoire protégée par TrustZone). **Piste actuelle** : LineageOS fait tourner des services QMI propres à Sony, absents de Linux — `ta_qmi_service` (« TA QMI service » et « MiscTA QMI service » : données de la partition TA servies au modem), `mlog_qmi_service`, `tad` ; le modem les attendrait après la lecture de l'EFS |
| Services Sony (`qmi-ecoute.py`) | ✅ **modem complètement démarré, plus de plantage** : une trentaine de services sur le nœud 0 (voix 9, réseau 3, SMS 5, SIM 11, données 1, Wi-Fi 69…) |
| Wi-Fi | ✅ `ath10k_snoc` : firmware WLAN.HL.2.0.c12, `wcn3990 hw1.0` ; interface `wlan0` (adresse MAC aléatoire : la vraie est sans doute dans la partition TA) ; scan et connexion à tester |
| Données mobiles | interface `rmnet_ipa0` présente ; à tester |

## 4 bis. Essai avec l'IPA (`boot-arch-ipa.img`)

Sur SDM845, le modem attend que Linux initialise l'IPA (accélérateur réseau partagé) ;
le plantage régulier 40 s après le démarrage en est le symptôme probable. Le DTB de
`boot-arch-ipa.img` active l'IPA (firmware `ipa_fws.mbn` chargé par Linux).

`ipa_fws.mbn` reste hors de `/usr/lib/firmware` : au démarrage, le pilote `ipa` échoue
proprement (`ipa_fws.mbn` introuvable), puis on le relie à la main :

```sh
fastboot flash boot_b boot-arch-ipa.img && fastboot reboot     # depuis le PC, slot B actif
```

```sh
# session 1
dmesg -w
# session 2 (root)
echo -n /root/fw-essai > /sys/module/firmware_class/parameters/path
echo 1e40000.ipa > /sys/bus/platform/drivers/ipa/bind       # 1) l'IPA d'abord
tqftpserv &
rmtfs -o /var/lib/rmtfs -s -v                                # 2) puis le modem
```

Attendu : `ipa 1e40000.ipa: IPA driver initialized`, puis, une fois le modem démarré,
`ipa … received modem running event` et une interface `rmnet_ipa0` ; le modem ne doit
plus planter au bout de 40 s, et `qrtr-lookup` doit montrer beaucoup plus de services
sur le nœud 0 (dont 69, le Wi-Fi).

Si tout fonctionne, il restera à rendre l'ensemble automatique (firmwares dans
`/usr/lib/firmware`, services `tqftpserv` et `rmtfs` activés au démarrage). Les données
mobiles (IPA) et les appels/SMS (ModemManager) viendront ensuite.

## Services QMI de LineageOS (relevé du 11/10/2026)

`/sys/kernel/debug/msm_ipc_router/dump_servers` sous LineageOS (champ « Instance » =
instance << 8 | version). Services annoncés côté Android (nœud 1) :

| Service | Programme | Équivalent sous Arch |
|---|---|---|
| 14 | `rmt_storage` | `rmtfs` ✅ |
| 64 | `pd-mapper` | noyau (`qcom_pd_mapper`) ✅ |
| 4096 (TFTP), versions 1 à 10 | `tftp_server` | `tqftpserv` (version 1 seulement) |
| 49 (IPA) | noyau | noyau (`ipa`) ✅ |
| **227 (0xe3)** | `ta_qmi_service` (TA) | ❌ |
| **228 (0xe4)** | `ta_qmi_service` (MiscTA) | ❌ |
| **229 (0xe5)** | `sct_service` | ❌ |
| **230 (0xe6)** | `mlog_qmi_service` | ❌ |
| 28 (RFSA), 52 (memshare), 53, 1053 | noyau / `pm-service` | ❌ |
| 770 | `imsdatadaemon` | ❌ (appels VoLTE, plus tard) |

[`scripts/qmi-ecoute.py`](../scripts/qmi-ecoute.py) annonce les services Sony 227 à 230
et affiche ce que le modem leur demande :

```sh
python3 qmi-ecoute.py | tee /root/qmi-ecoute.log      # session 3, AVANT rmtfs
```


**Résultat du 11/10/2026 : le modem dépasse son blocage.** Dès que les services Sony
existent (même s'ils répondent « non pris en charge »), le modem continue son
démarrage : il interroge **MiscTA (228)** et envoie son **journal (mlog, 230)** en clair.

- MiscTA, message `0x0001` (lecture d'une unité TA ?) : unités 0x7d3, 0x7da, 0x7db,
  0x7df, 0x9c7 ; message `0x0002` (taille d'une unité ?) : 0x8a1, 0x8b3, 0x9b7, 0x9f6 ;
  message `0x0004` (écriture) : unité 0x9c7 avec le texte `-1:3:s1sl/s1sl_integration.c:2121`.
- Journal du modem : `MMGSDI_CARD_INSERTED_EVT, slot: 0x1` (carte SIM détectée),
  `MMGSDI_PIN1_EVT`, `SIM Lock response message not supported(status=1)`.

Prochaine étape : un vrai service MiscTA qui lit une copie de la partition TA.

### Wi-Fi : le firmware plante à la création de l'interface (11/10/2026)

`ip link set wlan0 up` → `wmi command 20481 timeout`, `failed to create WMI vdev 0`,
`firmware crashed!`. La puce ne donne pas d'identifiant de carte (`board_id 0xff`) :
ath10k prenait les réglages génériques de `linux-firmware`. Sony fournit les siens dans
`/vendor/etc/wifi/bdwlan.bin` (19 152 octets). [`scripts/ath10k-board2.py`](../scripts/ath10k-board2.py)
les range dans un `board-2.bin` (noms `bus=snoc,qmi-board-id=ff[,qmi-chip-id=30214]`),
installé dans `/usr/lib/firmware/updates/ath10k/WCN3990/hw1.0/` pour passer avant
celui de `linux-firmware`. `extraire-firmwares-adb.sh` le fabrique automatiquement.

### Wi-Fi : la vraie cause, la commande « quiet mode » (11/10/2026)

Avec le mode bavard d'ath10k (`debug_mask=0x00200022`), les réglages Sony sont bien
envoyés (`boot found board data … qmi bdf download request completed`), puis :

```
wmi tlv quiet param: period 100 duration 0 enabled 0
wmi tlv vdev create
fatal error received: err_qdi.c:456:EX:wlan_process:1:WLAN RT:108b:PC=b001ba04
```

C'est le bug décrit par le patch « ath10k: skip quiet mode for WCN3990 to prevent
firmware crash » (Malte Schababerle, liste ath10k, 22/03/2026) : le firmware annonce
le service THERM_THROT, ath10k lui envoie « quiet mode », il plante ~17 ms après la
création de l'interface et entraîne le modem. Le firmware Sony WLAN.HL.2.0.c12 fait
de même. Le patch n'est pas dans le noyau pmOS 7.1-rc1.

Correctif sans recompiler le noyau : [`scripts/ath10k-sans-quiet.py`](../scripts/ath10k-sans-quiet.py)
fait rendre la main immédiatement à `ath10k_thermal_set_throttling()` dans une copie
du module (vérification des octets avant modification, signature retirée), installée
dans `/usr/lib/modules/<version>/updates/` (prioritaire pour `depmod`) :

```sh
M=/usr/lib/modules/$(uname -r)
zstd -dc $M/kernel/drivers/net/wireless/ath/ath10k/ath10k_core.ko.zst > /tmp/ath10k_core.ko
python3 ath10k-sans-quiet.py /tmp/ath10k_core.ko /tmp/ath10k_core.sans-quiet.ko
install -D -m 644 /tmp/ath10k_core.sans-quiet.ko $M/updates/ath10k_core.ko
depmod -a && modinfo -n ath10k_core      # → …/updates/ath10k_core.ko
reboot
```

Retour arrière : `rm $M/updates/ath10k_core.ko && depmod -a && reboot`.

**⚠️ Refusé par le noyau pmOS (essai du 11/10/2026)** : `Lockdown: (udev-worker): unsigned
module loading is restricted`. Le noyau est compilé avec
`CONFIG_LOCK_DOWN_KERNEL_FORCE_INTEGRITY=y` (verrouillage actif dès le démarrage,
impossible à lever par la ligne de commande) : tout module non signé par la clé de
pmOS est refusé, et `ath10k_core` ne se charge plus du tout. **Ne pas utiliser ce
correctif avec le noyau pmOS** ; il faut un noyau recompilé (avec le patch
« skip quiet mode »), ou une version de pmOS qui l'intègre.
