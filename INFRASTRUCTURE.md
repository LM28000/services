# Infrastructure Docker — Documentation Complète

> Généré le 2026-06-25 | Serveur : `192.168.0.75` | Domaine : `du-cray.eu`

---

## Table des matières

1. [Vue d'ensemble](#1-vue-densemble)
2. [Architecture réseau](#2-architecture-réseau)
3. [Services par catégorie](#3-services-par-catégorie)
4. [Stockage & volumes](#4-stockage--volumes)
5. [Alertes de sécurité](#5-alertes-de-sécurité)
6. [Services en anomalie](#6-services-en-anomalie)
7. [Cartographie des ports](#7-cartographie-des-ports-exposés)

---

## 1. Vue d'ensemble

**63 conteneurs** déployés au total (61 actifs, 2 arrêtés).

| Catégorie | Services |
|-----------|----------|
| Média | Plex, Jellyfin, Sonarr, Radarr, Bazarr, Prowlarr, Jackett, qBittorrent+VPN, Tdarr, Kometa, Tautulli, WatchState, Requestrr, Overseerr/Seerr |
| Réseau & Accès | Headscale, Headplane, Authelia, Coturn |
| Communication | Matrix Synapse, Element Web, Maubot, Hookshot, Mautrix-WhatsApp, Roundcube |
| Monitoring | Prometheus, Grafana, Node Exporter, cAdvisor, Glances, Scrutiny, Uptime Kuma, Dozzle |
| IA / Automatisation | Ollama, Open WebUI, n8n, Control Tower |
| Outils Dev/Infra | Portainer, Watchtower, Vaultwarden, Kopia, cmd-hub, ttyd, IT-Tools |
| Bases de données | PostgreSQL x2, MariaDB x2, Redis x2, Qdrant |
| Apps personnelles | Actual Budget, Nextcloud, Trilium, MediaWiki, Portfolio, PEABot, CryptoBot, Homelab Dashboard |

---

## 2. Architecture réseau

### Réseaux Docker

| Réseau | Subnet | Rôle |
|--------|--------|------|
| `dmz_net` | `172.27.0.0/16` | Zone publique — services exposables via reverse proxy |
| `internal_net` | `172.18.0.0/16` | Zone interne — services *arr, monitoring, médias |
| `secure_dmz2_default` | `172.19.0.0/16` | Zone semi-publique (IT-Tools, Requestrr, Qui) |
| `matrix_default` | bridge isolé | Stack Matrix complet |
| `peabot_default` | bridge isolé | PEABot (app + db + redis) |
| `ollama_default` | bridge isolé | Ollama + Open WebUI |
| `authelia2_default` | bridge isolé | Authelia |
| `headscale2_default` | bridge isolé | Headscale + UI |
| `cryptobot_default` | bridge isolé | CryptoBot |
| `prometheus_default` | bridge isolé | Prometheus |
| `qdrant_default` | bridge isolé | Qdrant |

### Conteneurs multi-réseaux (DMZ + Internal)

Ces services font pont entre les zones publique et interne :

`roundcube_app`, `sonarr`, `tautulli`, `watchtower`, `radarr`, `bazarr`, `prowlarr`, `seerr`, `nextcloud_app`, `nextcloud_cron`, `grafana`, `nextcloud_db`, `flaresolverr`, `qbittorrent`, `tdarr`, `ttyd`

---

## 3. Services par catégorie

### 3.1 Gestion des médias

| Conteneur | Image | Port | Réseau | Config |
|-----------|-------|------|--------|--------|
| `plex` | `lscr.io/linuxserver/plex:latest` | 32400 (host) | `host` | `/docker/services/plex/config` |
| `jellyfin` | `lscr.io/linuxserver/jellyfin:latest` | 8096 | `jellyfin_default` | `/docker/services/jellyfin` |
| `sonarr` | `lscr.io/linuxserver/sonarr:latest` | 8989 | `internal_net` | `/docker/services/sonarr` |
| `radarr` | `lscr.io/linuxserver/radarr:latest` | 7878 | `internal_net` | `/docker/services/radarr` |
| `bazarr` | `lscr.io/linuxserver/bazarr:latest` | 6767 | `internal_net` | `/docker/services/bazarr` |
| `prowlarr` | `lscr.io/linuxserver/prowlarr:latest` | 9696 | `internal_net` | `/docker/services/prowlarr` |
| `jackett` | `lscr.io/linuxserver/jackett:latest` | 9117 | `jackett_default` | `/data/compose/36/jackett/config` |
| `qbittorrent` | `binhex/arch-qbittorrentvpn:latest` | 8080 | `dmz_net` + `internal_net` | `/docker/services/qbittorrent` |
| `tdarr` | `haveagitgat/tdarr:latest` | 8265-8266 | `internal_net` | `/docker/services/tdarr` |
| `kometa` | `kometateam/kometa:latest` | — | `kometa2_default` | `/docker/services/kometa/config` |
| `tautulli` | `lscr.io/linuxserver/tautulli:latest` | 8181 | `internal_net` | `/docker/services/tautulli` |
| `watchstate` | `ghcr.io/arabcoders/watchstate:latest` | 8087 | `watchstate_default` | `/docker/services/watchstate/data` |
| `seerr` | `ghcr.io/seerr-team/seerr:latest` | 5000 | `dmz_net` + `internal_net` | `/docker/services/overseerr` |
| `requestrr` | `darkalfx/requestrr:latest` | 4545 | `secure_dmz2_default` | `/docker/services/requestrr` |
| `flaresolverr` | `ghcr.io/flaresolverr/flaresolverr:latest` | 8191 | `dmz_net` + `internal_net` | volume anonyme |

**Volumes médias montés :**
- `/mnt/pool/Plex/shows` — Séries TV
- `/mnt/pool/Plex/movies` — Films
- `/mnt/pool/Plex/children` — Contenu enfants
- `/mnt/pool/Plex/photos` — Photos
- `/mnt/diskE/qbittorent` — Téléchargements torrent
- `/mnt/diskE/plex_temp` — Transcodage Plex
- `/mnt/diskE/tdarr_temp` — Transcodage Tdarr

**qBittorrent VPN :**
- Provider : `custom` (OpenVPN)
- Config VPN : `/mnt/vpn_config` → `/config/openvpn/openvpn.ovpn`
- LAN Network : `192.168.0.0/24,192.168.0.1/32`
- DNS : `8.8.8.8`

---

### 3.2 Réseau & Accès distant

| Conteneur | Image | Port | Réseau | Config |
|-----------|-------|------|--------|--------|
| `headscale` | `headscale/headscale:latest` | — **(EN CRASH)** | `headscale2_default` | `/docker/services/headscale/config` |
| `headscale-ui` | `ghcr.io/gurucomputing/headscale-ui:latest` | 9092 | `headscale2_default` | — |
| `headplane` | `ghcr.io/tale/headplane:latest` | 3006 | `headplane_default` | `/docker/services/headplane/config.yaml` |
| `authelia` | `authelia/authelia:latest` | 9091 | `authelia2_default` | `/docker/services/authelia` |

**Authelia :**
- Domaine protégé : `*.du-cray.eu`
- URL : `https://auth.du-cray.eu`
- Redirection par défaut : `https://home.du-cray.eu`
- SMTP : port 587 (STARTTLS)

---

### 3.3 Communication & Messagerie

| Conteneur | Image | Port | Réseau | Config |
|-----------|-------|------|--------|--------|
| `matrix_synapse` | `matrixdotorg/synapse:latest` | 8008 | `matrix_default` | `/docker/services/matrix/data` |
| `matrix_element` | `vectorim/element-web:latest` | 7777 | `matrix_default` | `/docker/services/matrix/element-config.json` |
| `matrix_db` | `postgres:15-alpine` | — | `matrix_default` | `/docker/services/matrix/postgresdata` |
| `matrix_admin` | `awesometechnologies/synapse-admin:latest` | 6666 | `matrix_default` | — |
| `matrix-maubot-1` | `dock.mau.dev/maubot/maubot:latest` | 29316 | `matrix_default` | `/docker/services/maubot` |
| `matrix-hookshot-1` | `halfshot/matrix-hookshot:latest` | 9000, 9002, 9993 | `matrix_default` | `/docker/services/hookshot/config.yml` |
| `mautrix-whatsapp` | `litetex/mau.mautrix.whatsapp:latest` | 29318 | `mautrix_whatsapp_default` | `/docker/services/matrix/data/bridge` |
| `roundcube_app` | `roundcube/roundcubemail:latest` | 8085 | `dmz_net` + `internal_net` | `/docker/services/roundcube_app/config` |

**Hookshot ports :**
- 9000 : API principale
- 9002 : Webhooks entrants
- 9993 : Metrics

---

### 3.4 Monitoring & Observabilité

| Conteneur | Image | Port | Réseau | Config |
|-----------|-------|------|--------|--------|
| `prometheus` | `prom/prometheus:latest` | 9090 | `prometheus_default` | `/docker/services/prometheus/prometheus.yml` |
| `node-exporter` | `prom/node-exporter:latest` | 9100 (host) | `host` | `/` en lecture seule |
| `cadvisor` | `gcr.io/cadvisor/cadvisor:latest` | 8098 | `internal_net` | Docker socket + fs |
| `grafana` | `grafana/grafana:latest` | 3000 | `internal_net` | `/docker/services/grafana` |
| `glances` | `nicolargo/glances:latest` | 61208 | `dmz_net` | Docker socket |
| `uptime_kuma` | `louislam/uptime-kuma:beta` | 3002 | `dmz_net` | `/docker/services/uptime-kuma` |
| `dozzle` | `amir20/dozzle:latest` | 8088 | `dmz_net` | Docker socket |
| `scrutiny` | `ghcr.io/analogj/scrutiny:master-omnibus` | 8082/8086 | `bridge` | `/home/louis/scrutiny`, `/home/louis/influxdb2` |

**Prometheus — scrape jobs :**
- `prometheus` : `192.168.0.75:9090`
- `node-exporter` : `192.168.0.75:9100`
- Intervalle global : 15s

---

### 3.5 IA & Automatisation

| Conteneur | Image | Port | Réseau | Config |
|-----------|-------|------|--------|--------|
| `ollama` | `ollama/ollama:latest` | 11434 | `ollama_default` | `/docker/servives/ollama` *(typo)* |
| `open-webui` | `ghcr.io/open-webui/open-webui:main` | 3008 | `ollama_default` | `/docker/service/open-webui` *(typo)* |
| `n8n` | `ghcr.io/n8n-io/n8n:ci-22914567060` | — (host) | `host` | `/docker/services/n8n/n8n_data` |
| `control-tower` | `control-tower:latest` | 4000 | `control-tower_default` | `/docker/services/control-tower/control-tower/data` |
| `cmd_hub` | `python:3.11-slim` | 5001 | `command_hub2_default` | `/docker/services/cmd-hub` |

**n8n :**
- URL publique : `https://n8n.du-cray.eu`
- Mode réseau : `host`
- SSH monté depuis `/home/ton_user/.ssh`

**Control Tower :**
- URL : `https://control-tower.du-cray.eu`
- Auth : Authelia OIDC
- Services intégrés : Prometheus, Scrutiny, qBittorrent, Plex, WatchState, Radarr, Sonarr, Bazarr, Grafana, Tdarr, Overseerr

---

### 3.6 Outils Dev & Infrastructure

| Conteneur | Image | Port | Réseau | Config |
|-----------|-------|------|--------|--------|
| `portainer` | `portainer/portainer-ee:latest` | 9443 HTTPS | `bridge` | volume `portainer_data` |
| `watchtower` | `containrrr/watchtower:latest` | — | `dmz_net` + `internal_net` | Docker socket |
| `vaultwarden` | `vaultwarden/server:latest` | 8084, 3012 | `dmz_net` | `/docker/services/vaultwarden` |
| `kopia` | `kopia/kopia:latest` | — **(ARRETE)** | `kopia_default` | `/docker/services/kopia` |
| `ttyd` | `tsl0922/ttyd:latest` | 7681 | `dmz_net` + `internal_net` | SSH keys montées |
| `it-tools` | `corentinth/it-tools:latest` | 8090 | `secure_dmz2_default` | — |
| `qui` | `ghcr.io/autobrr/qui:latest` | 7476 | `secure_dmz2_default` | `/docker/services/qui` |

**Kopia (backup) :**
- Source : `/docker`
- Config : `/docker/services/kopia/config`
- rclone : `/home/louis/.config/rclone`
- **ETAT : arrêté (exit 1) — backup non fonctionnel**

---

### 3.7 Applications personnelles

| Conteneur | Image | Port | Réseau | Config |
|-----------|-------|------|--------|--------|
| `actual_budget` | `actualbudget/actual-server:latest` | 5006 | `dmz_net` | `/docker/services/actual_budget` |
| `nextcloud_app` | `nextcloud:latest` | 8081 | `dmz_net` + `internal_net` | `/docker/services/nextcloud/app` |
| `nextcloud_db` | `mariadb:10.6` | — | `internal_net` | `/docker/services/nextcloud/db` |
| `mediawiki_app` | `mediawiki:1.39` | 8083 | `mediawiki_default` | `/opt/mediawiki-stack/config/LocalSettings.php` |
| `mediawiki_db` | `mariadb:10.6` | 3306 | `mediawiki_default` | `/data/compose/17/data/db` |
| `portfolio-production` | `portfolio-portfolio` | 2368 | `portfolio_default` | volume `portfolio_admin_files` |
| `peabot-app` | `peabot-app` | 8502 | `peabot_default` | image custom |
| `peabot-db` | `postgres:16-alpine` | 5432 | `peabot_default` | volume `peabot_peabot_pg_data` |
| `peabot-redis` | `redis:7-alpine` | — | `peabot_default` | volume anonyme |
| `crypto_bot_app` | `mon-crypto-bot:latest` | 8501 | `cryptobot_default` | `/docker/services/CryptoBot` |
| `homelab_dashboard` | `nginx:alpine` | 8089 | `dmz_net` | `/docker/services/homelab-dashboard` |
| `qdrant` | `qdrant/qdrant:latest` | 6333-6334 | `qdrant_default` | `/docker/services/qdrant/storage` |

**PEABot :**
- Stack : FastAPI + PostgreSQL 16 + Redis 7
- Variables requises : `JWT_SECRET`, `ADMIN_PASSWORD` (via `.env`)

**Nextcloud :**
- Données utilisateurs : `/mnt/pool/nextcloud`
- Accès bibliothèque Plex : `/mnt/pool/Plex`

---

## 4. Stockage & Volumes

### Montages hôte principaux

| Chemin hôte | Usage |
|-------------|-------|
| `/mnt/pool/Plex/` | Médias (films, séries, enfants, photos) |
| `/mnt/diskE/qbittorent` | Téléchargements torrent |
| `/mnt/diskE/plex_temp` | Transcodage Plex |
| `/mnt/diskE/tdarr_temp` | Transcodage Tdarr |
| `/mnt/pool/nextcloud` | Données utilisateurs Nextcloud |
| `/mnt/vpn_config` | Config OpenVPN pour qBittorrent |
| `/docker/services/` | Configurations de tous les services |
| `/home/louis/scrutiny` | Config Scrutiny |
| `/home/louis/influxdb2` | Données InfluxDB (Scrutiny) |

### Volumes Docker nommés

| Volume | Usage |
|--------|-------|
| `portainer_data` | Données Portainer EE |
| `peabot_peabot_pg_data` | Base de données PEABot |
| `prometheus_prometheus_data` | Métriques Prometheus |
| `portfolio_admin_files` | Fichiers admin Portfolio |

### Anomalies de chemin détectées

| Conteneur | Chemin configuré | Chemin correct |
|-----------|-----------------|----------------|
| `ollama` | `/docker/servives/ollama` | `/docker/services/ollama` |
| `open-webui` | `/docker/service/open-webui` | `/docker/services/open-webui` |

---

## 5. Alertes de sécurité

### CRITIQUE — Token GitHub PAT exposé

Le conteneur `control-tower` contient un **GitHub Personal Access Token** stocké en clair
dans ses variables d'environnement (variable `GITHUB_PAT`), visible via `docker inspect`.

Actions requises :
1. **Révoquer immédiatement** le token sur GitHub → Settings → Developer settings → Personal access tokens
2. Créer un nouveau token avec les permissions minimales nécessaires
3. Le stocker via Docker secrets ou Vaultwarden, pas en variable d'env en clair

### ATTENTION — Ports de bases de données exposés sur 0.0.0.0

- `peabot-db` (PostgreSQL) : `0.0.0.0:5432`
- `mediawiki_db` (MariaDB) : `0.0.0.0:3306`
- `secure_dmz2-redis-1` (Redis) : `0.0.0.0:6379` sans authentification

Recommandation : changer en `127.0.0.1:PORT` si l'accès externe n'est pas requis.

### ATTENTION — Terminal web ttyd

Le port `7681` expose un shell bash avec les clés SSH montées. Vérifier la protection Authelia.

### ATTENTION — AUTH_DISABLED sur Control Tower

`AUTH_DISABLED=true` — la protection repose uniquement sur le reverse proxy / Authelia.

---

## 6. Services en anomalie

| Conteneur | État | Nb restarts | Action |
|-----------|------|-------------|--------|
| `headscale` | Restarting | 4541 | Vérifier `/docker/services/headscale/config` |
| `kopia` | Exited (1) | — | Backup non fonctionnel — investigation requise |
| `plex-mcp` | Exited (128) | — | Arrêt anormal (signal) |
| `headplane` | Unhealthy | — | Dépend de headscale |

---

## 7. Cartographie des ports exposés

| Port | Conteneur | Service |
|------|-----------|---------|
| 2368 | portfolio-production | Portfolio |
| 3000 | grafana | Grafana |
| 3002 | uptime_kuma | Uptime Kuma |
| 3006 | headplane | Headplane UI |
| 3008 | open-webui | Open WebUI (Ollama) |
| 3012 | vaultwarden | WebSocket Vaultwarden |
| 4000 | control-tower | Control Tower |
| 4545 | requestrr | Requestrr |
| 5000 | seerr | Overseerr/Seerr |
| 5001 | cmd_hub | Command Hub API |
| 5006 | actual_budget | Actual Budget |
| 5432 | peabot-db | PostgreSQL PEABot [EXPOSITION] |
| 6333 | qdrant | Qdrant HTTP |
| 6334 | qdrant | Qdrant gRPC |
| 6379 | secure_dmz2-redis-1 | Redis [SANS AUTH] |
| 6666 | matrix_admin | Synapse Admin |
| 6767 | bazarr | Bazarr |
| 7476 | qui | Qui (Autobrr) |
| 7681 | ttyd | Terminal Web |
| 7777 | matrix_element | Element Web |
| 7878 | radarr | Radarr |
| 8008 | matrix_synapse | Matrix Synapse |
| 8080 | qbittorrent | qBittorrent WebUI |
| 8081 | nextcloud_app | Nextcloud |
| 8082 | scrutiny | Scrutiny UI |
| 8083 | mediawiki_app | MediaWiki |
| 8084 | vaultwarden | Vaultwarden HTTP |
| 8085 | roundcube_app | Roundcube Mail |
| 8086 | scrutiny | Scrutiny InfluxDB |
| 8087 | watchstate | WatchState |
| 8088 | dozzle | Dozzle (logs) |
| 8089 | homelab_dashboard | Homelab Dashboard |
| 8090 | it-tools | IT-Tools |
| 8096 | jellyfin | Jellyfin |
| 8098 | cadvisor | cAdvisor |
| 8181 | tautulli | Tautulli |
| 8191 | flaresolverr | FlareSolverr |
| 8265 | tdarr | Tdarr WebUI |
| 8266 | tdarr | Tdarr Server |
| 8501 | crypto_bot_app | CryptoBot |
| 8502 | peabot-app | PEABot |
| 8989 | sonarr | Sonarr |
| 9000 | matrix-hookshot-1 | Hookshot API |
| 9002 | matrix-hookshot-1 | Hookshot Webhooks |
| 9090 | prometheus | Prometheus |
| 9091 | authelia | Authelia |
| 9092 | headscale-ui | Headscale UI |
| 9117 | jackett | Jackett |
| 9306 | mediawiki_db | MariaDB [EXPOSITION] |
| 9443 | portainer | Portainer EE HTTPS |
| 9696 | prowlarr | Prowlarr |
| 9993 | matrix-hookshot-1 | Hookshot Metrics |
| 11434 | ollama | Ollama API |
| 29316 | matrix-maubot-1 | Maubot |
| 29318 | mautrix-whatsapp | Mautrix WhatsApp |
| 32400 | plex | Plex Media Server |
| 61208 | glances | Glances |
