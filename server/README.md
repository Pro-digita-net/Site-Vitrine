# API du formulaire de contact

Service Node (sans framework) appelé par le formulaire du site sur `POST /api/contact-requests`.
Au clic sur « Envoyer ma demande », il :

1. **enregistre** la demande dans PostgreSQL (`site.contact_submissions`) — c'est ce qui déclenche la confirmation affichée au client ;
2. **envoie l'e-mail** de notification (modèle « Une nouvelle demande vous attend ») ;
3. **crée la demande dans Genesis CRM** via `POST /api/sales/public/leads`, avec un récapitulatif complet en lecture seule.

Les opérations 2 et 3 sont indépendantes et relancées automatiquement en cas d'échec. Le navigateur ne voit jamais le jeton Genesis ni les identifiants SMTP.

## Fonctionnement

```
Formulaire ──POST──▶ API ──┬─ transaction ─▶ site.contact_submissions   (demande, immuable)
   (Idempotency-Key)       │                 site.contact_operations    (email: pending, crm: pending)
        ◀── 201 + id ──────┘                 site.contact_events        (historique)
                            worker ──▶ SMTP ─────────▶ e-mail à l'équipe
                                   └─▶ Genesis ──────▶ web.contact_requests (lead)
```

- **Source unique** : les trois opérations lisent la ligne enregistrée ; l'e-mail et le récapitulatif Genesis contiennent donc exactement ce que le client a envoyé, y compris à la dixième relance.
- **Sujets et champs complémentaires** : définis une seule fois dans [`src/contactQuestions.js`](../src/contactQuestions.js), utilisés par le formulaire *et* par la validation du serveur.
- **Doublons** : clé `Idempotency-Key` générée par le navigateur (double clic, renvoi réseau), plus rapprochement e-mail + sujet + message sur 24 h (rechargement de page). Côté Genesis, la clé `site-vitrine:<id>` garantit un seul lead par demande.
- **Relances** : après 30 s, 2 min, 10 min, 30 min, 1 h, 3 h, 6 h, 12 h. Au-delà, l'opération passe en `failed` et attend une relance manuelle ; la demande reste en base. Une opération interrompue par un arrêt brutal est reprise à l'expiration de son bail (2 min).
- **Erreurs définitives** : un refus de Genesis sur le contenu (400, 409, 413, 422) n'est pas relancé. Jeton invalide, Genesis ou messagerie injoignable : relance.
- **Limite connue** : l'e-mail est « au moins une fois ». Si le serveur s'arrête entre l'acceptation SMTP et l'écriture du statut, il peut partir deux fois (même `Message-ID`).

## Lecture seule

| Donnée | Garantie |
| --- | --- |
| `site.contact_submissions` | Trigger : aucune modification possible, même par le propriétaire. Le rôle `site_vitrine` n'a ni `UPDATE` ni `DELETE`. |
| Récapitulatif dans Genesis (`web.contact_requests.message`) | Le rôle `genesis` n'a que `SELECT`/`INSERT` (migration Genesis 015). [`sql/core-contact-requests-readonly.sql`](sql/core-contact-requests-readonly.sql) étend l'interdiction à tous les rôles ; le statut de traitement reste modifiable. |

## Mise en service

1. **Base** — créer le rôle, appliquer le schéma, accorder les droits :
   ```bash
   psql "$URL_PROPRIETAIRE" -c "CREATE ROLE site_vitrine LOGIN PASSWORD '…'"
   DATABASE_URL="$URL_PROPRIETAIRE" npm run migrate
   psql "$URL_PROPRIETAIRE" -v ON_ERROR_STOP=1 -f sql/site-role-grants.sql
   psql "$URL_PROPRIETAIRE" -v ON_ERROR_STOP=1 -f sql/core-contact-requests-readonly.sql   # base Core
   ```
2. **Variables** du service `api` : voir [`.env.example`](../.env.example) (`DATABASE_URL`, `GENESIS_URL`, `GENESIS_SERVICE_TOKEN`, `SMTP_*`).
3. **Réseau** : le conteneur `api` doit joindre PostgreSQL et Genesis.

Si le jeton Genesis ou le SMTP manquent, l'API démarre quand même : les demandes sont enregistrées et les opérations concernées attendent la configuration.

## Exploitation

```bash
npm run ops -- list            # dernières demandes, statut e-mail / CRM
npm run ops -- show <id>       # détail et historique d'une demande
npm run ops -- retry [<id>]    # relance les opérations en échec
```

```sql
-- Demandes dont une opération n'a pas abouti
SELECT s.id, s.created_at, s.email, o.kind, o.status, o.attempts, o.last_error
  FROM site.contact_submissions s JOIN site.contact_operations o ON o.submission_id = s.id
 WHERE o.status <> 'succeeded' ORDER BY s.created_at;
```

## Développement et tests

```bash
npm ci
npm test            # validation, récapitulatif, modèle d'e-mail, relances
npm run test:e2e    # parcours complet (Docker + dépôt Genesis en local)
```

`test:e2e` démarre un PostgreSQL jetable, y applique le schéma `web.contact_requests` et les migrations 015/017 de Genesis, monte le **vrai handler** `server/sales-lead-http.ts` du dépôt Genesis (`GENESIS_REPO`, défaut `C:/GENESIS`), reçoit les e-mails par SMTP authentifié, puis joue : parcours nominal, doubles soumissions, validation, panne Genesis, panne messagerie, jeton invalide, arrêt brutal, relance manuelle, lecture seule, panne de base.

En local avec le site : `node test/e2e.mjs --serve`, puis à la racine `API_PROXY_TARGET=http://127.0.0.1:58788 npm run dev`.
