#!/usr/bin/env bash
#
# Pare-feu pour les ports publiés par Docker, via la chaîne DOCKER-USER.
# (UFW/iptables INPUT n'ont AUCUN effet sur les conteneurs : Docker les contourne.
#  DOCKER-USER est le SEUL point d'accroche correct.)
#
# Politique posée :
#   - Autorise le trafic ÉTABLI/RELIÉ (retours de connexion, sortants conteneurs OK)
#   - Autorise les sources de confiance arrivant sur l'interface physique / Tailscale
#   - BLOQUE tout le reste qui arrive de l'extérieur vers un port de conteneur
#   - Ne touche NI le SSH (port hôte, hors DOCKER-USER) NI l'inter-conteneurs
#
# Usage :
#   sudo ./firewall-docker-user.sh test      # applique 120s puis revert auto (sécurité)
#   sudo ./firewall-docker-user.sh apply      # applique définitivement (mémoire)
#   sudo ./firewall-docker-user.sh revert     # retire UNIQUEMENT nos règles
#   sudo ./firewall-docker-user.sh status     # affiche la chaîne DOCKER-USER
#   sudo ./firewall-docker-user.sh persist    # rend les règles persistantes au reboot
#
set -euo pipefail

# ---------- Paramètres (adapte si besoin) ----------
PHYS_IF="eno1"                 # interface LAN physique (192.168.0.75)
TS_IF="tailscale0"             # interface Tailscale
LAN="192.168.0.0/24"           # LAN de confiance (inclut NPM 192.168.0.178)
TAILNET="100.64.0.0/10"        # plage Tailnet (headscale)
MARK="audit-fw"                # marqueur de commentaire pour retrouver NOS règles
CHAIN="DOCKER-USER"
# ---------------------------------------------------

need_root() { [ "$(id -u)" -eq 0 ] || { echo "À lancer en root (sudo)."; exit 1; }; }
ipt() { iptables "$@"; }

ensure_chain() {
  ipt -nL "$CHAIN" >/dev/null 2>&1 || { echo "Chaîne $CHAIN absente (Docker non démarré ?)."; exit 1; }
}

revert() {
  # Supprime nos règles (repérées par le commentaire), de la dernière à la première
  ipt -L "$CHAIN" --line-numbers -n 2>/dev/null \
    | awk -v m="$MARK" '$0 ~ m {print $1}' | sort -rn \
    | while read -r n; do ipt -D "$CHAIN" "$n"; done
  echo "Règles '$MARK' retirées."
}

apply() {
  revert
  # Inséré en position 1, en ORDRE INVERSE pour finir avec le bon ordre en haut :
  ipt -I "$CHAIN" 1 -i "$TS_IF"  -j DROP   -m comment --comment "$MARK"
  ipt -I "$CHAIN" 1 -i "$PHYS_IF" -j DROP  -m comment --comment "$MARK"
  ipt -I "$CHAIN" 1 -i "$TS_IF"  -s "$TAILNET" -j RETURN -m comment --comment "$MARK"
  ipt -I "$CHAIN" 1 -i "$PHYS_IF" -s "$LAN"     -j RETURN -m comment --comment "$MARK"
  ipt -I "$CHAIN" 1 -m conntrack --ctstate ESTABLISHED,RELATED -j RETURN -m comment --comment "$MARK"
  echo "Règles appliquées. Ordre final :"
  status
}

status() { ipt -L "$CHAIN" -n -v --line-numbers; }

test_mode() {
  apply
  echo ""
  echo ">>> MODE TEST : revert automatique dans 120 s."
  echo ">>> Si tout fonctionne (NPM, accès LAN), garde-les avec :  sudo touch /tmp/${MARK}-keep"
  rm -f "/tmp/${MARK}-keep"
  ( sleep 120
    if [ -f "/tmp/${MARK}-keep" ]; then
      echo "[$MARK] confirmées (gardées)."
    else
      iptables -L "$CHAIN" --line-numbers -n | awk -v m="$MARK" '$0 ~ m {print $1}' | sort -rn \
        | while read -r n; do iptables -D "$CHAIN" "$n"; done
      logger -t "$MARK" "revert auto (non confirmé)"
    fi
  ) >/dev/null 2>&1 &
  echo ">>> (timer lancé en arrière-plan, PID $!)"
}

persist() {
  if command -v netfilter-persistent >/dev/null 2>&1; then
    netfilter-persistent save && echo "Sauvegardé via netfilter-persistent."
  else
    echo "iptables-persistent non installé. Pour persister au reboot :"
    echo "  sudo apt install iptables-persistent   # puis : sudo netfilter-persistent save"
    echo "Ou ajoute au cron root :  @reboot $(readlink -f "$0") apply"
  fi
}

need_root; ensure_chain
case "${1:-}" in
  test)    test_mode ;;
  apply)   apply ;;
  revert)  revert ;;
  status)  status ;;
  persist) persist ;;
  *) echo "Usage: $0 {test|apply|revert|status|persist}"; exit 1 ;;
esac
