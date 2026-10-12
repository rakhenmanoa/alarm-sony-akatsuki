# Écran — ✅ fonctionne (11/10/2026)

L'écran du XZ3 est un panneau **LG LH599QH3-EDB1** (1440 × 2880, 60 Hz, compression
**DSC 1.1** obligatoire), avec le tactile Atmel maXTouch. Le bootloader Sony éteint
l'écran avant Linux : le framebuffer simple ne montre rien.

Pilote : série v2 de Marijn Suijten (SoMainline, 21/12/2025), « drm/panel: Add LGD
LH599QH3-EDB1 panel driver for Sony Xperia XZ3 » (`panel-lgd-lh599qh3-edb1.c`,
`compatible = "lgd,lh599qh3-edb1-um1"`), **pas encore dans le noyau officiel**.

## Plan

1. Compiler ce pilote **en module** pour le noyau pmOS, sans recompiler le noyau :
   [`scripts/preparer-arbre-noyau.sh`](../scripts/preparer-arbre-noyau.sh) reproduit
   l'ABI du noyau pmOS (sources v7.1-rc1, clang 22.1.8, même configuration). Vérifié
   en recompilant des modules que pmOS fournit (`panel-simple`, `panel-himax-hx83112a`) :
   désassemblage identique, `struct module` de même taille. Chargeable grâce au
   noyau sans verrouillage (`boot-arch-wifi.img`).
2. DTB : réactiver MDSS/DSI (désactivés pour le framebuffer simple), donner au nœud
   `panel@0` de DSI0 (déjà présent, sans `compatible`) les propriétés du pilote.
3. Essai prudent : module chargé à la main ; au pire écran noir ou redémarrage.
4. Ensuite : tactile (`atmel_mxt_ts`, même méthode).

## État au 11/10/2026

- Module compilé : [`modules/panel-lgd-lh599qh3-edb1/`](../modules/panel-lgd-lh599qh3-edb1/)
  (vermagic `7.1.0-rc1-sdm845`, 33 symboles importés, tous exportés par le noyau pmOS).
- DTB : [`dts/akatsuki-ecran-dsi.dtsi`](../dts/akatsuki-ecran-dsi.dtsi), activé par
  `ECRAN=dsi` : framebuffer simple désactivé, MDSS et dispcc réactivés, `panel@0`
  de DSI0 avec `compatible = "lgd,lh599qh3-edb1-um1"`, `reset-gpios` = GPIO 6 active
  basse (comme Hodina), `avdd-supply` = LDO28 (3,0 V), `vddio-supply` = LDO14 (1,84 V,
  déjà présent), DCDC de l'OLED (GPIO 133) toujours allumé.
- boot.img : `ECRAN=dsi SANS_VERROU=1 test-boot/build.sh … boot-arch-ecran.img`.

### Premier essai

```sh
fastboot flash boot_b boot-arch-ecran.img && fastboot reboot
# puis, root, téléphone démarré (SSH) :
insmod /root/panel-lgd-lh599qh3-edb1.ko
dmesg | grep -iE 'panel|dsi|dpu|msm|drm' | tail -40
ls /dev/dri /sys/class/drm
```

Si rien ne s'affiche : essayer la polarité inverse du reset (GPIO 6 active haute,
comme l'exemple de la liaison DT).

### ✅ Résultat du premier essai (11/10/2026, 21 h 55)

`insmod panel-lgd-lh599qh3-edb1.ko` → `msm_dpu … bound ae94000.dsi`,
`[drm] Initialized msm 1.13.0`, `fb0: msmdrmfb frame buffer device`, sortie
`card0-DSI-1` : **l'écran s'allume et affiche la console texte**. Premier affichage
du XZ3 sous un noyau mainline sans patch du noyau (pilote en module).

Reste : GPU (`a630_zap.mbn` à installer et tester), tactile (Atmel maXTouch),
ligne `DSI PLL(0) lock failed` au démarrage (avant le chargement du panneau, sans
effet visible).

Chargement automatique au démarrage :

```sh
M=/usr/lib/modules/$(uname -r)
install -D -m 644 /root/panel-lgd-lh599qh3-edb1.ko $M/updates/panel-lgd-lh599qh3-edb1.ko
depmod -a
```

## Tactile — ✅ fonctionne (12/10/2026)

Pilote officiel `atmel_mxt_ts` (absent de la configuration pmOS) compilé en module :
[`modules/atmel_mxt_ts/`](../modules/atmel_mxt_ts/). DTB :
[`dts/akatsuki-tactile.dtsi`](../dts/akatsuki-tactile.dtsi) (inclus avec `ECRAN=dsi`) —
`touchscreen@4a` sur l'I2C5 (`i2c@894000`), interruption GPIO 125 (niveau bas),
reset GPIO 99 (actif bas), `vdda` = LDO28, `vdd` = DCDC GPIO 133, d'après Hodina (2023).

```sh
insmod /root/atmel_mxt_ts.ko
dmesg | grep -i mxt
cat /proc/bus/input/devices | grep -A4 -i atmel
pacman -S --needed evtest && evtest      # toucher l'écran
```

**Validé le 12/10/2026** : `atmel_mxt_ts` se charge, le maXTouch répond sur l'I2C5 et
`evtest` reçoit les positions du doigt.

Chargement automatique des deux modules :

```sh
M=/usr/lib/modules/$(uname -r)
install -D -m 644 /root/panel-lgd-lh599qh3-edb1.ko /root/atmel_mxt_ts.ko -t $M/updates/
depmod -a
```
