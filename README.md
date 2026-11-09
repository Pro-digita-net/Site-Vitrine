# Site-Vitrine

Site vitrine de ProDigital (pro-digital.net) : application React 19 + Vite 7,
100 % statique (navigation `HashRouter`, formulaire de contact en `mailto:`).
Aucun backend, aucune base de données, aucun secret.

## Développement

```bash
npm ci
npm run dev      # http://127.0.0.1:5173
npm run build    # génère dist/
```

## Image Docker

| Fichier | Rôle |
|---|---|
| `Dockerfile` | Build multi-étapes : `node:22-alpine` (npm ci + vite build) → `nginxinc/nginx-unprivileged:1.28-alpine` (non-root, port 8080) |
| `nginx/default.conf` | Service des fichiers, gzip, cache (hash Vite = 1 an, images/polices = 7 j, `index.html` = no-cache), `/healthz`, fichiers cachés bloqués |
| `nginx/security-headers.conf` | HSTS, CSP stricte, nosniff, X-Frame-Options, Referrer-Policy, Permissions-Policy |
| `docker-compose.yml` | Fichier utilisé par Coolify (aucun port publié, conteneur en lecture seule, sans privilèges, healthcheck) |
| `docker-compose.local.yml` | Ajoute un port local pour les tests, ignoré par Coolify |
| `scripts/test-docker.ps1` | Test complet de l'image sous Windows (Docker Desktop) |

Test local :

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\test-docker.ps1   # résultat dans docker-test.log
# ou manuellement :
docker compose -f docker-compose.yml -f docker-compose.local.yml up --build   # http://localhost:8080
```

## Déploiement sur Coolify

1. **+ New Resource → Private Repository (GitHub App)** → dépôt `Pro-digita-net/Site-Vitrine`, branche `main`.
2. **Build Pack : Docker Compose**, *Docker Compose Location* : `/docker-compose.yml`.
3. Service `site` → **Domains** : `https://pro-digital.net:8080,https://www.pro-digital.net:8080`
   (`:8080` = port interne du conteneur ; le public accède en HTTPS 443, certificat Let's Encrypt généré par Coolify,
   redirection HTTP → HTTPS assurée par le proxy de Coolify).
4. Les DNS `pro-digital.net` et `www` doivent pointer (enregistrements A/AAAA) vers le serveur Coolify **avant** le déploiement, sinon le certificat ne peut pas être émis.
5. **Deploy**. Les déploiements suivants sont automatiques à chaque push sur `main` (option *Auto Deploy*, activée par défaut avec la GitHub App).

Variables d'environnement : aucune n'est requise (voir `.env.example` pour les options).
Volumes : aucun, le site ne stocke aucune donnée.

L'application est indépendante des autres produits ProDigital (Genesis CRM, Orbit ITSM, ProDigital Core) :
pas de réseau partagé, pas de dépendance, une ressource Coolify dédiée.
