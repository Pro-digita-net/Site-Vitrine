# ProDigital Core — SQL pour PostgreSQL / Coolify

> Ancienne proposition basée sur Genesis, conservée pour référence. Pour le socle commun multi-entreprises demandé ensuite, utiliser `../prodigital-core-v1/prodigital-core.sql` et lire son `INSTALLATION.md`. Ne pas importer les deux modèles ensemble.

Export du 12 novembre 2026, provenant des migrations réelles de `C:/GENESIS/infra/prodigital/database` et de l'API de ce site. Aucun secret inclus.

## Quel fichier utiliser ?

- `01-prodigital-core-complet.sql` : base `prodigital`, domaines métier Core/CRM/ITSM/projets/facturation, identité, assistants, droits applicatifs, demandes web et les trois tables du formulaire du site. Inclut 25 migrations Genesis et les compléments du site.
- `02-prodigital-platform.sql` : base séparée `prodigital_platform`, abonnements, installations, offres, quotas et droits plateforme. Ne pas importer dans `prodigital`.
- `03-site-contact-seulement.sql` : si Core fonctionne déjà et que seul le formulaire manque, ce fichier crée les tables `site.contact_submissions`, `site.contact_operations`, `site.contact_events`, le registre de migration et les droits `site_vitrine`.
- `04-verifier-contact.sql` : teste une demande, ses opérations et son historique sous le rôle réel du site, puis annule les écritures. Aucun e-mail ni appel CRM.

Le manifeste indique les sources et leurs empreintes. Les données de démonstration (clients ACME/TechStart, offres de démonstration) et le seed d'inventaire d'assistants sont exclus. Les migrations 030–034 concernent les bases des installations clientes SaaS : elles ne sont pas destinées à Core. Les fonctions, contraintes, index, politiques et référentiels techniques des migrations retenues sont conservés.

## Import depuis Coolify

Il faut PostgreSQL **15 ou plus** et son administrateur (généralement `postgres`). Les fichiers utilisent **psql**, y compris ses commandes `\if` et `\gset`. Ne pas les coller dans un éditeur SQL générique ni dans les variables d'environnement.

1. Sauvegarder la base existante via Coolify. Pour un Core existant, essayer le fichier complet sur une restauration de cette sauvegarde avant de l'appliquer : une installation ancienne peut avoir des migrations différentes. Pour le problème du formulaire seul, privilégier le fichier 03.
2. Créer les bases si elles n'existent pas (`createdb -U postgres prodigital`, puis éventuellement `createdb -U postgres prodigital_platform`). Ne pas recréer une base existante.
3. Copier le fichier choisi dans le conteneur PostgreSQL (par exemple dans `/tmp/01-prodigital-core-complet.sql`). Depuis le terminal du serveur, `docker cp CHEMIN_DU_FICHIER NOM_CONTENEUR:/tmp/01-prodigital-core-complet.sql` ; le chemin doit désigner un fichier présent sur ce serveur.
4. Dans le terminal du conteneur PostgreSQL, exécuter :

```sh
psql -U postgres -d prodigital -v ON_ERROR_STOP=1 -f /tmp/01-prodigital-core-complet.sql
```

Pour le correctif site seul, utiliser le fichier 03 avec la même base. Pour la plateforme, utiliser le fichier 02 avec `-d prodigital_platform`.

Les scripts ne suppriment aucune base. Les migrations ont leurs transactions d'origine ; l'import complet n'est pas une unique transaction. L'arrêt sur erreur laisse les migrations précédentes appliquées. Le registre `deployment.bundle_migrations` évite de réexécuter les étapes terminées par cet export et contrôle leurs empreintes ; il ne remplace pas une vérification de compatibilité avec une base préexistante.

## Compte du site

Les rôles absents sont créés **NOLOGIN**, sans mot de passe. Les rôles déjà présents gardent leurs identifiants. Dans `psql -U postgres -d prodigital`, pour activer un nouveau compte :

```sql
ALTER ROLE site_vitrine LOGIN;
\password site_vitrine
```

`\password` demande le mot de passe de façon interactive. Pour Genesis/Orbit nouveaux, activer leurs rôles et définir leur mot de passe de la même manière seulement si ces applications sont utilisées.

Dans les variables Coolify du service `api`, configurer :

```text
DATABASE_URL=postgresql://site_vitrine:MOT_DE_PASSE_ENCODE@HOTE_POSTGRES_INTERNE:5432/prodigital
```

Le compte doit correspondre à celui créé, le mot de passe doit être encodé pour une URL, et le conteneur API doit pouvoir joindre PostgreSQL sur le réseau Docker. Redéployer le site après modification des variables.

Les migrations du site sont déjà enregistrées dans `site.schema_migrations`. Aucun besoin d'activer MIGRATE_ON_START avec le compte applicatif.

## Vérification et e-mails

Copier aussi le fichier 04 et exécuter `psql -U postgres -d prodigital -v ON_ERROR_STOP=1 -f /tmp/04-verifier-contact.sql`. Il doit terminer par ROLLBACK et une liste de tables.

Le SQL prépare le stockage ; il ne configure ni le réseau ni la messagerie. L'envoi exige toujours SMTP_HOST, SMTP_PORT, SMTP_SECURITY, SMTP_USER, SMTP_PASSWORD, SMTP_FROM et CONTACT_NOTIFY_TO dans Coolify. La synchronisation CRM exige GENESIS_URL et GENESIS_SERVICE_TOKEN. Un `/api/health` à `ok` ne valide que la connexion PostgreSQL, pas la messagerie.
