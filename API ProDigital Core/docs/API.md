# ProDigital Core API V1 — Documentation de référence

Cette documentation décrit tous les points d'entrée HTTP, les champs acceptés, les règles d'accès et les erreurs. Elle est écrite à partir du code (`src/core/resources/index.ts`, `src/core/app.ts`, `src/iam/app.ts`). La spécification machine (OpenAPI 3) est servie par `GET /api/v1/openapi.json`.

## Sommaire

1. [Vue d'ensemble](#1-vue-densemble)
2. [Authentification](#2-authentification)
3. [Permissions et rôles](#3-permissions-et-rôles)
4. [Conventions communes](#4-conventions-communes)
5. [Erreurs](#5-erreurs)
6. [API métier `/api/v1`](#6-api-métier-apiv1)
7. [Service IAM `/iam/v1`](#7-service-iam-iamv1)
8. [Webhooks et notifications](#8-webhooks-et-notifications)
9. [Commandes d'exploitation (CLI)](#9-commandes-dexploitation-cli)
10. [Supervision](#10-supervision)

---

## 1. Vue d'ensemble

| Service | Préfixe | Rôle |
|---|---|---|
| `core-api` | `/api/v1` | Données métier de l'organisation : annuaire, catalogue, documents, demandes, intégrations, audit. |
| `core-iam` | `/iam/v1` | Connexion, sessions, membres, invitations, clés API, comptes de service. |
| `core-worker` | aucun | Traitement en arrière-plan : webhooks et e-mails. Pas d'API HTTP métier. |

- Toutes les données sont **cloisonnées par organisation**. L'organisation est déduite du jeton, jamais d'un paramètre : un identifiant d'une autre organisation renvoie toujours `404`.
- **Aucune suppression physique** n'existe. Selon la ressource, on archive, on change un statut, ou rien.
- Format : JSON UTF-8. Corps limité à 64 Ko (16 Ko sur le service IAM).

---

## 2. Authentification

Chaque appel (hors santé et OpenAPI) porte un jeton opaque :

```
Authorization: Bearer <jeton>
```

Le jeton fait 43 à 128 caractères `[A-Za-z0-9_-]`. Un en-tête absent, mal formé, inconnu, expiré ou révoqué donne `401 unauthorized`, avec la même réponse dans tous les cas.

Le jeton cesse aussi d'être accepté dès que le membre, l'utilisateur ou l'organisation est suspendu, et dès qu'un administrateur change le rôle du membre.

### 2.1 Sessions utilisateur (OpenID Connect)

L'API ne gère aucun mot de passe. L'utilisateur se connecte auprès du fournisseur d'identité, puis échange son **ID token** contre une session :

```http
POST /iam/v1/sessions
Content-Type: application/json

{ "id_token": "eyJhbGciOi...", "organization": "prodigital" }
```

- `organization` (slug) est facultatif. Il devient obligatoire si l'utilisateur appartient à plusieurs organisations : sinon la réponse est `409 organization_required` avec `details.organizations` (liste des slugs).
- L'ID token est vérifié : signature (JWKS), émetteur, audience, expiration.
- La session dure `SESSION_TTL_HOURS` (12 h par défaut). Ses permissions sont celles du rôle.

Réponse `201` :

```json
{
  "data": {
    "token": "q3Zs…(43 caractères)",
    "id": "5f0c…",
    "user_id": "a1b2…",
    "organization_id": "c3d4…",
    "kind": "session",
    "label": "session",
    "scopes": ["directory.read", "directory.write", "…"],
    "created_at": "2026-11-12T09:00:00.000Z",
    "expires_at": "2026-11-12T21:00:00.000Z",
    "revoked_at": null
  }
}
```

Le champ `token` n'est **affiché qu'une fois** : seule son empreinte SHA-256 est conservée.

Déconnexion : `DELETE /iam/v1/sessions/current` → `204`.

Sans `OIDC_ISSUER` et `OIDC_AUDIENCE` configurés, la connexion et l'acceptation d'invitation répondent `503`. Les clés API restent utilisables.

### 2.2 Clés API (interservices)

Une clé API est un jeton opaque de longue durée, aux permissions choisies, au plus celles du rôle de son titulaire. Elle est créée par un owner/admin connecté (`POST /iam/v1/api-keys`, §7.4) ou en ligne de commande (§9).

Pour un logiciel tiers, créer d'abord un **compte de service** (`POST /iam/v1/service-accounts`), puis une clé API à son nom.

Une clé API donne accès à `/api/v1` mais **jamais** à l'administration IAM.

---

## 3. Permissions et rôles

| Permission | Donne accès à |
|---|---|
| `directory.read` / `directory.write` | entreprises, contacts, rattachements, adresses, équipes, membres d'équipe, consentements |
| `catalog.read` / `catalog.write` | offres, formations, modules |
| `documents.read` / `documents.write` | fichiers (métadonnées), pièces jointes |
| `requests.read` / `requests.write` | demandes, notes, demandes du site |
| `integrations.read` / `integrations.write` | connexions externes |
| `audit.read` | journal d'audit |

| Rôle | Permissions maximales | Administration IAM |
|---|---|---|
| `owner` | toutes | oui, y compris les autres propriétaires |
| `admin` | toutes | oui, sauf sur les propriétaires |
| `editor` | lecture + écriture sur directory, catalog, documents, requests | non |
| `viewer` | lecture sur directory, catalog, documents, requests | non |

Règles :

- **Toute écriture exige aussi la permission de lecture** correspondante.
- Un `viewer` ne peut jamais écrire, même avec une clé API qui le prétendrait : la base le refuse.
- `GET /api/v1/me` renvoie les permissions réellement accordées au jeton.

---

## 4. Conventions communes

### 4.1 Réponses

Un élément :

```json
{ "data": { "id": "…", "…": "…", "version": "1731402000123456" } }
```

Une liste :

```json
{ "data": [ … ], "page": { "limit": 25, "offset": 0, "has_more": true } }
```

`has_more` indique s'il existe une page suivante (`offset + limit`). Le total n'est pas calculé.

### 4.2 Listes : pagination, tri, recherche, filtres

| Paramètre | Valeur | Défaut |
|---|---|---|
| `limit` | 1 à 100 | 25 |
| `offset` | 0 à 100 000 | 0 |
| `sort` | un champ autorisé, préfixé de `-` pour l'ordre décroissant | selon la ressource |
| `q` | recherche partielle, insensible à la casse, 1 à 100 caractères | — |
| `archived` | `false` (actifs), `true` (archivés), `all` | `false` |
| filtres | égalité stricte sur les champs listés pour chaque ressource | — |

`q` et `archived` n'existent que sur les ressources qui les déclarent (§6). **Tout paramètre inconnu donne `400`**, comme une valeur hors liste.

Exemple : `GET /api/v1/companies?kind=customer&q=dupont&sort=-created_at&limit=50`

### 4.3 Modification et verrouillage optimiste

Chaque ressource modifiable expose un champ `version` (et l'en-tête `ETag` en lecture unitaire). Une modification doit le renvoyer :

```http
PATCH /api/v1/companies/7e1d…
If-Match: "1731402000123456"
Content-Type: application/json

{ "phone": "+33 1 23 45 67 89" }
```

| Cas | Réponse |
|---|---|
| `If-Match` absent ou invalide | `428 precondition_required` |
| La ressource a changé depuis la lecture | `412 version_mismatch` : relire, puis réessayer |
| Corps vide | `400` |

`PATCH` ne modifie que les champs fournis. Un champ facultatif peut être vidé avec `null`.

### 4.4 Création idempotente

Toute création (`POST` qui crée) accepte un en-tête facultatif :

```
Idempotency-Key: 8 à 128 caractères [A-Za-z0-9._:-]
```

- Même clé et même contenu : la réponse d'origine est renvoyée (`201`, en-tête `Idempotency-Replayed: true`), sans nouvelle création.
- Même clé, contenu ou route différents : `409 idempotency_conflict`.
- Deux envois simultanés de la même clé créent un seul élément.

La clé est propre à l'organisation.

### 4.5 Archivage

Sur les ressources archivables : `POST /api/v1/<ressource>/{id}/archive` et `POST /api/v1/<ressource>/{id}/restore`, sans corps. Réponse `200` avec l'élément. L'opération peut être répétée sans effet supplémentaire.

### 4.6 En-têtes

| En-tête | Sens |
|---|---|
| `X-Request-Id` (requête, facultatif) | Identifiant de corrélation, 8 à 64 caractères. Sinon généré. Toujours renvoyé en réponse. |
| `RateLimit-Limit`, `RateLimit-Remaining` | Quota de la fenêtre en cours. |
| `Retry-After` | Secondes d'attente après un `429`. |

### 4.7 Limitation de débit

Par adresse IP cliente, sur une fenêtre de `RATE_LIMIT_WINDOW_MS` (60 s par défaut) :

- `RATE_LIMIT_MAX` requêtes (300 par défaut) sur chaque service ;
- `RATE_LIMIT_AUTH_MAX` (20 par défaut) sur `POST /iam/v1/sessions` et `POST /iam/v1/invitations/accept`.

Au-delà : `429 rate_limited`.

### 4.8 Formats

- Identifiants : UUID.
- Dates : ISO 8601 UTC.
- E-mails : convertis en minuscules.
- Téléphones : 3 à 30 caractères parmi chiffres, espaces, `+ ( ) . -`.
- Codes pays : ISO 3166-1 alpha-2 en majuscules (`FR`).
- Textes : espaces de début et de fin retirés, longueur minimale 1.

---

## 5. Erreurs

```json
{
  "error": {
    "code": "invalid_request",
    "message": "Paramètres invalides.",
    "details": [ { "field": "email", "message": "Invalid email address" } ],
    "request_id": "9b0f…"
  }
}
```

| HTTP | `code` | Cause |
|---|---|---|
| 400 | `invalid_request` | Paramètre ou champ invalide, inconnu, ou corps vide sur un `PATCH`. `details` liste les champs. |
| 400 | `invalid_json` | Corps non JSON. |
| 401 | `unauthorized` | Jeton absent, invalide, expiré ou révoqué. |
| 403 | `forbidden` | Permission manquante (le message la nomme) ou opération interdite. |
| 404 | `not_found` | Inexistant **ou** appartenant à une autre organisation. |
| 409 | `duplicate` | Contrainte d'unicité (ex. slug d'offre déjà pris). |
| 409 | `idempotency_conflict` | Clé d'idempotence déjà utilisée pour une autre requête. |
| 409 | `conflict` | Règle métier (ex. dernier propriétaire, membre déjà actif). |
| 409 | `organization_required` | Connexion : préciser l'organisation. |
| 409 | `concurrent_update` | Conflit transactionnel : réessayer. |
| 412 | `version_mismatch` | `If-Match` périmé. |
| 413 | `payload_too_large` | Corps trop volumineux. |
| 422 | `unprocessable` | Référence introuvable, ou règle du référentiel non respectée. |
| 428 | `precondition_required` | `If-Match` manquant. |
| 429 | `rate_limited` | Trop de requêtes. |
| 503 | `not_configured` / `unavailable` | Fonction non configurée, ou base indisponible. |
| 504 | `timeout` | Délai de traitement dépassé. |
| 500 | `internal_error` | Erreur inattendue. Le détail n'est jamais renvoyé ; il est journalisé avec le `request_id`. |

---

## 6. API métier `/api/v1`

### Récapitulatif des routes

Légende : **L** = `GET /` et `GET /{id}`, **C** = `POST /`, **M** = `PATCH /{id}`, **A** = `POST /{id}/archive` et `/restore`.

| Ressource | L | C | M | A | Permission |
|---|---|---|---|---|---|
| `companies` | ✓ | ✓ | ✓ | ✓ | directory |
| `contacts` | ✓ | ✓ | ✓ | ✓ | directory |
| `company-contacts` | ✓ | ✓ | ✓ | — | directory |
| `addresses` | ✓ | ✓ | ✓ | — | directory |
| `teams` | ✓ | ✓ | ✓ | ✓ | directory |
| `team-members` | ✓ | ✓ | — | — | directory |
| `offerings` | ✓ | ✓ | ✓ | ✓ | catalog |
| `courses` | ✓ | ✓ | ✓ | — | catalog |
| `course-modules` | ✓ | ✓ | ✓ | — | catalog |
| `files` | ✓ | ✓ | ✓ | ✓ | documents |
| `attachments` | ✓ | ✓ | — | — | documents |
| `requests` | ✓ | ✓ | ✓ | — | requests |
| `request-notes` | ✓ | ✓ | ✓ | — | requests |
| `connections` | ✓ | ✓ | ✓ | — | integrations |
| `audit-events` | ✓ | — | — | — | audit.read |
| `applications` | liste | — | — | — | jeton valide |
| `application-plans` | liste | — | — | — | jeton valide |
| `subscriptions` | ✓ | — | — | — | jeton valide |
| `organization-applications` | liste | — | — | — | jeton valide |

Routes spécifiques : `GET /me`, `GET /organization`, `GET|POST /contacts/{id}/communication-preferences`, `GET /site/contact-submissions`, `GET /site/contact-submissions/{id}`, `POST /site/contact-submissions/{id}/retry`, `GET /openapi.json`.

Toutes les ressources renvoient `id`, `created_at`, `updated_at` et `version`, sauf mention contraire.

### 6.1 Profil et organisation

**`GET /me`** : identité du jeton.

```json
{ "data": { "user_id": "…", "organization_id": "…", "permissions": ["catalog.read", "directory.read"] } }
```

**`GET /organization`** : l'organisation courante. Champs : `id`, `slug`, `name`, `legal_name`, `registration_number`, `country_code`, `timezone`, `locale`, `status`, `created_at`, `updated_at`. Lecture seule.

### 6.2 Entreprises — `/companies`

Carnet d'adresses : clients, prospects, fournisseurs, partenaires.

| Champ | Type | Création | Notes |
|---|---|---|---|
| `name` | texte ≤ 200 | **requis** | |
| `kind` | `prospect` · `customer` · `supplier` · `partner` · `other` | facultatif | |
| `legal_name` | texte ≤ 200 | facultatif | |
| `registration_number` | texte ≤ 50 | facultatif | SIREN/SIRET, etc. |
| `email` | e-mail | facultatif | |
| `phone` | téléphone | facultatif | |
| `website` | URL http(s) ≤ 500 | facultatif | |
| `archived_at` | date | lecture seule | posée par `/archive` |

Filtres : `kind`. Recherche `q` : `name`, `legal_name`, `email`. Tris : `name` (défaut), `created_at`, `updated_at`. Archivage : oui.

```http
POST /api/v1/companies
Authorization: Bearer …
Idempotency-Key: crm-import-4821

{ "name": "Dupont SARL", "kind": "customer", "email": "contact@dupont.fr" }
```

### 6.3 Contacts — `/contacts`

| Champ | Type | Création |
|---|---|---|
| `given_name` | texte ≤ 80 | **requis** |
| `family_name` | texte ≤ 80 | **requis** |
| `email` | e-mail | facultatif |
| `phone` | téléphone | facultatif |
| `job_title` | texte ≤ 120 | facultatif |
| `archived_at` | date | lecture seule |

Filtres : `email`. Recherche : `given_name`, `family_name`, `email`. Tris : `family_name` (défaut), `given_name`, `created_at`, `updated_at`. Archivage : oui.

#### Consentements — `/contacts/{id}/communication-preferences`

Journal **en ajout seul** : un consentement ne se modifie ni ne se supprime ; on enregistre une nouvelle décision.

- `GET` : historique complet (`directory.read`).
- `POST` : nouvelle décision (`directory.write` + `directory.read`). Accepte `Idempotency-Key`.

| Champ | Type | Création |
|---|---|---|
| `purpose` | `[a-z][a-z0-9_.-]{1,63}`, ex. `newsletter` | **requis** |
| `channel` | `email` · `sms` · `phone` | **requis** |
| `allowed` | booléen | **requis** |
| `source` | texte ≤ 100, ex. `formulaire-site` | **requis** |
| `notice_version` | texte ≤ 50 ou `null` | facultatif |

Réponse : `id`, `contact_id`, `purpose`, `channel`, `allowed`, `recorded_at`, `source`, `notice_version`.

### 6.4 Rattachements contact ↔ entreprise — `/company-contacts`

| Champ | Type | Création | Modification |
|---|---|---|---|
| `company_id` | UUID | **requis** | non |
| `contact_id` | UUID | **requis** | non |
| `relationship` | texte ≤ 100, ex. `Directeur` | facultatif | oui |

Filtres : `company_id`, `contact_id`. Tri : `created_at` (défaut décroissant). Un rattachement ne peut pas être retiré (limite du référentiel).

### 6.5 Adresses — `/addresses`

Une adresse appartient à **une** entreprise **ou** à **un** contact, jamais aux deux.

| Champ | Type | Création | Modification |
|---|---|---|---|
| `company_id` | UUID | l'un des deux | non |
| `contact_id` | UUID | l'un des deux | non |
| `label` | texte ≤ 50, ex. `Siège` | facultatif | oui |
| `line1` | texte ≤ 200 | **requis** | oui |
| `line2` | texte ≤ 200 | facultatif | oui |
| `postal_code` | texte ≤ 20 | facultatif | oui |
| `city` | texte ≤ 120 | **requis** | oui |
| `country_code` | `FR`, `BE`… | **requis** | oui |

Filtres : `company_id`, `contact_id`. Tris : `created_at` (défaut décroissant), `city`.

### 6.6 Équipes — `/teams` et `/team-members`

`/teams` : `name` (texte ≤ 120, requis). Recherche : `name`. Tris : `name` (défaut), `created_at`. Archivage : oui.

`/team-members` : `team_id` et `user_id` (UUID, requis). L'utilisateur doit être membre de l'organisation. Filtres : `team_id`, `user_id`. Pas de modification ni de retrait.

### 6.7 Offres — `/offerings`

Prestations, formations et logiciels proposés.

| Champ | Type | Création | Modification |
|---|---|---|---|
| `slug` | `[a-z0-9][a-z0-9-]{1,80}`, unique | **requis** | oui |
| `name` | texte ≤ 200 | **requis** | oui |
| `kind` | `service` · `course` · `software` | **requis** | non |
| `description` | texte ≤ 10 000 | facultatif | oui |
| `status` | `draft` · `published` · `archived` | facultatif | oui |

Filtres : `kind`, `status`. Recherche : `name`, `slug`. Tris : `name` (défaut), `created_at`, `updated_at`.

Archivage : `/archive` passe `status` à `archived`, `/restore` le repasse à `draft`. Il n'y a pas de paramètre `archived` en liste : filtrer par `status`.

### 6.8 Formations — `/courses` et `/course-modules`

`/courses` : descriptif pédagogique d'une offre de type `course`.

| Champ | Type | Création | Modification |
|---|---|---|---|
| `offering_id` | UUID d'une offre `kind = course` | **requis** | non |
| `objectives` | texte ≤ 5 000 | facultatif | oui |
| `prerequisites` | texte ≤ 5 000 | facultatif | oui |
| `level` | texte ≤ 50 | facultatif | oui |
| `duration_minutes` | entier 1 à 1 000 000 | facultatif | oui |

Une offre d'un autre type donne `422`. Filtre : `offering_id`.

`/course-modules` :

| Champ | Type | Création | Modification |
|---|---|---|---|
| `course_id` | UUID | **requis** | non |
| `position` | entier 1 à 10 000 | **requis** | oui |
| `title` | texte ≤ 200 | **requis** | oui |
| `content` | texte ≤ 50 000 | facultatif | oui |

Filtre : `course_id`. Tris : `position` (défaut), `created_at`.

### 6.9 Fichiers — `/files` et `/attachments`

L'API gère **uniquement les métadonnées**. Le dépôt et le téléchargement du contenu ne sont pas encore raccordés.

`/files` :

| Champ | Type | Création | Modification |
|---|---|---|---|
| `name` | texte ≤ 255 | **requis** | oui |
| `media_type` | type MIME, ex. `application/pdf` | **requis** | non |
| `size_bytes` | entier ≥ 0 | **requis** | non |
| `sha256` | 64 caractères hexadécimaux | facultatif | non |
| `storage_key` | texte | lecture seule | générée par le serveur, préfixée par l'organisation |
| `archived_at` | date | lecture seule | |

Recherche : `name`. Tris : `created_at` (défaut décroissant), `name`, `size_bytes`. Archivage : oui.

`/attachments` : rattache un fichier à **une** entreprise **ou** à **un** contact. Champs : `file_id` (requis), `company_id` ou `contact_id`. Filtres : `file_id`, `company_id`, `contact_id`. Pas de modification.

### 6.10 Demandes — `/requests` et `/request-notes`

Demandes entrantes (devis, contact, support).

| Champ | Type | Création | Modification |
|---|---|---|---|
| `subject` | texte ≤ 200 | **requis** | non |
| `message` | texte ≤ 5 000 | **requis** | non |
| `source` | `[a-z][a-z0-9_-]{1,39}`, ex. `site`, `telephone` | facultatif | non |
| `details` | objet plat, ≤ 40 clés, valeurs texte ≤ 2 000, nombre, booléen ou `null` | facultatif | non |
| `company_id` | UUID | facultatif | oui |
| `contact_id` | UUID | facultatif | oui |
| `status` | `new` · `in_progress` · `closed` · `spam` | lecture seule | oui |

Le contenu d'origine ne se réécrit pas : seuls le statut et les liens évoluent. Filtres : `status`, `company_id`, `contact_id`. Recherche : `subject`. Tris : `created_at` (défaut décroissant), `updated_at`.

Chaque création déclenche l'événement `web.request.created`, envoyé aux connexions activées (§8).

`/request-notes` : notes internes. `request_id` (requis à la création), `body` (texte ≤ 5 000, modifiable). Filtre : `request_id`. Tri : `created_at` (défaut croissant).

### 6.11 Demandes du site vitrine — `/site/contact-submissions`

Lecture des demandes reçues par le formulaire du site ProDigital et relance de leurs envois. Réservé aux membres de l'organisation liée au site. Pour toute autre organisation, la réponse est `404`. Sans `SITE_DATABASE_URL`, la réponse est `503`.

| Route | Permission | Description |
|---|---|---|
| `GET /site/contact-submissions?limit=&offset=` | `requests.read` | Liste, plus récentes d'abord : `id`, `created_at`, `given_name`, `family_name`, `email`, `company`, `subject`, `subject_group`, `operations` (état de chaque envoi, ex. `{"email":"succeeded","crm":"failed"}`). |
| `GET /site/contact-submissions/{id}` | `requests.read` | Détail avec `details`, `message`, `source`, `operations` (tentatives, prochaine tentative, dernière erreur, identifiant externe) et `events` (historique). |
| `POST /site/contact-submissions/{id}/retry` | `requests.read` + `requests.write` | Remet en file les envois en échec (e-mail, Genesis CRM). Réponse : `{ "requeued": ["crm"] }`. Les envois réussis ne sont jamais renvoyés. |

Les demandes elles-mêmes sont créées uniquement par l'API du site (`server/`) et ne sont pas modifiables.

### 6.12 Connexions externes — `/connections`

Destinations des événements : webhooks et e-mails de notification.

| Champ | Type | Création | Modification |
|---|---|---|---|
| `provider` | `webhook` · `email` | **requis** | non |
| `name` | texte ≤ 120 | **requis** | oui |
| `status` | `disabled` · `enabled` (`error` posé par l'exploitation) | lecture seule | oui |

Filtres : `provider`, `status`. Tris : `name` (défaut), `created_at`.

Une connexion est créée désactivée et sans secret. **Le secret (URL, clé de signature, destinataire) n'est jamais transmis par l'API.** L'exploitation l'enregistre dans le coffre (§9), puis on active la connexion par `PATCH { "status": "enabled" }`.

### 6.13 Journal d'audit — `/audit-events`

Lecture seule, `audit.read`. Toute écriture dans l'organisation y est tracée, y compris les opérations IAM.

Champs : `id`, `actor_user_id`, `actor_database_role`, `action` (ex. `INSERT`, `UPDATE`, `iam.session.issued`), `entity_type` (ex. `core.companies`), `entity_id`, `occurred_at`. Pas de `version` ni de `updated_at`.

Filtres : `entity_type`, `entity_id`, `actor_user_id`, `action`. Tri : `occurred_at` (défaut décroissant).

### 6.14 Plateforme (lecture seule)

Accessibles à tout jeton valide. Pas de création ni de modification par l'API.

| Route | Champs | Notes |
|---|---|---|
| `GET /applications` | `code`, `name`, `active` | Applications de la plateforme. Liste seulement. |
| `GET /application-plans` | `application_code`, `code`, `name`, `limits`, `published` | Filtre : `application_code`. Liste seulement. |
| `GET /subscriptions` | `id`, `application_code`, `plan_code`, `status`, `starts_at`, `ends_at` | Filtres : `application_code`, `status` (`pending`, `trialing`, `active`, `past_due`, `suspended`, `cancelled`, `ended`). |
| `GET /organization-applications` | `application_code`, `status`, `starts_at`, `ends_at` | Applications activées pour l'organisation. Liste seulement. |

---

## 7. Service IAM `/iam/v1`

Toutes les routes, sauf `POST /sessions` et `POST /invitations/accept`, exigent une **session** (pas une clé API) d'un membre `owner` ou `admin`. Sinon : `403`.

Règles permanentes :

- un `admin` ne nomme pas de propriétaire et ne modifie pas un propriétaire ;
- personne ne modifie sa propre appartenance ;
- l'organisation garde toujours au moins un propriétaire actif (`409` sinon) ;
- un changement de rôle ou une suspension révoque immédiatement tous les jetons du membre ;
- chaque opération est inscrite au journal d'audit.

### 7.1 Sessions

| Route | Corps | Réponse |
|---|---|---|
| `POST /sessions` | `{ id_token, organization? }` | `201`, voir §2.1 |
| `DELETE /sessions/current` | — | `204` |

### 7.2 Membres

**`GET /members`** : `user_id`, `email`, `given_name`, `family_name`, `role`, `status` (`active`, `suspended`, `revoked`), `user_status`, `created_at`.

**`PATCH /members/{userId}`** :

```json
{ "role": "editor" }
{ "status": "suspended" }
```

Au moins un des deux champs. `role` : `owner` · `admin` · `editor` · `viewer`. `status` : `active` · `suspended` · `revoked`. Réponse : `user_id`, `role`, `status`.

### 7.3 Invitations

| Route | Corps | Réponse |
|---|---|---|
| `GET /invitations` | — | `id`, `email`, `role`, `expires_at`, `accepted_at`, `revoked_at`, `created_at` |
| `POST /invitations` | `{ "email": "…", "role": "admin" \| "editor" \| "viewer" }` | `201` avec `token` (affiché une seule fois) |
| `DELETE /invitations/{id}` | — | `204` ; `404` si déjà acceptée ou révoquée |
| `POST /invitations/accept` | `{ "invitation_token": "…", "id_token": "…" }` | `201` : une session (§2.1) |

L'API **n'envoie pas l'invitation** : l'administrateur transmet le jeton à l'invité. L'invitation expire après `INVITATION_TTL_HOURS` (72 h par défaut). Pour l'accepter, l'ID token doit porter un e-mail **vérifié** par le fournisseur et **identique** à l'e-mail invité. On ne peut pas inviter directement un propriétaire.

### 7.4 Jetons, clés API et comptes de service

**`GET /tokens`** : sessions et clés de l'organisation, sans le jeton lui-même : `id`, `user_id`, `kind`, `label`, `scopes`, `created_at`, `expires_at`, `revoked_at`.

**`POST /api-keys`** :

```json
{
  "label": "Synchronisation ERP",
  "scopes": ["directory.read", "directory.write"],
  "expires_in_days": 90,
  "user_id": "…"
}
```

- `user_id` est facultatif (par défaut, l'appelant). Le titulaire doit être un membre actif.
- `scopes` ne peut pas dépasser le rôle du titulaire : `422` sinon.
- `expires_in_days` va de 1 à `API_KEY_MAX_DAYS` (365 par défaut).
- Réponse `201` au même format qu'une session, avec `kind: "api_key"` et le `token` affiché une seule fois.

**`DELETE /tokens/{id}`** : révoque une session ou une clé. `204`.

**`POST /service-accounts`** : `{ "name": "ERP", "role": "editor" }` → `201` `{ user_id, name, role }`. Le compte n'a pas d'identité de connexion : il n'agit que par clé API. Rôles possibles : `admin`, `editor`, `viewer`.

### 7.5 Exemple de mise en service d'un logiciel tiers

```sh
# 1. compte de service
curl -X POST https://<hôte>/iam/v1/service-accounts \
  -H "Authorization: Bearer $SESSION" -H "Content-Type: application/json" \
  -d '{"name":"ERP","role":"editor"}'
# 2. clé API à son nom (user_id renvoyé à l'étape 1)
curl -X POST https://<hôte>/iam/v1/api-keys \
  -H "Authorization: Bearer $SESSION" -H "Content-Type: application/json" \
  -d '{"user_id":"<id>","label":"ERP prod","scopes":["directory.read","directory.write"],"expires_in_days":90}'
# 3. utilisation
curl https://<hôte>/api/v1/companies -H "Authorization: Bearer $CLE_API"
```

---

## 8. Webhooks et notifications

Un événement est émis à la création d'une demande (`POST /api/v1/requests`). Il est enregistré dans la même transaction que la demande, puis envoyé par le worker à chaque connexion **activée** de l'organisation.

### 8.1 Webhook

```http
POST <url du coffre>
Content-Type: application/json
User-Agent: ProDigital-Core/1
X-ProDigital-Event: web.request.created
X-ProDigital-Signature: sha256=<HMAC-SHA256 hexadécimal du corps brut>
Idempotency-Key: <id de l'événement>

{
  "id": "<id de l'événement>",
  "type": "web.request.created",
  "organization_id": "…",
  "data": {
    "request_id": "…", "subject": "…", "source": "site", "status": "new",
    "company_id": null, "contact_id": null, "created_at": "…"
  }
}
```

Pour le destinataire :

- **Vérifier la signature** : calculer le HMAC-SHA256 du corps brut avec `signing_secret`, puis comparer en temps constant.
- **Dédupliquer** avec `Idempotency-Key` : la livraison est « au moins une fois ».
- Répondre en `2xx`. Un corps `{ "id": "…" }` est conservé comme référence externe.
- Toute autre réponse, une redirection ou un dépassement de délai entraîne une relance après 30 s, 2 min, 10 min, 30 min, 1 h puis 3 h (`WORKER_BACKOFF_SECONDS`). Au-delà, l'événement passe en `failed`, relançable à la main.
- L'URL doit être en **HTTPS**.

Le message, les coordonnées et `details` de la demande ne sont pas transmis : le destinataire les lit par l'API.

### 8.2 E-mail

Une connexion `email` envoie par SMTP une notification « Nouvelle demande : <sujet> » avec la référence de la demande, sans son contenu.

### 8.3 Contenu du secret

Fichier JSON `SECRETS_DIR/<référence>` ou variable `PD_SECRET_<RÉFÉRENCE>` :

```json
{ "url": "https://exemple.fr/hooks/prodigital", "signing_secret": "au moins 16 caractères" }
{ "to": "equipe@exemple.fr" }
```

---

## 9. Commandes d'exploitation (CLI)

Ces commandes ne sont pas exposées en HTTP. Elles se lancent dans le conteneur concerné.

### `core-iam` : `node dist/iam/cli.js <commande>`

| Commande | Options |
|---|---|
| `org:list` | — |
| `org:create` | `--slug --name` |
| `org:status` | `--slug --status active\|suspended\|archived` |
| `app:set` | `--org --app --status enabled\|disabled\|suspended` |
| `user:create` | `--email --given-name --family-name` |
| `identity:link` | `--email --issuer --subject` |
| `member:set` | `--org --email --role owner\|admin\|editor\|viewer` |
| `token:issue` | `--org --email --label --scopes a,b --days n` (clé affichée une seule fois) |
| `token:revoke` | `--id` |

Amorçage du premier propriétaire : `user:create`, puis `identity:link`, puis `member:set --role owner`.

### `core-worker` : `node dist/worker/cli.js <commande>`

| Commande | Options |
|---|---|
| `outbox:list` | `[--status pending\|running\|succeeded\|failed]` |
| `outbox:retry` | `--id` |
| `deliveries:list` | `[--status …]` |
| `deliveries:retry` | `--id` |
| `secret:set` | `--org --connection --ref` (référence du coffre, jamais le secret) |
| `drain` | Un cycle de traitement immédiat. |

---

## 10. Supervision

Disponibles sur chaque service, sans authentification sauf `/metrics` :

| Route | Réponse |
|---|---|
| `GET /healthz` | `200 {"status":"ok"}` si le processus tourne. |
| `GET /readyz` | `200 {"status":"ready"}` si la base répond, sinon `503`. |
| `GET /metrics` | Format Prometheus. Exige `Authorization: Bearer <METRICS_TOKEN>`, sinon `404`. |
| `GET /api/v1/openapi.json` | Spécification OpenAPI 3 de l'API métier. |

Les journaux sont en JSON, une ligne par requête : `request_id`, méthode, chemin **sans** paramètres, statut et durée. Aucun jeton, secret ni terme de recherche n'y figure.
