# Interface graphique : Plasma Mobile (12/10/2026)

Prérequis : écran DSI, tactile et GPU validés ([ecran.md](ecran.md)) — au démarrage,
`/dev/dri/card0` et `renderD128` présents, « Atmel maXTouch Touchscreen » en entrée.

## Installation (root)

```sh
pacman -Syu
pacman -S --needed mesa plasma-mobile plasma-pa kscreen konsole sddm qt6-wayland
pacman -S --needed plasma-keyboard        # clavier virtuel (maliit-keyboard absent d'Arch ARM)
mkdir -p /etc/sddm.conf.d
cat > /etc/sddm.conf.d/autologin.conf <<'EOF'
[Autologin]
User=alarm
Session=plasma-mobile

[General]
DisplayServer=wayland
EOF
systemctl start sddm          # essai ; « systemctl enable sddm » pour le démarrage
```

SDDM sert seulement à ouvrir la session automatiquement (son écran de connexion
n'est pas tactile). Échelle (écran 1440 × 2880, 6 pouces), en tant qu'`alarm`, en SSH :

```sh
export WAYLAND_DISPLAY=wayland-0 XDG_RUNTIME_DIR=/run/user/1000
kscreen-doctor -o
kscreen-doctor output.DSI-1.scale.3
```

`linux-aarch64` (mis à jour par `pacman -Syu`) ne sert pas : le téléphone démarre sur
le noyau pmOS du `boot.img`. On peut le retirer (`pacman -Rns linux-aarch64`).

## Résultat

- 12/10/2026 : **validé** — Plasma Mobile s'ouvre sur l'écran du XZ3, rendu par le GPU
  (Adreno 630, freedreno ; aucune erreur zap), tactile, échelle et clavier virtuel
  fonctionnent.

Reste : NetworkManager (panneaux Wi-Fi et réseau mobile de Plasma), son, rotation.
