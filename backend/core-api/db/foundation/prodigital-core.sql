-- PRODIGITAL CORE V1 : BASE COMMUNE, installation neuve uniquement.
-- PostgreSQL 15+ ; exécuter comme administrateur avec psql -d prodigital -f prodigital-core.sql
-- Ne pas importer les anciens exports Genesis avec ce fichier. Lire INSTALLATION.md.
-- Aucun mot de passe ni compte humain préconfiguré. Aucun changement de production automatique.
\set ON_ERROR_STOP on
BEGIN;
SET LOCAL lock_timeout = '15s';
SET LOCAL statement_timeout = '180s';
SELECT pg_advisory_xact_lock(hashtextextended('prodigital-core-foundation-v1',0));
DO $$ BEGIN
 IF current_database() <> 'prodigital' THEN RAISE EXCEPTION 'Se connecter à la base prodigital'; END IF;
 IF current_setting('server_version_num')::int < 150000 THEN RAISE EXCEPTION 'PostgreSQL 15 minimum'; END IF;
 IF NOT (SELECT rolsuper FROM pg_roles WHERE rolname=current_user) THEN RAISE EXCEPTION 'Installation réservée à l administrateur PostgreSQL'; END IF;
END $$;
CREATE SCHEMA IF NOT EXISTS core_meta;
REVOKE ALL ON SCHEMA core_meta FROM PUBLIC;
CREATE TABLE IF NOT EXISTS core_meta.migrations(version text PRIMARY KEY, sha256 text NOT NULL, installed_at timestamptz NOT NULL DEFAULT now());
SELECT EXISTS(SELECT FROM core_meta.migrations WHERE version='foundation_v1') AS installed \gset
\if :installed
DO $$ BEGIN IF NOT EXISTS(SELECT FROM core_meta.migrations WHERE version='foundation_v1' AND sha256='b181f4e11f9a1222a3eef9a2a777a2ed7a82a196cd9a8d13e3cff0833885fa3d') THEN RAISE EXCEPTION 'Version déjà installée avec un SQL différent : migration nécessaire'; END IF; END $$;
\echo ProDigital Core V1 deja installe, empreinte verifiee.
\else
-- Refus de mélanger ce modèle avec une base Core/Genesis existante.
DO $$ BEGIN
 IF EXISTS(SELECT FROM pg_namespace WHERE nspname IN ('core','iam','site','catalog','documents','web','integration','audit','notifications','genesis','crm','itsm','platform'))
 THEN RAISE EXCEPTION 'Base déjà structurée : installer sur une base vierge ou préparer une migration des données. Aucune table existante supprimée.'; END IF;
 IF EXISTS(SELECT FROM pg_roles WHERE rolname IN ('pd_core_api','pd_site_api'))
 THEN RAISE EXCEPTION 'Rôles pd_core_api/pd_site_api déjà présents sur ce serveur : contrôler les rôles avant installation.'; END IF;
END $$;
-- Source du socle. Utiliser prodigital-core.sql, généré avec les politiques et les tables site.
CREATE ROLE pd_core_api NOLOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT NOREPLICATION NOBYPASSRLS;
CREATE ROLE pd_site_api NOLOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT NOREPLICATION NOBYPASSRLS;
REVOKE ALL ON DATABASE prodigital FROM PUBLIC;
REVOKE CREATE ON SCHEMA public FROM PUBLIC;
GRANT CONNECT ON DATABASE prodigital TO pd_core_api, pd_site_api;
ALTER ROLE pd_core_api IN DATABASE prodigital SET search_path=pg_catalog;
ALTER ROLE pd_site_api IN DATABASE prodigital SET search_path=pg_catalog;
ALTER ROLE pd_core_api SET statement_timeout='15s';
ALTER ROLE pd_core_api SET idle_in_transaction_session_timeout='30s';
ALTER ROLE pd_site_api SET statement_timeout='15s';

CREATE SCHEMA core;
CREATE SCHEMA iam;
CREATE SCHEMA catalog;
CREATE SCHEMA documents;
CREATE SCHEMA web;
CREATE SCHEMA integration;
CREATE SCHEMA notifications;
CREATE SCHEMA audit;
REVOKE ALL ON SCHEMA core,iam,catalog,documents,web,integration,notifications,audit FROM PUBLIC;
-- Les fonctions créées par cet administrateur ne sont pas publiques par défaut.
ALTER DEFAULT PRIVILEGES IN SCHEMA core_meta,core,iam,catalog,documents,web,integration,notifications,audit REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC;

CREATE TABLE core.organizations (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 slug text NOT NULL UNIQUE CHECK(slug ~ '^[a-z0-9][a-z0-9-]{1,62}$'),
 name text NOT NULL CHECK(length(btrim(name)) BETWEEN 1 AND 200),
 legal_name text, registration_number text, country_code text CHECK(country_code ~ '^[A-Z]{2}$'),
 timezone text NOT NULL DEFAULT 'Europe/Paris', locale text NOT NULL DEFAULT 'fr-FR',
 status text NOT NULL DEFAULT 'active' CHECK(status IN ('active','suspended','archived')),
 created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now()
);
-- Une seule entreprise initiale réelle. Aucun compte humain ou client inventé.
INSERT INTO core.organizations(id,slug,name) VALUES ('00000000-0000-4000-8000-000000000001','prodigital','ProDigital');

-- Référentiel d'identité privé : l'API métier ne peut pas lire ou modifier ces tables.
CREATE TABLE iam.users (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), email text NOT NULL CHECK(length(email) BETWEEN 3 AND 254),
 given_name text NOT NULL, family_name text NOT NULL,
 status text NOT NULL DEFAULT 'active' CHECK(status IN ('active','suspended','archived')),
 created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX users_email_unique ON iam.users(lower(email));
CREATE TABLE iam.identities (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), user_id uuid NOT NULL REFERENCES iam.users(id),
 issuer text NOT NULL, subject text NOT NULL, created_at timestamptz NOT NULL DEFAULT now(),
 UNIQUE(issuer,subject)
);
CREATE TABLE iam.memberships (
 organization_id uuid NOT NULL REFERENCES core.organizations(id), user_id uuid NOT NULL REFERENCES iam.users(id),
 role text NOT NULL CHECK(role IN ('owner','admin','editor','viewer')),
 status text NOT NULL DEFAULT 'active' CHECK(status IN ('active','suspended','revoked')),
 created_at timestamptz NOT NULL DEFAULT now(), PRIMARY KEY(organization_id,user_id)
);
CREATE INDEX memberships_user ON iam.memberships(user_id);
CREATE TYPE iam.permission AS ENUM (
 'directory.read','directory.write','catalog.read','catalog.write','documents.read','documents.write',
 'requests.read','requests.write','integrations.read','integrations.write','audit.read'
);
CREATE TABLE iam.access_tokens (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), organization_id uuid NOT NULL, user_id uuid NOT NULL,
 token_hash bytea NOT NULL UNIQUE CHECK(octet_length(token_hash)=32),
 kind text NOT NULL CHECK(kind IN ('session','api_key')),
 label text NOT NULL DEFAULT '', scopes iam.permission[] NOT NULL CHECK(cardinality(scopes)>0),
 created_at timestamptz NOT NULL DEFAULT now(), expires_at timestamptz NOT NULL,
 revoked_at timestamptz, CHECK(expires_at>created_at),
 FOREIGN KEY(organization_id,user_id) REFERENCES iam.memberships(organization_id,user_id)
);
CREATE INDEX tokens_member ON iam.access_tokens(organization_id,user_id);
CREATE TABLE iam.invitations (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), organization_id uuid NOT NULL REFERENCES core.organizations(id),
 email text NOT NULL, role text NOT NULL CHECK(role IN ('admin','editor','viewer')),
 token_hash bytea NOT NULL UNIQUE CHECK(octet_length(token_hash)=32),
 expires_at timestamptz NOT NULL, accepted_at timestamptz, revoked_at timestamptz,
 created_at timestamptz NOT NULL DEFAULT now(), CHECK(expires_at>created_at)
);
CREATE TABLE iam.service_bindings (
 database_role name PRIMARY KEY, organization_id uuid NOT NULL REFERENCES core.organizations(id),
 active boolean NOT NULL DEFAULT true
);
INSERT INTO iam.service_bindings VALUES ('pd_site_api','00000000-0000-4000-8000-000000000001',true);

