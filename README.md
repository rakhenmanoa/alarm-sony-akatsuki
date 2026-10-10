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
| `arch/linux-sony-akatsuki-pmos/` | PKGBUILD Arch : noyau 7.1 de postmarketOS reconditionné (refuse de se construire si l'UFS est actif) |
| `scripts/fetch-pmos-kernel.sh` | Trouve et télécharge la version actuelle du noyau pmOS, met à jour le PKGBUILD |
| `dts/akatsuki-ecran-charge.dtsi` | Étape 1 (source) : écran (simple-framebuffer) et charge, fragment à appliquer au DTB pmOS |
| `scripts/build-dtb.sh` | Construit le DTB modifié avec `dtc` (base pmOS + fragments de `dts/`), garde-fou UFS entrée et sortie |
| `scripts/patch-dtb-akatsuki.py` | Secours sans `dtc` : même résultat que `build-dtb.sh` (vérifié identique), en Python seul |
| `scripts/check-dtb-ufs.sh` | Garde-fou : refuse tout DTB où l'UFS est actif |
| `scripts/make-bootimg.sh` | Assemble un `boot.img` (noyau + DTB + initramfs) avec les bons offsets |
| `scripts/make-first-bootimg.sh` | `boot.img` du premier démarrage : initramfs vide, système monté directement depuis la carte SD |
| `scripts/prepare-sdcard.sh` | Prépare la carte micro-SD : Arch Linux ARM + modules pmOS + réseau USB (nombreux garde-fous) |
| `rootfs/` | Configuration copiée sur la carte : gadget USB NCM, `systemd-networkd` (172.16.42.1), `fstab`, nom d'hôte |
| `docs/etat-des-lieux.md` | Ce qui fonctionne déjà, ce qui manque, sources |
| `docs/noyau-pmos-7.1.md` | Analyse du noyau pmOS 7.1 et de son DTB (décompilé dans `docs/dts/`) |
| `docs/patches-petr-hodina.md` | Inventaire des patches de Petr Hodina (fusionnés, en attente, à récupérer) |
| `docs/premier-demarrage.md` | **Premier démarrage pas à pas** : carte SD, DTB, `fastboot boot`, SSH par USB |
| `docs/etape1-ecran-charge.md` | Étape 1 : écran + charge, procédure de test et ce qu'il faut observer |
| `patches/reference-hodina-2023/` | Patches de 2023 récupérés, conservés tels quels avec leur analyse |

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

**Le plus simple pour commencer : [docs/premier-demarrage.md](docs/premier-demarrage.md)**
(carte SD préparée par script, sans initramfs ni paquet à construire).

Installation par paquet (à terme) :

Même noyau que postmarketOS (`linux-postmarketos-qcom-sdm845`, 7.1), reconditionné
en paquet Arch, avec un rootfs Arch Linux ARM aarch64 sur la carte SD.

**1. Récupérer le noyau pmOS et construire le paquet Arch** (sur le PC) :

```sh
scripts/fetch-pmos-kernel.sh                 # télécharge le .apk, met à jour pkgver et sha256sums
cd arch/linux-sony-akatsuki-pmos
sed 's/^CARCH=.*/CARCH="aarch64"/' /etc/makepkg.conf > /tmp/makepkg-aarch64.conf
makepkg -A --config /tmp/makepkg-aarch64.conf
```

Aucune compilation : le binaire de postmarketOS est repris tel quel. La construction
échoue volontairement si le DTB du XZ3 active l'UFS (`check()` et `package()`).

**2. Installer le paquet dans le rootfs Arch** (carte SD montée sur `/mnt`,
`qemu-user-static` nécessaire sur un PC x86) :

```sh
sudo cp linux-sony-akatsuki-pmos-*.pkg.tar.zst /mnt/root/
sudo arch-chroot /mnt pacman -U /root/linux-sony-akatsuki-pmos-*.pkg.tar.zst
```

Le hook pacman de mkinitcpio copie le noyau en `/boot/vmlinuz-linux-sony-akatsuki-pmos`
et génère `/boot/initramfs-linux-sony-akatsuki-pmos.img`.

**3. Assembler et démarrer le `boot.img`** :

```sh
scripts/make-bootimg.sh \
    /mnt/boot/vmlinuz-linux-sony-akatsuki-pmos \
    /mnt/boot/dtbs/qcom/sdm845-sony-xperia-tama-akatsuki.dtb \
    /mnt/boot/initramfs-linux-sony-akatsuki-pmos.img \
    boot-arch.img "root=LABEL=ALARM_ROOT rootwait rw"
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
