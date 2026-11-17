# Progression — Site Vitrine ↔ CMS Core

## Périmètre contenu

**Statique (`shared/data.js`) — aucun appel CMS**

- Accueil
- Le Studio
- Expertises

**Dynamique — API publique Core (publié uniquement, pas de brouillons)**

| Page | Collection Core |
| --- | --- |
| Nos logiciels | `saas` |
| Formations | `formations` |
| Contact (sujets / questions) | `forms` (+ sujets issus de `saas` / `formations` / expertises statiques) |

**Retiré** : page Projets (`/projets`) et lien navbar.

Route : `GET /api/v1/public/cms/{organization}/{collection}` (+ médias).

**Repli**

- CMS absent ou erreur sur une collection → repli `shared/data.js` pour cette collection.
- `200` + `data: []` → liste vide conservée (rien de publié = rien affiché).
- `forms` vide → questions intégrées (`shared/contactQuestions.js`) : les demandes restent possibles.
- Expertises toujours statiques.

**Conservé** : design, animations, responsive, envoi des demandes et e-mails.

### 17/11 — Retour des pages statiques à l'affichage du 16/11

- **Cause des cards manquantes en ligne** : le CMS de production répond `200 {"data":[]}` pour toutes les collections, et le bundle déployé lisait encore le CMS pour Accueil / Studio / Expertises. Ce n'était pas un problème d'animation.
- `frontend/src/motion.js` restauré à l'identique du 16/11 (`aeff3a5`) : les révélations au scroll d'Accueil / Studio / Expertises, retirées par les correctifs du 17/11 au matin, sont de retour.
- `shared/cmsCatalog.js` : retrait du repli statique sur liste vide ajouté le 17/11 (`bc2feb4`). Les pages dynamiques n'affichent que le publié.
- Vérifié sur le build de production (PC 1440 px, mobile 390 px), avec un CMS simulé vide puis avec une entrée publiée par collection :
  - pages statiques complètes et identiques dans les deux cas (30 / 10 / 39 éléments) ;
  - entrées publiées affichées sur Logiciels, Formations et Projets ; sujets Formations / Logiciels du formulaire alimentés par le CMS ;
  - questions intégrées toujours présentes.
- Tests : `test-cms-catalog`, `test-contact`, SEO (29 pages) et contact-api (11/11), tous réussis.
- **À faire côté Studio** : publier les SaaS, formations et réalisations. Sinon, ces trois pages restent vides en ligne.
- **Non vérifiable d'ici** : le filtrage des brouillons par l'API publique, qui est hors de ce dépôt (tous ses retours sont vides aujourd'hui).

### Coolify — service `site` (build)

```
VITE_CMS_URL=https://<origine-publique-core>
VITE_CMS_ORG=<slug-organisation>
```

**Core :** `CORS_ALLOWED_ORIGINS` doit inclure `https://pro-digital.net` et `https://www.pro-digital.net`.