-- Le jeton est aléatoire, jamais un simple identifiant utilisateur/entreprise.
-- Le backend authentifie d'abord l'utilisateur ; seule l'administration de confiance
-- crée les tokens. Aucun droit de création de session n'est accordé à pd_core_api.
CREATE FUNCTION iam.context() RETURNS TABLE(user_id uuid,organization_id uuid,member_role text,scopes iam.permission[])
LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog AS $$
 SELECT t.user_id,t.organization_id,m.role,t.scopes
 FROM iam.access_tokens t JOIN iam.memberships m USING(organization_id,user_id)
 JOIN iam.users u ON u.id=t.user_id JOIN core.organizations o ON o.id=t.organization_id
 WHERE length(current_setting('app.access_token',true)) BETWEEN 32 AND 512
 AND t.token_hash=sha256(convert_to(current_setting('app.access_token',true),'UTF8'))
 AND t.revoked_at IS NULL AND t.expires_at>statement_timestamp()
 AND m.status='active' AND u.status='active' AND o.status='active'
$$;
CREATE FUNCTION iam.current_organization_id() RETURNS uuid LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog AS $$ SELECT organization_id FROM iam.context() $$;
CREATE FUNCTION iam.current_user_id() RETURNS uuid LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog AS $$ SELECT user_id FROM iam.context() $$;
CREATE FUNCTION iam.permitted(requested iam.permission) RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog AS $$
 SELECT COALESCE((SELECT requested=ANY(scopes) AND (requested::text NOT LIKE '%.write' OR member_role IN ('owner','admin','editor')) FROM iam.context()),false)
$$;
CREATE FUNCTION iam.site_organization_id() RETURNS uuid LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog AS $$
 SELECT b.organization_id FROM iam.service_bindings b JOIN core.organizations o ON o.id=b.organization_id
 WHERE b.database_role=session_user AND b.active AND o.status='active'
$$;
-- session_user ne peut pas être falsifié par un simple SET ROLE applicatif.
GRANT USAGE ON SCHEMA iam TO pd_core_api,pd_site_api;
GRANT EXECUTE ON FUNCTION iam.current_organization_id(),iam.current_user_id(),iam.permitted(iam.permission) TO pd_core_api;
GRANT EXECUTE ON FUNCTION iam.site_organization_id() TO pd_site_api;

CREATE FUNCTION core_meta.touch_row() RETURNS trigger LANGUAGE plpgsql SET search_path=pg_catalog AS $$
BEGIN
 IF NEW.id IS DISTINCT FROM OLD.id OR NEW.organization_id IS DISTINCT FROM OLD.organization_id OR NEW.created_at IS DISTINCT FROM OLD.created_at
 THEN RAISE EXCEPTION 'Identité et organisation non modifiables' USING ERRCODE='42501'; END IF;
 NEW.updated_at=clock_timestamp(); RETURN NEW;
END $$;

-- Une entreprise cliente dans le carnet d'adresses n'est pas automatiquement un tenant.
CREATE TABLE core.companies (
 organization_id uuid NOT NULL DEFAULT iam.current_organization_id() REFERENCES core.organizations(id),
 id uuid NOT NULL DEFAULT gen_random_uuid(), name text NOT NULL CHECK(length(btrim(name)) BETWEEN 1 AND 200),
 kind text NOT NULL DEFAULT 'prospect' CHECK(kind IN ('prospect','customer','supplier','partner','other')),
 legal_name text, registration_number text, email text, phone text, website text,
 archived_at timestamptz, created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(),
 PRIMARY KEY(organization_id,id)
);
CREATE TABLE core.contacts (
 organization_id uuid NOT NULL DEFAULT iam.current_organization_id() REFERENCES core.organizations(id),
 id uuid NOT NULL DEFAULT gen_random_uuid(), given_name text NOT NULL, family_name text NOT NULL,
 email text, phone text, job_title text, archived_at timestamptz,
 created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(), PRIMARY KEY(organization_id,id)
);
CREATE INDEX contacts_email ON core.contacts(organization_id,lower(email));
CREATE TABLE core.company_contacts (
 organization_id uuid NOT NULL DEFAULT iam.current_organization_id() REFERENCES core.organizations(id),
 id uuid NOT NULL DEFAULT gen_random_uuid(), company_id uuid NOT NULL, contact_id uuid NOT NULL, relationship text,
 created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(), PRIMARY KEY(organization_id,id),
 UNIQUE(organization_id,company_id,contact_id),
 FOREIGN KEY(organization_id,company_id) REFERENCES core.companies(organization_id,id),
 FOREIGN KEY(organization_id,contact_id) REFERENCES core.contacts(organization_id,id)
);
CREATE TABLE core.addresses (
 organization_id uuid NOT NULL DEFAULT iam.current_organization_id() REFERENCES core.organizations(id),
 id uuid NOT NULL DEFAULT gen_random_uuid(), company_id uuid, contact_id uuid,
 label text NOT NULL DEFAULT 'main', line1 text NOT NULL, line2 text, postal_code text, city text NOT NULL,
 country_code text NOT NULL CHECK(country_code ~ '^[A-Z]{2}$'),
 created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(), PRIMARY KEY(organization_id,id),
 CHECK(num_nonnulls(company_id,contact_id)=1),
 FOREIGN KEY(organization_id,company_id) REFERENCES core.companies(organization_id,id),
 FOREIGN KEY(organization_id,contact_id) REFERENCES core.contacts(organization_id,id)
);
CREATE TABLE core.teams (
 organization_id uuid NOT NULL DEFAULT iam.current_organization_id() REFERENCES core.organizations(id),
 id uuid NOT NULL DEFAULT gen_random_uuid(), name text NOT NULL, archived_at timestamptz,
 created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(),
 PRIMARY KEY(organization_id,id), UNIQUE(organization_id,name)
);
CREATE TABLE core.team_members (
 organization_id uuid NOT NULL DEFAULT iam.current_organization_id() REFERENCES core.organizations(id),
 id uuid NOT NULL DEFAULT gen_random_uuid(), team_id uuid NOT NULL, user_id uuid NOT NULL,
 created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(), PRIMARY KEY(organization_id,id),
 UNIQUE(organization_id,team_id,user_id),
 FOREIGN KEY(organization_id,team_id) REFERENCES core.teams(organization_id,id),
 FOREIGN KEY(organization_id,user_id) REFERENCES iam.memberships(organization_id,user_id)
);
CREATE TABLE core.applications (
 code text PRIMARY KEY, name text NOT NULL, active boolean NOT NULL DEFAULT true
);
INSERT INTO core.applications VALUES ('site','Site ProDigital',true),('crm','CRM',false),('itsm','ITSM',false),('formations','Formations',false);
CREATE TABLE core.application_plans (
 application_code text NOT NULL REFERENCES core.applications(code), code text NOT NULL,
 name text NOT NULL, limits jsonb NOT NULL DEFAULT '{}' CHECK(jsonb_typeof(limits)='object'),
 published boolean NOT NULL DEFAULT false, PRIMARY KEY(application_code,code)
);
CREATE TABLE core.subscriptions (
 organization_id uuid NOT NULL REFERENCES core.organizations(id), id uuid NOT NULL DEFAULT gen_random_uuid(),
 application_code text NOT NULL, plan_code text NOT NULL,
 status text NOT NULL DEFAULT 'pending' CHECK(status IN ('pending','trialing','active','past_due','suspended','cancelled','ended')),
 starts_at timestamptz NOT NULL, ends_at timestamptz, external_reference text,
 created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(),
 PRIMARY KEY(organization_id,id), CHECK(ends_at IS NULL OR ends_at>starts_at),
 FOREIGN KEY(application_code,plan_code) REFERENCES core.application_plans(application_code,code)
);
CREATE UNIQUE INDEX subscription_current ON core.subscriptions(organization_id,application_code)
 WHERE status IN ('pending','trialing','active','past_due','suspended');
