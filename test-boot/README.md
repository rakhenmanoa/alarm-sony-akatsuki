# Test : est-ce que le noyau démarre ?

Le test le plus simple possible : **noyau pmOS 7.1 + DTB + un initramfs de 115 Ko**.
Pas de carte SD, pas de système, rien n'est écrit sur le téléphone (`fastboot boot`).

L'initramfs ne contient que [`init.c`](init.c) (programme sans libc, appels système
directs) et les 5 modules du gadget USB repris tels quels du paquet pmOS.

## Construire

```sh
test-boot/build.sh linux-postmarketos-qcom-sdm845-7.1_rc1-r4.apk boot-test-noyau.img
```

Nécessite `clang`, `ld.lld`, `python3`, `dtc`, `mkbootimg`. Le DTB utilisé est celui
de l'étape 1 (écran en simple-framebuffer) ; l'UFS est vérifié désactivé.

## Lancer

Noter d'abord le slot de LineageOS : `fastboot getvar current-slot`.

Téléphone éteint, **Volume haut + câble USB** (LED bleue), puis :

```sh
fastboot boot boot-test-noyau.img
```

## Lire le résultat

| Ce qui se passe | Verdict |
|---|---|
| Messages du noyau à l'écran, puis `akatsuki-test: init lancé : le noyau a démarré !` | ✅ Noyau, DTB et écran OK |
| Un nouveau périphérique USB `18d1:d001` « Xperia XZ3 test noyau » (`lsusb`, `dmesg -w` sur le PC) | ✅ Noyau + USB OK |
| Écran noir, mais le téléphone **revient tout seul en fastboot** (LED bleue) après ~40 s | 🟡 Le noyau a démarré et lancé init, mais l'USB n'a pas pu être activé |
| Le téléphone redémarre sur le **recovery** ou change de slot | ❌ Le noyau a planté (redémarrage par le chien de garde) : le bootloader a compté un échec de démarrage. Revenir avec `fastboot --set-active=<slot de LineageOS>` |
| Écran noir, rien sur l'USB, pas de redémarrage (attendre 3 min) | ❌ Le noyau ne démarre pas (ou plante avant init) |

Pour éteindre en cas de blocage : **Power + Volume haut** jusqu'à 3 vibrations.

## Lire le journal du noyau depuis le PC

Le téléphone fournit un port série USB :

```sh
sudo screen /dev/ttyACM0       # ou : sudo picocom /dev/ttyACM0
```

Appuyer sur **Entrée** : le journal complet s'affiche, puis les nouveaux messages au fil
de l'eau. Commandes (lettre puis Entrée) : **b** redémarrer en fastboot,
**r** redémarrer, **p** éteindre.

Pour garder une copie : `sudo sh -c 'cat /dev/ttyACM0 > dmesg-xz3.txt'`, puis Entrée
dans un autre terminal avec `echo > /dev/ttyACM0`.

Réseau (facultatif, le téléphone est en 172.16.42.1, sans DHCP) :

```sh
sudo ip addr add 172.16.42.2/24 dev <interface usb>   # voir « ip link »
ping 172.16.42.1
```

## Vérifié avant le premier essai

Le même noyau et le même initramfs (extrait du `boot.img`) ont été démarrés dans
QEMU (machine `virt` ARM64) : init lancé, les 5 modules (zstd, signés) chargés,
configuration USB créée sans erreur ; faute de contrôleur USB dans la machine
virtuelle, retour demandé en mode fastboot (`reboot: Restarting system with command 'bootloader'`) au bout de 44 s, comme prévu. Ce qui reste
propre au téléphone : DTB, écran, contrôleur USB dwc3.
