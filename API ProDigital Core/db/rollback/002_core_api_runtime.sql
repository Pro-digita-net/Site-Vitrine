-- Retour arrière de la migration 002 (administrateur, psql -1 -f, après le retour arrière de 003).
-- Arrêter d'abord core-api, core-iam et core-worker. Les données métier, les identités, les jetons,
-- l'outbox et l'audit sont conservés ; seule la table des clés d'idempotence est supprimée.
DROP FUNCTION integration.publish_request_created(uuid);
DROP FUNCTION web.record_communication_preference(uuid, text, text, boolean, text, text);
DROP FUNCTION web.list_communication_preferences(uuid);
DROP INDEX web.communication_preferences_contact;
DROP TABLE core.idempotency_keys;

DROP TRIGGER guard_update ON iam.access_tokens;
DROP TRIGGER guard_update ON iam.invitations;
DROP FUNCTION iam.guard_token_update();
DROP FUNCTION iam.guard_invitation_update();
DROP INDEX iam.invitations_org;

DROP POLICY iam_admin_provisioning ON core.organizations;
DROP POLICY iam_admin_provisioning ON core.organization_applications;
DROP POLICY iam_admin_append ON audit.events;
DROP POLICY worker_queue ON integration.outbox;
DROP POLICY worker_queue ON notifications.deliveries;
DROP POLICY worker_read ON integration.connections;
DROP POLICY worker_secrets ON integration.connection_secrets;
DROP POLICY worker_refs ON integration.external_references;

-- Retire tous les droits accordés aux deux rôles dans cette base, puis les rôles eux-mêmes.
DROP OWNED BY pd_iam_admin, pd_core_worker;
DROP ROLE pd_iam_admin;
DROP ROLE pd_core_worker;
DELETE FROM core_meta.migrations WHERE version = '002_core_api_runtime';
