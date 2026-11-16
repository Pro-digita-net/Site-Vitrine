# Site-Vitrine

Site vitrine de ProDigital (pro-digital.net), séparé en deux parties :

| Dossier | Contenu |
|---|---|
| [`frontend/`](frontend/) | Le site : application React 19 + Vite 7 servie en statique (pages HTML pré-rendues, navigation `BrowserRouter`), configuration Nginx et son `Dockerfile`. |
| [`backend/contact-api/`](backend/contact-api/README.md) | API du formulaire de contact : enregistrement en base, notification e-mail, transmission à Genesis CRM, et son `Dockerfile`. |
| [`backend/core-api/`](backend/core-api/README.md) | API ProDigital Core (référentiel multi-entreprises, IAM, workers) — déployée séparément, avec son propre `docker-compose.yml`. |
| `backend/exports/`, `backend/scripts/` | Exports SQL du socle Core et scripts qui les génèrent (à lancer depuis `backend/`). |
| [`shared/`](shared/) | Seul code commun : contenu du site (`data.js`) et définition du formulaire (`contactQuestions.js`), utilisés par le formulaire *et* par la validation de l'API. |

À la racine ne restent que l'orchestration (`docker-compose*.yml`, `.env.example`) et `scripts/test-docker.ps1`.

## Développement

```bash
cd frontend
npm ci
npm run dev      # http://127.0.0.1:5173
npm run build    # génère frontend/dist/
```

Le formulaire de contact appelle `/api`, relayé par Vite vers l'API locale (port 8788,
`API_PROXY_TARGET` pour changer). Sans API, le formulaire propose l'envoi par e-mail.
Voir [backend/contact-api/README.md](backend/contact-api/README.md) pour la lancer et la tester.

## Image Docker

Les deux images se construisent avec la racine du dépôt comme contexte (elles copient `shared/`).

| Fichier | Rôle |
|---|---|
| `frontend/Dockerfile` | Build multi-étapes : `node:22-alpine` (npm ci + vite build) → `nginxinc/nginx-unprivileged:1.28-alpine` (non-root, port 8080) |
| `backend/contact-api/Dockerfile` | Image de l'API du formulaire : `node:22-alpine`, non-root, port 8788 |
| `frontend/nginx/default.conf` | Relais `/api/` vers le service `api`, service des fichiers, gzip, cache (hash Vite = 1 an, images/polices = 7 j, `index.html` = no-cache), `/healthz`, fichiers cachés bloqués |
| `frontend/nginx/security-headers.conf` | HSTS, CSP stricte, nosniff, X-Frame-Options, Referrer-Policy, Permissions-Policy |
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

Variables d'environnement : le service `site` n'en demande aucune ; le service `api` exige
`DATABASE_URL`, et `GENESIS_SERVICE_TOKEN` + `SMTP_*` pour transmettre les demandes (voir `.env.example`).
Le service `api` doit pouvoir joindre PostgreSQL et Genesis (dans Coolify : « Connect To Predefined Network »
ou une URL joignable). Avant le premier déploiement, préparer la base : [backend/contact-api/README.md](backend/contact-api/README.md#mise-en-service).
Volumes : aucun, les demandes sont stockées dans PostgreSQL (schéma `site`).

Le site reste servi même si l'API, la base, Genesis ou la messagerie sont indisponibles : seule la
transmission des demandes en dépend, et elle reprend automatiquement.

Référencement : voir [frontend/SEO.md](frontend/SEO.md). Vérification après build : `npm run test:seo` (dans `frontend/`).
