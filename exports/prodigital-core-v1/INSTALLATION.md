# ProDigital Core V1 — une seule base commune

**Fichier à importer : `prodigital-core.sql`.** Il remplace la proposition d'export Genesis du dossier voisin `prodigital-core`. Ne pas importer les deux modèles ensemble.

Ce socle contient 36 tables dans la même base PostgreSQL `prodigital`. Il ne crée aucune base séparée et ne reprend pas les 312 tables de l'ancien CRM. Les domaines métier du futur CRM/ITSM seront raccordés par migrations à ce référentiel commun.

## Contenu

- `core` : entreprises utilisatrices (organisations), entreprises de leur carnet d'adresses, contacts, relations, adresses, équipes et membres ; applications, offres d'abonnement, abonnements et activations.
- `iam` : utilisateurs, identités d'authentification, appartenances, invitations, sessions/clés API hachées et affectation du compte technique du site.
- `catalog` : prestations, logiciels et formations, descriptifs et modules de formation.
- `documents` : métadonnées de fichiers privés et rattachements aux contacts/entreprises. Le contenu reste dans un stockage privé externe.
- `web` : demandes et notes internes multi-entreprises, préférences de communication.
- `site` : demandes du formulaire ProDigital, opérations e-mail/CRM et historique ; mêmes colonnes que l'API actuelle, avec organisation ajoutée automatiquement.
- `integration`, `notifications` : connexions externes, références de secrets dans un coffre, correspondances, événements à traiter et notifications.
- `audit`, `core_meta` : traces de modification du référentiel et version de la base.

Seule l'organisation ProDigital est initialisée, avec l'identifiant `00000000-0000-4000-8000-000000000001`. Aucun utilisateur humain, client de démonstration, abonnement, tarif ou mot de passe n'est inventé. CRM et ITSM sont déclarés mais désactivés.

## Conditions d'installation

- PostgreSQL 15 minimum, validation réalisée sur PostgreSQL 17.
- Installer dans une **base vierge** nommée `prodigital`, en tant qu'administrateur PostgreSQL. Le fichier refuse une base contenant un ancien schéma Core/Genesis/site. Il ne supprime ni ne convertit les données existantes.
- Si la base actuelle contient des données, conserver une sauvegarde et préparer leur migration avant remplacement. Ne pas supprimer la base active pour contourner ce contrôle.
- Les deux rôles `pd_core_api` et `pd_site_api` doivent être absents du cluster lors de la première installation ; le script refuse de réutiliser un rôle dont les droits seraient inconnus.
- Exécuter avec **psql**, pas dans un champ de variables Coolify ou un éditeur SQL générique : le fichier utilise `\set`, `\if` et `\gset`.
- Installation en une transaction. Le réimport du même fichier vérifie son empreinte et ne réinitialise rien. Après installation, faire évoluer la base avec une migration, pas en modifiant puis réimportant ce fichier.

## Dans Coolify

1. Utiliser une ressource PostgreSQL destinée à cette base commune. Définir son nom de base initiale à `prodigital`. Si elle est déjà créée vide, la conserver.
2. Déposer `prodigital-core.sql` sur le serveur, puis le copier dans le conteneur PostgreSQL. Exemple depuis le terminal du **serveur** (remplacer le nom du conteneur) :

```sh
docker cp /chemin/prodigital-core.sql NOM_CONTENEUR_POSTGRES:/tmp/prodigital-core.sql
```

3. Dans le terminal du **conteneur PostgreSQL** accessible depuis Coolify :

```sh
psql -U "$POSTGRES_USER" -d prodigital -v ON_ERROR_STOP=1 -f /tmp/prodigital-core.sql
```

Si l'administrateur s'appelle `postgres`, remplacer `"$POSTGRES_USER"` par `postgres`. La dernière étape doit afficher `COMMIT` sans erreur.

4. Définir le mot de passe du compte du site, puis autoriser sa connexion. Ouvrir `psql -U "$POSTGRES_USER" -d prodigital`, puis :

```sql
\password pd_site_api
ALTER ROLE pd_site_api LOGIN;
```

Le mot de passe est demandé interactivement. Il ne figure pas dans le SQL livré. Garder `pd_core_api` désactivé tant que le nouveau backend Core n'est pas raccordé ; son activation suivra le même principe.

5. Dans les variables du service `api` du site :

```text
DATABASE_URL=postgresql://pd_site_api:MOT_DE_PASSE_ENCODE@HOTE_POSTGRES_INTERNE:5432/prodigital
```

Encoder les caractères réservés du mot de passe pour cette URL. Connecter l'API et PostgreSQL au réseau Docker adéquat, puis redéployer le site. Ne pas activer `MIGRATE_ON_START` : le schéma du site est déjà installé et son compte n'a pas les droits d'administration.

