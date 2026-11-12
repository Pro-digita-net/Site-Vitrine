-- PRODIGITAL CORE — migration 002 : droits d'exécution de l'API Core V1.
-- S'applique APRÈS prodigital-core.sql (foundation_v1), par `npm run migrate` (transaction unique,
-- compte administrateur, jamais au démarrage de l'API). Ne modifie aucune table ni politique existante.
--
-- Le socle laisse volontairement fermés : le référentiel iam, les tables de traitement
-- (outbox, notifications, secrets, consentements). Cette migration ouvre le strict nécessaire :
--   pd_iam_admin   : composant d'administration IAM (identités, appartenances, jetons, organisations)
--   pd_core_worker : workers d'intégration (outbox, notifications, références de secrets)
--   pd_core_api    : trois fonctions métier bornées + table d'idempotence
-- Aucun mot de passe : les rôles sont créés NOLOGIN, l'administrateur les active explicitement.

DO $$ BEGIN
 IF EXISTS(SELECT FROM pg_roles WHERE rolname IN ('pd_iam_admin','pd_core_worker'))
 THEN RAISE EXCEPTION 'Rôles pd_iam_admin/pd_core_worker déjà présents : contrôler leurs droits avant migration.'; END IF;
END $$;
CREATE ROLE pd_iam_admin NOLOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT NOREPLICATION NOBYPASSRLS;
CREATE ROLE pd_core_worker NOLOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT NOREPLICATION NOBYPASSRLS;
DO $$ BEGIN
 EXECUTE format('GRANT CONNECT ON DATABASE %I TO pd_iam_admin, pd_core_worker', current_database());
 EXECUTE format('ALTER ROLE pd_iam_admin IN DATABASE %I SET search_path=pg_catalog', current_database());
 EXECUTE format('ALTER ROLE pd_core_worker IN DATABASE %I SET search_path=pg_catalog', current_database());
END $$;
ALTER ROLE pd_iam_admin SET statement_timeout='15s';
ALTER ROLE pd_iam_admin SET idle_in_transaction_session_timeout='30s';
ALTER ROLE pd_core_worker SET statement_timeout='30s';
ALTER ROLE pd_core_worker SET idle_in_transaction_session_timeout='60s';

-- ───────────── Composant IAM : aucun DELETE, aucune lecture des données métier ─────────────
GRANT USAGE ON SCHEMA iam, core, audit TO pd_iam_admin;
GRANT SELECT, INSERT ON iam.users, iam.identities, iam.memberships, iam.access_tokens, iam.invitations TO pd_iam_admin;
GRANT UPDATE(email, given_name, family_name, status, updated_at) ON iam.users TO pd_iam_admin;
GRANT UPDATE(role, status) ON iam.memberships TO pd_iam_admin;
GRANT UPDATE(revoked_at) ON iam.access_tokens TO pd_iam_admin;
GRANT UPDATE(accepted_at, revoked_at) ON iam.invitations TO pd_iam_admin;

GRANT SELECT, INSERT ON core.organizations TO pd_iam_admin;
GRANT UPDATE(name, legal_name, registration_number, country_code, timezone, locale, status, updated_at) ON core.organizations TO pd_iam_admin;
CREATE POLICY iam_admin_provisioning ON core.organizations TO pd_iam_admin USING (true) WITH CHECK (true);
GRANT SELECT ON core.applications TO pd_iam_admin;
GRANT SELECT, INSERT ON core.organization_applications TO pd_iam_admin;
GRANT UPDATE(status, starts_at, ends_at) ON core.organization_applications TO pd_iam_admin;
CREATE POLICY iam_admin_provisioning ON core.organization_applications TO pd_iam_admin USING (true) WITH CHECK (true);

-- Journal d'audit : ajout seul, signé par le compte réel de connexion.
GRANT INSERT ON audit.events TO pd_iam_admin;
CREATE POLICY iam_admin_append ON audit.events FOR INSERT TO pd_iam_admin WITH CHECK (actor_database_role = session_user);

