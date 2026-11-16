# Validation du socle commun — 12 novembre 2026

Exécution locale sur PostgreSQL 17 dans des conteneurs temporaires, sans port publié. Aucun accès à la production ou à Coolify, aucun e-mail envoyé.

- Import transactionnel : réussi, **36 tables** dans la base unique `prodigital`.
- Réimport du même fichier : réussi, empreinte vérifiée, aucune réinitialisation.
- Absence de jeton ou jeton inconnu : aucune donnée privée visible.
- Jeton A : données A accessibles, données B et ProDigital invisibles ; scénario inverse validé avec B.
- Falsification des variables d'organisation/utilisateur : aucun changement de l'identité dérivée du jeton.
- Insert/update inter-entreprises refusés ou sans ligne affectée ; liens entre entreprises différentes refusés par les clés étrangères composites.
- Jetons expirés/révoqués, appartenance suspendue, organisation suspendue : accès refusé.
- Membre viewer et scopes limités : écritures non autorisées refusées.
- Accès aux utilisateurs, appartenances, jetons, secrets et demandes ProDigital depuis le rôle client : refusés.
- Élévation vers postgres ou le compte du site, désactivation RLS, TRUNCATE, DELETE et création dans public : refusés.
- Abonnements isolés, plans non publiés cachés ; modification des abonnements/activations refusée au rôle métier.
- Audit produit lors des écritures, attribution correcte à l'utilisateur, consultation limitée au tenant et modification interdite.
- Compte du site : enregistrement de demande, opérations e-mail/CRM et événements réussis ; données d'une autre organisation invisibles.
- Tables métier portant une organisation : RLS activée et forcée vérifiée ; comptes techniques sans superuser, BYPASSRLS ou appartenance à un rôle privilégié.
- Installation sur un schéma Core préexistant : arrêt attendu ; donnée existante conservée et modifications de l'import annulées.
- Les fixtures sont annulées : état final = 0 utilisateur, 1 organisation ProDigital, 0 demande de contact.

Les journaux `*-test.log` donnent les résultats. L'erreur du journal `existing-database-test.log` est volontaire : elle prouve le refus d'import sur une base existante.

Limites : le futur backend d'authentification/autorisation, les routes API du CRM/ITSM, les téléchargements privés, le réseau Coolify et les envois SMTP ne sont pas testés ici. Les tests SQL ne constituent pas une garantie contre une compromission du serveur ou d'un administrateur.
