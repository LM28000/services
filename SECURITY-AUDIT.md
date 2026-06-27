# 🔒 Audit de sécurité & exploitation — Stack Docker

> Réalisé le 2026-06-27 · Hôte `192.168.0.75` (LAN `192.168.0.0/24` + Tailnet `100.64.0.0/10`) · 63 conteneurs
> Complète et met à jour `INFRASTRUCTURE.md` (2026-06-25). Aucune valeur de secret n'est reproduite ici.

## Note de périmètre
- **CryptoBot** : limité à un constat d'infra (port/réseau) conformément à la politique d'organisation. Aucune analyse de sa logique applicative.
- Sévérités : 🔴 Critique · 🟠 Élevée · 🟡 Moyenne · 🟢 Hygiène.

---

## 0. Constat structurant : surface d'exposition

| Fait | Vérifié | Conséquence |
|------|---------|-------------|
| **Aucun pare-feu hôte** | `iptables -S` et `nft list ruleset` vides | Tous les ports `0.0.0.0` sont joignables depuis tout le LAN **et tout le Tailnet** |
| **Docker contourne UFW** | par conception | Même si UFW était posé, les ports publiés Docker passeraient outre sans règle `DOCKER-USER` |
| **Aucun reverse proxy sur cet hôte** | rien sur `:80/:443`, aucun conteneur traefik/caddy/npm/cloudflared | Les `*.du-cray.eu` (Authelia) sont servis ailleurs. **Donc l'accès direct `IP:port` court-circuite Authelia** |

➡️ Tant qu'aucun proxy local n'est en place, **chaque service bindé `0.0.0.0` est accessible sans authentification depuis le LAN/Tailnet**, indépendamment d'Authelia. C'est la racine de la plupart des findings ci-dessous.

---

## 1. 🔴 Findings CRITIQUES (action immédiate)

### C1 — `ttyd` : backdoor SSH ouverte en `admin:admin`
- Entrypoint réel : `ttyd -p 7681 -W -c admin:admin ssh louis@192.168.0.75`, bindé `0.0.0.0:7681`.
- `-W` (writable) + auth basique **admin/admin** → quiconque ouvre `http://192.168.0.75:7681` obtient un **shell SSH interactif en tant que `louis`** sur l'hôte. Clés SSH montées en prime.
- C'est l'équivalent d'un accès root distant non authentifié sur le LAN/Tailnet.
- **Correctif** : arrêter immédiatement, ou a minima mot de passe fort + bind `127.0.0.1` + Authelia obligatoire devant.
```bash
docker stop ttyd && docker rm ttyd   # si pas indispensable
```

### C2 — Redis `secure_dmz2-redis-1` exposé sans mot de passe
- `0.0.0.0:6379`, `CONFIG GET requirepass` → **vide**, `PING` répond `PONG` sans auth.
- Redis sans auth + sans firewall = vecteur RCE classique (`CONFIG SET dir` → écriture `authorized_keys`/cron, ou `MODULE LOAD`).
- **Correctif** : binder `127.0.0.1:6379` (ou réseau interne uniquement) **et** poser un mot de passe :
```bash
# dans la définition du conteneur : command: redis-server --requirepass <fort> --bind 0.0.0.0
# et port mapping 127.0.0.1:6379:6379
```

### C3 — `control-tower` : authentification désactivée + secrets en clair
- `AUTH_DISABLED=true` et `NEXT_PUBLIC_AUTH_DISABLED=true`, bindé `0.0.0.0:4000`.
- L'accès direct `:4000` **contourne totalement Authelia**. Or Control Tower pilote qBittorrent, Radarr, Sonarr, Plex, WatchState, etc.
- Secrets en clair dans l'env (visibles via `docker inspect`) : `GITHUB_PAT`, `GITHUB_CLIENT_SECRET`, `NEXTAUTH_SECRET`, `AUTHELIA_CLIENT_SECRET`, `*_API_KEY` (Radarr/Sonarr/Plex/WatchState/Jellyseerr), `QBT_PASSWORD`, `API_ADMIN_TOKEN`.
- ⚠️ Le `GITHUB_PAT` avait **déjà** été signalé critique le 2026-06-25 — il est **toujours présent**. À considérer comme compromis.
- **Correctifs** :
  1. **Révoquer le `GITHUB_PAT` et le `GITHUB_CLIENT_SECRET` sur GitHub maintenant** (présents en clair depuis ≥ 2 jours).
  2. Binder `127.0.0.1:4000` et ne l'exposer qu'à travers le proxy + Authelia ; ne pas se reposer sur `AUTH_DISABLED`.
  3. Déplacer tous ces secrets vers un fichier `.env` hors monde-lisible / Docker secrets.

