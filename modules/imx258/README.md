# Module imx258 (caméra avant du Xperia XZ3)

`imx258.c` : copie de `drivers/media/i2c/imx258.c` de Linux v7.1-rc1
(pilote officiel du capteur Sony IMX258, **avec un correctif** :
[`0001-imx258-reset-gpio.patch`](0001-imx258-reset-gpio.patch) — le pilote d'origine ne
gère pas la broche de reset (XCLR) : sur le XZ3 le capteur restait en reset et ne
répondait pas en I2C ; ajout de `reset-gpios`, sortie de reset 1 ms après l'horloge,
puis 10 ms d'attente ; `CONFIG_VIDEO_IMX258` n'est pas activé dans
le noyau pmOS). Dépend de `videodev`, `v4l2-cci`, `v4l2-fwnode`, `v4l2-async`
(présents dans le noyau pmOS ; tous les symboles vérifiés).

```sh
~/noyau-7.1-rc1/construire-module.sh modules/imx258
```

Description matérielle : [`dts/akatsuki-camera-avant.dtsi`](../../dts/akatsuki-camera-avant.dtsi)
(`CAMERA=1 scripts/build-dtb.sh`).
