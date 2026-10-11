#!/bin/sh
# partage-internet-pc.sh — Donne internet au Xperia XZ3 (Arch) par le câble USB,
# via la connexion du PC (NAT). À lancer sur le PC, en root, téléphone branché.
#
# Usage : sudo scripts/partage-internet-pc.sh [start|stop]
#
# Le téléphone est en 172.16.42.1 et utilise 172.16.42.2 (le PC) comme passerelle.
# Effet sur le PC (non permanent, disparaît au redémarrage du PC) :
#   - transfert IPv4 activé (net.ipv4.ip_forward=1) ;
#   - traduction d'adresses (masquerade) pour 172.16.42.0/24 vers les autres
#     interfaces du PC.

set -eu
die() { echo "Erreur : $*" >&2; exit 1; }
[ "$(id -u)" -eq 0 ] || die "lancer en root (sudo)."

action="${1:-start}"
NET=172.16.42.0/24

# Interface USB du téléphone : celle qui porte une adresse 172.16.42.x
iface="$(ip -4 -o addr show | awk '$4 ~ /^172\.16\.42\./ { print $2; exit }')"

case "$action" in
start)
	[ -n "$iface" ] || die "aucune interface en 172.16.42.x : téléphone branché et démarré ?
(si besoin : sudo ip addr add 172.16.42.2/24 dev <interface USB du téléphone>)"
	ip -4 -o addr show dev "$iface" | grep -q '172\.16\.42\.2/' || \
		echo "Attention : le PC n'est pas en 172.16.42.2 sur $iface ; le téléphone attend cette passerelle."
	sysctl -q -w net.ipv4.ip_forward=1
	if command -v nft >/dev/null 2>&1; then
		nft delete table ip akatsuki 2>/dev/null || true
		nft -f - <<EOF
table ip akatsuki {
	chain post {
		type nat hook postrouting priority srcnat; policy accept;
		ip saddr $NET oifname != "$iface" masquerade
	}
	chain fwd {
		type filter hook forward priority filter - 1; policy accept;
		iifname "$iface" accept
		oifname "$iface" ct state established,related accept
	}
}
EOF
	elif command -v iptables >/dev/null 2>&1; then
		iptables -t nat -C POSTROUTING -s "$NET" ! -o "$iface" -j MASQUERADE 2>/dev/null || \
			iptables -t nat -A POSTROUTING -s "$NET" ! -o "$iface" -j MASQUERADE
		iptables -C FORWARD -i "$iface" -j ACCEPT 2>/dev/null || iptables -I FORWARD -i "$iface" -j ACCEPT
		iptables -C FORWARD -o "$iface" -m state --state ESTABLISHED,RELATED -j ACCEPT 2>/dev/null || \
			iptables -I FORWARD -o "$iface" -m state --state ESTABLISHED,RELATED -j ACCEPT
	else
		die "ni nft ni iptables sur ce PC."
	fi
	echo "Partage actif : $iface → internet. Sur le téléphone : ping -c3 archlinuxarm.org"
	;;
stop)
	if command -v nft >/dev/null 2>&1; then
		nft delete table ip akatsuki 2>/dev/null || true
	fi
	if command -v iptables >/dev/null 2>&1 && [ -n "$iface" ]; then
		iptables -t nat -D POSTROUTING -s "$NET" ! -o "$iface" -j MASQUERADE 2>/dev/null || true
		iptables -D FORWARD -i "$iface" -j ACCEPT 2>/dev/null || true
		iptables -D FORWARD -o "$iface" -m state --state ESTABLISHED,RELATED -j ACCEPT 2>/dev/null || true
	fi
	echo "Partage arrêté (le transfert IPv4 reste activé jusqu'au redémarrage du PC)."
	;;
*)
	echo "Usage : $0 [start|stop]" >&2
	exit 2
	;;
esac
