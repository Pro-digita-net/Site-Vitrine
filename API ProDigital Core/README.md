# ProDigital Core API V1

API REST multi-entreprises construite sur `db/foundation/prodigital-core.sql` (copie inchangée du modèle de référence, PostgreSQL 15+). Node.js 24, TypeScript, Express 5, `pg`, Zod, OpenAPI 3.

Trois processus, une image, **un compte PostgreSQL par processus** — aucun n'est superuser, propriétaire de table ou `BYPASSRLS` :

| Processus | Compte | Rôle |
|---|---|---|
| `core-api` (`/api/v1`) | `pd_core_api` | API métier. Isolation par RLS, contexte dérivé du jeton par PostgreSQL. |
| `core-iam` (`/iam/v1` + CLI) | `pd_iam_admin` | Connexion OIDC, sessions, membres, invitations, clés API. Seul à écrire dans `iam`. |
| `core-worker` (+ CLI) | `pd_core_worker` | Outbox, notifications, webhooks, références de secrets. |
| API du site (`../server`, inchangée) | `pd_site_api` | Formulaire de contact, e-mail et Genesis CRM. |

Architecture : `routes → controllers → services → repositories → PostgreSQL` (`src/core/controller.ts`, `service.ts`, `repository.ts`). Chaque ressource est déclarée dans `src/core/resources/index.ts` : table, colonnes, filtres, tris et opérations autorisés. Aucun identifiant SQL ne vient d'une requête ; toutes les valeurs sont des paramètres.

## Matrice d'accès

Dérivée des `GRANT` et politiques du SQL. **Aucune suppression physique n'existe** (ni `DELETE` ni `TRUNCATE` accordés).

| Ressource | Lire | Créer | Modifier | Archiver | Permission |
|---|---|---|---|---|---|
| companies, contacts, teams | oui | oui | oui | oui (`archived_at`) | `directory.*` |
| company-contacts, addresses | oui | oui | oui | non (absent du SQL) | `directory.*` |
| team-members | oui | oui | non | non | `directory.*` |
| offerings | oui | oui | oui | oui (`status`) | `catalog.*` |
| courses, course-modules | oui | oui | oui | non | `catalog.*` |
| files | oui | oui (métadonnées) | nom seul | oui | `documents.*` |
| attachments | oui | oui | non | non | `documents.*` |
| requests | oui | oui | suivi et liens | non | `requests.*` |
| request-notes | oui | oui | oui | non | `requests.*` |
| connections | oui | oui | nom, activation | non | `integrations.*` |
| audit-events | oui | — | — | — | `audit.read` |
| organization, applications, application-plans, subscriptions, organization-applications | oui | — | — | — | jeton valide |
| communication_preferences | historique | ajout seul | interdit | interdit | `directory.*`, via fonctions dédiées |
| site.contact_* | membres ProDigital | — (API du site) | relance des échecs | — | `requests.*` + organisation du site |
| outbox, deliveries, external_references, connection_secrets | **interne** (worker) | | | | aucune route |
| iam.* | **interne** (service IAM) | | | | aucune route métier |

Une écriture exige aussi la permission de lecture (la base relit la ligne). Un `viewer` ne peut jamais écrire, même avec un scope d'écriture (règle du SQL). Les abonnements, offres et applications ne sont modifiables par aucun service : le SQL ne prévoit pas de moteur de facturation.

## Conventions HTTP

- `Authorization: Bearer <jeton opaque>`. Réponses `{ "data": … }` et listes `{ "data": [], "page": { limit, offset, has_more } }`.
- Erreurs `{ "error": { code, message, details?, request_id } }`. Les messages PostgreSQL ne sortent jamais.
- Listes : `limit` (≤ 100), `offset`, `sort` (`champ` ou `-champ`, liste fermée), `q`, filtres déclarés, `archived=false|true|all`. Tout paramètre inconnu → 400.
- Modification : `If-Match: <version>` obligatoire (428 sinon, 412 si la ressource a changé).
- Création : `Idempotency-Key` facultatif ; même clé + même contenu → réponse d'origine, contenu différent → 409.
- `GET /api/v1/openapi.json` (ou `npm run openapi > openapi.json`). `/healthz`, `/readyz`, `/metrics` (si `METRICS_TOKEN`).

## Authentification

Le schéma ne stocke aucun mot de passe : `iam.identities(issuer, subject)` désigne un fournisseur OpenID Connect.

1. `POST /iam/v1/sessions { id_token, organization? }` : l'ID token est vérifié (signature JWKS, émetteur, audience, expiration) ; une session opaque de 32 octets aléatoires est émise. Seul son SHA-256 est stocké.
2. Chaque requête métier ouvre une transaction et exécute `set_config('app.access_token', $1, true)` : le jeton est local à la transaction, effacé au COMMIT/ROLLBACK, donc sans fuite entre connexions du pool. `iam.context()` en déduit utilisateur, organisation et permissions.
3. Expiration, révocation, suspension d'un membre ou d'une organisation : refus immédiat, décidé par la base.

Service IAM (session `owner`/`admin` uniquement, jamais une clé API) : `GET/PATCH /members`, `GET/POST/DELETE /invitations`, `POST /invitations/accept`, `GET /tokens`, `POST /api-keys`, `DELETE /tokens/:id`, `POST /service-accounts`, `DELETE /sessions/current`. Un admin ne nomme ni ne modifie un propriétaire ; nul ne modifie sa propre appartenance ; l'organisation garde toujours un propriétaire actif ; un changement de rôle révoque les jetons du membre.

**Interservices** : compte de service (`POST /service-accounts`) + clé API aux scopes bornés par son rôle.

Il n'existe ni compte par défaut ni clé maître. Amorçage par un opérateur, dans le conteneur `core-iam` :