CREATE TABLE core.organization_applications (
 organization_id uuid NOT NULL REFERENCES core.organizations(id), application_code text NOT NULL REFERENCES core.applications(code),
 status text NOT NULL DEFAULT 'disabled' CHECK(status IN ('enabled','disabled','suspended')),
 starts_at timestamptz, ends_at timestamptz, CHECK(ends_at IS NULL OR starts_at IS NULL OR ends_at>starts_at),
 PRIMARY KEY(organization_id,application_code)
);
INSERT INTO core.organization_applications VALUES ('00000000-0000-4000-8000-000000000001','site','enabled',now(),NULL);

CREATE TABLE catalog.offerings (
 organization_id uuid NOT NULL DEFAULT iam.current_organization_id() REFERENCES core.organizations(id),
 id uuid NOT NULL DEFAULT gen_random_uuid(), slug text NOT NULL, name text NOT NULL,
 kind text NOT NULL CHECK(kind IN ('service','course','software')), description text NOT NULL DEFAULT '',
 status text NOT NULL DEFAULT 'draft' CHECK(status IN ('draft','published','archived')),
 created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(),
 PRIMARY KEY(organization_id,id), UNIQUE(organization_id,slug)
);
CREATE TABLE catalog.courses (
 organization_id uuid NOT NULL DEFAULT iam.current_organization_id() REFERENCES core.organizations(id),
 id uuid NOT NULL DEFAULT gen_random_uuid(), offering_id uuid NOT NULL, objectives text, prerequisites text,
 level text, duration_minutes integer CHECK(duration_minutes>0),
 created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(), PRIMARY KEY(organization_id,id),
 UNIQUE(organization_id,offering_id), FOREIGN KEY(organization_id,offering_id) REFERENCES catalog.offerings(organization_id,id)
);
CREATE TABLE catalog.course_modules (
 organization_id uuid NOT NULL DEFAULT iam.current_organization_id() REFERENCES core.organizations(id),
 id uuid NOT NULL DEFAULT gen_random_uuid(), course_id uuid NOT NULL, position integer NOT NULL CHECK(position>0),
 title text NOT NULL, content text NOT NULL DEFAULT '',
 created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(), PRIMARY KEY(organization_id,id),
 UNIQUE(organization_id,course_id,position), FOREIGN KEY(organization_id,course_id) REFERENCES catalog.courses(organization_id,id)
);

CREATE TABLE documents.files (
 organization_id uuid NOT NULL DEFAULT iam.current_organization_id() REFERENCES core.organizations(id),
 id uuid NOT NULL DEFAULT gen_random_uuid(), name text NOT NULL, media_type text NOT NULL,
 storage_key text NOT NULL, size_bytes bigint NOT NULL CHECK(size_bytes>=0), sha256 text CHECK(sha256 ~ '^[a-f0-9]{64}$'),
 archived_at timestamptz, created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(),
 PRIMARY KEY(organization_id,id), UNIQUE(organization_id,storage_key),
 CHECK(storage_key LIKE organization_id::text || '/%')
);
COMMENT ON COLUMN documents.files.storage_key IS 'Clé privée préfixée par organisation ; l API vérifie les droits avant toute URL signée. Aucun bucket public.';
CREATE TABLE documents.attachments (
 organization_id uuid NOT NULL DEFAULT iam.current_organization_id() REFERENCES core.organizations(id),
 id uuid NOT NULL DEFAULT gen_random_uuid(), file_id uuid NOT NULL, company_id uuid, contact_id uuid,
 created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(), PRIMARY KEY(organization_id,id),
 CHECK(num_nonnulls(company_id,contact_id)=1),
 FOREIGN KEY(organization_id,file_id) REFERENCES documents.files(organization_id,id),
 FOREIGN KEY(organization_id,company_id) REFERENCES core.companies(organization_id,id),
 FOREIGN KEY(organization_id,contact_id) REFERENCES core.contacts(organization_id,id)
);
CREATE TABLE web.requests (
 organization_id uuid NOT NULL DEFAULT iam.current_organization_id() REFERENCES core.organizations(id),
 id uuid NOT NULL DEFAULT gen_random_uuid(), company_id uuid, contact_id uuid,
 subject text NOT NULL, message text NOT NULL, source text NOT NULL DEFAULT 'api',
 status text NOT NULL DEFAULT 'new' CHECK(status IN ('new','in_progress','closed','spam')),
 details jsonb NOT NULL DEFAULT '{}' CHECK(jsonb_typeof(details)='object'),
 created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(), PRIMARY KEY(organization_id,id),
 FOREIGN KEY(organization_id,company_id) REFERENCES core.companies(organization_id,id),
 FOREIGN KEY(organization_id,contact_id) REFERENCES core.contacts(organization_id,id)
);
CREATE TABLE web.request_notes (
 organization_id uuid NOT NULL DEFAULT iam.current_organization_id() REFERENCES core.organizations(id),
 id uuid NOT NULL DEFAULT gen_random_uuid(), request_id uuid NOT NULL, body text NOT NULL,
 created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(), PRIMARY KEY(organization_id,id),
 FOREIGN KEY(organization_id,request_id) REFERENCES web.requests(organization_id,id)
);
CREATE TABLE web.communication_preferences (
 organization_id uuid NOT NULL REFERENCES core.organizations(id), id uuid NOT NULL DEFAULT gen_random_uuid(),
 contact_id uuid NOT NULL, purpose text NOT NULL, channel text NOT NULL CHECK(channel IN ('email','sms','phone')),
 allowed boolean NOT NULL, recorded_at timestamptz NOT NULL DEFAULT now(), source text NOT NULL, notice_version text,
 PRIMARY KEY(organization_id,id), FOREIGN KEY(organization_id,contact_id) REFERENCES core.contacts(organization_id,id)
);
-- Préférences : écriture réservée au backend de consentement, pas au CRUD métier.

