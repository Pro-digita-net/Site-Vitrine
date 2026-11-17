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
| Projets | `realisations` |
| Contact (sujets / questions) | `forms` (+ sujets issus de `saas` / `formations` / expertises statiques) |

Route : `GET /api/v1/public/cms/{organization}/{collection}` (+ médias).

**Repli**

- CMS absent ou erreur sur une collection → repli `shared/data.js` pour cette collection.
- `200` + `data: []` → liste vide conservée.
- Expertises toujours statiques.

**Conservé** : design, animations, responsive, envoi des demandes et e-mails.

**Correctif** : cartes « Nos expertises » / grilles projets — révélation GSAP au chargement (plus d’`autoAlpha: 0` bloqué au scroll).

### Coolify — service `site` (build)

```
VITE_CMS_URL=https://<origine-publique-core>
VITE_CMS_ORG=<slug-organisation>
```

**Core :** `CORS_ALLOWED_ORIGINS` doit inclure `https://pro-digital.net` et `https://www.pro-digital.net`.
