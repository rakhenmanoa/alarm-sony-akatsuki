# U-Boot pour le Xperia XZ3 (akatsuki)

But : flasher **une seule fois** U-Boot dans `boot_b` ; U-Boot démarre ensuite le noyau,
le DTB et l'initramfs rangés sur la carte micro-SD (`/boot/akatsuki/`, menu
`/boot/extlinux/extlinux.conf`). Changer de noyau ne demande plus de fastboot, et le
noyau précédent reste proposé dans le menu (Volume bas maintenu au démarrage).

| Fichier | Rôle |
|---|---|
| `akatsuki.config` | fragment après `qcom_defconfig` : DTB akatsuki, **sans UFS / SCSI / fastboot** |
| `akatsuki.env` | environnement : `bootflow scan` (extlinux), menu, Volume bas |
| `akatsuki-u-boot.dtsi` | écran (simple-framebuffer avec `reg`, image du chargeur Sony) |
| `xxd-mini.py` | remplaçant de `xxd -i` pour la compilation |
| `entete-image.py` | en-tête Linux de l'image : `text_offset` 0x80000 (sinon ABL ne la lance pas) |
| `patches/0001-snapdragon-couper-mmu-abl.patch` | hypothèse en cours de vérification : ABL de Sony saute avec la MMU allumée (ses tables ne couvrent pas toute la mémoire) : U-Boot gelait en se relogeant en haut de la RAM. Le correctif nettoie le cache et coupe la MMU à l'entrée, comme Linux |

⚠️ Sur Tama, un pilote UFS peut effacer le bootloader. U-Boot est donc compilé sans
aucun pilote UFS/SCSI (le script refuse sinon), et son DTB passe `check-dtb-ufs.sh`.

## Construire (PC)

```sh
scripts/construire-u-boot.sh u-boot-akatsuki.img          # U-Boot v2026.07
GARDER=pieces …flags habituels… test-boot/build.sh <noyau.apk> boot-akatsuki.img
```

## Essayer (sans rien flasher)

```sh
# téléphone, root : pièces du noyau sur la carte
sh scripts/installer-u-boot-carte.sh /chemin/pieces
# PC, téléphone en fastboot
fastboot boot u-boot-akatsuki.img
```

U-Boot doit afficher son logo/texte, trouver `extlinux.conf` sur la carte et démarrer
Arch comme d'habitude. Si ça marche, `fastboot flash boot_b u-boot-akatsuki.img`.
Retour : reflasher l'image habituelle (`boot-arch-*.img`).

## Mise au point (13/10/2026)

Recherche par dichotomie avec des images qui redémarrent (PSCI `SYSTEM_RESET`) à une
étape donnée : U-Boot passait tout `board_init_f`, puis gelait pendant la copie vers le
haut de la mémoire (0x17e2c0000 annoncé par ABL, une seule banque depuis 0x80000000).