-- Un jeton ne se modifie pas : seule sa révocation, définitive, est possible.
CREATE FUNCTION iam.guard_token_update() RETURNS trigger LANGUAGE plpgsql SET search_path=pg_catalog AS $$
BEGIN
 IF OLD.revoked_at IS NOT NULL OR NEW.revoked_at IS NULL OR (to_jsonb(NEW) - 'revoked_at') <> (to_jsonb(OLD) - 'revoked_at')
 THEN RAISE EXCEPTION 'Jeton : seule la révocation est permise' USING ERRCODE='42501'; END IF;
 RETURN NEW;
END $$;
REVOKE ALL ON FUNCTION iam.guard_token_update() FROM PUBLIC;
CREATE TRIGGER guard_update BEFORE UPDATE ON iam.access_tokens FOR EACH ROW EXECUTE FUNCTION iam.guard_token_update();

-- Une invitation acceptée ou révoquée est close.
CREATE FUNCTION iam.guard_invitation_update() RETURNS trigger LANGUAGE plpgsql SET search_path=pg_catalog AS $$
BEGIN
 IF OLD.accepted_at IS NOT NULL OR OLD.revoked_at IS NOT NULL
 THEN RAISE EXCEPTION 'Invitation close' USING ERRCODE='42501'; END IF;
 RETURN NEW;
END $$;
REVOKE ALL ON FUNCTION iam.guard_invitation_update() FROM PUBLIC;
CREATE TRIGGER guard_update BEFORE UPDATE ON iam.invitations FOR EACH ROW EXECUTE FUNCTION iam.guard_invitation_update();
CREATE INDEX invitations_org ON iam.invitations(organization_id, created_at DESC);

-- ───────────── Workers : files de traitement uniquement ─────────────
GRANT USAGE ON SCHEMA integration, notifications TO pd_core_worker;
GRANT SELECT ON integration.outbox TO pd_core_worker;
GRANT UPDATE(status, attempts, available_at, locked_until, last_error) ON integration.outbox TO pd_core_worker;
CREATE POLICY worker_queue ON integration.outbox TO pd_core_worker USING (true) WITH CHECK (true);
GRANT SELECT, INSERT ON notifications.deliveries TO pd_core_worker;
GRANT UPDATE(status, attempts, next_attempt_at, last_error, delivered_at) ON notifications.deliveries TO pd_core_worker;
CREATE POLICY worker_queue ON notifications.deliveries TO pd_core_worker USING (true) WITH CHECK (true);
GRANT SELECT ON integration.connections TO pd_core_worker;
CREATE POLICY worker_read ON integration.connections FOR SELECT TO pd_core_worker USING (true);
-- Seule une référence de coffre est stockée ; le secret lui-même n'entre jamais en base.
GRANT SELECT, INSERT ON integration.connection_secrets TO pd_core_worker;
GRANT UPDATE(vault_reference) ON integration.connection_secrets TO pd_core_worker;
CREATE POLICY worker_secrets ON integration.connection_secrets TO pd_core_worker USING (true) WITH CHECK (true);
GRANT SELECT, INSERT ON integration.external_references TO pd_core_worker;
CREATE POLICY worker_refs ON integration.external_references TO pd_core_worker USING (true) WITH CHECK (true);

-- ───────────── API métier : fonctions bornées (aucun accès direct aux tables internes) ─────────────
-- Publication transactionnelle d'un événement : le contenu est relu en base, jamais fourni par le client.
CREATE FUNCTION integration.publish_request_created(p_request_id uuid) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE org uuid := iam.current_organization_id(); body jsonb; out_id uuid;
BEGIN
 IF org IS NULL OR NOT iam.permitted('requests.write') THEN RAISE EXCEPTION 'Accès refusé' USING ERRCODE='42501'; END IF;
 SELECT jsonb_build_object('request_id', r.id, 'subject', r.subject, 'source', r.source, 'status', r.status,
   'company_id', r.company_id, 'contact_id', r.contact_id, 'created_at', r.created_at)
   INTO body FROM web.requests r WHERE r.organization_id = org AND r.id = p_request_id;
 IF body IS NULL THEN RAISE EXCEPTION 'Demande introuvable' USING ERRCODE='P0002'; END IF;
 INSERT INTO integration.outbox(organization_id, event_type, payload, idempotency_key)
 VALUES (org, 'web.request.created', body, 'web.request.created:' || p_request_id::text)
 ON CONFLICT (organization_id, idempotency_key) DO NOTHING RETURNING id INTO out_id;
 RETURN out_id;
