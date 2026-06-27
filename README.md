# Infrastructure Docker — `/docker/services`

Tous les services sont définis en **compose-sur-disque versionné** (git). Chaque stack = un dossier avec son `docker-compose.yml` et, si besoin, un `.env` (secrets, **git-ignoré**).

## Opérer un stack (workflow quotidien)

```bash
cd /docker/services/<stack>
# éditer docker-compose.yml ou .env, puis appliquer :
docker compose -p <stack> up -d        # crée/met à jour
docker compose -p <stack> ps           # état
docker compose -p <stack> logs -f      # logs
docker compose -p <stack> down         # arrêt (ne supprime PAS les volumes)
```
> Toujours `-p <stack>` (= nom du dossier) pour rester cohérent avec les conteneurs existants.

## Structure

| Stack | Contenu |
|-------|---------|
| `media/` | sonarr, radarr, bazarr, prowlarr, jackett, qbittorrent(VPN), tdarr, seerr, requestrr, flaresolverr, tautulli, qui, plex |
| `monitoring/` | grafana, prometheus, node-exporter, cadvisor, glances, dozzle, uptime-kuma, scrutiny |
| `apps/` | nextcloud(+db+cron+redis), vaultwarden, actual_budget, roundcube, mediawiki(+db), homelab_dashboard, it-tools |
| `matrix/` | synapse, element, admin, db, maubot, hookshot, mautrix-whatsapp |
| `ollama/`, `n8n/`, `headscale/`, `headplane/`, `authelia/`, `kopia/`, `portfolio/`, `qdrant/`, `watchstate/`, `kometa/`, `media-stack/`(jellyfin), `PEABot/` | un service/groupe chacun |

## Secrets
Dans `<stack>/.env` (et `secrets.*.env` pour apps), `chmod 600`, **jamais commités** (`.gitignore`). Référencés via `env_file:`. Présents sur le disque → `docker compose up` fonctionne localement ; un clone ailleurs nécessite de fournir les `.env`.

## Réseaux
- `dmz_net` / `internal_net` : partagés (services face NPM + comms internes).
- Réseaux par stack (`<stack>_default`, `monitoring_net`…) pour l'isolation.
- Bases de données : **sans port hôte** (réseau interne).

## Sauvegardes
- **Dumps SQL** : `scripts/backup-databases.sh`, cron quotidien 03h30 → `backups/db/*.sql.gz` (rétention 14 j). Restauration : `zcat backups/db/<x>.sql.gz | docker exec -i <db> mariadb/psql ...`.
- **Kopia** → gdrive (chiffré, snapshot 04h00 de `/docker`, embarque les dumps + ce dépôt git). Rétention horaire→annuelle.

## Pare-feu
`scripts/firewall-docker-user.sh` (chaîne `DOCKER-USER`, car Docker contourne UFW). Persistance : service systemd `firewall-docker-user.service`. Autorise LAN + Tailnet + NPM (192.168.0.178), bloque le reste.

## Portainer
Les stacks apparaissent en **« limited »** (créés via `docker compose`, pas par Portainer) — normal. Portainer sert à l'observation (logs/console). La source de vérité = ces fichiers + git.

## Non migrés
- **CryptoBot** : hors périmètre (politique d'organisation).
- **control-tower** : tourne encore sur son ancien stack Portainer (`/data/compose/72`) — à migrer ici si souhaité.

## Référence
- `INFRASTRUCTURE.md` — cartographie détaillée. `SECURITY-AUDIT.md` — audit + correctifs. `CLEANUP-PLAN.md` — historique de la réorg.
