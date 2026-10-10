#!/bin/sh
# check-dtb-ufs.sh — Garde-fou à lancer AVANT chaque démarrage d'un nouveau noyau.
#
# Sur la plateforme Sony Tama (XZ2, XZ2C, XZ3), le pilote UFS mainline envoie une
# commande qui efface toute la puce UFS, bootloader compris : brick définitif.
# Le DTB doit donc garder le contrôleur UFS et son PHY en status = "disabled".
#
# Usage : scripts/check-dtb-ufs.sh <fichier.dtb>
# Code de sortie : 0 = sûr, 1 = DANGER, 2 = erreur d'utilisation.

set -eu

dtb="${1:-}"
if [ -z "$dtb" ] || [ ! -f "$dtb" ]; then
	echo "Usage : $0 <fichier.dtb>" >&2
	exit 2
fi

if ! command -v dtc >/dev/null 2>&1; then
	echo "Erreur : 'dtc' est introuvable (paquet dtc / device-tree-compiler)." >&2
	exit 2
fi

dts="$(dtc -I dtb -O dts "$dtb" 2>/dev/null)" || {
	echo "Erreur : impossible de décompiler $dtb (est-ce bien un .dtb ?)." >&2
	exit 2
}

# Affiche la valeur "status" propre au nœud demandé (ignore les sous-nœuds).
node_status() {
	printf '%s\n' "$dts" | awk -v node="$1" '
		!inb && $0 ~ "^[[:space:]]*" node "[[:space:]]*\\{" { inb = 1; depth = 0 }
		inb {
			if (depth == 1 && $0 ~ /^[[:space:]]*status[[:space:]]*=/) {
				match($0, /"[^"]*"/)
				print substr($0, RSTART + 1, RLENGTH - 2)
			}
			depth += gsub(/\{/, "{")
			depth -= gsub(/\}/, "}")
			if (depth <= 0) exit
		}'
}

danger=0
for node in "ufshc@1d84000" "phy@1d87000"; do
	if ! printf '%s\n' "$dts" | grep -q "^[[:space:]]*$node[[:space:]]*{"; then
		echo "?  $node : nœud absent du DTB (inhabituel pour un SDM845, vérifie le fichier)"
		danger=1
		continue
	fi
	status="$(node_status "$node")"
	case "$status" in
		disabled)
			echo "OK $node : status = \"disabled\"" ;;
		"")
			echo "!! $node : aucun status => le nœud est ACTIF par défaut"
			danger=1 ;;
		*)
			echo "!! $node : status = \"$status\""
			danger=1 ;;
	esac
done

if [ "$danger" -ne 0 ]; then
	echo
	echo "DANGER : NE DÉMARRE PAS ce noyau sur un Xperia XZ3 (risque de brick définitif)."
	exit 1
fi

echo
echo "UFS désactivé : ce DTB peut être démarré."