```sh
node dist/iam/cli.js user:create   --email vous@exemple.fr --given-name Prénom --family-name Nom
node dist/iam/cli.js identity:link --email vous@exemple.fr --issuer https://votre-idp --subject <sub>
node dist/iam/cli.js member:set    --org prodigital --email vous@exemple.fr --role owner
```

## Intégrations

- Créer une demande (`POST /requests`) écrit dans la même transaction un événement `web.request.created` dans `integration.outbox`.
- Le worker réserve les événements (`FOR UPDATE SKIP LOCKED`, bail, jeton de garde), les diffuse aux connexions **activées de la même organisation**, relance avec délais croissants puis passe en `failed` (relance : `node dist/worker/cli.js outbox:retry --id …`).
- `webhook` : POST signé `X-ProDigital-Signature: sha256=<HMAC du corps>`, `Idempotency-Key` = identifiant de l'événement (livraison « au moins une fois »).
- `email` : notification via SMTP (`notifications.deliveries`).
- La base ne stocke qu'une **référence** de secret. Le secret est un fichier JSON `SECRETS_DIR/<référence>` (ou `PD_SECRET_<RÉFÉRENCE>`) : `{"url":"https://…","signing_secret":"…"}` ou `{"to":"adresse@domaine"}`. Enregistrement : `node dist/worker/cli.js secret:set --org <uuid> --connection <uuid> --ref <référence>`.
- Formulaire du site et Genesis CRM : inchangés, assurés par `../server` ; l'API Core en donne la lecture et la relance (`/site/contact-submissions`).

## Migrations

`prodigital-core.sql` s'installe par `psql` sur une base vierge (voir son `INSTALLATION.md`). Les migrations de ce projet s'appliquent ensuite **à la main**, jamais au démarrage :

| Migration | Contenu |
|---|---|
| `002_core_api_runtime` | Rôles `pd_iam_admin` et `pd_core_worker` (NOLOGIN), droits minimaux, révocation définitive des jetons, 3 fonctions bornées pour `pd_core_api`, table `core.idempotency_keys`. |
| `003_function_privileges` | **Correction du socle** : son `ALTER DEFAULT PRIVILEGES IN SCHEMA … REVOKE EXECUTE … FROM PUBLIC` est sans effet (un réglage par schéma ne retire pas un droit par défaut), toutes ses fonctions restaient donc exécutables par tous les comptes. Retrait à PUBLIC et ré-attribution exacte. |

## Déploiement (VPS Hostinger, Coolify)

Rien de ce qui suit n'a été exécuté en production.

1. **Sauvegarde** : `pg_dump -Fc -d prodigital -f prodigital-$(date +%F).dump` depuis le conteneur PostgreSQL.
2. **Socle** : installer `prodigital-core.sql` (base vierge) si ce n'est pas fait.
3. **Migrations**, depuis un conteneur de l'image, avec le compte administrateur pour cette seule commande :
   `MIGRATION_DATABASE_URL=postgresql://… node dist/scripts/migrate.js --dry-run`, puis sans `--dry-run`.
4. **Activer les comptes** dans `psql` (mot de passe saisi, jamais écrit dans un fichier) : `\password pd_core_api` puis `ALTER ROLE pd_core_api LOGIN;` — idem `pd_iam_admin`, `pd_core_worker`.
5. **Coolify** : ressource Docker Compose sur ce dossier, variables de `.env.example`, réseau de la base dans `DATABASE_NETWORK`. Domaines : `core-api` → chemin `/api`, `core-iam` → chemin `/iam`. PostgreSQL n'expose aucun port.
6. **Vérifier** : `/readyz` des trois services, puis amorcer le premier propriétaire.

**Restauration** : arrêter les trois services, `pg_restore --clean --if-exists -d prodigital prodigital-AAAA-MM-JJ.dump`, redémarrer.

**Retour arrière** : applicatif → redéployer l'image précédente (les migrations sont additives). Base → arrêter les services puis `psql -1 -f db/rollback/003_function_privileges.sql` et `psql -1 -f db/rollback/002_core_api_runtime.sql` ; données métier, identités et audit sont conservés.

## Développement et tests

```sh
npm ci
npm test          # Docker requis : PostgreSQL 15 jetable (TEST_PG_IMAGE=postgres:17-alpine pour une autre version)
npm run build     # dist/
docker build -t prodigital-core-api .
```

Les tests installent le socle par `psql`, appliquent les migrations par le script du projet, vérifient le retour arrière, puis n'utilisent **que les quatre comptes applicatifs** : endpoints, permissions, injections SQL, isolation entre deux organisations, jetons invalides/expirés/révoqués, suppressions interdites, rollback, contraintes, concurrence, idempotence, workers, et l'API existante du site lancée telle quelle sur le socle.

## Limites connues

- **Fournisseur d'identité** : la connexion des utilisateurs exige `OIDC_ISSUER`/`OIDC_AUDIENCE` (503 sinon). Testé avec un fournisseur local à vraies clés RSA, pas avec le fournisseur de production.
- **SMTP et secrets de connexion** : à fournir ; sans eux les notifications restent en file puis en échec, relançables.
- **Fichiers** : seules les métadonnées sont gérées ; le stockage privé et les URL signées restent à raccorder.
- **Limitation de débit** en mémoire, par instance : prévoir un magasin partagé si plusieurs réplicas.
- `core.idempotency_keys` n'est pas purgée automatiquement (pas de `DELETE` pour l'API) : purge administrateur à planifier.
- Le SQL ne permet pas de retirer un rattachement, une adresse ou un membre d'équipe (ni `DELETE` ni colonne d'archivage).
- Aucun test de charge, aucun test sur le réseau Coolify réel.
