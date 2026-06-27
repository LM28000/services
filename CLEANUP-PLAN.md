# 🧹 Plan de réorganisation Docker — vers compose-sur-disque versionné

> Décision : **modèle = stacks Portainer ← fichiers compose sur disque** (`/docker/services/<stack>/docker-compose.yml`, versionnés git) · **ampleur = réorg complète**.
> Principe directeur : **migration incrémentale, un stack à la fois, jamais big-bang.** Les volumes (nommés ou bind) sont préservés à chaque recréation.

---

## 1. État de départ (constaté le 2026-06-27)

- **3 modèles de gestion mélangés** : standalone `docker run` (portainer, scrutiny), compose-disque (media-stack, peabot), et stacks Portainer internes (tout le reste, opaques dans `/var/lib/docker`).
- **Stack fourre-tout `secure_dmz2`** : ~28 services sans rapport dans un seul YAML.
- **Dérive de versions Portainer** : stack `17` = Matrix **et** MediaWiki ; conteneurs pointant sur des versions différentes (v6/v12/v13/v17). `tdarr` sur un snapshot différent du reste de `secure_dmz2`.
- **Réseaux** : OK globalement, mais subnets Docker auto en `192.168.16→207.x` (même /16 que le LAN `192.168.0.0/24` → risque de collision), `secure_dmz2_default` quasi inutile, `command_hub2_default` vide.
- ✅ Déjà fait : `jellyfin_default` (orphelin) supprimé, `plex-mcp` (mort) supprimé, images −3 Go.

---

## 2. Cible : groupement des stacks

| Nouveau stack | Services | Dossier |
|---------------|----------|---------|
| `media` | sonarr, radarr, bazarr, prowlarr, jackett, qbittorrent, tdarr, seerr, requestrr, flaresolverr, tautulli, qui, plex, watchstate, kometa | `/docker/services/media/` |
| `jellyfin` | jellyfin, jellystat, jellystat-db, jellyui *(déjà compose-disque dans media-stack/)* | `/docker/services/media-stack/` |
| `monitoring` | grafana, prometheus, node-exporter, cadvisor, glances, dozzle, uptime-kuma, scrutiny | `/docker/services/monitoring/` |
| `apps` | nextcloud (app/cron/db), vaultwarden, actual_budget, roundcube, mediawiki (app/db), homelab_dashboard, it-tools | `/docker/services/apps/` |
| inchangés (déjà 1 stack propre, à passer sur disque) | matrix, headscale (+headplane), authelia, ollama (+open-webui), n8n, peabot ✅, cryptobot, qdrant ✅(pilote), portfolio, kopia | `/docker/services/<nom>/` |

> `watchtower` : à **remplacer** par un mode notification (Diun) ou retirer (cf. A6 — c'est lui qui a cassé Kopia). `cmd_hub` et `ttyd` : décommissionnés (stoppés), retirer les stacks.

---

## 3. Modèle de réseaux cible

Quelques réseaux **intentionnels** au lieu de l'enchevêtrement dmz_net/internal_net :

| Réseau | Rôle | Membres |
|--------|------|---------|
| `proxy` | Face à NPM (192.168.0.178) | toutes les UIs web proxyfiées |
| `media-net` | Comms internes média | arr ↔ download ↔ indexeurs |
| `monitoring-net` | Métriques internes | grafana/prometheus/exporters |
| `apps-net` | App ↔ base de données | nextcloud↔db, mediawiki↔db… |

**Règles** : les **bases de données n'ont AUCUN port hôte** (réseau interne only). Les UIs sont sur `proxy` (joignables par NPM) + protégées par le pare-feu `DOCKER-USER`. Une base + son app partagent un réseau privé.

---

## 4. Gestion des secrets (résout A4 en même temps)

Chaque dossier de stack contient un **`.env` (chmod 600, git-ignoré)** avec les vraies valeurs **copiées depuis l'env du stack Portainer actuel**. Le compose ne contient que des `${VAR}` + `env_file: .env`. Plus aucun secret en clair dans le YAML ni dans `docker inspect` côté définition.

---

## 5. Recette de migration (par stack)

1. **Générer** `/docker/services/<stack>/docker-compose.yml` (je le fais depuis `docker inspect` : image, ports, volumes, réseaux, noms de variables, command, caps, restart — sans lire les valeurs de secrets).
2. **Créer le `.env`** : tu copies les valeurs depuis Portainer (Stack → Editor / variables d'env). 
3. **Cutover** : dans Portainer, **supprimer l'ancien stack** (les volumes nommés/bind sont conservés). 
4. **Déployer** : `docker compose up -d` depuis le dossier (ou ré-ajouter en Portainer « stack from path »).
5. **Vérifier** : conteneur up/healthy, données présentes, accès via NPM OK.
6. Stack suivant.

> Le `daemon.json` (pools d'adresses + rotation logs) est posé **une fois** lors d'une fenêtre de maintenance (redémarre le démon = redémarre tous les conteneurs). Ensuite chaque stack recréé prend un subnet propre hors `192.168.x`.

---

## 6. Ordre recommandé (risque croissant)

1. ✅ **Hygiène** (prune, conteneurs morts) — fait.
2. 🔄 **Pilote `qdrant`** — compose écrit, en attente de cutover (valide le pattern de bout en bout).
3. **Stacks simples sans secret** : portfolio, qdrant, watchstate, jackett, kometa.
4. **Stacks simples avec secrets** : ollama/open-webui, n8n, authelia, headscale, cryptobot.
5. **Stacks multi-services** : matrix, nextcloud.
6. **Le monstre** : éclater `secure_dmz2` → `media` / `monitoring` / `apps` (le plus délicat, en dernier).
7. **`daemon.json`** : appliquer en fenêtre de maintenance (`scripts/daemon.json.proposed`).
8. **git init** `/docker/services` une fois les compose en place (avec `.gitignore` excluant `.env`, données, backups, node_modules).
9. Remplacer/retirer Watchtower ; retirer stacks cmd_hub & ttyd.

---

## 7. Pilote qdrant — étapes de cutover

Compose prêt : `/docker/services/qdrant/docker-compose.yml`.
1. Portainer → Stacks → **qdrant** → Delete (les données `./storage` restent sur le disque).
2. Me dire « go » → je lance `docker compose -p qdrant up -d` et je vérifie (santé + collections présentes).
3. Si OK → on enchaîne ; sinon rollback (re-déployer l'ancien stack).

Application `daemon.json` proposée : `scripts/daemon.json.proposed` (à copier vers `/etc/docker/daemon.json` puis `sudo systemctl restart docker` en maintenance).