CREATE TABLE integration.connections (
 organization_id uuid NOT NULL DEFAULT iam.current_organization_id() REFERENCES core.organizations(id),
 id uuid NOT NULL DEFAULT gen_random_uuid(), provider text NOT NULL, name text NOT NULL,
 status text NOT NULL DEFAULT 'disabled' CHECK(status IN ('disabled','enabled','error')),
 created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(), PRIMARY KEY(organization_id,id)
);
CREATE TABLE integration.connection_secrets (
 organization_id uuid NOT NULL, connection_id uuid NOT NULL, vault_reference text NOT NULL,
 PRIMARY KEY(organization_id,connection_id), FOREIGN KEY(organization_id,connection_id) REFERENCES integration.connections(organization_id,id)
);
CREATE TABLE integration.external_references (
 organization_id uuid NOT NULL, id uuid NOT NULL DEFAULT gen_random_uuid(), connection_id uuid NOT NULL,
 entity_type text NOT NULL, local_id uuid NOT NULL, external_id text NOT NULL,
 PRIMARY KEY(organization_id,id), UNIQUE(organization_id,connection_id,entity_type,external_id),
 FOREIGN KEY(organization_id,connection_id) REFERENCES integration.connections(organization_id,id)
);
CREATE TABLE integration.outbox (
 organization_id uuid NOT NULL REFERENCES core.organizations(id), id uuid NOT NULL DEFAULT gen_random_uuid(),
 event_type text NOT NULL, payload jsonb NOT NULL CHECK(jsonb_typeof(payload)='object'), idempotency_key text NOT NULL,
 status text NOT NULL DEFAULT 'pending' CHECK(status IN ('pending','running','succeeded','failed')),
 attempts integer NOT NULL DEFAULT 0 CHECK(attempts>=0), available_at timestamptz NOT NULL DEFAULT now(),
 locked_until timestamptz, last_error text, created_at timestamptz NOT NULL DEFAULT now(),
 PRIMARY KEY(organization_id,id), UNIQUE(organization_id,idempotency_key)
);
CREATE INDEX outbox_pending ON integration.outbox(available_at) WHERE status IN ('pending','running');
CREATE TABLE notifications.deliveries (
 organization_id uuid NOT NULL REFERENCES core.organizations(id), id uuid NOT NULL DEFAULT gen_random_uuid(),
 channel text NOT NULL CHECK(channel IN ('email','sms','in_app')), recipient text NOT NULL,
 template text NOT NULL, payload jsonb NOT NULL DEFAULT '{}' CHECK(jsonb_typeof(payload)='object'),
 status text NOT NULL DEFAULT 'pending' CHECK(status IN ('pending','running','succeeded','failed')),
 attempts integer NOT NULL DEFAULT 0 CHECK(attempts>=0), next_attempt_at timestamptz NOT NULL DEFAULT now(),
 last_error text, delivered_at timestamptz, created_at timestamptz NOT NULL DEFAULT now(), PRIMARY KEY(organization_id,id)
);
CREATE TABLE audit.events (
 organization_id uuid NOT NULL REFERENCES core.organizations(id), id uuid NOT NULL DEFAULT gen_random_uuid(),
 actor_user_id uuid, actor_database_role name NOT NULL, action text NOT NULL,
 entity_type text NOT NULL, entity_id uuid, occurred_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 PRIMARY KEY(organization_id,id)
);
CREATE INDEX audit_timeline ON audit.events(organization_id,occurred_at DESC);
CREATE FUNCTION audit.record_change() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE r record;
BEGIN
 IF TG_OP='DELETE' THEN r=OLD; ELSE r=NEW; END IF;
 INSERT INTO audit.events(organization_id,actor_user_id,actor_database_role,action,entity_type,entity_id)
 VALUES(r.organization_id,iam.current_user_id(),session_user,TG_OP,TG_TABLE_SCHEMA||'.'||TG_TABLE_NAME,r.id);
 RETURN NULL;
END $$;

GRANT USAGE ON SCHEMA core,catalog,documents,web,integration,audit TO pd_core_api;

ALTER TABLE core.companies ENABLE ROW LEVEL SECURITY;
ALTER TABLE core.companies FORCE ROW LEVEL SECURITY;
CREATE INDEX ON core.companies(organization_id);
CREATE POLICY tenant_boundary ON core.companies AS RESTRICTIVE TO pd_core_api
 USING (organization_id = (SELECT iam.current_organization_id()))
 WITH CHECK (organization_id = (SELECT iam.current_organization_id()));
CREATE POLICY scoped_read ON core.companies FOR SELECT TO pd_core_api USING ((SELECT iam.permitted('directory.read')));
CREATE POLICY scoped_insert ON core.companies FOR INSERT TO pd_core_api WITH CHECK ((SELECT iam.permitted('directory.write')));
CREATE POLICY scoped_update ON core.companies FOR UPDATE TO pd_core_api
 USING ((SELECT iam.permitted('directory.write'))) WITH CHECK ((SELECT iam.permitted('directory.write')));
-- Pas de DELETE/TRUNCATE accordé : archivage par les champs métier.
GRANT SELECT, INSERT, UPDATE ON core.companies TO pd_core_api;
CREATE TRIGGER preserve_identity BEFORE UPDATE ON core.companies FOR EACH ROW EXECUTE FUNCTION core_meta.touch_row();
CREATE TRIGGER audit_change AFTER INSERT OR UPDATE OR DELETE ON core.companies FOR EACH ROW EXECUTE FUNCTION audit.record_change();


ALTER TABLE core.contacts ENABLE ROW LEVEL SECURITY;
ALTER TABLE core.contacts FORCE ROW LEVEL SECURITY;
CREATE INDEX ON core.contacts(organization_id);
CREATE POLICY tenant_boundary ON core.contacts AS RESTRICTIVE TO pd_core_api
 USING (organization_id = (SELECT iam.current_organization_id()))
 WITH CHECK (organization_id = (SELECT iam.current_organization_id()));
CREATE POLICY scoped_read ON core.contacts FOR SELECT TO pd_core_api USING ((SELECT iam.permitted('directory.read')));
CREATE POLICY scoped_insert ON core.contacts FOR INSERT TO pd_core_api WITH CHECK ((SELECT iam.permitted('directory.write')));
CREATE POLICY scoped_update ON core.contacts FOR UPDATE TO pd_core_api
 USING ((SELECT iam.permitted('directory.write'))) WITH CHECK ((SELECT iam.permitted('directory.write')));
-- Pas de DELETE/TRUNCATE accordé : archivage par les champs métier.
GRANT SELECT, INSERT, UPDATE ON core.contacts TO pd_core_api;
CREATE TRIGGER preserve_identity BEFORE UPDATE ON core.contacts FOR EACH ROW EXECUTE FUNCTION core_meta.touch_row();
CREATE TRIGGER audit_change AFTER INSERT OR UPDATE OR DELETE ON core.contacts FOR EACH ROW EXECUTE FUNCTION audit.record_change();


