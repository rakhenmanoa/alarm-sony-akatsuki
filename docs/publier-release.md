# Publier une Release (mainteneur)

Les Releases contiennent ce qui permet d'installer Arch sur un XZ3 sans rien compiler
([installation-rapide.md](installation-rapide.md)). Rien de propre à un téléphone ou à
son propriétaire ne doit y figurer.

| Fichier | Contenu | Publiable car |
|---|---|---|
| `boot-akatsuki-generique.img` | noyau pmOS (sans verrouillage), DTB du dépôt, initramfs | logiciel libre, **sans adresses MAC** (lues dans la TA au démarrage) |
| `akatsuki-systeme-AAAAMMJJ.tar.zst` | Arch + Plasma Mobile configurés, modules compilés | nettoyé par `creer-image-systeme.sh` (vérifications automatiques) |
| `akatsuki-systeme-AAAAMMJJ.sha256` | empreintes | — |
| `linux-postmarketos-qcom-sdm845-*.apk` | paquet noyau de postmarketOS (modules) | logiciel libre (GPL) |

**Jamais** : firmwares ou fichiers Sony, EFS, TA, images personnelles (`WLAN_MAC`/`BT_MAC`),
dossiers `akatsuki-perso/`, `firmware-akatsuki/`, `blobs-akatsuki/`.

## 1. Préparer le système de référence (sur le téléphone, root)

```sh
cd /root/alarm-sony-akatsuki && git pull
sh scripts/installer-image-generique.sh   # MAC lues dans la TA, installation au 1er démarrage
```

Puis démarrer sur `boot-akatsuki-generique.img` (`fastboot boot` d'abord) et vérifier que
tout marche encore, en particulier les adresses d'origine :
`ip link show wlan0` et `bluetoothctl show`.

## 2. Fabriquer l'archive (sur le PC, carte dans le lecteur)

Éteindre le téléphone, mettre la carte dans le PC (**sans la monter**) :

```sh
sudo IMEI=<votre IMEI> scripts/creer-image-systeme.sh /dev/sdX1
```

Le script refuse de produire l'archive s'il reste un fichier Sony, une clé, un mot de
passe Wi-Fi, ou la moindre trace des adresses MAC du téléphone ou de l'IMEI.

## 3. Publier

```sh
v=$(date +%Y.%m.%d)
gh release create "$v" --title "XZ3 Arch Linux ARM $v" \
  --notes-file docs/installation-rapide.md \
  boot-akatsuki-generique.img akatsuki-systeme-*.tar.zst* akatsuki-systeme-*.sha256 \
  linux-postmarketos-qcom-sdm845-7.1_rc1-r4.apk
```

GitHub refuse les fichiers de plus de 2 Gio : `creer-image-systeme.sh` découpe alors
l'archive en morceaux `.part00`, `.part01`… (à publier tous).
