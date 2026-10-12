#!/bin/sh
# installer-plasma-mobile.sh — Complète Plasma Mobile : composants de la session et
# applications mobiles de KDE. Le paquet « plasma-mobile » seul n'installe presque
# rien. Chaque paquet est essayé séparément : ceux absents des dépôts d'Arch ARM
# sont listés à la fin (sans faire échouer le reste). En root.
set -u
[ "$(id -u)" -eq 0 ] || { echo "Erreur : lancer en root." >&2; exit 1; }

session="plasma-mobile plasma-nano plasma-workspace plasma-nm plasma-pa bluedevil
powerdevil kscreen kde-gtk-config breeze breeze-gtk qqc2-breeze-style kirigami-addons
plasma-settings plasma-mobile-sounds feedbackd xdg-desktop-portal-kde
xdg-desktop-portal-gtk kdeconnect ark plasma-keyboard noto-fonts noto-fonts-emoji
networkmanager modemmanager upower"

applis="plasma-dialer spacebar plasma-phonebook angelfish qmlkonsole kclock kweather
kalk kalendar merkuro koko elisa haruna kasts krecorder okular index-fm nota
discover flatpak packagekit-qt6 alligator tokodon neochat audiotube plasmatube
calindori kongress"

pacman -Sy
absents=""
for p in $session $applis; do
	if pacman -Si "$p" >/dev/null 2>&1; then
		pacman -S --needed --noconfirm "$p" >/dev/null 2>&1 && echo "   ok   $p" || { echo "   ÉCHEC $p"; absents="$absents $p"; }
	else
		absents="$absents $p"
	fi
done
systemctl enable NetworkManager ModemManager bluetooth 2>/dev/null || true
echo
[ -n "$absents" ] && echo "Absents des dépôts ou en échec :$absents"
echo "Terminé. Redémarrer la session : systemctl restart sddm"
