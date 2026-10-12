# Module imx258 (caméra avant du Xperia XZ3)

`imx258.c` : copie sans modification de `drivers/media/i2c/imx258.c` de Linux v7.1-rc1
(pilote officiel du capteur Sony IMX258 ; `CONFIG_VIDEO_IMX258` n'est pas activé dans
le noyau pmOS). Dépend de `videodev`, `v4l2-cci`, `v4l2-fwnode`, `v4l2-async`
(présents dans le noyau pmOS ; tous les symboles vérifiés).

```sh
~/noyau-7.1-rc1/construire-module.sh modules/imx258
```

Description matérielle : [`dts/akatsuki-camera-avant.dtsi`](../../dts/akatsuki-camera-avant.dtsi)
(`CAMERA=1 scripts/build-dtb.sh`).
