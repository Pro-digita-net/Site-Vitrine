-- Retour arrière de la migration 003 (administrateur, psql -1 -f). Rétablit l'état du socle :
-- les fonctions redeviennent exécutables par PUBLIC. À n'utiliser que pour revenir strictement à foundation_v1.
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA iam, audit, core_meta, core, catalog, documents, web, integration, notifications TO PUBLIC;
DELETE FROM core_meta.migrations WHERE version = '003_function_privileges';
