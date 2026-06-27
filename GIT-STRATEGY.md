# Stratégie git & dépôt

## Principe
- **Mono-repo infra** : ce dépôt (`/docker/services`) contient TOUTE l'infra (compose + scripts + docs). Un clone = toute l'infra.
- **Code applicatif séparé** : `PEABot`, `CryptoBot`, `control-tower`, `media-stack`, `portfolio` = leurs **propres dépôts** (exclus via `.gitignore`). Le mono-repo ne fait que les **référencer** (image ou `build:`), jamais embarquer leur code.
- **Données hors git** : tout ce qui est runtime (`data/`, `*-db/`, `storage/`, `cache/`, `nextcloud/`…) est git-ignoré et sauvegardé par Kopia.

## Secrets
- Vrais secrets dans `<stack>/.env` (et `apps/secrets.*.env`), `chmod 600`, **JAMAIS commités**.
- Modèles `<stack>/.env.example` **commités** (clés sans valeurs) → le repo est auto-documenté.
- Pour cloner/redéployer ailleurs : copier le `.env.example` → `.env` et remplir (valeurs récupérables depuis Vaultwarden, ou la sauvegarde Kopia de `/docker`).
- Niveau supérieur (optionnel) : **SOPS + age** pour chiffrer les `.env` directement dans git.

## Dépôt distant : GitHub PRIVÉ
- ⚠️ **Privé obligatoire** — ce repo expose ports/domaines/archi.
- Le serveur peut ne pas avoir d'accès GitHub depuis cet environnement : pousser via une auth dédiée (clé SSH de déploiement ou PAT à scope limité) depuis le serveur, ou depuis une machine perso qui clone via Tailscale.

### Mise en place (une fois)
```bash
# Sur GitHub : créer un repo PRIVÉ "homelab" (vide, sans README).
cd /docker/services
git branch -M main
git remote add origin git@github.com:<user>/homelab.git   # SSH (clé de déploiement)
# ou en HTTPS+PAT : https://<user>:<PAT>@github.com/<user>/homelab.git
git push -u origin main
```

### Au quotidien
```bash
cd /docker/services/<stack>
# modifier docker-compose.yml / .env
docker compose -p <stack> up -d      # appliquer
cd /docker/services
git add -A && git commit -m "<stack>: <ce qui change>" && git push
```

## Garde-fous
- `.gitignore` en whitelist stricte : seuls `*/docker-compose.yml`, `*.env.example`, `scripts/`, docs `.md` top-level sont suivis. Tout le reste (secrets, données, repos imbriqués) est exclu par défaut.
- Avant un push, vérifier qu'aucun secret n'est suivi :
  `git ls-files | grep -iE '\.env$|/secrets/|\.pem$|\.key$' ` → doit être **vide**.