END $$;
REVOKE ALL ON FUNCTION integration.publish_request_created(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION integration.publish_request_created(uuid) TO pd_core_api;

-- Consentements : journal en ajout seul, écrit par le service de consentement.
CREATE FUNCTION web.record_communication_preference(p_contact_id uuid, p_purpose text, p_channel text, p_allowed boolean, p_source text, p_notice_version text)
RETURNS web.communication_preferences LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE org uuid := iam.current_organization_id(); r web.communication_preferences;
BEGIN
 IF org IS NULL OR NOT iam.permitted('directory.write') THEN RAISE EXCEPTION 'Accès refusé' USING ERRCODE='42501'; END IF;
 IF p_allowed IS NULL OR p_purpose !~ '^[a-z][a-z0-9_.-]{1,63}$' OR length(btrim(p_source)) NOT BETWEEN 1 AND 100
    OR length(p_notice_version) > 50 THEN RAISE EXCEPTION 'Préférence invalide' USING ERRCODE='22023'; END IF;
 INSERT INTO web.communication_preferences AS c (organization_id, contact_id, purpose, channel, allowed, source, notice_version)
 VALUES (org, p_contact_id, p_purpose, p_channel, p_allowed, btrim(p_source), p_notice_version) RETURNING c.* INTO r;
 RETURN r;
END $$;
REVOKE ALL ON FUNCTION web.record_communication_preference(uuid, text, text, boolean, text, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION web.record_communication_preference(uuid, text, text, boolean, text, text) TO pd_core_api;

CREATE FUNCTION web.list_communication_preferences(p_contact_id uuid) RETURNS SETOF web.communication_preferences
LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog AS $$
 SELECT p.* FROM web.communication_preferences p
 WHERE p.organization_id = iam.current_organization_id() AND p.contact_id = p_contact_id AND iam.permitted('directory.read')
 ORDER BY p.recorded_at DESC, p.id LIMIT 500
$$;
REVOKE ALL ON FUNCTION web.list_communication_preferences(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION web.list_communication_preferences(uuid) TO pd_core_api;
CREATE INDEX communication_preferences_contact ON web.communication_preferences(organization_id, contact_id, recorded_at DESC);

-- Idempotence des créations : même clé + même contenu = même réponse, par organisation.
CREATE TABLE core.idempotency_keys (
 organization_id uuid NOT NULL DEFAULT iam.current_organization_id() REFERENCES core.organizations(id),
 key text NOT NULL CHECK(length(key) BETWEEN 8 AND 128), scope text NOT NULL, request_hash text NOT NULL,
 status_code integer NOT NULL, response jsonb NOT NULL, created_at timestamptz NOT NULL DEFAULT now(),
 PRIMARY KEY(organization_id, key)
);
ALTER TABLE core.idempotency_keys ENABLE ROW LEVEL SECURITY;
ALTER TABLE core.idempotency_keys FORCE ROW LEVEL SECURITY;
CREATE POLICY tenant_boundary ON core.idempotency_keys AS RESTRICTIVE TO pd_core_api
 USING (organization_id = (SELECT iam.current_organization_id()))
 WITH CHECK (organization_id = (SELECT iam.current_organization_id()));
CREATE POLICY own_keys ON core.idempotency_keys TO pd_core_api USING (true) WITH CHECK (true);
GRANT SELECT, INSERT ON core.idempotency_keys TO pd_core_api;