### C4 — `cmd_hub` : injection de commande → root hôte
- Flask exposé `0.0.0.0:5001`, conteneur avec `docker.io` installé + **socket Docker monté en RW**.
- `app.py` exécute `subprocess(..., shell=True)` en interpolant `args` non filtré :
  - `!cmd logs <args>` → `docker logs --tail 15 {args}` ; `!cmd restart <args>` idem.
  - Ex. `… ; rm -rf / ; …` ou `; docker run -v /:/host …` → exécution arbitraire = **root sur l'hôte**.
- Seule barrière : un `SECRET_TOKEN` **codé en dur** dans `app.py` (fichier en `chmod 777`, présent dans l'arborescence sauvegardée).
- **Correctifs** : ne jamais passer `args` à un shell ; liste blanche stricte des noms de conteneurs ; retirer `shell=True` ; sortir le token du code ; binder `127.0.0.1` ; idéalement remplacer le socket RW par un socket-proxy en lecture seule.

---

## 2. 🟠 Findings ÉLEVÉS

| # | Service | Problème | Correctif |
|---|---------|----------|-----------|
| H1 | `peabot-db` (5432), `mediawiki_db` (3306) | Bases exposées `0.0.0.0`. Postgres exige scram (OK) mais reste brute-forçable ; MariaDB à vérifier | Binder `127.0.0.1` ou réseau interne uniquement |
| H2 | `dozzle`, `uptime_kuma` | Montent le **socket Docker en RW** sans en avoir besoin (Dozzle = lecture seule ; Kuma n'en a pas besoin) | Passer en `:ro`, ou retirer le montage pour Kuma |
| H3 | `vaultwarden` | `DOMAIN` non défini, `SIGNUPS_ALLOWED` non posé (**défaut = true → inscription ouverte**), HTTP sur `0.0.0.0:8084` | `SIGNUPS_ALLOWED=false`, définir `DOMAIN=https://…`, vérifier que `ADMIN_TOKEN` est au format Argon2, accès HTTPS only |
| H4 | `n8n` | Réseau `host` → voit tous les ports DB locaux ; montage SSH prévu. Combiné à l'absence de firewall, large surface | Repasser en bridge avec ports explicites ; auth n8n forte |
| H5 | Secrets en clair (`docker inspect`) | Au-delà de control-tower : tout conteneur compromis ou tout accès Docker lit les env | Centraliser en `.env` 600 / Docker secrets ; auditer Portainer EE (accès = accès à tous les secrets) |
| H6 | `matrix_admin` (6666), `headscale-ui` (9092), `portainer` (9443) | Panneaux d'admin bindés `0.0.0.0` | Restreindre à `127.0.0.1`/proxy + Authelia |

---

## 3. 🟡 Findings MOYENS

| # | Sujet | Détail | Correctif |
|---|-------|--------|-----------|
| M1 | **Watchtower** | Met à jour **tout** en `:latest` toutes les 6 h (`CLEANUP=true`, aucun scope). Image upstream **archivée** (dernière build 2023-11) | Épingler les versions critiques (DB, Synapse, Nextcloud) ; restreindre le scope ; envisager une alternative (ex. *diun* pour notifier sans appliquer) |
| M2 | **Pas de versions épinglées** | Quasi tous les services en `:latest`/`:main` → pas de rollback, breakage silencieux | Épingler au moins bases de données et services critiques |
| M3 | **Sauvegardes** | `kopia` **Exited (1)** → backups non fonctionnels. Source `/docker` non sauvegardée | Réparer Kopia en priorité (un homelab sans backup = perte totale sur incident disque) |
| M4 | Images abandonnées | `requestrr` (2024, mort), `it-tools` (2024-10), `watchtower` (archivé), `plex-mcp` (Exited 128) | Remplacer/supprimer |
| M5 | Healthchecks absents | `*arr`, `jellyfin`, `nextcloud_app`, `mediawiki_db`… aucun | Ajouter des healthchecks pour redémarrage auto fiable |
| M6 | `scrutiny` | Caps larges (`SYS_RAWIO`, `MKNOD`, …) | Acceptable pour l'accès SMART, mais à documenter/limiter aux disques nécessaires |
| M7 | Architecture proxy | `*.du-cray.eu` servis hors hôte : **vérifier** que le proxy force bien Authelia et que le routeur ne publie pas directement des `IP:port` | Cartographier le chemin d'entrée réel (Cloudflare ? autre hôte ?) |

---

## 4. 🟢 Hygiène

- `docker system df` : **8 GB d'images** + **2,8 GB de build cache** récupérables → `docker builder prune && docker image prune -a` (prudence avec Watchtower).
- Typos de chemins (depuis le doc) : `ollama` → `/docker/servives/ollama`, `open-webui` → `/docker/service/open-webui`. À corriger pour éviter des volumes fantômes.
- `plex-mcp` (Exited 128) à supprimer si inutilisé.
- `cmd_hub` tourne sur le serveur de dev Flask (`app.run`) en « production » → passer derrière gunicorn si conservé.

---

## 5. Plan d'action priorisé

**Aujourd'hui (≤ 30 min) :**
1. `docker stop ttyd` (C1).
2. Révoquer `GITHUB_PAT` + `GITHUB_CLIENT_SECRET` sur GitHub (C3).
3. Mettre un mot de passe + bind local sur le Redis exposé (C2).
4. Binder `127.0.0.1` : `control-tower:4000`, `cmd_hub:5001`, `peabot-db:5432`, `mediawiki_db:3306` (C3/C4/H1).

**Cette semaine :**
5. Poser un pare-feu réel : règles `DOCKER-USER` (et/ou n'exposer que via proxy). Modèle : tout fermer sauf 80/443 du proxy + SSH restreint.
6. Réparer Kopia (M3) et vérifier une restauration test.
7. Verrouiller Vaultwarden (H3) ; corriger `cmd_hub` (C4) ou le retirer.
8. Sortir les secrets des env vars (H5).

**Ensuite :**
9. Épingler les versions, restreindre Watchtower (M1/M2).
10. Healthchecks + nettoyage images (M5, hygiène).

---

## Annexe — Récapitulatif exposition (services bindés `0.0.0.0`, sans firewall)
Bases : `peabot-db:5432`, `mediawiki_db:3306`, `secure_dmz2-redis:6379` (sans auth).
Admin/contrôle : `portainer:9443`, `control-tower:4000` (auth off), `cmd_hub:5001`, `ttyd:7681` (admin:admin), `matrix_admin:6666`, `headscale-ui:9092`.
Apps : jellyfin 8096, plex (host) 32400, sonarr 8989, radarr 7878, prowlarr 9696, bazarr 6767, jackett 9117, tdarr 8265-66, tautulli 8181, qbittorrent 8080, seerr 5000, requestrr 4545, nextcloud 8081, mediawiki 8083, roundcube 8085, actual 5006, grafana 3000, prometheus 9090, qdrant 6333-34, ollama 11434, open-webui 3008, n8n (host), vaultwarden 8084/3012, authelia 9091, matrix 8008/7777, mautrix 29318, maubot 29316, hookshot 9000/9002/9993, uptime-kuma 3002, dozzle 8088, cadvisor 8098, glances 61208, scrutiny 8082/8086, headplane 3006, headscale 9999, it-tools 8090, qui 7476, jellystat 8044, jellyui 8091, homelab-dashboard 8089, portfolio 2368, peabot-app 8502, crypto_bot 8501 *(infra only)*.

---

## 6. Journal des actions appliquées (2026-06-27)

| Action | Statut | Réversible |
|--------|--------|-----------|
| `docker stop ttyd` (C1 backdoor) | ✅ Appliqué | `docker start ttyd` |
| `docker stop cmd_hub` (C4 RCE) | ✅ Appliqué | `docker start cmd_hub` |
| `peabot-db` rebindé sur `127.0.0.1:5432` (H1) | ✅ Appliqué (DB healthy, app OK) | éditer `/docker/services/PEABot/docker-compose.yml` |

### À appliquer via Portainer (stacks internes, non éditables en CLI sans root)
Pour chaque stack : **Portainer → Stacks → \<stack\> → Editor → modifier → Update the stack**.

1. **secure_dmz2 / Redis (C2)** — supprimer la publication du port. Le client légitime passe par le réseau interne `172.27.x`, donc retirer le mapping ne casse rien :
   ```yaml
   # retirer entièrement le bloc :
   #   ports:
   #     - "6379:6379"
   ```
   (Optionnel mais recommandé : ajouter `command: redis-server --requirepass <fort>` et configurer le mot de passe côté client.)
2. **control-tower (C3)** — `ports: ["127.0.0.1:4000:4000"]` ; à terme retirer `AUTH_DISABLED`/`NEXT_PUBLIC_AUTH_DISABLED` une fois le reverse proxy + Authelia en place ; sortir les secrets en `env_file`.
3. **mediawiki_db (H1)** — `ports: ["127.0.0.1:3306:3306"]` (l'app accède via le réseau interne).
4. **dozzle (H2)** — passer le montage socket en lecture seule : `/var/run/docker.sock:/var/run/docker.sock:ro`.
5. **uptime_kuma (H2)** — retirer le montage du socket Docker (inutile à son fonctionnement).
6. **vaultwarden (H3)** — ajouter `SIGNUPS_ALLOWED=false`, `DOMAIN=https://vault.du-cray.eu`, vérifier `ADMIN_TOKEN` au format Argon2.

### Action hors-serveur (utilisateur)
- **Révoquer `GITHUB_PAT` + `GITHUB_CLIENT_SECRET`** sur GitHub (exposés en clair ≥ 2 jours).

---

## 7. Améliorations de fond (architecture)

Classées par rapport effort/impact. Les 3 premières corrigent des *classes entières* de problèmes.

### A1 — Reverse proxy local + Authelia réellement appliqué *(impact majeur)*
Aujourd'hui Authelia existe mais rien ne l'applique en local : les services sont directement sur `0.0.0.0`. 
- Déployer **un reverse proxy sur cet hôte** (Caddy = le plus simple, ou Traefik, ou Nginx Proxy Manager).
- Faire écouter les apps sur `127.0.0.1` / réseau interne (**arrêter de publier sur `0.0.0.0`**).
- Le proxy gère TLS (Let's Encrypt sur `du-cray.eu`) + `forward_auth` vers Authelia.
- ➡️ Supprime d'un coup tout le « accès direct `IP:port` qui contourne l'auth ».

### A2 — Pare-feu via la chaîne `DOCKER-USER` *(impact majeur, ~30 min)*
Docker contourne UFW : poser les règles dans `DOCKER-USER` (ou utiliser `ufw-docker`). 
- N'autoriser en entrée que : 80/443 (proxy), SSH restreint, et le subnet Tailnet pour l'admin.
- Tout le reste (ports applicatifs) → DROP depuis l'extérieur de l'hôte.

### A3 — `docker-socket-proxy` au lieu du socket brut *(impact élevé)*
Remplacer les montages `docker.sock` (Portainer, Watchtower, Dozzle, Glances, Uptime-Kuma) par **`tecnativa/docker-socket-proxy`** exposant une API restreinte/lecture seule par service. Supprime une classe entière d'évasion conteneur→root.

### A4 — Gestion des secrets
Sortir tous les secrets des variables d'env en clair : `env_file` en `chmod 600`, Docker secrets, ou SOPS chiffré. Priorité : control-tower, et tout ce qui contient API keys/tokens.

### A5 — Infrastructure as Code (GitOps)
Les stacks sont éclatés entre Portainer (`/var/lib/docker/.../compose/NN`, opaques) et quelques fichiers. Centraliser **tous** les `docker-compose.yml` versionnés sous `/docker/services` (git) + déploiement via stacks Git Portainer ou `docker compose`. Bénéfices : rollback, revue, audit reproductible, plus de stacks cachés.

### A6 — Versions épinglées + mises à jour maîtrisées
Remplacer `:latest` partout + Watchtower auto-apply par : tags/digests épinglés, et Watchtower en **mode notification** (ou **Diun**) pour alerter sans appliquer. Critique pour bases de données, Synapse, Nextcloud. (Watchtower est aussi archivé upstream → envisager un remplacement.)

### A7 — Sauvegardes fonctionnelles *(critique)*
Kopia est **mort (Exited 1)** → aucun backup. Réparer ou passer à **restic/Borg**. Sauvegarder : configs `/docker/services`, **dumps SQL** (`pg_dump`/`mariadb-dump`, pas les fichiers DB à chaud), volumes nommés. Règle 3-2-1, et **tester une restauration**. Brancher un heartbeat sur Uptime-Kuma pour alerter si un backup échoue.

### A8 — ACLs Tailnet (headscale)
Puisque tout est joignable sur le Tailnet, définir des **ACLs headscale** : seuls certains nœuds/utilisateurs atteignent certains ports. Défense en profondeur même derrière le proxy.

### A9 — Hygiène diverse
- Roter les creds DB triviaux (`peabot/peabot`).
- Limites CPU/RAM sur conteneurs lourds/non fiables (ollama, transcodage).
- `docker system prune` (~11 GB récupérables) ; supprimer `plex-mcp` (mort).
- Alerting Grafana/Alertmanager : conteneur down, disque plein, expiration certifs, succès backup.

---

## 8. Sauvegardes (A7) — état au 2026-06-27

### ✅ Fait : dumps SQL logiques quotidiens
- Script : `/docker/services/scripts/backup-databases.sh` (auto-découvre Postgres + MariaDB, dumps `pg_dumpall` / `--all-databases`, gzip, rétention 14 j, log `backups/backup.log`).
- Cron utilisateur `louis` : `30 3 * * *`.
- Testé OK : matrix/synapse 45M, nextcloud 106M, mediawiki 1,8M, jellystat 448K, peabot 20K. Intégrité gzip + entêtes SQL vérifiées.

### ⏳ À faire (toi) : réparer Kopia (copie chiffrée hors-site gdrive)
**Cause racine** : Watchtower a mis à jour Kopia ; la nouvelle version refuse `--insecure --address=0.0.0.0 --without-password` (serveur non authentifié sur adresse non-loopback) → crash en boucle. **Illustration directe du besoin A6 (épinglage + MAJ maîtrisées).**

Stack Portainer `kopia` (`/data/compose/78/v2`). `KOPIA_PASSWORD` est dans l'env du compose → l'éditer ne le perd pas. Dans **Portainer → Stacks → kopia → Editor**, remplacer le bloc `command:` :
```yaml
    command:
      - server
      - start
      - --insecure
      - --address=0.0.0.0:8200
      - --server-username=admin
      - --server-password=<MOT_DE_PASSE_FORT>   # remplace --without-password
```
(Garde l'accès via NPM. Alternative verrouillée : `--address=127.0.0.1:8200` + tunnel SSH, et retirer la publication du port.)
Tant qu'à faire, épingler l'image : `image: kopia/kopia:<version>` au lieu de `:latest`.

**Après redémarrage** : vérifier dans l'UI Kopia qu'une **policy de snapshot planifié existe pour `/data`** (sinon le serveur tourne mais ne sauvegarde rien) ; lancer un snapshot manuel pour valider l'envoi vers `gdrive`.

