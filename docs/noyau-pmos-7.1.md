# Analyse du noyau postmarketOS 7.1 pour le XZ3

Paquet analysé : `linux-postmarketos-qcom-sdm845-7.1_rc1-r4.apk`

| Élément | Valeur |
|---|---|
| sha256 du .apk | `d0b4b950a500cede73fe5ce094060b1f9d608e3b4cbcb9d59bf2d876b2dc9804` |
| Date de compilation | 14 juillet 2026, 02:44:55 UTC (identique à l'index pkgs) |
| Version du noyau | `7.1.0-rc1-sdm845`, compilé avec clang 22.1.8 |
| `/boot/vmlinuz` | déjà compressé en gzip (convient au bootloader) |
| Modules | `/usr/lib/modules/7.1.0-rc1-sdm845/` (1155 modules, `.ko.zst`) |
| DTB du XZ3 | `boot/dtbs/qcom/sdm845-sony-xperia-tama-akatsuki.dtb` |
| sha256 du DTB | `fbb38e8dbb9639140930a5c8a5e148cfbf9514102f015ecddae41bb79fd52142` |

DTB décompilé : [dts/sdm845-sony-xperia-tama-akatsuki.pmos-7.1_rc1-r4.dts](dts/sdm845-sony-xperia-tama-akatsuki.pmos-7.1_rc1-r4.dts)
(phandles numériques : le DTB ne contient pas les noms des labels).

## Sécurité UFS

`ufshc@1d84000` et `phy@1d87000` : `status = "disabled"`. ✅

⚠️ Les pilotes UFS (`ufs-qcom`, `ufshcd-core`, `ufshcd-pltfrm`) sont **intégrés au noyau**.
La seule protection est donc le `status = "disabled"` du DTB : ne jamais démarrer ce noyau
avec un DTB modifié sans passer `scripts/check-dtb-ufs.sh`.

## Comparaison avec le DTS officiel (Linux 7.3)

Les blocs activés sont **exactement les mêmes** que dans le DTS mainline :
ADSP, CDSP, GPU Adreno 630, MDSS + DSI + PHY DSI, GPI DMA ×2, QUP ×2,
I2C5 (tactile), I2C10, I2C14, UART6 (Bluetooth WCN3990), UART9 (console),
carte SD, USB (périphérique, USB 2.0), Venus.

Aucun ajout propre au XZ3 :

| Composant | Dans le DTB | Pilote dans le noyau |
|---|---|---|
| Écran OLED | nœud `panel@0` **sans `compatible`** → aucun pilote ne s'y attache | aucun pilote de panneau Sony |
| Tactile Atmel | **absent** (bus I2C5 vide) | **absent** (ni intégré ni module) |
| `simple-framebuffer` | absent | **intégré** (`simplefb`) |
| Wi-Fi WCN3990 | `disabled` | modules `ath10k_snoc`, `ath10k_core` |
| Modem | `disabled` | module `qcom_q6v5_mss` |
| Capteurs (SLPI) | `disabled` | — |
| Vibreur | `disabled` | module `qcom-spmi-haptics` |
| Son | nœud `sound` vide | — |

## Conséquences pour le portage

1. **Premier démarrage : écran noir attendu.** Accès par USB (réseau) ou console UART9.
2. **Affichage rapide possible sans pilote de panneau** : `simplefb` est intégré, il suffit
   d'ajouter au DTB un nœud `simple-framebuffer` sur la zone `cont_splash_mem`
   (`0x9d400000`, laissée allumée par le bootloader). Modification du DTB uniquement.
3. **Tactile** : demandera un noyau recompilé (`CONFIG_TOUCHSCREEN_ATMEL_MXT`) en plus du nœud DTS.
4. **Wi-Fi et modem** : les pilotes existent en modules ; il manque les nœuds DTS et les firmwares.
