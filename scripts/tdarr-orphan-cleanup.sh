#!/usr/bin/env bash
#
# tdarr-orphan-cleanup.sh
# -----------------------
# Supprime les fichiers de travail Tdarr orphelins laissés dans la bibliothèque
# après un transcodage interrompu (crash/redémarrage du node en pleine copie
# cache -> pool, cf. incident du 14/01/2026).
#
# Pourquoi ils existent : les libraries Tdarr ont output="." (résultat réécrit
# dans le dossier source) et le cache (/mnt/diskE) est sur un disque différent
# de la bibliothèque (mergerfs /mnt/pool). Le rapatriement final est donc une
# COPIE qui passe par un fichier temporaire "tmp<8 car>.mkv" renommé à la fin.
# Si Tdarr est coupé pendant cette copie, le temporaire (corrompu, runtime 0)
# reste sur place et Radarr le signale : "has a runtime of 0, is it a valid
# video file?".
#
# Garde-fou : on ne supprime QUE les tmp*.mkv non modifiés depuis >120 min.
# Une copie, même de plusieurs dizaines de Go, se termine en quelques minutes ;
# un orphelin de plus de 2 h est donc forcément mort, jamais une copie en cours.

set -euo pipefail

ROOTS=(/mnt/pool/Plex/movies /mnt/pool/Plex/children /mnt/pool/Plex/shows)
AGE_MIN=120
LOG=/docker/services/scripts/tdarr-orphan-cleanup.log
TS=$(date '+%F %T')

# Pattern strict = celui produit par tempfile/Tdarr : tmp + 8 caractères [a-z0-9_] + .mkv
# (évite tout faux positif sur un éventuel fichier nommé "tmp...").
mapfile -t orphans < <(
  find "${ROOTS[@]}" -type f -mmin +"$AGE_MIN" \
       -regextype posix-extended -regex '.*/tmp[a-z0-9_]{8}\.mkv' 2>/dev/null
)

if [ "${#orphans[@]}" -eq 0 ]; then
  exit 0
fi

{
  echo "[$TS] ${#orphans[@]} orphelin(s) Tdarr supprimé(s) :"
  for f in "${orphans[@]}"; do
    sz=$(stat -c '%s' "$f" 2>/dev/null || echo 0)
    printf '  %8.2f GB  %s\n' "$(awk "BEGIN{print $sz/1073741824}")" "$f"
  done
} >> "$LOG"

for f in "${orphans[@]}"; do
  rm -f -- "$f"
done
