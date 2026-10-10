# Patches de Petr Hodina (2023) — référence

Copies conservées telles quelles, **pas à appliquer directement** : elles visent le
noyau sdm845-mainline de 2023 et ne s'appliquent plus sur Linux 7.x (labels renommés,
ancienne syntaxe). Elles servent de base pour réécrire des patches propres.

## 0001 — « Enable multiple peripherals » (`9c5b9554`, 5 août 2023)

Comparaison avec le DTB du noyau pmOS 7.1 (`linux-postmarketos-qcom-sdm845-7.1_rc1-r4`) :

| Bloc | Patch 2023 | pmOS 7.1 | Pilote dans pmOS 7.1 | Bilan |
|---|---|---|---|---|
| ADSP, CDSP | activés + firmware | activés | ✅ | déjà fait |
| GPU (zap shader) | activé | activé (`&gpu_zap_shader`) | ✅ | déjà fait |
| MDSS | activé | activé | ✅ | déjà fait |
| **IPA** (données mobiles) | activé, `ipa_fws.mbn` | **désactivé** | module `ipa` | à essayer |
| **SLPI** (capteurs) | activé, `slpi.mbn` | **désactivé** | module `qcom_q6v5_pas` | à essayer |
| **Modem** (`mss_pil`) | activé, `mba.mbn` + `modem.mbn` | **désactivé** | module `qcom_q6v5_mss` | à essayer |

Réserves sur les trois blocs « à essayer » :

- En 2023, avec ce patch, le firmware SLPI manquait et les services du modem
  n'apparaissaient pas dans `qrtr-lookup` (ticket sonyxperiadev/bug_tracker #799).
- Konrad Dybcio a retiré l'IPA et le modem de sa série Tama upstream en 2023
  « parce qu'ils plantaient sans arrêt ».
- Risque : plantage ou redémarrage du téléphone, **pas** de brick (rien à voir avec l'UFS).

Détail utile : le contexte du patch montre un bloc `&pmi8998_charger { … }` dans sa
version du DTSI. Le DTB pmOS 7.1 contient ce nœud mais **désactivé**, et le noyau
fournit les pilotes `qcom_smbx` (charge) et `pmi8998_fg` (jauge de batterie) en modules.
La configuration de la charge et de la jauge est donc dans ses autres commits / fichiers.

## Fichiers DTS de la branche `sony/akatsuki`

`sdm845-sony-xperia-tama.dtsi` et `sdm845-sony-xperia-tama-akatsuki.dts`, téléchargés
depuis `gitlab.com/phodina/linux` (branche `sony/akatsuki`), conservés tels quels.

### Ce qu'ils ajoutent par rapport au DTB pmOS 7.1 (= DTS mainline)

| # | Ajout | Fichier | État du pilote dans pmOS 7.1 | Remarque |
|---|---|---|---|---|
| 1 | **Écran** : `compatible = "lgphilips,akatsuki"` + `reset-gpios` (GPIO 6, actif bas) | akatsuki.dts | ❌ absent | Remplacé depuis par le pilote de Marijn Suijten (voir plus bas) |
| 2 | **Tactile Atmel** `atmel,maxtouch` sur I2C5 @ `0x4a`, IRQ GPIO 125, reset GPIO 99, `vdda` = L28A, `vdd` = `ts_vddio` | akatsuki.dts | ❌ absent (`CONFIG_TOUCHSCREEN_ATMEL_MXT`) | Noyau à recompiler |
| 3 | **Charge** : `&pmi8998_charger` activé + batterie `simple-battery` 3325 mAh, 3,40–4,38 V | tama.dtsi | ✅ module `qcom_smbx` | **DTB seulement** |
| 4 | **Capteur de clapet** (Hall) GPIO 124 → `SW_LID` | tama.dtsi | ✅ `gpio-keys` | DTB seulement |
| 5 | **Wi-Fi** `&wifi` + alimentations + `qcom,snoc-host-cap-8bit-quirk` | tama.dtsi | ✅ module `ath10k_snoc` | DTB + firmwares |
| 6 | **Modem** `&mss_pil` (`mba.mbn`, `modem.mbn`) | tama.dtsi | ✅ module `qcom_q6v5_mss` | Ne marchait pas en 2023 |
| 7 | **Zone rmtfs du modem à `0xfdc01000`** (+ gardes) | tama.dtsi | — | **Indispensable au modem** : pmOS 7.1 la place à `0x88f00000` (valeur générique SDM845) |
| 8 | **IPA** (`ipa_fws.mbn`), **SLPI** (`slpi.mbn`) | tama.dtsi | ✅ modules | Instables en 2023 |
| 9 | Bluetooth (firmware `akatsuki/crnv21.bin`) | tama.dtsi | ✅ | Déjà fusionné en 2026 sous une autre forme |

Divers sans effet : états GPIO SIM / détection d'eau / HWID, `debug_mem`,
`&adsp_pas` en double, ancienne syntaxe `zap-shader`, `serial0 = &uart6` (corrigé
upstream en 2026).

### Le pilote d'écran officiel est en cours de relecture

Marijn Suijten (SoMainline) a envoyé en décembre 2025 une série v2 de 11 patches
pour des écrans Sony, dont **`drm/panel: Add LGD LH599QH3-EDB1 panel driver for Sony
Xperia XZ3`** : écran LG 1440 × 2880 à 60 Hz, **compression DSC 1.1 obligatoire**,
`compatible = "lgd,lh599qh3-edb1-um1"`, fichier `panel-lgd-lh599qh3-edb1.c`,
option `DRM_PANEL_LGD_LH599QH3_EDB1`.

Vérifié le 10 octobre 2026 : **pas encore dans le noyau officiel** (ni le pilote ni sa
liaison DT), alors que la liaison `samsung,sofef01-m` de la même série y est.
C'est cette version qu'il faudra reprendre, pas `lgphilips,akatsuki` de 2023.

https://lkml.iu.edu/hypermail/linux/kernel/2512.2/06952.html