Le SQL n'installe pas de SMTP et ne remplace pas les variables SMTP_* ; elles restent nécessaires à l'envoi. La synchronisation Genesis existante requiert encore son endpoint et son jeton. Ce socle n'est pas compatible avec toutes les requêtes de l'ancien CRM : la refonte doit le prendre en compte. L'API du site peut enregistrer et envoyer ses e-mails indépendamment d'un échec CRM.

## Isolation des entreprises et contrat de la future API

`pd_core_api` n'est ni administrateur, ni propriétaire des tables, ni autorisé à contourner la RLS. Les données métier appartiennent à une organisation. Les politiques PostgreSQL contrôlent cette organisation à la lecture et à l'écriture ; les références composites empêchent de relier un contact A à une entreprise B. Les identifiants/organisations d'une ligne ne sont pas déplaçables par une mise à jour.

Les clés et sessions de `iam.access_tokens` sont attachées à un utilisateur **et une organisation**, avec expiration, révocation et scopes. La base vérifie aussi que l'utilisateur, l'organisation et son appartenance sont actifs. Un rôle viewer ne peut pas écrire même avec un scope write. Les invitations, appartenances et jetons ne sont pas modifiables par le rôle API métier.

Le service d'authentification de confiance devra créer les identités, appartenances et sessions après authentification. Il n'est pas implémenté par ce SQL. Ne pas utiliser le compte administrateur pour l'API publique et ne pas donner à `pd_core_api` le droit de créer ses propres jetons. Les mots de passe humains ne sont pas traités dans cette version : raccorder un fournisseur d'identité ou un composant d'authentification dédié.

Pour chaque appel API métier, le backend utilisera le même client PostgreSQL pour cette transaction :

```sql
BEGIN;
-- Requête paramétrée : $1 = jeton secret du demandeur, pas un ID d'entreprise.
SELECT set_config('app.access_token', $1, true);
SELECT * FROM core.companies;
COMMIT;
```

`$1` est un paramètre du pilote PostgreSQL, pas une valeur à concaténer. `true` rend le contexte local à la transaction : il disparaît après COMMIT/ROLLBACK. Toujours annuler la transaction sur erreur avant de rendre la connexion au pool. Sans jeton valide, aucune donnée privée n'est visible. Le token doit être aléatoire (au moins 32 octets cryptographiques) ; seul son SHA-256 binaire est enregistré dans `token_hash`. Ne pas le journaliser.

**Ne pas exposer un terminal SQL ou une route exécutant du SQL fourni par un client.** L'API expose des opérations définies, authentifiées, limitées et paramétrées. Elle applique aussi les droits d'accès aux applications, les quotas et les règles métier. Les plans/abonnements enregistrés ne constituent pas un moteur de paiement ni de quotas automatique.

Le compte `pd_site_api` est réservé au backend du formulaire ProDigital, jamais aux clients de la future API. Son organisation est définie par une liaison privée au nom réel de connexion PostgreSQL (`session_user`). Il ne peut consulter ni contacts Core, ni utilisateurs, ni jetons. En revanche, il peut lire les demandes ProDigital nécessaires au worker d'e-mail : ses identifiants restent strictement côté serveur.

Les tables d'identité privées sont protégées par les droits PostgreSQL et accessibles uniquement à l'administration et aux petites fonctions de validation du contexte. Les tables de traitement interne (outbox, secrets, notifications, consentements) sont fermées aux clients ; leurs futurs workers devront recevoir des fonctions et droits précisément limités. Aucun worker générique ou accès client automatique n'est fourni.

Les métadonnées de fichiers sont isolées ; le stockage externe doit aussi rester privé. Les téléchargements, recherches, exports, caches, sauvegardes et journaux doivent respecter la même isolation. Les erreurs internes de contraintes ne doivent pas être renvoyées telles quelles aux clients.

Cette protection ne prétend pas résister à la compromission d'un administrateur PostgreSQL ou du serveur d'authentification. Référence du mécanisme : [documentation PostgreSQL sur la Row-Level Security](https://www.postgresql.org/docs/17/ddl-rowsecurity.html).

## Vérification

`test-isolation.sql` est à lancer sur une copie de test uniquement, comme administrateur. Il crée temporairement deux entreprises et des jetons factices, teste les accès autorisés/interdits et le formulaire, puis annule tout avec ROLLBACK.

Les preuves locales sont `installation-test.log`, `reimport-test.log` et `isolation-test.log`. Aucun envoi d'e-mail, appel CRM ou changement sur le serveur Coolify n'a été effectué pour ces tests.
