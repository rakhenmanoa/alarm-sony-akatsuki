# Écran (en cours, 11/10/2026)

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