ALTER TABLE core.company_contacts ENABLE ROW LEVEL SECURITY;
ALTER TABLE core.company_contacts FORCE ROW LEVEL SECURITY;
CREATE INDEX ON core.company_contacts(organization_id);
CREATE POLICY tenant_boundary ON core.company_contacts AS RESTRICTIVE TO pd_core_api
 USING (organization_id = (SELECT iam.current_organization_id()))
 WITH CHECK (organization_id = (SELECT iam.current_organization_id()));
CREATE POLICY scoped_read ON core.company_contacts FOR SELECT TO pd_core_api USING ((SELECT iam.permitted('directory.read')));
CREATE POLICY scoped_insert ON core.company_contacts FOR INSERT TO pd_core_api WITH CHECK ((SELECT iam.permitted('directory.write')));
CREATE POLICY scoped_update ON core.company_contacts FOR UPDATE TO pd_core_api
 USING ((SELECT iam.permitted('directory.write'))) WITH CHECK ((SELECT iam.permitted('directory.write')));
-- Pas de DELETE/TRUNCATE accordé : archivage par les champs métier.
GRANT SELECT, INSERT, UPDATE ON core.company_contacts TO pd_core_api;
CREATE TRIGGER preserve_identity BEFORE UPDATE ON core.company_contacts FOR EACH ROW EXECUTE FUNCTION core_meta.touch_row();
CREATE TRIGGER audit_change AFTER INSERT OR UPDATE OR DELETE ON core.company_contacts FOR EACH ROW EXECUTE FUNCTION audit.record_change();


ALTER TABLE core.addresses ENABLE ROW LEVEL SECURITY;
ALTER TABLE core.addresses FORCE ROW LEVEL SECURITY;
CREATE INDEX ON core.addresses(organization_id);
CREATE POLICY tenant_boundary ON core.addresses AS RESTRICTIVE TO pd_core_api
 USING (organization_id = (SELECT iam.current_organization_id()))
 WITH CHECK (organization_id = (SELECT iam.current_organization_id()));
CREATE POLICY scoped_read ON core.addresses FOR SELECT TO pd_core_api USING ((SELECT iam.permitted('directory.read')));
CREATE POLICY scoped_insert ON core.addresses FOR INSERT TO pd_core_api WITH CHECK ((SELECT iam.permitted('directory.write')));
CREATE POLICY scoped_update ON core.addresses FOR UPDATE TO pd_core_api
 USING ((SELECT iam.permitted('directory.write'))) WITH CHECK ((SELECT iam.permitted('directory.write')));
-- Pas de DELETE/TRUNCATE accordé : archivage par les champs métier.
GRANT SELECT, INSERT, UPDATE ON core.addresses TO pd_core_api;
CREATE TRIGGER preserve_identity BEFORE UPDATE ON core.addresses FOR EACH ROW EXECUTE FUNCTION core_meta.touch_row();
CREATE TRIGGER audit_change AFTER INSERT OR UPDATE OR DELETE ON core.addresses FOR EACH ROW EXECUTE FUNCTION audit.record_change();


ALTER TABLE core.teams ENABLE ROW LEVEL SECURITY;
ALTER TABLE core.teams FORCE ROW LEVEL SECURITY;
CREATE INDEX ON core.teams(organization_id);
CREATE POLICY tenant_boundary ON core.teams AS RESTRICTIVE TO pd_core_api
 USING (organization_id = (SELECT iam.current_organization_id()))
 WITH CHECK (organization_id = (SELECT iam.current_organization_id()));
CREATE POLICY scoped_read ON core.teams FOR SELECT TO pd_core_api USING ((SELECT iam.permitted('directory.read')));
CREATE POLICY scoped_insert ON core.teams FOR INSERT TO pd_core_api WITH CHECK ((SELECT iam.permitted('directory.write')));
CREATE POLICY scoped_update ON core.teams FOR UPDATE TO pd_core_api
 USING ((SELECT iam.permitted('directory.write'))) WITH CHECK ((SELECT iam.permitted('directory.write')));
-- Pas de DELETE/TRUNCATE accordé : archivage par les champs métier.
GRANT SELECT, INSERT, UPDATE ON core.teams TO pd_core_api;
CREATE TRIGGER preserve_identity BEFORE UPDATE ON core.teams FOR EACH ROW EXECUTE FUNCTION core_meta.touch_row();
CREATE TRIGGER audit_change AFTER INSERT OR UPDATE OR DELETE ON core.teams FOR EACH ROW EXECUTE FUNCTION audit.record_change();


ALTER TABLE core.team_members ENABLE ROW LEVEL SECURITY;
ALTER TABLE core.team_members FORCE ROW LEVEL SECURITY;
CREATE INDEX ON core.team_members(organization_id);
CREATE POLICY tenant_boundary ON core.team_members AS RESTRICTIVE TO pd_core_api
 USING (organization_id = (SELECT iam.current_organization_id()))
 WITH CHECK (organization_id = (SELECT iam.current_organization_id()));
CREATE POLICY scoped_read ON core.team_members FOR SELECT TO pd_core_api USING ((SELECT iam.permitted('directory.read')));
CREATE POLICY scoped_insert ON core.team_members FOR INSERT TO pd_core_api WITH CHECK ((SELECT iam.permitted('directory.write')));
CREATE POLICY scoped_update ON core.team_members FOR UPDATE TO pd_core_api
 USING ((SELECT iam.permitted('directory.write'))) WITH CHECK ((SELECT iam.permitted('directory.write')));
-- Pas de DELETE/TRUNCATE accordé : archivage par les champs métier.
GRANT SELECT, INSERT, UPDATE ON core.team_members TO pd_core_api;
CREATE TRIGGER preserve_identity BEFORE UPDATE ON core.team_members FOR EACH ROW EXECUTE FUNCTION core_meta.touch_row();
CREATE TRIGGER audit_change AFTER INSERT OR UPDATE OR DELETE ON core.team_members FOR EACH ROW EXECUTE FUNCTION audit.record_change();


ALTER TABLE catalog.offerings ENABLE ROW LEVEL SECURITY;
ALTER TABLE catalog.offerings FORCE ROW LEVEL SECURITY;
CREATE INDEX ON catalog.offerings(organization_id);
CREATE POLICY tenant_boundary ON catalog.offerings AS RESTRICTIVE TO pd_core_api
 USING (organization_id = (SELECT iam.current_organization_id()))
 WITH CHECK (organization_id = (SELECT iam.current_organization_id()));
CREATE POLICY scoped_read ON catalog.offerings FOR SELECT TO pd_core_api USING ((SELECT iam.permitted('catalog.read')));
CREATE POLICY scoped_insert ON catalog.offerings FOR INSERT TO pd_core_api WITH CHECK ((SELECT iam.permitted('catalog.write')));
CREATE POLICY scoped_update ON catalog.offerings FOR UPDATE TO pd_core_api
 USING ((SELECT iam.permitted('catalog.write'))) WITH CHECK ((SELECT iam.permitted('catalog.write')));
-- Pas de DELETE/TRUNCATE accordé : archivage par les champs métier.
GRANT SELECT, INSERT, UPDATE ON catalog.offerings TO pd_core_api;
CREATE TRIGGER preserve_identity BEFORE UPDATE ON catalog.offerings FOR EACH ROW EXECUTE FUNCTION core_meta.touch_row();
CREATE TRIGGER audit_change AFTER INSERT OR UPDATE OR DELETE ON catalog.offerings FOR EACH ROW EXECUTE FUNCTION audit.record_change();


