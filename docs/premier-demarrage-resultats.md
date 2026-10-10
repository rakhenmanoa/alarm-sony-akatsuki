# Premier démarrage réel du noyau mainline sur le XZ3 (10/10/2026)

Téléphone : Xperia XZ3 H8416, bootloader `1310-7079_X_Boot_SDM845_LA2.0_P_118`, déverrouillé.
Noyau : pmOS `linux-postmarketos-qcom-sdm845` `7.1_rc1-r4`, DTB étape 1 (simple-framebuffer
+ charge), initramfs de [`test-boot/`](../test-boot) v3.
Journal complet : [`journaux/2026-10-10-test-boot-v3.txt`](journaux/2026-10-10-test-boot-v3.txt)
(IMEI et numéro de série masqués).

## Comment démarrer

`fastboot boot` **ne fonctionne pas** : le bootloader Sony superpose le `dtbo` du slot
actif (Android) au DTB mainline, et le noyau meurt avant tout affichage.
Méthode qui marche : slot inutilisé avec `dtbo` vide.

```sh
fastboot flash boot_b <image>
fastboot erase dtbo_b
fastboot --set-active=b
fastboot reboot
# retour à LineageOS : fastboot --set-active=a && fastboot reboot
```

## Ce qui fonctionne

| Élément | Preuve dans le journal |
|---|---|
| Démarrage du noyau, 8 cœurs, 4 Go | `smp: Brought up 1 node, 8 CPUs`, `Memory: 3379240K/4164352K` |
| Régulateurs RPMh (PM8998) | `ldo1…ldo28: Setting …` |
| Carte micro-SD | `mmc0: new UHS-I speed SDR104 SDXC card`, `mmcblk0: 58.2 GiB` (vers 3,6 s) |
| USB en mode périphérique (dwc3) | `akatsuki-test: a600000.usb`, gadget ACM + NCM vu par le PC |
| Réseau USB | `usb0 = 172.16.42.1/24`, ping et HTTP depuis le PC |
| Bouton marche, boutons volume | `pm8941_pwrkey`, `gpio-keys` |
| pstore / ramoops | `ramoops: using 0x100000@0xffc00000` → journaux après plantage récupérables |
| UFS | **non touché** (aucun message `ufshc`) ✅ |

## Ce qui ne fonctionne pas encore

**Écran.** `simplefb registered` et la console passe bien sur le framebuffer
(`switching to colour frame buffer device 180x180`), mais l'écran reste noir et
**aucun logo** n'apparaît dès le bootloader. Le bootloader n'a donc pas laissé
l'écran allumé à la main de Linux : simple-framebuffer n'a rien à réutiliser.
Il faudra le vrai pilote d'affichage (MDSS + DSI + panneau LG avec compression DSC,
patches de Marijn Suijten, non fusionnés).

**Port série USB (`ttyACM0`).** Muet. Cause non établie : les messages de diagnostic de
l'init ont été supprimés par la limitation de débit de `/dev/kmsg` (10 messages par 5 s :
« USB prêt », « serveur web prêt » et l'état de `/dev/ttyGS0` manquent). À corriger avec
`printk.devkmsg=on`. Sans gravité : le réseau USB fait mieux.

**Pas encore chargés** (modules absents de l'initramfs de test) : chargeur et jauge
de batterie, Wi-Fi, modem, son, capteurs.

## Point important pour la suite : la ligne de commande du bootloader

Le bootloader **ajoute ses propres paramètres après les nôtres**, dont :

```
root=/dev/dm-0 … skip_initramfs rootwait ro init=/init
```

Pour le noyau, le dernier `root=` gagne : un `root=/dev/mmcblk0p1` passé dans le
`boot.img` serait **écrasé** par `root=/dev/dm-0`. Démarrer Arch directement par
`root=` (sans initramfs, comme le prévoyait l'ancien `scripts/make-first-bootimg.sh`, supprimé depuis) ne
marchera donc pas. Il faut un **initramfs** qui monte lui-même la carte SD
(`/dev/mmcblk0p1`) puis bascule dessus (`switch_root`) — c'est ce que font
postmarketOS et Mobile NixOS.

## Autres remarques

- `[Firmware Bug]: Kernel image misaligned at boot` : sans conséquence.
- `rmtfs@88f00000` : adresse du DTB pmOS ; le modem attendra `0xfdc01000` (à corriger
  quand on s'attaquera au modem).
- `qseecom: untested machine, skipping` : normal, pas utile pour l'instant.
