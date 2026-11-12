# Validation locale — 12 novembre 2026

Moteur : PostgreSQL 17 (conteneur jetable, sans port publié). Aucune connexion à la production.

- Import Core complet sur base vide : réussi, 312 tables au total, registres techniques inclus.
- Réapplication du fichier Core complet : réussie.
- Import Platform sur base vide séparée : réussi, 20 tables platform et 3 tables techniques.
- Correctif site seul sur le Core créé : réussi.
- INSERT demande + deux opérations + historique puis UPDATE opération, avec SET ROLE site_vitrine : réussi ; transaction annulée.

Les sorties sont conservées dans les fichiers validation-*.log. Le conteneur temporaire a été supprimé après les tests.

Non testé : import sur une copie de la base de production actuelle, connexion réseau Coolify, authentification SMTP et traitement réel par Genesis. Un export de migrations ne prouve pas la compatibilité avec des modifications manuelles d'une base existante.
