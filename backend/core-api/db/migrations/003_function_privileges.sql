-- PRODIGITAL CORE — migration 003 : correction d'une incohérence du socle (privilèges des fonctions).
--
-- Constat (vérifié sur PostgreSQL 15 avec les comptes applicatifs) : prodigital-core.sql utilise
--   ALTER DEFAULT PRIVILEGES IN SCHEMA ... REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC
-- or un réglage par schéma ne peut pas retirer le droit EXECUTE accordé par défaut à PUBLIC
-- (seul un réglage global le peut). Les fonctions du socle restaient donc exécutables par tous les
-- comptes : pd_core_api pouvait appeler iam.context() et iam.site_organization_id(), pd_site_api
-- pouvait appeler iam.current_organization_id(), etc. Aucune donnée d'une autre organisation n'était
-- exposée (chaque fonction ne renvoie que le contexte de l'appelant), mais cela contredit l'intention
-- du socle : seules les fonctions explicitement accordées doivent être appelables.
--
-- Correction minimale : retrait à PUBLIC, puis ré-attribution exacte des GRANT du socle. Aucune table,
-- politique ou donnée n'est modifiée. Les triggers ne sont pas concernés (aucun EXECUTE requis).

REVOKE EXECUTE ON ALL FUNCTIONS IN SCHEMA iam, audit, core_meta, core, catalog, documents, web, integration, notifications, site FROM PUBLIC;

-- Socle (lignes 137-138 de prodigital-core.sql).
GRANT EXECUTE ON FUNCTION iam.current_organization_id(), iam.current_user_id(), iam.permitted(iam.permission) TO pd_core_api;
GRANT EXECUTE ON FUNCTION iam.site_organization_id() TO pd_site_api;
-- Migration 002.
GRANT EXECUTE ON FUNCTION integration.publish_request_created(uuid) TO pd_core_api;
GRANT EXECUTE ON FUNCTION web.record_communication_preference(uuid, text, text, boolean, text, text) TO pd_core_api;
GRANT EXECUTE ON FUNCTION web.list_communication_preferences(uuid) TO pd_core_api;
