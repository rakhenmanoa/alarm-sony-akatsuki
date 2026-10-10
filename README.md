# alarm-sony-akatsuki

**Arch Linux ARM** sur le Sony Xperia XZ3 (H8416 / H9436 / H9493, nom de code *akatsuki*,
SoC Snapdragon 845), avec un noyau mainline.

postmarketOS sert de première étape pour valider le démarrage (noyau, DTB, `boot.img`,
carte SD) grâce à son shell de débogage par USB ; le rootfs est ensuite remplacé par
Arch Linux ARM.

Ce projet reprend le travail de **Petr Hodina** (phodina), qui a fait démarrer le XZ3
sur noyau mainline en 2023 (postmarketOS) puis en 2026 (Mobile NixOS).
Voir [docs/etat-des-lieux.md](docs/etat-des-lieux.md).

## ⚠️ Avertissement : ne jamais activer l'UFS

Sur la plateforme Sony Tama (XZ2, XZ2 Compact, XZ3), le pilote UFS mainline envoie au
démarrage une commande qui **efface toute la mémoire interne, bootloader compris**.
Le téléphone est alors perdu définitivement, sans aucun moyen de récupération.

Le noyau officiel désactive donc l'UFS dans le DTS :

```
/* BIG WARNING! DO NOT TOUCH UFS, YOUR DEVICE WILL DIE! */
&ufs_mem_hc { status = "disabled"; };
&ufs_mem_phy { status = "disabled"; };
```

Règles du projet :

1. **Ne jamais** modifier ces deux lignes, ni utiliser un DTB qui les modifie.
2. Le système (rootfs) est installé **sur la carte micro-SD**.
3. Avant chaque nouveau noyau, lancer le garde-fou :
   ```sh
   scripts/check-dtb-ufs.sh sdm845-sony-xperia-tama-akatsuki.dtb
   ```
4. Tester avec `fastboot boot` (temporaire), jamais `fastboot flash`, tant que rien n'est validé.

Le correctif Sony existe dans le noyau d'origine (commit `cfd1489` du noyau Sailfish Tama,
« Forward port Yoshino/Tama UFS quirks/hacks ») mais n'a jamais été porté ni testé en mainline.

## Contenu du dépôt

| Chemin | Rôle |
|---|---|
| `pmos/device-sony-akatsuki/` | Paquet appareil postmarketOS (`deviceinfo`, `APKBUILD`) — brouillon |
| `pmos/firmware-sony-akatsuki/` | Paquet des firmwares, depuis le dépôt de Petr Hodina — brouillon |
| `scripts/check-dtb-ufs.sh` | Garde-fou : refuse tout DTB où l'UFS est actif |
| `scripts/make-bootimg.sh` | Assemble un `boot.img` (noyau + DTB + initramfs) avec les bons offsets |
| `docs/etat-des-lieux.md` | Ce qui fonctionne déjà, ce qui manque, sources |

## Paramètres de démarrage

Repris du portage Mobile NixOS (famille `sdm845-mainline`) :

| Paramètre | Valeur |
|---|---|
| base | `0x00000000` |
| kernel offset | `0x00008000` |
| ramdisk offset | `0x01000000` |
| tags offset | `0x00000100` |
| pagesize | `4096` |
| DTB | ajouté à la suite du noyau (`Image.gz` + `.dtb`) |
| DTB mainline | `qcom/sdm845-sony-xperia-tama-akatsuki.dtb` |
| Slots | A/B |

## Piste 1 — postmarketOS

```sh
cp -r pmos/* "$(pmbootstrap config aports)"/device/testing/
pmbootstrap checksum device-sony-akatsuki firmware-sony-akatsuki
pmbootstrap init                       # vendor: sony, device: akatsuki
pmbootstrap initfs hook_add debug-shell
pmbootstrap install --sdcard=/dev/sdX  # vérifier le /dev avant !
# téléphone en fastboot (Volume haut + USB, LED bleue), carte SD insérée :
pmbootstrap flasher boot
telnet 172.16.42.1                     # shell de débogage par USB
```

## Piste 2 — Arch Linux ARM

Même noyau et même DTB, rootfs Arch Linux ARM aarch64 sur la carte SD :

```sh
scripts/make-bootimg.sh Image.gz sdm845-sony-xperia-tama-akatsuki.dtb \
    initramfs.img boot-arch.img "root=LABEL=ALARM_ROOT rootwait rw"
fastboot boot boot-arch.img
```

Conseil : valider d'abord le démarrage avec postmarketOS (débogage USB fourni),
puis remplacer le rootfs par Arch.

## Modes du téléphone

| Mode | Combinaison | LED |
|---|---|---|
| Fastboot | Volume haut + branchement USB | bleue |
| Flash (Newflasher / Flashtool) | Volume bas + branchement USB | verte |
| Extinction forcée | Power + Volume haut jusqu'à 3 vibrations | — |

## État

Brouillons non testés. Voir les tickets / issues pour l'avancement.

## Crédits

- Petr Hodina — portages postmarketOS (2023) et Mobile NixOS (2026), firmwares
- Konrad Dybcio, Marijn Suijten (SoMainline) — support Tama dans le noyau mainline
- Communauté sdm845-mainline et postmarketOS
