# Progression — Site Vitrine ↔ CMS Core

## Lot 6c — lecture publique + formulaire dynamique

**API Core (lot 6a, `src/core/routes/cms.ts`) :**

- `GET /api/v1/public/cms/{organization}/{collection}`
- `GET /api/v1/public/cms/{organization}/media/{id}`

**Collections → site**

| Collection Core | Site |
| --- | --- |
| `saas` | logiciels (`products`) |
| `formations` | formations |
| `services` | expertises |
| `realisations` | projets |
| `forms` | questions du formulaire de contact |

**Repli statique (`shared/data.js`)**

- CMS non configuré → catalogue statique.
- Collection en erreur réseau/HTTP → repli statique **pour cette collection seulement**.
- Collection en `200` avec `data: []` → **liste vide conservée** (pas de repli).

**Formulaire**

- Sujets : catalogues CMS courants (+ « Autre besoin »).
- Questions : entrée publiée `forms` (slug = id du sujet, ou `subject`/`name`) si `fields[]` est présent ; sinon schémas intégrés / générique.
- Envoi `/api/contact-requests` inchangé (design, animations, idempotence). Sujets CMS libres acceptés côté API (max 120 car.).

**Contrat `forms` (Studio → site)**

```json
{
  "title": "Votre projet web",
  "hint": "…",
  "subject": "Création web",
  "fields": [
    { "id": "goal", "label": "Objectif", "type": "text", "required": true },
    { "id": "kind", "label": "Type", "type": "select", "options": ["A", "B"] }
  ]
}
```

### Coolify — variables

**Service `site` (build args / variables build Vite) :**

```
VITE_CMS_URL=https://<origine-publique-core>
VITE_CMS_ORG=<slug-organisation>
```

Sans ces deux valeurs, le build conserve uniquement `shared/data.js`.

**Service `api` (runtime) :** inchangé — `DATABASE_URL`, Genesis, SMTP, `ALLOWED_ORIGINS`, etc. (voir `.env.example`). Plus de `CORE_API_*`.

**Core (hors ce dépôt) :** `CORS_ALLOWED_ORIGINS` doit inclure `https://pro-digital.net` et `https://www.pro-digital.net`.
