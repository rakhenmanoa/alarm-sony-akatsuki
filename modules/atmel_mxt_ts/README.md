# Module atmel_mxt_ts (tactile du Xperia XZ3)

`atmel_mxt_ts.c` : copie sans modification de `drivers/input/touchscreen/atmel_mxt_ts.c`
de Linux v7.1-rc1 (pilote officiel ; `CONFIG_TOUCHSCREEN_ATMEL_MXT` n'est pas activé
dans le noyau pmOS). Les 60 symboles importés sont exportés par le noyau pmOS.

```sh
~/noyau-7.1-rc1/construire-module.sh modules/atmel_mxt_ts
```
