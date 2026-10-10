# Patches de Petr Hodina pour le Xperia XZ3

Inventaire au 10 octobre 2026. Classés du plus utile au moins utile pour ce portage.

## 1. Fusionnés dans Linux (déjà dans le noyau pmOS 7.1)

Série « Enable uart and bluetooth for Xperia devices » (v2, 20 janvier 2026),
relue par David Heidelberg, Konrad Dybcio et Dmitry Baryshkov,
**appliquée par Bjorn Andersson le 23 mars 2026**.

| Patch | Effet |
|---|---|
| `arm64: dts: qcom: sdm845-sony-xperia-tama: Correct uart instances` | `serial0` = UART9 : la console série fonctionne en se branchant sur la broche Rx du connecteur micro-SD |
| `arm64: dts: qcom: sdm845-sony-xperia-tama: Add bluetooth` | Bluetooth WCN3990 sur UART6, firmware `Sony/tama/crnv21.bin` |

Vérifié présent dans le DTB du paquet `linux-postmarketos-qcom-sdm845-7.1_rc1-r4`.
**Rien à faire de notre côté.**

Fil : https://ratatoskr.run/lkml/2026/01/3377628/t

## 2. Recette simple-framebuffer (Poco F1, même SoC, même zone mémoire)

Série « Add framebuffer on Xiaomi Poco F1… » (11 mars 2026), envoyée par
David Heidelberg avec des patches de Petr Hodina. **Non fusionnée** (en attente).

Le Poco F1 utilise la même zone `cont_splash_mem` à `0x9d400000` que le XZ3.
Nœud utilisé :

```dts
chosen {
	#address-cells = <2>;
	#size-cells = <2>;
	ranges;

	framebuffer {                       /* sans "@adresse" : remarque de Konrad Dybcio */
		compatible = "simple-framebuffer";
		memory-region = <&cont_splash_mem>;
		format = "a8r8g8b8";
		stride = <(1080 * 4)>;
		height = <2246>;
		width = <1080>;
	};
};
```

Le second patch désactive `&mdss` et `&dispcc` pour que le pilote d'affichage ne
reprenne pas la main sur l'écran et que le framebuffer reste actif.

**Base directe de notre patch d'affichage pour le XZ3** (1440 × 2880, stride 1440 × 4).
`simplefb` est intégré au noyau pmOS 7.1.

Fil : https://ratatoskr.run/lkml/2026/03/3453944/t

## 3. Pilote du capteur de couleur AMS TCS3400 (non fusionné)

Série « iio: light: add AMS TCS3400 driver » (19 janvier 2026) : pilote IIO et nœud
sur l'I2C14 des Tama (adresse 0x39, interruption GPIO11). Revue très critique
(liaison DT invalide, ABI sysfs non standard, gestion du trigger incorrecte),
non reprise depuis. Priorité basse.

Fil : https://ratatoskr.run/lkml/2026/01/3376206/t

## 4. Le portage de 2023 — non récupéré

Branche `sony/akatsuki` de `gitlab.com/phodina/linux`, proposée dans
sdm845-mainline !73 (« Port to Sony Xperia XZ3 », toujours en brouillon) :
écran, tactile Atmel, jauge et charge fonctionnels selon son auteur.

C'est la partie la plus précieuse, mais GitLab bloque les accès automatiques :
à récupérer depuis un PC :

```sh
git clone --filter=blob:none -b sony/akatsuki https://gitlab.com/phodina/linux.git phodina-linux
cd phodina-linux
git log --oneline --author="Petr Hodina" -40
# puis exporter ses commits (remplacer <premier> par le plus ancien de la liste) :
git format-patch <premier>^..HEAD --author="Petr Hodina" -o ../patches-akatsuki
```

## Hors sujet pour le XZ3

- « Input: support for STM FTS5 » (mars 2026) : tactile du Pixel 3, pas des Tama.
- « Sony SDM845 panel and remoteproc enablement » (2022-2023) : série de
  Konrad Dybcio, déjà fusionnée (affichage XZ2/XZ2C, remoteprocs, GPU, GPI DMA).