ALTER TABLE catalog.courses ENABLE ROW LEVEL SECURITY;
ALTER TABLE catalog.courses FORCE ROW LEVEL SECURITY;
CREATE INDEX ON catalog.courses(organization_id);
CREATE POLICY tenant_boundary ON catalog.courses AS RESTRICTIVE TO pd_core_api
 USING (organization_id = (SELECT iam.current_organization_id()))
 WITH CHECK (organization_id = (SELECT iam.current_organization_id()));
CREATE POLICY scoped_read ON catalog.courses FOR SELECT TO pd_core_api USING ((SELECT iam.permitted('catalog.read')));
CREATE POLICY scoped_insert ON catalog.courses FOR INSERT TO pd_core_api WITH CHECK ((SELECT iam.permitted('catalog.write')));
CREATE POLICY scoped_update ON catalog.courses FOR UPDATE TO pd_core_api
 USING ((SELECT iam.permitted('catalog.write'))) WITH CHECK ((SELECT iam.permitted('catalog.write')));
-- Pas de DELETE/TRUNCATE accordé : archivage par les champs métier.
GRANT SELECT, INSERT, UPDATE ON catalog.courses TO pd_core_api;
CREATE TRIGGER preserve_identity BEFORE UPDATE ON catalog.courses FOR EACH ROW EXECUTE FUNCTION core_meta.touch_row();
CREATE TRIGGER audit_change AFTER INSERT OR UPDATE OR DELETE ON catalog.courses FOR EACH ROW EXECUTE FUNCTION audit.record_change();


ALTER TABLE catalog.course_modules ENABLE ROW LEVEL SECURITY;
ALTER TABLE catalog.course_modules FORCE ROW LEVEL SECURITY;
CREATE INDEX ON catalog.course_modules(organization_id);
CREATE POLICY tenant_boundary ON catalog.course_modules AS RESTRICTIVE TO pd_core_api
 USING (organization_id = (SELECT iam.current_organization_id()))
 WITH CHECK (organization_id = (SELECT iam.current_organization_id()));
CREATE POLICY scoped_read ON catalog.course_modules FOR SELECT TO pd_core_api USING ((SELECT iam.permitted('catalog.read')));
CREATE POLICY scoped_insert ON catalog.course_modules FOR INSERT TO pd_core_api WITH CHECK ((SELECT iam.permitted('catalog.write')));
CREATE POLICY scoped_update ON catalog.course_modules FOR UPDATE TO pd_core_api
 USING ((SELECT iam.permitted('catalog.write'))) WITH CHECK ((SELECT iam.permitted('catalog.write')));
-- Pas de DELETE/TRUNCATE accordé : archivage par les champs métier.
GRANT SELECT, INSERT, UPDATE ON catalog.course_modules TO pd_core_api;
CREATE TRIGGER preserve_identity BEFORE UPDATE ON catalog.course_modules FOR EACH ROW EXECUTE FUNCTION core_meta.touch_row();
CREATE TRIGGER audit_change AFTER INSERT OR UPDATE OR DELETE ON catalog.course_modules FOR EACH ROW EXECUTE FUNCTION audit.record_change();


ALTER TABLE documents.files ENABLE ROW LEVEL SECURITY;
ALTER TABLE documents.files FORCE ROW LEVEL SECURITY;
CREATE INDEX ON documents.files(organization_id);
CREATE POLICY tenant_boundary ON documents.files AS RESTRICTIVE TO pd_core_api
 USING (organization_id = (SELECT iam.current_organization_id()))
 WITH CHECK (organization_id = (SELECT iam.current_organization_id()));
CREATE POLICY scoped_read ON documents.files FOR SELECT TO pd_core_api USING ((SELECT iam.permitted('documents.read')));
CREATE POLICY scoped_insert ON documents.files FOR INSERT TO pd_core_api WITH CHECK ((SELECT iam.permitted('documents.write')));
CREATE POLICY scoped_update ON documents.files FOR UPDATE TO pd_core_api
 USING ((SELECT iam.permitted('documents.write'))) WITH CHECK ((SELECT iam.permitted('documents.write')));
-- Pas de DELETE/TRUNCATE accordé : archivage par les champs métier.
GRANT SELECT, INSERT, UPDATE ON documents.files TO pd_core_api;
CREATE TRIGGER preserve_identity BEFORE UPDATE ON documents.files FOR EACH ROW EXECUTE FUNCTION core_meta.touch_row();
CREATE TRIGGER audit_change AFTER INSERT OR UPDATE OR DELETE ON documents.files FOR EACH ROW EXECUTE FUNCTION audit.record_change();


ALTER TABLE documents.attachments ENABLE ROW LEVEL SECURITY;
ALTER TABLE documents.attachments FORCE ROW LEVEL SECURITY;
CREATE INDEX ON documents.attachments(organization_id);
CREATE POLICY tenant_boundary ON documents.attachments AS RESTRICTIVE TO pd_core_api
 USING (organization_id = (SELECT iam.current_organization_id()))
 WITH CHECK (organization_id = (SELECT iam.current_organization_id()));
CREATE POLICY scoped_read ON documents.attachments FOR SELECT TO pd_core_api USING ((SELECT iam.permitted('documents.read')));
CREATE POLICY scoped_insert ON documents.attachments FOR INSERT TO pd_core_api WITH CHECK ((SELECT iam.permitted('documents.write')));
CREATE POLICY scoped_update ON documents.attachments FOR UPDATE TO pd_core_api
 USING ((SELECT iam.permitted('documents.write'))) WITH CHECK ((SELECT iam.permitted('documents.write')));
-- Pas de DELETE/TRUNCATE accordé : archivage par les champs métier.
GRANT SELECT, INSERT, UPDATE ON documents.attachments TO pd_core_api;
CREATE TRIGGER preserve_identity BEFORE UPDATE ON documents.attachments FOR EACH ROW EXECUTE FUNCTION core_meta.touch_row();
CREATE TRIGGER audit_change AFTER INSERT OR UPDATE OR DELETE ON documents.attachments FOR EACH ROW EXECUTE FUNCTION audit.record_change();


ALTER TABLE web.requests ENABLE ROW LEVEL SECURITY;
ALTER TABLE web.requests FORCE ROW LEVEL SECURITY;
CREATE INDEX ON web.requests(organization_id);
CREATE POLICY tenant_boundary ON web.requests AS RESTRICTIVE TO pd_core_api
 USING (organization_id = (SELECT iam.current_organization_id()))
 WITH CHECK (organization_id = (SELECT iam.current_organization_id()));
CREATE POLICY scoped_read ON web.requests FOR SELECT TO pd_core_api USING ((SELECT iam.permitted('requests.read')));
CREATE POLICY scoped_insert ON web.requests FOR INSERT TO pd_core_api WITH CHECK ((SELECT iam.permitted('requests.write')));
CREATE POLICY scoped_update ON web.requests FOR UPDATE TO pd_core_api
 USING ((SELECT iam.permitted('requests.write'))) WITH CHECK ((SELECT iam.permitted('requests.write')));
-- Pas de DELETE/TRUNCATE accordé : archivage par les champs métier.
GRANT SELECT, INSERT, UPDATE ON web.requests TO pd_core_api;
CREATE TRIGGER preserve_identity BEFORE UPDATE ON web.requests FOR EACH ROW EXECUTE FUNCTION core_meta.touch_row();
CREATE TRIGGER audit_change AFTER INSERT OR UPDATE OR DELETE ON web.requests FOR EACH ROW EXECUTE FUNCTION audit.record_change();


