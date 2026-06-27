#!/usr/bin/env bash
#
# Sauvegarde logique de toutes les bases Docker (Postgres + MariaDB/MySQL).
# Auto-découverte des conteneurs par image -> couvre aussi les futures bases.
# Les mots de passe ne sont JAMAIS passés en argument hôte : ils sont lus
# depuis les variables d'environnement À L'INTÉRIEUR de chaque conteneur.
#
# Sortie : /docker/services/backups/db/<conteneur>_<date>.sql.gz
# Rétention : RETENTION_DAYS jours.
# Code de sortie != 0 si au moins un dump échoue (pour alerte cron/uptime-kuma).
#
set -uo pipefail

BACKUP_DIR="/docker/services/backups/db"
RETENTION_DAYS=14
DATE="$(date +%Y-%m-%d_%H%M)"
LOG="/docker/services/backups/backup.log"
PUSH_URL="${BACKUP_PUSH_URL:-}"   # optionnel : URL push Uptime-Kuma

mkdir -p "$BACKUP_DIR"
errors=0
log() { echo "$(date '+%F %T') | $*" | tee -a "$LOG"; }

dump_one() {  # $1=conteneur  $2=commande-de-dump-dans-le-conteneur
  local c="$1" cmd="$2" out="$BACKUP_DIR/$1_$DATE.sql.gz" tmp
  tmp="$out.part"
  if docker exec "$c" sh -c "$cmd" 2>>"$LOG" | gzip > "$tmp"; then
    # Vérifie intégrité gzip + taille plausible (> 100 octets)
    if gzip -t "$tmp" 2>/dev/null && [ "$(stat -c%s "$tmp")" -gt 100 ]; then
      mv "$tmp" "$out"
      log "OK   $c -> $(du -h "$out" | cut -f1)"
    else
      rm -f "$tmp"; log "ÉCHEC $c : dump vide ou corrompu"; errors=$((errors+1))
    fi
  else
    rm -f "$tmp"; log "ÉCHEC $c : erreur d'exécution"; errors=$((errors+1))
  fi
}

log "=== Début sauvegarde DB ==="

# --- PostgreSQL : pg_dumpall (toutes les bases + rôles), trust local ---
for c in $(docker ps --format '{{.Names}} {{.Image}}' | awk '$2 ~ /postgres/ {print $1}'); do
  dump_one "$c" 'pg_dumpall -U "${POSTGRES_USER:-postgres}"'
done

# --- MariaDB / MySQL : --all-databases, mot de passe root depuis l'env interne ---
for c in $(docker ps --format '{{.Names}} {{.Image}}' | awk '$2 ~ /maria|mysql/ {print $1}'); do
  dump_one "$c" 'D=$(command -v mariadb-dump || command -v mysqldump); \
    "$D" -uroot -p"${MARIADB_ROOT_PASSWORD:-$MYSQL_ROOT_PASSWORD}" \
    --single-transaction --routines --events --all-databases'
done

# --- Rotation ---
find "$BACKUP_DIR" -name '*.sql.gz' -mtime +"$RETENTION_DAYS" -delete 2>/dev/null
log "Rétention : suppression des dumps > ${RETENTION_DAYS} j"

if [ "$errors" -eq 0 ]; then
  log "=== Terminé : OK ==="
  [ -n "$PUSH_URL" ] && curl -fsS "$PUSH_URL?status=up&msg=db-backup-ok" >/dev/null 2>&1
  exit 0
else
  log "=== Terminé : $errors ÉCHEC(S) ==="
  [ -n "$PUSH_URL" ] && curl -fsS "$PUSH_URL?status=down&msg=db-backup-$errors-fails" >/dev/null 2>&1
  exit 1
fi
