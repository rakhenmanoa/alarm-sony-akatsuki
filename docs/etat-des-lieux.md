# État des lieux — Xperia XZ3 sur noyau mainline

Synthèse du travail existant au 10 octobre 2026.

## Chronologie

| Date | Étape |
|---|---|
| Nov. 2021 | Konrad Dybcio ajoute la plateforme Tama (XZ2, XZ2C, XZ3) au noyau mainline, UFS volontairement désactivé |
| Juin 2023 | Petr Hodina ouvre le brouillon pmaports **!4183** : démarre, mais bloque faute d'UFS |
| Juin 2023 | Ticket Sony **bug_tracker #799** : identification du correctif UFS du noyau d'origine |
| Été 2023 | Brouillon noyau **sdm845-mainline !73** : écran, tactile, jauge et charge OK |
| Sept. 2023 | Démarrage complet sur **carte SD** avec interface graphique (noyau 6.4) |
| Fév. 2026 | Ajout du XZ3 à **Mobile NixOS** (PR #862), linux-next 6.19, démarrage sur carte SD |
| Mars 2026 | Ticket #799 fermé (UFS toujours non résolu) |

## Matériel (d'après les journaux de 2023)

| Composant | État | Notes |
|---|---|---|
| Écran OLED (DSI) | ✅ | Avec les patches sdm845-mainline ; **pas de pilote de panneau dans le DTS mainline** |
| Tactile Atmel maXTouch | ✅ | 1440×2880 ; absent du DTS mainline (le nœud Synaptics y est supprimé) |
| GPU Adreno 630 | ✅ | Firmwares `a630_sqe.fw`, `a630_gmu.bin` |
| Jauge batterie, charge | ✅ | |
| Vibreur | ✅ | `pmi8998_haptics` |
| ADSP, CDSP | ✅ | Démarrent |
| Carte SD | ✅ | SDR104 |
| USB réseau | ✅ | |
| UFS | ⛔ | Désactivé : risque de brick |
| Modem | ❌ | `modemst1/2` évitent les plantages, mais aucun service modem dans `qrtr-lookup` |
| Son | ❌ | Pas de DAI dans le DTS |
| Capteurs (SLPI) | ❌ | `slpi.mbn` manquant ; travail en cours sur `sensors-porting` |
| Wi-Fi, Bluetooth | ❌ | Pilotes chargés, non fonctionnels |
| Appareil photo | ❌ | Rien de fait |

## Ce que contient le DTS mainline (Linux 7.3, octobre 2026)

Activés dans `sdm845-sony-xperia-tama.dtsi` : ADSP, CDSP, GPU, MDSS/DSI (panneau sans
`compatible` pour le XZ3), carte SD, UART6 (Bluetooth), UART9 (console de débogage),
USB (périphérique, high-speed), Venus.

Absents pour le XZ3 : pilote du panneau OLED, tactile Atmel, Wi-Fi, modem (MPSS),
SLPI, son, jauge et charge.

## Portage Mobile NixOS (référence la plus récente)

Branche `sdm845-devices` de `github.com/phodina/mobile-nixos-next` :

- noyau `codeberg.org/sdm845/linux`, commit `dc7b19cffd9ef96b28da5441061ff26dce1025a6`
  (linux-next 6.19, next-20260106), `defconfig` + `sdm845.config`, non modulaire ;
- firmwares : `gitlab.com/phodina/firmware-sony-akatsuki` (arborescence postmarketOS) ;
- `modem.mbn` retiré de l'initramfs (trop gros) ;
- `a630_sqe.fw` et `a630_gmu.bin` copiés depuis `linux-firmware` ;
- USB : adb, mass storage, rndis.

## Le problème UFS

- Commit du noyau d'origine : `sailfishos-sony-tama/android_kernel_sony_msm@cfd1489`
  (Angelo G. Del Regno, 2019), « scsi: ufs: Forward port Yoshino/Tama UFS quirks/hacks ».
- D'après Marijn Suijten (SoMainline), un portage mainline existe mais n'a jamais été testé.
- Piste évoquée par Petr Hodina : sauvegarder l'UFS depuis Android, démarrer sur SD,
  charger le pilote UFS **en module**, et restaurer avec `dd` avant tout redémarrage
  en cas d'effacement. Jamais testée ; marge d'erreur quasi nulle.

## Sources

- https://github.com/sonyxperiadev/bug_tracker/issues/799
- https://gitlab.com/sdm845-mainline/linux/-/merge_requests/73
- https://gitlab.com/postmarketOS/pmaports/-/merge_requests/4183
- https://github.com/mobile-nixos/mobile-nixos/pull/862
- https://lkml.rescloud.iu.edu/2111.2/05327.html