ALTER TABLE web.request_notes ENABLE ROW LEVEL SECURITY;
ALTER TABLE web.request_notes FORCE ROW LEVEL SECURITY;
CREATE INDEX ON web.request_notes(organization_id);
CREATE POLICY tenant_boundary ON web.request_notes AS RESTRICTIVE TO pd_core_api
 USING (organization_id = (SELECT iam.current_organization_id()))
 WITH CHECK (organization_id = (SELECT iam.current_organization_id()));
CREATE POLICY scoped_read ON web.request_notes FOR SELECT TO pd_core_api USING ((SELECT iam.permitted('requests.read')));
CREATE POLICY scoped_insert ON web.request_notes FOR INSERT TO pd_core_api WITH CHECK ((SELECT iam.permitted('requests.write')));
CREATE POLICY scoped_update ON web.request_notes FOR UPDATE TO pd_core_api
 USING ((SELECT iam.permitted('requests.write'))) WITH CHECK ((SELECT iam.permitted('requests.write')));
-- Pas de DELETE/TRUNCATE accordé : archivage par les champs métier.
GRANT SELECT, INSERT, UPDATE ON web.request_notes TO pd_core_api;
CREATE TRIGGER preserve_identity BEFORE UPDATE ON web.request_notes FOR EACH ROW EXECUTE FUNCTION core_meta.touch_row();
CREATE TRIGGER audit_change AFTER INSERT OR UPDATE OR DELETE ON web.request_notes FOR EACH ROW EXECUTE FUNCTION audit.record_change();


ALTER TABLE integration.connections ENABLE ROW LEVEL SECURITY;
ALTER TABLE integration.connections FORCE ROW LEVEL SECURITY;
CREATE INDEX ON integration.connections(organization_id);
CREATE POLICY tenant_boundary ON integration.connections AS RESTRICTIVE TO pd_core_api
 USING (organization_id = (SELECT iam.current_organization_id()))
 WITH CHECK (organization_id = (SELECT iam.current_organization_id()));
CREATE POLICY scoped_read ON integration.connections FOR SELECT TO pd_core_api USING ((SELECT iam.permitted('integrations.read')));
CREATE POLICY scoped_insert ON integration.connections FOR INSERT TO pd_core_api WITH CHECK ((SELECT iam.permitted('integrations.write')));
CREATE POLICY scoped_update ON integration.connections FOR UPDATE TO pd_core_api
 USING ((SELECT iam.permitted('integrations.write'))) WITH CHECK ((SELECT iam.permitted('integrations.write')));
-- Pas de DELETE/TRUNCATE accordé : archivage par les champs métier.
GRANT SELECT, INSERT, UPDATE ON integration.connections TO pd_core_api;
CREATE TRIGGER preserve_identity BEFORE UPDATE ON integration.connections FOR EACH ROW EXECUTE FUNCTION core_meta.touch_row();
CREATE TRIGGER audit_change AFTER INSERT OR UPDATE OR DELETE ON integration.connections FOR EACH ROW EXECUTE FUNCTION audit.record_change();


ALTER TABLE core.organizations ENABLE ROW LEVEL SECURITY;
ALTER TABLE core.organizations FORCE ROW LEVEL SECURITY;
CREATE POLICY own_org ON core.organizations FOR SELECT TO pd_core_api USING(id=(SELECT iam.current_organization_id()));
GRANT SELECT ON core.organizations TO pd_core_api;
GRANT SELECT ON core.applications TO pd_core_api;
ALTER TABLE core.application_plans ENABLE ROW LEVEL SECURITY;
ALTER TABLE core.application_plans FORCE ROW LEVEL SECURITY;
CREATE POLICY published_plans ON core.application_plans FOR SELECT TO pd_core_api USING(published);
GRANT SELECT ON core.application_plans TO pd_core_api;
ALTER TABLE core.subscriptions ENABLE ROW LEVEL SECURITY;
ALTER TABLE core.subscriptions FORCE ROW LEVEL SECURITY;
CREATE POLICY own_subscriptions ON core.subscriptions FOR SELECT TO pd_core_api USING(organization_id=(SELECT iam.current_organization_id()));
GRANT SELECT ON core.subscriptions TO pd_core_api;
ALTER TABLE core.organization_applications ENABLE ROW LEVEL SECURITY;
ALTER TABLE core.organization_applications FORCE ROW LEVEL SECURITY;
CREATE POLICY own_apps ON core.organization_applications FOR SELECT TO pd_core_api USING(organization_id=(SELECT iam.current_organization_id()));
GRANT SELECT ON core.organization_applications TO pd_core_api;
ALTER TABLE audit.events ENABLE ROW LEVEL SECURITY;
ALTER TABLE audit.events FORCE ROW LEVEL SECURITY;
CREATE POLICY own_audit ON audit.events FOR SELECT TO pd_core_api USING(organization_id=(SELECT iam.current_organization_id()) AND (SELECT iam.permitted('audit.read')));
GRANT SELECT ON audit.events TO pd_core_api;

-- Backend-only : ni accès API client ni droit implicite ; RLS refuse par défaut.
DO $$ DECLARE tab text; BEGIN
 FOREACH tab IN ARRAY ARRAY['web.communication_preferences','integration.connection_secrets','integration.external_references','integration.outbox','notifications.deliveries'] LOOP
  EXECUTE format('ALTER TABLE %s ENABLE ROW LEVEL SECURITY',tab);
  EXECUTE format('ALTER TABLE %s FORCE ROW LEVEL SECURITY',tab);
 END LOOP;
END $$;
-- Les futures fonctions de traitement seront ajoutées avec leurs droits propres.


-- Tables compatibles avec l'API du formulaire actuellement dans le dépôt.
-- Demandes du formulaire de contact du site vitrine ProDigital.
--
-- Une ligne `contact_submissions` = une demande, immuable après insertion.
-- Les opérations déclenchées (notification e-mail, transmission Genesis CRM)
-- sont suivies dans `contact_operations` (outbox) et leur historique dans
-- `contact_events`. Une demande enregistrée n'est donc jamais perdue, même si
-- la messagerie ou Genesis sont indisponibles : elles sont relancées ensuite.

CREATE SCHEMA IF NOT EXISTS site;

CREATE TABLE IF NOT EXISTS site.contact_submissions (
  id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  -- Clé envoyée par le navigateur : un double clic ou un renvoi réseau
  -- retombe sur la même demande au lieu d'en créer une seconde.
  idempotency_key  text NOT NULL UNIQUE CHECK (length(idempotency_key) BETWEEN 8 AND 128),
  -- Empreinte du contenu : même clé + contenu différent = conflit (409).
  request_hash     text NOT NULL,
  -- Empreinte e-mail + sujet + message : bloque les doublons sur 24 h
  -- (rechargement de page, second onglet).
  natural_key      text NOT NULL,
  given_name       text NOT NULL CHECK (length(given_name) BETWEEN 1 AND 80),
  family_name      text NOT NULL CHECK (length(family_name) BETWEEN 1 AND 80),
  email            text NOT NULL CHECK (length(email) BETWEEN 3 AND 254),
  company          text CHECK (company IS NULL OR length(company) <= 150),
  subject          text NOT NULL CHECK (length(subject) <= 200),
  subject_group    text NOT NULL,
  -- Champs complémentaires du sujet, dans l'ordre du formulaire :
  -- [{ "id": "budget", "label": "Budget envisagé", "value": "...", "required": false }]
  details          jsonb NOT NULL DEFAULT '[]'::jsonb CHECK (jsonb_typeof(details) = 'array'),
  message          text NOT NULL CHECK (length(message) BETWEEN 10 AND 5000),
  source           text NOT NULL DEFAULT 'site_web',
  created_at       timestamptz NOT NULL DEFAULT clock_timestamp()
);

