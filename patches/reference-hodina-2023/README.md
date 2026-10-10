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
