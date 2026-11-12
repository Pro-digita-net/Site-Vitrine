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
-- GENERATED_TENANT_POLICIES

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

-- GENERATED_SITE_SCHEMA

-- Contrôle final des privilèges : pas d'accès direct au référentiel d'authentification.
REVOKE ALL ON ALL TABLES IN SCHEMA iam FROM PUBLIC,pd_core_api,pd_site_api;
REVOKE ALL ON ALL TABLES IN SCHEMA core_meta FROM PUBLIC,pd_core_api,pd_site_api;
COMMENT ON SCHEMA core IS 'Référentiel commun multi-entreprises ProDigital Core V1 ; les domaines CRM/ITSM seront ajoutés par migrations.';
COMMENT ON SCHEMA iam IS 'Privé : identités, appartenances et jetons. Accès limité aux fonctions de contexte vérifié.';