CREATE INDEX IF NOT EXISTS contact_submissions_natural_key_idx
  ON site.contact_submissions (natural_key, created_at DESC);
CREATE INDEX IF NOT EXISTS contact_submissions_created_at_idx
  ON site.contact_submissions (created_at DESC);

-- Le contenu d'une demande ne se modifie pas : toutes les opérations
-- (e-mail, CRM, relances) relisent exactement ce que le client a envoyé.
CREATE OR REPLACE FUNCTION site.contact_submissions_immutable() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
  RAISE EXCEPTION 'Une demande de contact est en lecture seule (id %).', OLD.id
    USING ERRCODE = 'insufficient_privilege';
END;
$$;

DROP TRIGGER IF EXISTS contact_submissions_immutable ON site.contact_submissions;
CREATE TRIGGER contact_submissions_immutable
  BEFORE UPDATE ON site.contact_submissions
  FOR EACH ROW EXECUTE FUNCTION site.contact_submissions_immutable();

CREATE TABLE IF NOT EXISTS site.contact_operations (
  submission_id    uuid NOT NULL REFERENCES site.contact_submissions(id) ON DELETE CASCADE,
  kind             text NOT NULL CHECK (kind IN ('email', 'crm')),
  -- pending : à faire · running : en cours (bail jusqu'à locked_until)
  -- succeeded : terminé · failed : abandon automatique, relance manuelle possible
  status           text NOT NULL DEFAULT 'pending'
                   CHECK (status IN ('pending', 'running', 'succeeded', 'failed')),
  attempts         integer NOT NULL DEFAULT 0 CHECK (attempts >= 0),
  next_attempt_at  timestamptz NOT NULL DEFAULT clock_timestamp(),
  locked_until     timestamptz,
  last_error       text,
  -- Identifiant côté service distant : Message-ID SMTP ou id du lead Genesis.
  external_id      text,
  created_at       timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at       timestamptz NOT NULL DEFAULT clock_timestamp(),
  completed_at     timestamptz,
  PRIMARY KEY (submission_id, kind)
);

CREATE INDEX IF NOT EXISTS contact_operations_due_idx
  ON site.contact_operations (next_attempt_at)
  WHERE status IN ('pending', 'running');

CREATE TABLE IF NOT EXISTS site.contact_events (
  id             bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  submission_id  uuid NOT NULL REFERENCES site.contact_submissions(id) ON DELETE CASCADE,
  kind           text NOT NULL CHECK (kind IN ('submission', 'email', 'crm')),
  event          text NOT NULL,
  detail         text,
  at             timestamptz NOT NULL DEFAULT clock_timestamp()
);

CREATE INDEX IF NOT EXISTS contact_events_submission_idx
  ON site.contact_events (submission_id, at);

ALTER TABLE site.contact_submissions ADD COLUMN organization_id uuid NOT NULL DEFAULT iam.site_organization_id() REFERENCES core.organizations(id);
ALTER TABLE site.contact_submissions ADD CONSTRAINT contact_tenant_identity UNIQUE(organization_id,id);
ALTER TABLE site.contact_operations ADD COLUMN organization_id uuid NOT NULL DEFAULT iam.site_organization_id() REFERENCES core.organizations(id);
ALTER TABLE site.contact_operations ADD CONSTRAINT contact_operation_tenant_fk FOREIGN KEY(organization_id,submission_id) REFERENCES site.contact_submissions(organization_id,id);
ALTER TABLE site.contact_events ADD COLUMN organization_id uuid NOT NULL DEFAULT iam.site_organization_id() REFERENCES core.organizations(id);
ALTER TABLE site.contact_events ADD CONSTRAINT contact_event_tenant_fk FOREIGN KEY(organization_id,submission_id) REFERENCES site.contact_submissions(organization_id,id);

ALTER TABLE site.contact_submissions ENABLE ROW LEVEL SECURITY;
ALTER TABLE site.contact_submissions FORCE ROW LEVEL SECURITY;
CREATE INDEX ON site.contact_submissions(organization_id);
CREATE POLICY site_isolation ON site.contact_submissions TO pd_site_api
 USING (organization_id = (SELECT iam.site_organization_id()))
 WITH CHECK (organization_id = (SELECT iam.site_organization_id()));


ALTER TABLE site.contact_operations ENABLE ROW LEVEL SECURITY;
ALTER TABLE site.contact_operations FORCE ROW LEVEL SECURITY;
CREATE INDEX ON site.contact_operations(organization_id);
CREATE POLICY site_isolation ON site.contact_operations TO pd_site_api
 USING (organization_id = (SELECT iam.site_organization_id()))
 WITH CHECK (organization_id = (SELECT iam.site_organization_id()));


ALTER TABLE site.contact_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE site.contact_events FORCE ROW LEVEL SECURITY;
CREATE INDEX ON site.contact_events(organization_id);
CREATE POLICY site_isolation ON site.contact_events TO pd_site_api
 USING (organization_id = (SELECT iam.site_organization_id()))
 WITH CHECK (organization_id = (SELECT iam.site_organization_id()));

CREATE TABLE site.schema_migrations(name text PRIMARY KEY, applied_at timestamptz NOT NULL DEFAULT clock_timestamp());
INSERT INTO site.schema_migrations(name) VALUES ('001-site-contact.sql');
GRANT USAGE ON SCHEMA site TO pd_site_api;
GRANT SELECT, INSERT ON site.contact_submissions, site.contact_events TO pd_site_api;
GRANT SELECT, INSERT, UPDATE ON site.contact_operations TO pd_site_api;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA site TO pd_site_api;
-- Le rôle API multi-entreprises n'a aucun accès direct aux demandes du site ProDigital.
REVOKE ALL ON ALL FUNCTIONS IN SCHEMA site FROM PUBLIC;


-- Contrôle final des privilèges : pas d'accès direct au référentiel d'authentification.
REVOKE ALL ON ALL TABLES IN SCHEMA iam FROM PUBLIC,pd_core_api,pd_site_api;
REVOKE ALL ON ALL TABLES IN SCHEMA core_meta FROM PUBLIC,pd_core_api,pd_site_api;
COMMENT ON SCHEMA core IS 'Référentiel commun multi-entreprises ProDigital Core V1 ; les domaines CRM/ITSM seront ajoutés par migrations.';
COMMENT ON SCHEMA iam IS 'Privé : identités, appartenances et jetons. Accès limité aux fonctions de contexte vérifié.';

INSERT INTO core_meta.migrations(version,sha256) VALUES ('foundation_v1','b181f4e11f9a1222a3eef9a2a777a2ed7a82a196cd9a8d13e3cff0833885fa3d');
\endif
COMMIT;
