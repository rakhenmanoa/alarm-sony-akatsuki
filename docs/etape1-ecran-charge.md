# Étape 1 — Écran (simple-framebuffer) et charge, sans recompiler le noyau

## Construire le DTB

**Méthode principale — avec `dtc`** (paquet `dtc` sur Arch) :

```sh
scripts/build-dtb.sh \
    x/boot/dtbs/qcom/sdm845-sony-xperia-tama-akatsuki.dtb \
    akatsuki-fb-charge.dtb
```

Le script décompile le DTB du noyau pmOS, y ajoute le fragment source
[`dts/akatsuki-ecran-charge.dtsi`](../dts/akatsuki-ecran-charge.dtsi), recompile,
et affiche les différences. Il refuse d'écrire la sortie si l'UFS est actif (entrée
ou sortie, y compris si un fragment tentait de le réactiver) ou si le DTB n'est pas
celui du XZ3.

On part du DTB **binaire** de pmOS plutôt que des sources du noyau : celles du noyau
pmOS (arbre SDM845 sur Codeberg) ne sont pas forcément identiques au noyau officiel,
et le DTB doit correspondre exactement au noyau qui démarre. Le DTB pmOS n'ayant pas
de labels, le fragment désigne les nœuds par leur chemin (`&{/soc@0/...}`).

**Méthode de secours — sans `dtc`** (Python 3 seul) :

```sh
python3 scripts/patch-dtb-akatsuki.py \
    sdm845-sony-xperia-tama-akatsuki.dtb \
    akatsuki-fb-charge.dtb
```

Mêmes garde-fous, plus le refus d'une double application.

**Validation croisée** (DTB pmOS `7.1_rc1-r4`, dtc 1.7.2 compilé depuis le dépôt
officiel) : les deux méthodes donnent un contenu **identique** une fois décompilé
par `dtc`, sans nouvel avertissement de `dtc`.

## Ce qui change dans le DTB

| Modification | Pourquoi |
|---|---|
| `/chosen/framebuffer` : `simple-framebuffer`, 1440 × 2880, `a8r8g8b8`, stride 5760, sur `cont_splash_mem` (`0x9d400000`) | Réutiliser l'écran que le bootloader laisse allumé (pilote `simplefb`, intégré au noyau pmOS 7.1) |
| Alimentations tenues par le framebuffer : L14A (E/S panneau), `ts_vddio` (DCDC de l'OLED), L26A (DSI), L1A (PHY DSI) | Empêcher Linux de couper l'écran en éteignant les « régulateurs inutilisés » |
| MDSS et `dispcc` désactivés | Le pilote d'affichage ne doit pas reprendre la main (même méthode que le Poco F1) |
| `/battery` : `simple-battery` 3325 mAh, 3,40–4,38 V | Valeurs du DTS de Petr Hodina (2023) |
| Chargeur PMI8998 activé, `monitored-battery` → `/battery` | Pilote `qcom_smbx` (module du noyau pmOS 7.1) |

Vérifications faites sur le DTB du paquet `linux-postmarketos-qcom-sdm845-7.1_rc1-r4` :
aller-retour sans modification identique au décodage indépendant ; seules les lignes
ci-dessus changent ; nouveaux phandles `0x100`–`0x102` (le maximum existant était `0xff`).

## Tester sans rien écrire sur le téléphone

Avec le noyau et l'initramfs pmOS (ou Arch), rootfs sur la carte SD :

```sh
scripts/make-bootimg.sh vmlinuz akatsuki-fb-charge.dtb initramfs boot-test.img \
    "root=LABEL=... rootwait"
fastboot boot boot-test.img        # temporaire : rien n'est flashé
```

## Ce qu'il faut observer

**Écran**

| Ce que tu vois | Signification | Action |
|---|---|---|
| Le logo Sony reste, puis le texte de la console Linux apparaît | ✅ simplefb fonctionne | — |
| Image décalée, en biais ou rayée | Le `stride` ou le `format` ne correspond pas | Me donner une photo : on ajuste `WIDTH*4` ou le format |
| L'image tient quelques secondes puis noir | Une horloge ou une alimentation est coupée tardivement | Ajouter à la ligne de commande : `clk_ignore_unused pd_ignore_unused regulator_ignore_unused` |
| Noir dès le début | Le bootloader éteint l'écran avant Linux, ou mauvaise adresse | Accès par USB / UART pour lire `dmesg` |

Hypothèse à confirmer : le format `a8r8g8b8` sans marge de ligne est celui du Poco F1 ;
pour le XZ3, c'est très probable mais pas vérifié.

**Charge** (par USB réseau / SSH) :

```sh
dmesg | grep -i -E 'smb|charger|battery'
ls /sys/class/power_supply/
cat /sys/class/power_supply/*/status /sys/class/power_supply/*/voltage_now 2>/dev/null
```

⚠️ Premiers essais de charge **sous surveillance** : téléphone posé sur une surface
non inflammable, et débranchement si le téléphone chauffe anormalement.
La tension maximale (4,38 V) reprend la valeur de Petr Hodina, légèrement sous la
limite habituelle de ce type de cellule.

## Rien ne touche à l'UFS

Les deux nœuds UFS restent en `status = "disabled"` ; vérifié par le script lui-même
(entrée, sortie, relecture du fichier produit) et par `scripts/check-dtb-ufs.sh`.
