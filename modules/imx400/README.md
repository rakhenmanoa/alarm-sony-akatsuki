# Module imx400 (caméra arrière du Xperia XZ3)

Pilote V4L2 du capteur **Sony IMX400** (19 Mpx, module SOI20BS2). Aucun pilote Linux
n'existe pour ce capteur et Sony n'en publie pas les registres : le pilote rejoue
les séquences que le pilote de Sony écrit sous Android, enregistrées **sur votre
téléphone** et lues dans `/usr/lib/firmware/sony/imx400-akatsuki.bin`. Ce fichier
n'est pas dans le dépôt (comme les autres fichiers Sony).

## 1. Construire le fichier de séquences (PC, téléphone sous LineageOS)

Débogage USB + débogage root activés :

```sh
scripts/capturer-camera-adb.sh arriere
# → capture-camera/imx400-akatsuki.bin
```

Le script active la journalisation du contrôleur I2C de la caméra (bit `CAM_CCI`
de `debug_mdl`), ouvre l'appareil photo (prendre une photo, fermer l'application),
puis [`decoder-cci.py`](../../scripts/decoder-cci.py) reconstitue les écritures et
[`imx400-sequences.py`](../../scripts/imx400-sequences.py) en tire :

- l'initialisation (dont un correctif du microcontrôleur du capteur, en 0xf800) ;
- un bloc par mode vu pendant la capture, avec sa géométrie.

Capture du 13/10/2026 :

| Mode | Recadrage | Binning | Images/s max |
|---|---|---|---|
| 1344×756 | (64,384)–(5439,3423) | 4×4 | 120 |
| 2752×1552 | (0,352)–(5503,3455) | 2×2 | 61 |
| 2528×1896 | (216,0)–(5287,3807) | 2×2 | 52 (aperçu de Sony, 30 i/s) |
| 5056×3792 | (216,0)–(5287,3807) | — | 21 (photo) |

Toutes à `llp` 5744, `pixel_rate` 2,667 GHz (VT : 8 MHz × 250 × 4 / 3 ; vérifié :
30,0 i/s mesurés à `fll` 15475), lien CSI-2 4 voies à 676 MHz (8 MHz × 169 / 2), RAW10.

## 2. Pilote

- alimentations `vana` (GPIO 27), `vif` (vio, GPIO 12 du PMI8998), `vaf` (L19, 2,7 V ; pas encore décrite dans le DTB : l'activer empêche le démarrage, voir le .dtsi),
  horloge MCLK0, reset GPIO 80 ; ordre de Sony ;
- horloge à 24 MHz (le SDM845 ne sait pas faire les 8 MHz de Sony) : le pilote
  corrige `0x0136` et multiplie par 3 les pré-diviseurs des PLL (`0x0305`, `0x030d`) ;
- au démarrage du flux : initialisation (une fois par mise sous tension), bloc du
  mode, gains de balance des blancs du capteur à 1, contrôles, puis `0x0100 = 1` ;
- contrôles : exposition (`0x0202`, lignes), gain analogique (`0x0204`, 0…960),
  gain numérique (`0x020e`…), `vblank` (`0x0340`), `hblank` (fixe).

Pas encore : autofocus et stabilisateur (puce 0x76 sur le même bus), retournement,
données PDAF.

Premier essai (13/10/2026, `boot-arch-13`) : flux 2528×1896 à la première tentative
après le plafonnement du `pixel_rate` ; image nette de contenu mais floue (objectif au
repos, sans autofocus) ; ordre de Bayer **RGGB** confirmé (bois orangé, peau).

```sh
~/noyau-7.1-rc1/construire-module.sh modules/imx400
```

## 3. Essai (téléphone, root)

```sh
KO=modules/precompiles/$(uname -r)/imx400.ko SEQ=…/imx400-akatsuki.bin \
    sh scripts/installer-camera-arriere.sh
# démarrer une image construite avec CAMERA_ARRIERE=1, puis :
sh scripts/tester-camera-arriere.sh
```

⚠️ Avec `CAMERA_ARRIERE=1`, CAMSS attend aussi ce capteur : sans le module ou sans le
fichier de séquences, la caméra avant ne s'ouvre plus. Description matérielle :
[`dts/akatsuki-camera-arriere.dtsi`](../../dts/akatsuki-camera-arriere.dtsi).
