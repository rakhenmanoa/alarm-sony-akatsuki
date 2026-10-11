# Module panel-lgd-lh599qh3-edb1 (écran du Xperia XZ3)

Pilote de Marijn Suijten (SoMainline), série « drm/panel: Add 5 DDIC panel drivers
for 14 Sony phones » v2 (22/12/2025), patches 02 (liaison DT) et 03 (pilote),
conservés tels quels ici. Message-ID du pilote :
`20251222-drm-panels-sony-v2-3-82a87465d163@somainline.org`. Relu par Linus Walleij
(Reviewed-by), pas encore fusionné au 11/10/2026.

`panel-lgd-lh599qh3-edb1.c` est extrait du patch 03 sans modification.

Compilation (PC x86_64) :

```sh
scripts/preparer-arbre-noyau.sh config-akatsuki ~/noyau-7.1-rc1
~/noyau-7.1-rc1/construire-module.sh modules/panel-lgd-lh599qh3-edb1
```

Les 33 symboles importés sont tous exportés par le noyau pmOS 7.1-rc1 (vérifié avec
les symboles extraits de son image).
