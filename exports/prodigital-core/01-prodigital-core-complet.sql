-- ProDigital : export des migrations existantes, 2026-11-12.
-- Exécuter avec psql, comme administrateur PostgreSQL 15+, dans prodigital.
-- Sauvegarder la base avant import. Ne pas lancer deux imports simultanés.
-- Ce fichier contient des commandes psql (\if, \gset) : pas un éditeur SQL générique.
-- Les nouveaux rôles sont NOLOGIN, sans mot de passe. Activer ensuite par \password.
\set ON_ERROR_STOP on
DO $$ BEGIN
 IF current_database() <> 'prodigital' THEN RAISE EXCEPTION 'Connectez-vous à la base prodigital'; END IF;
 IF current_setting('server_version_num')::int < 150000 THEN RAISE EXCEPTION 'PostgreSQL 15 minimum'; END IF;
END $$;
DO $$ BEGIN IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname='genesis') THEN CREATE ROLE genesis NOLOGIN; END IF; END $$;
DO $$ BEGIN IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname='orbit') THEN CREATE ROLE orbit NOLOGIN; END IF; END $$;
DO $$ BEGIN IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname='site_vitrine') THEN CREATE ROLE site_vitrine NOLOGIN; END IF; END $$;
CREATE SCHEMA IF NOT EXISTS deployment;
REVOKE ALL ON SCHEMA deployment FROM PUBLIC;
CREATE TABLE IF NOT EXISTS deployment.bundle_migrations (name text PRIMARY KEY, sha256 text NOT NULL, applied_at timestamptz NOT NULL DEFAULT now());
CREATE SCHEMA IF NOT EXISTS genesis AUTHORIZATION genesis;
CREATE SCHEMA IF NOT EXISTS orbit AUTHORIZATION orbit;
CREATE SCHEMA IF NOT EXISTS common;
GRANT USAGE ON SCHEMA common TO genesis, orbit;
GRANT CONNECT, TEMPORARY ON DATABASE prodigital TO genesis;
GRANT CONNECT ON DATABASE prodigital TO orbit;
ALTER ROLE genesis IN DATABASE prodigital SET search_path=genesis,common;
ALTER ROLE orbit IN DATABASE prodigital SET search_path=orbit,common;

-- ===== 001-business.sql =====
SELECT EXISTS (SELECT FROM deployment.bundle_migrations WHERE name='001-business.sql') AS bundle_done \gset
\if :bundle_done
DO $$ BEGIN IF NOT EXISTS (SELECT FROM deployment.bundle_migrations WHERE name='001-business.sql' AND sha256='78ac29f8a2b8f2783ee54dd208617b33130488d56f37d4d86a47e10523d70afa') THEN RAISE EXCEPTION 'Empreinte différente : 001-business.sql'; END IF; END $$;
\else
\set ON_ERROR_STOP on
BEGIN;
SET LOCAL lock_timeout='15s';
SET LOCAL statement_timeout='180s';
SELECT pg_advisory_xact_lock(hashtextextended('prodigital-schema',0));
CREATE SCHEMA IF NOT EXISTS infrastructure;
REVOKE ALL ON SCHEMA infrastructure FROM PUBLIC;
CREATE TABLE IF NOT EXISTS infrastructure.migrations (version text PRIMARY KEY,checksum text NOT NULL,applied_at timestamptz NOT NULL DEFAULT clock_timestamp());
SELECT EXISTS(SELECT 1 FROM infrastructure.migrations WHERE version='20261010_001_business') AS already_applied \gset
\if :already_applied
SELECT checksum='a4f11fa8dee0a5f30a09b5a7a4cc2ca3ecd2b37d383316ea722e97c41e5e6c94' AS checksum_matches FROM infrastructure.migrations WHERE version='20261010_001_business' \gset
\if :checksum_matches
\echo Migration already applied; checksum verified.
\else
DO $$ BEGIN RAISE EXCEPTION 'Migration checksum mismatch'; END $$;
\endif
\else
CREATE EXTENSION IF NOT EXISTS btree_gist WITH SCHEMA public;

CREATE TABLE infrastructure.graph_locks (graph_key text PRIMARY KEY, revision bigint NOT NULL DEFAULT 0);
REVOKE ALL ON infrastructure.graph_locks FROM PUBLIC;

CREATE FUNCTION infrastructure.touch_row() RETURNS trigger
LANGUAGE plpgsql SET search_path = pg_catalog AS $$
BEGIN
  IF NEW.id <> OLD.id OR NEW.created_at <> OLD.created_at THEN
    RAISE EXCEPTION 'Identity and creation time are immutable' USING ERRCODE='23514';
  END IF;
  NEW.updated_at := clock_timestamp();
  NEW.row_version := OLD.row_version + 1;
  RETURN NEW;
END $$;
CREATE FUNCTION infrastructure.reject_mutation() RETURNS trigger
LANGUAGE plpgsql SET search_path = pg_catalog AS $$
BEGIN
  RAISE EXCEPTION 'Append-only object: %.%', TG_TABLE_SCHEMA,TG_TABLE_NAME USING ERRCODE='23514';
END $$;
CREATE FUNCTION infrastructure.freeze_published() RETURNS trigger
LANGUAGE plpgsql SET search_path = pg_catalog AS $$
BEGIN
  IF OLD.published_at IS NOT NULL THEN
    RAISE EXCEPTION 'Published revision is immutable' USING ERRCODE='23514';
  END IF;
  IF TG_OP='DELETE' THEN RETURN OLD; END IF;
  RETURN NEW;
END $$;
-- Updating a guard row serializes graph edits, including at stronger isolation.
CREATE FUNCTION infrastructure.prevent_tree_cycle() RETURNS trigger
LANGUAGE plpgsql SET search_path = pg_catalog AS $$
DECLARE parent uuid; cyclic boolean;
BEGIN
  parent := (to_jsonb(NEW)->>TG_ARGV[0])::uuid;
  IF parent IS NULL THEN RETURN NEW; END IF;
  INSERT INTO infrastructure.graph_locks(graph_key) VALUES (TG_TABLE_SCHEMA||'.'||TG_TABLE_NAME)
  ON CONFLICT(graph_key) DO UPDATE SET revision=infrastructure.graph_locks.revision+1;
  EXECUTE format(
    'WITH RECURSIVE ancestors(id,parent) AS (
      SELECT id,%1$I FROM %2$I.%3$I WHERE id=$1
      UNION SELECT t.id,t.%1$I FROM %2$I.%3$I t JOIN ancestors a ON t.id=a.parent
    ) SELECT $1=$2 OR EXISTS(SELECT 1 FROM ancestors WHERE id=$2)',
    TG_ARGV[0],TG_TABLE_SCHEMA,TG_TABLE_NAME)
  INTO cyclic USING parent,NEW.id;
  IF cyclic THEN RAISE EXCEPTION 'Hierarchy cycle rejected' USING ERRCODE='23514'; END IF;
  RETURN NEW;
END $$;
REVOKE ALL ON ALL FUNCTIONS IN SCHEMA infrastructure FROM PUBLIC;


CREATE SCHEMA "core";
REVOKE ALL ON SCHEMA "core" FROM PUBLIC;

CREATE SCHEMA "iam";
REVOKE ALL ON SCHEMA "iam" FROM PUBLIC;

CREATE SCHEMA "crm";
REVOKE ALL ON SCHEMA "crm" FROM PUBLIC;

CREATE SCHEMA "web";
REVOKE ALL ON SCHEMA "web" FROM PUBLIC;

CREATE SCHEMA "project";
REVOKE ALL ON SCHEMA "project" FROM PUBLIC;

CREATE SCHEMA "people";
REVOKE ALL ON SCHEMA "people" FROM PUBLIC;

CREATE SCHEMA "schedule";
REVOKE ALL ON SCHEMA "schedule" FROM PUBLIC;

CREATE SCHEMA "itsm";
REVOKE ALL ON SCHEMA "itsm" FROM PUBLIC;

CREATE SCHEMA "service";
REVOKE ALL ON SCHEMA "service" FROM PUBLIC;

CREATE SCHEMA "workflow";
REVOKE ALL ON SCHEMA "workflow" FROM PUBLIC;

CREATE SCHEMA "cmdb";
REVOKE ALL ON SCHEMA "cmdb" FROM PUBLIC;

CREATE SCHEMA "inventory";
REVOKE ALL ON SCHEMA "inventory" FROM PUBLIC;

CREATE SCHEMA "commercial";
REVOKE ALL ON SCHEMA "commercial" FROM PUBLIC;

CREATE SCHEMA "billing";
REVOKE ALL ON SCHEMA "billing" FROM PUBLIC;

CREATE SCHEMA "knowledge";
REVOKE ALL ON SCHEMA "knowledge" FROM PUBLIC;

CREATE SCHEMA "docs";
REVOKE ALL ON SCHEMA "docs" FROM PUBLIC;

CREATE SCHEMA "comms";
REVOKE ALL ON SCHEMA "comms" FROM PUBLIC;

CREATE SCHEMA "integration";
REVOKE ALL ON SCHEMA "integration" FROM PUBLIC;

CREATE SCHEMA "reporting";
REVOKE ALL ON SCHEMA "reporting" FROM PUBLIC;

CREATE SCHEMA "governance";
REVOKE ALL ON SCHEMA "governance" FROM PUBLIC;

CREATE TABLE "core"."installation" (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "operator_organization_id" uuid,
  "external_tenant_key" text,
  "environment" text NOT NULL,
  "timezone" text NOT NULL,
  "locale" text NOT NULL,
  "schema_version" text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  row_version bigint NOT NULL DEFAULT 1 CHECK(row_version>0)
);

COMMENT ON TABLE "core"."installation" IS 'Identité de cette base métier | Catalogue: Une seule ligne active par base ; identifiant externe sans clé étrangère vers la base plateforme.';

ALTER TABLE "core"."installation" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "core"."installation" FORCE ROW LEVEL SECURITY;

CREATE TRIGGER z_touch BEFORE UPDATE ON "core"."installation" FOR EACH ROW EXECUTE FUNCTION infrastructure.touch_row();

CREATE TABLE "core"."organizations" (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "name" text NOT NULL,
  "legal_name" text,
  "kind" text NOT NULL,
  "country_code" text NOT NULL,
  "status" text NOT NULL,
  "website" text,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  row_version bigint NOT NULL DEFAULT 1 CHECK(row_version>0)
);

COMMENT ON TABLE "core"."organizations" IS 'Sociétés, groupes et organismes | Catalogue: Le nom n’est pas unique ; identifiants légaux dans une table dédiée.';

ALTER TABLE "core"."organizations" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "core"."organizations" FORCE ROW LEVEL SECURITY;

CREATE TRIGGER z_touch BEFORE UPDATE ON "core"."organizations" FOR EACH ROW EXECUTE FUNCTION infrastructure.touch_row();

ALTER TABLE "core"."organizations" ADD CONSTRAINT "c_264f54c37edce9277f57" CHECK ("country_code" ~ '^[A-Z]{2}$');

CREATE TABLE "core"."organization_identifiers" (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "organization_id" uuid NOT NULL,
  "scheme" text NOT NULL,
  "country_code" text NOT NULL,
  "value" text NOT NULL,
  "valid_from" date,
  "valid_to" date,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  row_version bigint NOT NULL DEFAULT 1 CHECK(row_version>0)
);

COMMENT ON TABLE "core"."organization_identifiers" IS 'Identifiants légaux ou métiers | Catalogue: Unicité contrôlée par pays et schéma ; aucune fusion automatique sur le nom.';

ALTER TABLE "core"."organization_identifiers" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "core"."organization_identifiers" FORCE ROW LEVEL SECURITY;

CREATE TRIGGER z_touch BEFORE UPDATE ON "core"."organization_identifiers" FOR EACH ROW EXECUTE FUNCTION infrastructure.touch_row();

ALTER TABLE "core"."organization_identifiers" ADD CONSTRAINT "c_993b46010538147c83b9" CHECK ("country_code" ~ '^[A-Z]{2}$');

ALTER TABLE "core"."organization_identifiers" ADD CONSTRAINT "c_53e5f9e105af86d89ad1" CHECK ("valid_to" >= "valid_from");

ALTER TABLE "core"."organization_identifiers" ADD CONSTRAINT "c_de379e1c741f0466183c" UNIQUE NULLS NOT DISTINCT ("scheme", "country_code", "value");

CREATE TABLE "core"."organization_relations" (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "parent_id" uuid NOT NULL,
  "child_id" uuid NOT NULL,
  "relation_type" text NOT NULL,
  "valid_from" date NOT NULL,
  "valid_to" date,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  row_version bigint NOT NULL DEFAULT 1 CHECK(row_version>0)
);

COMMENT ON TABLE "core"."organization_relations" IS 'Structure des groupes et filiales | Catalogue: Interdire auto-lien et cycles hiérarchiques ; permettre une relation non hiérarchique typée.';

ALTER TABLE "core"."organization_relations" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "core"."organization_relations" FORCE ROW LEVEL SECURITY;

CREATE TRIGGER z_touch BEFORE UPDATE ON "core"."organization_relations" FOR EACH ROW EXECUTE FUNCTION infrastructure.touch_row();

ALTER TABLE "core"."organization_relations" ADD CONSTRAINT "c_47cb3886eb7fe01ea28a" CHECK ("valid_to" >= "valid_from");

CREATE TABLE "core"."organization_roles" (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "organization_id" uuid NOT NULL,
  "role_code" text NOT NULL,
  "valid_from" date NOT NULL,
  "valid_to" date,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  row_version bigint NOT NULL DEFAULT 1 CHECK(row_version>0)
);

COMMENT ON TABLE "core"."organization_roles" IS 'Client, fournisseur, partenaire, opérateur | Catalogue: Plusieurs rôles simultanés permis.';

ALTER TABLE "core"."organization_roles" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "core"."organization_roles" FORCE ROW LEVEL SECURITY;

CREATE TRIGGER z_touch BEFORE UPDATE ON "core"."organization_roles" FOR EACH ROW EXECUTE FUNCTION infrastructure.touch_row();

ALTER TABLE "core"."organization_roles" ADD CONSTRAINT "c_43e55be315d1c105438c" CHECK ("valid_to" >= "valid_from");

ALTER TABLE "core"."organization_roles" ADD CONSTRAINT "c_4c8693f08ba04fbfeba9" UNIQUE NULLS NOT DISTINCT ("organization_id", "role_code", "valid_from");

CREATE TABLE "core"."sites" (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "organization_id" uuid NOT NULL,
  "code" text NOT NULL,
  "name" text NOT NULL,
  "address_id" uuid,
  "timezone" text NOT NULL,
  "active" boolean NOT NULL,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  row_version bigint NOT NULL DEFAULT 1 CHECK(row_version>0)
);

COMMENT ON TABLE "core"."sites" IS 'Établissements physiques | Catalogue: UNIQUE organisation + code ; rattachement à une société explicite.';

ALTER TABLE "core"."sites" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "core"."sites" FORCE ROW LEVEL SECURITY;

CREATE TRIGGER z_touch BEFORE UPDATE ON "core"."sites" FOR EACH ROW EXECUTE FUNCTION infrastructure.touch_row();

ALTER TABLE "core"."sites" ADD CONSTRAINT "c_bcf5a73a54616d946a38" UNIQUE NULLS NOT DISTINCT ("organization_id", "code");

CREATE TABLE "core"."locations" (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "site_id" uuid NOT NULL,
  "parent_id" uuid,
  "kind" text NOT NULL,
  "code" text NOT NULL,
  "label" text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  row_version bigint NOT NULL DEFAULT 1 CHECK(row_version>0)
);

COMMENT ON TABLE "core"."locations" IS 'Bâtiments, étages, salles et baies | Catalogue: Parent dans le même site ; arborescence sans cycle.';

ALTER TABLE "core"."locations" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "core"."locations" FORCE ROW LEVEL SECURITY;

CREATE TRIGGER z_touch BEFORE UPDATE ON "core"."locations" FOR EACH ROW EXECUTE FUNCTION infrastructure.touch_row();

ALTER TABLE "core"."locations" ADD CONSTRAINT "c_75051dd12c09adcd8d7e" CHECK ("parent_id" <> id);

ALTER TABLE "core"."locations" ADD CONSTRAINT "c_894f5d9db2607fb372dd" UNIQUE NULLS NOT DISTINCT ("site_id", "code");

CREATE TABLE "core"."addresses" (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "line1" text NOT NULL,
  "line2" text,
  "postal_code" text,
  "city" text NOT NULL,
  "region" text,
  "country_code" text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  row_version bigint NOT NULL DEFAULT 1 CHECK(row_version>0)
);

COMMENT ON TABLE "core"."addresses" IS 'Adresses structurées | Catalogue: Adresses historisables ; copie figée sur les documents commerciaux émis.';

ALTER TABLE "core"."addresses" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "core"."addresses" FORCE ROW LEVEL SECURITY;

CREATE TRIGGER z_touch BEFORE UPDATE ON "core"."addresses" FOR EACH ROW EXECUTE FUNCTION infrastructure.touch_row();

ALTER TABLE "core"."addresses" ADD CONSTRAINT "c_7aadb9536e3a5f3800ae" CHECK ("country_code" ~ '^[A-Z]{2}$');

CREATE TABLE "core"."persons" (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "given_name" text NOT NULL,
  "family_name" text NOT NULL,
  "preferred_name" text,
  "locale" text NOT NULL,
  "status" text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  row_version bigint NOT NULL DEFAULT 1 CHECK(row_version>0)
);

COMMENT ON TABLE "core"."persons" IS 'Personnes sans obligation de compte | Catalogue: Ne contient ni rôle global ni company_id unique.';

ALTER TABLE "core"."persons" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "core"."persons" FORCE ROW LEVEL SECURITY;

CREATE TRIGGER z_touch BEFORE UPDATE ON "core"."persons" FOR EACH ROW EXECUTE FUNCTION infrastructure.touch_row();

CREATE TABLE "core"."person_contacts" (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "person_id" uuid NOT NULL,
  "kind" text NOT NULL,
  "value" text NOT NULL,
  "normalized_value" text NOT NULL,
  "verified_at" timestamptz,
  "is_primary" boolean NOT NULL,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  row_version bigint NOT NULL DEFAULT 1 CHECK(row_version>0)
);

COMMENT ON TABLE "core"."person_contacts" IS 'Coordonnées professionnelles | Catalogue: Adresse email non assimilée à une identité authentifiée ; visibilité contrôlée.';

ALTER TABLE "core"."person_contacts" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "core"."person_contacts" FORCE ROW LEVEL SECURITY;

CREATE TRIGGER z_touch BEFORE UPDATE ON "core"."person_contacts" FOR EACH ROW EXECUTE FUNCTION infrastructure.touch_row();

CREATE TABLE "core"."affiliations" (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "person_id" uuid NOT NULL,
  "organization_id" uuid NOT NULL,
  "site_id" uuid,
  "job_title" text,
  "department" text,
  "valid_from" date NOT NULL,
  "valid_to" date,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  row_version bigint NOT NULL DEFAULT 1 CHECK(row_version>0)
);

COMMENT ON TABLE "core"."affiliations" IS 'Appartenance d’une personne à une société | Catalogue: Site dans la société indiquée ; historique des changements conservé.';

ALTER TABLE "core"."affiliations" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "core"."affiliations" FORCE ROW LEVEL SECURITY;

CREATE TRIGGER z_touch BEFORE UPDATE ON "core"."affiliations" FOR EACH ROW EXECUTE FUNCTION infrastructure.touch_row();

ALTER TABLE "core"."affiliations" ADD CONSTRAINT "c_e70674c7962459b2a980" CHECK ("valid_to" >= "valid_from");

CREATE TABLE "core"."reporting_lines" (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "manager_affiliation_id" uuid NOT NULL,
  "member_affiliation_id" uuid NOT NULL,
  "valid_from" date NOT NULL,
  "valid_to" date,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  row_version bigint NOT NULL DEFAULT 1 CHECK(row_version>0)
);

COMMENT ON TABLE "core"."reporting_lines" IS 'Responsables de collaborateurs clients | Catalogue: Relation organisationnelle seulement : ne confère pas à elle seule un accès aux tickets.';

ALTER TABLE "core"."reporting_lines" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "core"."reporting_lines" FORCE ROW LEVEL SECURITY;

CREATE TRIGGER z_touch BEFORE UPDATE ON "core"."reporting_lines" FOR EACH ROW EXECUTE FUNCTION infrastructure.touch_row();

ALTER TABLE "core"."reporting_lines" ADD CONSTRAINT "c_9b0fbf36c612cdca4461" CHECK ("valid_to" >= "valid_from");

CREATE TABLE "core"."teams" (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "organization_id" uuid NOT NULL,
  "name" text NOT NULL,
  "kind" text NOT NULL,
  "parent_id" uuid,
  "active" boolean NOT NULL,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  row_version bigint NOT NULL DEFAULT 1 CHECK(row_version>0)
);

COMMENT ON TABLE "core"."teams" IS 'Équipes métier internes ou support | Catalogue: Nombre d’équipes non fixé ; hiérarchie sans cycle.';

ALTER TABLE "core"."teams" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "core"."teams" FORCE ROW LEVEL SECURITY;

CREATE TRIGGER z_touch BEFORE UPDATE ON "core"."teams" FOR EACH ROW EXECUTE FUNCTION infrastructure.touch_row();

ALTER TABLE "core"."teams" ADD CONSTRAINT "c_84f73c7c4d1e317b67a9" CHECK ("parent_id" <> id);

CREATE TABLE "core"."team_memberships" (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "team_id" uuid NOT NULL,
  "person_id" uuid NOT NULL,
  "role_code" text NOT NULL,
  "valid_from" timestamptz NOT NULL,
  "valid_to" timestamptz,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  row_version bigint NOT NULL DEFAULT 1 CHECK(row_version>0)
);

COMMENT ON TABLE "core"."team_memberships" IS 'Membres des équipes | Catalogue: Périodes d’appartenance historisées ; pas de doublons actifs équivalents.';

ALTER TABLE "core"."team_memberships" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "core"."team_memberships" FORCE ROW LEVEL SECURITY;

CREATE TRIGGER z_touch BEFORE UPDATE ON "core"."team_memberships" FOR EACH ROW EXECUTE FUNCTION infrastructure.touch_row();

ALTER TABLE "core"."team_memberships" ADD CONSTRAINT "c_6a4054167af79e8d6dfa" CHECK ("valid_to" >= "valid_from");

ALTER TABLE "core"."team_memberships" ADD CONSTRAINT "c_0f7279a5a487458196b4" UNIQUE NULLS NOT DISTINCT ("team_id", "person_id", "role_code", "valid_from");

CREATE TABLE "core"."tags" (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "code" text NOT NULL,
  "label" text NOT NULL,
  "color_token" text,
  "active" boolean NOT NULL,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  row_version bigint NOT NULL DEFAULT 1 CHECK(row_version>0)
);

COMMENT ON TABLE "core"."tags" IS 'Étiquettes communes | Catalogue: Code unique ; liens par domaine avec vraies références.';

ALTER TABLE "core"."tags" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "core"."tags" FORCE ROW LEVEL SECURITY;

CREATE TRIGGER z_touch BEFORE UPDATE ON "core"."tags" FOR EACH ROW EXECUTE FUNCTION infrastructure.touch_row();

ALTER TABLE "core"."tags" ADD CONSTRAINT "c_76ec8bb7c53790714851" UNIQUE NULLS NOT DISTINCT ("code");

CREATE TABLE "iam"."principals" (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "person_id" uuid,
  "kind" text NOT NULL,
  "status" text NOT NULL,
  "display_name" text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  row_version bigint NOT NULL DEFAULT 1 CHECK(row_version>0)
);

COMMENT ON TABLE "iam"."principals" IS 'Comptes humains et techniques | Catalogue: Un contact sans compte reste dans core.persons ; comptes de service distincts.';

ALTER TABLE "iam"."principals" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "iam"."principals" FORCE ROW LEVEL SECURITY;

CREATE TRIGGER z_touch BEFORE UPDATE ON "iam"."principals" FOR EACH ROW EXECUTE FUNCTION infrastructure.touch_row();

CREATE TABLE "iam"."identity_links" (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "principal_id" uuid NOT NULL,
  "issuer" text NOT NULL,
  "subject" text NOT NULL,
  "last_authenticated_at" timestamptz,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  row_version bigint NOT NULL DEFAULT 1 CHECK(row_version>0)
);

COMMENT ON TABLE "iam"."identity_links" IS 'Liaison au fournisseur d’identité | Catalogue: UNIQUE issuer + subject ; aucun mot de passe en clair ni secret MFA dans la base métier.';

ALTER TABLE "iam"."identity_links" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "iam"."identity_links" FORCE ROW LEVEL SECURITY;

CREATE TRIGGER z_touch BEFORE UPDATE ON "iam"."identity_links" FOR EACH ROW EXECUTE FUNCTION infrastructure.touch_row();

ALTER TABLE "iam"."identity_links" ADD CONSTRAINT "c_731f331658d61cad007d" UNIQUE NULLS NOT DISTINCT ("issuer", "subject");

CREATE TABLE "iam"."applications" (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "code" text NOT NULL,
  "name" text NOT NULL,
  "audience" text NOT NULL,
  "enabled" boolean NOT NULL,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  row_version bigint NOT NULL DEFAULT 1 CHECK(row_version>0)
);

COMMENT ON TABLE "iam"."applications" IS 'Applications et audiences d’API | Catalogue: Codes stables : CRM, ITSM, projets, collaborateurs, commercial, vitrine.';

ALTER TABLE "iam"."applications" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "iam"."applications" FORCE ROW LEVEL SECURITY;

CREATE TRIGGER z_touch BEFORE UPDATE ON "iam"."applications" FOR EACH ROW EXECUTE FUNCTION infrastructure.touch_row();

ALTER TABLE "iam"."applications" ADD CONSTRAINT "c_256cff6c7c59b987c706" UNIQUE NULLS NOT DISTINCT ("code");

CREATE TABLE "iam"."permissions" (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "application_id" uuid NOT NULL,
  "resource_type" text NOT NULL,
  "action" text NOT NULL,
  "field_group" text,
  "code" text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  row_version bigint NOT NULL DEFAULT 1 CHECK(row_version>0)
);

COMMENT ON TABLE "iam"."permissions" IS 'Catalogue des actions autorisables | Catalogue: Code unique ; lire, créer, modifier, supprimer, exporter, approuver, administrer séparés.';

ALTER TABLE "iam"."permissions" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "iam"."permissions" FORCE ROW LEVEL SECURITY;

CREATE TRIGGER z_touch BEFORE UPDATE ON "iam"."permissions" FOR EACH ROW EXECUTE FUNCTION infrastructure.touch_row();

ALTER TABLE "iam"."permissions" ADD CONSTRAINT "c_7b86f156461e041f735a" UNIQUE NULLS NOT DISTINCT ("code");

CREATE TABLE "iam"."roles" (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "code" text NOT NULL,
  "label" text NOT NULL,
  "description" text,
  "system_role" boolean NOT NULL,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  row_version bigint NOT NULL DEFAULT 1 CHECK(row_version>0)
);

COMMENT ON TABLE "iam"."roles" IS 'Profils personnalisables | Catalogue: Super administrateur métier distinct du super administrateur SQL et de la plateforme.';

ALTER TABLE "iam"."roles" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "iam"."roles" FORCE ROW LEVEL SECURITY;

CREATE TRIGGER z_touch BEFORE UPDATE ON "iam"."roles" FOR EACH ROW EXECUTE FUNCTION infrastructure.touch_row();

ALTER TABLE "iam"."roles" ADD CONSTRAINT "c_f6156b59bd5d0c175d05" UNIQUE NULLS NOT DISTINCT ("code");

CREATE TABLE "iam"."role_permissions" (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "role_id" uuid NOT NULL,
  "permission_id" uuid NOT NULL,
  "effect" text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  row_version bigint NOT NULL DEFAULT 1 CHECK(row_version>0)
);

COMMENT ON TABLE "iam"."role_permissions" IS 'Droits inclus dans un profil | Catalogue: UNIQUE rôle + permission ; politique de conflit explicite, refus prioritaire.';

ALTER TABLE "iam"."role_permissions" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "iam"."role_permissions" FORCE ROW LEVEL SECURITY;

CREATE TRIGGER z_touch BEFORE UPDATE ON "iam"."role_permissions" FOR EACH ROW EXECUTE FUNCTION infrastructure.touch_row();

ALTER TABLE "iam"."role_permissions" ADD CONSTRAINT "c_82501277325214711ef2" CHECK (effect IN ('allow','deny'));

ALTER TABLE "iam"."role_permissions" ADD CONSTRAINT "c_dc498a533aea0b591c14" UNIQUE NULLS NOT DISTINCT ("role_id", "permission_id");

CREATE TABLE "iam"."access_scopes" (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "kind" text NOT NULL,
  "organization_id" uuid,
  "site_id" uuid,
  "team_id" uuid,
  "project_id" uuid,
  "subject_person_id" uuid,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  row_version bigint NOT NULL DEFAULT 1 CHECK(row_version>0)
);

COMMENT ON TABLE "iam"."access_scopes" IS 'Périmètres de visibilité | Catalogue: CHECK colonnes selon kind : soi, société, site, équipe, projet, installation ; pas de portée implicite.';

ALTER TABLE "iam"."access_scopes" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "iam"."access_scopes" FORCE ROW LEVEL SECURITY;

CREATE TRIGGER z_touch BEFORE UPDATE ON "iam"."access_scopes" FOR EACH ROW EXECUTE FUNCTION infrastructure.touch_row();

ALTER TABLE "iam"."access_scopes" ADD CONSTRAINT "c_7181e17f061f7c7d6b49" CHECK ((kind='installation' AND num_nonnulls(organization_id,site_id,team_id,project_id,subject_person_id)=0) OR (num_nonnulls(organization_id,site_id,team_id,project_id,subject_person_id)=1 AND ((kind='organization' AND organization_id IS NOT NULL) OR (kind='site' AND site_id IS NOT NULL) OR (kind='team' AND team_id IS NOT NULL) OR (kind='project' AND project_id IS NOT NULL) OR (kind='self' AND subject_person_id IS NOT NULL))));

CREATE TABLE "iam"."role_bindings" (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "principal_id" uuid NOT NULL,
  "role_id" uuid NOT NULL,
  "scope_id" uuid NOT NULL,
  "valid_from" timestamptz NOT NULL,
  "valid_to" timestamptz,
  "granted_by" uuid NOT NULL,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  row_version bigint NOT NULL DEFAULT 1 CHECK(row_version>0)
);

COMMENT ON TABLE "iam"."role_bindings" IS 'Attribution datée d’un profil | Catalogue: Contrôle d’autorité du donneur ; révocation effective dans les caches et sessions.';

ALTER TABLE "iam"."role_bindings" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "iam"."role_bindings" FORCE ROW LEVEL SECURITY;

CREATE TRIGGER z_touch BEFORE UPDATE ON "iam"."role_bindings" FOR EACH ROW EXECUTE FUNCTION infrastructure.touch_row();

ALTER TABLE "iam"."role_bindings" ADD CONSTRAINT "c_8c246336d458cb290d36" CHECK ("valid_to" >= "valid_from");

CREATE TABLE "iam"."delegations" (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "grantor_id" uuid NOT NULL,
  "delegate_id" uuid NOT NULL,
  "role_binding_id" uuid NOT NULL,
  "starts_at" timestamptz NOT NULL,
  "ends_at" timestamptz NOT NULL,
  "revoked_at" timestamptz,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  row_version bigint NOT NULL DEFAULT 1 CHECK(row_version>0)
);

COMMENT ON TABLE "iam"."delegations" IS 'Remplacement temporaire encadré | Catalogue: Pas de délégation plus large ni plus longue que le droit initial.';

ALTER TABLE "iam"."delegations" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "iam"."delegations" FORCE ROW LEVEL SECURITY;

CREATE TRIGGER z_touch BEFORE UPDATE ON "iam"."delegations" FOR EACH ROW EXECUTE FUNCTION infrastructure.touch_row();

ALTER TABLE "iam"."delegations" ADD CONSTRAINT "c_bd3e8f86a2ea7d6d044d" CHECK (grantor_id <> delegate_id);

ALTER TABLE "iam"."delegations" ADD CONSTRAINT "c_ba788b74fe24cda39047" CHECK ("ends_at" > "starts_at");

CREATE TABLE "iam"."policy_versions" (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "version_no" integer NOT NULL,
  "rules" jsonb NOT NULL,
  "published_at" timestamptz,
  "published_by" uuid,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  row_version bigint NOT NULL DEFAULT 1 CHECK(row_version>0)
);

COMMENT ON TABLE "iam"."policy_versions" IS 'Versions des règles d’autorisation | Catalogue: Version publiée immuable ; toute API connaît la version évaluée.';

ALTER TABLE "iam"."policy_versions" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "iam"."policy_versions" FORCE ROW LEVEL SECURITY;

CREATE TRIGGER z_touch BEFORE UPDATE ON "iam"."policy_versions" FOR EACH ROW EXECUTE FUNCTION infrastructure.touch_row();

CREATE TRIGGER a_published BEFORE UPDATE OR DELETE ON "iam"."policy_versions" FOR EACH ROW EXECUTE FUNCTION infrastructure.freeze_published();

ALTER TABLE "iam"."policy_versions" ADD CONSTRAINT "c_0d73660e93e825afed85" CHECK ("version_no" > 0);

ALTER TABLE "iam"."policy_versions" ADD CONSTRAINT "c_f8293190cd804805a33b" UNIQUE NULLS NOT DISTINCT ("version_no");

CREATE TABLE "iam"."access_reviews" (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "role_binding_id" uuid NOT NULL,
  "reviewer_id" uuid NOT NULL,
  "due_at" timestamptz NOT NULL,
  "decision" text,
  "decided_at" timestamptz,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  row_version bigint NOT NULL DEFAULT 1 CHECK(row_version>0)
);

COMMENT ON TABLE "iam"."access_reviews" IS 'Revue périodique des droits | Catalogue: Conserver justification et décisions ; pas d’auto-approbation sensible.';

ALTER TABLE "iam"."access_reviews" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "iam"."access_reviews" FORCE ROW LEVEL SECURITY;

CREATE TRIGGER z_touch BEFORE UPDATE ON "iam"."access_reviews" FOR EACH ROW EXECUTE FUNCTION infrastructure.touch_row();

CREATE TABLE "iam"."service_credentials" (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "principal_id" uuid NOT NULL,
  "key_fingerprint" text NOT NULL,
  "secret_ref" text,
  "scopes" jsonb NOT NULL,
  "expires_at" timestamptz,
  "revoked_at" timestamptz,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  row_version bigint NOT NULL DEFAULT 1 CHECK(row_version>0)
);

COMMENT ON TABLE "iam"."service_credentials" IS 'Métadonnées des accès automatisés | Catalogue: Secret dans coffre séparé ; empreinte seulement pour vérifier une clé entrante.';

ALTER TABLE "iam"."service_credentials" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "iam"."service_credentials" FORCE ROW LEVEL SECURITY;

CREATE TRIGGER z_touch BEFORE UPDATE ON "iam"."service_credentials" FOR EACH ROW EXECUTE FUNCTION infrastructure.touch_row();

ALTER TABLE "iam"."service_credentials" ADD CONSTRAINT "c_df85eae7bbae1353ab87" UNIQUE NULLS NOT DISTINCT ("key_fingerprint");

CREATE TABLE "crm"."accounts" (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "organization_id" uuid NOT NULL,
  "owner_id" uuid,
  "lifecycle" text NOT NULL,
  "source" text,
  "customer_since" date,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  row_version bigint NOT NULL DEFAULT 1 CHECK(row_version>0)
);

COMMENT ON TABLE "crm"."accounts" IS 'Relation commerciale avec une société | Catalogue: UNIQUE société ; prospect/client désigne la relation, opportunité désigne une affaire distincte.';

ALTER TABLE "crm"."accounts" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "crm"."accounts" FORCE ROW LEVEL SECURITY;

CREATE TRIGGER z_touch BEFORE UPDATE ON "crm"."accounts" FOR EACH ROW EXECUTE FUNCTION infrastructure.touch_row();

ALTER TABLE "crm"."accounts" ADD CONSTRAINT "c_312054dc5aeb1d7ca0f3" UNIQUE NULLS NOT DISTINCT ("organization_id");

CREATE TABLE "crm"."leads" (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "organization_id" uuid,
  "person_id" uuid,
  "source_request_id" uuid,
  "owner_id" uuid,
  "status" text NOT NULL,
  "qualified_at" timestamptz,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  row_version bigint NOT NULL DEFAULT 1 CHECK(row_version>0)
);

COMMENT ON TABLE "crm"."leads" IS 'Pistes à qualifier | Catalogue: Conserver origine, qualification et raison du rejet.';

ALTER TABLE "crm"."leads" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "crm"."leads" FORCE ROW LEVEL SECURITY;

CREATE TRIGGER z_touch BEFORE UPDATE ON "crm"."leads" FOR EACH ROW EXECUTE FUNCTION infrastructure.touch_row();

CREATE TABLE "crm"."pipelines" (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "code" text NOT NULL,
  "label" text NOT NULL,
  "active" boolean NOT NULL,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  row_version bigint NOT NULL DEFAULT 1 CHECK(row_version>0)
);

COMMENT ON TABLE "crm"."pipelines" IS 'Processus de vente | Catalogue: Plusieurs pipelines possibles.';

ALTER TABLE "crm"."pipelines" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "crm"."pipelines" FORCE ROW LEVEL SECURITY;

CREATE TRIGGER z_touch BEFORE UPDATE ON "crm"."pipelines" FOR EACH ROW EXECUTE FUNCTION infrastructure.touch_row();

ALTER TABLE "crm"."pipelines" ADD CONSTRAINT "c_7988ef26b00f95102f1f" UNIQUE NULLS NOT DISTINCT ("code");

CREATE TABLE "crm"."stages" (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "pipeline_id" uuid NOT NULL,
  "code" text NOT NULL,
  "label" text NOT NULL,
  "position" integer NOT NULL,
  "probability" numeric(20,6) NOT NULL,
  "terminal_kind" text,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  row_version bigint NOT NULL DEFAULT 1 CHECK(row_version>0)
);

COMMENT ON TABLE "crm"."stages" IS 'Étapes d’un pipeline | Catalogue: UNIQUE pipeline + code ; probabilité entre 0 et 1 ; gagné et perdu distingués.';

ALTER TABLE "crm"."stages" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "crm"."stages" FORCE ROW LEVEL SECURITY;

CREATE TRIGGER z_touch BEFORE UPDATE ON "crm"."stages" FOR EACH ROW EXECUTE FUNCTION infrastructure.touch_row();

ALTER TABLE "crm"."stages" ADD CONSTRAINT "c_bed529246089f50ce149" CHECK (terminal_kind IS NULL OR terminal_kind IN ('won','lost'));

ALTER TABLE "crm"."stages" ADD CONSTRAINT "c_2f94c670180021707cd9" CHECK ("probability" <> 'NaN'::numeric);

ALTER TABLE "crm"."stages" ADD CONSTRAINT "c_885f54d79278eb9eb18b" CHECK ("probability" BETWEEN 0 AND 1);

ALTER TABLE "crm"."stages" ADD CONSTRAINT "c_bacfb763138f524b0306" UNIQUE NULLS NOT DISTINCT ("pipeline_id", "code");

ALTER TABLE "crm"."stages" ADD CONSTRAINT "c_b3714507f3410d882845" UNIQUE NULLS NOT DISTINCT ("pipeline_id", "position");

CREATE TABLE "crm"."opportunities" (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "account_id" uuid NOT NULL,
  "pipeline_id" uuid NOT NULL,
  "stage_id" uuid NOT NULL,
  "lead_id" uuid,
  "owner_id" uuid NOT NULL,
  "title" text NOT NULL,
  "amount" numeric(20,6) NOT NULL,
  "currency" text NOT NULL,
  "expected_close_on" date,
  "closed_at" timestamptz,
  "loss_reason" text,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  row_version bigint NOT NULL DEFAULT 1 CHECK(row_version>0)
);

COMMENT ON TABLE "crm"."opportunities" IS 'Affaires commerciales | Catalogue: Étape appartenant au pipeline ; devise explicite ; historique de valeur.';

ALTER TABLE "crm"."opportunities" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "crm"."opportunities" FORCE ROW LEVEL SECURITY;

CREATE TRIGGER z_touch BEFORE UPDATE ON "crm"."opportunities" FOR EACH ROW EXECUTE FUNCTION infrastructure.touch_row();

ALTER TABLE "crm"."opportunities" ADD CONSTRAINT "c_b1e622a9c314932ee871" CHECK ("amount" <> 'NaN'::numeric);

ALTER TABLE "crm"."opportunities" ADD CONSTRAINT "c_51ee98752f5d4c28e293" CHECK ("currency" ~ '^[A-Z]{3}$');

CREATE TABLE "crm"."opportunity_contacts" (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "opportunity_id" uuid NOT NULL,
  "affiliation_id" uuid NOT NULL,
  "role" text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  row_version bigint NOT NULL DEFAULT 1 CHECK(row_version>0)
);

COMMENT ON TABLE "crm"."opportunity_contacts" IS 'Décideurs et participants | Catalogue: Plusieurs sociétés participantes possibles, explicitement autorisées.';

ALTER TABLE "crm"."opportunity_contacts" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "crm"."opportunity_contacts" FORCE ROW LEVEL SECURITY;

CREATE TRIGGER z_touch BEFORE UPDATE ON "crm"."opportunity_contacts" FOR EACH ROW EXECUTE FUNCTION infrastructure.touch_row();

ALTER TABLE "crm"."opportunity_contacts" ADD CONSTRAINT "c_d52f88ce996053e4830c" UNIQUE NULLS NOT DISTINCT ("opportunity_id", "affiliation_id", "role");

CREATE TABLE "crm"."opportunity_lines" (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "opportunity_id" uuid NOT NULL,
  "product_id" uuid,
  "description" text NOT NULL,
  "quantity" numeric(20,6) NOT NULL,
  "unit_price" numeric(20,6) NOT NULL,
  "discount_rate" numeric(20,6) NOT NULL,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  row_version bigint NOT NULL DEFAULT 1 CHECK(row_version>0)
);

COMMENT ON TABLE "crm"."opportunity_lines" IS 'Prestations proposées dans l’affaire | Catalogue: Estimation commerciale, pas facture ; total calculé et règles d’arrondi explicites.';

ALTER TABLE "crm"."opportunity_lines" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "crm"."opportunity_lines" FORCE ROW LEVEL SECURITY;

CREATE TRIGGER z_touch BEFORE UPDATE ON "crm"."opportunity_lines" FOR EACH ROW EXECUTE FUNCTION infrastructure.touch_row();

ALTER TABLE "crm"."opportunity_lines" ADD CONSTRAINT "c_f30fb6a9ab61305d8c1d" CHECK ("quantity" <> 'NaN'::numeric);

ALTER TABLE "crm"."opportunity_lines" ADD CONSTRAINT "c_6db0c6918ba840112c48" CHECK ("quantity" >= 0);

ALTER TABLE "crm"."opportunity_lines" ADD CONSTRAINT "c_7e4fa39b76a73b1e1d59" CHECK ("unit_price" <> 'NaN'::numeric);

ALTER TABLE "crm"."opportunity_lines" ADD CONSTRAINT "c_d5920c0a031b04a79d7a" CHECK ("unit_price" >= 0);

ALTER TABLE "crm"."opportunity_lines" ADD CONSTRAINT "c_029bd455026213cc92f9" CHECK ("discount_rate" <> 'NaN'::numeric);

ALTER TABLE "crm"."opportunity_lines" ADD CONSTRAINT "c_bf8ddc2e06cfb585d4ee" CHECK ("discount_rate" BETWEEN 0 AND 1);

CREATE TABLE "crm"."opportunity_history" (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "opportunity_id" uuid NOT NULL,
  "stage_id" uuid NOT NULL,
  "amount" numeric(20,6) NOT NULL,
  "probability" numeric(20,6) NOT NULL,
  "changed_at" timestamptz NOT NULL,
  "actor_id" uuid NOT NULL,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  row_version bigint NOT NULL DEFAULT 1 CHECK(row_version>0)
);

COMMENT ON TABLE "crm"."opportunity_history" IS 'Changements commerciaux | Catalogue: Ajout seulement ; prévisions passées reconstructibles.';

ALTER TABLE "crm"."opportunity_history" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "crm"."opportunity_history" FORCE ROW LEVEL SECURITY;

CREATE TRIGGER z_touch BEFORE UPDATE ON "crm"."opportunity_history" FOR EACH ROW EXECUTE FUNCTION infrastructure.touch_row();

CREATE TRIGGER a_immutable BEFORE UPDATE OR DELETE ON "crm"."opportunity_history" FOR EACH ROW EXECUTE FUNCTION infrastructure.reject_mutation();
CREATE TRIGGER a_no_truncate BEFORE TRUNCATE ON "crm"."opportunity_history" FOR EACH STATEMENT EXECUTE FUNCTION infrastructure.reject_mutation();

ALTER TABLE "crm"."opportunity_history" ADD CONSTRAINT "c_1888fca5cbde8c033f3f" CHECK ("amount" <> 'NaN'::numeric);

ALTER TABLE "crm"."opportunity_history" ADD CONSTRAINT "c_1ffcb559496c6099328d" CHECK ("probability" <> 'NaN'::numeric);

ALTER TABLE "crm"."opportunity_history" ADD CONSTRAINT "c_f088fec8eb45d7dedfe9" CHECK ("probability" BETWEEN 0 AND 1);

CREATE TABLE "crm"."activities" (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "account_id" uuid,
  "person_id" uuid,
  "opportunity_id" uuid,
  "owner_id" uuid NOT NULL,
  "kind" text NOT NULL,
  "subject" text NOT NULL,
  "due_at" timestamptz,
  "completed_at" timestamptz,
  "summary" text,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  row_version bigint NOT NULL DEFAULT 1 CHECK(row_version>0)
);

COMMENT ON TABLE "crm"."activities" IS 'Appels, rendez-vous et relances | Catalogue: Un rendez-vous réservé pointe aussi vers une réservation de disponibilité.';

ALTER TABLE "crm"."activities" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "crm"."activities" FORCE ROW LEVEL SECURITY;

CREATE TRIGGER z_touch BEFORE UPDATE ON "crm"."activities" FOR EACH ROW EXECUTE FUNCTION infrastructure.touch_row();

CREATE TABLE "crm"."notes" (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "account_id" uuid NOT NULL,
  "author_id" uuid NOT NULL,
  "body" text NOT NULL,
  "visibility" text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  row_version bigint NOT NULL DEFAULT 1 CHECK(row_version>0)
);

COMMENT ON TABLE "crm"."notes" IS 'Notes commerciales internes | Catalogue: Jamais publiées automatiquement sur le portail client.';

ALTER TABLE "crm"."notes" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "crm"."notes" FORCE ROW LEVEL SECURITY;

CREATE TRIGGER z_touch BEFORE UPDATE ON "crm"."notes" FOR EACH ROW EXECUTE FUNCTION infrastructure.touch_row();

ALTER TABLE "crm"."notes" ADD CONSTRAINT "c_44b126e6bc77d752cf19" CHECK (visibility = 'internal');

CREATE TABLE "crm"."campaigns" (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "name" text NOT NULL,
  "channel" text NOT NULL,
  "status" text NOT NULL,
  "starts_at" timestamptz,
  "ends_at" timestamptz,
  "budget" numeric(20,6),
  "currency" text,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  row_version bigint NOT NULL DEFAULT 1 CHECK(row_version>0)
);

COMMENT ON TABLE "crm"."campaigns" IS 'Actions marketing | Catalogue: Module ultérieur ; consentements et préférences avant envoi.';

ALTER TABLE "crm"."campaigns" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "crm"."campaigns" FORCE ROW LEVEL SECURITY;

CREATE TRIGGER z_touch BEFORE UPDATE ON "crm"."campaigns" FOR EACH ROW EXECUTE FUNCTION infrastructure.touch_row();

ALTER TABLE "crm"."campaigns" ADD CONSTRAINT "c_130e8f0820b688dbedbc" CHECK ("budget" <> 'NaN'::numeric);

ALTER TABLE "crm"."campaigns" ADD CONSTRAINT "c_b3460f089c24bd399dfc" CHECK ("currency" ~ '^[A-Z]{3}$');

ALTER TABLE "crm"."campaigns" ADD CONSTRAINT "c_0f69a53274cc4665ead4" CHECK ("ends_at" > "starts_at");

CREATE TABLE "crm"."campaign_recipients" (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "campaign_id" uuid NOT NULL,
  "person_id" uuid NOT NULL,
  "status" text NOT NULL,
  "responded_at" timestamptz,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  row_version bigint NOT NULL DEFAULT 1 CHECK(row_version>0)
);

COMMENT ON TABLE "crm"."campaign_recipients" IS 'Participation et résultat par contact | Catalogue: UNIQUE campagne + personne ; désinscription prise en compte.';

ALTER TABLE "crm"."campaign_recipients" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "crm"."campaign_recipients" FORCE ROW LEVEL SECURITY;

CREATE TRIGGER z_touch BEFORE UPDATE ON "crm"."campaign_recipients" FOR EACH ROW EXECUTE FUNCTION infrastructure.touch_row();

ALTER TABLE "crm"."campaign_recipients" ADD CONSTRAINT "c_2760a0874badb866d877" UNIQUE NULLS NOT DISTINCT ("campaign_id", "person_id");

CREATE TABLE "web"."pages" (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "slug" text NOT NULL,
  "locale" text NOT NULL,
  "status" text NOT NULL,
  "published_revision_id" uuid,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  row_version bigint NOT NULL DEFAULT 1 CHECK(row_version>0)
);

COMMENT ON TABLE "web"."pages" IS 'Pages du site | Catalogue: UNIQUE slug + langue ; publication explicite d’une révision.';

ALTER TABLE "web"."pages" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "web"."pages" FORCE ROW LEVEL SECURITY;

CREATE TRIGGER z_touch BEFORE UPDATE ON "web"."pages" FOR EACH ROW EXECUTE FUNCTION infrastructure.touch_row();

ALTER TABLE "web"."pages" ADD CONSTRAINT "c_c2554db3495a59bb58a7" UNIQUE NULLS NOT DISTINCT ("slug", "locale");

CREATE TABLE "web"."page_revisions" (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "page_id" uuid NOT NULL,
  "version_no" integer NOT NULL,
  "title" text NOT NULL,
  "body" jsonb NOT NULL,
  "seo" jsonb NOT NULL,
  "author_id" uuid NOT NULL,
  "published_at" timestamptz,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  row_version bigint NOT NULL DEFAULT 1 CHECK(row_version>0)
);

COMMENT ON TABLE "web"."page_revisions" IS 'Contenu éditorial versionné | Catalogue: UNIQUE page + version ; révision publiée appartenant à la même page.';

ALTER TABLE "web"."page_revisions" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "web"."page_revisions" FORCE ROW LEVEL SECURITY;

CREATE TRIGGER z_touch BEFORE UPDATE ON "web"."page_revisions" FOR EACH ROW EXECUTE FUNCTION infrastructure.touch_row();

CREATE TRIGGER a_published BEFORE UPDATE OR DELETE ON "web"."page_revisions" FOR EACH ROW EXECUTE FUNCTION infrastructure.freeze_published();

ALTER TABLE "web"."page_revisions" ADD CONSTRAINT "c_3ea8379095d6238373d4" CHECK ("version_no" > 0);

ALTER TABLE "web"."page_revisions" ADD CONSTRAINT "c_71169ecd2189e9afc1e2" UNIQUE NULLS NOT DISTINCT ("page_id", "version_no");

CREATE TABLE "web"."offers" (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "code" text NOT NULL,
  "title" text NOT NULL,
  "description" text NOT NULL,
  "status" text NOT NULL,
  "product_id" uuid,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  row_version bigint NOT NULL DEFAULT 1 CHECK(row_version>0)
);

COMMENT ON TABLE "web"."offers" IS 'Prestations visibles au public | Catalogue: Projection publique sans prix internes ni marge.';

ALTER TABLE "web"."offers" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "web"."offers" FORCE ROW LEVEL SECURITY;

CREATE TRIGGER z_touch BEFORE UPDATE ON "web"."offers" FOR EACH ROW EXECUTE FUNCTION infrastructure.touch_row();

ALTER TABLE "web"."offers" ADD CONSTRAINT "c_87845f09a383742668e1" UNIQUE NULLS NOT DISTINCT ("code");

CREATE TABLE "web"."portfolio_entries" (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "project_id" uuid,
  "slug" text NOT NULL,
  "title" text NOT NULL,
  "public_summary" text NOT NULL,
  "kind" text NOT NULL,
  "publication_status" text NOT NULL,
  "publication_authorized_at" timestamptz,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  row_version bigint NOT NULL DEFAULT 1 CHECK(row_version>0)
);

COMMENT ON TABLE "web"."portfolio_entries" IS 'Réalisations et concepts | Catalogue: Aucun héritage automatique des notes ou fichiers privés du projet.';

ALTER TABLE "web"."portfolio_entries" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "web"."portfolio_entries" FORCE ROW LEVEL SECURITY;

CREATE TRIGGER z_touch BEFORE UPDATE ON "web"."portfolio_entries" FOR EACH ROW EXECUTE FUNCTION infrastructure.touch_row();

ALTER TABLE "web"."portfolio_entries" ADD CONSTRAINT "c_98e2560b359b05d5441c" UNIQUE NULLS NOT DISTINCT ("slug");

CREATE TABLE "web"."contact_requests" (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "given_name" text NOT NULL,
  "family_name" text NOT NULL,
  "email" text NOT NULL,
  "phone" text,
  "company_text" text,
  "subject" text NOT NULL,
  "message" text NOT NULL,
  "budget_band" text,
  "requested_date" date,
  "source" text NOT NULL,
  "notice_version" text NOT NULL,
  "status" text NOT NULL,
  "received_at" timestamptz NOT NULL,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  row_version bigint NOT NULL DEFAULT 1 CHECK(row_version>0)
);

COMMENT ON TABLE "web"."contact_requests" IS 'Formulaires entrants | Catalogue: Soumission anonyme sans écrasement d’un contact connu ; déduplication contrôlée.';

ALTER TABLE "web"."contact_requests" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "web"."contact_requests" FORCE ROW LEVEL SECURITY;

CREATE TRIGGER z_touch BEFORE UPDATE ON "web"."contact_requests" FOR EACH ROW EXECUTE FUNCTION infrastructure.touch_row();

CREATE TABLE "web"."request_links" (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "request_id" uuid NOT NULL,
  "person_id" uuid,
  "organization_id" uuid,
  "lead_id" uuid,
  "ticket_id" uuid,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  row_version bigint NOT NULL DEFAULT 1 CHECK(row_version>0)
);

COMMENT ON TABLE "web"."request_links" IS 'Qualification d’une demande publique | Catalogue: Liens explicites après qualification ; aucune identité déduite du seul email.';

ALTER TABLE "web"."request_links" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "web"."request_links" FORCE ROW LEVEL SECURITY;

CREATE TRIGGER z_touch BEFORE UPDATE ON "web"."request_links" FOR EACH ROW EXECUTE FUNCTION infrastructure.touch_row();

ALTER TABLE "web"."request_links" ADD CONSTRAINT "c_9ebb4dfeecb31bcf9cea" CHECK (num_nonnulls(person_id,organization_id,lead_id,ticket_id)>=1);

CREATE TABLE "web"."request_files" (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "request_id" uuid NOT NULL,
  "file_id" uuid NOT NULL,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  row_version bigint NOT NULL DEFAULT 1 CHECK(row_version>0)
);

COMMENT ON TABLE "web"."request_files" IS 'Pièces d’une demande publique | Catalogue: Contrôle contenu, taille, quarantaine et expiration des dépôts abandonnés.';

ALTER TABLE "web"."request_files" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "web"."request_files" FORCE ROW LEVEL SECURITY;

CREATE TRIGGER z_touch BEFORE UPDATE ON "web"."request_files" FOR EACH ROW EXECUTE FUNCTION infrastructure.touch_row();

ALTER TABLE "web"."request_files" ADD CONSTRAINT "c_000f6eda033a5d59e506" UNIQUE NULLS NOT DISTINCT ("request_id", "file_id");

CREATE TABLE "web"."publication_media" (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "file_id" uuid NOT NULL,
  "page_revision_id" uuid,
  "portfolio_id" uuid,
  "alt_text" text NOT NULL,
  "publication_authorized_by" uuid NOT NULL,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  row_version bigint NOT NULL DEFAULT 1 CHECK(row_version>0)
);

COMMENT ON TABLE "web"."publication_media" IS 'Médias explicitement publiés | Catalogue: Exactement une cible ; copie ou zone publique distincte des pièces privées.';

ALTER TABLE "web"."publication_media" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "web"."publication_media" FORCE ROW LEVEL SECURITY;

CREATE TRIGGER z_touch BEFORE UPDATE ON "web"."publication_media" FOR EACH ROW EXECUTE FUNCTION infrastructure.touch_row();

ALTER TABLE "web"."publication_media" ADD CONSTRAINT "c_0449bbcf28b25b9884d7" CHECK (num_nonnulls(page_revision_id,portfolio_id)=1);

CREATE TABLE "web"."communication_preferences" (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "person_id" uuid NOT NULL,
  "channel" text NOT NULL,
  "purpose" text NOT NULL,
  "status" text NOT NULL,
  "evidence_ref" text,
  "recorded_at" timestamptz NOT NULL,
  "notice_version" text,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  row_version bigint NOT NULL DEFAULT 1 CHECK(row_version>0)
);

COMMENT ON TABLE "web"."communication_preferences" IS 'Préférences par finalité | Catalogue: Contact commercial entrant ne vaut pas abonnement marketing.';

ALTER TABLE "web"."communication_preferences" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "web"."communication_preferences" FORCE ROW LEVEL SECURITY;

CREATE TRIGGER z_touch BEFORE UPDATE ON "web"."communication_preferences" FOR EACH ROW EXECUTE FUNCTION infrastructure.touch_row();

ALTER TABLE "web"."communication_preferences" ADD CONSTRAINT "c_b3a77981245fc9e2dd3c" UNIQUE NULLS NOT DISTINCT ("person_id", "channel", "purpose");

CREATE TABLE "project"."projects" (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "code" text NOT NULL,
  "title" text NOT NULL,
  "description" text,
  "owner_organization_id" uuid NOT NULL,
  "customer_organization_id" uuid,
  "manager_id" uuid NOT NULL,
  "opportunity_id" uuid,
  "status" text NOT NULL,
  "start_on" date,
  "target_end_on" date,
  "closed_at" timestamptz,
  "progress_mode" text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  row_version bigint NOT NULL DEFAULT 1 CHECK(row_version>0)
);

COMMENT ON TABLE "project"."projects" IS 'Projets internes ou clients | Catalogue: Code unique ; avancement calculé ou saisi avec règle explicite.';

ALTER TABLE "project"."projects" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "project"."projects" FORCE ROW LEVEL SECURITY;

CREATE TRIGGER z_touch BEFORE UPDATE ON "project"."projects" FOR EACH ROW EXECUTE FUNCTION infrastructure.touch_row();

ALTER TABLE "project"."projects" ADD CONSTRAINT "c_66aa527dc301b716b6be" CHECK ("target_end_on" >= "start_on");

ALTER TABLE "project"."projects" ADD CONSTRAINT "c_d41faa03e6beb198adaf" UNIQUE NULLS NOT DISTINCT ("code");

CREATE TABLE "project"."project_parties" (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "project_id" uuid NOT NULL,
  "organization_id" uuid NOT NULL,
  "site_id" uuid,
  "role" text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  row_version bigint NOT NULL DEFAULT 1 CHECK(row_version>0)
);

COMMENT ON TABLE "project"."project_parties" IS 'Autres sociétés et sites concernés | Catalogue: Le lien n’accorde aucun accès automatique.';

ALTER TABLE "project"."project_parties" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "project"."project_parties" FORCE ROW LEVEL SECURITY;

CREATE TRIGGER z_touch BEFORE UPDATE ON "project"."project_parties" FOR EACH ROW EXECUTE FUNCTION infrastructure.touch_row();

ALTER TABLE "project"."project_parties" ADD CONSTRAINT "c_21e4cbd85ea1dbb90edc" UNIQUE NULLS NOT DISTINCT ("project_id", "organization_id", "site_id", "role");

CREATE TABLE "project"."memberships" (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "project_id" uuid NOT NULL,
  "person_id" uuid NOT NULL,
  "project_role" text NOT NULL,
  "starts_on" date NOT NULL,
  "ends_on" date,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  row_version bigint NOT NULL DEFAULT 1 CHECK(row_version>0)
);

COMMENT ON TABLE "project"."memberships" IS 'Participants et responsabilités | Catalogue: Droits évalués par IAM ; tâches modifiables séparément des données structurantes.';

ALTER TABLE "project"."memberships" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "project"."memberships" FORCE ROW LEVEL SECURITY;

CREATE TRIGGER z_touch BEFORE UPDATE ON "project"."memberships" FOR EACH ROW EXECUTE FUNCTION infrastructure.touch_row();

ALTER TABLE "project"."memberships" ADD CONSTRAINT "c_eee278735563539c6181" CHECK ("ends_on" >= "starts_on");

ALTER TABLE "project"."memberships" ADD CONSTRAINT "c_df5f73b498b917a16b40" UNIQUE NULLS NOT DISTINCT ("project_id", "person_id", "project_role", "starts_on");

CREATE TABLE "project"."phases" (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "project_id" uuid NOT NULL,
  "name" text NOT NULL,
  "position" integer NOT NULL,
  "status" text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  row_version bigint NOT NULL DEFAULT 1 CHECK(row_version>0)
);

COMMENT ON TABLE "project"."phases" IS 'Phases de réalisation | Catalogue: Ordre unique par projet si nécessaire.';

ALTER TABLE "project"."phases" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "project"."phases" FORCE ROW LEVEL SECURITY;

CREATE TRIGGER z_touch BEFORE UPDATE ON "project"."phases" FOR EACH ROW EXECUTE FUNCTION infrastructure.touch_row();

ALTER TABLE "project"."phases" ADD CONSTRAINT "c_9cac4d4d6d75bed9f91e" UNIQUE NULLS NOT DISTINCT ("project_id", "position");

CREATE TABLE "project"."milestones" (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "project_id" uuid NOT NULL,
  "phase_id" uuid,
  "title" text NOT NULL,
  "due_on" date NOT NULL,
  "achieved_at" timestamptz,
  "acceptance_required" boolean NOT NULL,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  row_version bigint NOT NULL DEFAULT 1 CHECK(row_version>0)
);

COMMENT ON TABLE "project"."milestones" IS 'Jalons et engagements | Catalogue: Phase dans le même projet.';

ALTER TABLE "project"."milestones" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "project"."milestones" FORCE ROW LEVEL SECURITY;

CREATE TRIGGER z_touch BEFORE UPDATE ON "project"."milestones" FOR EACH ROW EXECUTE FUNCTION infrastructure.touch_row();

CREATE TABLE "project"."tasks" (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "project_id" uuid NOT NULL,
  "phase_id" uuid,
  "parent_id" uuid,
  "title" text NOT NULL,
  "description" text,
  "status" text NOT NULL,
  "priority" text NOT NULL,
  "planned_minutes" integer,
  "start_at" timestamptz,
  "due_at" timestamptz,
  "done_at" timestamptz,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  row_version bigint NOT NULL DEFAULT 1 CHECK(row_version>0)
);

COMMENT ON TABLE "project"."tasks" IS 'Travail de réalisation | Catalogue: Parent dans le même projet ; cycles interdits ; durée positive.';

ALTER TABLE "project"."tasks" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "project"."tasks" FORCE ROW LEVEL SECURITY;

CREATE TRIGGER z_touch BEFORE UPDATE ON "project"."tasks" FOR EACH ROW EXECUTE FUNCTION infrastructure.touch_row();

ALTER TABLE "project"."tasks" ADD CONSTRAINT "c_3fcdf546b753dd939dfe" CHECK ("parent_id" <> id);

ALTER TABLE "project"."tasks" ADD CONSTRAINT "c_1961d5eb66dc591d8a29" CHECK ("planned_minutes" >= 0);

CREATE TABLE "project"."task_assignees" (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "task_id" uuid NOT NULL,
  "person_id" uuid NOT NULL,
  "allocation_percent" numeric(20,6) NOT NULL,
  "role" text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  row_version bigint NOT NULL DEFAULT 1 CHECK(row_version>0)
);

COMMENT ON TABLE "project"."task_assignees" IS 'Affectations des tâches | Catalogue: Pas de liste de personnes dans une cellule ; allocation contrôlée.';

ALTER TABLE "project"."task_assignees" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "project"."task_assignees" FORCE ROW LEVEL SECURITY;

CREATE TRIGGER z_touch BEFORE UPDATE ON "project"."task_assignees" FOR EACH ROW EXECUTE FUNCTION infrastructure.touch_row();

ALTER TABLE "project"."task_assignees" ADD CONSTRAINT "c_63940690efd35108d4f2" CHECK ("allocation_percent" <> 'NaN'::numeric);

ALTER TABLE "project"."task_assignees" ADD CONSTRAINT "c_a798e19fec6e3e26ed3d" CHECK ("allocation_percent" > 0 AND "allocation_percent" <= 100);

ALTER TABLE "project"."task_assignees" ADD CONSTRAINT "c_05ce9c26dd75611b2fd4" UNIQUE NULLS NOT DISTINCT ("task_id", "person_id", "role");

CREATE TABLE "project"."task_dependencies" (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "predecessor_id" uuid NOT NULL,
  "successor_id" uuid NOT NULL,
  "dependency_type" text NOT NULL,
  "lag_minutes" integer NOT NULL,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  row_version bigint NOT NULL DEFAULT 1 CHECK(row_version>0)
);

COMMENT ON TABLE "project"."task_dependencies" IS 'Dépendances du planning | Catalogue: Graphe sans cycle ; dépendances entre projets seulement si autorisées.';

ALTER TABLE "project"."task_dependencies" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "project"."task_dependencies" FORCE ROW LEVEL SECURITY;

CREATE TRIGGER z_touch BEFORE UPDATE ON "project"."task_dependencies" FOR EACH ROW EXECUTE FUNCTION infrastructure.touch_row();

ALTER TABLE "project"."task_dependencies" ADD CONSTRAINT "c_f31554255cf1ff79cd3c" CHECK (predecessor_id <> successor_id);

ALTER TABLE "project"."task_dependencies" ADD CONSTRAINT "c_2b874e2d03c4ceac1af2" UNIQUE NULLS NOT DISTINCT ("predecessor_id", "successor_id", "dependency_type");

CREATE TABLE "project"."resource_demands" (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "project_id" uuid NOT NULL,
  "task_id" uuid,
  "person_id" uuid,
  "skill_id" uuid,
  "starts_on" date NOT NULL,
  "ends_on" date NOT NULL,
  "planned_minutes" integer NOT NULL,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  row_version bigint NOT NULL DEFAULT 1 CHECK(row_version>0)
);

COMMENT ON TABLE "project"."resource_demands" IS 'Charge prévue par période | Catalogue: Charge estimée distincte d’une réservation ferme ; ne pas compter les deux deux fois.';

ALTER TABLE "project"."resource_demands" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "project"."resource_demands" FORCE ROW LEVEL SECURITY;

CREATE TRIGGER z_touch BEFORE UPDATE ON "project"."resource_demands" FOR EACH ROW EXECUTE FUNCTION infrastructure.touch_row();

ALTER TABLE "project"."resource_demands" ADD CONSTRAINT "c_444d6592622e48f1cc4a" CHECK ("planned_minutes" >= 0);

ALTER TABLE "project"."resource_demands" ADD CONSTRAINT "c_f49c585b739259387364" CHECK ("ends_on" >= "starts_on");

CREATE TABLE "project"."baselines" (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "project_id" uuid NOT NULL,
  "version_no" integer NOT NULL,
  "snapshot" jsonb NOT NULL,
  "approved_by" uuid NOT NULL,
  "approved_at" timestamptz NOT NULL,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  row_version bigint NOT NULL DEFAULT 1 CHECK(row_version>0)
);

COMMENT ON TABLE "project"."baselines" IS 'Photographies du planning approuvé | Catalogue: Version immuable ; comparaison du prévu et du réalisé.';

ALTER TABLE "project"."baselines" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "project"."baselines" FORCE ROW LEVEL SECURITY;

CREATE TRIGGER z_touch BEFORE UPDATE ON "project"."baselines" FOR EACH ROW EXECUTE FUNCTION infrastructure.touch_row();

CREATE TRIGGER a_immutable BEFORE UPDATE OR DELETE ON "project"."baselines" FOR EACH ROW EXECUTE FUNCTION infrastructure.reject_mutation();
CREATE TRIGGER a_no_truncate BEFORE TRUNCATE ON "project"."baselines" FOR EACH STATEMENT EXECUTE FUNCTION infrastructure.reject_mutation();

ALTER TABLE "project"."baselines" ADD CONSTRAINT "c_86fd094fb56fdaba6eaf" CHECK ("version_no" > 0);

ALTER TABLE "project"."baselines" ADD CONSTRAINT "c_cae2b12117c5da2aecc7" UNIQUE NULLS NOT DISTINCT ("project_id", "version_no");

CREATE TABLE "project"."risks" (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "project_id" uuid NOT NULL,
  "title" text NOT NULL,
  "probability" numeric(20,6) NOT NULL,
  "impact" text NOT NULL,
  "owner_id" uuid NOT NULL,
  "mitigation" text,
  "status" text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  row_version bigint NOT NULL DEFAULT 1 CHECK(row_version>0)
);

COMMENT ON TABLE "project"."risks" IS 'Risques et actions de traitement | Catalogue: Probabilité encadrée ; suivi des décisions.';

ALTER TABLE "project"."risks" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "project"."risks" FORCE ROW LEVEL SECURITY;

CREATE TRIGGER z_touch BEFORE UPDATE ON "project"."risks" FOR EACH ROW EXECUTE FUNCTION infrastructure.touch_row();

ALTER TABLE "project"."risks" ADD CONSTRAINT "c_c15373cd14791b67d99b" CHECK ("probability" <> 'NaN'::numeric);

ALTER TABLE "project"."risks" ADD CONSTRAINT "c_23de99d8fe494f7df880" CHECK ("probability" BETWEEN 0 AND 1);

CREATE TABLE "project"."decisions" (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "project_id" uuid NOT NULL,
  "title" text NOT NULL,
  "decision" text NOT NULL,
  "decided_by" uuid NOT NULL,
  "decided_at" timestamptz NOT NULL,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  row_version bigint NOT NULL DEFAULT 1 CHECK(row_version>0)
);

COMMENT ON TABLE "project"."decisions" IS 'Décisions de projet | Catalogue: Historique des corrections ; auteur conservé.';

ALTER TABLE "project"."decisions" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "project"."decisions" FORCE ROW LEVEL SECURITY;

CREATE TRIGGER z_touch BEFORE UPDATE ON "project"."decisions" FOR EACH ROW EXECUTE FUNCTION infrastructure.touch_row();

CREATE TRIGGER a_immutable BEFORE UPDATE OR DELETE ON "project"."decisions" FOR EACH ROW EXECUTE FUNCTION infrastructure.reject_mutation();
CREATE TRIGGER a_no_truncate BEFORE TRUNCATE ON "project"."decisions" FOR EACH STATEMENT EXECUTE FUNCTION infrastructure.reject_mutation();

CREATE TABLE "project"."deliverables" (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "project_id" uuid NOT NULL,
  "milestone_id" uuid,
  "title" text NOT NULL,
  "file_id" uuid,
  "status" text NOT NULL,
  "delivered_at" timestamptz,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  row_version bigint NOT NULL DEFAULT 1 CHECK(row_version>0)
);

COMMENT ON TABLE "project"."deliverables" IS 'Livrables attendus | Catalogue: Livrable documentaire facultatif ; version du fichier figée pour réception.';

ALTER TABLE "project"."deliverables" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "project"."deliverables" FORCE ROW LEVEL SECURITY;

CREATE TRIGGER z_touch BEFORE UPDATE ON "project"."deliverables" FOR EACH ROW EXECUTE FUNCTION infrastructure.touch_row();

CREATE TABLE "project"."acceptances" (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "deliverable_id" uuid NOT NULL,
  "reviewer_affiliation_id" uuid NOT NULL,
  "decision" text NOT NULL,
  "comment" text,
  "decided_at" timestamptz NOT NULL,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  row_version bigint NOT NULL DEFAULT 1 CHECK(row_version>0)
);

COMMENT ON TABLE "project"."acceptances" IS 'Recettes et réserves | Catalogue: Refus, accepté, accepté avec réserves distingués.';

ALTER TABLE "project"."acceptances" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "project"."acceptances" FORCE ROW LEVEL SECURITY;

CREATE TRIGGER z_touch BEFORE UPDATE ON "project"."acceptances" FOR EACH ROW EXECUTE FUNCTION infrastructure.touch_row();

CREATE TRIGGER a_immutable BEFORE UPDATE OR DELETE ON "project"."acceptances" FOR EACH ROW EXECUTE FUNCTION infrastructure.reject_mutation();
CREATE TRIGGER a_no_truncate BEFORE TRUNCATE ON "project"."acceptances" FOR EACH STATEMENT EXECUTE FUNCTION infrastructure.reject_mutation();

CREATE TABLE "project"."budget_lines" (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "project_id" uuid NOT NULL,
  "kind" text NOT NULL,
  "description" text NOT NULL,
  "planned_amount" numeric(20,6) NOT NULL,
  "currency" text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  row_version bigint NOT NULL DEFAULT 1 CHECK(row_version>0)
);

COMMENT ON TABLE "project"."budget_lines" IS 'Budget et coûts prévus | Catalogue: Coûts réels issus des temps, dépenses et achats, sans duplication de saisie.';

ALTER TABLE "project"."budget_lines" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "project"."budget_lines" FORCE ROW LEVEL SECURITY;

CREATE TRIGGER z_touch BEFORE UPDATE ON "project"."budget_lines" FOR EACH ROW EXECUTE FUNCTION infrastructure.touch_row();

ALTER TABLE "project"."budget_lines" ADD CONSTRAINT "c_18a734061bdec76f81c1" CHECK ("planned_amount" <> 'NaN'::numeric);

ALTER TABLE "project"."budget_lines" ADD CONSTRAINT "c_d98c8999761bc45a0d09" CHECK ("currency" ~ '^[A-Z]{3}$');

CREATE TABLE "people"."employment_records" (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "person_id" uuid NOT NULL,
  "employer_id" uuid NOT NULL,
  "employee_number" text NOT NULL,
  "engagement_kind" text NOT NULL,
  "starts_on" date NOT NULL,
  "ends_on" date,
  "manager_id" uuid,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  row_version bigint NOT NULL DEFAULT 1 CHECK(row_version>0)
);

COMMENT ON TABLE "people"."employment_records" IS 'Relation de travail avec l’entreprise | Catalogue: Historiser employeur, statut, équipe et manager ; données RH minimales utiles.';

ALTER TABLE "people"."employment_records" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "people"."employment_records" FORCE ROW LEVEL SECURITY;

CREATE TRIGGER z_touch BEFORE UPDATE ON "people"."employment_records" FOR EACH ROW EXECUTE FUNCTION infrastructure.touch_row();

ALTER TABLE "people"."employment_records" ADD CONSTRAINT "c_09b97ecef5c06c880780" CHECK ("ends_on" >= "starts_on");

ALTER TABLE "people"."employment_records" ADD CONSTRAINT "c_0e30fc0ad0471715cc9d" UNIQUE NULLS NOT DISTINCT ("employer_id", "employee_number");

CREATE TABLE "people"."working_patterns" (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "name" text NOT NULL,
  "timezone" text NOT NULL,
  "weekly_minutes" integer NOT NULL,
  "calendar_id" uuid NOT NULL,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  row_version bigint NOT NULL DEFAULT 1 CHECK(row_version>0)
);

COMMENT ON TABLE "people"."working_patterns" IS 'Horaires de travail de référence | Catalogue: Référence datée ; horaires contractuels distincts d’un pointage réel.';

ALTER TABLE "people"."working_patterns" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "people"."working_patterns" FORCE ROW LEVEL SECURITY;

CREATE TRIGGER z_touch BEFORE UPDATE ON "people"."working_patterns" FOR EACH ROW EXECUTE FUNCTION infrastructure.touch_row();

ALTER TABLE "people"."working_patterns" ADD CONSTRAINT "c_e5fc765241700971ed1a" CHECK ("weekly_minutes" >= 0);

CREATE TABLE "people"."working_pattern_slots" (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "pattern_id" uuid NOT NULL,
  "weekday" integer NOT NULL,
  "start_local" time NOT NULL,
  "end_local" time NOT NULL,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  row_version bigint NOT NULL DEFAULT 1 CHECK(row_version>0)
);

COMMENT ON TABLE "people"."working_pattern_slots" IS 'Plages hebdomadaires de travail | Catalogue: Jour 1 à 7 ; plage non vide ; découper les plages nocturnes à minuit.';

ALTER TABLE "people"."working_pattern_slots" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "people"."working_pattern_slots" FORCE ROW LEVEL SECURITY;

CREATE TRIGGER z_touch BEFORE UPDATE ON "people"."working_pattern_slots" FOR EACH ROW EXECUTE FUNCTION infrastructure.touch_row();

ALTER TABLE "people"."working_pattern_slots" ADD CONSTRAINT "c_25d99b9a2da2ae525364" CHECK ("weekday" BETWEEN 1 AND 7);

ALTER TABLE "people"."working_pattern_slots" ADD CONSTRAINT "c_3f55b1a6e08400ff1c94" CHECK ("end_local" > "start_local");

CREATE TABLE "people"."employment_patterns" (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "employment_id" uuid NOT NULL,
  "pattern_id" uuid NOT NULL,
  "valid_from" date NOT NULL,
  "valid_to" date,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  row_version bigint NOT NULL DEFAULT 1 CHECK(row_version>0)
);

COMMENT ON TABLE "people"."employment_patterns" IS 'Affectation d’un régime horaire | Catalogue: Une seule règle principale applicable à un instant donné.';

ALTER TABLE "people"."employment_patterns" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "people"."employment_patterns" FORCE ROW LEVEL SECURITY;

CREATE TRIGGER z_touch BEFORE UPDATE ON "people"."employment_patterns" FOR EACH ROW EXECUTE FUNCTION infrastructure.touch_row();

ALTER TABLE "people"."employment_patterns" ADD CONSTRAINT "c_58964540a3ba3a2b9958" CHECK ("valid_to" >= "valid_from");

CREATE TABLE "people"."leave_types" (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "code" text NOT NULL,
  "label" text NOT NULL,
  "requires_approval" boolean NOT NULL,
  "balance_tracked" boolean NOT NULL,
  "restricted_reason" boolean NOT NULL,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  row_version bigint NOT NULL DEFAULT 1 CHECK(row_version>0)
);

COMMENT ON TABLE "people"."leave_types" IS 'Types d’absence paramétrables | Catalogue: Règles configurables ; aucun régime juridique présumé.';

ALTER TABLE "people"."leave_types" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "people"."leave_types" FORCE ROW LEVEL SECURITY;

CREATE TRIGGER z_touch BEFORE UPDATE ON "people"."leave_types" FOR EACH ROW EXECUTE FUNCTION infrastructure.touch_row();

ALTER TABLE "people"."leave_types" ADD CONSTRAINT "c_9ae790024c1bebad3cd7" UNIQUE NULLS NOT DISTINCT ("code");

CREATE TABLE "people"."leave_requests" (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "employment_id" uuid NOT NULL,
  "leave_type_id" uuid NOT NULL,
  "starts_at" timestamptz NOT NULL,
  "ends_at" timestamptz NOT NULL,
  "status" text NOT NULL,
  "reviewer_id" uuid,
  "decided_at" timestamptz,
  "private_note" text,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  row_version bigint NOT NULL DEFAULT 1 CHECK(row_version>0)
);

COMMENT ON TABLE "people"."leave_requests" IS 'Demandes d’absence et validation | Catalogue: Date de fin après début ; absence validée produit indisponibilité ; note RH non exportée à ITSM.';

ALTER TABLE "people"."leave_requests" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "people"."leave_requests" FORCE ROW LEVEL SECURITY;

CREATE TRIGGER z_touch BEFORE UPDATE ON "people"."leave_requests" FOR EACH ROW EXECUTE FUNCTION infrastructure.touch_row();

ALTER TABLE "people"."leave_requests" ADD CONSTRAINT "c_9393bee3ab8f09599e1a" CHECK ("ends_at" > "starts_at");

CREATE TABLE "people"."leave_ledger" (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "employment_id" uuid NOT NULL,
  "leave_type_id" uuid NOT NULL,
  "request_id" uuid,
  "quantity" numeric(20,6) NOT NULL,
  "unit" text NOT NULL,
  "effective_on" date NOT NULL,
  "reason" text NOT NULL,
  "reversal_of_id" uuid,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  row_version bigint NOT NULL DEFAULT 1 CHECK(row_version>0)
);

COMMENT ON TABLE "people"."leave_ledger" IS 'Mouvements de solde d’absence | Catalogue: Solde dérivé d’un journal ; corrections par compensation ; unité explicite.';

ALTER TABLE "people"."leave_ledger" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "people"."leave_ledger" FORCE ROW LEVEL SECURITY;

CREATE TRIGGER z_touch BEFORE UPDATE ON "people"."leave_ledger" FOR EACH ROW EXECUTE FUNCTION infrastructure.touch_row();

CREATE TRIGGER a_immutable BEFORE UPDATE OR DELETE ON "people"."leave_ledger" FOR EACH ROW EXECUTE FUNCTION infrastructure.reject_mutation();
CREATE TRIGGER a_no_truncate BEFORE TRUNCATE ON "people"."leave_ledger" FOR EACH STATEMENT EXECUTE FUNCTION infrastructure.reject_mutation();

ALTER TABLE "people"."leave_ledger" ADD CONSTRAINT "c_1ddc7d2611e3b91da57f" CHECK ("quantity" <> 'NaN'::numeric);

ALTER TABLE "people"."leave_ledger" ADD CONSTRAINT "c_ddca5ead63dd379c30eb" CHECK ("reversal_of_id" <> id);

CREATE TABLE "people"."attendance_events" (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "employment_id" uuid NOT NULL,
  "occurred_at" timestamptz NOT NULL,
  "event_type" text NOT NULL,
  "source" text NOT NULL,
  "correction_of_id" uuid,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  row_version bigint NOT NULL DEFAULT 1 CHECK(row_version>0)
);

COMMENT ON TABLE "people"."attendance_events" IS 'Présences réellement constatées | Catalogue: Ne pas confondre avec un temps facturable ni déduire une surveillance continue.';

ALTER TABLE "people"."attendance_events" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "people"."attendance_events" FORCE ROW LEVEL SECURITY;

CREATE TRIGGER z_touch BEFORE UPDATE ON "people"."attendance_events" FOR EACH ROW EXECUTE FUNCTION infrastructure.touch_row();

CREATE TRIGGER a_immutable BEFORE UPDATE OR DELETE ON "people"."attendance_events" FOR EACH ROW EXECUTE FUNCTION infrastructure.reject_mutation();
CREATE TRIGGER a_no_truncate BEFORE TRUNCATE ON "people"."attendance_events" FOR EACH STATEMENT EXECUTE FUNCTION infrastructure.reject_mutation();

ALTER TABLE "people"."attendance_events" ADD CONSTRAINT "c_ca580c3162775de56bdf" CHECK ("correction_of_id" <> id);

CREATE TABLE "people"."work_locations" (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "employment_id" uuid NOT NULL,
  "starts_at" timestamptz NOT NULL,
  "ends_at" timestamptz NOT NULL,
  "mode" text NOT NULL,
  "site_id" uuid,
  "label" text,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  row_version bigint NOT NULL DEFAULT 1 CHECK(row_version>0)
);

COMMENT ON TABLE "people"."work_locations" IS 'Lieu déclaré de travail | Catalogue: Site, télétravail, déplacement ; pas de géolocalisation précise permanente.';

ALTER TABLE "people"."work_locations" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "people"."work_locations" FORCE ROW LEVEL SECURITY;

CREATE TRIGGER z_touch BEFORE UPDATE ON "people"."work_locations" FOR EACH ROW EXECUTE FUNCTION infrastructure.touch_row();

ALTER TABLE "people"."work_locations" ADD CONSTRAINT "c_beebbcd0cb646eb18a52" CHECK ("ends_at" > "starts_at");

CREATE TABLE "people"."skills" (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "code" text NOT NULL,
  "label" text NOT NULL,
  "category" text,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  row_version bigint NOT NULL DEFAULT 1 CHECK(row_version>0)
);

COMMENT ON TABLE "people"."skills" IS 'Compétences professionnelles | Catalogue: Référentiel partageable pour affecter les interventions.';

ALTER TABLE "people"."skills" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "people"."skills" FORCE ROW LEVEL SECURITY;

CREATE TRIGGER z_touch BEFORE UPDATE ON "people"."skills" FOR EACH ROW EXECUTE FUNCTION infrastructure.touch_row();

ALTER TABLE "people"."skills" ADD CONSTRAINT "c_c0809915ed154b57aa89" UNIQUE NULLS NOT DISTINCT ("code");

CREATE TABLE "people"."person_skills" (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "person_id" uuid NOT NULL,
  "skill_id" uuid NOT NULL,
  "level" text NOT NULL,
  "valid_until" date,
  "verified_by" uuid,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  row_version bigint NOT NULL DEFAULT 1 CHECK(row_version>0)
);

COMMENT ON TABLE "people"."person_skills" IS 'Compétences et habilitations techniques | Catalogue: Une compétence n’est pas une permission applicative.';

ALTER TABLE "people"."person_skills" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "people"."person_skills" FORCE ROW LEVEL SECURITY;

CREATE TRIGGER z_touch BEFORE UPDATE ON "people"."person_skills" FOR EACH ROW EXECUTE FUNCTION infrastructure.touch_row();

ALTER TABLE "people"."person_skills" ADD CONSTRAINT "c_8c30eb927fc684d78e15" UNIQUE NULLS NOT DISTINCT ("person_id", "skill_id");

CREATE TABLE "people"."certifications" (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "person_id" uuid NOT NULL,
  "name" text NOT NULL,
  "issuer" text NOT NULL,
  "obtained_on" date NOT NULL,
  "expires_on" date,
  "document_id" uuid,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  row_version bigint NOT NULL DEFAULT 1 CHECK(row_version>0)
);

COMMENT ON TABLE "people"."certifications" IS 'Certifications et justificatifs | Catalogue: Visibilité limitée ; alertes d’expiration configurables.';

ALTER TABLE "people"."certifications" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "people"."certifications" FORCE ROW LEVEL SECURITY;

CREATE TRIGGER z_touch BEFORE UPDATE ON "people"."certifications" FOR EACH ROW EXECUTE FUNCTION infrastructure.touch_row();

CREATE TABLE "schedule"."business_calendars" (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "code" text NOT NULL,
  "name" text NOT NULL,
  "timezone" text NOT NULL,
  "version_no" integer NOT NULL,
  "valid_from" date NOT NULL,
  "valid_to" date,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  row_version bigint NOT NULL DEFAULT 1 CHECK(row_version>0)
);

COMMENT ON TABLE "schedule"."business_calendars" IS 'Calendriers ouvrés versionnés | Catalogue: Distinct du planning personnel ; timezone IANA conservée.';

ALTER TABLE "schedule"."business_calendars" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "schedule"."business_calendars" FORCE ROW LEVEL SECURITY;

CREATE TRIGGER z_touch BEFORE UPDATE ON "schedule"."business_calendars" FOR EACH ROW EXECUTE FUNCTION infrastructure.touch_row();

ALTER TABLE "schedule"."business_calendars" ADD CONSTRAINT "c_048483683af3a85b5144" CHECK ("version_no" > 0);

ALTER TABLE "schedule"."business_calendars" ADD CONSTRAINT "c_a8595eaffed394c140e0" CHECK ("valid_to" >= "valid_from");

ALTER TABLE "schedule"."business_calendars" ADD CONSTRAINT "c_64921bc25a24c7157b3e" UNIQUE NULLS NOT DISTINCT ("code", "version_no");

CREATE TABLE "schedule"."calendar_slots" (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "calendar_id" uuid NOT NULL,
  "weekday" integer NOT NULL,
  "start_local" time NOT NULL,
  "end_local" time NOT NULL,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  row_version bigint NOT NULL DEFAULT 1 CHECK(row_version>0)
);

COMMENT ON TABLE "schedule"."calendar_slots" IS 'Heures d’ouverture habituelles | Catalogue: Exclure les plages vides ; jours fériés via exceptions.';

ALTER TABLE "schedule"."calendar_slots" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "schedule"."calendar_slots" FORCE ROW LEVEL SECURITY;

CREATE TRIGGER z_touch BEFORE UPDATE ON "schedule"."calendar_slots" FOR EACH ROW EXECUTE FUNCTION infrastructure.touch_row();

ALTER TABLE "schedule"."calendar_slots" ADD CONSTRAINT "c_5f5bc17fbe92a919246f" CHECK ("weekday" BETWEEN 1 AND 7);

ALTER TABLE "schedule"."calendar_slots" ADD CONSTRAINT "c_fea81ccc110827bbce54" CHECK ("end_local" > "start_local");

CREATE TABLE "schedule"."calendar_exceptions" (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "calendar_id" uuid NOT NULL,
  "local_date" date NOT NULL,
  "is_open" boolean NOT NULL,
  "start_local" time,
  "end_local" time,
  "reason" text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  row_version bigint NOT NULL DEFAULT 1 CHECK(row_version>0)
);

COMMENT ON TABLE "schedule"."calendar_exceptions" IS 'Jours fériés et ouvertures exceptionnelles | Catalogue: Peut représenter un jour fermé ou une ouverture partielle.';

ALTER TABLE "schedule"."calendar_exceptions" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "schedule"."calendar_exceptions" FORCE ROW LEVEL SECURITY;

CREATE TRIGGER z_touch BEFORE UPDATE ON "schedule"."calendar_exceptions" FOR EACH ROW EXECUTE FUNCTION infrastructure.touch_row();

ALTER TABLE "schedule"."calendar_exceptions" ADD CONSTRAINT "c_d74ae202ab028ea364cc" CHECK ((NOT is_open AND start_local IS NULL AND end_local IS NULL) OR (is_open AND start_local IS NOT NULL AND end_local IS NOT NULL AND end_local > start_local));

ALTER TABLE "schedule"."calendar_exceptions" ADD CONSTRAINT "c_d3a01bf2134433c0e26c" CHECK ("end_local" > "start_local");

CREATE TABLE "schedule"."resources" (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "kind" text NOT NULL,
  "person_id" uuid,
  "asset_id" uuid,
  "name" text NOT NULL,
  "capacity" integer NOT NULL,
  "timezone" text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  row_version bigint NOT NULL DEFAULT 1 CHECK(row_version>0)
);

COMMENT ON TABLE "schedule"."resources" IS 'Ressources réservables | Catalogue: Exactement une référence selon kind ; ressources humaines à capacité 1 pour réservations exclusives.';

ALTER TABLE "schedule"."resources" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "schedule"."resources" FORCE ROW LEVEL SECURITY;

CREATE TRIGGER z_touch BEFORE UPDATE ON "schedule"."resources" FOR EACH ROW EXECUTE FUNCTION infrastructure.touch_row();

ALTER TABLE "schedule"."resources" ADD CONSTRAINT "c_70d790e1e28c975ce57c" CHECK ((kind='person' AND person_id IS NOT NULL AND asset_id IS NULL AND capacity=1) OR (kind='asset' AND asset_id IS NOT NULL AND person_id IS NULL) OR (kind='pool' AND person_id IS NULL AND asset_id IS NULL));

ALTER TABLE "schedule"."resources" ADD CONSTRAINT "c_a66f8738eb177001401e" CHECK (capacity > 0);

CREATE TABLE "schedule"."availability_blocks" (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "resource_id" uuid NOT NULL,
  "starts_at" timestamptz NOT NULL,
  "ends_at" timestamptz NOT NULL,
  "kind" text NOT NULL,
  "source_system" text NOT NULL,
  "external_source_key" text,
  "source_version" text NOT NULL,
  "fresh_until" timestamptz,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  row_version bigint NOT NULL DEFAULT 1 CHECK(row_version>0)
);

COMMENT ON TABLE "schedule"."availability_blocks" IS 'Indisponibilités ou capacités publiées | Catalogue: Source idempotente ; uniquement disponibilité, sans motif médical ou détail de congé dans ITSM.';

ALTER TABLE "schedule"."availability_blocks" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "schedule"."availability_blocks" FORCE ROW LEVEL SECURITY;

CREATE TRIGGER z_touch BEFORE UPDATE ON "schedule"."availability_blocks" FOR EACH ROW EXECUTE FUNCTION infrastructure.touch_row();

ALTER TABLE "schedule"."availability_blocks" ADD CONSTRAINT "c_465b802f1b2323c4cb95" CHECK ("ends_at" > "starts_at");

CREATE TABLE "schedule"."bookings" (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "resource_id" uuid NOT NULL,
  "starts_at" timestamptz NOT NULL,
  "ends_at" timestamptz NOT NULL,
  "status" text NOT NULL,
  "activity_type" text NOT NULL,
  "location_mode" text NOT NULL,
  "site_id" uuid,
  "project_task_id" uuid,
  "intervention_id" uuid,
  "crm_activity_id" uuid,
  "external_work_ref" text,
  "exclusive" boolean NOT NULL,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  row_version bigint NOT NULL DEFAULT 1 CHECK(row_version>0)
);

COMMENT ON TABLE "schedule"."bookings" IS 'Créneaux réservés | Catalogue: Une cible métier ou référence externe au maximum ; réservation ferme atomique contre les conflits.';

ALTER TABLE "schedule"."bookings" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "schedule"."bookings" FORCE ROW LEVEL SECURITY;

CREATE TRIGGER z_touch BEFORE UPDATE ON "schedule"."bookings" FOR EACH ROW EXECUTE FUNCTION infrastructure.touch_row();

ALTER TABLE "schedule"."bookings" ADD CONSTRAINT "c_6e1e2220a3509ccb972f" CHECK (num_nonnulls(project_task_id,intervention_id,crm_activity_id,external_work_ref)<=1);

ALTER TABLE "schedule"."bookings" ADD CONSTRAINT "c_09a79a9b37c7501f367b" CHECK (status IN ('tentative','confirmed','cancelled','completed'));

ALTER TABLE "schedule"."bookings" ADD CONSTRAINT "c_ab57092c5296d7935b08" CHECK ("ends_at" > "starts_at");

CREATE TABLE "schedule"."booking_events" (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "booking_id" uuid NOT NULL,
  "event_type" text NOT NULL,
  "actor_id" uuid NOT NULL,
  "occurred_at" timestamptz NOT NULL,
  "reason" text,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  row_version bigint NOT NULL DEFAULT 1 CHECK(row_version>0)
);

COMMENT ON TABLE "schedule"."booking_events" IS 'Historique de réservation | Catalogue: Toute annulation ou dérogation visible et justifiée.';

ALTER TABLE "schedule"."booking_events" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "schedule"."booking_events" FORCE ROW LEVEL SECURITY;

CREATE TRIGGER z_touch BEFORE UPDATE ON "schedule"."booking_events" FOR EACH ROW EXECUTE FUNCTION infrastructure.touch_row();

CREATE TRIGGER a_immutable BEFORE UPDATE OR DELETE ON "schedule"."booking_events" FOR EACH ROW EXECUTE FUNCTION infrastructure.reject_mutation();
CREATE TRIGGER a_no_truncate BEFORE TRUNCATE ON "schedule"."booking_events" FOR EACH STATEMENT EXECUTE FUNCTION infrastructure.reject_mutation();

CREATE TABLE "schedule"."recurrence_rules" (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "resource_id" uuid NOT NULL,
  "rule" text NOT NULL,
  "timezone" text NOT NULL,
  "starts_on" date NOT NULL,
  "ends_on" date,
  "template" jsonb NOT NULL,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  row_version bigint NOT NULL DEFAULT 1 CHECK(row_version>0)
);

COMMENT ON TABLE "schedule"."recurrence_rules" IS 'Séries de créneaux | Catalogue: Instances matérialisées sur horizon borné ; exceptions gérées individuellement.';

ALTER TABLE "schedule"."recurrence_rules" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "schedule"."recurrence_rules" FORCE ROW LEVEL SECURITY;

CREATE TRIGGER z_touch BEFORE UPDATE ON "schedule"."recurrence_rules" FOR EACH ROW EXECUTE FUNCTION infrastructure.touch_row();

ALTER TABLE "schedule"."recurrence_rules" ADD CONSTRAINT "c_55a489eff2a4f5d22673" CHECK ("ends_on" >= "starts_on");

CREATE TABLE "schedule"."calendar_connections" (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "integration_id" uuid NOT NULL,
  "resource_id" uuid NOT NULL,
  "external_calendar_key" text NOT NULL,
  "sync_cursor" text,
  "mode" text NOT NULL,
  "last_success_at" timestamptz,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  row_version bigint NOT NULL DEFAULT 1 CHECK(row_version>0)
);

COMMENT ON TABLE "schedule"."calendar_connections" IS 'Connexions au portail ou agenda externe | Catalogue: Ne pas réserver directement dans une copie périmée ; confirmation par le service source.';

ALTER TABLE "schedule"."calendar_connections" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "schedule"."calendar_connections" FORCE ROW LEVEL SECURITY;

CREATE TRIGGER z_touch BEFORE UPDATE ON "schedule"."calendar_connections" FOR EACH ROW EXECUTE FUNCTION infrastructure.touch_row();

ALTER TABLE "schedule"."calendar_connections" ADD CONSTRAINT "c_26e21eacdb087a27bd8b" UNIQUE NULLS NOT DISTINCT ("integration_id", "external_calendar_key", "resource_id");

CREATE TABLE "itsm"."ticket_types" (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "code" text NOT NULL,
  "label" text NOT NULL,
  "class" text NOT NULL,
  "active" boolean NOT NULL,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  row_version bigint NOT NULL DEFAULT 1 CHECK(row_version>0)
);

COMMENT ON TABLE "itsm"."ticket_types" IS 'Types de tickets configurables | Catalogue: Incident, demande, problème, changement distingués ; référentiel extensible sans code libre incontrôlé.';

ALTER TABLE "itsm"."ticket_types" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "itsm"."ticket_types" FORCE ROW LEVEL SECURITY;

CREATE TRIGGER z_touch BEFORE UPDATE ON "itsm"."ticket_types" FOR EACH ROW EXECUTE FUNCTION infrastructure.touch_row();

ALTER TABLE "itsm"."ticket_types" ADD CONSTRAINT "c_180c95ff95f41c0b9498" UNIQUE NULLS NOT DISTINCT ("code");

CREATE TABLE "itsm"."categories" (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "parent_id" uuid,
  "code" text NOT NULL,
  "label" text NOT NULL,
  "active" boolean NOT NULL,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  row_version bigint NOT NULL DEFAULT 1 CHECK(row_version>0)
);

COMMENT ON TABLE "itsm"."categories" IS 'Catégories et sous-catégories | Catalogue: Hiérarchie sans cycle ; désactivation plutôt que perte des références passées.';

ALTER TABLE "itsm"."categories" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "itsm"."categories" FORCE ROW LEVEL SECURITY;

CREATE TRIGGER z_touch BEFORE UPDATE ON "itsm"."categories" FOR EACH ROW EXECUTE FUNCTION infrastructure.touch_row();

ALTER TABLE "itsm"."categories" ADD CONSTRAINT "c_962042cc6db48047db29" CHECK ("parent_id" <> id);

ALTER TABLE "itsm"."categories" ADD CONSTRAINT "c_cf30d1b0623ec95f1bce" UNIQUE NULLS NOT DISTINCT ("code");

CREATE TABLE "itsm"."statuses" (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "code" text NOT NULL,
  "label" text NOT NULL,
  "state_class" text NOT NULL,
  "is_terminal" boolean NOT NULL,
  "portal_label" text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  row_version bigint NOT NULL DEFAULT 1 CHECK(row_version>0)
);

COMMENT ON TABLE "itsm"."statuses" IS 'États et signification métier | Catalogue: Classes stables derrière libellés personnalisables.';

ALTER TABLE "itsm"."statuses" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "itsm"."statuses" FORCE ROW LEVEL SECURITY;

CREATE TRIGGER z_touch BEFORE UPDATE ON "itsm"."statuses" FOR EACH ROW EXECUTE FUNCTION infrastructure.touch_row();

ALTER TABLE "itsm"."statuses" ADD CONSTRAINT "c_fb402bba8829ac6caa7b" UNIQUE NULLS NOT DISTINCT ("code");

CREATE TABLE "itsm"."transition_rules" (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "ticket_type_id" uuid NOT NULL,
  "from_status_id" uuid NOT NULL,
  "to_status_id" uuid NOT NULL,
  "required_permission_id" uuid NOT NULL,
  "condition_rule" jsonb NOT NULL,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  row_version bigint NOT NULL DEFAULT 1 CHECK(row_version>0)
);

COMMENT ON TABLE "itsm"."transition_rules" IS 'Transitions autorisées | Catalogue: Versionner avant publication ; pas de modification arbitraire du statut via une API générique.';

ALTER TABLE "itsm"."transition_rules" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "itsm"."transition_rules" FORCE ROW LEVEL SECURITY;

CREATE TRIGGER z_touch BEFORE UPDATE ON "itsm"."transition_rules" FOR EACH ROW EXECUTE FUNCTION infrastructure.touch_row();

ALTER TABLE "itsm"."transition_rules" ADD CONSTRAINT "c_df91e2866c4d36b07b0a" CHECK (from_status_id <> to_status_id);

ALTER TABLE "itsm"."transition_rules" ADD CONSTRAINT "c_0910e58c4e255ef5305f" UNIQUE NULLS NOT DISTINCT ("ticket_type_id", "from_status_id", "to_status_id");

CREATE TABLE "itsm"."priority_matrix" (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "impact" text NOT NULL,
  "urgency" text NOT NULL,
  "priority_code" text NOT NULL,
  "rank" integer NOT NULL,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  row_version bigint NOT NULL DEFAULT 1 CHECK(row_version>0)
);

COMMENT ON TABLE "itsm"."priority_matrix" IS 'Impact × urgence → priorité | Catalogue: UNIQUE impact + urgence ; criticité métier distincte de l’ordre d’affichage.';

ALTER TABLE "itsm"."priority_matrix" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "itsm"."priority_matrix" FORCE ROW LEVEL SECURITY;

CREATE TRIGGER z_touch BEFORE UPDATE ON "itsm"."priority_matrix" FOR EACH ROW EXECUTE FUNCTION infrastructure.touch_row();

ALTER TABLE "itsm"."priority_matrix" ADD CONSTRAINT "c_768063c46e64dac1df3b" UNIQUE NULLS NOT DISTINCT ("impact", "urgency");

CREATE TABLE "itsm"."tickets" (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "number" text NOT NULL,
  "type_id" uuid NOT NULL,
  "category_id" uuid,
  "status_id" uuid NOT NULL,
  "customer_org_id" uuid NOT NULL,
  "site_id" uuid,
  "requester_affiliation_id" uuid NOT NULL,
  "beneficiary_affiliation_id" uuid,
  "created_by_id" uuid NOT NULL,
  "assigned_team_id" uuid,
  "assigned_to_id" uuid,
  "parent_id" uuid,
  "service_id" uuid,
  "contract_id" uuid,
  "title" text NOT NULL,
  "description" text NOT NULL,
  "portal_summary" text,
  "impact" text NOT NULL,
  "urgency" text NOT NULL,
  "priority_code" text NOT NULL,
  "source" text NOT NULL,
  "opened_at" timestamptz NOT NULL,
  "resolved_at" timestamptz,
  "closed_at" timestamptz,
  "resolution_due_at" timestamptz,
  "external_project_ref" text,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  row_version bigint NOT NULL DEFAULT 1 CHECK(row_version>0)
);

COMMENT ON TABLE "itsm"."tickets" IS 'Dossier de support central | Catalogue: Numéro unique par installation ; demandeur dans le contexte société ; site cohérent ; filiation sans cycle ; contexte client explicite même pour demandes internes.';

ALTER TABLE "itsm"."tickets" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "itsm"."tickets" FORCE ROW LEVEL SECURITY;

CREATE TRIGGER z_touch BEFORE UPDATE ON "itsm"."tickets" FOR EACH ROW EXECUTE FUNCTION infrastructure.touch_row();

ALTER TABLE "itsm"."tickets" ADD CONSTRAINT "c_dff4c4fc15fb9b7dc0b9" CHECK ("parent_id" <> id);

ALTER TABLE "itsm"."tickets" ADD CONSTRAINT "c_9ab61c79e02bd3d062bf" UNIQUE NULLS NOT DISTINCT ("number");

CREATE TABLE "itsm"."ticket_participants" (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "ticket_id" uuid NOT NULL,
  "person_id" uuid NOT NULL,
  "role" text NOT NULL,
  "visibility_scope" text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  row_version bigint NOT NULL DEFAULT 1 CHECK(row_version>0)
);

COMMENT ON TABLE "itsm"."ticket_participants" IS 'Demandeurs délégués, observateurs, intervenants | Catalogue: Participation ne donne pas accès aux notes internes ; invitation vérifiée.';

ALTER TABLE "itsm"."ticket_participants" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "itsm"."ticket_participants" FORCE ROW LEVEL SECURITY;

CREATE TRIGGER z_touch BEFORE UPDATE ON "itsm"."ticket_participants" FOR EACH ROW EXECUTE FUNCTION infrastructure.touch_row();

ALTER TABLE "itsm"."ticket_participants" ADD CONSTRAINT "c_b22709530830e7abb1a5" UNIQUE NULLS NOT DISTINCT ("ticket_id", "person_id", "role");

CREATE TABLE "itsm"."ticket_messages" (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "ticket_id" uuid NOT NULL,
  "author_id" uuid NOT NULL,
  "body" text NOT NULL,
  "visibility" text NOT NULL,
  "channel" text NOT NULL,
  "posted_at" timestamptz NOT NULL,
  "external_message_key" text,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  row_version bigint NOT NULL DEFAULT 1 CHECK(row_version>0)
);

COMMENT ON TABLE "itsm"."ticket_messages" IS 'Questions, réponses et notes | Catalogue: Visibilité public-client ou interne obligatoire ; HTML assaini ; édition historisée.';

ALTER TABLE "itsm"."ticket_messages" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "itsm"."ticket_messages" FORCE ROW LEVEL SECURITY;

CREATE TRIGGER z_touch BEFORE UPDATE ON "itsm"."ticket_messages" FOR EACH ROW EXECUTE FUNCTION infrastructure.touch_row();

ALTER TABLE "itsm"."ticket_messages" ADD CONSTRAINT "c_0125dc8eb1ac63561655" CHECK (visibility IN ('client','internal'));

CREATE TABLE "itsm"."message_revisions" (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "message_id" uuid NOT NULL,
  "revision_no" integer NOT NULL,
  "body" text NOT NULL,
  "edited_by" uuid NOT NULL,
  "edited_at" timestamptz NOT NULL,
  "reason" text,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  row_version bigint NOT NULL DEFAULT 1 CHECK(row_version>0)
);

COMMENT ON TABLE "itsm"."message_revisions" IS 'Corrections de messages | Catalogue: Anciennes versions non exposées au portail sans droit ; rétention distincte.';

ALTER TABLE "itsm"."message_revisions" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "itsm"."message_revisions" FORCE ROW LEVEL SECURITY;

CREATE TRIGGER z_touch BEFORE UPDATE ON "itsm"."message_revisions" FOR EACH ROW EXECUTE FUNCTION infrastructure.touch_row();

CREATE TRIGGER a_immutable BEFORE UPDATE OR DELETE ON "itsm"."message_revisions" FOR EACH ROW EXECUTE FUNCTION infrastructure.reject_mutation();
CREATE TRIGGER a_no_truncate BEFORE TRUNCATE ON "itsm"."message_revisions" FOR EACH STATEMENT EXECUTE FUNCTION infrastructure.reject_mutation();

ALTER TABLE "itsm"."message_revisions" ADD CONSTRAINT "c_65fe43a76cea92b4d682" CHECK ("revision_no" > 0);

ALTER TABLE "itsm"."message_revisions" ADD CONSTRAINT "c_0a49ee0558d3efad982d" UNIQUE NULLS NOT DISTINCT ("message_id", "revision_no");

CREATE TABLE "itsm"."ticket_events" (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "ticket_id" uuid NOT NULL,
  "event_type" text NOT NULL,
  "actor_id" uuid,
  "occurred_at" timestamptz NOT NULL,
  "from_status_id" uuid,
  "to_status_id" uuid,
  "payload" jsonb NOT NULL,
  "correlation_id" text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  row_version bigint NOT NULL DEFAULT 1 CHECK(row_version>0)
);

COMMENT ON TABLE "itsm"."ticket_events" IS 'Journal métier du ticket | Catalogue: Écriture atomique avec la modification ; payload limité aux données nécessaires.';

ALTER TABLE "itsm"."ticket_events" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "itsm"."ticket_events" FORCE ROW LEVEL SECURITY;

CREATE TRIGGER z_touch BEFORE UPDATE ON "itsm"."ticket_events" FOR EACH ROW EXECUTE FUNCTION infrastructure.touch_row();

CREATE TRIGGER a_immutable BEFORE UPDATE OR DELETE ON "itsm"."ticket_events" FOR EACH ROW EXECUTE FUNCTION infrastructure.reject_mutation();
CREATE TRIGGER a_no_truncate BEFORE TRUNCATE ON "itsm"."ticket_events" FOR EACH STATEMENT EXECUTE FUNCTION infrastructure.reject_mutation();

CREATE TABLE "itsm"."assignment_history" (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "ticket_id" uuid NOT NULL,
  "team_id" uuid,
  "assignee_id" uuid,
  "starts_at" timestamptz NOT NULL,
  "ends_at" timestamptz,
  "reason" text,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  row_version bigint NOT NULL DEFAULT 1 CHECK(row_version>0)
);

COMMENT ON TABLE "itsm"."assignment_history" IS 'Affectations successives | Catalogue: Une affectation principale active ; courant et historique mis à jour ensemble.';

ALTER TABLE "itsm"."assignment_history" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "itsm"."assignment_history" FORCE ROW LEVEL SECURITY;

CREATE TRIGGER z_touch BEFORE UPDATE ON "itsm"."assignment_history" FOR EACH ROW EXECUTE FUNCTION infrastructure.touch_row();

ALTER TABLE "itsm"."assignment_history" ADD CONSTRAINT "c_82776b48bc6f62c8f8a2" CHECK (num_nonnulls(team_id,assignee_id)>=1);

ALTER TABLE "itsm"."assignment_history" ADD CONSTRAINT "c_3391f04dd7cc22b13878" CHECK ("ends_at" > "starts_at");

CREATE TABLE "itsm"."wait_reasons" (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "code" text NOT NULL,
  "label" text NOT NULL,
  "requires_customer_reply" boolean NOT NULL,
  "pause_first_response" boolean NOT NULL,
  "pause_resolution" boolean NOT NULL,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  row_version bigint NOT NULL DEFAULT 1 CHECK(row_version>0)
);

COMMENT ON TABLE "itsm"."wait_reasons" IS 'Motifs de suspension | Catalogue: Les pauses dépendent de la politique appliquée et du motif, pas seulement du statut.';

ALTER TABLE "itsm"."wait_reasons" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "itsm"."wait_reasons" FORCE ROW LEVEL SECURITY;

CREATE TRIGGER z_touch BEFORE UPDATE ON "itsm"."wait_reasons" FOR EACH ROW EXECUTE FUNCTION infrastructure.touch_row();

ALTER TABLE "itsm"."wait_reasons" ADD CONSTRAINT "c_9150cd77f9d64340d62d" UNIQUE NULLS NOT DISTINCT ("code");

CREATE TABLE "itsm"."waiting_periods" (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "ticket_id" uuid NOT NULL,
  "reason_id" uuid NOT NULL,
  "question_message_id" uuid,
  "started_at" timestamptz NOT NULL,
  "ended_at" timestamptz,
  "response_due_at" timestamptz,
  "calendar_id" uuid NOT NULL,
  "deadline_action" text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  row_version bigint NOT NULL DEFAULT 1 CHECK(row_version>0)
);

COMMENT ON TABLE "itsm"."waiting_periods" IS 'Épisodes d’attente | Catalogue: Une attente active de même type ; réponse autorisée remet en cours ; action à expiration à valider.';

ALTER TABLE "itsm"."waiting_periods" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "itsm"."waiting_periods" FORCE ROW LEVEL SECURITY;

CREATE TRIGGER z_touch BEFORE UPDATE ON "itsm"."waiting_periods" FOR EACH ROW EXECUTE FUNCTION infrastructure.touch_row();

ALTER TABLE "itsm"."waiting_periods" ADD CONSTRAINT "c_4481c167a13cd2b6bea1" CHECK (deadline_action IN ('remind','escalate','manual_review'));

ALTER TABLE "itsm"."waiting_periods" ADD CONSTRAINT "c_199058cd380a50e45899" CHECK ("ended_at" >= "started_at");

CREATE TABLE "itsm"."resolutions" (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "ticket_id" uuid NOT NULL,
  "proposed_by" uuid NOT NULL,
  "summary" text NOT NULL,
  "cause_code" text,
  "proposed_at" timestamptz NOT NULL,
  "approval_due_at" timestamptz NOT NULL,
  "calendar_id" uuid NOT NULL,
  "status" text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  row_version bigint NOT NULL DEFAULT 1 CHECK(row_version>0)
);

COMMENT ON TABLE "itsm"."resolutions" IS 'Propositions successives de résolution | Catalogue: Une proposition en cours ; refus explicite rouvre ; anciennes propositions conservées.';

ALTER TABLE "itsm"."resolutions" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "itsm"."resolutions" FORCE ROW LEVEL SECURITY;

CREATE TRIGGER z_touch BEFORE UPDATE ON "itsm"."resolutions" FOR EACH ROW EXECUTE FUNCTION infrastructure.touch_row();

ALTER TABLE "itsm"."resolutions" ADD CONSTRAINT "c_1a184e9e256b4d10c2e4" CHECK (status IN ('pending','accepted','rejected','withdrawn'));

ALTER TABLE "itsm"."resolutions" ADD CONSTRAINT "c_338930f5ccde0f6120a3" CHECK (approval_due_at >= proposed_at);

CREATE TABLE "itsm"."resolution_responses" (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "resolution_id" uuid NOT NULL,
  "responder_id" uuid NOT NULL,
  "decision" text NOT NULL,
  "comment" text,
  "responded_at" timestamptz NOT NULL,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  row_version bigint NOT NULL DEFAULT 1 CHECK(row_version>0)
);

COMMENT ON TABLE "itsm"."resolution_responses" IS 'Acceptations et refus des utilisateurs | Catalogue: Autorité du répondant contrôlée ; décision idempotente ; aucune approbation inventée en cas de silence.';

ALTER TABLE "itsm"."resolution_responses" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "itsm"."resolution_responses" FORCE ROW LEVEL SECURITY;

CREATE TRIGGER z_touch BEFORE UPDATE ON "itsm"."resolution_responses" FOR EACH ROW EXECUTE FUNCTION infrastructure.touch_row();

CREATE TRIGGER a_immutable BEFORE UPDATE OR DELETE ON "itsm"."resolution_responses" FOR EACH ROW EXECUTE FUNCTION infrastructure.reject_mutation();
CREATE TRIGGER a_no_truncate BEFORE TRUNCATE ON "itsm"."resolution_responses" FOR EACH STATEMENT EXECUTE FUNCTION infrastructure.reject_mutation();

ALTER TABLE "itsm"."resolution_responses" ADD CONSTRAINT "c_4f926af420f3f748dbb7" CHECK (decision IN ('accepted','rejected'));

ALTER TABLE "itsm"."resolution_responses" ADD CONSTRAINT "c_f612e9664bf8828b6596" UNIQUE NULLS NOT DISTINCT ("resolution_id", "responder_id");

CREATE TABLE "itsm"."ticket_assets" (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "ticket_id" uuid NOT NULL,
  "item_id" uuid NOT NULL,
  "relation_type" text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  row_version bigint NOT NULL DEFAULT 1 CHECK(row_version>0)
);

COMMENT ON TABLE "itsm"."ticket_assets" IS 'Équipements concernés | Catalogue: Vérifier droit de support et périmètre client ; présence d’un lien ne publie pas la fiche complète.';

ALTER TABLE "itsm"."ticket_assets" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "itsm"."ticket_assets" FORCE ROW LEVEL SECURITY;

CREATE TRIGGER z_touch BEFORE UPDATE ON "itsm"."ticket_assets" FOR EACH ROW EXECUTE FUNCTION infrastructure.touch_row();

ALTER TABLE "itsm"."ticket_assets" ADD CONSTRAINT "c_11f0e331b06237e873d5" UNIQUE NULLS NOT DISTINCT ("ticket_id", "item_id", "relation_type");

CREATE TABLE "itsm"."ticket_projects" (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "ticket_id" uuid NOT NULL,
  "project_id" uuid NOT NULL,
  "relation_type" text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  row_version bigint NOT NULL DEFAULT 1 CHECK(row_version>0)
);

COMMENT ON TABLE "itsm"."ticket_projects" IS 'Liens aux projets internes | Catalogue: Table seulement si module projet installé ; sinon mapping d’intégration.';

ALTER TABLE "itsm"."ticket_projects" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "itsm"."ticket_projects" FORCE ROW LEVEL SECURITY;

CREATE TRIGGER z_touch BEFORE UPDATE ON "itsm"."ticket_projects" FOR EACH ROW EXECUTE FUNCTION infrastructure.touch_row();

ALTER TABLE "itsm"."ticket_projects" ADD CONSTRAINT "c_a24e910a38ff6ce42eaa" UNIQUE NULLS NOT DISTINCT ("ticket_id", "project_id", "relation_type");

CREATE TABLE "itsm"."ticket_opportunities" (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "ticket_id" uuid NOT NULL,
  "opportunity_id" uuid NOT NULL,
  "relation_type" text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  row_version bigint NOT NULL DEFAULT 1 CHECK(row_version>0)
);

COMMENT ON TABLE "itsm"."ticket_opportunities" IS 'Liens aux affaires commerciales | Catalogue: Aucun montant commercial visible au portail.';

ALTER TABLE "itsm"."ticket_opportunities" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "itsm"."ticket_opportunities" FORCE ROW LEVEL SECURITY;

CREATE TRIGGER z_touch BEFORE UPDATE ON "itsm"."ticket_opportunities" FOR EACH ROW EXECUTE FUNCTION infrastructure.touch_row();

ALTER TABLE "itsm"."ticket_opportunities" ADD CONSTRAINT "c_e07b93df33ad08890db7" UNIQUE NULLS NOT DISTINCT ("ticket_id", "opportunity_id", "relation_type");

CREATE TABLE "itsm"."ticket_relations" (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "source_id" uuid NOT NULL,
  "target_id" uuid NOT NULL,
  "relation_type" text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  row_version bigint NOT NULL DEFAULT 1 CHECK(row_version>0)
);

COMMENT ON TABLE "itsm"."ticket_relations" IS 'Doublons, causes et dépendances | Catalogue: Pas d’auto-lien ; types bloquants sans cycle ; fusion ne mélange pas les droits clients.';

ALTER TABLE "itsm"."ticket_relations" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "itsm"."ticket_relations" FORCE ROW LEVEL SECURITY;

CREATE TRIGGER z_touch BEFORE UPDATE ON "itsm"."ticket_relations" FOR EACH ROW EXECUTE FUNCTION infrastructure.touch_row();

ALTER TABLE "itsm"."ticket_relations" ADD CONSTRAINT "c_f28ecd60b733b8202e64" CHECK (source_id <> target_id);

ALTER TABLE "itsm"."ticket_relations" ADD CONSTRAINT "c_d663ea1d2247ab880953" UNIQUE NULLS NOT DISTINCT ("source_id", "target_id", "relation_type");

CREATE TABLE "itsm"."ticket_tags" (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "ticket_id" uuid NOT NULL,
  "tag_id" uuid NOT NULL,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  row_version bigint NOT NULL DEFAULT 1 CHECK(row_version>0)
);

COMMENT ON TABLE "itsm"."ticket_tags" IS 'Étiquettes filtrables | Catalogue: UNIQUE ticket + tag.';

ALTER TABLE "itsm"."ticket_tags" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "itsm"."ticket_tags" FORCE ROW LEVEL SECURITY;

CREATE TRIGGER z_touch BEFORE UPDATE ON "itsm"."ticket_tags" FOR EACH ROW EXECUTE FUNCTION infrastructure.touch_row();

ALTER TABLE "itsm"."ticket_tags" ADD CONSTRAINT "c_7bc92c537cdd1b69faf0" UNIQUE NULLS NOT DISTINCT ("ticket_id", "tag_id");

CREATE TABLE "itsm"."problem_details" (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "ticket_id" uuid NOT NULL,
  "root_cause" text,
  "workaround" text,
  "known_error" boolean NOT NULL,
  "reviewed_at" timestamptz,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  row_version bigint NOT NULL DEFAULT 1 CHECK(row_version>0)
);

COMMENT ON TABLE "itsm"."problem_details" IS 'Analyse des problèmes | Catalogue: UNIQUE ticket ; type problème ; liens aux incidents via relations explicites.';

ALTER TABLE "itsm"."problem_details" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "itsm"."problem_details" FORCE ROW LEVEL SECURITY;

CREATE TRIGGER z_touch BEFORE UPDATE ON "itsm"."problem_details" FOR EACH ROW EXECUTE FUNCTION infrastructure.touch_row();

ALTER TABLE "itsm"."problem_details" ADD CONSTRAINT "c_841f7a45ea382d4d4920" UNIQUE NULLS NOT DISTINCT ("ticket_id");

CREATE TABLE "itsm"."change_details" (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "ticket_id" uuid NOT NULL,
  "risk_level" text NOT NULL,
  "reason" text NOT NULL,
  "implementation_plan" text NOT NULL,
  "rollback_plan" text NOT NULL,
  "test_plan" text NOT NULL,
  "window_start" timestamptz,
  "window_end" timestamptz,
  "review_outcome" text,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  row_version bigint NOT NULL DEFAULT 1 CHECK(row_version>0)
);

COMMENT ON TABLE "itsm"."change_details" IS 'Gestion des changements internes ou clients | Catalogue: UNIQUE ticket de type changement ; approbations et actifs impactés avant exécution selon politique.';

ALTER TABLE "itsm"."change_details" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "itsm"."change_details" FORCE ROW LEVEL SECURITY;

CREATE TRIGGER z_touch BEFORE UPDATE ON "itsm"."change_details" FOR EACH ROW EXECUTE FUNCTION infrastructure.touch_row();

ALTER TABLE "itsm"."change_details" ADD CONSTRAINT "c_54ff9ceb52c76fc322e7" CHECK ("window_end" >= "window_start");

ALTER TABLE "itsm"."change_details" ADD CONSTRAINT "c_96d4a949d0db62cf6659" UNIQUE NULLS NOT DISTINCT ("ticket_id");

CREATE TABLE "itsm"."interventions" (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "ticket_id" uuid NOT NULL,
  "mode" text NOT NULL,
  "site_id" uuid,
  "status" text NOT NULL,
  "planned_start" timestamptz,
  "planned_end" timestamptz,
  "actual_start" timestamptz,
  "actual_end" timestamptz,
  "report" text,
  "travel_minutes" integer,
  "travel_distance_km" numeric(20,6),
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  row_version bigint NOT NULL DEFAULT 1 CHECK(row_version>0)
);

COMMENT ON TABLE "itsm"."interventions" IS 'Interventions à distance et sur site | Catalogue: Plusieurs techniciens via réservations ; déplacement distingue durée, frais et prestation.';

ALTER TABLE "itsm"."interventions" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "itsm"."interventions" FORCE ROW LEVEL SECURITY;

CREATE TRIGGER z_touch BEFORE UPDATE ON "itsm"."interventions" FOR EACH ROW EXECUTE FUNCTION infrastructure.touch_row();

ALTER TABLE "itsm"."interventions" ADD CONSTRAINT "c_18935377a55e702c1ff6" CHECK ("travel_minutes" >= 0);

ALTER TABLE "itsm"."interventions" ADD CONSTRAINT "c_6d40352d34262ac5e542" CHECK ("travel_distance_km" <> 'NaN'::numeric);

ALTER TABLE "itsm"."interventions" ADD CONSTRAINT "c_2b8b1da8e7cfb103ae7d" CHECK ("travel_distance_km" >= 0);

ALTER TABLE "itsm"."interventions" ADD CONSTRAINT "c_8f14262dd0f6bc57112c" CHECK ("planned_end" >= "planned_start");

ALTER TABLE "itsm"."interventions" ADD CONSTRAINT "c_0e5a2e3208848bc04664" CHECK ("actual_end" >= "actual_start");

CREATE TABLE "itsm"."intervention_signoffs" (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "intervention_id" uuid NOT NULL,
  "signer_affiliation_id" uuid NOT NULL,
  "decision" text NOT NULL,
  "signed_at" timestamptz NOT NULL,
  "document_id" uuid,
  "evidence_ref" text,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  row_version bigint NOT NULL DEFAULT 1 CHECK(row_version>0)
);

COMMENT ON TABLE "itsm"."intervention_signoffs" IS 'Validation de compte rendu | Catalogue: Ne vaut pas clôture automatique du ticket ; version du compte rendu figée.';

ALTER TABLE "itsm"."intervention_signoffs" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "itsm"."intervention_signoffs" FORCE ROW LEVEL SECURITY;

CREATE TRIGGER z_touch BEFORE UPDATE ON "itsm"."intervention_signoffs" FOR EACH ROW EXECUTE FUNCTION infrastructure.touch_row();

CREATE TRIGGER a_immutable BEFORE UPDATE OR DELETE ON "itsm"."intervention_signoffs" FOR EACH ROW EXECUTE FUNCTION infrastructure.reject_mutation();
CREATE TRIGGER a_no_truncate BEFORE TRUNCATE ON "itsm"."intervention_signoffs" FOR EACH STATEMENT EXECUTE FUNCTION infrastructure.reject_mutation();

CREATE TABLE "itsm"."saved_views" (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "owner_id" uuid NOT NULL,
  "name" text NOT NULL,
  "filters" jsonb NOT NULL,
  "columns" jsonb NOT NULL,
  "sharing_scope" text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  row_version bigint NOT NULL DEFAULT 1 CHECK(row_version>0)
);

COMMENT ON TABLE "itsm"."saved_views" IS 'Filtres et vues partagées | Catalogue: Filtres appliqués après autorisation ; aucun filtre ne peut étendre les droits.';

ALTER TABLE "itsm"."saved_views" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "itsm"."saved_views" FORCE ROW LEVEL SECURITY;

CREATE TRIGGER z_touch BEFORE UPDATE ON "itsm"."saved_views" FOR EACH ROW EXECUTE FUNCTION infrastructure.touch_row();

CREATE TABLE "itsm"."portal_preferences" (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "principal_id" uuid NOT NULL,
  "default_view" text NOT NULL,
  "locale" text NOT NULL,
  "notification_settings" jsonb NOT NULL,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  row_version bigint NOT NULL DEFAULT 1 CHECK(row_version>0)
);

COMMENT ON TABLE "itsm"."portal_preferences" IS 'Préférences de consultation | Catalogue: Tickets en cours par défaut ; historique accessible sans changer le périmètre autorisé.';

ALTER TABLE "itsm"."portal_preferences" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "itsm"."portal_preferences" FORCE ROW LEVEL SECURITY;

CREATE TRIGGER z_touch BEFORE UPDATE ON "itsm"."portal_preferences" FOR EACH ROW EXECUTE FUNCTION infrastructure.touch_row();

ALTER TABLE "itsm"."portal_preferences" ADD CONSTRAINT "c_1ae6ebd5a6cc127394d0" UNIQUE NULLS NOT DISTINCT ("principal_id");

CREATE TABLE "service"."catalog_items" (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "code" text NOT NULL,
  "name" text NOT NULL,
  "description" text NOT NULL,
  "request_type_id" uuid NOT NULL,
  "workflow_id" uuid,
  "active" boolean NOT NULL,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  row_version bigint NOT NULL DEFAULT 1 CHECK(row_version>0)
);

COMMENT ON TABLE "service"."catalog_items" IS 'Services et demandes standard | Catalogue: Catalogue utilisé en interne ; portail reste limité aux tickets et équipements.';

ALTER TABLE "service"."catalog_items" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "service"."catalog_items" FORCE ROW LEVEL SECURITY;

CREATE TRIGGER z_touch BEFORE UPDATE ON "service"."catalog_items" FOR EACH ROW EXECUTE FUNCTION infrastructure.touch_row();

ALTER TABLE "service"."catalog_items" ADD CONSTRAINT "c_ddc8d55194d897095b06" UNIQUE NULLS NOT DISTINCT ("code");

CREATE TABLE "service"."catalog_versions" (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "catalog_item_id" uuid NOT NULL,
  "version_no" integer NOT NULL,
  "form_schema" jsonb NOT NULL,
  "validation_rules" jsonb NOT NULL,
  "published_at" timestamptz,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  row_version bigint NOT NULL DEFAULT 1 CHECK(row_version>0)
);

COMMENT ON TABLE "service"."catalog_versions" IS 'Formulaires de demande versionnés | Catalogue: Réponses liées à la version exacte du formulaire.';

ALTER TABLE "service"."catalog_versions" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "service"."catalog_versions" FORCE ROW LEVEL SECURITY;

CREATE TRIGGER z_touch BEFORE UPDATE ON "service"."catalog_versions" FOR EACH ROW EXECUTE FUNCTION infrastructure.touch_row();

CREATE TRIGGER a_published BEFORE UPDATE OR DELETE ON "service"."catalog_versions" FOR EACH ROW EXECUTE FUNCTION infrastructure.freeze_published();

ALTER TABLE "service"."catalog_versions" ADD CONSTRAINT "c_67277808aaf59a237334" CHECK ("version_no" > 0);

ALTER TABLE "service"."catalog_versions" ADD CONSTRAINT "c_cae052c2b03dbddc65d2" UNIQUE NULLS NOT DISTINCT ("catalog_item_id", "version_no");

CREATE TABLE "service"."request_answers" (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "ticket_id" uuid NOT NULL,
  "catalog_version_id" uuid NOT NULL,
  "answers" jsonb NOT NULL,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  row_version bigint NOT NULL DEFAULT 1 CHECK(row_version>0)
);

COMMENT ON TABLE "service"."request_answers" IS 'Réponses structurées aux formulaires | Catalogue: Schéma validé ; champs sensibles masqués selon profil.';

ALTER TABLE "service"."request_answers" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "service"."request_answers" FORCE ROW LEVEL SECURITY;

CREATE TRIGGER z_touch BEFORE UPDATE ON "service"."request_answers" FOR EACH ROW EXECUTE FUNCTION infrastructure.touch_row();

ALTER TABLE "service"."request_answers" ADD CONSTRAINT "c_6f91346d1528aa6e819f" UNIQUE NULLS NOT DISTINCT ("ticket_id", "catalog_version_id");

CREATE TABLE "service"."sla_policies" (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "code" text NOT NULL,
  "name" text NOT NULL,
  "version_no" integer NOT NULL,
  "calendar_id" uuid NOT NULL,
  "kind" text NOT NULL,
  "effective_from" timestamptz NOT NULL,
  "effective_to" timestamptz,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  row_version bigint NOT NULL DEFAULT 1 CHECK(row_version>0)
);

COMMENT ON TABLE "service"."sla_policies" IS 'Politiques de service versionnées | Catalogue: kind interne, contractuel ou OLA ; version applicable figée à l’ouverture selon règle.';

ALTER TABLE "service"."sla_policies" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "service"."sla_policies" FORCE ROW LEVEL SECURITY;

CREATE TRIGGER z_touch BEFORE UPDATE ON "service"."sla_policies" FOR EACH ROW EXECUTE FUNCTION infrastructure.touch_row();

ALTER TABLE "service"."sla_policies" ADD CONSTRAINT "c_2ea7dce837c9865d22d6" CHECK ("version_no" > 0);

ALTER TABLE "service"."sla_policies" ADD CONSTRAINT "c_563964e8cf549004c075" CHECK ("effective_to" >= "effective_from");

ALTER TABLE "service"."sla_policies" ADD CONSTRAINT "c_ddc3e0423166bfc95973" UNIQUE NULLS NOT DISTINCT ("code", "version_no");

CREATE TABLE "service"."sla_targets" (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "policy_id" uuid NOT NULL,
  "priority_code" text NOT NULL,
  "service_id" uuid,
  "metric" text NOT NULL,
  "target_work_minutes" integer NOT NULL,
  "pause_rules" jsonb NOT NULL,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  row_version bigint NOT NULL DEFAULT 1 CHECK(row_version>0)
);

COMMENT ON TABLE "service"."sla_targets" IS 'Objectifs par priorité et service | Catalogue: Réponse, prise en charge et résolution distinguées ; minutes positives.';

ALTER TABLE "service"."sla_targets" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "service"."sla_targets" FORCE ROW LEVEL SECURITY;

CREATE TRIGGER z_touch BEFORE UPDATE ON "service"."sla_targets" FOR EACH ROW EXECUTE FUNCTION infrastructure.touch_row();

ALTER TABLE "service"."sla_targets" ADD CONSTRAINT "c_d6c014f16337dc288699" CHECK ("target_work_minutes" >= 0);

ALTER TABLE "service"."sla_targets" ADD CONSTRAINT "c_d177d2ddb672705e3087" UNIQUE NULLS NOT DISTINCT ("policy_id", "priority_code", "service_id", "metric");

CREATE TABLE "service"."sla_instances" (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "ticket_id" uuid NOT NULL,
  "target_id" uuid NOT NULL,
  "calendar_id" uuid NOT NULL,
  "cycle_no" integer NOT NULL,
  "started_at" timestamptz NOT NULL,
  "due_at" timestamptz NOT NULL,
  "stopped_at" timestamptz,
  "elapsed_work_minutes" integer NOT NULL,
  "breached_at" timestamptz,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  row_version bigint NOT NULL DEFAULT 1 CHECK(row_version>0)
);

COMMENT ON TABLE "service"."sla_instances" IS 'Horloges appliquées aux tickets | Catalogue: Objectif et calendrier versionnés ; recalcul tracé ; réouverture selon politique explicite.';

ALTER TABLE "service"."sla_instances" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "service"."sla_instances" FORCE ROW LEVEL SECURITY;

CREATE TRIGGER z_touch BEFORE UPDATE ON "service"."sla_instances" FOR EACH ROW EXECUTE FUNCTION infrastructure.touch_row();

ALTER TABLE "service"."sla_instances" ADD CONSTRAINT "c_ca2aa9e1899e90aba2f5" CHECK ("cycle_no" > 0);

ALTER TABLE "service"."sla_instances" ADD CONSTRAINT "c_b398d75333be1e1876dd" CHECK ("elapsed_work_minutes" >= 0);

ALTER TABLE "service"."sla_instances" ADD CONSTRAINT "c_a7199c8d11d1d80de465" UNIQUE NULLS NOT DISTINCT ("ticket_id", "target_id", "cycle_no");

CREATE TABLE "service"."sla_pauses" (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "instance_id" uuid NOT NULL,
  "waiting_period_id" uuid,
  "starts_at" timestamptz NOT NULL,
  "ends_at" timestamptz,
  "reason" text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  row_version bigint NOT NULL DEFAULT 1 CHECK(row_version>0)
);

COMMENT ON TABLE "service"."sla_pauses" IS 'Pauses d’une horloge | Catalogue: Intervalles sans double comptage ; aucune pause rétroactive silencieuse.';

ALTER TABLE "service"."sla_pauses" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "service"."sla_pauses" FORCE ROW LEVEL SECURITY;

CREATE TRIGGER z_touch BEFORE UPDATE ON "service"."sla_pauses" FOR EACH ROW EXECUTE FUNCTION infrastructure.touch_row();

ALTER TABLE "service"."sla_pauses" ADD CONSTRAINT "c_030d83fb702367ff1bc1" CHECK ("ends_at" > "starts_at");

CREATE TABLE "service"."escalation_rules" (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "policy_id" uuid NOT NULL,
  "threshold_percent" numeric(20,6) NOT NULL,
  "target_team_id" uuid,
  "action" text NOT NULL,
  "active" boolean NOT NULL,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  row_version bigint NOT NULL DEFAULT 1 CHECK(row_version>0)
);

COMMENT ON TABLE "service"."escalation_rules" IS 'Seuils et destinataires d’escalade | Catalogue: Actions déclaratives autorisées ; seuils configurables, pas de scripts SQL libres.';

ALTER TABLE "service"."escalation_rules" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "service"."escalation_rules" FORCE ROW LEVEL SECURITY;

CREATE TRIGGER z_touch BEFORE UPDATE ON "service"."escalation_rules" FOR EACH ROW EXECUTE FUNCTION infrastructure.touch_row();

ALTER TABLE "service"."escalation_rules" ADD CONSTRAINT "c_cc773536e541662061d4" CHECK ("threshold_percent" <> 'NaN'::numeric);

CREATE TABLE "service"."escalation_events" (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "ticket_id" uuid NOT NULL,
  "rule_id" uuid NOT NULL,
  "triggered_at" timestamptz NOT NULL,
  "result" text NOT NULL,
  "idempotency_key" text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  row_version bigint NOT NULL DEFAULT 1 CHECK(row_version>0)
);

COMMENT ON TABLE "service"."escalation_events" IS 'Exécution des escalades | Catalogue: Clé unique contre doublons de notification ou d’affectation.';

ALTER TABLE "service"."escalation_events" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "service"."escalation_events" FORCE ROW LEVEL SECURITY;

CREATE TRIGGER z_touch BEFORE UPDATE ON "service"."escalation_events" FOR EACH ROW EXECUTE FUNCTION infrastructure.touch_row();

CREATE TRIGGER a_immutable BEFORE UPDATE OR DELETE ON "service"."escalation_events" FOR EACH ROW EXECUTE FUNCTION infrastructure.reject_mutation();
CREATE TRIGGER a_no_truncate BEFORE TRUNCATE ON "service"."escalation_events" FOR EACH STATEMENT EXECUTE FUNCTION infrastructure.reject_mutation();

ALTER TABLE "service"."escalation_events" ADD CONSTRAINT "c_b52c4f4f100c58f2db91" UNIQUE NULLS NOT DISTINCT ("idempotency_key");

CREATE TABLE "workflow"."definitions" (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "code" text NOT NULL,
  "name" text NOT NULL,
  "purpose" text NOT NULL,
  "active" boolean NOT NULL,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  row_version bigint NOT NULL DEFAULT 1 CHECK(row_version>0)
);

COMMENT ON TABLE "workflow"."definitions" IS 'Modèles de processus | Catalogue: Arrivée, départ, mobilité, changement et demandes personnalisées.';

ALTER TABLE "workflow"."definitions" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "workflow"."definitions" FORCE ROW LEVEL SECURITY;

CREATE TRIGGER z_touch BEFORE UPDATE ON "workflow"."definitions" FOR EACH ROW EXECUTE FUNCTION infrastructure.touch_row();

ALTER TABLE "workflow"."definitions" ADD CONSTRAINT "c_85244b2a15405662fefd" UNIQUE NULLS NOT DISTINCT ("code");

CREATE TABLE "workflow"."versions" (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "definition_id" uuid NOT NULL,
  "version_no" integer NOT NULL,
  "status" text NOT NULL,
  "published_at" timestamptz,
  "published_by" uuid,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  row_version bigint NOT NULL DEFAULT 1 CHECK(row_version>0)
);

COMMENT ON TABLE "workflow"."versions" IS 'Versions publiables des processus | Catalogue: UNIQUE modèle + version ; immuable après publication.';

ALTER TABLE "workflow"."versions" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "workflow"."versions" FORCE ROW LEVEL SECURITY;

CREATE TRIGGER z_touch BEFORE UPDATE ON "workflow"."versions" FOR EACH ROW EXECUTE FUNCTION infrastructure.touch_row();

CREATE TRIGGER a_published BEFORE UPDATE OR DELETE ON "workflow"."versions" FOR EACH ROW EXECUTE FUNCTION infrastructure.freeze_published();

ALTER TABLE "workflow"."versions" ADD CONSTRAINT "c_f3e53e600269e6bf6279" CHECK ("version_no" > 0);

ALTER TABLE "workflow"."versions" ADD CONSTRAINT "c_0d0f38dd2d81b0e3ba40" UNIQUE NULLS NOT DISTINCT ("definition_id", "version_no");

CREATE TABLE "workflow"."steps" (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "version_id" uuid NOT NULL,
  "step_key" text NOT NULL,
  "kind" text NOT NULL,
  "name" text NOT NULL,
  "configuration" jsonb NOT NULL,
  "required_permission_id" uuid,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  row_version bigint NOT NULL DEFAULT 1 CHECK(row_version>0)
);

COMMENT ON TABLE "workflow"."steps" IS 'Étapes d’un modèle | Catalogue: Étape ticket, validation, condition, délai, notification ou connecteur autorisé.';

ALTER TABLE "workflow"."steps" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "workflow"."steps" FORCE ROW LEVEL SECURITY;

CREATE TRIGGER z_touch BEFORE UPDATE ON "workflow"."steps" FOR EACH ROW EXECUTE FUNCTION infrastructure.touch_row();

ALTER TABLE "workflow"."steps" ADD CONSTRAINT "c_64f8d2f4ff2bf5c6d4fa" UNIQUE NULLS NOT DISTINCT ("version_id", "step_key");

CREATE TABLE "workflow"."edges" (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "version_id" uuid NOT NULL,
  "from_step_id" uuid NOT NULL,
  "to_step_id" uuid NOT NULL,
  "condition" jsonb,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  row_version bigint NOT NULL DEFAULT 1 CHECK(row_version>0)
);

COMMENT ON TABLE "workflow"."edges" IS 'Enchaînements et conditions | Catalogue: Étapes de même version ; cycles interdits au départ, répétitions bornées si ajoutées plus tard.';

ALTER TABLE "workflow"."edges" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "workflow"."edges" FORCE ROW LEVEL SECURITY;

CREATE TRIGGER z_touch BEFORE UPDATE ON "workflow"."edges" FOR EACH ROW EXECUTE FUNCTION infrastructure.touch_row();

ALTER TABLE "workflow"."edges" ADD CONSTRAINT "c_1af5c628084fcc3924ae" CHECK (from_step_id <> to_step_id);

ALTER TABLE "workflow"."edges" ADD CONSTRAINT "c_75324e0923327bd57ce4" UNIQUE NULLS NOT DISTINCT ("version_id", "from_step_id", "to_step_id");

CREATE TABLE "workflow"."instances" (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "version_id" uuid NOT NULL,
  "parent_ticket_id" uuid NOT NULL,
  "subject_person_id" uuid,
  "organization_id" uuid NOT NULL,
  "context" jsonb NOT NULL,
  "status" text NOT NULL,
  "started_at" timestamptz NOT NULL,
  "finished_at" timestamptz,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  row_version bigint NOT NULL DEFAULT 1 CHECK(row_version>0)
);

COMMENT ON TABLE "workflow"."instances" IS 'Processus effectivement lancé | Catalogue: Contexte figé utile au traitement ; données personnelles limitées.';

ALTER TABLE "workflow"."instances" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "workflow"."instances" FORCE ROW LEVEL SECURITY;

CREATE TRIGGER z_touch BEFORE UPDATE ON "workflow"."instances" FOR EACH ROW EXECUTE FUNCTION infrastructure.touch_row();

ALTER TABLE "workflow"."instances" ADD CONSTRAINT "c_4246f513a78eb189751b" CHECK ("finished_at" >= "started_at");

CREATE TABLE "workflow"."step_runs" (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "instance_id" uuid NOT NULL,
  "step_id" uuid NOT NULL,
  "attempt" integer NOT NULL,
  "child_ticket_id" uuid,
  "status" text NOT NULL,
  "started_at" timestamptz,
  "finished_at" timestamptz,
  "idempotency_key" text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  row_version bigint NOT NULL DEFAULT 1 CHECK(row_version>0)
);

COMMENT ON TABLE "workflow"."step_runs" IS 'Exécutions et reprises d’étapes | Catalogue: Une même exécution ne crée pas deux demandes filles ; reprise après panne possible.';

ALTER TABLE "workflow"."step_runs" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "workflow"."step_runs" FORCE ROW LEVEL SECURITY;

CREATE TRIGGER z_touch BEFORE UPDATE ON "workflow"."step_runs" FOR EACH ROW EXECUTE FUNCTION infrastructure.touch_row();

ALTER TABLE "workflow"."step_runs" ADD CONSTRAINT "c_c525993f8838422c8d90" CHECK ("attempt" > 0);

ALTER TABLE "workflow"."step_runs" ADD CONSTRAINT "c_9d42830faf15b8b3a4f4" CHECK ("finished_at" >= "started_at");

ALTER TABLE "workflow"."step_runs" ADD CONSTRAINT "c_79e08ea5f09ccd39612e" UNIQUE NULLS NOT DISTINCT ("idempotency_key");

ALTER TABLE "workflow"."step_runs" ADD CONSTRAINT "c_8616bf5fd4db1138be4d" UNIQUE NULLS NOT DISTINCT ("instance_id", "step_id", "attempt");

CREATE TABLE "workflow"."approval_requests" (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "instance_id" uuid,
  "ticket_id" uuid,
  "requested_by" uuid NOT NULL,
  "policy" text NOT NULL,
  "due_at" timestamptz,
  "status" text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  row_version bigint NOT NULL DEFAULT 1 CHECK(row_version>0)
);

COMMENT ON TABLE "workflow"."approval_requests" IS 'Demandes de validation métier | Catalogue: Au moins une cible ; ordre, quorum et délégation explicites.';

ALTER TABLE "workflow"."approval_requests" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "workflow"."approval_requests" FORCE ROW LEVEL SECURITY;

CREATE TRIGGER z_touch BEFORE UPDATE ON "workflow"."approval_requests" FOR EACH ROW EXECUTE FUNCTION infrastructure.touch_row();

ALTER TABLE "workflow"."approval_requests" ADD CONSTRAINT "c_b785e8117248dae5138a" CHECK (num_nonnulls(instance_id,ticket_id)>=1);

CREATE TABLE "workflow"."approval_decisions" (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "request_id" uuid NOT NULL,
  "approver_id" uuid NOT NULL,
  "decision" text NOT NULL,
  "reason" text,
  "decided_at" timestamptz NOT NULL,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  row_version bigint NOT NULL DEFAULT 1 CHECK(row_version>0)
);

COMMENT ON TABLE "workflow"."approval_decisions" IS 'Décisions des approbateurs | Catalogue: UNIQUE demande + approbateur sauf remplacement tracé ; auto-approbation encadrée.';

ALTER TABLE "workflow"."approval_decisions" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "workflow"."approval_decisions" FORCE ROW LEVEL SECURITY;

CREATE TRIGGER z_touch BEFORE UPDATE ON "workflow"."approval_decisions" FOR EACH ROW EXECUTE FUNCTION infrastructure.touch_row();

CREATE TRIGGER a_immutable BEFORE UPDATE OR DELETE ON "workflow"."approval_decisions" FOR EACH ROW EXECUTE FUNCTION infrastructure.reject_mutation();
CREATE TRIGGER a_no_truncate BEFORE TRUNCATE ON "workflow"."approval_decisions" FOR EACH STATEMENT EXECUTE FUNCTION infrastructure.reject_mutation();

ALTER TABLE "workflow"."approval_decisions" ADD CONSTRAINT "c_d271e00a4eb8e5b31a36" UNIQUE NULLS NOT DISTINCT ("request_id", "approver_id");

CREATE TABLE "workflow"."automation_rules" (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "code" text NOT NULL,
  "version_no" integer NOT NULL,
  "trigger_event" text NOT NULL,
  "condition" jsonb NOT NULL,
  "action" jsonb NOT NULL,
  "enabled" boolean NOT NULL,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  row_version bigint NOT NULL DEFAULT 1 CHECK(row_version>0)
);

COMMENT ON TABLE "workflow"."automation_rules" IS 'Déclencheurs transversaux | Catalogue: Langage de règles limité, contrôlé et testable ; pas de code arbitraire.';

ALTER TABLE "workflow"."automation_rules" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "workflow"."automation_rules" FORCE ROW LEVEL SECURITY;

CREATE TRIGGER z_touch BEFORE UPDATE ON "workflow"."automation_rules" FOR EACH ROW EXECUTE FUNCTION infrastructure.touch_row();

ALTER TABLE "workflow"."automation_rules" ADD CONSTRAINT "c_96440dd3bd128b88a312" CHECK ("version_no" > 0);

ALTER TABLE "workflow"."automation_rules" ADD CONSTRAINT "c_5d651d6099bb9ef4e63c" UNIQUE NULLS NOT DISTINCT ("code", "version_no");

CREATE TABLE "workflow"."automation_runs" (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "rule_id" uuid NOT NULL,
  "event_key" text NOT NULL,
  "started_at" timestamptz NOT NULL,
  "finished_at" timestamptz,
  "result" text NOT NULL,
  "error_summary" text,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  row_version bigint NOT NULL DEFAULT 1 CHECK(row_version>0)
);

COMMENT ON TABLE "workflow"."automation_runs" IS 'Journal des règles exécutées | Catalogue: UNIQUE règle + événement ; traces expurgées des secrets.';

ALTER TABLE "workflow"."automation_runs" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "workflow"."automation_runs" FORCE ROW LEVEL SECURITY;

CREATE TRIGGER z_touch BEFORE UPDATE ON "workflow"."automation_runs" FOR EACH ROW EXECUTE FUNCTION infrastructure.touch_row();

ALTER TABLE "workflow"."automation_runs" ADD CONSTRAINT "c_a074017d45bff093a8cd" CHECK ("finished_at" >= "started_at");

ALTER TABLE "workflow"."automation_runs" ADD CONSTRAINT "c_d9e4f783815b7cad9edd" UNIQUE NULLS NOT DISTINCT ("rule_id", "event_key");

CREATE TABLE "cmdb"."item_types" (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "code" text NOT NULL,
  "label" text NOT NULL,
  "category" text NOT NULL,
  "active" boolean NOT NULL,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  row_version bigint NOT NULL DEFAULT 1 CHECK(row_version>0)
);

COMMENT ON TABLE "cmdb"."item_types" IS 'Types de composants | Catalogue: Matériel, logiciel, service, réseau, domaine et cloud ; extensions typées.';

ALTER TABLE "cmdb"."item_types" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "cmdb"."item_types" FORCE ROW LEVEL SECURITY;

CREATE TRIGGER z_touch BEFORE UPDATE ON "cmdb"."item_types" FOR EACH ROW EXECUTE FUNCTION infrastructure.touch_row();

ALTER TABLE "cmdb"."item_types" ADD CONSTRAINT "c_c6afa09fad5d1b9808d0" UNIQUE NULLS NOT DISTINCT ("code");

CREATE TABLE "cmdb"."items" (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "type_id" uuid NOT NULL,
  "code" text NOT NULL,
  "name" text NOT NULL,
  "owner_org_id" uuid NOT NULL,
  "manager_org_id" uuid,
  "site_id" uuid,
  "location_id" uuid,
  "lifecycle" text NOT NULL,
  "criticality" text NOT NULL,
  "management_mode" text NOT NULL,
  "authoritative_source" text NOT NULL,
  "last_verified_at" timestamptz,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  row_version bigint NOT NULL DEFAULT 1 CHECK(row_version>0)
);

COMMENT ON TABLE "cmdb"."items" IS 'Composants de configuration | Catalogue: Code unique par base ; support-only, géré ou observé ; location cohérente avec site.';

ALTER TABLE "cmdb"."items" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "cmdb"."items" FORCE ROW LEVEL SECURITY;

CREATE TRIGGER z_touch BEFORE UPDATE ON "cmdb"."items" FOR EACH ROW EXECUTE FUNCTION infrastructure.touch_row();

ALTER TABLE "cmdb"."items" ADD CONSTRAINT "c_8c650c6883bc10577425" CHECK (location_id IS NULL OR site_id IS NOT NULL);

ALTER TABLE "cmdb"."items" ADD CONSTRAINT "c_55252b2b8cba7a860200" UNIQUE NULLS NOT DISTINCT ("code");

CREATE TABLE "cmdb"."item_identifiers" (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "item_id" uuid NOT NULL,
  "scheme" text NOT NULL,
  "issuer" text NOT NULL,
  "value" text NOT NULL,
  "valid_from" timestamptz,
  "valid_to" timestamptz,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  row_version bigint NOT NULL DEFAULT 1 CHECK(row_version>0)
);

COMMENT ON TABLE "cmdb"."item_identifiers" IS 'Identifiants multiples | Catalogue: Numéro série pas supposé universellement unique ; empreintes de déduplication par source.';

ALTER TABLE "cmdb"."item_identifiers" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "cmdb"."item_identifiers" FORCE ROW LEVEL SECURITY;

CREATE TRIGGER z_touch BEFORE UPDATE ON "cmdb"."item_identifiers" FOR EACH ROW EXECUTE FUNCTION infrastructure.touch_row();

ALTER TABLE "cmdb"."item_identifiers" ADD CONSTRAINT "c_c97d2108daa590c8553e" CHECK ("valid_to" >= "valid_from");

CREATE TABLE "cmdb"."ownership_history" (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "item_id" uuid NOT NULL,
  "organization_id" uuid NOT NULL,
  "starts_at" timestamptz NOT NULL,
  "ends_at" timestamptz,
  "evidence_file_id" uuid,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  row_version bigint NOT NULL DEFAULT 1 CHECK(row_version>0)
);

COMMENT ON TABLE "cmdb"."ownership_history" IS 'Propriétaires successifs | Catalogue: Un propriétaire principal à un instant ; transfert tracé.';

ALTER TABLE "cmdb"."ownership_history" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "cmdb"."ownership_history" FORCE ROW LEVEL SECURITY;

CREATE TRIGGER z_touch BEFORE UPDATE ON "cmdb"."ownership_history" FOR EACH ROW EXECUTE FUNCTION infrastructure.touch_row();

ALTER TABLE "cmdb"."ownership_history" ADD CONSTRAINT "c_9512ee6097312774423d" CHECK ("ends_at" > "starts_at");

CREATE TABLE "cmdb"."management_mandates" (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "item_id" uuid NOT NULL,
  "provider_org_id" uuid NOT NULL,
  "contract_id" uuid,
  "scope" text NOT NULL,
  "can_modify_inventory" boolean NOT NULL,
  "valid_from" timestamptz NOT NULL,
  "valid_to" timestamptz,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  row_version bigint NOT NULL DEFAULT 1 CHECK(row_version>0)
);

COMMENT ON TABLE "cmdb"."management_mandates" IS 'Mandats de gestion ou de support | Catalogue: Sans mandat : observation/support limité ; n’accorde pas un droit technique sur l’infrastructure.';

ALTER TABLE "cmdb"."management_mandates" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "cmdb"."management_mandates" FORCE ROW LEVEL SECURITY;

CREATE TRIGGER z_touch BEFORE UPDATE ON "cmdb"."management_mandates" FOR EACH ROW EXECUTE FUNCTION infrastructure.touch_row();

ALTER TABLE "cmdb"."management_mandates" ADD CONSTRAINT "c_21247b9b0610728cffce" CHECK ("valid_to" >= "valid_from");

CREATE TABLE "cmdb"."assignments" (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "item_id" uuid NOT NULL,
  "person_id" uuid,
  "team_id" uuid,
  "site_id" uuid,
  "starts_at" timestamptz NOT NULL,
  "ends_at" timestamptz,
  "kind" text NOT NULL,
  "acknowledged_at" timestamptz,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  row_version bigint NOT NULL DEFAULT 1 CHECK(row_version>0)
);

COMMENT ON TABLE "cmdb"."assignments" IS 'Affectation ou prêt d’un équipement | Catalogue: Cible selon kind ; exclusivité selon nature du matériel ; retour conservé.';

ALTER TABLE "cmdb"."assignments" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "cmdb"."assignments" FORCE ROW LEVEL SECURITY;

CREATE TRIGGER z_touch BEFORE UPDATE ON "cmdb"."assignments" FOR EACH ROW EXECUTE FUNCTION infrastructure.touch_row();

ALTER TABLE "cmdb"."assignments" ADD CONSTRAINT "c_8e8d36711f491159f276" CHECK (num_nonnulls(person_id,team_id,site_id)=1);

ALTER TABLE "cmdb"."assignments" ADD CONSTRAINT "c_e3d90ad3a86f40b67ad2" CHECK ("ends_at" > "starts_at");

CREATE TABLE "cmdb"."relations" (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "source_item_id" uuid NOT NULL,
  "target_item_id" uuid NOT NULL,
  "relation_type" text NOT NULL,
  "valid_from" timestamptz NOT NULL,
  "valid_to" timestamptz,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  row_version bigint NOT NULL DEFAULT 1 CHECK(row_version>0)
);

COMMENT ON TABLE "cmdb"."relations" IS 'Dépendances entre composants | Catalogue: Hébergé sur, connecté à, dépend de, sauvegardé par ; cycles permis seulement pour types adaptés.';

ALTER TABLE "cmdb"."relations" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "cmdb"."relations" FORCE ROW LEVEL SECURITY;

CREATE TRIGGER z_touch BEFORE UPDATE ON "cmdb"."relations" FOR EACH ROW EXECUTE FUNCTION infrastructure.touch_row();

ALTER TABLE "cmdb"."relations" ADD CONSTRAINT "c_34f395bd7b318d74d06b" CHECK (source_item_id <> target_item_id);

ALTER TABLE "cmdb"."relations" ADD CONSTRAINT "c_64caaed17d4823833146" CHECK ("valid_to" >= "valid_from");

CREATE TABLE "cmdb"."models" (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "manufacturer_org_id" uuid,
  "manufacturer_name" text NOT NULL,
  "model_name" text NOT NULL,
  "category" text NOT NULL,
  "end_of_sale_on" date,
  "end_of_support_on" date,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  row_version bigint NOT NULL DEFAULT 1 CHECK(row_version>0)
);

COMMENT ON TABLE "cmdb"."models" IS 'Marques et modèles | Catalogue: Référentiel distinct des exemplaires inventoriés.';

ALTER TABLE "cmdb"."models" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "cmdb"."models" FORCE ROW LEVEL SECURITY;

CREATE TRIGGER z_touch BEFORE UPDATE ON "cmdb"."models" FOR EACH ROW EXECUTE FUNCTION infrastructure.touch_row();

CREATE TABLE "cmdb"."hardware" (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "item_id" uuid NOT NULL,
  "model_id" uuid,
  "serial_number" text,
  "cpu_model" text,
  "memory_bytes" bigint,
  "purchase_on" date,
  "purchase_amount" numeric(20,6),
  "currency" text,
  "condition" text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  row_version bigint NOT NULL DEFAULT 1 CHECK(row_version>0)
);

COMMENT ON TABLE "cmdb"."hardware" IS 'Détails des équipements physiques | Catalogue: UNIQUE item ; spécifications complétées par composants enfants.';

ALTER TABLE "cmdb"."hardware" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "cmdb"."hardware" FORCE ROW LEVEL SECURITY;

CREATE TRIGGER z_touch BEFORE UPDATE ON "cmdb"."hardware" FOR EACH ROW EXECUTE FUNCTION infrastructure.touch_row();

ALTER TABLE "cmdb"."hardware" ADD CONSTRAINT "c_49cd2da11a174a15d089" CHECK ("memory_bytes" >= 0);

ALTER TABLE "cmdb"."hardware" ADD CONSTRAINT "c_b517eb40d3582259be87" CHECK ("purchase_amount" <> 'NaN'::numeric);

ALTER TABLE "cmdb"."hardware" ADD CONSTRAINT "c_8c5a057c2ff7e4d0c0bf" CHECK ("currency" ~ '^[A-Z]{3}$');

ALTER TABLE "cmdb"."hardware" ADD CONSTRAINT "c_c58da036c5179d864aca" UNIQUE NULLS NOT DISTINCT ("item_id");

CREATE TABLE "cmdb"."components" (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "parent_item_id" uuid NOT NULL,
  "child_item_id" uuid,
  "kind" text NOT NULL,
  "model" text,
  "serial_number" text,
  "capacity_bytes" bigint,
  "slot" text,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  row_version bigint NOT NULL DEFAULT 1 CHECK(row_version>0)
);

COMMENT ON TABLE "cmdb"."components" IS 'Disques, mémoire et composants remplaçables | Catalogue: Composant individuellement suivi ou simple caractéristique ; ne pas dédoubler le même disque.';

ALTER TABLE "cmdb"."components" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "cmdb"."components" FORCE ROW LEVEL SECURITY;

CREATE TRIGGER z_touch BEFORE UPDATE ON "cmdb"."components" FOR EACH ROW EXECUTE FUNCTION infrastructure.touch_row();

ALTER TABLE "cmdb"."components" ADD CONSTRAINT "c_0341db3512dc0147db3e" CHECK (parent_item_id <> child_item_id);

ALTER TABLE "cmdb"."components" ADD CONSTRAINT "c_7c2ae54dbb3308ef3af8" CHECK ("capacity_bytes" >= 0);

CREATE TABLE "cmdb"."os_installations" (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "item_id" uuid NOT NULL,
  "name" text NOT NULL,
  "version" text NOT NULL,
  "build" text,
  "installed_at" timestamptz,
  "last_seen_at" timestamptz NOT NULL,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  row_version bigint NOT NULL DEFAULT 1 CHECK(row_version>0)
);

COMMENT ON TABLE "cmdb"."os_installations" IS 'Systèmes d’exploitation observés | Catalogue: Historiser les versions ; fin de support associable.';

ALTER TABLE "cmdb"."os_installations" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "cmdb"."os_installations" FORCE ROW LEVEL SECURITY;

CREATE TRIGGER z_touch BEFORE UPDATE ON "cmdb"."os_installations" FOR EACH ROW EXECUTE FUNCTION infrastructure.touch_row();

CREATE TABLE "cmdb"."software_products" (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "publisher_org_id" uuid,
  "name" text NOT NULL,
  "edition" text,
  "licensing_metric" text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  row_version bigint NOT NULL DEFAULT 1 CHECK(row_version>0)
);

COMMENT ON TABLE "cmdb"."software_products" IS 'Catalogue logiciel | Catalogue: Produit distinct de version, installation et droit de licence.';

ALTER TABLE "cmdb"."software_products" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "cmdb"."software_products" FORCE ROW LEVEL SECURITY;

CREATE TRIGGER z_touch BEFORE UPDATE ON "cmdb"."software_products" FOR EACH ROW EXECUTE FUNCTION infrastructure.touch_row();

CREATE TABLE "cmdb"."software_versions" (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "product_id" uuid NOT NULL,
  "version" text NOT NULL,
  "release_on" date,
  "end_of_support_on" date,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  row_version bigint NOT NULL DEFAULT 1 CHECK(row_version>0)
);

COMMENT ON TABLE "cmdb"."software_versions" IS 'Versions logicielles | Catalogue: UNIQUE produit + version + édition si nécessaire.';

ALTER TABLE "cmdb"."software_versions" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "cmdb"."software_versions" FORCE ROW LEVEL SECURITY;

CREATE TRIGGER z_touch BEFORE UPDATE ON "cmdb"."software_versions" FOR EACH ROW EXECUTE FUNCTION infrastructure.touch_row();

ALTER TABLE "cmdb"."software_versions" ADD CONSTRAINT "c_a1d526cfdcc98d6eae88" UNIQUE NULLS NOT DISTINCT ("product_id", "version");

CREATE TABLE "cmdb"."software_installations" (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "item_id" uuid NOT NULL,
  "software_version_id" uuid NOT NULL,
  "installed_at" timestamptz,
  "last_seen_at" timestamptz NOT NULL,
  "removed_at" timestamptz,
  "source" text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  row_version bigint NOT NULL DEFAULT 1 CHECK(row_version>0)
);

COMMENT ON TABLE "cmdb"."software_installations" IS 'Installations détectées | Catalogue: Conserver disparition comme état à confirmer avant désinstallation déclarée.';

ALTER TABLE "cmdb"."software_installations" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "cmdb"."software_installations" FORCE ROW LEVEL SECURITY;

CREATE TRIGGER z_touch BEFORE UPDATE ON "cmdb"."software_installations" FOR EACH ROW EXECUTE FUNCTION infrastructure.touch_row();

CREATE TABLE "cmdb"."license_entitlements" (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "product_id" uuid NOT NULL,
  "owner_org_id" uuid NOT NULL,
  "contract_id" uuid,
  "quantity" numeric(20,6) NOT NULL,
  "metric" text NOT NULL,
  "starts_on" date NOT NULL,
  "ends_on" date,
  "secret_ref" text,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  row_version bigint NOT NULL DEFAULT 1 CHECK(row_version>0)
);

COMMENT ON TABLE "cmdb"."license_entitlements" IS 'Droits de licences détenus | Catalogue: Clés de licence sensibles dans coffre ; quantité non négative.';

ALTER TABLE "cmdb"."license_entitlements" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "cmdb"."license_entitlements" FORCE ROW LEVEL SECURITY;

CREATE TRIGGER z_touch BEFORE UPDATE ON "cmdb"."license_entitlements" FOR EACH ROW EXECUTE FUNCTION infrastructure.touch_row();

ALTER TABLE "cmdb"."license_entitlements" ADD CONSTRAINT "c_5145d34c7b8273eee1a2" CHECK ("quantity" <> 'NaN'::numeric);

ALTER TABLE "cmdb"."license_entitlements" ADD CONSTRAINT "c_c44b524933c73f3fc7ea" CHECK ("quantity" >= 0);

ALTER TABLE "cmdb"."license_entitlements" ADD CONSTRAINT "c_8564c50d1d1f1ccbf47d" CHECK ("ends_on" >= "starts_on");

CREATE TABLE "cmdb"."license_allocations" (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "entitlement_id" uuid NOT NULL,
  "person_id" uuid,
  "item_id" uuid,
  "quantity" numeric(20,6) NOT NULL,
  "starts_at" timestamptz NOT NULL,
  "ends_at" timestamptz,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  row_version bigint NOT NULL DEFAULT 1 CHECK(row_version>0)
);

COMMENT ON TABLE "cmdb"."license_allocations" IS 'Consommation des droits de licence | Catalogue: Une cible selon métrique ; surallocation signalée, calcul par période.';

ALTER TABLE "cmdb"."license_allocations" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "cmdb"."license_allocations" FORCE ROW LEVEL SECURITY;

CREATE TRIGGER z_touch BEFORE UPDATE ON "cmdb"."license_allocations" FOR EACH ROW EXECUTE FUNCTION infrastructure.touch_row();

ALTER TABLE "cmdb"."license_allocations" ADD CONSTRAINT "c_18da0be7fa46b41788a8" CHECK (num_nonnulls(person_id,item_id)=1);

ALTER TABLE "cmdb"."license_allocations" ADD CONSTRAINT "c_071fc85b4729c453fe7c" CHECK ("quantity" <> 'NaN'::numeric);

ALTER TABLE "cmdb"."license_allocations" ADD CONSTRAINT "c_5f7aa3952e51636beefe" CHECK ("quantity" >= 0);

ALTER TABLE "cmdb"."license_allocations" ADD CONSTRAINT "c_35df1367041864b91c11" CHECK ("ends_at" > "starts_at");

CREATE TABLE "cmdb"."network_interfaces" (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "item_id" uuid NOT NULL,
  "name" text NOT NULL,
  "mac_address" text,
  "kind" text NOT NULL,
  "speed_bps" bigint,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  row_version bigint NOT NULL DEFAULT 1 CHECK(row_version>0)
);

COMMENT ON TABLE "cmdb"."network_interfaces" IS 'Cartes réseau et interfaces | Catalogue: MAC pas identité universelle d’un actif ; interfaces virtuelles prévues.';

ALTER TABLE "cmdb"."network_interfaces" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "cmdb"."network_interfaces" FORCE ROW LEVEL SECURITY;

CREATE TRIGGER z_touch BEFORE UPDATE ON "cmdb"."network_interfaces" FOR EACH ROW EXECUTE FUNCTION infrastructure.touch_row();

ALTER TABLE "cmdb"."network_interfaces" ADD CONSTRAINT "c_bddd7af4e3033f0329ed" UNIQUE NULLS NOT DISTINCT ("item_id", "name");

CREATE TABLE "cmdb"."network_segments" (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "owner_org_id" uuid NOT NULL,
  "site_id" uuid,
  "name" text NOT NULL,
  "cidr" cidr,
  "vlan" integer,
  "routing_domain" text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  row_version bigint NOT NULL DEFAULT 1 CHECK(row_version>0)
);

COMMENT ON TABLE "cmdb"."network_segments" IS 'Réseaux et sous-réseaux | Catalogue: Sous-réseaux privés identiques possibles chez différents clients ; VLAN encadré.';

ALTER TABLE "cmdb"."network_segments" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "cmdb"."network_segments" FORCE ROW LEVEL SECURITY;

CREATE TRIGGER z_touch BEFORE UPDATE ON "cmdb"."network_segments" FOR EACH ROW EXECUTE FUNCTION infrastructure.touch_row();

ALTER TABLE "cmdb"."network_segments" ADD CONSTRAINT "c_3d0136aa315042e5cce8" CHECK (vlan BETWEEN 1 AND 4094);

CREATE TABLE "cmdb"."ip_assignments" (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "interface_id" uuid NOT NULL,
  "segment_id" uuid NOT NULL,
  "address" inet NOT NULL,
  "assignment_kind" text NOT NULL,
  "starts_at" timestamptz NOT NULL,
  "ends_at" timestamptz,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  row_version bigint NOT NULL DEFAULT 1 CHECK(row_version>0)
);

COMMENT ON TABLE "cmdb"."ip_assignments" IS 'Adresses et historique réseau | Catalogue: Unicité temporelle dans le domaine réseau, pas globale.';

ALTER TABLE "cmdb"."ip_assignments" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "cmdb"."ip_assignments" FORCE ROW LEVEL SECURITY;

CREATE TRIGGER z_touch BEFORE UPDATE ON "cmdb"."ip_assignments" FOR EACH ROW EXECUTE FUNCTION infrastructure.touch_row();

ALTER TABLE "cmdb"."ip_assignments" ADD CONSTRAINT "c_e7640d77860e7d21b0bd" CHECK ("ends_at" > "starts_at");

CREATE TABLE "cmdb"."network_links" (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "from_interface_id" uuid NOT NULL,
  "to_interface_id" uuid NOT NULL,
  "kind" text NOT NULL,
  "label" text,
  "active" boolean NOT NULL,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  row_version bigint NOT NULL DEFAULT 1 CHECK(row_version>0)
);

COMMENT ON TABLE "cmdb"."network_links" IS 'Connexions physiques ou logiques | Catalogue: Empêcher doublons symétriques pour liens non orientés.';

ALTER TABLE "cmdb"."network_links" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "cmdb"."network_links" FORCE ROW LEVEL SECURITY;

CREATE TRIGGER z_touch BEFORE UPDATE ON "cmdb"."network_links" FOR EACH ROW EXECUTE FUNCTION infrastructure.touch_row();

ALTER TABLE "cmdb"."network_links" ADD CONSTRAINT "c_e3096b769d366ab0d886" CHECK (from_interface_id <> to_interface_id);

CREATE TABLE "cmdb"."domains" (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "item_id" uuid NOT NULL,
  "fqdn" text NOT NULL,
  "registrar_org_id" uuid,
  "registered_on" date,
  "expires_on" date,
  "auto_renew" boolean NOT NULL,
  "secret_ref" text,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  row_version bigint NOT NULL DEFAULT 1 CHECK(row_version>0)
);

COMMENT ON TABLE "cmdb"."domains" IS 'Noms de domaine | Catalogue: UNIQUE item ; nom normalisé ; alertes de renouvellement.';

ALTER TABLE "cmdb"."domains" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "cmdb"."domains" FORCE ROW LEVEL SECURITY;

CREATE TRIGGER z_touch BEFORE UPDATE ON "cmdb"."domains" FOR EACH ROW EXECUTE FUNCTION infrastructure.touch_row();

ALTER TABLE "cmdb"."domains" ADD CONSTRAINT "c_ad3a8ec2ba65d18e891d" UNIQUE NULLS NOT DISTINCT ("item_id");

ALTER TABLE "cmdb"."domains" ADD CONSTRAINT "c_77fec65688dc75e8a12f" UNIQUE NULLS NOT DISTINCT ("fqdn");

CREATE TABLE "cmdb"."dns_records" (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "domain_id" uuid NOT NULL,
  "name" text NOT NULL,
  "record_type" text NOT NULL,
  "value" text NOT NULL,
  "ttl_seconds" integer NOT NULL,
  "source" text NOT NULL,
  "observed_at" timestamptz NOT NULL,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  row_version bigint NOT NULL DEFAULT 1 CHECK(row_version>0)
);

COMMENT ON TABLE "cmdb"."dns_records" IS 'Enregistrements DNS suivis | Catalogue: Inventaire n’implique pas droit d’écriture DNS ; historique de changement.';

ALTER TABLE "cmdb"."dns_records" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "cmdb"."dns_records" FORCE ROW LEVEL SECURITY;

CREATE TRIGGER z_touch BEFORE UPDATE ON "cmdb"."dns_records" FOR EACH ROW EXECUTE FUNCTION infrastructure.touch_row();

ALTER TABLE "cmdb"."dns_records" ADD CONSTRAINT "c_b8f0394acf0a8cf02897" CHECK ("ttl_seconds" >= 0);

CREATE TABLE "cmdb"."certificates" (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "item_id" uuid NOT NULL,
  "fingerprint" text NOT NULL,
  "issuer" text NOT NULL,
  "subject" text NOT NULL,
  "valid_from" timestamptz NOT NULL,
  "valid_to" timestamptz NOT NULL,
  "private_key_ref" text,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  row_version bigint NOT NULL DEFAULT 1 CHECK(row_version>0)
);

COMMENT ON TABLE "cmdb"."certificates" IS 'Certificats et échéances | Catalogue: Clé privée exclusivement dans coffre ; empreinte unique dans son contexte.';

ALTER TABLE "cmdb"."certificates" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "cmdb"."certificates" FORCE ROW LEVEL SECURITY;

CREATE TRIGGER z_touch BEFORE UPDATE ON "cmdb"."certificates" FOR EACH ROW EXECUTE FUNCTION infrastructure.touch_row();

ALTER TABLE "cmdb"."certificates" ADD CONSTRAINT "c_d0ce118218f673aea543" CHECK ("valid_to" >= "valid_from");

ALTER TABLE "cmdb"."certificates" ADD CONSTRAINT "c_8f5be4a7f2160f7004fa" UNIQUE NULLS NOT DISTINCT ("item_id", "fingerprint");

CREATE TABLE "cmdb"."cloud_accounts" (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "item_id" uuid NOT NULL,
  "provider" text NOT NULL,
  "external_account_id" text NOT NULL,
  "region" text,
  "billing_owner_org_id" uuid NOT NULL,
  "secret_ref" text,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  row_version bigint NOT NULL DEFAULT 1 CHECK(row_version>0)
);

COMMENT ON TABLE "cmdb"."cloud_accounts" IS 'Comptes cloud et abonnements | Catalogue: Compte distinct des ressources qu’il héberge.';

ALTER TABLE "cmdb"."cloud_accounts" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "cmdb"."cloud_accounts" FORCE ROW LEVEL SECURITY;

CREATE TRIGGER z_touch BEFORE UPDATE ON "cmdb"."cloud_accounts" FOR EACH ROW EXECUTE FUNCTION infrastructure.touch_row();

ALTER TABLE "cmdb"."cloud_accounts" ADD CONSTRAINT "c_f3821f2912e8ae71811e" UNIQUE NULLS NOT DISTINCT ("provider", "external_account_id");

CREATE TABLE "cmdb"."cloud_resources" (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "item_id" uuid NOT NULL,
  "cloud_account_id" uuid,
  "external_resource_id" text NOT NULL,
  "resource_kind" text NOT NULL,
  "region" text,
  "specification" jsonb NOT NULL,
  "last_seen_at" timestamptz NOT NULL,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  row_version bigint NOT NULL DEFAULT 1 CHECK(row_version>0)
);

COMMENT ON TABLE "cmdb"."cloud_resources" IS 'Ressources cloud et virtualisation | Catalogue: Identifiant unique par fournisseur/compte ; détails typés dans specification.';

ALTER TABLE "cmdb"."cloud_resources" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "cmdb"."cloud_resources" FORCE ROW LEVEL SECURITY;

CREATE TRIGGER z_touch BEFORE UPDATE ON "cmdb"."cloud_resources" FOR EACH ROW EXECUTE FUNCTION infrastructure.touch_row();

ALTER TABLE "cmdb"."cloud_resources" ADD CONSTRAINT "c_f3a12d50bbc49bca21f9" UNIQUE NULLS NOT DISTINCT ("cloud_account_id", "external_resource_id");

CREATE TABLE "cmdb"."hosting_services" (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "item_id" uuid NOT NULL,
  "provider_org_id" uuid,
  "environment" text NOT NULL,
  "endpoint" text,
  "runtime" text,
  "backup_policy_id" uuid,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  row_version bigint NOT NULL DEFAULT 1 CHECK(row_version>0)
);

COMMENT ON TABLE "cmdb"."hosting_services" IS 'Hébergements et sites maintenus | Catalogue: Production/test distincts ; lier domaines, certificats et serveurs par relations.';

ALTER TABLE "cmdb"."hosting_services" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "cmdb"."hosting_services" FORCE ROW LEVEL SECURITY;

CREATE TRIGGER z_touch BEFORE UPDATE ON "cmdb"."hosting_services" FOR EACH ROW EXECUTE FUNCTION infrastructure.touch_row();

ALTER TABLE "cmdb"."hosting_services" ADD CONSTRAINT "c_b4a35114bb42e10e6833" UNIQUE NULLS NOT DISTINCT ("item_id");

CREATE TABLE "cmdb"."backup_policies" (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "code" text NOT NULL,
  "name" text NOT NULL,
  "frequency" text NOT NULL,
  "retention_days" integer NOT NULL,
  "target_rpo_minutes" integer,
  "target_rto_minutes" integer,
  "storage_ref" text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  row_version bigint NOT NULL DEFAULT 1 CHECK(row_version>0)
);

COMMENT ON TABLE "cmdb"."backup_policies" IS 'Politiques de sauvegarde des actifs | Catalogue: Décrit les actifs clients ; distinct des sauvegardes des bases ITSM de plateforme.';

ALTER TABLE "cmdb"."backup_policies" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "cmdb"."backup_policies" FORCE ROW LEVEL SECURITY;

CREATE TRIGGER z_touch BEFORE UPDATE ON "cmdb"."backup_policies" FOR EACH ROW EXECUTE FUNCTION infrastructure.touch_row();

ALTER TABLE "cmdb"."backup_policies" ADD CONSTRAINT "c_94865be86f9d5ac0baad" CHECK ("target_rpo_minutes" >= 0);

ALTER TABLE "cmdb"."backup_policies" ADD CONSTRAINT "c_db3a526bd0e7e25e64f8" CHECK ("target_rto_minutes" >= 0);

ALTER TABLE "cmdb"."backup_policies" ADD CONSTRAINT "c_c9b987bd11823cb45ae9" UNIQUE NULLS NOT DISTINCT ("code");

CREATE TABLE "cmdb"."backup_checks" (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "item_id" uuid NOT NULL,
  "policy_id" uuid NOT NULL,
  "checked_at" timestamptz NOT NULL,
  "kind" text NOT NULL,
  "result" text NOT NULL,
  "evidence_ref" text,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  row_version bigint NOT NULL DEFAULT 1 CHECK(row_version>0)
);

COMMENT ON TABLE "cmdb"."backup_checks" IS 'Résultats et tests de restauration | Catalogue: Une sauvegarde réussie n’est pas un test de restauration.';

ALTER TABLE "cmdb"."backup_checks" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "cmdb"."backup_checks" FORCE ROW LEVEL SECURITY;

CREATE TRIGGER z_touch BEFORE UPDATE ON "cmdb"."backup_checks" FOR EACH ROW EXECUTE FUNCTION infrastructure.touch_row();

CREATE TABLE "cmdb"."technical_accounts" (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "item_id" uuid NOT NULL,
  "owner_person_id" uuid,
  "login_label" text NOT NULL,
  "purpose" text NOT NULL,
  "privilege_level" text NOT NULL,
  "secret_ref" text,
  "expires_at" timestamptz,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  row_version bigint NOT NULL DEFAULT 1 CHECK(row_version>0)
);

COMMENT ON TABLE "cmdb"."technical_accounts" IS 'Comptes techniques inventoriés | Catalogue: Pas de mot de passe dans les fiches, tickets ou exports ; revue des accès.';

ALTER TABLE "cmdb"."technical_accounts" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "cmdb"."technical_accounts" FORCE ROW LEVEL SECURITY;

CREATE TRIGGER z_touch BEFORE UPDATE ON "cmdb"."technical_accounts" FOR EACH ROW EXECUTE FUNCTION infrastructure.touch_row();

CREATE TABLE "cmdb"."item_observations" (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "item_id" uuid NOT NULL,
  "connection_id" uuid,
  "observed_at" timestamptz NOT NULL,
  "attribute_key" text NOT NULL,
  "value" jsonb NOT NULL,
  "confidence" numeric(20,6) NOT NULL,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  row_version bigint NOT NULL DEFAULT 1 CHECK(row_version>0)
);

COMMENT ON TABLE "cmdb"."item_observations" IS 'Valeurs et provenance inventoriées | Catalogue: Observation distincte de valeur de référence ; arbitrage par autorité de champ.';

ALTER TABLE "cmdb"."item_observations" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "cmdb"."item_observations" FORCE ROW LEVEL SECURITY;

CREATE TRIGGER z_touch BEFORE UPDATE ON "cmdb"."item_observations" FOR EACH ROW EXECUTE FUNCTION infrastructure.touch_row();

ALTER TABLE "cmdb"."item_observations" ADD CONSTRAINT "c_58228154d6dae0d7dc05" CHECK ("confidence" <> 'NaN'::numeric);

ALTER TABLE "cmdb"."item_observations" ADD CONSTRAINT "c_f8dcc4f3b9e4a2a9b8f2" CHECK ("confidence" BETWEEN 0 AND 1);

CREATE TABLE "inventory"."warehouses" (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "organization_id" uuid NOT NULL,
  "location_id" uuid,
  "code" text NOT NULL,
  "name" text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  row_version bigint NOT NULL DEFAULT 1 CHECK(row_version>0)
);

COMMENT ON TABLE "inventory"."warehouses" IS 'Réserves et lieux de stockage | Catalogue: Stock détenu distinct du stock appartenant à autrui.';

ALTER TABLE "inventory"."warehouses" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "inventory"."warehouses" FORCE ROW LEVEL SECURITY;

CREATE TRIGGER z_touch BEFORE UPDATE ON "inventory"."warehouses" FOR EACH ROW EXECUTE FUNCTION infrastructure.touch_row();

ALTER TABLE "inventory"."warehouses" ADD CONSTRAINT "c_85fb871f0024031da9a6" UNIQUE NULLS NOT DISTINCT ("organization_id", "code");

CREATE TABLE "inventory"."stock_products" (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "sku" text NOT NULL,
  "name" text NOT NULL,
  "model_id" uuid,
  "unit" text NOT NULL,
  "serialized" boolean NOT NULL,
  "reorder_threshold" numeric(20,6),
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  row_version bigint NOT NULL DEFAULT 1 CHECK(row_version>0)
);

COMMENT ON TABLE "inventory"."stock_products" IS 'Références de matériel et consommables | Catalogue: Exemplaires sérialisés dans cmdb.items ; consommables en quantité.';

ALTER TABLE "inventory"."stock_products" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "inventory"."stock_products" FORCE ROW LEVEL SECURITY;

CREATE TRIGGER z_touch BEFORE UPDATE ON "inventory"."stock_products" FOR EACH ROW EXECUTE FUNCTION infrastructure.touch_row();

ALTER TABLE "inventory"."stock_products" ADD CONSTRAINT "c_0e658625dbd973e814e8" CHECK ("reorder_threshold" <> 'NaN'::numeric);

ALTER TABLE "inventory"."stock_products" ADD CONSTRAINT "c_a74e88320afbcd4bdea9" CHECK ("reorder_threshold" >= 0);

ALTER TABLE "inventory"."stock_products" ADD CONSTRAINT "c_17b41c700f1eca263613" UNIQUE NULLS NOT DISTINCT ("sku");

CREATE TABLE "inventory"."stock_movements" (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "product_id" uuid NOT NULL,
  "item_id" uuid,
  "warehouse_id" uuid NOT NULL,
  "quantity_delta" numeric(20,6) NOT NULL,
  "occurred_at" timestamptz NOT NULL,
  "reason" text NOT NULL,
  "transfer_key" text,
  "owner_org_id" uuid NOT NULL,
  "reversal_of_id" uuid,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  row_version bigint NOT NULL DEFAULT 1 CHECK(row_version>0)
);

COMMENT ON TABLE "inventory"."stock_movements" IS 'Entrées, sorties et transferts | Catalogue: Stock calculé par journal ; transfert en deux mouvements atomiques ; correction compensatoire.';

ALTER TABLE "inventory"."stock_movements" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "inventory"."stock_movements" FORCE ROW LEVEL SECURITY;

CREATE TRIGGER z_touch BEFORE UPDATE ON "inventory"."stock_movements" FOR EACH ROW EXECUTE FUNCTION infrastructure.touch_row();

CREATE TRIGGER a_immutable BEFORE UPDATE OR DELETE ON "inventory"."stock_movements" FOR EACH ROW EXECUTE FUNCTION infrastructure.reject_mutation();
CREATE TRIGGER a_no_truncate BEFORE TRUNCATE ON "inventory"."stock_movements" FOR EACH STATEMENT EXECUTE FUNCTION infrastructure.reject_mutation();

ALTER TABLE "inventory"."stock_movements" ADD CONSTRAINT "c_694198c34c62f0dfa584" CHECK ("quantity_delta" <> 'NaN'::numeric);

ALTER TABLE "inventory"."stock_movements" ADD CONSTRAINT "c_cef9dd923a4e0428e36b" CHECK ("reversal_of_id" <> id);

CREATE TABLE "inventory"."stock_reservations" (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "product_id" uuid NOT NULL,
  "warehouse_id" uuid NOT NULL,
  "ticket_id" uuid,
  "quantity" numeric(20,6) NOT NULL,
  "expires_at" timestamptz,
  "status" text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  row_version bigint NOT NULL DEFAULT 1 CHECK(row_version>0)
);

COMMENT ON TABLE "inventory"."stock_reservations" IS 'Matériel réservé | Catalogue: Réservation atomique ; empêcher sur-réservation selon politique.';

ALTER TABLE "inventory"."stock_reservations" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "inventory"."stock_reservations" FORCE ROW LEVEL SECURITY;

CREATE TRIGGER z_touch BEFORE UPDATE ON "inventory"."stock_reservations" FOR EACH ROW EXECUTE FUNCTION infrastructure.touch_row();

ALTER TABLE "inventory"."stock_reservations" ADD CONSTRAINT "c_b7e1894863feea482d07" CHECK ("quantity" <> 'NaN'::numeric);

ALTER TABLE "inventory"."stock_reservations" ADD CONSTRAINT "c_bda638d7caeaf8268011" CHECK ("quantity" >= 0);

CREATE TABLE "inventory"."purchase_orders" (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "supplier_org_id" uuid NOT NULL,
  "buyer_org_id" uuid NOT NULL,
  "number" text NOT NULL,
  "status" text NOT NULL,
  "ordered_on" date,
  "currency" text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  row_version bigint NOT NULL DEFAULT 1 CHECK(row_version>0)
);

COMMENT ON TABLE "inventory"."purchase_orders" IS 'Commandes fournisseur | Catalogue: Numéro unique par acheteur ; approbation avant engagement selon règles.';

ALTER TABLE "inventory"."purchase_orders" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "inventory"."purchase_orders" FORCE ROW LEVEL SECURITY;

CREATE TRIGGER z_touch BEFORE UPDATE ON "inventory"."purchase_orders" FOR EACH ROW EXECUTE FUNCTION infrastructure.touch_row();

ALTER TABLE "inventory"."purchase_orders" ADD CONSTRAINT "c_12dafa84c36af917ea55" CHECK ("currency" ~ '^[A-Z]{3}$');

ALTER TABLE "inventory"."purchase_orders" ADD CONSTRAINT "c_8f23d4c997f6fa6ddede" UNIQUE NULLS NOT DISTINCT ("buyer_org_id", "number");

CREATE TABLE "inventory"."purchase_lines" (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "order_id" uuid NOT NULL,
  "product_id" uuid,
  "description" text NOT NULL,
  "quantity" numeric(20,6) NOT NULL,
  "unit_price" numeric(20,6) NOT NULL,
  "expected_on" date,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  row_version bigint NOT NULL DEFAULT 1 CHECK(row_version>0)
);

COMMENT ON TABLE "inventory"."purchase_lines" IS 'Lignes d’achat | Catalogue: Réceptions partielles possibles.';

ALTER TABLE "inventory"."purchase_lines" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "inventory"."purchase_lines" FORCE ROW LEVEL SECURITY;

CREATE TRIGGER z_touch BEFORE UPDATE ON "inventory"."purchase_lines" FOR EACH ROW EXECUTE FUNCTION infrastructure.touch_row();

ALTER TABLE "inventory"."purchase_lines" ADD CONSTRAINT "c_3525b57c0e6ed9ec3bec" CHECK ("quantity" <> 'NaN'::numeric);

ALTER TABLE "inventory"."purchase_lines" ADD CONSTRAINT "c_d2eb49708460d798b6fc" CHECK ("quantity" >= 0);

ALTER TABLE "inventory"."purchase_lines" ADD CONSTRAINT "c_a80e6b6aa84fdf24862e" CHECK ("unit_price" <> 'NaN'::numeric);

ALTER TABLE "inventory"."purchase_lines" ADD CONSTRAINT "c_65d39e424cbc6a94fd20" CHECK ("unit_price" >= 0);

CREATE TABLE "inventory"."receipts" (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "order_id" uuid NOT NULL,
  "received_at" timestamptz NOT NULL,
  "received_by" uuid NOT NULL,
  "warehouse_id" uuid NOT NULL,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  row_version bigint NOT NULL DEFAULT 1 CHECK(row_version>0)
);

COMMENT ON TABLE "inventory"."receipts" IS 'Réceptions de commande | Catalogue: Événement de réception, pas écrasement de quantité commandée.';

ALTER TABLE "inventory"."receipts" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "inventory"."receipts" FORCE ROW LEVEL SECURITY;

CREATE TRIGGER z_touch BEFORE UPDATE ON "inventory"."receipts" FOR EACH ROW EXECUTE FUNCTION infrastructure.touch_row();

CREATE TABLE "inventory"."receipt_lines" (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "receipt_id" uuid NOT NULL,
  "purchase_line_id" uuid NOT NULL,
  "quantity" numeric(20,6) NOT NULL,
  "item_id" uuid,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  row_version bigint NOT NULL DEFAULT 1 CHECK(row_version>0)
);

COMMENT ON TABLE "inventory"."receipt_lines" IS 'Matériel effectivement reçu | Catalogue: Cohérence commande ; exemplaire individualisé si sérialisé.';

ALTER TABLE "inventory"."receipt_lines" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "inventory"."receipt_lines" FORCE ROW LEVEL SECURITY;

CREATE TRIGGER z_touch BEFORE UPDATE ON "inventory"."receipt_lines" FOR EACH ROW EXECUTE FUNCTION infrastructure.touch_row();

ALTER TABLE "inventory"."receipt_lines" ADD CONSTRAINT "c_98434f6e661e26b5f861" CHECK ("quantity" <> 'NaN'::numeric);

ALTER TABLE "inventory"."receipt_lines" ADD CONSTRAINT "c_d20382e632963c90c921" CHECK ("quantity" >= 0);

CREATE TABLE "inventory"."warranties" (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "item_id" uuid NOT NULL,
  "provider_org_id" uuid NOT NULL,
  "reference" text,
  "starts_on" date NOT NULL,
  "ends_on" date NOT NULL,
  "terms" text,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  row_version bigint NOT NULL DEFAULT 1 CHECK(row_version>0)
);

COMMENT ON TABLE "inventory"."warranties" IS 'Garanties et extensions | Catalogue: Plusieurs couvertures possibles ; dates cohérentes.';

ALTER TABLE "inventory"."warranties" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "inventory"."warranties" FORCE ROW LEVEL SECURITY;

CREATE TRIGGER z_touch BEFORE UPDATE ON "inventory"."warranties" FOR EACH ROW EXECUTE FUNCTION infrastructure.touch_row();

ALTER TABLE "inventory"."warranties" ADD CONSTRAINT "c_7140f1fc94424391c469" CHECK ("ends_on" >= "starts_on");

CREATE TABLE "inventory"."repairs" (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "item_id" uuid NOT NULL,
  "ticket_id" uuid,
  "supplier_org_id" uuid,
  "rma_number" text,
  "status" text NOT NULL,
  "sent_at" timestamptz,
  "returned_at" timestamptz,
  "cost" numeric(20,6),
  "currency" text,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  row_version bigint NOT NULL DEFAULT 1 CHECK(row_version>0)
);

COMMENT ON TABLE "inventory"."repairs" IS 'Réparations et retours fournisseur | Catalogue: Localisation et disponibilité mises à jour avec le mouvement.';

ALTER TABLE "inventory"."repairs" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "inventory"."repairs" FORCE ROW LEVEL SECURITY;

CREATE TRIGGER z_touch BEFORE UPDATE ON "inventory"."repairs" FOR EACH ROW EXECUTE FUNCTION infrastructure.touch_row();

ALTER TABLE "inventory"."repairs" ADD CONSTRAINT "c_628af277ce26dcba73db" CHECK ("cost" <> 'NaN'::numeric);

ALTER TABLE "inventory"."repairs" ADD CONSTRAINT "c_78630bd921bd7ffa36c6" CHECK ("currency" ~ '^[A-Z]{3}$');

CREATE TABLE "inventory"."loans" (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "item_id" uuid NOT NULL,
  "borrower_org_id" uuid NOT NULL,
  "person_id" uuid,
  "contract_id" uuid,
  "starts_at" timestamptz NOT NULL,
  "due_at" timestamptz NOT NULL,
  "returned_at" timestamptz,
  "condition_out" text NOT NULL,
  "condition_in" text,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  row_version bigint NOT NULL DEFAULT 1 CHECK(row_version>0)
);

COMMENT ON TABLE "inventory"."loans" IS 'Prêts et locations de matériel | Catalogue: Propriété inchangée ; pas de prêt actif incompatible.';

ALTER TABLE "inventory"."loans" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "inventory"."loans" FORCE ROW LEVEL SECURITY;

CREATE TRIGGER z_touch BEFORE UPDATE ON "inventory"."loans" FOR EACH ROW EXECUTE FUNCTION infrastructure.touch_row();

CREATE TABLE "inventory"."stock_counts" (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "warehouse_id" uuid NOT NULL,
  "started_at" timestamptz NOT NULL,
  "closed_at" timestamptz,
  "status" text NOT NULL,
  "approved_by" uuid,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  row_version bigint NOT NULL DEFAULT 1 CHECK(row_version>0)
);

COMMENT ON TABLE "inventory"."stock_counts" IS 'Campagnes d’inventaire physique | Catalogue: Écarts approuvés avant création des ajustements.';

ALTER TABLE "inventory"."stock_counts" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "inventory"."stock_counts" FORCE ROW LEVEL SECURITY;

CREATE TRIGGER z_touch BEFORE UPDATE ON "inventory"."stock_counts" FOR EACH ROW EXECUTE FUNCTION infrastructure.touch_row();

CREATE TABLE "inventory"."stock_count_lines" (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "count_id" uuid NOT NULL,
  "product_id" uuid NOT NULL,
  "expected_quantity" numeric(20,6) NOT NULL,
  "counted_quantity" numeric(20,6) NOT NULL,
  "item_id" uuid,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  row_version bigint NOT NULL DEFAULT 1 CHECK(row_version>0)
);

COMMENT ON TABLE "inventory"."stock_count_lines" IS 'Quantités comptées | Catalogue: Photographie du stock au démarrage ; justification des écarts.';

ALTER TABLE "inventory"."stock_count_lines" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "inventory"."stock_count_lines" FORCE ROW LEVEL SECURITY;

CREATE TRIGGER z_touch BEFORE UPDATE ON "inventory"."stock_count_lines" FOR EACH ROW EXECUTE FUNCTION infrastructure.touch_row();

ALTER TABLE "inventory"."stock_count_lines" ADD CONSTRAINT "c_0ec7f180f34994015307" CHECK ("expected_quantity" <> 'NaN'::numeric);

ALTER TABLE "inventory"."stock_count_lines" ADD CONSTRAINT "c_e85120450b4c371cc360" CHECK ("counted_quantity" <> 'NaN'::numeric);

ALTER TABLE "inventory"."stock_count_lines" ADD CONSTRAINT "c_35fb1f258184267126ed" CHECK ("counted_quantity" >= 0);

ALTER TABLE "inventory"."stock_count_lines" ADD CONSTRAINT "c_42a567e311187d5d7023" UNIQUE NULLS NOT DISTINCT ("count_id", "product_id", "item_id");

CREATE TABLE "inventory"."disposals" (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "item_id" uuid NOT NULL,
  "reason" text NOT NULL,
  "disposed_on" date NOT NULL,
  "approved_by" uuid NOT NULL,
  "erasure_evidence_id" uuid,
  "recipient_org_id" uuid,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  row_version bigint NOT NULL DEFAULT 1 CHECK(row_version>0)
);

COMMENT ON TABLE "inventory"."disposals" IS 'Sorties définitives et effacement | Catalogue: Conserver historique et preuve ; ne pas supprimer l’actif lié à des tickets.';

ALTER TABLE "inventory"."disposals" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "inventory"."disposals" FORCE ROW LEVEL SECURITY;

CREATE TRIGGER z_touch BEFORE UPDATE ON "inventory"."disposals" FOR EACH ROW EXECUTE FUNCTION infrastructure.touch_row();

ALTER TABLE "inventory"."disposals" ADD CONSTRAINT "c_41e453ab0f2c36507011" UNIQUE NULLS NOT DISTINCT ("item_id");

CREATE TABLE "commercial"."products" (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "sku" text NOT NULL,
  "name" text NOT NULL,
  "kind" text NOT NULL,
  "unit" text NOT NULL,
  "active" boolean NOT NULL,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  row_version bigint NOT NULL DEFAULT 1 CHECK(row_version>0)
);

COMMENT ON TABLE "commercial"."products" IS 'Catalogue de prestations et produits | Catalogue: Unité explicite : heure, minute, intervention, mois, matériel.';

ALTER TABLE "commercial"."products" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "commercial"."products" FORCE ROW LEVEL SECURITY;

CREATE TRIGGER z_touch BEFORE UPDATE ON "commercial"."products" FOR EACH ROW EXECUTE FUNCTION infrastructure.touch_row();

ALTER TABLE "commercial"."products" ADD CONSTRAINT "c_66e26091e21ff39454f0" UNIQUE NULLS NOT DISTINCT ("sku");

CREATE TABLE "commercial"."contracts" (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "number" text NOT NULL,
  "provider_org_id" uuid NOT NULL,
  "signatory_org_id" uuid NOT NULL,
  "name" text NOT NULL,
  "status" text NOT NULL,
  "starts_on" date NOT NULL,
  "ends_on" date,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  row_version bigint NOT NULL DEFAULT 1 CHECK(row_version>0)
);

COMMENT ON TABLE "commercial"."contracts" IS 'Identité du contrat | Catalogue: Numéro unique par fournisseur ; groupe signataire distinct des sociétés couvertes.';

ALTER TABLE "commercial"."contracts" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "commercial"."contracts" FORCE ROW LEVEL SECURITY;

CREATE TRIGGER z_touch BEFORE UPDATE ON "commercial"."contracts" FOR EACH ROW EXECUTE FUNCTION infrastructure.touch_row();

ALTER TABLE "commercial"."contracts" ADD CONSTRAINT "c_280596eb03e111b07df1" CHECK ("ends_on" >= "starts_on");

ALTER TABLE "commercial"."contracts" ADD CONSTRAINT "c_7d00b69a2725107fb07e" UNIQUE NULLS NOT DISTINCT ("provider_org_id", "number");

CREATE TABLE "commercial"."contract_versions" (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "contract_id" uuid NOT NULL,
  "version_no" integer NOT NULL,
  "effective_from" timestamptz NOT NULL,
  "effective_to" timestamptz,
  "currency" text NOT NULL,
  "terms_file_id" uuid,
  "signed_at" timestamptz,
  "external_source_ref" text,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  row_version bigint NOT NULL DEFAULT 1 CHECK(row_version>0)
);

COMMENT ON TABLE "commercial"."contract_versions" IS 'Conditions contractuelles datées | Catalogue: Pas de réécriture d’une version ayant servi à valoriser une activité.';

ALTER TABLE "commercial"."contract_versions" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "commercial"."contract_versions" FORCE ROW LEVEL SECURITY;

CREATE TRIGGER z_touch BEFORE UPDATE ON "commercial"."contract_versions" FOR EACH ROW EXECUTE FUNCTION infrastructure.touch_row();

ALTER TABLE "commercial"."contract_versions" ADD CONSTRAINT "c_117cdf7c1db011e5fd16" CHECK ("version_no" > 0);

ALTER TABLE "commercial"."contract_versions" ADD CONSTRAINT "c_adfa0a6fee3223b8d42c" CHECK ("currency" ~ '^[A-Z]{3}$');

ALTER TABLE "commercial"."contract_versions" ADD CONSTRAINT "c_bf308521e0345ebcc372" CHECK ("effective_to" >= "effective_from");

ALTER TABLE "commercial"."contract_versions" ADD CONSTRAINT "c_182237e47a3ea847e07e" UNIQUE NULLS NOT DISTINCT ("contract_id", "version_no");

CREATE TABLE "commercial"."contract_scopes" (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "version_id" uuid NOT NULL,
  "organization_id" uuid NOT NULL,
  "site_id" uuid,
  "item_id" uuid,
  "service_id" uuid,
  "effect" text NOT NULL,
  "conditions" jsonb NOT NULL,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  row_version bigint NOT NULL DEFAULT 1 CHECK(row_version>0)
);

COMMENT ON TABLE "commercial"."contract_scopes" IS 'Sociétés, sites et actifs couverts | Catalogue: Couverture explicite avec inclusion ou exclusion ; site et actif cohérents avec le client.';

ALTER TABLE "commercial"."contract_scopes" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "commercial"."contract_scopes" FORCE ROW LEVEL SECURITY;

CREATE TRIGGER z_touch BEFORE UPDATE ON "commercial"."contract_scopes" FOR EACH ROW EXECUTE FUNCTION infrastructure.touch_row();

CREATE TABLE "commercial"."contract_components" (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "version_id" uuid NOT NULL,
  "kind" text NOT NULL,
  "product_id" uuid,
  "unit" text NOT NULL,
  "unit_price" numeric(20,6) NOT NULL,
  "included_quantity" numeric(20,6),
  "periodicity" text,
  "minimum_quantity" numeric(20,6),
  "rounding_minutes" integer,
  "overage_price" numeric(20,6),
  "priority" integer NOT NULL,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  row_version bigint NOT NULL DEFAULT 1 CHECK(row_version>0)
);

COMMENT ON TABLE "commercial"."contract_components" IS 'Composants tarifaires combinables | Catalogue: Abonnement, forfait, crédit, temps, intervention combinables ; ordre et cumul définis pour éviter double facturation.';

ALTER TABLE "commercial"."contract_components" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "commercial"."contract_components" FORCE ROW LEVEL SECURITY;

CREATE TRIGGER z_touch BEFORE UPDATE ON "commercial"."contract_components" FOR EACH ROW EXECUTE FUNCTION infrastructure.touch_row();

ALTER TABLE "commercial"."contract_components" ADD CONSTRAINT "c_ca575b984c91f1add5ff" CHECK ("unit_price" <> 'NaN'::numeric);

ALTER TABLE "commercial"."contract_components" ADD CONSTRAINT "c_518081987941af9c1f93" CHECK ("unit_price" >= 0);

ALTER TABLE "commercial"."contract_components" ADD CONSTRAINT "c_76998ec036476839c264" CHECK ("included_quantity" <> 'NaN'::numeric);

ALTER TABLE "commercial"."contract_components" ADD CONSTRAINT "c_a639e2bf6cee6e5cf030" CHECK ("included_quantity" >= 0);

ALTER TABLE "commercial"."contract_components" ADD CONSTRAINT "c_5e642abb48dad0431148" CHECK ("minimum_quantity" <> 'NaN'::numeric);

ALTER TABLE "commercial"."contract_components" ADD CONSTRAINT "c_a661e521ba6234c7ac9e" CHECK ("minimum_quantity" >= 0);

ALTER TABLE "commercial"."contract_components" ADD CONSTRAINT "c_080b972dac198132b023" CHECK ("rounding_minutes" >= 0);

ALTER TABLE "commercial"."contract_components" ADD CONSTRAINT "c_5255bc6db937de37726c" CHECK ("overage_price" <> 'NaN'::numeric);

ALTER TABLE "commercial"."contract_components" ADD CONSTRAINT "c_77d150d1cd3c8fc17442" CHECK ("overage_price" >= 0);

CREATE TABLE "commercial"."contract_sla_bindings" (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "version_id" uuid NOT NULL,
  "policy_id" uuid NOT NULL,
  "service_id" uuid,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  row_version bigint NOT NULL DEFAULT 1 CHECK(row_version>0)
);

COMMENT ON TABLE "commercial"."contract_sla_bindings" IS 'Engagements applicables au contrat | Catalogue: Une politique compatible par contexte ; engagement signé distinct d’un objectif interne.';

ALTER TABLE "commercial"."contract_sla_bindings" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "commercial"."contract_sla_bindings" FORCE ROW LEVEL SECURITY;

CREATE TRIGGER z_touch BEFORE UPDATE ON "commercial"."contract_sla_bindings" FOR EACH ROW EXECUTE FUNCTION infrastructure.touch_row();

ALTER TABLE "commercial"."contract_sla_bindings" ADD CONSTRAINT "c_65d20455c448966d973e" UNIQUE NULLS NOT DISTINCT ("version_id", "policy_id", "service_id");

CREATE TABLE "commercial"."contract_payers" (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "version_id" uuid NOT NULL,
  "payer_org_id" uuid NOT NULL,
  "covered_org_id" uuid NOT NULL,
  "share_percent" numeric(20,6) NOT NULL,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  row_version bigint NOT NULL DEFAULT 1 CHECK(row_version>0)
);

COMMENT ON TABLE "commercial"."contract_payers" IS 'Répartition de facturation | Catalogue: Total de répartition 100 % par périmètre applicable, validé transactionnellement.';

ALTER TABLE "commercial"."contract_payers" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "commercial"."contract_payers" FORCE ROW LEVEL SECURITY;

CREATE TRIGGER z_touch BEFORE UPDATE ON "commercial"."contract_payers" FOR EACH ROW EXECUTE FUNCTION infrastructure.touch_row();

ALTER TABLE "commercial"."contract_payers" ADD CONSTRAINT "c_fda0b18e280e16542e13" CHECK (share_percent > 0 AND share_percent <= 100);

ALTER TABLE "commercial"."contract_payers" ADD CONSTRAINT "c_3da4f9bb907522407158" CHECK ("share_percent" <> 'NaN'::numeric);

ALTER TABLE "commercial"."contract_payers" ADD CONSTRAINT "c_e2f24c8609aab5893255" UNIQUE NULLS NOT DISTINCT ("version_id", "payer_org_id", "covered_org_id");

CREATE TABLE "commercial"."rate_rules" (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "component_id" uuid NOT NULL,
  "activity_type" text NOT NULL,
  "skill_id" uuid,
  "time_band" text,
  "rate" numeric(20,6) NOT NULL,
  "valid_from" timestamptz NOT NULL,
  "valid_to" timestamptz,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  row_version bigint NOT NULL DEFAULT 1 CHECK(row_version>0)
);

COMMENT ON TABLE "commercial"."rate_rules" IS 'Tarifs et exceptions | Catalogue: Priorité et règle de repli explicites ; pas de tarif flottant non historisé.';

ALTER TABLE "commercial"."rate_rules" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "commercial"."rate_rules" FORCE ROW LEVEL SECURITY;

CREATE TRIGGER z_touch BEFORE UPDATE ON "commercial"."rate_rules" FOR EACH ROW EXECUTE FUNCTION infrastructure.touch_row();

ALTER TABLE "commercial"."rate_rules" ADD CONSTRAINT "c_e1cda1a8b6a98f94d273" CHECK ("rate" <> 'NaN'::numeric);

ALTER TABLE "commercial"."rate_rules" ADD CONSTRAINT "c_62460b611907b5d368b9" CHECK ("valid_to" >= "valid_from");

CREATE TABLE "commercial"."credit_accounts" (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "contract_id" uuid NOT NULL,
  "unit" text NOT NULL,
  "rollover_policy" text NOT NULL,
  "expiry_policy" text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  row_version bigint NOT NULL DEFAULT 1 CHECK(row_version>0)
);

COMMENT ON TABLE "commercial"."credit_accounts" IS 'Comptes de crédits d’heures ou unités | Catalogue: Solde dérivé des mouvements ; unité et période contractuelles.';

ALTER TABLE "commercial"."credit_accounts" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "commercial"."credit_accounts" FORCE ROW LEVEL SECURITY;

CREATE TRIGGER z_touch BEFORE UPDATE ON "commercial"."credit_accounts" FOR EACH ROW EXECUTE FUNCTION infrastructure.touch_row();

ALTER TABLE "commercial"."credit_accounts" ADD CONSTRAINT "c_799653f1e66eafcaeabc" UNIQUE NULLS NOT DISTINCT ("contract_id", "unit");

CREATE TABLE "commercial"."credit_ledger" (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "account_id" uuid NOT NULL,
  "quantity_delta" numeric(20,6) NOT NULL,
  "effective_at" timestamptz NOT NULL,
  "expires_at" timestamptz,
  "usage_event_id" uuid,
  "reversal_of_id" uuid,
  "idempotency_key" text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  row_version bigint NOT NULL DEFAULT 1 CHECK(row_version>0)
);

COMMENT ON TABLE "commercial"."credit_ledger" IS 'Achats, consommation et corrections de crédits | Catalogue: Écriture append-only ; consommation sérialisée ; compensation au lieu de suppression.';

ALTER TABLE "commercial"."credit_ledger" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "commercial"."credit_ledger" FORCE ROW LEVEL SECURITY;

CREATE TRIGGER z_touch BEFORE UPDATE ON "commercial"."credit_ledger" FOR EACH ROW EXECUTE FUNCTION infrastructure.touch_row();

CREATE TRIGGER a_immutable BEFORE UPDATE OR DELETE ON "commercial"."credit_ledger" FOR EACH ROW EXECUTE FUNCTION infrastructure.reject_mutation();
CREATE TRIGGER a_no_truncate BEFORE TRUNCATE ON "commercial"."credit_ledger" FOR EACH STATEMENT EXECUTE FUNCTION infrastructure.reject_mutation();

ALTER TABLE "commercial"."credit_ledger" ADD CONSTRAINT "c_c07f98da3c22baaed91f" CHECK ("quantity_delta" <> 'NaN'::numeric);

ALTER TABLE "commercial"."credit_ledger" ADD CONSTRAINT "c_7eca91d96d2625740ccc" CHECK ("reversal_of_id" <> id);

ALTER TABLE "commercial"."credit_ledger" ADD CONSTRAINT "c_e4c8b56eedf15a0d7fc4" UNIQUE NULLS NOT DISTINCT ("idempotency_key");

CREATE TABLE "commercial"."quotes" (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "number" text NOT NULL,
  "issuer_org_id" uuid NOT NULL,
  "customer_org_id" uuid NOT NULL,
  "opportunity_id" uuid,
  "status" text NOT NULL,
  "currency" text NOT NULL,
  "issued_on" date,
  "expires_on" date,
  "revision_no" integer NOT NULL,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  row_version bigint NOT NULL DEFAULT 1 CHECK(row_version>0)
);

COMMENT ON TABLE "commercial"."quotes" IS 'Devis | Catalogue: Versions et acceptation conservées ; modèle d’offre distinct d’un document émis.';

ALTER TABLE "commercial"."quotes" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "commercial"."quotes" FORCE ROW LEVEL SECURITY;

CREATE TRIGGER z_touch BEFORE UPDATE ON "commercial"."quotes" FOR EACH ROW EXECUTE FUNCTION infrastructure.touch_row();

ALTER TABLE "commercial"."quotes" ADD CONSTRAINT "c_1b5f3e562c7731b483db" CHECK ("currency" ~ '^[A-Z]{3}$');

ALTER TABLE "commercial"."quotes" ADD CONSTRAINT "c_605648907e27c5f17bed" CHECK ("revision_no" > 0);

ALTER TABLE "commercial"."quotes" ADD CONSTRAINT "c_8bc2935fbfc308b48cdb" UNIQUE NULLS NOT DISTINCT ("issuer_org_id", "number", "revision_no");

CREATE TABLE "commercial"."quote_lines" (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "quote_id" uuid NOT NULL,
  "product_id" uuid,
  "description" text NOT NULL,
  "quantity" numeric(20,6) NOT NULL,
  "unit_price" numeric(20,6) NOT NULL,
  "discount_rate" numeric(20,6) NOT NULL,
  "tax_rate" numeric(20,6) NOT NULL,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  row_version bigint NOT NULL DEFAULT 1 CHECK(row_version>0)
);

COMMENT ON TABLE "commercial"."quote_lines" IS 'Lignes de devis | Catalogue: Montants et taxes figés sur la version acceptée.';

ALTER TABLE "commercial"."quote_lines" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "commercial"."quote_lines" FORCE ROW LEVEL SECURITY;

CREATE TRIGGER z_touch BEFORE UPDATE ON "commercial"."quote_lines" FOR EACH ROW EXECUTE FUNCTION infrastructure.touch_row();

ALTER TABLE "commercial"."quote_lines" ADD CONSTRAINT "c_3ec4130bf03b6b447e15" CHECK ("quantity" <> 'NaN'::numeric);

ALTER TABLE "commercial"."quote_lines" ADD CONSTRAINT "c_5ef9acaf41643e93d7cf" CHECK ("quantity" >= 0);

ALTER TABLE "commercial"."quote_lines" ADD CONSTRAINT "c_ecdebcd4e5e970a8c61f" CHECK ("unit_price" <> 'NaN'::numeric);

ALTER TABLE "commercial"."quote_lines" ADD CONSTRAINT "c_30186abd903ed54a547b" CHECK ("unit_price" >= 0);

ALTER TABLE "commercial"."quote_lines" ADD CONSTRAINT "c_303cf631ddee761a1211" CHECK ("discount_rate" <> 'NaN'::numeric);

ALTER TABLE "commercial"."quote_lines" ADD CONSTRAINT "c_9903fd7d25d07d8b0163" CHECK ("discount_rate" BETWEEN 0 AND 1);

ALTER TABLE "commercial"."quote_lines" ADD CONSTRAINT "c_adc66dbc61e27c30eda3" CHECK ("tax_rate" <> 'NaN'::numeric);

ALTER TABLE "commercial"."quote_lines" ADD CONSTRAINT "c_6e7f22079241a4b2c3f4" CHECK ("tax_rate" BETWEEN 0 AND 1);

CREATE TABLE "commercial"."invoices" (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "number" text NOT NULL,
  "issuer_org_id" uuid NOT NULL,
  "payer_org_id" uuid NOT NULL,
  "status" text NOT NULL,
  "currency" text NOT NULL,
  "issued_on" date,
  "due_on" date,
  "issuer_snapshot" jsonb NOT NULL,
  "customer_snapshot" jsonb NOT NULL,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  row_version bigint NOT NULL DEFAULT 1 CHECK(row_version>0)
);

COMMENT ON TABLE "commercial"."invoices" IS 'Factures dans l’outil commercial | Catalogue: Règles de numérotation et d’émission à spécifier selon contexte ; document émis non réécrit.';

ALTER TABLE "commercial"."invoices" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "commercial"."invoices" FORCE ROW LEVEL SECURITY;

CREATE TRIGGER z_touch BEFORE UPDATE ON "commercial"."invoices" FOR EACH ROW EXECUTE FUNCTION infrastructure.touch_row();

ALTER TABLE "commercial"."invoices" ADD CONSTRAINT "c_76d9fc11df1947969d33" CHECK ("currency" ~ '^[A-Z]{3}$');

ALTER TABLE "commercial"."invoices" ADD CONSTRAINT "c_5b428df7767221100181" UNIQUE NULLS NOT DISTINCT ("issuer_org_id", "number");

CREATE TABLE "commercial"."invoice_lines" (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "invoice_id" uuid NOT NULL,
  "description" text NOT NULL,
  "quantity" numeric(20,6) NOT NULL,
  "unit_price" numeric(20,6) NOT NULL,
  "tax_rate" numeric(20,6) NOT NULL,
  "source_statement_line_key" text,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  row_version bigint NOT NULL DEFAULT 1 CHECK(row_version>0)
);

COMMENT ON TABLE "commercial"."invoice_lines" IS 'Détail des montants facturés | Catalogue: Référence export/import idempotente ; ajustements via document correctif.';

ALTER TABLE "commercial"."invoice_lines" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "commercial"."invoice_lines" FORCE ROW LEVEL SECURITY;

CREATE TRIGGER z_touch BEFORE UPDATE ON "commercial"."invoice_lines" FOR EACH ROW EXECUTE FUNCTION infrastructure.touch_row();

ALTER TABLE "commercial"."invoice_lines" ADD CONSTRAINT "c_8d8530ef156c857e394b" CHECK ("quantity" <> 'NaN'::numeric);

ALTER TABLE "commercial"."invoice_lines" ADD CONSTRAINT "c_109c0ee9719db33740e1" CHECK ("quantity" >= 0);

ALTER TABLE "commercial"."invoice_lines" ADD CONSTRAINT "c_5233cc0287ae7606fc99" CHECK ("unit_price" <> 'NaN'::numeric);

ALTER TABLE "commercial"."invoice_lines" ADD CONSTRAINT "c_b28825e6051e510cccf5" CHECK ("unit_price" >= 0);

ALTER TABLE "commercial"."invoice_lines" ADD CONSTRAINT "c_580b7e2118cfdbca60e5" CHECK ("tax_rate" <> 'NaN'::numeric);

ALTER TABLE "commercial"."invoice_lines" ADD CONSTRAINT "c_2b9f04f3a6ea2b572107" CHECK ("tax_rate" BETWEEN 0 AND 1);

CREATE TABLE "commercial"."payments" (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "payer_org_id" uuid NOT NULL,
  "amount" numeric(20,6) NOT NULL,
  "currency" text NOT NULL,
  "received_on" date NOT NULL,
  "method" text NOT NULL,
  "external_reference" text,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  row_version bigint NOT NULL DEFAULT 1 CHECK(row_version>0)
);

COMMENT ON TABLE "commercial"."payments" IS 'Paiements enregistrés | Catalogue: Enregistrement et rapprochement, pas initiation automatique d’un paiement.';

ALTER TABLE "commercial"."payments" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "commercial"."payments" FORCE ROW LEVEL SECURITY;

CREATE TRIGGER z_touch BEFORE UPDATE ON "commercial"."payments" FOR EACH ROW EXECUTE FUNCTION infrastructure.touch_row();

ALTER TABLE "commercial"."payments" ADD CONSTRAINT "c_2d98c755dcae0cc7d312" CHECK ("amount" <> 'NaN'::numeric);

ALTER TABLE "commercial"."payments" ADD CONSTRAINT "c_7bad18e3ba134c6dc69d" CHECK ("currency" ~ '^[A-Z]{3}$');

CREATE TABLE "commercial"."payment_allocations" (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "payment_id" uuid NOT NULL,
  "invoice_id" uuid NOT NULL,
  "amount" numeric(20,6) NOT NULL,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  row_version bigint NOT NULL DEFAULT 1 CHECK(row_version>0)
);

COMMENT ON TABLE "commercial"."payment_allocations" IS 'Rapprochement paiement et facture | Catalogue: Sommes bornées au paiement et à la facture ; devise compatible.';

ALTER TABLE "commercial"."payment_allocations" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "commercial"."payment_allocations" FORCE ROW LEVEL SECURITY;

CREATE TRIGGER z_touch BEFORE UPDATE ON "commercial"."payment_allocations" FOR EACH ROW EXECUTE FUNCTION infrastructure.touch_row();

ALTER TABLE "commercial"."payment_allocations" ADD CONSTRAINT "c_df8e1f0798b988c051e5" CHECK ("amount" <> 'NaN'::numeric);

ALTER TABLE "commercial"."payment_allocations" ADD CONSTRAINT "c_e6eed65cf7512429d05d" UNIQUE NULLS NOT DISTINCT ("payment_id", "invoice_id");

CREATE TABLE "commercial"."credit_notes" (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "invoice_id" uuid NOT NULL,
  "number" text NOT NULL,
  "reason" text NOT NULL,
  "amount" numeric(20,6) NOT NULL,
  "currency" text NOT NULL,
  "issued_on" date NOT NULL,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  row_version bigint NOT NULL DEFAULT 1 CHECK(row_version>0)
);

COMMENT ON TABLE "commercial"."credit_notes" IS 'Avoirs | Catalogue: Numéro et document correctif conservés ; ne pas effacer une facture émise.';

ALTER TABLE "commercial"."credit_notes" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "commercial"."credit_notes" FORCE ROW LEVEL SECURITY;

CREATE TRIGGER z_touch BEFORE UPDATE ON "commercial"."credit_notes" FOR EACH ROW EXECUTE FUNCTION infrastructure.touch_row();

CREATE TRIGGER a_immutable BEFORE UPDATE OR DELETE ON "commercial"."credit_notes" FOR EACH ROW EXECUTE FUNCTION infrastructure.reject_mutation();
CREATE TRIGGER a_no_truncate BEFORE TRUNCATE ON "commercial"."credit_notes" FOR EACH STATEMENT EXECUTE FUNCTION infrastructure.reject_mutation();

ALTER TABLE "commercial"."credit_notes" ADD CONSTRAINT "c_6b3098c788376ba8edd2" CHECK ("amount" <> 'NaN'::numeric);

ALTER TABLE "commercial"."credit_notes" ADD CONSTRAINT "c_68310cf7a78f455bb559" CHECK ("currency" ~ '^[A-Z]{3}$');

CREATE TABLE "billing"."time_entries" (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "person_id" uuid NOT NULL,
  "ticket_id" uuid,
  "task_id" uuid,
  "intervention_id" uuid,
  "activity_type" text NOT NULL,
  "started_at" timestamptz,
  "ended_at" timestamptz,
  "duration_minutes" integer NOT NULL,
  "billable" boolean NOT NULL,
  "status" text NOT NULL,
  "description" text,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  row_version bigint NOT NULL DEFAULT 1 CHECK(row_version>0)
);

COMMENT ON TABLE "billing"."time_entries" IS 'Temps réellement passé | Catalogue: Ticket ou tâche obligatoire ; intervention cohérente avec ticket ; durée positive ; un temps n’est saisi qu’une fois.';

ALTER TABLE "billing"."time_entries" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "billing"."time_entries" FORCE ROW LEVEL SECURITY;

CREATE TRIGGER z_touch BEFORE UPDATE ON "billing"."time_entries" FOR EACH ROW EXECUTE FUNCTION infrastructure.touch_row();

ALTER TABLE "billing"."time_entries" ADD CONSTRAINT "c_cfa6e0063484c8e88cea" CHECK (num_nonnulls(ticket_id,task_id)=1);

ALTER TABLE "billing"."time_entries" ADD CONSTRAINT "c_4db3bbb10ca7780b0024" CHECK (intervention_id IS NULL OR ticket_id IS NOT NULL);

ALTER TABLE "billing"."time_entries" ADD CONSTRAINT "c_61fa836248fc4b61bb71" CHECK (duration_minutes > 0);

ALTER TABLE "billing"."time_entries" ADD CONSTRAINT "c_99875ae5b2afdc2d75e3" CHECK ("duration_minutes" >= 0);

ALTER TABLE "billing"."time_entries" ADD CONSTRAINT "c_02ffdd461f4fc9b6dacc" CHECK ("ended_at" >= "started_at");

CREATE TABLE "billing"."time_approvals" (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "time_entry_id" uuid NOT NULL,
  "reviewer_id" uuid NOT NULL,
  "decision" text NOT NULL,
  "decided_at" timestamptz NOT NULL,
  "reason" text,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  row_version bigint NOT NULL DEFAULT 1 CHECK(row_version>0)
);

COMMENT ON TABLE "billing"."time_approvals" IS 'Validation du temps | Catalogue: Temps approuvé figé ; correction tracée après export.';

ALTER TABLE "billing"."time_approvals" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "billing"."time_approvals" FORCE ROW LEVEL SECURITY;

CREATE TRIGGER z_touch BEFORE UPDATE ON "billing"."time_approvals" FOR EACH ROW EXECUTE FUNCTION infrastructure.touch_row();

CREATE TRIGGER a_immutable BEFORE UPDATE OR DELETE ON "billing"."time_approvals" FOR EACH ROW EXECUTE FUNCTION infrastructure.reject_mutation();
CREATE TRIGGER a_no_truncate BEFORE TRUNCATE ON "billing"."time_approvals" FOR EACH STATEMENT EXECUTE FUNCTION infrastructure.reject_mutation();

ALTER TABLE "billing"."time_approvals" ADD CONSTRAINT "c_a9e9742a2bed0b8e8452" UNIQUE NULLS NOT DISTINCT ("time_entry_id", "reviewer_id");

CREATE TABLE "billing"."expenses" (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "ticket_id" uuid,
  "project_id" uuid,
  "person_id" uuid,
  "kind" text NOT NULL,
  "amount" numeric(20,6) NOT NULL,
  "currency" text NOT NULL,
  "incurred_on" date NOT NULL,
  "receipt_file_id" uuid,
  "billable" boolean NOT NULL,
  "status" text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  row_version bigint NOT NULL DEFAULT 1 CHECK(row_version>0)
);

COMMENT ON TABLE "billing"."expenses" IS 'Frais et fournitures imputables | Catalogue: Au moins une cible ; distinguer coût interne et montant refacturé.';

ALTER TABLE "billing"."expenses" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "billing"."expenses" FORCE ROW LEVEL SECURITY;

CREATE TRIGGER z_touch BEFORE UPDATE ON "billing"."expenses" FOR EACH ROW EXECUTE FUNCTION infrastructure.touch_row();

ALTER TABLE "billing"."expenses" ADD CONSTRAINT "c_5e192d4a950d0b772065" CHECK (num_nonnulls(ticket_id,project_id)>=1);

ALTER TABLE "billing"."expenses" ADD CONSTRAINT "c_01125058f6784f0a48da" CHECK ("amount" <> 'NaN'::numeric);

ALTER TABLE "billing"."expenses" ADD CONSTRAINT "c_d1aebf48d986e6a11f52" CHECK ("currency" ~ '^[A-Z]{3}$');

CREATE TABLE "billing"."usage_events" (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "customer_org_id" uuid NOT NULL,
  "contract_version_id" uuid,
  "time_entry_id" uuid,
  "intervention_id" uuid,
  "expense_id" uuid,
  "component_id" uuid,
  "quantity" numeric(20,6) NOT NULL,
  "unit" text NOT NULL,
  "occurred_at" timestamptz NOT NULL,
  "source_key" text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  row_version bigint NOT NULL DEFAULT 1 CHECK(row_version>0)
);

COMMENT ON TABLE "billing"."usage_events" IS 'Unités consommées facturables ou incluses | Catalogue: UNIQUE source_key ; sources explicites ; lignes de temps/intervention ne se facturent pas deux fois par défaut.';

ALTER TABLE "billing"."usage_events" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "billing"."usage_events" FORCE ROW LEVEL SECURITY;

CREATE TRIGGER z_touch BEFORE UPDATE ON "billing"."usage_events" FOR EACH ROW EXECUTE FUNCTION infrastructure.touch_row();

CREATE TRIGGER a_immutable BEFORE UPDATE OR DELETE ON "billing"."usage_events" FOR EACH ROW EXECUTE FUNCTION infrastructure.reject_mutation();
CREATE TRIGGER a_no_truncate BEFORE TRUNCATE ON "billing"."usage_events" FOR EACH STATEMENT EXECUTE FUNCTION infrastructure.reject_mutation();

ALTER TABLE "billing"."usage_events" ADD CONSTRAINT "c_28d2c4e55b5ca36d8d50" CHECK (num_nonnulls(time_entry_id,intervention_id,expense_id)=1);

ALTER TABLE "billing"."usage_events" ADD CONSTRAINT "c_9290d1eb36d2c7a14a84" CHECK ("quantity" <> 'NaN'::numeric);

ALTER TABLE "billing"."usage_events" ADD CONSTRAINT "c_17881c83064a2954ab2c" CHECK ("quantity" >= 0);

ALTER TABLE "billing"."usage_events" ADD CONSTRAINT "c_89649071c0b11ff52e6c" UNIQUE NULLS NOT DISTINCT ("source_key");

CREATE TABLE "billing"."valuation_runs" (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "period_start" date NOT NULL,
  "period_end" date NOT NULL,
  "customer_org_id" uuid NOT NULL,
  "contract_id" uuid,
  "engine_version" text NOT NULL,
  "status" text NOT NULL,
  "calculated_at" timestamptz NOT NULL,
  "currency" text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  row_version bigint NOT NULL DEFAULT 1 CHECK(row_version>0)
);

COMMENT ON TABLE "billing"."valuation_runs" IS 'Calculs de valorisation | Catalogue: Période demi-ouverte ; taux, calendriers et contrats de référence conservés.';

ALTER TABLE "billing"."valuation_runs" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "billing"."valuation_runs" FORCE ROW LEVEL SECURITY;

CREATE TRIGGER z_touch BEFORE UPDATE ON "billing"."valuation_runs" FOR EACH ROW EXECUTE FUNCTION infrastructure.touch_row();

ALTER TABLE "billing"."valuation_runs" ADD CONSTRAINT "c_aaa65769d64c8842601d" CHECK ("currency" ~ '^[A-Z]{3}$');

ALTER TABLE "billing"."valuation_runs" ADD CONSTRAINT "c_7da98a2eca5d6fb074da" CHECK ("period_end" > "period_start");

CREATE TABLE "billing"."valuation_lines" (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "run_id" uuid NOT NULL,
  "usage_event_id" uuid NOT NULL,
  "component_id" uuid,
  "quantity" numeric(20,6) NOT NULL,
  "unit_rate" numeric(20,6) NOT NULL,
  "amount" numeric(20,6) NOT NULL,
  "covered_quantity" numeric(20,6) NOT NULL,
  "calculation_snapshot" jsonb NOT NULL,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  row_version bigint NOT NULL DEFAULT 1 CHECK(row_version>0)
);

COMMENT ON TABLE "billing"."valuation_lines" IS 'Résultats explicables par consommation | Catalogue: Part incluse, crédit, dépassement, remise et arrondi identifiables ; montant non calculé en flottant.';

ALTER TABLE "billing"."valuation_lines" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "billing"."valuation_lines" FORCE ROW LEVEL SECURITY;

CREATE TRIGGER z_touch BEFORE UPDATE ON "billing"."valuation_lines" FOR EACH ROW EXECUTE FUNCTION infrastructure.touch_row();

ALTER TABLE "billing"."valuation_lines" ADD CONSTRAINT "c_16269278e0ce3f4e50b7" CHECK ("quantity" <> 'NaN'::numeric);

ALTER TABLE "billing"."valuation_lines" ADD CONSTRAINT "c_073c6be7ecc7730d0ea9" CHECK ("quantity" >= 0);

ALTER TABLE "billing"."valuation_lines" ADD CONSTRAINT "c_1e792d6d4043e8c3a1a6" CHECK ("unit_rate" <> 'NaN'::numeric);

ALTER TABLE "billing"."valuation_lines" ADD CONSTRAINT "c_5e8079a846493ebcd192" CHECK ("amount" <> 'NaN'::numeric);

ALTER TABLE "billing"."valuation_lines" ADD CONSTRAINT "c_470ce77e589cb26b0f81" CHECK ("covered_quantity" <> 'NaN'::numeric);

CREATE TABLE "billing"."activity_statements" (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "number" text NOT NULL,
  "customer_org_id" uuid NOT NULL,
  "contract_id" uuid,
  "period_start" date NOT NULL,
  "period_end" date NOT NULL,
  "status" text NOT NULL,
  "revision_no" integer NOT NULL,
  "currency" text NOT NULL,
  "approved_by" uuid,
  "approved_at" timestamptz,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  row_version bigint NOT NULL DEFAULT 1 CHECK(row_version>0)
);

COMMENT ON TABLE "billing"."activity_statements" IS 'Rapports client prêts à exporter | Catalogue: Peut regrouper plusieurs sociétés/sites du contrat ; périmètre explicitement listé.';

ALTER TABLE "billing"."activity_statements" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "billing"."activity_statements" FORCE ROW LEVEL SECURITY;

CREATE TRIGGER z_touch BEFORE UPDATE ON "billing"."activity_statements" FOR EACH ROW EXECUTE FUNCTION infrastructure.touch_row();

ALTER TABLE "billing"."activity_statements" ADD CONSTRAINT "c_86855913563c9a77981c" CHECK ("revision_no" > 0);

ALTER TABLE "billing"."activity_statements" ADD CONSTRAINT "c_d799b616c1c105944ae0" CHECK ("currency" ~ '^[A-Z]{3}$');

ALTER TABLE "billing"."activity_statements" ADD CONSTRAINT "c_5b32795567b48f5b7429" CHECK ("period_end" > "period_start");

ALTER TABLE "billing"."activity_statements" ADD CONSTRAINT "c_a6182b4dc9b871bb861d" UNIQUE NULLS NOT DISTINCT ("number", "revision_no");

CREATE TABLE "billing"."statement_lines" (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "statement_id" uuid NOT NULL,
  "valuation_line_id" uuid NOT NULL,
  "line_key" text NOT NULL,
  "description" text NOT NULL,
  "quantity" numeric(20,6) NOT NULL,
  "amount" numeric(20,6) NOT NULL,
  "tax_treatment" text,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  row_version bigint NOT NULL DEFAULT 1 CHECK(row_version>0)
);

COMMENT ON TABLE "billing"."statement_lines" IS 'Lignes figées du rapport | Catalogue: Clé stable unique ; export répété ne consomme pas de crédit ni ne crée une nouvelle facturation.';

ALTER TABLE "billing"."statement_lines" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "billing"."statement_lines" FORCE ROW LEVEL SECURITY;

CREATE TRIGGER z_touch BEFORE UPDATE ON "billing"."statement_lines" FOR EACH ROW EXECUTE FUNCTION infrastructure.touch_row();

ALTER TABLE "billing"."statement_lines" ADD CONSTRAINT "c_37483459d6acedd658ac" CHECK ("quantity" <> 'NaN'::numeric);

ALTER TABLE "billing"."statement_lines" ADD CONSTRAINT "c_6bc30158df0c49bd8024" CHECK ("quantity" >= 0);

ALTER TABLE "billing"."statement_lines" ADD CONSTRAINT "c_3a6ef59d6afcf984ab47" CHECK ("amount" <> 'NaN'::numeric);

ALTER TABLE "billing"."statement_lines" ADD CONSTRAINT "c_066547f0500a3a85b565" UNIQUE NULLS NOT DISTINCT ("line_key");

CREATE TABLE "billing"."statement_exports" (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "statement_id" uuid NOT NULL,
  "format" text NOT NULL,
  "file_id" uuid NOT NULL,
  "exported_by" uuid NOT NULL,
  "exported_at" timestamptz NOT NULL,
  "checksum" text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  row_version bigint NOT NULL DEFAULT 1 CHECK(row_version>0)
);

COMMENT ON TABLE "billing"."statement_exports" IS 'Fichiers et versions exportés | Catalogue: CSV, XLSX, PDF, JSON ; format et version du schéma exportés.';

ALTER TABLE "billing"."statement_exports" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "billing"."statement_exports" FORCE ROW LEVEL SECURITY;

CREATE TRIGGER z_touch BEFORE UPDATE ON "billing"."statement_exports" FOR EACH ROW EXECUTE FUNCTION infrastructure.touch_row();

CREATE TRIGGER a_immutable BEFORE UPDATE OR DELETE ON "billing"."statement_exports" FOR EACH ROW EXECUTE FUNCTION infrastructure.reject_mutation();
CREATE TRIGGER a_no_truncate BEFORE TRUNCATE ON "billing"."statement_exports" FOR EACH STATEMENT EXECUTE FUNCTION infrastructure.reject_mutation();

CREATE TABLE "billing"."invoice_reconciliations" (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "statement_line_id" uuid NOT NULL,
  "external_invoice_key" text NOT NULL,
  "external_line_key" text NOT NULL,
  "invoiced_amount" numeric(20,6) NOT NULL,
  "recorded_at" timestamptz NOT NULL,
  "status" text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  row_version bigint NOT NULL DEFAULT 1 CHECK(row_version>0)
);

COMMENT ON TABLE "billing"."invoice_reconciliations" IS 'Retour de l’outil de facturation | Catalogue: Pas de FK interbase ; imports idempotents ; suivi partiel ou corrigé.';

ALTER TABLE "billing"."invoice_reconciliations" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "billing"."invoice_reconciliations" FORCE ROW LEVEL SECURITY;

CREATE TRIGGER z_touch BEFORE UPDATE ON "billing"."invoice_reconciliations" FOR EACH ROW EXECUTE FUNCTION infrastructure.touch_row();

ALTER TABLE "billing"."invoice_reconciliations" ADD CONSTRAINT "c_4adf9ad618f43d4ee41f" CHECK ("invoiced_amount" <> 'NaN'::numeric);

ALTER TABLE "billing"."invoice_reconciliations" ADD CONSTRAINT "c_10d14f8e62fe9176fa61" UNIQUE NULLS NOT DISTINCT ("external_invoice_key", "external_line_key");

CREATE TABLE "knowledge"."spaces" (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "code" text NOT NULL,
  "name" text NOT NULL,
  "visibility" text NOT NULL,
  "owner_team_id" uuid,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  row_version bigint NOT NULL DEFAULT 1 CHECK(row_version>0)
);

COMMENT ON TABLE "knowledge"."spaces" IS 'Espaces documentaires | Catalogue: Visibilité contrôlée indépendamment du forfait.';

ALTER TABLE "knowledge"."spaces" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "knowledge"."spaces" FORCE ROW LEVEL SECURITY;

CREATE TRIGGER z_touch BEFORE UPDATE ON "knowledge"."spaces" FOR EACH ROW EXECUTE FUNCTION infrastructure.touch_row();

ALTER TABLE "knowledge"."spaces" ADD CONSTRAINT "c_8316f671455addcf63d7" UNIQUE NULLS NOT DISTINCT ("code");

CREATE TABLE "knowledge"."articles" (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "space_id" uuid NOT NULL,
  "slug" text NOT NULL,
  "title" text NOT NULL,
  "status" text NOT NULL,
  "owner_id" uuid NOT NULL,
  "review_due_on" date,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  row_version bigint NOT NULL DEFAULT 1 CHECK(row_version>0)
);

COMMENT ON TABLE "knowledge"."articles" IS 'Identité des articles | Catalogue: Statut brouillon, validé, publié, archivé.';

ALTER TABLE "knowledge"."articles" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "knowledge"."articles" FORCE ROW LEVEL SECURITY;

CREATE TRIGGER z_touch BEFORE UPDATE ON "knowledge"."articles" FOR EACH ROW EXECUTE FUNCTION infrastructure.touch_row();

ALTER TABLE "knowledge"."articles" ADD CONSTRAINT "c_1d97956de2f281143dbe" UNIQUE NULLS NOT DISTINCT ("space_id", "slug");

CREATE TABLE "knowledge"."article_versions" (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "article_id" uuid NOT NULL,
  "version_no" integer NOT NULL,
  "body" text NOT NULL,
  "author_id" uuid NOT NULL,
  "approved_by" uuid,
  "published_at" timestamptz,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  row_version bigint NOT NULL DEFAULT 1 CHECK(row_version>0)
);

COMMENT ON TABLE "knowledge"."article_versions" IS 'Contenu et versions | Catalogue: Version publiée immuable ; pièces soumises aux mêmes droits.';

ALTER TABLE "knowledge"."article_versions" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "knowledge"."article_versions" FORCE ROW LEVEL SECURITY;

CREATE TRIGGER z_touch BEFORE UPDATE ON "knowledge"."article_versions" FOR EACH ROW EXECUTE FUNCTION infrastructure.touch_row();

CREATE TRIGGER a_published BEFORE UPDATE OR DELETE ON "knowledge"."article_versions" FOR EACH ROW EXECUTE FUNCTION infrastructure.freeze_published();

ALTER TABLE "knowledge"."article_versions" ADD CONSTRAINT "c_75f3fe01ceac44c4bb95" CHECK ("version_no" > 0);

ALTER TABLE "knowledge"."article_versions" ADD CONSTRAINT "c_3430f95f8cc8e4d87dd0" UNIQUE NULLS NOT DISTINCT ("article_id", "version_no");

CREATE TABLE "knowledge"."article_links" (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "article_id" uuid NOT NULL,
  "ticket_id" uuid NOT NULL,
  "relation_type" text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  row_version bigint NOT NULL DEFAULT 1 CHECK(row_version>0)
);

COMMENT ON TABLE "knowledge"."article_links" IS 'Connaissances associées aux tickets | Catalogue: Lier un article interne ne le rend pas public.';

ALTER TABLE "knowledge"."article_links" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "knowledge"."article_links" FORCE ROW LEVEL SECURITY;

CREATE TRIGGER z_touch BEFORE UPDATE ON "knowledge"."article_links" FOR EACH ROW EXECUTE FUNCTION infrastructure.touch_row();

ALTER TABLE "knowledge"."article_links" ADD CONSTRAINT "c_0b03d68f4f0b12a3c2b3" UNIQUE NULLS NOT DISTINCT ("article_id", "ticket_id", "relation_type");

CREATE TABLE "knowledge"."article_feedback" (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "article_id" uuid NOT NULL,
  "principal_id" uuid NOT NULL,
  "helpful" boolean NOT NULL,
  "comment" text,
  "submitted_at" timestamptz NOT NULL,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  row_version bigint NOT NULL DEFAULT 1 CHECK(row_version>0)
);

COMMENT ON TABLE "knowledge"."article_feedback" IS 'Utilité et corrections | Catalogue: Restreint au lectorat autorisé.';

ALTER TABLE "knowledge"."article_feedback" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "knowledge"."article_feedback" FORCE ROW LEVEL SECURITY;

CREATE TRIGGER z_touch BEFORE UPDATE ON "knowledge"."article_feedback" FOR EACH ROW EXECUTE FUNCTION infrastructure.touch_row();

CREATE TABLE "docs"."files" (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "storage_key" text NOT NULL,
  "original_name" text NOT NULL,
  "mime_detected" text NOT NULL,
  "size_bytes" bigint NOT NULL,
  "sha256" text NOT NULL,
  "scan_status" text NOT NULL,
  "uploaded_by" uuid,
  "classification" text NOT NULL,
  "deleted_at" timestamptz,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  row_version bigint NOT NULL DEFAULT 1 CHECK(row_version>0)
);

COMMENT ON TABLE "docs"."files" IS 'Objets binaires stockés | Catalogue: Clé opaque unique ; téléchargement après autorisation ; pas de déduplication entre abonnés.';

ALTER TABLE "docs"."files" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "docs"."files" FORCE ROW LEVEL SECURITY;

CREATE TRIGGER z_touch BEFORE UPDATE ON "docs"."files" FOR EACH ROW EXECUTE FUNCTION infrastructure.touch_row();

ALTER TABLE "docs"."files" ADD CONSTRAINT "c_17461bb54f7cbdb5154e" CHECK (sha256 ~ '^[0-9a-f]{64}$');

ALTER TABLE "docs"."files" ADD CONSTRAINT "c_43e35a9db1d39bbd86dd" CHECK ("size_bytes" >= 0);

ALTER TABLE "docs"."files" ADD CONSTRAINT "c_f55d2adb09a2be5011a8" UNIQUE NULLS NOT DISTINCT ("storage_key");

CREATE TABLE "docs"."documents" (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "title" text NOT NULL,
  "kind" text NOT NULL,
  "owner_id" uuid NOT NULL,
  "classification" text NOT NULL,
  "status" text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  row_version bigint NOT NULL DEFAULT 1 CHECK(row_version>0)
);

COMMENT ON TABLE "docs"."documents" IS 'Documents versionnés | Catalogue: Dossier documentaire distinct du fichier physique.';

ALTER TABLE "docs"."documents" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "docs"."documents" FORCE ROW LEVEL SECURITY;

CREATE TRIGGER z_touch BEFORE UPDATE ON "docs"."documents" FOR EACH ROW EXECUTE FUNCTION infrastructure.touch_row();

CREATE TABLE "docs"."document_versions" (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "document_id" uuid NOT NULL,
  "version_no" integer NOT NULL,
  "file_id" uuid NOT NULL,
  "authored_by" uuid NOT NULL,
  "published_at" timestamptz,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  row_version bigint NOT NULL DEFAULT 1 CHECK(row_version>0)
);

COMMENT ON TABLE "docs"."document_versions" IS 'Versions d’un document | Catalogue: UNIQUE document + version ; fichier immuable.';

ALTER TABLE "docs"."document_versions" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "docs"."document_versions" FORCE ROW LEVEL SECURITY;

CREATE TRIGGER z_touch BEFORE UPDATE ON "docs"."document_versions" FOR EACH ROW EXECUTE FUNCTION infrastructure.touch_row();

CREATE TRIGGER a_published BEFORE UPDATE OR DELETE ON "docs"."document_versions" FOR EACH ROW EXECUTE FUNCTION infrastructure.freeze_published();

ALTER TABLE "docs"."document_versions" ADD CONSTRAINT "c_03b708ebc6c09185cc3e" CHECK ("version_no" > 0);

ALTER TABLE "docs"."document_versions" ADD CONSTRAINT "c_5c9ad96645953daabb84" UNIQUE NULLS NOT DISTINCT ("document_id", "version_no");

CREATE TABLE "docs"."ticket_attachments" (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "ticket_id" uuid NOT NULL,
  "message_id" uuid,
  "file_id" uuid NOT NULL,
  "visibility" text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  row_version bigint NOT NULL DEFAULT 1 CHECK(row_version>0)
);

COMMENT ON TABLE "docs"."ticket_attachments" IS 'Pièces des tickets et messages | Catalogue: Message appartenant au ticket ; visibilité jamais plus large que le message source.';

ALTER TABLE "docs"."ticket_attachments" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "docs"."ticket_attachments" FORCE ROW LEVEL SECURITY;

CREATE TRIGGER z_touch BEFORE UPDATE ON "docs"."ticket_attachments" FOR EACH ROW EXECUTE FUNCTION infrastructure.touch_row();

ALTER TABLE "docs"."ticket_attachments" ADD CONSTRAINT "c_427ced482010b5d78a74" CHECK (visibility IN ('client','internal'));

ALTER TABLE "docs"."ticket_attachments" ADD CONSTRAINT "c_98c3e99fedcfc4c0f43d" UNIQUE NULLS NOT DISTINCT ("ticket_id", "message_id", "file_id");

CREATE TABLE "docs"."project_documents" (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "project_id" uuid NOT NULL,
  "document_id" uuid NOT NULL,
  "role" text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  row_version bigint NOT NULL DEFAULT 1 CHECK(row_version>0)
);

COMMENT ON TABLE "docs"."project_documents" IS 'Documents rattachés aux projets | Catalogue: Pas de publication web implicite.';

ALTER TABLE "docs"."project_documents" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "docs"."project_documents" FORCE ROW LEVEL SECURITY;

CREATE TRIGGER z_touch BEFORE UPDATE ON "docs"."project_documents" FOR EACH ROW EXECUTE FUNCTION infrastructure.touch_row();

ALTER TABLE "docs"."project_documents" ADD CONSTRAINT "c_8586766cadc7cd0a87c0" UNIQUE NULLS NOT DISTINCT ("project_id", "document_id", "role");

CREATE TABLE "docs"."item_documents" (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "item_id" uuid NOT NULL,
  "document_id" uuid NOT NULL,
  "portal_visible" boolean NOT NULL,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  row_version bigint NOT NULL DEFAULT 1 CHECK(row_version>0)
);

COMMENT ON TABLE "docs"."item_documents" IS 'Notices, preuves et documents du parc | Catalogue: Visibilité par champ et pièce ; documents techniques sensibles exclus du portail.';

ALTER TABLE "docs"."item_documents" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "docs"."item_documents" FORCE ROW LEVEL SECURITY;

CREATE TRIGGER z_touch BEFORE UPDATE ON "docs"."item_documents" FOR EACH ROW EXECUTE FUNCTION infrastructure.touch_row();

ALTER TABLE "docs"."item_documents" ADD CONSTRAINT "c_b27cb97188bfe1b2dec8" UNIQUE NULLS NOT DISTINCT ("item_id", "document_id");

CREATE TABLE "docs"."document_access_events" (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "file_id" uuid NOT NULL,
  "principal_id" uuid NOT NULL,
  "action" text NOT NULL,
  "occurred_at" timestamptz NOT NULL,
  "request_id" text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  row_version bigint NOT NULL DEFAULT 1 CHECK(row_version>0)
);

COMMENT ON TABLE "docs"."document_access_events" IS 'Consultation et export sensibles | Catalogue: Journaux sans contenu ni URL signée persistante.';

ALTER TABLE "docs"."document_access_events" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "docs"."document_access_events" FORCE ROW LEVEL SECURITY;

CREATE TRIGGER z_touch BEFORE UPDATE ON "docs"."document_access_events" FOR EACH ROW EXECUTE FUNCTION infrastructure.touch_row();

CREATE TRIGGER a_immutable BEFORE UPDATE OR DELETE ON "docs"."document_access_events" FOR EACH ROW EXECUTE FUNCTION infrastructure.reject_mutation();
CREATE TRIGGER a_no_truncate BEFORE TRUNCATE ON "docs"."document_access_events" FOR EACH STATEMENT EXECUTE FUNCTION infrastructure.reject_mutation();

CREATE TABLE "comms"."mailboxes" (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "address" text NOT NULL,
  "connection_id" uuid NOT NULL,
  "default_team_id" uuid,
  "active" boolean NOT NULL,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  row_version bigint NOT NULL DEFAULT 1 CHECK(row_version>0)
);

COMMENT ON TABLE "comms"."mailboxes" IS 'Boîtes de réception de support | Catalogue: Secrets du fournisseur dans coffre, pas dans la fiche.';

ALTER TABLE "comms"."mailboxes" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "comms"."mailboxes" FORCE ROW LEVEL SECURITY;

CREATE TRIGGER z_touch BEFORE UPDATE ON "comms"."mailboxes" FOR EACH ROW EXECUTE FUNCTION infrastructure.touch_row();

ALTER TABLE "comms"."mailboxes" ADD CONSTRAINT "c_5bd06f738899804ffb1b" UNIQUE NULLS NOT DISTINCT ("address");

CREATE TABLE "comms"."inbound_messages" (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "mailbox_id" uuid NOT NULL,
  "provider_message_id" text NOT NULL,
  "internet_message_id" text,
  "in_reply_to" text,
  "from_address" text NOT NULL,
  "received_at" timestamptz NOT NULL,
  "processing_status" text NOT NULL,
  "ticket_id" uuid,
  "raw_file_id" uuid,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  row_version bigint NOT NULL DEFAULT 1 CHECK(row_version>0)
);

COMMENT ON TABLE "comms"."inbound_messages" IS 'Messages reçus et déduplication | Catalogue: UNIQUE boîte + ID fournisseur ; expéditeur, signature de fil et destinataires contrôlés.';

ALTER TABLE "comms"."inbound_messages" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "comms"."inbound_messages" FORCE ROW LEVEL SECURITY;

CREATE TRIGGER z_touch BEFORE UPDATE ON "comms"."inbound_messages" FOR EACH ROW EXECUTE FUNCTION infrastructure.touch_row();

ALTER TABLE "comms"."inbound_messages" ADD CONSTRAINT "c_9d16a503513489c0e18a" UNIQUE NULLS NOT DISTINCT ("mailbox_id", "provider_message_id");

CREATE TABLE "comms"."outbound_messages" (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "ticket_message_id" uuid,
  "recipient" text NOT NULL,
  "template_key" text NOT NULL,
  "payload" jsonb NOT NULL,
  "status" text NOT NULL,
  "idempotency_key" text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  row_version bigint NOT NULL DEFAULT 1 CHECK(row_version>0)
);

COMMENT ON TABLE "comms"."outbound_messages" IS 'Messages à transmettre | Catalogue: Une note interne ne devient jamais email client ; preuve des tentatives.';

ALTER TABLE "comms"."outbound_messages" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "comms"."outbound_messages" FORCE ROW LEVEL SECURITY;

CREATE TRIGGER z_touch BEFORE UPDATE ON "comms"."outbound_messages" FOR EACH ROW EXECUTE FUNCTION infrastructure.touch_row();

ALTER TABLE "comms"."outbound_messages" ADD CONSTRAINT "c_4015e98dbc98da2850c4" UNIQUE NULLS NOT DISTINCT ("idempotency_key");

CREATE TABLE "comms"."delivery_attempts" (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "outbound_id" uuid NOT NULL,
  "attempt" integer NOT NULL,
  "sent_at" timestamptz,
  "provider_id" text,
  "result" text NOT NULL,
  "error_code" text,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  row_version bigint NOT NULL DEFAULT 1 CHECK(row_version>0)
);

COMMENT ON TABLE "comms"."delivery_attempts" IS 'Distribution, erreurs et rebonds | Catalogue: Reprise bornée ; arrêt sur rebonds définitifs.';

ALTER TABLE "comms"."delivery_attempts" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "comms"."delivery_attempts" FORCE ROW LEVEL SECURITY;

CREATE TRIGGER z_touch BEFORE UPDATE ON "comms"."delivery_attempts" FOR EACH ROW EXECUTE FUNCTION infrastructure.touch_row();

ALTER TABLE "comms"."delivery_attempts" ADD CONSTRAINT "c_01cacc2c5860e5e71c15" CHECK ("attempt" > 0);

ALTER TABLE "comms"."delivery_attempts" ADD CONSTRAINT "c_f17bc42a20bec9f980ed" UNIQUE NULLS NOT DISTINCT ("outbound_id", "attempt");

CREATE TABLE "comms"."notification_templates" (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "code" text NOT NULL,
  "locale" text NOT NULL,
  "channel" text NOT NULL,
  "version_no" integer NOT NULL,
  "subject" text,
  "body" text NOT NULL,
  "active" boolean NOT NULL,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  row_version bigint NOT NULL DEFAULT 1 CHECK(row_version>0)
);

COMMENT ON TABLE "comms"."notification_templates" IS 'Textes paramétrables versionnés | Catalogue: Variables autorisées ; échappement du contenu.';

ALTER TABLE "comms"."notification_templates" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "comms"."notification_templates" FORCE ROW LEVEL SECURITY;

CREATE TRIGGER z_touch BEFORE UPDATE ON "comms"."notification_templates" FOR EACH ROW EXECUTE FUNCTION infrastructure.touch_row();

ALTER TABLE "comms"."notification_templates" ADD CONSTRAINT "c_435cc0d0fe5b5dc3de4a" CHECK ("version_no" > 0);

ALTER TABLE "comms"."notification_templates" ADD CONSTRAINT "c_6e2eb641bd679918e24b" UNIQUE NULLS NOT DISTINCT ("code", "locale", "channel", "version_no");

CREATE TABLE "comms"."notifications" (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "principal_id" uuid NOT NULL,
  "event_key" text NOT NULL,
  "kind" text NOT NULL,
  "target_ref" text NOT NULL,
  "created_at" timestamptz DEFAULT clock_timestamp() NOT NULL,
  "read_at" timestamptz,
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  row_version bigint NOT NULL DEFAULT 1 CHECK(row_version>0)
);

COMMENT ON TABLE "comms"."notifications" IS 'Notifications dans l’application | Catalogue: Cible recontrôlée à l’ouverture ; pas de fuite par aperçu.';

ALTER TABLE "comms"."notifications" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "comms"."notifications" FORCE ROW LEVEL SECURITY;

CREATE TRIGGER z_touch BEFORE UPDATE ON "comms"."notifications" FOR EACH ROW EXECUTE FUNCTION infrastructure.touch_row();

ALTER TABLE "comms"."notifications" ADD CONSTRAINT "c_5edf90d0854f53a2dea7" UNIQUE NULLS NOT DISTINCT ("principal_id", "event_key", "kind");

CREATE TABLE "comms"."surveys" (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "code" text NOT NULL,
  "name" text NOT NULL,
  "version_no" integer NOT NULL,
  "questions" jsonb NOT NULL,
  "active" boolean NOT NULL,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  row_version bigint NOT NULL DEFAULT 1 CHECK(row_version>0)
);

COMMENT ON TABLE "comms"."surveys" IS 'Enquêtes configurables | Catalogue: Échelle et questionnaire versionnés.';

ALTER TABLE "comms"."surveys" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "comms"."surveys" FORCE ROW LEVEL SECURITY;

CREATE TRIGGER z_touch BEFORE UPDATE ON "comms"."surveys" FOR EACH ROW EXECUTE FUNCTION infrastructure.touch_row();

ALTER TABLE "comms"."surveys" ADD CONSTRAINT "c_46f9734af7fc1a65b48f" CHECK ("version_no" > 0);

ALTER TABLE "comms"."surveys" ADD CONSTRAINT "c_f73b5b082d7f6ea6d1d4" UNIQUE NULLS NOT DISTINCT ("code", "version_no");

CREATE TABLE "comms"."survey_invitations" (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "survey_id" uuid NOT NULL,
  "ticket_id" uuid NOT NULL,
  "person_id" uuid NOT NULL,
  "token_hash" text NOT NULL,
  "sent_at" timestamptz NOT NULL,
  "expires_at" timestamptz NOT NULL,
  "responded_at" timestamptz,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  row_version bigint NOT NULL DEFAULT 1 CHECK(row_version>0)
);

COMMENT ON TABLE "comms"."survey_invitations" IS 'Enquêtes envoyées après support | Catalogue: Jeton à durée limitée ; une invitation par cycle configuré.';

ALTER TABLE "comms"."survey_invitations" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "comms"."survey_invitations" FORCE ROW LEVEL SECURITY;

CREATE TRIGGER z_touch BEFORE UPDATE ON "comms"."survey_invitations" FOR EACH ROW EXECUTE FUNCTION infrastructure.touch_row();

ALTER TABLE "comms"."survey_invitations" ADD CONSTRAINT "c_a593a1f4bae9a3970c4f" UNIQUE NULLS NOT DISTINCT ("token_hash");

CREATE TABLE "comms"."survey_answers" (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "invitation_id" uuid NOT NULL,
  "answers" jsonb NOT NULL,
  "submitted_at" timestamptz NOT NULL,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  row_version bigint NOT NULL DEFAULT 1 CHECK(row_version>0)
);

COMMENT ON TABLE "comms"."survey_answers" IS 'Réponses de satisfaction | Catalogue: UNIQUE invitation ; accès nominatif limité, agrégats pour pilotage.';

ALTER TABLE "comms"."survey_answers" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "comms"."survey_answers" FORCE ROW LEVEL SECURITY;

CREATE TRIGGER z_touch BEFORE UPDATE ON "comms"."survey_answers" FOR EACH ROW EXECUTE FUNCTION infrastructure.touch_row();

ALTER TABLE "comms"."survey_answers" ADD CONSTRAINT "c_4e725fea51078875b614" UNIQUE NULLS NOT DISTINCT ("invitation_id");

CREATE TABLE "integration"."connections" (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "code" text NOT NULL,
  "kind" text NOT NULL,
  "provider" text NOT NULL,
  "base_url" text,
  "secret_ref" text,
  "direction" text NOT NULL,
  "status" text NOT NULL,
  "config" jsonb NOT NULL,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  row_version bigint NOT NULL DEFAULT 1 CHECK(row_version>0)
);

COMMENT ON TABLE "integration"."connections" IS 'Connexions aux outils externes | Catalogue: Config validée sans secrets ; destination et permissions bornées.';

ALTER TABLE "integration"."connections" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "integration"."connections" FORCE ROW LEVEL SECURITY;

CREATE TRIGGER z_touch BEFORE UPDATE ON "integration"."connections" FOR EACH ROW EXECUTE FUNCTION infrastructure.touch_row();

ALTER TABLE "integration"."connections" ADD CONSTRAINT "c_fc2ae2ea424885a95c74" UNIQUE NULLS NOT DISTINCT ("code");

CREATE TABLE "integration"."external_mappings" (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "connection_id" uuid NOT NULL,
  "external_type" text NOT NULL,
  "external_id" text NOT NULL,
  "local_kind" text NOT NULL,
  "local_id" uuid NOT NULL,
  "last_seen_at" timestamptz NOT NULL,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  row_version bigint NOT NULL DEFAULT 1 CHECK(row_version>0)
);

COMMENT ON TABLE "integration"."external_mappings" IS 'Correspondances d’identifiants | Catalogue: UNIQUE connexion + type + ID ; registre technique polymorphe validé côté service, pas FK métier.';

ALTER TABLE "integration"."external_mappings" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "integration"."external_mappings" FORCE ROW LEVEL SECURITY;

CREATE TRIGGER z_touch BEFORE UPDATE ON "integration"."external_mappings" FOR EACH ROW EXECUTE FUNCTION infrastructure.touch_row();

ALTER TABLE "integration"."external_mappings" ADD CONSTRAINT "c_de6e9f3e9afbb0a7aa03" UNIQUE NULLS NOT DISTINCT ("connection_id", "external_type", "external_id");

CREATE TABLE "integration"."sync_runs" (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "connection_id" uuid NOT NULL,
  "started_at" timestamptz NOT NULL,
  "finished_at" timestamptz,
  "cursor_in" text,
  "cursor_out" text,
  "status" text NOT NULL,
  "counts" jsonb NOT NULL,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  row_version bigint NOT NULL DEFAULT 1 CHECK(row_version>0)
);

COMMENT ON TABLE "integration"."sync_runs" IS 'Exécutions de synchronisation | Catalogue: Reprise sur curseur confirmé ; aucune suppression de parc sur simple absence d’une collecte.';

ALTER TABLE "integration"."sync_runs" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "integration"."sync_runs" FORCE ROW LEVEL SECURITY;

CREATE TRIGGER z_touch BEFORE UPDATE ON "integration"."sync_runs" FOR EACH ROW EXECUTE FUNCTION infrastructure.touch_row();

ALTER TABLE "integration"."sync_runs" ADD CONSTRAINT "c_8ece3fa45a60e6de607d" CHECK ("finished_at" >= "started_at");

CREATE TABLE "integration"."sync_conflicts" (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "run_id" uuid NOT NULL,
  "mapping_id" uuid NOT NULL,
  "field_name" text NOT NULL,
  "local_value" jsonb NOT NULL,
  "remote_value" jsonb NOT NULL,
  "resolution" text,
  "resolved_by" uuid,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  row_version bigint NOT NULL DEFAULT 1 CHECK(row_version>0)
);

COMMENT ON TABLE "integration"."sync_conflicts" IS 'Conflits de données | Catalogue: Autorité par champ ; journal des arbitrages.';

ALTER TABLE "integration"."sync_conflicts" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "integration"."sync_conflicts" FORCE ROW LEVEL SECURITY;

CREATE TRIGGER z_touch BEFORE UPDATE ON "integration"."sync_conflicts" FOR EACH ROW EXECUTE FUNCTION infrastructure.touch_row();

CREATE TABLE "integration"."inbox_events" (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "connection_id" uuid NOT NULL,
  "external_event_id" text NOT NULL,
  "event_type" text NOT NULL,
  "received_at" timestamptz NOT NULL,
  "payload" jsonb NOT NULL,
  "status" text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  row_version bigint NOT NULL DEFAULT 1 CHECK(row_version>0)
);

COMMENT ON TABLE "integration"."inbox_events" IS 'Événements reçus | Catalogue: UNIQUE connexion + événement ; validation et contrôle de signature selon fournisseur.';

ALTER TABLE "integration"."inbox_events" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "integration"."inbox_events" FORCE ROW LEVEL SECURITY;

CREATE TRIGGER z_touch BEFORE UPDATE ON "integration"."inbox_events" FOR EACH ROW EXECUTE FUNCTION infrastructure.touch_row();

ALTER TABLE "integration"."inbox_events" ADD CONSTRAINT "c_65490db5e28bafdb8de5" UNIQUE NULLS NOT DISTINCT ("connection_id", "external_event_id");

CREATE TABLE "integration"."outbox_events" (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "event_id" text NOT NULL,
  "event_type" text NOT NULL,
  "aggregate_type" text NOT NULL,
  "aggregate_id" uuid NOT NULL,
  "payload" jsonb NOT NULL,
  "occurred_at" timestamptz NOT NULL,
  "published_at" timestamptz,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  row_version bigint NOT NULL DEFAULT 1 CHECK(row_version>0)
);

COMMENT ON TABLE "integration"."outbox_events" IS 'Événements métier à publier | Catalogue: Insérés dans la transaction métier ; livraison au moins une fois, consommateurs idempotents.';

ALTER TABLE "integration"."outbox_events" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "integration"."outbox_events" FORCE ROW LEVEL SECURITY;

CREATE TRIGGER z_touch BEFORE UPDATE ON "integration"."outbox_events" FOR EACH ROW EXECUTE FUNCTION infrastructure.touch_row();

CREATE TRIGGER a_published BEFORE UPDATE OR DELETE ON "integration"."outbox_events" FOR EACH ROW EXECUTE FUNCTION infrastructure.freeze_published();

ALTER TABLE "integration"."outbox_events" ADD CONSTRAINT "c_e4b80d9ed6b91c3b4ab2" UNIQUE NULLS NOT DISTINCT ("event_id");

CREATE TABLE "integration"."webhook_subscriptions" (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "connection_id" uuid NOT NULL,
  "event_types" jsonb NOT NULL,
  "destination_url" text NOT NULL,
  "signing_secret_ref" text NOT NULL,
  "active" boolean NOT NULL,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  row_version bigint NOT NULL DEFAULT 1 CHECK(row_version>0)
);

COMMENT ON TABLE "integration"."webhook_subscriptions" IS 'Destinations des événements | Catalogue: Prévenir destinations internes non autorisées ; ne pas exposer des champs au-delà du scope.';

ALTER TABLE "integration"."webhook_subscriptions" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "integration"."webhook_subscriptions" FORCE ROW LEVEL SECURITY;

CREATE TRIGGER z_touch BEFORE UPDATE ON "integration"."webhook_subscriptions" FOR EACH ROW EXECUTE FUNCTION infrastructure.touch_row();

CREATE TABLE "integration"."webhook_deliveries" (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "subscription_id" uuid NOT NULL,
  "outbox_event_id" uuid NOT NULL,
  "attempt" integer NOT NULL,
  "result" text NOT NULL,
  "next_attempt_at" timestamptz,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  row_version bigint NOT NULL DEFAULT 1 CHECK(row_version>0)
);

COMMENT ON TABLE "integration"."webhook_deliveries" IS 'Tentatives de livraison | Catalogue: Backoff, limite puis file d’échec ; événement rejouable.';

ALTER TABLE "integration"."webhook_deliveries" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "integration"."webhook_deliveries" FORCE ROW LEVEL SECURITY;

CREATE TRIGGER z_touch BEFORE UPDATE ON "integration"."webhook_deliveries" FOR EACH ROW EXECUTE FUNCTION infrastructure.touch_row();

ALTER TABLE "integration"."webhook_deliveries" ADD CONSTRAINT "c_a7c108c5d62f7da7000d" CHECK ("attempt" > 0);

ALTER TABLE "integration"."webhook_deliveries" ADD CONSTRAINT "c_a9f0bbf706516ff9913b" UNIQUE NULLS NOT DISTINCT ("subscription_id", "outbox_event_id", "attempt");

CREATE TABLE "integration"."monitor_alerts" (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "connection_id" uuid NOT NULL,
  "external_alert_key" text NOT NULL,
  "item_id" uuid,
  "severity" text NOT NULL,
  "summary" text NOT NULL,
  "first_seen_at" timestamptz NOT NULL,
  "last_seen_at" timestamptz NOT NULL,
  "status" text NOT NULL,
  "ticket_id" uuid,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  row_version bigint NOT NULL DEFAULT 1 CHECK(row_version>0)
);

COMMENT ON TABLE "integration"."monitor_alerts" IS 'Alertes issues de la supervision | Catalogue: Déduplication et corrélation ; fin d’alerte ne clôture pas seule un ticket client.';

ALTER TABLE "integration"."monitor_alerts" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "integration"."monitor_alerts" FORCE ROW LEVEL SECURITY;

CREATE TRIGGER z_touch BEFORE UPDATE ON "integration"."monitor_alerts" FOR EACH ROW EXECUTE FUNCTION infrastructure.touch_row();

ALTER TABLE "integration"."monitor_alerts" ADD CONSTRAINT "c_b12bdfd212e784f485b1" UNIQUE NULLS NOT DISTINCT ("connection_id", "external_alert_key");

CREATE TABLE "integration"."import_jobs" (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "source" text NOT NULL,
  "file_id" uuid,
  "status" text NOT NULL,
  "started_at" timestamptz NOT NULL,
  "finished_at" timestamptz,
  "validation_report" jsonb NOT NULL,
  "dry_run" boolean NOT NULL,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  row_version bigint NOT NULL DEFAULT 1 CHECK(row_version>0)
);

COMMENT ON TABLE "integration"."import_jobs" IS 'Imports de fichiers et migrations | Catalogue: Prévisualisation des erreurs ; import idempotent ; données d’origine conservées selon rétention.';

ALTER TABLE "integration"."import_jobs" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "integration"."import_jobs" FORCE ROW LEVEL SECURITY;

CREATE TRIGGER z_touch BEFORE UPDATE ON "integration"."import_jobs" FOR EACH ROW EXECUTE FUNCTION infrastructure.touch_row();

ALTER TABLE "integration"."import_jobs" ADD CONSTRAINT "c_3e04879c9c41c37957cf" CHECK ("finished_at" >= "started_at");

CREATE TABLE "integration"."import_rows" (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "job_id" uuid NOT NULL,
  "row_number" integer NOT NULL,
  "source_key" text,
  "status" text NOT NULL,
  "error_code" text,
  "local_kind" text,
  "local_id" uuid,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  row_version bigint NOT NULL DEFAULT 1 CHECK(row_version>0)
);

COMMENT ON TABLE "integration"."import_rows" IS 'Résultats et rejets par ligne | Catalogue: Résultats techniques, pas copie indéfinie des données sensibles.';

ALTER TABLE "integration"."import_rows" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "integration"."import_rows" FORCE ROW LEVEL SECURITY;

CREATE TRIGGER z_touch BEFORE UPDATE ON "integration"."import_rows" FOR EACH ROW EXECUTE FUNCTION infrastructure.touch_row();

ALTER TABLE "integration"."import_rows" ADD CONSTRAINT "c_f67ea96e673334550f4c" CHECK ("row_number" > 0);

ALTER TABLE "integration"."import_rows" ADD CONSTRAINT "c_1afa3d5406039d7e053c" UNIQUE NULLS NOT DISTINCT ("job_id", "row_number");

CREATE TABLE "reporting"."metric_definitions" (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "code" text NOT NULL,
  "version_no" integer NOT NULL,
  "label" text NOT NULL,
  "unit" text NOT NULL,
  "definition" text NOT NULL,
  "aggregation_rule" jsonb NOT NULL,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  row_version bigint NOT NULL DEFAULT 1 CHECK(row_version>0)
);

COMMENT ON TABLE "reporting"."metric_definitions" IS 'Définitions versionnées des indicateurs | Catalogue: Backlog, MTTR, respect des délais, charge, satisfaction, valorisation définis sans ambiguïté.';

ALTER TABLE "reporting"."metric_definitions" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "reporting"."metric_definitions" FORCE ROW LEVEL SECURITY;

CREATE TRIGGER z_touch BEFORE UPDATE ON "reporting"."metric_definitions" FOR EACH ROW EXECUTE FUNCTION infrastructure.touch_row();

ALTER TABLE "reporting"."metric_definitions" ADD CONSTRAINT "c_a1160439cbfa94581b1d" CHECK ("version_no" > 0);

ALTER TABLE "reporting"."metric_definitions" ADD CONSTRAINT "c_d85387b5d621ef7bda7e" UNIQUE NULLS NOT DISTINCT ("code", "version_no");

CREATE TABLE "reporting"."report_definitions" (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "code" text NOT NULL,
  "name" text NOT NULL,
  "version_no" integer NOT NULL,
  "required_feature" text,
  "parameters_schema" jsonb NOT NULL,
  "query_key" text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  row_version bigint NOT NULL DEFAULT 1 CHECK(row_version>0)
);

COMMENT ON TABLE "reporting"."report_definitions" IS 'Rapports disponibles par module | Catalogue: Requêtes prédéfinies autorisées, pas SQL libre utilisateur.';

ALTER TABLE "reporting"."report_definitions" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "reporting"."report_definitions" FORCE ROW LEVEL SECURITY;

CREATE TRIGGER z_touch BEFORE UPDATE ON "reporting"."report_definitions" FOR EACH ROW EXECUTE FUNCTION infrastructure.touch_row();

ALTER TABLE "reporting"."report_definitions" ADD CONSTRAINT "c_a52d16eacf1cbbf2a283" CHECK ("version_no" > 0);

ALTER TABLE "reporting"."report_definitions" ADD CONSTRAINT "c_353cc78db6e6a433b837" UNIQUE NULLS NOT DISTINCT ("code", "version_no");

CREATE TABLE "reporting"."report_runs" (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "definition_id" uuid NOT NULL,
  "requested_by" uuid NOT NULL,
  "scope_snapshot" jsonb NOT NULL,
  "parameters" jsonb NOT NULL,
  "source_cutoff_at" timestamptz NOT NULL,
  "status" text NOT NULL,
  "generated_at" timestamptz,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  row_version bigint NOT NULL DEFAULT 1 CHECK(row_version>0)
);

COMMENT ON TABLE "reporting"."report_runs" IS 'Générations de rapports | Catalogue: Vérifier permissions et abonnement à la demande puis au téléchargement.';

ALTER TABLE "reporting"."report_runs" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "reporting"."report_runs" FORCE ROW LEVEL SECURITY;

CREATE TRIGGER z_touch BEFORE UPDATE ON "reporting"."report_runs" FOR EACH ROW EXECUTE FUNCTION infrastructure.touch_row();

CREATE TABLE "reporting"."report_files" (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "run_id" uuid NOT NULL,
  "format" text NOT NULL,
  "file_id" uuid NOT NULL,
  "expires_at" timestamptz,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  row_version bigint NOT NULL DEFAULT 1 CHECK(row_version>0)
);

COMMENT ON TABLE "reporting"."report_files" IS 'Formats d’un même rapport | Catalogue: PDF, XLSX, CSV, JSON ; protection contre formules actives injectées dans les exports tableurs.';

ALTER TABLE "reporting"."report_files" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "reporting"."report_files" FORCE ROW LEVEL SECURITY;

CREATE TRIGGER z_touch BEFORE UPDATE ON "reporting"."report_files" FOR EACH ROW EXECUTE FUNCTION infrastructure.touch_row();

CREATE TABLE "reporting"."report_schedules" (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "definition_id" uuid NOT NULL,
  "owner_id" uuid NOT NULL,
  "recurrence" text NOT NULL,
  "parameters" jsonb NOT NULL,
  "active" boolean NOT NULL,
  "next_run_at" timestamptz,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  row_version bigint NOT NULL DEFAULT 1 CHECK(row_version>0)
);

COMMENT ON TABLE "reporting"."report_schedules" IS 'Générations périodiques | Catalogue: Réévaluer les droits après révocation ; destinataires explicitement autorisés.';

ALTER TABLE "reporting"."report_schedules" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "reporting"."report_schedules" FORCE ROW LEVEL SECURITY;

CREATE TRIGGER z_touch BEFORE UPDATE ON "reporting"."report_schedules" FOR EACH ROW EXECUTE FUNCTION infrastructure.touch_row();

CREATE TABLE "reporting"."dashboard_layouts" (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "principal_id" uuid NOT NULL,
  "name" text NOT NULL,
  "widgets" jsonb NOT NULL,
  "scope" jsonb NOT NULL,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  row_version bigint NOT NULL DEFAULT 1 CHECK(row_version>0)
);

COMMENT ON TABLE "reporting"."dashboard_layouts" IS 'Tableaux de bord personnels | Catalogue: Personnalisation d’affichage, jamais contournement des filtres de sécurité.';

ALTER TABLE "reporting"."dashboard_layouts" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "reporting"."dashboard_layouts" FORCE ROW LEVEL SECURITY;

CREATE TRIGGER z_touch BEFORE UPDATE ON "reporting"."dashboard_layouts" FOR EACH ROW EXECUTE FUNCTION infrastructure.touch_row();

CREATE TABLE "reporting"."daily_support_facts" (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "local_date" date NOT NULL,
  "customer_org_id" uuid NOT NULL,
  "team_id" uuid,
  "metric_code" text NOT NULL,
  "metric_version" integer NOT NULL,
  "value" numeric(20,6) NOT NULL,
  "computed_at" timestamptz NOT NULL,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  row_version bigint NOT NULL DEFAULT 1 CHECK(row_version>0)
);

COMMENT ON TABLE "reporting"."daily_support_facts" IS 'Agrégats reconstruisibles | Catalogue: Grain complet défini avant déploiement ; suppression/reconstruction possible depuis les sources.';

ALTER TABLE "reporting"."daily_support_facts" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "reporting"."daily_support_facts" FORCE ROW LEVEL SECURITY;

CREATE TRIGGER z_touch BEFORE UPDATE ON "reporting"."daily_support_facts" FOR EACH ROW EXECUTE FUNCTION infrastructure.touch_row();

ALTER TABLE "reporting"."daily_support_facts" ADD CONSTRAINT "c_82dd27c41982c90bc08a" CHECK ("metric_version" > 0);

ALTER TABLE "reporting"."daily_support_facts" ADD CONSTRAINT "c_be2d1097f97958a74148" CHECK ("value" <> 'NaN'::numeric);

ALTER TABLE "reporting"."daily_support_facts" ADD CONSTRAINT "c_0426398616e8430ee473" UNIQUE NULLS NOT DISTINCT ("local_date", "customer_org_id", "team_id", "metric_code", "metric_version");

CREATE TABLE "governance"."audit_events" (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "actor_id" uuid,
  "action" text NOT NULL,
  "resource_type" text NOT NULL,
  "resource_id" uuid,
  "occurred_at" timestamptz NOT NULL,
  "request_id" text NOT NULL,
  "reason" text,
  "changed_fields" jsonb NOT NULL,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  row_version bigint NOT NULL DEFAULT 1 CHECK(row_version>0)
);

COMMENT ON TABLE "governance"."audit_events" IS 'Traçabilité des actions sensibles | Catalogue: Ajout seulement par service ; diff expurgé ; extraction d’audit séparée pour résistance à l’altération.';

ALTER TABLE "governance"."audit_events" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "governance"."audit_events" FORCE ROW LEVEL SECURITY;

CREATE TRIGGER z_touch BEFORE UPDATE ON "governance"."audit_events" FOR EACH ROW EXECUTE FUNCTION infrastructure.touch_row();

CREATE TRIGGER a_immutable BEFORE UPDATE OR DELETE ON "governance"."audit_events" FOR EACH ROW EXECUTE FUNCTION infrastructure.reject_mutation();
CREATE TRIGGER a_no_truncate BEFORE TRUNCATE ON "governance"."audit_events" FOR EACH STATEMENT EXECUTE FUNCTION infrastructure.reject_mutation();

CREATE TABLE "governance"."field_definitions" (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "entity_type" text NOT NULL,
  "field_key" text NOT NULL,
  "label" text NOT NULL,
  "data_type" text NOT NULL,
  "required" boolean NOT NULL,
  "validation" jsonb NOT NULL,
  "sensitivity" text NOT NULL,
  "version_no" integer NOT NULL,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  row_version bigint NOT NULL DEFAULT 1 CHECK(row_version>0)
);

COMMENT ON TABLE "governance"."field_definitions" IS 'Champs personnalisés par objet | Catalogue: Type stable/versionné ; champs critiques normalisés ; pas de relations centrales dans du JSON opaque.';

ALTER TABLE "governance"."field_definitions" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "governance"."field_definitions" FORCE ROW LEVEL SECURITY;

CREATE TRIGGER z_touch BEFORE UPDATE ON "governance"."field_definitions" FOR EACH ROW EXECUTE FUNCTION infrastructure.touch_row();

ALTER TABLE "governance"."field_definitions" ADD CONSTRAINT "c_b3f30919a9ca46431fa2" CHECK ("version_no" > 0);

ALTER TABLE "governance"."field_definitions" ADD CONSTRAINT "c_889a2d679f2f34e35cc3" UNIQUE NULLS NOT DISTINCT ("entity_type", "field_key", "version_no");

CREATE TABLE "governance"."field_values" (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "definition_id" uuid NOT NULL,
  "entity_type" text NOT NULL,
  "entity_id" uuid NOT NULL,
  "text_value" text,
  "number_value" numeric(20,6),
  "date_value" date,
  "boolean_value" boolean,
  "json_value" jsonb,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  row_version bigint NOT NULL DEFAULT 1 CHECK(row_version>0)
);

COMMENT ON TABLE "governance"."field_values" IS 'Valeurs des extensions | Catalogue: Une valeur typée selon définition ; registre d’entités validé, sans prétendre à une FK polymorphe native.';

ALTER TABLE "governance"."field_values" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "governance"."field_values" FORCE ROW LEVEL SECURITY;

CREATE TRIGGER z_touch BEFORE UPDATE ON "governance"."field_values" FOR EACH ROW EXECUTE FUNCTION infrastructure.touch_row();

ALTER TABLE "governance"."field_values" ADD CONSTRAINT "c_1489ff646e8842ff0cbd" CHECK (num_nonnulls(text_value,number_value,date_value,boolean_value,json_value)=1);

ALTER TABLE "governance"."field_values" ADD CONSTRAINT "c_3ab16f0eaf9270116622" CHECK ("number_value" <> 'NaN'::numeric);

ALTER TABLE "governance"."field_values" ADD CONSTRAINT "c_d2ae00cf3b668290a3af" UNIQUE NULLS NOT DISTINCT ("definition_id", "entity_type", "entity_id");

CREATE TABLE "governance"."retention_policies" (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "domain_code" text NOT NULL,
  "record_class" text NOT NULL,
  "retention_days" integer,
  "action" text NOT NULL,
  "trigger" text NOT NULL,
  "version_no" integer NOT NULL,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  row_version bigint NOT NULL DEFAULT 1 CHECK(row_version>0)
);

COMMENT ON TABLE "governance"."retention_policies" IS 'Durées et traitement des données | Catalogue: Durées à valider selon finalité ; indéfini nécessite justification explicite.';

ALTER TABLE "governance"."retention_policies" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "governance"."retention_policies" FORCE ROW LEVEL SECURITY;

CREATE TRIGGER z_touch BEFORE UPDATE ON "governance"."retention_policies" FOR EACH ROW EXECUTE FUNCTION infrastructure.touch_row();

ALTER TABLE "governance"."retention_policies" ADD CONSTRAINT "c_8d6c59f580c8462eed92" CHECK ("version_no" > 0);

ALTER TABLE "governance"."retention_policies" ADD CONSTRAINT "c_bb46dd5631977d917d52" UNIQUE NULLS NOT DISTINCT ("domain_code", "record_class", "version_no");

CREATE TABLE "governance"."legal_holds" (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "resource_type" text NOT NULL,
  "resource_id" uuid NOT NULL,
  "reason" text NOT NULL,
  "starts_at" timestamptz NOT NULL,
  "ends_at" timestamptz,
  "authorized_by" uuid NOT NULL,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  row_version bigint NOT NULL DEFAULT 1 CHECK(row_version>0)
);

COMMENT ON TABLE "governance"."legal_holds" IS 'Suspensions justifiées de purge | Catalogue: Accès restreint ; ne pas appliquer une conservation uniforme à toutes les données.';

ALTER TABLE "governance"."legal_holds" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "governance"."legal_holds" FORCE ROW LEVEL SECURITY;

CREATE TRIGGER z_touch BEFORE UPDATE ON "governance"."legal_holds" FOR EACH ROW EXECUTE FUNCTION infrastructure.touch_row();

ALTER TABLE "governance"."legal_holds" ADD CONSTRAINT "c_584a6f3d5b6d34a18f6d" CHECK ("ends_at" > "starts_at");

CREATE TABLE "governance"."data_requests" (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "requester_person_id" uuid NOT NULL,
  "request_type" text NOT NULL,
  "scope" jsonb NOT NULL,
  "status" text NOT NULL,
  "received_at" timestamptz NOT NULL,
  "completed_at" timestamptz,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  row_version bigint NOT NULL DEFAULT 1 CHECK(row_version>0)
);

COMMENT ON TABLE "governance"."data_requests" IS 'Demandes d’accès, correction, export ou suppression | Catalogue: Identité vérifiée ; traitement coordonné des copies, index, fichiers et sauvegardes.';

ALTER TABLE "governance"."data_requests" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "governance"."data_requests" FORCE ROW LEVEL SECURITY;

CREATE TRIGGER z_touch BEFORE UPDATE ON "governance"."data_requests" FOR EACH ROW EXECUTE FUNCTION infrastructure.touch_row();

CREATE TABLE "governance"."purge_runs" (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "policy_id" uuid NOT NULL,
  "started_at" timestamptz NOT NULL,
  "finished_at" timestamptz,
  "status" text NOT NULL,
  "counts" jsonb NOT NULL,
  "backup_expiry_on" date,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  row_version bigint NOT NULL DEFAULT 1 CHECK(row_version>0)
);

COMMENT ON TABLE "governance"."purge_runs" IS 'Exécution des règles de cycle de vie | Catalogue: Ne pas confondre soft delete et suppression effective ; trace sans recopier le contenu purgé.';

ALTER TABLE "governance"."purge_runs" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "governance"."purge_runs" FORCE ROW LEVEL SECURITY;

CREATE TRIGGER z_touch BEFORE UPDATE ON "governance"."purge_runs" FOR EACH ROW EXECUTE FUNCTION infrastructure.touch_row();

ALTER TABLE "governance"."purge_runs" ADD CONSTRAINT "c_5c552ec922e01dc69a21" CHECK ("finished_at" >= "started_at");

CREATE TABLE "governance"."schema_migrations" (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "version" text NOT NULL,
  "checksum" text NOT NULL,
  "started_at" timestamptz NOT NULL,
  "finished_at" timestamptz,
  "status" text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  row_version bigint NOT NULL DEFAULT 1 CHECK(row_version>0)
);

COMMENT ON TABLE "governance"."schema_migrations" IS 'Versions techniques appliquées | Catalogue: Historique de migration distinct des versions de forfait et de workflow.';

ALTER TABLE "governance"."schema_migrations" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "governance"."schema_migrations" FORCE ROW LEVEL SECURITY;

CREATE TRIGGER z_touch BEFORE UPDATE ON "governance"."schema_migrations" FOR EACH ROW EXECUTE FUNCTION infrastructure.touch_row();

ALTER TABLE "governance"."schema_migrations" ADD CONSTRAINT "c_6bd44e0e8055917fa571" CHECK ("finished_at" >= "started_at");

ALTER TABLE "governance"."schema_migrations" ADD CONSTRAINT "c_28fb0ece96a6a9d3724c" UNIQUE NULLS NOT DISTINCT ("version");

CREATE TABLE "governance"."idempotency_keys" (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "principal_id" uuid NOT NULL,
  "operation" text NOT NULL,
  "key" text NOT NULL,
  "request_hash" text NOT NULL,
  "result_ref" text NOT NULL,
  "expires_at" timestamptz NOT NULL,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  row_version bigint NOT NULL DEFAULT 1 CHECK(row_version>0)
);

COMMENT ON TABLE "governance"."idempotency_keys" IS 'Résultats d’opérations répétées | Catalogue: UNIQUE principal + opération + clé ; même clé avec corps différent rejetée.';

ALTER TABLE "governance"."idempotency_keys" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "governance"."idempotency_keys" FORCE ROW LEVEL SECURITY;

CREATE TRIGGER z_touch BEFORE UPDATE ON "governance"."idempotency_keys" FOR EACH ROW EXECUTE FUNCTION infrastructure.touch_row();

ALTER TABLE "governance"."idempotency_keys" ADD CONSTRAINT "c_cb8492e2548efe688a08" UNIQUE NULLS NOT DISTINCT ("principal_id", "operation", "key");

CREATE TABLE "governance"."legacy_ids" (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "source_system" text NOT NULL,
  "entity_type" text NOT NULL,
  "legacy_id" text NOT NULL,
  "new_id" uuid NOT NULL,
  "import_job_id" uuid,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  row_version bigint NOT NULL DEFAULT 1 CHECK(row_version>0)
);

COMMENT ON TABLE "governance"."legacy_ids" IS 'Correspondances de reprise | Catalogue: UNIQUE source + type + ancien ID ; aucune fusion silencieuse de personnes.';

ALTER TABLE "governance"."legacy_ids" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "governance"."legacy_ids" FORCE ROW LEVEL SECURITY;

CREATE TRIGGER z_touch BEFORE UPDATE ON "governance"."legacy_ids" FOR EACH ROW EXECUTE FUNCTION infrastructure.touch_row();

ALTER TABLE "governance"."legacy_ids" ADD CONSTRAINT "c_5826b1160980f3e72d9c" UNIQUE NULLS NOT DISTINCT ("source_system", "entity_type", "legacy_id");

ALTER TABLE "core"."installation" ADD CONSTRAINT "c_89db21ead96f1cbb3513" FOREIGN KEY ("operator_organization_id") REFERENCES "core"."organizations"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_52c26b11f18fe7932ee2" ON "core"."installation" ("operator_organization_id");

ALTER TABLE "core"."organization_identifiers" ADD CONSTRAINT "c_3d54845df70ee4abedea" FOREIGN KEY ("organization_id") REFERENCES "core"."organizations"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_b02951957e03ac362e5e" ON "core"."organization_identifiers" ("organization_id");

ALTER TABLE "core"."organization_relations" ADD CONSTRAINT "c_e702060f69aca0c63ba8" FOREIGN KEY ("parent_id") REFERENCES "core"."organizations"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_5abf1aa7c4478cf0a1e5" ON "core"."organization_relations" ("parent_id");

ALTER TABLE "core"."organization_relations" ADD CONSTRAINT "c_2edf9159c43f344a72e5" FOREIGN KEY ("child_id") REFERENCES "core"."organizations"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_97dccdd0c8417ab2dae8" ON "core"."organization_relations" ("child_id");

ALTER TABLE "core"."organization_roles" ADD CONSTRAINT "c_003ee06254db0ab881b2" FOREIGN KEY ("organization_id") REFERENCES "core"."organizations"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_2384cb8954217828b334" ON "core"."organization_roles" ("organization_id");

ALTER TABLE "core"."sites" ADD CONSTRAINT "c_7c4154f4576e0538458c" FOREIGN KEY ("organization_id") REFERENCES "core"."organizations"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_621762bbd60d0c00e15a" ON "core"."sites" ("organization_id");

ALTER TABLE "core"."sites" ADD CONSTRAINT "c_20634aa2dae9b3e27775" FOREIGN KEY ("address_id") REFERENCES "core"."addresses"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_a776de999bdd4fb7bfef" ON "core"."sites" ("address_id");

ALTER TABLE "core"."locations" ADD CONSTRAINT "c_da4eda0507e3fa952843" FOREIGN KEY ("site_id") REFERENCES "core"."sites"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_f8d2e55e093ac1945377" ON "core"."locations" ("site_id");

ALTER TABLE "core"."locations" ADD CONSTRAINT "c_6ee8b0e4600760c12a82" FOREIGN KEY ("parent_id") REFERENCES "core"."locations"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_4ee8dfd151cddb32acb4" ON "core"."locations" ("parent_id");

ALTER TABLE "core"."person_contacts" ADD CONSTRAINT "c_2d827f38962938b8ee72" FOREIGN KEY ("person_id") REFERENCES "core"."persons"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_5964f5fe4538019c2561" ON "core"."person_contacts" ("person_id");

ALTER TABLE "core"."affiliations" ADD CONSTRAINT "c_8dec658380b8741b0e71" FOREIGN KEY ("person_id") REFERENCES "core"."persons"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_0911377f0ab6152bc497" ON "core"."affiliations" ("person_id");

ALTER TABLE "core"."affiliations" ADD CONSTRAINT "c_fab69f2adb69c362a39a" FOREIGN KEY ("organization_id") REFERENCES "core"."organizations"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_1e8c3d28357c6a66fe93" ON "core"."affiliations" ("organization_id");

ALTER TABLE "core"."affiliations" ADD CONSTRAINT "c_bd583406d20487c380d3" FOREIGN KEY ("site_id") REFERENCES "core"."sites"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_28367c0fa43fd231b1c3" ON "core"."affiliations" ("site_id");

ALTER TABLE "core"."reporting_lines" ADD CONSTRAINT "c_8914215217442f2b442c" FOREIGN KEY ("manager_affiliation_id") REFERENCES "core"."affiliations"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_b9f6e7682dc8d3d29fc5" ON "core"."reporting_lines" ("manager_affiliation_id");

ALTER TABLE "core"."reporting_lines" ADD CONSTRAINT "c_e38b35f544d62a2bcf3b" FOREIGN KEY ("member_affiliation_id") REFERENCES "core"."affiliations"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_4fa16739c6c22cff6e29" ON "core"."reporting_lines" ("member_affiliation_id");

ALTER TABLE "core"."teams" ADD CONSTRAINT "c_523194f7058bb6f75ee0" FOREIGN KEY ("organization_id") REFERENCES "core"."organizations"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_16502ee4f537f232be8d" ON "core"."teams" ("organization_id");

ALTER TABLE "core"."teams" ADD CONSTRAINT "c_48124f4134a4db5f2f98" FOREIGN KEY ("parent_id") REFERENCES "core"."teams"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_a4aaaf41c1681b8b42b9" ON "core"."teams" ("parent_id");

ALTER TABLE "core"."team_memberships" ADD CONSTRAINT "c_4bab9b6dcf5908ec8cf7" FOREIGN KEY ("team_id") REFERENCES "core"."teams"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_d1b574bf9a84486ae897" ON "core"."team_memberships" ("team_id");

ALTER TABLE "core"."team_memberships" ADD CONSTRAINT "c_3c5ca6d3d8367d75978d" FOREIGN KEY ("person_id") REFERENCES "core"."persons"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_5b54a95770300264912f" ON "core"."team_memberships" ("person_id");

ALTER TABLE "iam"."principals" ADD CONSTRAINT "c_3bac4aaeaa2e34f688a5" FOREIGN KEY ("person_id") REFERENCES "core"."persons"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_cfa09f7c0695891b15a5" ON "iam"."principals" ("person_id");

ALTER TABLE "iam"."identity_links" ADD CONSTRAINT "c_288ab40be2b6d44fff8b" FOREIGN KEY ("principal_id") REFERENCES "iam"."principals"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_a6e960fa0bc9447db525" ON "iam"."identity_links" ("principal_id");

ALTER TABLE "iam"."permissions" ADD CONSTRAINT "c_3d1e89c82ad224e4de9c" FOREIGN KEY ("application_id") REFERENCES "iam"."applications"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_94a4cf680aeec758e3d1" ON "iam"."permissions" ("application_id");

ALTER TABLE "iam"."role_permissions" ADD CONSTRAINT "c_b2660d79c4abcb0bb476" FOREIGN KEY ("role_id") REFERENCES "iam"."roles"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_543064cf6b769c8435fa" ON "iam"."role_permissions" ("role_id");

ALTER TABLE "iam"."role_permissions" ADD CONSTRAINT "c_aba21de29fd7163e3aa1" FOREIGN KEY ("permission_id") REFERENCES "iam"."permissions"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_3da2496c442cd0123220" ON "iam"."role_permissions" ("permission_id");

ALTER TABLE "iam"."access_scopes" ADD CONSTRAINT "c_649c15d5b292058f72c0" FOREIGN KEY ("organization_id") REFERENCES "core"."organizations"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_c05e710f6e79e368a6fe" ON "iam"."access_scopes" ("organization_id");

ALTER TABLE "iam"."access_scopes" ADD CONSTRAINT "c_a8cfcd4b88518621902b" FOREIGN KEY ("site_id") REFERENCES "core"."sites"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_058fa4c3d117aa1e97d9" ON "iam"."access_scopes" ("site_id");

ALTER TABLE "iam"."access_scopes" ADD CONSTRAINT "c_77ac65b6c319ed684fe4" FOREIGN KEY ("team_id") REFERENCES "core"."teams"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_783abbd497b32d60c6f8" ON "iam"."access_scopes" ("team_id");

ALTER TABLE "iam"."access_scopes" ADD CONSTRAINT "c_0fecf6c9eaa11dbb640a" FOREIGN KEY ("project_id") REFERENCES "project"."projects"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_f50ccae6e968a764f2f9" ON "iam"."access_scopes" ("project_id");

ALTER TABLE "iam"."access_scopes" ADD CONSTRAINT "c_8783d0afd5ccd678e6d1" FOREIGN KEY ("subject_person_id") REFERENCES "core"."persons"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_42aa9bf69bf6d28b034a" ON "iam"."access_scopes" ("subject_person_id");

ALTER TABLE "iam"."role_bindings" ADD CONSTRAINT "c_baf59033c59cc61a79ce" FOREIGN KEY ("principal_id") REFERENCES "iam"."principals"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_9695e722d53c1431d016" ON "iam"."role_bindings" ("principal_id");

ALTER TABLE "iam"."role_bindings" ADD CONSTRAINT "c_201c1e2522f6ac092a43" FOREIGN KEY ("role_id") REFERENCES "iam"."roles"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_f562dc90d6b835f5fcf2" ON "iam"."role_bindings" ("role_id");

ALTER TABLE "iam"."role_bindings" ADD CONSTRAINT "c_0ce50e33712cfdd565b4" FOREIGN KEY ("scope_id") REFERENCES "iam"."access_scopes"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_e7a91834d701b26a3ed7" ON "iam"."role_bindings" ("scope_id");

ALTER TABLE "iam"."role_bindings" ADD CONSTRAINT "c_fae18b9db2225d161f0e" FOREIGN KEY ("granted_by") REFERENCES "iam"."principals"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_9e08f5058559180724c8" ON "iam"."role_bindings" ("granted_by");

ALTER TABLE "iam"."delegations" ADD CONSTRAINT "c_e76554fe4acba6bd7e07" FOREIGN KEY ("grantor_id") REFERENCES "iam"."principals"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_7c95f0707043e675f0cf" ON "iam"."delegations" ("grantor_id");

ALTER TABLE "iam"."delegations" ADD CONSTRAINT "c_77cfd7ecc182717d2d67" FOREIGN KEY ("delegate_id") REFERENCES "iam"."principals"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_e3ffdcc40c1f63dccf58" ON "iam"."delegations" ("delegate_id");

ALTER TABLE "iam"."delegations" ADD CONSTRAINT "c_cdc823c9c73c1d7048c1" FOREIGN KEY ("role_binding_id") REFERENCES "iam"."role_bindings"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_5e157a70e7240eda68d5" ON "iam"."delegations" ("role_binding_id");

ALTER TABLE "iam"."policy_versions" ADD CONSTRAINT "c_41dc10d55efbcf7ccfe3" FOREIGN KEY ("published_by") REFERENCES "iam"."principals"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_5907a7f684322dbec51a" ON "iam"."policy_versions" ("published_by");

ALTER TABLE "iam"."access_reviews" ADD CONSTRAINT "c_a58a01923268410f6b65" FOREIGN KEY ("role_binding_id") REFERENCES "iam"."role_bindings"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_79e206d4ab6ca801a8ab" ON "iam"."access_reviews" ("role_binding_id");

ALTER TABLE "iam"."access_reviews" ADD CONSTRAINT "c_d73d589c5d4befc98717" FOREIGN KEY ("reviewer_id") REFERENCES "iam"."principals"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_4c7fd3aaf03c8bef6a6a" ON "iam"."access_reviews" ("reviewer_id");

ALTER TABLE "iam"."service_credentials" ADD CONSTRAINT "c_07b849a4f247c2589628" FOREIGN KEY ("principal_id") REFERENCES "iam"."principals"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_1145daad46216d38b97e" ON "iam"."service_credentials" ("principal_id");

ALTER TABLE "crm"."accounts" ADD CONSTRAINT "c_88e73bcda64d2da6f23b" FOREIGN KEY ("organization_id") REFERENCES "core"."organizations"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_e22912b3bda1e6d47c42" ON "crm"."accounts" ("organization_id");

ALTER TABLE "crm"."accounts" ADD CONSTRAINT "c_01d32bf03210f2d532a6" FOREIGN KEY ("owner_id") REFERENCES "iam"."principals"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_11b70a174bf8dc273287" ON "crm"."accounts" ("owner_id");

ALTER TABLE "crm"."leads" ADD CONSTRAINT "c_ddbf640ce009fecf2718" FOREIGN KEY ("organization_id") REFERENCES "core"."organizations"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_210ed2b9ef2571c80793" ON "crm"."leads" ("organization_id");

ALTER TABLE "crm"."leads" ADD CONSTRAINT "c_4bfb2441d72ff16f9b33" FOREIGN KEY ("person_id") REFERENCES "core"."persons"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_98196cea838d7256a381" ON "crm"."leads" ("person_id");

ALTER TABLE "crm"."leads" ADD CONSTRAINT "c_a198cc63ba0af6dfc785" FOREIGN KEY ("source_request_id") REFERENCES "web"."contact_requests"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_1c5979e0f8a605debe1a" ON "crm"."leads" ("source_request_id");

ALTER TABLE "crm"."leads" ADD CONSTRAINT "c_16d20990a2b1706e21fc" FOREIGN KEY ("owner_id") REFERENCES "iam"."principals"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_454861a18a26731fb39a" ON "crm"."leads" ("owner_id");

ALTER TABLE "crm"."stages" ADD CONSTRAINT "c_34ec1de7106cdd9c0d6a" FOREIGN KEY ("pipeline_id") REFERENCES "crm"."pipelines"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_41d7fe2139a55bdaec9a" ON "crm"."stages" ("pipeline_id");

ALTER TABLE "crm"."opportunities" ADD CONSTRAINT "c_a9c27850d380e46a20ad" FOREIGN KEY ("account_id") REFERENCES "crm"."accounts"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_81c87b3369aba96365c2" ON "crm"."opportunities" ("account_id");

ALTER TABLE "crm"."opportunities" ADD CONSTRAINT "c_821f0c431e00aff519ba" FOREIGN KEY ("pipeline_id") REFERENCES "crm"."pipelines"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_cceb89c8f6602543e109" ON "crm"."opportunities" ("pipeline_id");

ALTER TABLE "crm"."opportunities" ADD CONSTRAINT "c_684d60f7e0a3b7326cea" FOREIGN KEY ("stage_id") REFERENCES "crm"."stages"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_12bc0b3896fc0b8dd662" ON "crm"."opportunities" ("stage_id");

ALTER TABLE "crm"."opportunities" ADD CONSTRAINT "c_86c0d07bfa28a6043193" FOREIGN KEY ("lead_id") REFERENCES "crm"."leads"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_73458870d5265a916fae" ON "crm"."opportunities" ("lead_id");

ALTER TABLE "crm"."opportunities" ADD CONSTRAINT "c_120a56dba5c7a55d138f" FOREIGN KEY ("owner_id") REFERENCES "iam"."principals"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_60276266bc91697238c9" ON "crm"."opportunities" ("owner_id");

ALTER TABLE "crm"."opportunity_contacts" ADD CONSTRAINT "c_97f7cf0df18f0953080d" FOREIGN KEY ("opportunity_id") REFERENCES "crm"."opportunities"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_a316d364de29664dabff" ON "crm"."opportunity_contacts" ("opportunity_id");

ALTER TABLE "crm"."opportunity_contacts" ADD CONSTRAINT "c_dba7077fa8590aa0e634" FOREIGN KEY ("affiliation_id") REFERENCES "core"."affiliations"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_09401c8467d75aaa8211" ON "crm"."opportunity_contacts" ("affiliation_id");

ALTER TABLE "crm"."opportunity_lines" ADD CONSTRAINT "c_f1000748aee4b165c73e" FOREIGN KEY ("opportunity_id") REFERENCES "crm"."opportunities"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_70ba835d77ec8bc97baf" ON "crm"."opportunity_lines" ("opportunity_id");

ALTER TABLE "crm"."opportunity_lines" ADD CONSTRAINT "c_2f3d318f24253e06f760" FOREIGN KEY ("product_id") REFERENCES "commercial"."products"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_838f860223853774946c" ON "crm"."opportunity_lines" ("product_id");

ALTER TABLE "crm"."opportunity_history" ADD CONSTRAINT "c_a1f2c2c980358be13610" FOREIGN KEY ("opportunity_id") REFERENCES "crm"."opportunities"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_91a889e03c65be53643b" ON "crm"."opportunity_history" ("opportunity_id");

ALTER TABLE "crm"."opportunity_history" ADD CONSTRAINT "c_c35e4502fa7cd0daf9db" FOREIGN KEY ("stage_id") REFERENCES "crm"."stages"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_af3b68513d5a2bd96642" ON "crm"."opportunity_history" ("stage_id");

ALTER TABLE "crm"."opportunity_history" ADD CONSTRAINT "c_e18182c54b20c319ae66" FOREIGN KEY ("actor_id") REFERENCES "iam"."principals"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_7851acf981e0364b6dbc" ON "crm"."opportunity_history" ("actor_id");

ALTER TABLE "crm"."activities" ADD CONSTRAINT "c_7e7398cd3cd02b5b2562" FOREIGN KEY ("account_id") REFERENCES "crm"."accounts"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_72a3d59f882b02632e04" ON "crm"."activities" ("account_id");

ALTER TABLE "crm"."activities" ADD CONSTRAINT "c_df18fef52812117b5925" FOREIGN KEY ("person_id") REFERENCES "core"."persons"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_44df3a24c9e9aac39702" ON "crm"."activities" ("person_id");

ALTER TABLE "crm"."activities" ADD CONSTRAINT "c_d6507e4cb30ab36dfe2b" FOREIGN KEY ("opportunity_id") REFERENCES "crm"."opportunities"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_eb5f230e8d7f088d8163" ON "crm"."activities" ("opportunity_id");

ALTER TABLE "crm"."activities" ADD CONSTRAINT "c_64f3b90db6c5b55a099a" FOREIGN KEY ("owner_id") REFERENCES "iam"."principals"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_aab53247541abf25cdfa" ON "crm"."activities" ("owner_id");

ALTER TABLE "crm"."notes" ADD CONSTRAINT "c_a5d5dd45a6b67f7f215b" FOREIGN KEY ("account_id") REFERENCES "crm"."accounts"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_996b55bbac48ee06a836" ON "crm"."notes" ("account_id");

ALTER TABLE "crm"."notes" ADD CONSTRAINT "c_24804e18d9e3ba6376ad" FOREIGN KEY ("author_id") REFERENCES "iam"."principals"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_29c5e5e8060c92c9fe26" ON "crm"."notes" ("author_id");

ALTER TABLE "crm"."campaign_recipients" ADD CONSTRAINT "c_c238f97afe590f598a0e" FOREIGN KEY ("campaign_id") REFERENCES "crm"."campaigns"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_dd983a363fbda0d75fdb" ON "crm"."campaign_recipients" ("campaign_id");

ALTER TABLE "crm"."campaign_recipients" ADD CONSTRAINT "c_085839a60401631fbdf8" FOREIGN KEY ("person_id") REFERENCES "core"."persons"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_72e55d3f71f57c6b746e" ON "crm"."campaign_recipients" ("person_id");

ALTER TABLE "web"."pages" ADD CONSTRAINT "c_b6acec3b060b4ea28a22" FOREIGN KEY ("published_revision_id") REFERENCES "web"."page_revisions"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_ac914c0690976fe9945b" ON "web"."pages" ("published_revision_id");

ALTER TABLE "web"."page_revisions" ADD CONSTRAINT "c_ea527267349e22598b89" FOREIGN KEY ("page_id") REFERENCES "web"."pages"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_6c74107bac5aba8d5c50" ON "web"."page_revisions" ("page_id");

ALTER TABLE "web"."page_revisions" ADD CONSTRAINT "c_a57cecdd9174b7acadf6" FOREIGN KEY ("author_id") REFERENCES "iam"."principals"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_1e03a9211ae8c9832fd7" ON "web"."page_revisions" ("author_id");

ALTER TABLE "web"."offers" ADD CONSTRAINT "c_c4e72eeda95e2c242bfa" FOREIGN KEY ("product_id") REFERENCES "commercial"."products"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_1c8b7b4a9467f67c6f16" ON "web"."offers" ("product_id");

ALTER TABLE "web"."portfolio_entries" ADD CONSTRAINT "c_a5a88df1bc3eb534e6a6" FOREIGN KEY ("project_id") REFERENCES "project"."projects"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_b808d9014faaa5239eb9" ON "web"."portfolio_entries" ("project_id");

ALTER TABLE "web"."request_links" ADD CONSTRAINT "c_ec27490c1e3662626375" FOREIGN KEY ("request_id") REFERENCES "web"."contact_requests"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_a5452bd946adbbffc932" ON "web"."request_links" ("request_id");

ALTER TABLE "web"."request_links" ADD CONSTRAINT "c_d0a984dbd5470274224e" FOREIGN KEY ("person_id") REFERENCES "core"."persons"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_52a908ed0a2ab98a76e7" ON "web"."request_links" ("person_id");

ALTER TABLE "web"."request_links" ADD CONSTRAINT "c_0ff5a50f3a77dbc7b044" FOREIGN KEY ("organization_id") REFERENCES "core"."organizations"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_66a3911cacd086740bf3" ON "web"."request_links" ("organization_id");

ALTER TABLE "web"."request_links" ADD CONSTRAINT "c_e33545a384df051d58ff" FOREIGN KEY ("lead_id") REFERENCES "crm"."leads"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_24e11ad4dddf742c6abf" ON "web"."request_links" ("lead_id");

ALTER TABLE "web"."request_links" ADD CONSTRAINT "c_5b1ed718720efc54e472" FOREIGN KEY ("ticket_id") REFERENCES "itsm"."tickets"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_91b05b6aa02bef862d15" ON "web"."request_links" ("ticket_id");

ALTER TABLE "web"."request_files" ADD CONSTRAINT "c_e4717a40f0b5bdf71a4f" FOREIGN KEY ("request_id") REFERENCES "web"."contact_requests"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_e410b74a19a648dca52a" ON "web"."request_files" ("request_id");

ALTER TABLE "web"."request_files" ADD CONSTRAINT "c_dd9e343e9a6006778c06" FOREIGN KEY ("file_id") REFERENCES "docs"."files"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_094f68c6bad770b239fe" ON "web"."request_files" ("file_id");

ALTER TABLE "web"."publication_media" ADD CONSTRAINT "c_7c8353e1f29af743ad0f" FOREIGN KEY ("file_id") REFERENCES "docs"."files"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_580e3eeb8d62c47b3366" ON "web"."publication_media" ("file_id");

ALTER TABLE "web"."publication_media" ADD CONSTRAINT "c_7da10ad8d852182cb946" FOREIGN KEY ("page_revision_id") REFERENCES "web"."page_revisions"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_1466f8995b5899c5d2f7" ON "web"."publication_media" ("page_revision_id");

ALTER TABLE "web"."publication_media" ADD CONSTRAINT "c_e81c0e6d40d74a53090e" FOREIGN KEY ("portfolio_id") REFERENCES "web"."portfolio_entries"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_3f38c48f248703fe6968" ON "web"."publication_media" ("portfolio_id");

ALTER TABLE "web"."publication_media" ADD CONSTRAINT "c_0e8de27563c318c73e96" FOREIGN KEY ("publication_authorized_by") REFERENCES "iam"."principals"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_abfc8a16db359f1be8c8" ON "web"."publication_media" ("publication_authorized_by");

ALTER TABLE "web"."communication_preferences" ADD CONSTRAINT "c_3eb4b46ff5d0c41014a0" FOREIGN KEY ("person_id") REFERENCES "core"."persons"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_98bc524eb942d8839fae" ON "web"."communication_preferences" ("person_id");

ALTER TABLE "project"."projects" ADD CONSTRAINT "c_4a7638ec7830830785d0" FOREIGN KEY ("owner_organization_id") REFERENCES "core"."organizations"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_c117e3c69506aa97fd84" ON "project"."projects" ("owner_organization_id");

ALTER TABLE "project"."projects" ADD CONSTRAINT "c_20398924ab60df11380c" FOREIGN KEY ("customer_organization_id") REFERENCES "core"."organizations"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_989bbd9679cf2423217b" ON "project"."projects" ("customer_organization_id");

ALTER TABLE "project"."projects" ADD CONSTRAINT "c_203192d3d3f1b0de4652" FOREIGN KEY ("manager_id") REFERENCES "iam"."principals"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_f9603ab1385253f59790" ON "project"."projects" ("manager_id");

ALTER TABLE "project"."projects" ADD CONSTRAINT "c_cead1e5c2b7ecdd0afa2" FOREIGN KEY ("opportunity_id") REFERENCES "crm"."opportunities"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_48f8c3ec4c8ab650773d" ON "project"."projects" ("opportunity_id");

ALTER TABLE "project"."project_parties" ADD CONSTRAINT "c_1a276b1dad8ebfc99a6c" FOREIGN KEY ("project_id") REFERENCES "project"."projects"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_131dc059a8c9baa1c24f" ON "project"."project_parties" ("project_id");

ALTER TABLE "project"."project_parties" ADD CONSTRAINT "c_3b8eb622696a0dbd3252" FOREIGN KEY ("organization_id") REFERENCES "core"."organizations"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_605ecf7b3e186cc26720" ON "project"."project_parties" ("organization_id");

ALTER TABLE "project"."project_parties" ADD CONSTRAINT "c_fb267f1eef9f296f10e0" FOREIGN KEY ("site_id") REFERENCES "core"."sites"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_ac7032c31cd44fb344c3" ON "project"."project_parties" ("site_id");

ALTER TABLE "project"."memberships" ADD CONSTRAINT "c_d905d99dc34f1e1567b3" FOREIGN KEY ("project_id") REFERENCES "project"."projects"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_d6fe351d9b23ec347a5a" ON "project"."memberships" ("project_id");

ALTER TABLE "project"."memberships" ADD CONSTRAINT "c_22f37528248a8789e51c" FOREIGN KEY ("person_id") REFERENCES "core"."persons"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_e1ad4c96fbb827ce30bc" ON "project"."memberships" ("person_id");

ALTER TABLE "project"."phases" ADD CONSTRAINT "c_73457a7b9b7000ee0b70" FOREIGN KEY ("project_id") REFERENCES "project"."projects"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_c6cc60182b46b939c048" ON "project"."phases" ("project_id");

ALTER TABLE "project"."milestones" ADD CONSTRAINT "c_c064365fdc4dea4942d3" FOREIGN KEY ("project_id") REFERENCES "project"."projects"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_eede76a9589b0e98bbce" ON "project"."milestones" ("project_id");

ALTER TABLE "project"."milestones" ADD CONSTRAINT "c_b19cdb1a19c1dcfce7c2" FOREIGN KEY ("phase_id") REFERENCES "project"."phases"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_b75d7c88fe44517ca734" ON "project"."milestones" ("phase_id");

ALTER TABLE "project"."tasks" ADD CONSTRAINT "c_0b50c5cf59010bc9b425" FOREIGN KEY ("project_id") REFERENCES "project"."projects"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_98683555de4befe18d6b" ON "project"."tasks" ("project_id");

ALTER TABLE "project"."tasks" ADD CONSTRAINT "c_a9cd7394c5da8e1fdd74" FOREIGN KEY ("phase_id") REFERENCES "project"."phases"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_260e019f08d70a121490" ON "project"."tasks" ("phase_id");

ALTER TABLE "project"."tasks" ADD CONSTRAINT "c_6450841bcfc16bec8ad2" FOREIGN KEY ("parent_id") REFERENCES "project"."tasks"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_c662a71cf9e7f8bffd6b" ON "project"."tasks" ("parent_id");

ALTER TABLE "project"."task_assignees" ADD CONSTRAINT "c_b00035f73bcfbc09f97c" FOREIGN KEY ("task_id") REFERENCES "project"."tasks"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_fc9257b42a1947c27167" ON "project"."task_assignees" ("task_id");

ALTER TABLE "project"."task_assignees" ADD CONSTRAINT "c_30b3b587980efa6f227a" FOREIGN KEY ("person_id") REFERENCES "core"."persons"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_21b298dbe98ca770796e" ON "project"."task_assignees" ("person_id");

ALTER TABLE "project"."task_dependencies" ADD CONSTRAINT "c_032d5a48b282f61545cf" FOREIGN KEY ("predecessor_id") REFERENCES "project"."tasks"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_aa108acab18ec91acc68" ON "project"."task_dependencies" ("predecessor_id");

ALTER TABLE "project"."task_dependencies" ADD CONSTRAINT "c_a1703bbb60760b8e81dd" FOREIGN KEY ("successor_id") REFERENCES "project"."tasks"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_370667425a82400b7b6d" ON "project"."task_dependencies" ("successor_id");

ALTER TABLE "project"."resource_demands" ADD CONSTRAINT "c_adac707c3c285bd6b804" FOREIGN KEY ("project_id") REFERENCES "project"."projects"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_309c30f6a3c5fd64d4c5" ON "project"."resource_demands" ("project_id");

ALTER TABLE "project"."resource_demands" ADD CONSTRAINT "c_10d2621b0e03757fb09e" FOREIGN KEY ("task_id") REFERENCES "project"."tasks"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_4d01fa4a95f6421cc394" ON "project"."resource_demands" ("task_id");

ALTER TABLE "project"."resource_demands" ADD CONSTRAINT "c_c5614cb10457c499e179" FOREIGN KEY ("person_id") REFERENCES "core"."persons"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_5274e2fe04e205d1c08f" ON "project"."resource_demands" ("person_id");

ALTER TABLE "project"."resource_demands" ADD CONSTRAINT "c_18112f16212dcdab0349" FOREIGN KEY ("skill_id") REFERENCES "people"."skills"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_6abf2c6e9b5679c06fa8" ON "project"."resource_demands" ("skill_id");

ALTER TABLE "project"."baselines" ADD CONSTRAINT "c_2a24c0c9d7d0d39311d0" FOREIGN KEY ("project_id") REFERENCES "project"."projects"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_f8e7800503573430831f" ON "project"."baselines" ("project_id");

ALTER TABLE "project"."baselines" ADD CONSTRAINT "c_84f09dad46eb3be576ca" FOREIGN KEY ("approved_by") REFERENCES "iam"."principals"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_5981576971ea03b68a5e" ON "project"."baselines" ("approved_by");

ALTER TABLE "project"."risks" ADD CONSTRAINT "c_9335bd17116399cc38ac" FOREIGN KEY ("project_id") REFERENCES "project"."projects"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_fb347526a2e061a651dd" ON "project"."risks" ("project_id");

ALTER TABLE "project"."risks" ADD CONSTRAINT "c_3901e2528eaea57f78f8" FOREIGN KEY ("owner_id") REFERENCES "iam"."principals"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_f1591a2af5b58e48c293" ON "project"."risks" ("owner_id");

ALTER TABLE "project"."decisions" ADD CONSTRAINT "c_0625d01c9d17280e00b6" FOREIGN KEY ("project_id") REFERENCES "project"."projects"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_f27fc4d9f68aa836f797" ON "project"."decisions" ("project_id");

ALTER TABLE "project"."decisions" ADD CONSTRAINT "c_e2e62edcba6e1ceb7932" FOREIGN KEY ("decided_by") REFERENCES "iam"."principals"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_5d3651f821e3813e3e5c" ON "project"."decisions" ("decided_by");

ALTER TABLE "project"."deliverables" ADD CONSTRAINT "c_84c12deed02c41507e4e" FOREIGN KEY ("project_id") REFERENCES "project"."projects"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_fee1127dccf0542a3a43" ON "project"."deliverables" ("project_id");

ALTER TABLE "project"."deliverables" ADD CONSTRAINT "c_bb00df14b01e8beafd20" FOREIGN KEY ("milestone_id") REFERENCES "project"."milestones"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_b6f9b8f0dc3e4314a052" ON "project"."deliverables" ("milestone_id");

ALTER TABLE "project"."deliverables" ADD CONSTRAINT "c_803f390e82c3dfd4a0f8" FOREIGN KEY ("file_id") REFERENCES "docs"."files"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_d5c7b94268996b7c293e" ON "project"."deliverables" ("file_id");

ALTER TABLE "project"."acceptances" ADD CONSTRAINT "c_8289f1096e6e3e46b1a7" FOREIGN KEY ("deliverable_id") REFERENCES "project"."deliverables"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_3e661c52103f648349ef" ON "project"."acceptances" ("deliverable_id");

ALTER TABLE "project"."acceptances" ADD CONSTRAINT "c_137e97e0a5948f18a990" FOREIGN KEY ("reviewer_affiliation_id") REFERENCES "core"."affiliations"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_d4d231cab4293cca926b" ON "project"."acceptances" ("reviewer_affiliation_id");

ALTER TABLE "project"."budget_lines" ADD CONSTRAINT "c_ebbd795899890c5df7c2" FOREIGN KEY ("project_id") REFERENCES "project"."projects"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_3ad7afaaecd7af9ec0e6" ON "project"."budget_lines" ("project_id");

ALTER TABLE "people"."employment_records" ADD CONSTRAINT "c_4fcf908fa2094c3bb50d" FOREIGN KEY ("person_id") REFERENCES "core"."persons"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_ef17fe5e9ecb41b1c0bc" ON "people"."employment_records" ("person_id");

ALTER TABLE "people"."employment_records" ADD CONSTRAINT "c_c3e19b255b90063d21e7" FOREIGN KEY ("employer_id") REFERENCES "core"."organizations"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_7d534c83fb87f4b2fc2c" ON "people"."employment_records" ("employer_id");

ALTER TABLE "people"."employment_records" ADD CONSTRAINT "c_e9444083d324715a410c" FOREIGN KEY ("manager_id") REFERENCES "core"."persons"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_efeb56c42de8153929a8" ON "people"."employment_records" ("manager_id");

ALTER TABLE "people"."working_patterns" ADD CONSTRAINT "c_1ef52f1dd5e4ff08498b" FOREIGN KEY ("calendar_id") REFERENCES "schedule"."business_calendars"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_582be295953e374bc9b9" ON "people"."working_patterns" ("calendar_id");

ALTER TABLE "people"."working_pattern_slots" ADD CONSTRAINT "c_3ac7ec6c588010ee412c" FOREIGN KEY ("pattern_id") REFERENCES "people"."working_patterns"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_5de2df26e011426a9732" ON "people"."working_pattern_slots" ("pattern_id");

ALTER TABLE "people"."employment_patterns" ADD CONSTRAINT "c_5abe403240d356a524cd" FOREIGN KEY ("employment_id") REFERENCES "people"."employment_records"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_d986ca0c6accbabddb6e" ON "people"."employment_patterns" ("employment_id");

ALTER TABLE "people"."employment_patterns" ADD CONSTRAINT "c_92b75ed9421542de1eb4" FOREIGN KEY ("pattern_id") REFERENCES "people"."working_patterns"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_0d2ef14b424a7e85f297" ON "people"."employment_patterns" ("pattern_id");

ALTER TABLE "people"."leave_requests" ADD CONSTRAINT "c_fa44016f233f1b370b52" FOREIGN KEY ("employment_id") REFERENCES "people"."employment_records"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_af8ad6ffd5fbb1d9bf0a" ON "people"."leave_requests" ("employment_id");

ALTER TABLE "people"."leave_requests" ADD CONSTRAINT "c_057d3ebd626f866ec426" FOREIGN KEY ("leave_type_id") REFERENCES "people"."leave_types"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_b8660289977af9189e51" ON "people"."leave_requests" ("leave_type_id");

ALTER TABLE "people"."leave_requests" ADD CONSTRAINT "c_c8984c13624b667a3e63" FOREIGN KEY ("reviewer_id") REFERENCES "iam"."principals"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_e38a83e9fc419e3ce9a4" ON "people"."leave_requests" ("reviewer_id");

ALTER TABLE "people"."leave_ledger" ADD CONSTRAINT "c_3a11360e304706cd2d47" FOREIGN KEY ("employment_id") REFERENCES "people"."employment_records"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_79be62be8341bd59f5e8" ON "people"."leave_ledger" ("employment_id");

ALTER TABLE "people"."leave_ledger" ADD CONSTRAINT "c_211e7d9ae09a2f6fe4b3" FOREIGN KEY ("leave_type_id") REFERENCES "people"."leave_types"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_b746af25932ae0744f9d" ON "people"."leave_ledger" ("leave_type_id");

ALTER TABLE "people"."leave_ledger" ADD CONSTRAINT "c_7f6fd1048244b9225eac" FOREIGN KEY ("request_id") REFERENCES "people"."leave_requests"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_6638226cc6bba37576da" ON "people"."leave_ledger" ("request_id");

ALTER TABLE "people"."leave_ledger" ADD CONSTRAINT "c_8129de82d2160056df99" FOREIGN KEY ("reversal_of_id") REFERENCES "people"."leave_ledger"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_7da5fb6fd7d3d02604e9" ON "people"."leave_ledger" ("reversal_of_id");

ALTER TABLE "people"."attendance_events" ADD CONSTRAINT "c_474b927e5fa71cc20e1c" FOREIGN KEY ("employment_id") REFERENCES "people"."employment_records"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_f6097046c9bfa3c2627b" ON "people"."attendance_events" ("employment_id");

ALTER TABLE "people"."attendance_events" ADD CONSTRAINT "c_c299afa59c644a886c54" FOREIGN KEY ("correction_of_id") REFERENCES "people"."attendance_events"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_8860bb7fb7185ad276db" ON "people"."attendance_events" ("correction_of_id");

ALTER TABLE "people"."work_locations" ADD CONSTRAINT "c_01bc8427c51f2f1ea074" FOREIGN KEY ("employment_id") REFERENCES "people"."employment_records"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_ac525f90f536ea63f195" ON "people"."work_locations" ("employment_id");

ALTER TABLE "people"."work_locations" ADD CONSTRAINT "c_aaf0a9c796ba345d1c02" FOREIGN KEY ("site_id") REFERENCES "core"."sites"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_7abd34092b9c5dfa3ccd" ON "people"."work_locations" ("site_id");

ALTER TABLE "people"."person_skills" ADD CONSTRAINT "c_13c80a887ec8ab4374ee" FOREIGN KEY ("person_id") REFERENCES "core"."persons"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_686ce2ac17612f9ad122" ON "people"."person_skills" ("person_id");

ALTER TABLE "people"."person_skills" ADD CONSTRAINT "c_797074ef168f3322cdec" FOREIGN KEY ("skill_id") REFERENCES "people"."skills"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_4c7a7b3d1467cac9eca5" ON "people"."person_skills" ("skill_id");

ALTER TABLE "people"."person_skills" ADD CONSTRAINT "c_b7e1e619b319412f4604" FOREIGN KEY ("verified_by") REFERENCES "iam"."principals"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_0fedd19db8b7c5590190" ON "people"."person_skills" ("verified_by");

ALTER TABLE "people"."certifications" ADD CONSTRAINT "c_0ae3a174896689f84f37" FOREIGN KEY ("person_id") REFERENCES "core"."persons"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_989a5417f11b668b4ab5" ON "people"."certifications" ("person_id");

ALTER TABLE "people"."certifications" ADD CONSTRAINT "c_f66789deba6b19c5b0c0" FOREIGN KEY ("document_id") REFERENCES "docs"."files"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_7ff16f26f457bb203123" ON "people"."certifications" ("document_id");

ALTER TABLE "schedule"."calendar_slots" ADD CONSTRAINT "c_1bb86b793142277c34dd" FOREIGN KEY ("calendar_id") REFERENCES "schedule"."business_calendars"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_4a0723063a95f2b9f718" ON "schedule"."calendar_slots" ("calendar_id");

ALTER TABLE "schedule"."calendar_exceptions" ADD CONSTRAINT "c_a0562484b47dffebf2d5" FOREIGN KEY ("calendar_id") REFERENCES "schedule"."business_calendars"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_94fa40e25215e3007aa3" ON "schedule"."calendar_exceptions" ("calendar_id");

ALTER TABLE "schedule"."resources" ADD CONSTRAINT "c_d683339555939d72d20d" FOREIGN KEY ("person_id") REFERENCES "core"."persons"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_0331d5879db827733ca4" ON "schedule"."resources" ("person_id");

ALTER TABLE "schedule"."resources" ADD CONSTRAINT "c_14d65e0eecfa23267b56" FOREIGN KEY ("asset_id") REFERENCES "cmdb"."items"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_8ac8e1c75e76fd4e9573" ON "schedule"."resources" ("asset_id");

ALTER TABLE "schedule"."availability_blocks" ADD CONSTRAINT "c_498310c049803210a0db" FOREIGN KEY ("resource_id") REFERENCES "schedule"."resources"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_b5b0c27f4b54fb0d2d1f" ON "schedule"."availability_blocks" ("resource_id");

ALTER TABLE "schedule"."bookings" ADD CONSTRAINT "c_9ed07fe224cf8b3bd2f2" FOREIGN KEY ("resource_id") REFERENCES "schedule"."resources"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_769775e3fa591b602197" ON "schedule"."bookings" ("resource_id");

ALTER TABLE "schedule"."bookings" ADD CONSTRAINT "c_ebe2cd1bfd79f591b0bf" FOREIGN KEY ("site_id") REFERENCES "core"."sites"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_d729c547446184d66e24" ON "schedule"."bookings" ("site_id");

ALTER TABLE "schedule"."bookings" ADD CONSTRAINT "c_010f9ea3ba1d4a8cf754" FOREIGN KEY ("project_task_id") REFERENCES "project"."tasks"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_da9ca40c3fc9bc37de0b" ON "schedule"."bookings" ("project_task_id");

ALTER TABLE "schedule"."bookings" ADD CONSTRAINT "c_897925bf2cc22e6ae6df" FOREIGN KEY ("intervention_id") REFERENCES "itsm"."interventions"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_1253b582c6bf6f642f9c" ON "schedule"."bookings" ("intervention_id");

ALTER TABLE "schedule"."bookings" ADD CONSTRAINT "c_86a7e4d23f4be9a52fc5" FOREIGN KEY ("crm_activity_id") REFERENCES "crm"."activities"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_31eccd81d4b532bd1f89" ON "schedule"."bookings" ("crm_activity_id");

ALTER TABLE "schedule"."booking_events" ADD CONSTRAINT "c_2208e898d65d04946cb7" FOREIGN KEY ("booking_id") REFERENCES "schedule"."bookings"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_f1ff63c5ed81f5823e3d" ON "schedule"."booking_events" ("booking_id");

ALTER TABLE "schedule"."booking_events" ADD CONSTRAINT "c_886a512075e1af4f876f" FOREIGN KEY ("actor_id") REFERENCES "iam"."principals"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_4125243a22bf65ff0033" ON "schedule"."booking_events" ("actor_id");

ALTER TABLE "schedule"."recurrence_rules" ADD CONSTRAINT "c_10d7021b989f978a892d" FOREIGN KEY ("resource_id") REFERENCES "schedule"."resources"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_bf20d702a5bc5f599490" ON "schedule"."recurrence_rules" ("resource_id");

ALTER TABLE "schedule"."calendar_connections" ADD CONSTRAINT "c_21cf86b86900f88a1f4c" FOREIGN KEY ("integration_id") REFERENCES "integration"."connections"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_7a4c178b15b9d56f71bd" ON "schedule"."calendar_connections" ("integration_id");

ALTER TABLE "schedule"."calendar_connections" ADD CONSTRAINT "c_5e6e3615f9e98b100081" FOREIGN KEY ("resource_id") REFERENCES "schedule"."resources"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_fe555c7ea846c8829ebb" ON "schedule"."calendar_connections" ("resource_id");

ALTER TABLE "itsm"."categories" ADD CONSTRAINT "c_78172b13c631f9bd9433" FOREIGN KEY ("parent_id") REFERENCES "itsm"."categories"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_0b299888bf189bc7ad64" ON "itsm"."categories" ("parent_id");

ALTER TABLE "itsm"."transition_rules" ADD CONSTRAINT "c_19257b7fcb9e191a66b4" FOREIGN KEY ("ticket_type_id") REFERENCES "itsm"."ticket_types"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_eba726d5803ff742c573" ON "itsm"."transition_rules" ("ticket_type_id");

ALTER TABLE "itsm"."transition_rules" ADD CONSTRAINT "c_0bf16f2ee6fd0afa3b12" FOREIGN KEY ("from_status_id") REFERENCES "itsm"."statuses"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_5f9487e07ff62053bbaf" ON "itsm"."transition_rules" ("from_status_id");

ALTER TABLE "itsm"."transition_rules" ADD CONSTRAINT "c_ee9ac5d91b1effe34a31" FOREIGN KEY ("to_status_id") REFERENCES "itsm"."statuses"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_1a1293ca308363037ba0" ON "itsm"."transition_rules" ("to_status_id");

ALTER TABLE "itsm"."transition_rules" ADD CONSTRAINT "c_3bdca54b074b85a286cf" FOREIGN KEY ("required_permission_id") REFERENCES "iam"."permissions"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_83055d3a73dbf15da5ee" ON "itsm"."transition_rules" ("required_permission_id");

ALTER TABLE "itsm"."tickets" ADD CONSTRAINT "c_496e3119777f8485a7df" FOREIGN KEY ("type_id") REFERENCES "itsm"."ticket_types"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_4c8c8651248cb3bf9393" ON "itsm"."tickets" ("type_id");

ALTER TABLE "itsm"."tickets" ADD CONSTRAINT "c_752375c581c3b0c25a5c" FOREIGN KEY ("category_id") REFERENCES "itsm"."categories"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_f01e3573948a8f762d73" ON "itsm"."tickets" ("category_id");

ALTER TABLE "itsm"."tickets" ADD CONSTRAINT "c_b843d27d08290033ecdd" FOREIGN KEY ("status_id") REFERENCES "itsm"."statuses"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_4bd1a128817378feef9f" ON "itsm"."tickets" ("status_id");

ALTER TABLE "itsm"."tickets" ADD CONSTRAINT "c_ac6bd829dd42289f0a2c" FOREIGN KEY ("customer_org_id") REFERENCES "core"."organizations"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_1b29932fc9ab6e8cf7fd" ON "itsm"."tickets" ("customer_org_id");

ALTER TABLE "itsm"."tickets" ADD CONSTRAINT "c_d233356861d5de4015dc" FOREIGN KEY ("site_id") REFERENCES "core"."sites"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_e7735967ed34f6cb9158" ON "itsm"."tickets" ("site_id");

ALTER TABLE "itsm"."tickets" ADD CONSTRAINT "c_64e11b3e2bf6547bc67c" FOREIGN KEY ("requester_affiliation_id") REFERENCES "core"."affiliations"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_a079c739834b922957a5" ON "itsm"."tickets" ("requester_affiliation_id");

ALTER TABLE "itsm"."tickets" ADD CONSTRAINT "c_0f9fc64398121de61708" FOREIGN KEY ("beneficiary_affiliation_id") REFERENCES "core"."affiliations"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_51ddabd41e42ebba4321" ON "itsm"."tickets" ("beneficiary_affiliation_id");

ALTER TABLE "itsm"."tickets" ADD CONSTRAINT "c_088e53a8a3c6a7d4a6b0" FOREIGN KEY ("created_by_id") REFERENCES "iam"."principals"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_4b239bf6b77e9153d0c0" ON "itsm"."tickets" ("created_by_id");

ALTER TABLE "itsm"."tickets" ADD CONSTRAINT "c_3b33e16d369336600cee" FOREIGN KEY ("assigned_team_id") REFERENCES "core"."teams"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_3534ad38cb30072f4ab0" ON "itsm"."tickets" ("assigned_team_id");

ALTER TABLE "itsm"."tickets" ADD CONSTRAINT "c_51f596b3b2248a3c7ef2" FOREIGN KEY ("assigned_to_id") REFERENCES "iam"."principals"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_5bda655617831c62399c" ON "itsm"."tickets" ("assigned_to_id");

ALTER TABLE "itsm"."tickets" ADD CONSTRAINT "c_4c55e95a9635fb0dc5e0" FOREIGN KEY ("parent_id") REFERENCES "itsm"."tickets"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_bd4992188a8f6d55be3f" ON "itsm"."tickets" ("parent_id");

ALTER TABLE "itsm"."tickets" ADD CONSTRAINT "c_b3478b62460d41df538e" FOREIGN KEY ("service_id") REFERENCES "service"."catalog_items"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_27d4dabad34ff570a193" ON "itsm"."tickets" ("service_id");

ALTER TABLE "itsm"."tickets" ADD CONSTRAINT "c_6a9b9f0079b31d00495a" FOREIGN KEY ("contract_id") REFERENCES "commercial"."contracts"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_00b76a40afb2568bdc7d" ON "itsm"."tickets" ("contract_id");

ALTER TABLE "itsm"."ticket_participants" ADD CONSTRAINT "c_16a9862951560dc56cca" FOREIGN KEY ("ticket_id") REFERENCES "itsm"."tickets"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_fe73844d0aded0184121" ON "itsm"."ticket_participants" ("ticket_id");

ALTER TABLE "itsm"."ticket_participants" ADD CONSTRAINT "c_6e7a6e758a6eb07beb08" FOREIGN KEY ("person_id") REFERENCES "core"."persons"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_63a1c37587a36cfdadc7" ON "itsm"."ticket_participants" ("person_id");

ALTER TABLE "itsm"."ticket_messages" ADD CONSTRAINT "c_316bd8313ad85b7c0c5d" FOREIGN KEY ("ticket_id") REFERENCES "itsm"."tickets"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_a96f9c826a7b9190ec0b" ON "itsm"."ticket_messages" ("ticket_id");

ALTER TABLE "itsm"."ticket_messages" ADD CONSTRAINT "c_995eca716022dc887a5f" FOREIGN KEY ("author_id") REFERENCES "iam"."principals"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_2def79721f4c1beaa053" ON "itsm"."ticket_messages" ("author_id");

ALTER TABLE "itsm"."message_revisions" ADD CONSTRAINT "c_7d6298b5c6d6b63bfbb9" FOREIGN KEY ("message_id") REFERENCES "itsm"."ticket_messages"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_22edd938edb4f10e4bd6" ON "itsm"."message_revisions" ("message_id");

ALTER TABLE "itsm"."message_revisions" ADD CONSTRAINT "c_7fcafbe0438261907852" FOREIGN KEY ("edited_by") REFERENCES "iam"."principals"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_0d5159cd2e12fb34bb54" ON "itsm"."message_revisions" ("edited_by");

ALTER TABLE "itsm"."ticket_events" ADD CONSTRAINT "c_8439ad7e9cea1ee903dd" FOREIGN KEY ("ticket_id") REFERENCES "itsm"."tickets"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_c4b6f7ca64beb0440382" ON "itsm"."ticket_events" ("ticket_id");

ALTER TABLE "itsm"."ticket_events" ADD CONSTRAINT "c_144523c0dadb6c8f1786" FOREIGN KEY ("actor_id") REFERENCES "iam"."principals"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_3f3cd116264bfbe0ccac" ON "itsm"."ticket_events" ("actor_id");

ALTER TABLE "itsm"."ticket_events" ADD CONSTRAINT "c_0fdb2af677a6acd181c5" FOREIGN KEY ("from_status_id") REFERENCES "itsm"."statuses"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_0f4e326124d229904c00" ON "itsm"."ticket_events" ("from_status_id");

ALTER TABLE "itsm"."ticket_events" ADD CONSTRAINT "c_7ebfe76bc211b5fd8a46" FOREIGN KEY ("to_status_id") REFERENCES "itsm"."statuses"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_b83fda97e56d654587f1" ON "itsm"."ticket_events" ("to_status_id");

ALTER TABLE "itsm"."assignment_history" ADD CONSTRAINT "c_5d3eb88db2d4cbab104b" FOREIGN KEY ("ticket_id") REFERENCES "itsm"."tickets"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_cc5a9c231012f9b41c0f" ON "itsm"."assignment_history" ("ticket_id");

ALTER TABLE "itsm"."assignment_history" ADD CONSTRAINT "c_493f4ffec957da81f11f" FOREIGN KEY ("team_id") REFERENCES "core"."teams"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_18796b7797e1805ed8b9" ON "itsm"."assignment_history" ("team_id");

ALTER TABLE "itsm"."assignment_history" ADD CONSTRAINT "c_549a44c15c3b70b88c2c" FOREIGN KEY ("assignee_id") REFERENCES "iam"."principals"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_6f85c6a471e711537599" ON "itsm"."assignment_history" ("assignee_id");

ALTER TABLE "itsm"."waiting_periods" ADD CONSTRAINT "c_2a2c1ab2cedda1b94751" FOREIGN KEY ("ticket_id") REFERENCES "itsm"."tickets"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_655632779702940bec52" ON "itsm"."waiting_periods" ("ticket_id");

ALTER TABLE "itsm"."waiting_periods" ADD CONSTRAINT "c_968d2ec85d8da8f357cd" FOREIGN KEY ("reason_id") REFERENCES "itsm"."wait_reasons"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_14a37e104095fae94811" ON "itsm"."waiting_periods" ("reason_id");

ALTER TABLE "itsm"."waiting_periods" ADD CONSTRAINT "c_8289b1413c060a673a67" FOREIGN KEY ("question_message_id") REFERENCES "itsm"."ticket_messages"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_57acfb6da02d3033232e" ON "itsm"."waiting_periods" ("question_message_id");

ALTER TABLE "itsm"."waiting_periods" ADD CONSTRAINT "c_a92073669f064cf88e5a" FOREIGN KEY ("calendar_id") REFERENCES "schedule"."business_calendars"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_16ff61d5b48706969a66" ON "itsm"."waiting_periods" ("calendar_id");

ALTER TABLE "itsm"."resolutions" ADD CONSTRAINT "c_137ab777ebea819af321" FOREIGN KEY ("ticket_id") REFERENCES "itsm"."tickets"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_8a41467a80bf78f81816" ON "itsm"."resolutions" ("ticket_id");

ALTER TABLE "itsm"."resolutions" ADD CONSTRAINT "c_0742fb5905a79a81a10e" FOREIGN KEY ("proposed_by") REFERENCES "iam"."principals"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_4a6f0441ceb0535cff7a" ON "itsm"."resolutions" ("proposed_by");

ALTER TABLE "itsm"."resolutions" ADD CONSTRAINT "c_5abf67274c5f5132b89a" FOREIGN KEY ("calendar_id") REFERENCES "schedule"."business_calendars"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_7686d91797429fae8616" ON "itsm"."resolutions" ("calendar_id");

ALTER TABLE "itsm"."resolution_responses" ADD CONSTRAINT "c_c8e99c1d2e7cd2fa5f68" FOREIGN KEY ("resolution_id") REFERENCES "itsm"."resolutions"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_63e2ef74c0d8439c6594" ON "itsm"."resolution_responses" ("resolution_id");

ALTER TABLE "itsm"."resolution_responses" ADD CONSTRAINT "c_9a9a0606c12527a194d5" FOREIGN KEY ("responder_id") REFERENCES "iam"."principals"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_f6d471dbc88546415755" ON "itsm"."resolution_responses" ("responder_id");

ALTER TABLE "itsm"."ticket_assets" ADD CONSTRAINT "c_e73490e94ec00cef5d9a" FOREIGN KEY ("ticket_id") REFERENCES "itsm"."tickets"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_47c844c37d95b6ac2e1a" ON "itsm"."ticket_assets" ("ticket_id");

ALTER TABLE "itsm"."ticket_assets" ADD CONSTRAINT "c_3f81cd23016608d77456" FOREIGN KEY ("item_id") REFERENCES "cmdb"."items"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_d53b28e6d603bcd851f5" ON "itsm"."ticket_assets" ("item_id");

ALTER TABLE "itsm"."ticket_projects" ADD CONSTRAINT "c_c54d0cb3aeae2f9ca206" FOREIGN KEY ("ticket_id") REFERENCES "itsm"."tickets"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_484b124eddb353dd0e68" ON "itsm"."ticket_projects" ("ticket_id");

ALTER TABLE "itsm"."ticket_projects" ADD CONSTRAINT "c_29f1fbad95e42d303849" FOREIGN KEY ("project_id") REFERENCES "project"."projects"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_00187fa0bd48c0ffc453" ON "itsm"."ticket_projects" ("project_id");

ALTER TABLE "itsm"."ticket_opportunities" ADD CONSTRAINT "c_6498fcdd56db905f1e78" FOREIGN KEY ("ticket_id") REFERENCES "itsm"."tickets"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_4c89497c6e1e954a3dcb" ON "itsm"."ticket_opportunities" ("ticket_id");

ALTER TABLE "itsm"."ticket_opportunities" ADD CONSTRAINT "c_28e1fd1f839ab6cd0f8b" FOREIGN KEY ("opportunity_id") REFERENCES "crm"."opportunities"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_04b9da5a9716cbb0a77d" ON "itsm"."ticket_opportunities" ("opportunity_id");

ALTER TABLE "itsm"."ticket_relations" ADD CONSTRAINT "c_493f72ec081a61790a57" FOREIGN KEY ("source_id") REFERENCES "itsm"."tickets"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_7c18a284da199a04da45" ON "itsm"."ticket_relations" ("source_id");

ALTER TABLE "itsm"."ticket_relations" ADD CONSTRAINT "c_1c03b4a9b472f8e4de5e" FOREIGN KEY ("target_id") REFERENCES "itsm"."tickets"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_8748c10d8b71d1d26bc8" ON "itsm"."ticket_relations" ("target_id");

ALTER TABLE "itsm"."ticket_tags" ADD CONSTRAINT "c_f9260de5882211debfa9" FOREIGN KEY ("ticket_id") REFERENCES "itsm"."tickets"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_0269bd040ded6a53f255" ON "itsm"."ticket_tags" ("ticket_id");

ALTER TABLE "itsm"."ticket_tags" ADD CONSTRAINT "c_18596d4e6c1bf0dd1a59" FOREIGN KEY ("tag_id") REFERENCES "core"."tags"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_c9c8a2da54fcf7d68c4e" ON "itsm"."ticket_tags" ("tag_id");

ALTER TABLE "itsm"."problem_details" ADD CONSTRAINT "c_0133dff90ed361aff43e" FOREIGN KEY ("ticket_id") REFERENCES "itsm"."tickets"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_7b2e2c87fff872670e16" ON "itsm"."problem_details" ("ticket_id");

ALTER TABLE "itsm"."change_details" ADD CONSTRAINT "c_cfddc147107f7c3a77a4" FOREIGN KEY ("ticket_id") REFERENCES "itsm"."tickets"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_57403a398b5ba714125b" ON "itsm"."change_details" ("ticket_id");

ALTER TABLE "itsm"."interventions" ADD CONSTRAINT "c_b4107e9afa070d5de07b" FOREIGN KEY ("ticket_id") REFERENCES "itsm"."tickets"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_21fc4d4b3e0b41fec0c2" ON "itsm"."interventions" ("ticket_id");

ALTER TABLE "itsm"."interventions" ADD CONSTRAINT "c_64c94ca6f5dc12052e29" FOREIGN KEY ("site_id") REFERENCES "core"."sites"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_4da669a810c197f5c270" ON "itsm"."interventions" ("site_id");

ALTER TABLE "itsm"."intervention_signoffs" ADD CONSTRAINT "c_180851044e10839f54b9" FOREIGN KEY ("intervention_id") REFERENCES "itsm"."interventions"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_630f22ed71cf2f561e3d" ON "itsm"."intervention_signoffs" ("intervention_id");

ALTER TABLE "itsm"."intervention_signoffs" ADD CONSTRAINT "c_03fc1addd740020b9b65" FOREIGN KEY ("signer_affiliation_id") REFERENCES "core"."affiliations"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_b4b1506926efabcf355c" ON "itsm"."intervention_signoffs" ("signer_affiliation_id");

ALTER TABLE "itsm"."intervention_signoffs" ADD CONSTRAINT "c_9ec5da1868fa167f267f" FOREIGN KEY ("document_id") REFERENCES "docs"."files"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_2d4a36dab3f9121eb8bb" ON "itsm"."intervention_signoffs" ("document_id");

ALTER TABLE "itsm"."saved_views" ADD CONSTRAINT "c_a209dea490df0275bad5" FOREIGN KEY ("owner_id") REFERENCES "iam"."principals"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_ed28d2b0053a5053c1ed" ON "itsm"."saved_views" ("owner_id");

ALTER TABLE "itsm"."portal_preferences" ADD CONSTRAINT "c_7d35fc7a86010a543f46" FOREIGN KEY ("principal_id") REFERENCES "iam"."principals"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_5aa196ee0daf8651c47e" ON "itsm"."portal_preferences" ("principal_id");

ALTER TABLE "service"."catalog_items" ADD CONSTRAINT "c_cc2400e945ee3e7b238b" FOREIGN KEY ("request_type_id") REFERENCES "itsm"."ticket_types"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_50f313dbfcb579719e88" ON "service"."catalog_items" ("request_type_id");

ALTER TABLE "service"."catalog_items" ADD CONSTRAINT "c_b0052fd0a46ea527ecb1" FOREIGN KEY ("workflow_id") REFERENCES "workflow"."definitions"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_f0b58a851b03e10936ca" ON "service"."catalog_items" ("workflow_id");

ALTER TABLE "service"."catalog_versions" ADD CONSTRAINT "c_d8e69010c797fe37a696" FOREIGN KEY ("catalog_item_id") REFERENCES "service"."catalog_items"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_eceba3d8fe9c439c7038" ON "service"."catalog_versions" ("catalog_item_id");

ALTER TABLE "service"."request_answers" ADD CONSTRAINT "c_a3c240ef6765a4c39039" FOREIGN KEY ("ticket_id") REFERENCES "itsm"."tickets"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_b44c4530aa78c5a9a3d0" ON "service"."request_answers" ("ticket_id");

ALTER TABLE "service"."request_answers" ADD CONSTRAINT "c_3585e4cb3ec8e5ee30d0" FOREIGN KEY ("catalog_version_id") REFERENCES "service"."catalog_versions"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_a215d14b867b50e2a30e" ON "service"."request_answers" ("catalog_version_id");

ALTER TABLE "service"."sla_policies" ADD CONSTRAINT "c_3bbb10b02b037971c8e5" FOREIGN KEY ("calendar_id") REFERENCES "schedule"."business_calendars"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_6526f5e145f5826e2a00" ON "service"."sla_policies" ("calendar_id");

ALTER TABLE "service"."sla_targets" ADD CONSTRAINT "c_ba2b3ab82d5e137051a9" FOREIGN KEY ("policy_id") REFERENCES "service"."sla_policies"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_78549209ea4336117cb7" ON "service"."sla_targets" ("policy_id");

ALTER TABLE "service"."sla_targets" ADD CONSTRAINT "c_34039d799e903a205aef" FOREIGN KEY ("service_id") REFERENCES "service"."catalog_items"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_fc4461d812ecb340066a" ON "service"."sla_targets" ("service_id");

ALTER TABLE "service"."sla_instances" ADD CONSTRAINT "c_d09d659a1d023245c458" FOREIGN KEY ("ticket_id") REFERENCES "itsm"."tickets"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_04ba79e19feca3d03153" ON "service"."sla_instances" ("ticket_id");

ALTER TABLE "service"."sla_instances" ADD CONSTRAINT "c_f93d4da5f1ef302960a4" FOREIGN KEY ("target_id") REFERENCES "service"."sla_targets"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_e9c478058fb98f0ef5bf" ON "service"."sla_instances" ("target_id");

ALTER TABLE "service"."sla_instances" ADD CONSTRAINT "c_c6c64b9e2d52ae708846" FOREIGN KEY ("calendar_id") REFERENCES "schedule"."business_calendars"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_012400897f77660b2bd2" ON "service"."sla_instances" ("calendar_id");

ALTER TABLE "service"."sla_pauses" ADD CONSTRAINT "c_a6b1f08177ff45038509" FOREIGN KEY ("instance_id") REFERENCES "service"."sla_instances"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_ee12528f96820ee37396" ON "service"."sla_pauses" ("instance_id");

ALTER TABLE "service"."sla_pauses" ADD CONSTRAINT "c_9d4b970a94b2dd6d9475" FOREIGN KEY ("waiting_period_id") REFERENCES "itsm"."waiting_periods"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_20843dccf28893e19478" ON "service"."sla_pauses" ("waiting_period_id");

ALTER TABLE "service"."escalation_rules" ADD CONSTRAINT "c_3f42a64ff90464597498" FOREIGN KEY ("policy_id") REFERENCES "service"."sla_policies"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_8ba231cfc409ccbf162a" ON "service"."escalation_rules" ("policy_id");

ALTER TABLE "service"."escalation_rules" ADD CONSTRAINT "c_52431af2e125dfe895a0" FOREIGN KEY ("target_team_id") REFERENCES "core"."teams"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_3689a65bc76d07270250" ON "service"."escalation_rules" ("target_team_id");

ALTER TABLE "service"."escalation_events" ADD CONSTRAINT "c_7b0724de9977ca514590" FOREIGN KEY ("ticket_id") REFERENCES "itsm"."tickets"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_a3dc14410841a66be73f" ON "service"."escalation_events" ("ticket_id");

ALTER TABLE "service"."escalation_events" ADD CONSTRAINT "c_3792d26497211d637a7c" FOREIGN KEY ("rule_id") REFERENCES "service"."escalation_rules"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_fcd96e011db15751204e" ON "service"."escalation_events" ("rule_id");

ALTER TABLE "workflow"."versions" ADD CONSTRAINT "c_0051aed4dca23888b691" FOREIGN KEY ("definition_id") REFERENCES "workflow"."definitions"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_0e28597b3c997be685c0" ON "workflow"."versions" ("definition_id");

ALTER TABLE "workflow"."versions" ADD CONSTRAINT "c_e8acf3102feccccd088a" FOREIGN KEY ("published_by") REFERENCES "iam"."principals"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_f034bcdd4ad5531d84e5" ON "workflow"."versions" ("published_by");

ALTER TABLE "workflow"."steps" ADD CONSTRAINT "c_a54bb4dd5646d6f3cb7c" FOREIGN KEY ("version_id") REFERENCES "workflow"."versions"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_197a086e40903c92d1e4" ON "workflow"."steps" ("version_id");

ALTER TABLE "workflow"."steps" ADD CONSTRAINT "c_3e07c5a54681c3c60654" FOREIGN KEY ("required_permission_id") REFERENCES "iam"."permissions"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_7518bf8a380abf6f06e6" ON "workflow"."steps" ("required_permission_id");

ALTER TABLE "workflow"."edges" ADD CONSTRAINT "c_7f344b8829628ea9bb72" FOREIGN KEY ("version_id") REFERENCES "workflow"."versions"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_a094d5f7fe784d33129a" ON "workflow"."edges" ("version_id");

ALTER TABLE "workflow"."edges" ADD CONSTRAINT "c_168f5e2cea0cb32eb2f2" FOREIGN KEY ("from_step_id") REFERENCES "workflow"."steps"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_37590dee9b19e4ef649a" ON "workflow"."edges" ("from_step_id");

ALTER TABLE "workflow"."edges" ADD CONSTRAINT "c_8270b3a282399f5e2272" FOREIGN KEY ("to_step_id") REFERENCES "workflow"."steps"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_9aafe59b23464d2ea450" ON "workflow"."edges" ("to_step_id");

ALTER TABLE "workflow"."instances" ADD CONSTRAINT "c_7af3a437b2c922e420d5" FOREIGN KEY ("version_id") REFERENCES "workflow"."versions"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_848ce356f1c8b94dd180" ON "workflow"."instances" ("version_id");

ALTER TABLE "workflow"."instances" ADD CONSTRAINT "c_90c1971d2a6062468664" FOREIGN KEY ("parent_ticket_id") REFERENCES "itsm"."tickets"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_4c962f4dc699721b5b6d" ON "workflow"."instances" ("parent_ticket_id");

ALTER TABLE "workflow"."instances" ADD CONSTRAINT "c_cd9d584a60f436a8d775" FOREIGN KEY ("subject_person_id") REFERENCES "core"."persons"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_08b2319082db0b4e2837" ON "workflow"."instances" ("subject_person_id");

ALTER TABLE "workflow"."instances" ADD CONSTRAINT "c_dd312d7472007c1c619b" FOREIGN KEY ("organization_id") REFERENCES "core"."organizations"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_84d213f49039bd8b43ed" ON "workflow"."instances" ("organization_id");

ALTER TABLE "workflow"."step_runs" ADD CONSTRAINT "c_486f5ed730000e347d73" FOREIGN KEY ("instance_id") REFERENCES "workflow"."instances"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_c96ed26ca39e38b16028" ON "workflow"."step_runs" ("instance_id");

ALTER TABLE "workflow"."step_runs" ADD CONSTRAINT "c_ebdd942ed5b55c9143d9" FOREIGN KEY ("step_id") REFERENCES "workflow"."steps"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_606bd50724b046cb4cda" ON "workflow"."step_runs" ("step_id");

ALTER TABLE "workflow"."step_runs" ADD CONSTRAINT "c_f4f5e139c842db47a0d4" FOREIGN KEY ("child_ticket_id") REFERENCES "itsm"."tickets"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_80f2332f9c461331fd88" ON "workflow"."step_runs" ("child_ticket_id");

ALTER TABLE "workflow"."approval_requests" ADD CONSTRAINT "c_b66a58c6ecbfc2061146" FOREIGN KEY ("instance_id") REFERENCES "workflow"."instances"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_3496deecca24c70c6247" ON "workflow"."approval_requests" ("instance_id");

ALTER TABLE "workflow"."approval_requests" ADD CONSTRAINT "c_c75449fb71460f751046" FOREIGN KEY ("ticket_id") REFERENCES "itsm"."tickets"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_0e62be0e12357b7f6df5" ON "workflow"."approval_requests" ("ticket_id");

ALTER TABLE "workflow"."approval_requests" ADD CONSTRAINT "c_120d2bad79b1e276bf83" FOREIGN KEY ("requested_by") REFERENCES "iam"."principals"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_609e84b1738817371704" ON "workflow"."approval_requests" ("requested_by");

ALTER TABLE "workflow"."approval_decisions" ADD CONSTRAINT "c_5ebc6bca8b0b14b5c015" FOREIGN KEY ("request_id") REFERENCES "workflow"."approval_requests"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_4138baaf48ffd8293b7e" ON "workflow"."approval_decisions" ("request_id");

ALTER TABLE "workflow"."approval_decisions" ADD CONSTRAINT "c_0f582609ad5df7599181" FOREIGN KEY ("approver_id") REFERENCES "iam"."principals"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_3afb4393caf5b53f906e" ON "workflow"."approval_decisions" ("approver_id");

ALTER TABLE "workflow"."automation_runs" ADD CONSTRAINT "c_80c8c17439dd3102763f" FOREIGN KEY ("rule_id") REFERENCES "workflow"."automation_rules"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_36b4a439392b57c08429" ON "workflow"."automation_runs" ("rule_id");

ALTER TABLE "cmdb"."items" ADD CONSTRAINT "c_c645fec017754a08df09" FOREIGN KEY ("type_id") REFERENCES "cmdb"."item_types"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_3b71db9d08009eec955a" ON "cmdb"."items" ("type_id");

ALTER TABLE "cmdb"."items" ADD CONSTRAINT "c_a53e3bc35c86cec0b602" FOREIGN KEY ("owner_org_id") REFERENCES "core"."organizations"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_0da542ccae0eb70e2427" ON "cmdb"."items" ("owner_org_id");

ALTER TABLE "cmdb"."items" ADD CONSTRAINT "c_222a6c9fd4833580e96c" FOREIGN KEY ("manager_org_id") REFERENCES "core"."organizations"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_33e6a0687b6efcd65288" ON "cmdb"."items" ("manager_org_id");

ALTER TABLE "cmdb"."items" ADD CONSTRAINT "c_fe27efbb900c187cbf92" FOREIGN KEY ("site_id") REFERENCES "core"."sites"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_b3e88a87d596e265f0a2" ON "cmdb"."items" ("site_id");

ALTER TABLE "cmdb"."items" ADD CONSTRAINT "c_fd9ea137965f705cd6f3" FOREIGN KEY ("location_id") REFERENCES "core"."locations"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_d4cc25323939c5a12dcd" ON "cmdb"."items" ("location_id");

ALTER TABLE "cmdb"."item_identifiers" ADD CONSTRAINT "c_7f28930e53447e5624dc" FOREIGN KEY ("item_id") REFERENCES "cmdb"."items"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_f8a7ce56892a0e7c9e3d" ON "cmdb"."item_identifiers" ("item_id");

ALTER TABLE "cmdb"."ownership_history" ADD CONSTRAINT "c_dce072cfa8bc7090d46a" FOREIGN KEY ("item_id") REFERENCES "cmdb"."items"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_45f6192a05ffcf0a825b" ON "cmdb"."ownership_history" ("item_id");

ALTER TABLE "cmdb"."ownership_history" ADD CONSTRAINT "c_6e599bf1bd6dd637c34d" FOREIGN KEY ("organization_id") REFERENCES "core"."organizations"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_3290a96d958cfed19513" ON "cmdb"."ownership_history" ("organization_id");

ALTER TABLE "cmdb"."ownership_history" ADD CONSTRAINT "c_65c8b7200fc57014327e" FOREIGN KEY ("evidence_file_id") REFERENCES "docs"."files"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_30e1a963abc949f28db8" ON "cmdb"."ownership_history" ("evidence_file_id");

ALTER TABLE "cmdb"."management_mandates" ADD CONSTRAINT "c_27d235f239dde9632532" FOREIGN KEY ("item_id") REFERENCES "cmdb"."items"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_9bf72984c8594e46d7d7" ON "cmdb"."management_mandates" ("item_id");

ALTER TABLE "cmdb"."management_mandates" ADD CONSTRAINT "c_a3b03c253669a662b44c" FOREIGN KEY ("provider_org_id") REFERENCES "core"."organizations"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_2d68135d6b282d032a39" ON "cmdb"."management_mandates" ("provider_org_id");

ALTER TABLE "cmdb"."management_mandates" ADD CONSTRAINT "c_112db7161f51a44ead7e" FOREIGN KEY ("contract_id") REFERENCES "commercial"."contracts"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_d09953e1e2523e3af00e" ON "cmdb"."management_mandates" ("contract_id");

ALTER TABLE "cmdb"."assignments" ADD CONSTRAINT "c_5f917146f816682120a3" FOREIGN KEY ("item_id") REFERENCES "cmdb"."items"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_8f34e2bafc5208932fe2" ON "cmdb"."assignments" ("item_id");

ALTER TABLE "cmdb"."assignments" ADD CONSTRAINT "c_074148d88e30a39239d3" FOREIGN KEY ("person_id") REFERENCES "core"."persons"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_5a74c4c061428b42244e" ON "cmdb"."assignments" ("person_id");

ALTER TABLE "cmdb"."assignments" ADD CONSTRAINT "c_8f49ec4a805703d333c0" FOREIGN KEY ("team_id") REFERENCES "core"."teams"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_8a2b0e78830498085189" ON "cmdb"."assignments" ("team_id");

ALTER TABLE "cmdb"."assignments" ADD CONSTRAINT "c_f3b1e826cfce2825b30a" FOREIGN KEY ("site_id") REFERENCES "core"."sites"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_18113878a0f46c0863ee" ON "cmdb"."assignments" ("site_id");

ALTER TABLE "cmdb"."relations" ADD CONSTRAINT "c_3f0b652ee59a8cd567bb" FOREIGN KEY ("source_item_id") REFERENCES "cmdb"."items"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_1007e9ad3327a616ccf6" ON "cmdb"."relations" ("source_item_id");

ALTER TABLE "cmdb"."relations" ADD CONSTRAINT "c_b5fb3bd24935bf088074" FOREIGN KEY ("target_item_id") REFERENCES "cmdb"."items"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_34493ad545cb49b95325" ON "cmdb"."relations" ("target_item_id");

ALTER TABLE "cmdb"."models" ADD CONSTRAINT "c_a246fd7577c20f58afcc" FOREIGN KEY ("manufacturer_org_id") REFERENCES "core"."organizations"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_966d20d97a3366407606" ON "cmdb"."models" ("manufacturer_org_id");

ALTER TABLE "cmdb"."hardware" ADD CONSTRAINT "c_f473eb5d1fb0c54913a4" FOREIGN KEY ("item_id") REFERENCES "cmdb"."items"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_55ff71a70da02cf0b304" ON "cmdb"."hardware" ("item_id");

ALTER TABLE "cmdb"."hardware" ADD CONSTRAINT "c_da74447d1d948c3294e6" FOREIGN KEY ("model_id") REFERENCES "cmdb"."models"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_eb95003b6044d0d75d06" ON "cmdb"."hardware" ("model_id");

ALTER TABLE "cmdb"."components" ADD CONSTRAINT "c_934c3af20bcf962acc1e" FOREIGN KEY ("parent_item_id") REFERENCES "cmdb"."items"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_494846ad385d48722275" ON "cmdb"."components" ("parent_item_id");

ALTER TABLE "cmdb"."components" ADD CONSTRAINT "c_56f14445fef12b13ef8f" FOREIGN KEY ("child_item_id") REFERENCES "cmdb"."items"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_02ddc04cb9f39fdd2a1c" ON "cmdb"."components" ("child_item_id");

ALTER TABLE "cmdb"."os_installations" ADD CONSTRAINT "c_f132f3a56639560f503b" FOREIGN KEY ("item_id") REFERENCES "cmdb"."items"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_8a63a74bba0f4f2e7a6c" ON "cmdb"."os_installations" ("item_id");

ALTER TABLE "cmdb"."software_products" ADD CONSTRAINT "c_26629ed827d1decc2db2" FOREIGN KEY ("publisher_org_id") REFERENCES "core"."organizations"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_648f4ea86c90efa8e451" ON "cmdb"."software_products" ("publisher_org_id");

ALTER TABLE "cmdb"."software_versions" ADD CONSTRAINT "c_031ee332b54fd2234eb1" FOREIGN KEY ("product_id") REFERENCES "cmdb"."software_products"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_343753b379bc723a8618" ON "cmdb"."software_versions" ("product_id");

ALTER TABLE "cmdb"."software_installations" ADD CONSTRAINT "c_8957b392c8aef745664d" FOREIGN KEY ("item_id") REFERENCES "cmdb"."items"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_3f06ae70daea02917b85" ON "cmdb"."software_installations" ("item_id");

ALTER TABLE "cmdb"."software_installations" ADD CONSTRAINT "c_cfcf403848881ffccd49" FOREIGN KEY ("software_version_id") REFERENCES "cmdb"."software_versions"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_267ff216759ff2a6a536" ON "cmdb"."software_installations" ("software_version_id");

ALTER TABLE "cmdb"."license_entitlements" ADD CONSTRAINT "c_b4bdb5ebad01d8bfe360" FOREIGN KEY ("product_id") REFERENCES "cmdb"."software_products"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_1087a76cc714bce54d7e" ON "cmdb"."license_entitlements" ("product_id");

ALTER TABLE "cmdb"."license_entitlements" ADD CONSTRAINT "c_c0c7132d1fd51890cdb8" FOREIGN KEY ("owner_org_id") REFERENCES "core"."organizations"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_a8bf9daf6bf8ee5f9937" ON "cmdb"."license_entitlements" ("owner_org_id");

ALTER TABLE "cmdb"."license_entitlements" ADD CONSTRAINT "c_539b7a37ff5c997b6857" FOREIGN KEY ("contract_id") REFERENCES "commercial"."contracts"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_1bc22ef96304ba8ce159" ON "cmdb"."license_entitlements" ("contract_id");

ALTER TABLE "cmdb"."license_allocations" ADD CONSTRAINT "c_ca132980d5ab240f2154" FOREIGN KEY ("entitlement_id") REFERENCES "cmdb"."license_entitlements"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_3bc02295cba088249ffc" ON "cmdb"."license_allocations" ("entitlement_id");

ALTER TABLE "cmdb"."license_allocations" ADD CONSTRAINT "c_771b142c914ebfb8aae0" FOREIGN KEY ("person_id") REFERENCES "core"."persons"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_44fab7012dd6d244cd0c" ON "cmdb"."license_allocations" ("person_id");

ALTER TABLE "cmdb"."license_allocations" ADD CONSTRAINT "c_1006880355ab73ac77a6" FOREIGN KEY ("item_id") REFERENCES "cmdb"."items"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_04a51d40a433eef7604f" ON "cmdb"."license_allocations" ("item_id");

ALTER TABLE "cmdb"."network_interfaces" ADD CONSTRAINT "c_8e4fe3a55e6e4bb5ef3a" FOREIGN KEY ("item_id") REFERENCES "cmdb"."items"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_7c96c564c5c22f66021e" ON "cmdb"."network_interfaces" ("item_id");

ALTER TABLE "cmdb"."network_segments" ADD CONSTRAINT "c_0a29d27c5a5e54a1ba3f" FOREIGN KEY ("owner_org_id") REFERENCES "core"."organizations"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_2dc92b1ed40a6bddbfdd" ON "cmdb"."network_segments" ("owner_org_id");

ALTER TABLE "cmdb"."network_segments" ADD CONSTRAINT "c_957ed6a36788213d1a03" FOREIGN KEY ("site_id") REFERENCES "core"."sites"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_a47773320ba6e8c460f7" ON "cmdb"."network_segments" ("site_id");

ALTER TABLE "cmdb"."ip_assignments" ADD CONSTRAINT "c_327ad2f612fa5cfc41bd" FOREIGN KEY ("interface_id") REFERENCES "cmdb"."network_interfaces"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_5cb8cdb4d3d292359fb2" ON "cmdb"."ip_assignments" ("interface_id");

ALTER TABLE "cmdb"."ip_assignments" ADD CONSTRAINT "c_6ec0f376e3ac66f58684" FOREIGN KEY ("segment_id") REFERENCES "cmdb"."network_segments"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_2b2231fac0c540137c76" ON "cmdb"."ip_assignments" ("segment_id");

ALTER TABLE "cmdb"."network_links" ADD CONSTRAINT "c_b79b4df6095fae171cd2" FOREIGN KEY ("from_interface_id") REFERENCES "cmdb"."network_interfaces"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_5c511e77ad7b6bd17007" ON "cmdb"."network_links" ("from_interface_id");

ALTER TABLE "cmdb"."network_links" ADD CONSTRAINT "c_30f91ce3db0a36a29956" FOREIGN KEY ("to_interface_id") REFERENCES "cmdb"."network_interfaces"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_f7b225175cac090ea8d5" ON "cmdb"."network_links" ("to_interface_id");

ALTER TABLE "cmdb"."domains" ADD CONSTRAINT "c_8985cb312969280af26c" FOREIGN KEY ("item_id") REFERENCES "cmdb"."items"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_7afbf767fd39cae8a36a" ON "cmdb"."domains" ("item_id");

ALTER TABLE "cmdb"."domains" ADD CONSTRAINT "c_543b283e1d73739808d9" FOREIGN KEY ("registrar_org_id") REFERENCES "core"."organizations"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_c2ce76abbc62f4151e35" ON "cmdb"."domains" ("registrar_org_id");

ALTER TABLE "cmdb"."dns_records" ADD CONSTRAINT "c_f1af7bf8d73a14b02137" FOREIGN KEY ("domain_id") REFERENCES "cmdb"."domains"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_065980bdb983113c788b" ON "cmdb"."dns_records" ("domain_id");

ALTER TABLE "cmdb"."certificates" ADD CONSTRAINT "c_9e5393e05893727fb353" FOREIGN KEY ("item_id") REFERENCES "cmdb"."items"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_0f028cdde2c14296f0cf" ON "cmdb"."certificates" ("item_id");

ALTER TABLE "cmdb"."cloud_accounts" ADD CONSTRAINT "c_d5f0d30a155276138609" FOREIGN KEY ("item_id") REFERENCES "cmdb"."items"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_f119fea8c3cac79f1575" ON "cmdb"."cloud_accounts" ("item_id");

ALTER TABLE "cmdb"."cloud_accounts" ADD CONSTRAINT "c_49142ea5d22dc07dfa22" FOREIGN KEY ("billing_owner_org_id") REFERENCES "core"."organizations"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_b04cdf678076332d7eef" ON "cmdb"."cloud_accounts" ("billing_owner_org_id");

ALTER TABLE "cmdb"."cloud_resources" ADD CONSTRAINT "c_a3a3d2574e3ee1a00f0a" FOREIGN KEY ("item_id") REFERENCES "cmdb"."items"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_70aefcad3b3ba90d6fa0" ON "cmdb"."cloud_resources" ("item_id");

ALTER TABLE "cmdb"."cloud_resources" ADD CONSTRAINT "c_06f8120411b42c54b567" FOREIGN KEY ("cloud_account_id") REFERENCES "cmdb"."cloud_accounts"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_7920f8bd400829953f1e" ON "cmdb"."cloud_resources" ("cloud_account_id");

ALTER TABLE "cmdb"."hosting_services" ADD CONSTRAINT "c_4e2bccbc266588dee249" FOREIGN KEY ("item_id") REFERENCES "cmdb"."items"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_4798e59029e0e04b6254" ON "cmdb"."hosting_services" ("item_id");

ALTER TABLE "cmdb"."hosting_services" ADD CONSTRAINT "c_001d2ca250b71935371a" FOREIGN KEY ("provider_org_id") REFERENCES "core"."organizations"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_72266bfe1e75e73698c5" ON "cmdb"."hosting_services" ("provider_org_id");

ALTER TABLE "cmdb"."hosting_services" ADD CONSTRAINT "c_db93d00cccb4dee91bb4" FOREIGN KEY ("backup_policy_id") REFERENCES "cmdb"."backup_policies"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_69f7d454bc3e469923de" ON "cmdb"."hosting_services" ("backup_policy_id");

ALTER TABLE "cmdb"."backup_checks" ADD CONSTRAINT "c_6d7fb459c6dd5505861a" FOREIGN KEY ("item_id") REFERENCES "cmdb"."items"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_aea722132777d06e229e" ON "cmdb"."backup_checks" ("item_id");

ALTER TABLE "cmdb"."backup_checks" ADD CONSTRAINT "c_e30c149b93aa99e2e63b" FOREIGN KEY ("policy_id") REFERENCES "cmdb"."backup_policies"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_4d477a9f5c07362a386b" ON "cmdb"."backup_checks" ("policy_id");

ALTER TABLE "cmdb"."technical_accounts" ADD CONSTRAINT "c_8c35da09c17d773e8de6" FOREIGN KEY ("item_id") REFERENCES "cmdb"."items"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_f0e63b2ab5ebb4627a5a" ON "cmdb"."technical_accounts" ("item_id");

ALTER TABLE "cmdb"."technical_accounts" ADD CONSTRAINT "c_4d502f6ee2f0e244d504" FOREIGN KEY ("owner_person_id") REFERENCES "core"."persons"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_0947e438aba3db53ee87" ON "cmdb"."technical_accounts" ("owner_person_id");

ALTER TABLE "cmdb"."item_observations" ADD CONSTRAINT "c_1ec303f5420580c28e13" FOREIGN KEY ("item_id") REFERENCES "cmdb"."items"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_35b3686abc5a14d37579" ON "cmdb"."item_observations" ("item_id");

ALTER TABLE "cmdb"."item_observations" ADD CONSTRAINT "c_2b06936047dfb091f976" FOREIGN KEY ("connection_id") REFERENCES "integration"."connections"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_cdcec05ff3f4de040067" ON "cmdb"."item_observations" ("connection_id");

ALTER TABLE "inventory"."warehouses" ADD CONSTRAINT "c_00a7265e96491ebe8398" FOREIGN KEY ("organization_id") REFERENCES "core"."organizations"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_3894e47d0ba971d70bab" ON "inventory"."warehouses" ("organization_id");

ALTER TABLE "inventory"."warehouses" ADD CONSTRAINT "c_105c77bc3446645de51a" FOREIGN KEY ("location_id") REFERENCES "core"."locations"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_ede86d11097f26d832ef" ON "inventory"."warehouses" ("location_id");

ALTER TABLE "inventory"."stock_products" ADD CONSTRAINT "c_f5f3719a8bc07dda4c98" FOREIGN KEY ("model_id") REFERENCES "cmdb"."models"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_5d5b0140374c8aa0c409" ON "inventory"."stock_products" ("model_id");

ALTER TABLE "inventory"."stock_movements" ADD CONSTRAINT "c_9f04de90ece63b0ba953" FOREIGN KEY ("product_id") REFERENCES "inventory"."stock_products"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_7752731d740073f5e87e" ON "inventory"."stock_movements" ("product_id");

ALTER TABLE "inventory"."stock_movements" ADD CONSTRAINT "c_78fa556f3a4b9245ffb8" FOREIGN KEY ("item_id") REFERENCES "cmdb"."items"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_5e6eb02cbed802e02f1a" ON "inventory"."stock_movements" ("item_id");

ALTER TABLE "inventory"."stock_movements" ADD CONSTRAINT "c_c45055cdcd4515cb79ee" FOREIGN KEY ("warehouse_id") REFERENCES "inventory"."warehouses"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_8a83e1b3eb203bcd41f4" ON "inventory"."stock_movements" ("warehouse_id");

ALTER TABLE "inventory"."stock_movements" ADD CONSTRAINT "c_aa2a38e45458b0345d96" FOREIGN KEY ("owner_org_id") REFERENCES "core"."organizations"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_01b8697030e47571ce30" ON "inventory"."stock_movements" ("owner_org_id");

ALTER TABLE "inventory"."stock_movements" ADD CONSTRAINT "c_d9a1fb84bacba4adae65" FOREIGN KEY ("reversal_of_id") REFERENCES "inventory"."stock_movements"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_7d3744c50c78b08b8087" ON "inventory"."stock_movements" ("reversal_of_id");

ALTER TABLE "inventory"."stock_reservations" ADD CONSTRAINT "c_8ffd567f83d3ce6f4f4d" FOREIGN KEY ("product_id") REFERENCES "inventory"."stock_products"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_4fd3495f2fe6d13e00d4" ON "inventory"."stock_reservations" ("product_id");

ALTER TABLE "inventory"."stock_reservations" ADD CONSTRAINT "c_88eb57925597b72c7da7" FOREIGN KEY ("warehouse_id") REFERENCES "inventory"."warehouses"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_7ef65d591336fea84e99" ON "inventory"."stock_reservations" ("warehouse_id");

ALTER TABLE "inventory"."stock_reservations" ADD CONSTRAINT "c_b799d74c96447d04cfef" FOREIGN KEY ("ticket_id") REFERENCES "itsm"."tickets"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_9cf485f5efa2f092febe" ON "inventory"."stock_reservations" ("ticket_id");

ALTER TABLE "inventory"."purchase_orders" ADD CONSTRAINT "c_1d123e83b80325f504f3" FOREIGN KEY ("supplier_org_id") REFERENCES "core"."organizations"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_54d50457ed873b181977" ON "inventory"."purchase_orders" ("supplier_org_id");

ALTER TABLE "inventory"."purchase_orders" ADD CONSTRAINT "c_93a9d32280d0adba01b1" FOREIGN KEY ("buyer_org_id") REFERENCES "core"."organizations"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_a01e143bc9f00a6ad94c" ON "inventory"."purchase_orders" ("buyer_org_id");

ALTER TABLE "inventory"."purchase_lines" ADD CONSTRAINT "c_6744a0bbed9f3606048a" FOREIGN KEY ("order_id") REFERENCES "inventory"."purchase_orders"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_2f3d02246050b64f30e0" ON "inventory"."purchase_lines" ("order_id");

ALTER TABLE "inventory"."purchase_lines" ADD CONSTRAINT "c_b66f4ac1fc0bb6a5198e" FOREIGN KEY ("product_id") REFERENCES "inventory"."stock_products"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_a708c452db7e24d1286b" ON "inventory"."purchase_lines" ("product_id");

ALTER TABLE "inventory"."receipts" ADD CONSTRAINT "c_dce2364672209ba4d4c7" FOREIGN KEY ("order_id") REFERENCES "inventory"."purchase_orders"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_463b7e36f7b5925eb970" ON "inventory"."receipts" ("order_id");

ALTER TABLE "inventory"."receipts" ADD CONSTRAINT "c_62629bd1e5ed9128ee80" FOREIGN KEY ("received_by") REFERENCES "iam"."principals"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_5789b533fc73da6affbe" ON "inventory"."receipts" ("received_by");

ALTER TABLE "inventory"."receipts" ADD CONSTRAINT "c_3f2da06e2e72c522ad6e" FOREIGN KEY ("warehouse_id") REFERENCES "inventory"."warehouses"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_21266014703ea8254d54" ON "inventory"."receipts" ("warehouse_id");

ALTER TABLE "inventory"."receipt_lines" ADD CONSTRAINT "c_033413492f89b3db534a" FOREIGN KEY ("receipt_id") REFERENCES "inventory"."receipts"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_606fa0ab73650420c138" ON "inventory"."receipt_lines" ("receipt_id");

ALTER TABLE "inventory"."receipt_lines" ADD CONSTRAINT "c_00f9e6b8e2ff506a086d" FOREIGN KEY ("purchase_line_id") REFERENCES "inventory"."purchase_lines"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_a13b52034fa5f75a5e57" ON "inventory"."receipt_lines" ("purchase_line_id");

ALTER TABLE "inventory"."receipt_lines" ADD CONSTRAINT "c_297c80dbcb06eed4d880" FOREIGN KEY ("item_id") REFERENCES "cmdb"."items"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_90ed0e8889056d6fd6bf" ON "inventory"."receipt_lines" ("item_id");

ALTER TABLE "inventory"."warranties" ADD CONSTRAINT "c_082f3e9190fd2325e44d" FOREIGN KEY ("item_id") REFERENCES "cmdb"."items"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_33ebd647b709b0940e8b" ON "inventory"."warranties" ("item_id");

ALTER TABLE "inventory"."warranties" ADD CONSTRAINT "c_2ac72adc77a28827ee05" FOREIGN KEY ("provider_org_id") REFERENCES "core"."organizations"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_4e7ade5c83b3ffdc46d8" ON "inventory"."warranties" ("provider_org_id");

ALTER TABLE "inventory"."repairs" ADD CONSTRAINT "c_e31b3554624fb3f0daf9" FOREIGN KEY ("item_id") REFERENCES "cmdb"."items"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_f7cd3545c2421a93b0f3" ON "inventory"."repairs" ("item_id");

ALTER TABLE "inventory"."repairs" ADD CONSTRAINT "c_2b2e2f51a333f373d89d" FOREIGN KEY ("ticket_id") REFERENCES "itsm"."tickets"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_f6dacdd438e2bee0db5e" ON "inventory"."repairs" ("ticket_id");

ALTER TABLE "inventory"."repairs" ADD CONSTRAINT "c_2067ca0df42fd38e8d4e" FOREIGN KEY ("supplier_org_id") REFERENCES "core"."organizations"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_d09b007616aed3fac1c9" ON "inventory"."repairs" ("supplier_org_id");

ALTER TABLE "inventory"."loans" ADD CONSTRAINT "c_ddcf9e6edf9f7a08558d" FOREIGN KEY ("item_id") REFERENCES "cmdb"."items"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_b99ab4f3bc685e03ccc2" ON "inventory"."loans" ("item_id");

ALTER TABLE "inventory"."loans" ADD CONSTRAINT "c_d3a5630b21d848d7a71e" FOREIGN KEY ("borrower_org_id") REFERENCES "core"."organizations"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_4d7964ea6b265fd0bb97" ON "inventory"."loans" ("borrower_org_id");

ALTER TABLE "inventory"."loans" ADD CONSTRAINT "c_5e3c5141e20830823e9c" FOREIGN KEY ("person_id") REFERENCES "core"."persons"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_fca63cbd8973ed2ecb3d" ON "inventory"."loans" ("person_id");

ALTER TABLE "inventory"."loans" ADD CONSTRAINT "c_2adb09e3afe6a0f66731" FOREIGN KEY ("contract_id") REFERENCES "commercial"."contracts"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_265fc98a0ee2bdfb74c0" ON "inventory"."loans" ("contract_id");

ALTER TABLE "inventory"."stock_counts" ADD CONSTRAINT "c_6669ccfef96068b6870b" FOREIGN KEY ("warehouse_id") REFERENCES "inventory"."warehouses"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_37f2a646386f02bca946" ON "inventory"."stock_counts" ("warehouse_id");

ALTER TABLE "inventory"."stock_counts" ADD CONSTRAINT "c_bbed7c0c40d4db848a51" FOREIGN KEY ("approved_by") REFERENCES "iam"."principals"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_3f09a5d6ad2e8a49b5ec" ON "inventory"."stock_counts" ("approved_by");

ALTER TABLE "inventory"."stock_count_lines" ADD CONSTRAINT "c_7a3b3bad19ff1d3f3ab5" FOREIGN KEY ("count_id") REFERENCES "inventory"."stock_counts"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_cedad911560a3910c81d" ON "inventory"."stock_count_lines" ("count_id");

ALTER TABLE "inventory"."stock_count_lines" ADD CONSTRAINT "c_486c812a02ac34de12ef" FOREIGN KEY ("product_id") REFERENCES "inventory"."stock_products"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_33342e24acac67b8a4a0" ON "inventory"."stock_count_lines" ("product_id");

ALTER TABLE "inventory"."stock_count_lines" ADD CONSTRAINT "c_5cd32798d0defa977718" FOREIGN KEY ("item_id") REFERENCES "cmdb"."items"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_9843a659219439d6b2cf" ON "inventory"."stock_count_lines" ("item_id");

ALTER TABLE "inventory"."disposals" ADD CONSTRAINT "c_00d0b3bcc5b17f736421" FOREIGN KEY ("item_id") REFERENCES "cmdb"."items"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_1356313828985c35efae" ON "inventory"."disposals" ("item_id");

ALTER TABLE "inventory"."disposals" ADD CONSTRAINT "c_bb578a605fd92c883d9d" FOREIGN KEY ("approved_by") REFERENCES "iam"."principals"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_dde182d8c6dea1818d84" ON "inventory"."disposals" ("approved_by");

ALTER TABLE "inventory"."disposals" ADD CONSTRAINT "c_29dea682a480b3e68826" FOREIGN KEY ("erasure_evidence_id") REFERENCES "docs"."files"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_7b933b3dcd0e99bd026c" ON "inventory"."disposals" ("erasure_evidence_id");

ALTER TABLE "inventory"."disposals" ADD CONSTRAINT "c_ed68f68da4c63f7c4628" FOREIGN KEY ("recipient_org_id") REFERENCES "core"."organizations"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_5f5e7356162b87aba09b" ON "inventory"."disposals" ("recipient_org_id");

ALTER TABLE "commercial"."contracts" ADD CONSTRAINT "c_1b61f06393823b86edea" FOREIGN KEY ("provider_org_id") REFERENCES "core"."organizations"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_147dd66f9393f8badc2e" ON "commercial"."contracts" ("provider_org_id");

ALTER TABLE "commercial"."contracts" ADD CONSTRAINT "c_b06e3668ef2709d80eb5" FOREIGN KEY ("signatory_org_id") REFERENCES "core"."organizations"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_a0f4b98e9567f9d27e65" ON "commercial"."contracts" ("signatory_org_id");

ALTER TABLE "commercial"."contract_versions" ADD CONSTRAINT "c_ae99670d5e1fa14b0d37" FOREIGN KEY ("contract_id") REFERENCES "commercial"."contracts"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_a66527bf28bb9de7b5ad" ON "commercial"."contract_versions" ("contract_id");

ALTER TABLE "commercial"."contract_versions" ADD CONSTRAINT "c_bc6a98ae6110f51b2122" FOREIGN KEY ("terms_file_id") REFERENCES "docs"."files"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_abf86e8c4db253b5acc1" ON "commercial"."contract_versions" ("terms_file_id");

ALTER TABLE "commercial"."contract_scopes" ADD CONSTRAINT "c_b15583de30569cb9529b" FOREIGN KEY ("version_id") REFERENCES "commercial"."contract_versions"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_c218f0edfc386d0322e7" ON "commercial"."contract_scopes" ("version_id");

ALTER TABLE "commercial"."contract_scopes" ADD CONSTRAINT "c_d5b34ebae50e74b44086" FOREIGN KEY ("organization_id") REFERENCES "core"."organizations"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_82661aa485021e487d07" ON "commercial"."contract_scopes" ("organization_id");

ALTER TABLE "commercial"."contract_scopes" ADD CONSTRAINT "c_5e4fe7bc9d4fc42420b7" FOREIGN KEY ("site_id") REFERENCES "core"."sites"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_f6a3471892cf2382b9b0" ON "commercial"."contract_scopes" ("site_id");

ALTER TABLE "commercial"."contract_scopes" ADD CONSTRAINT "c_235e6f918aa37a623fa2" FOREIGN KEY ("item_id") REFERENCES "cmdb"."items"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_c7c736a280fef2405355" ON "commercial"."contract_scopes" ("item_id");

ALTER TABLE "commercial"."contract_scopes" ADD CONSTRAINT "c_72a5c407d97c6fe6ceb6" FOREIGN KEY ("service_id") REFERENCES "service"."catalog_items"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_117c2209d7d0b878c20d" ON "commercial"."contract_scopes" ("service_id");

ALTER TABLE "commercial"."contract_components" ADD CONSTRAINT "c_075f2137ac1c9762ba1c" FOREIGN KEY ("version_id") REFERENCES "commercial"."contract_versions"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_8e65d862f15a7b25d47f" ON "commercial"."contract_components" ("version_id");

ALTER TABLE "commercial"."contract_components" ADD CONSTRAINT "c_e564b709dab7d44f3944" FOREIGN KEY ("product_id") REFERENCES "commercial"."products"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_4f216345b113f5659837" ON "commercial"."contract_components" ("product_id");

ALTER TABLE "commercial"."contract_sla_bindings" ADD CONSTRAINT "c_6a7211b462129ae57acd" FOREIGN KEY ("version_id") REFERENCES "commercial"."contract_versions"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_ae3c50ff70b7a6cd729e" ON "commercial"."contract_sla_bindings" ("version_id");

ALTER TABLE "commercial"."contract_sla_bindings" ADD CONSTRAINT "c_55270b67a93fe8bec9bd" FOREIGN KEY ("policy_id") REFERENCES "service"."sla_policies"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_6c0b02453e4c52f74168" ON "commercial"."contract_sla_bindings" ("policy_id");

ALTER TABLE "commercial"."contract_sla_bindings" ADD CONSTRAINT "c_5712c9bd44ae83f69334" FOREIGN KEY ("service_id") REFERENCES "service"."catalog_items"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_4480475e87da43e26664" ON "commercial"."contract_sla_bindings" ("service_id");

ALTER TABLE "commercial"."contract_payers" ADD CONSTRAINT "c_a00cc03bf1f6531335f8" FOREIGN KEY ("version_id") REFERENCES "commercial"."contract_versions"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_4274d67ccf4f64abed3d" ON "commercial"."contract_payers" ("version_id");

ALTER TABLE "commercial"."contract_payers" ADD CONSTRAINT "c_da894a71325bb27e00b2" FOREIGN KEY ("payer_org_id") REFERENCES "core"."organizations"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_1b8044354b895bd618d4" ON "commercial"."contract_payers" ("payer_org_id");

ALTER TABLE "commercial"."contract_payers" ADD CONSTRAINT "c_c600b1140136a453c8b1" FOREIGN KEY ("covered_org_id") REFERENCES "core"."organizations"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_da0b4fea6735d2947c3c" ON "commercial"."contract_payers" ("covered_org_id");

ALTER TABLE "commercial"."rate_rules" ADD CONSTRAINT "c_8ea94a84ea224594c96a" FOREIGN KEY ("component_id") REFERENCES "commercial"."contract_components"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_60ac7afc72a10d9924f5" ON "commercial"."rate_rules" ("component_id");

ALTER TABLE "commercial"."rate_rules" ADD CONSTRAINT "c_5fff90b168690c9a9eb6" FOREIGN KEY ("skill_id") REFERENCES "people"."skills"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_61a169df1bbb08a69158" ON "commercial"."rate_rules" ("skill_id");

ALTER TABLE "commercial"."credit_accounts" ADD CONSTRAINT "c_9b1d7b8d0fe0cd01136b" FOREIGN KEY ("contract_id") REFERENCES "commercial"."contracts"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_cfe5308fac0942749aa5" ON "commercial"."credit_accounts" ("contract_id");

ALTER TABLE "commercial"."credit_ledger" ADD CONSTRAINT "c_feb0ccd210baf4a93b41" FOREIGN KEY ("account_id") REFERENCES "commercial"."credit_accounts"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_10554aae38c7d1e87fc2" ON "commercial"."credit_ledger" ("account_id");

ALTER TABLE "commercial"."credit_ledger" ADD CONSTRAINT "c_ba31503e12ca1848fa90" FOREIGN KEY ("usage_event_id") REFERENCES "billing"."usage_events"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_1413ef8a2c5ab542f7c8" ON "commercial"."credit_ledger" ("usage_event_id");

ALTER TABLE "commercial"."credit_ledger" ADD CONSTRAINT "c_0ba6e5eda368edcda43c" FOREIGN KEY ("reversal_of_id") REFERENCES "commercial"."credit_ledger"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_9b2e0a511af4aa759bf1" ON "commercial"."credit_ledger" ("reversal_of_id");

ALTER TABLE "commercial"."quotes" ADD CONSTRAINT "c_11223f54c9f056b56577" FOREIGN KEY ("issuer_org_id") REFERENCES "core"."organizations"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_9639c7f24474e3d047a7" ON "commercial"."quotes" ("issuer_org_id");

ALTER TABLE "commercial"."quotes" ADD CONSTRAINT "c_d77fe392cd4c053279d0" FOREIGN KEY ("customer_org_id") REFERENCES "core"."organizations"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_84b47b16a09fa046ef09" ON "commercial"."quotes" ("customer_org_id");

ALTER TABLE "commercial"."quotes" ADD CONSTRAINT "c_287cc8d70fce812ad3f3" FOREIGN KEY ("opportunity_id") REFERENCES "crm"."opportunities"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_925db506354a77b90c8f" ON "commercial"."quotes" ("opportunity_id");

ALTER TABLE "commercial"."quote_lines" ADD CONSTRAINT "c_f73c84a99420eb80e0c2" FOREIGN KEY ("quote_id") REFERENCES "commercial"."quotes"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_a047db4579239e11650d" ON "commercial"."quote_lines" ("quote_id");

ALTER TABLE "commercial"."quote_lines" ADD CONSTRAINT "c_4ca1ceed1804835ece69" FOREIGN KEY ("product_id") REFERENCES "commercial"."products"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_8879c7b3ea34ab101bf0" ON "commercial"."quote_lines" ("product_id");

ALTER TABLE "commercial"."invoices" ADD CONSTRAINT "c_5a43f86287c5d3b47829" FOREIGN KEY ("issuer_org_id") REFERENCES "core"."organizations"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_5ab2eeb3fe21312aa996" ON "commercial"."invoices" ("issuer_org_id");

ALTER TABLE "commercial"."invoices" ADD CONSTRAINT "c_959e60c75f0c86f42766" FOREIGN KEY ("payer_org_id") REFERENCES "core"."organizations"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_cf20ed302000bcf8fab7" ON "commercial"."invoices" ("payer_org_id");

ALTER TABLE "commercial"."invoice_lines" ADD CONSTRAINT "c_b68d17d6f4cadf76724d" FOREIGN KEY ("invoice_id") REFERENCES "commercial"."invoices"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_cc2442c72290cf15643c" ON "commercial"."invoice_lines" ("invoice_id");

ALTER TABLE "commercial"."payments" ADD CONSTRAINT "c_9d5f0c6908591bc951d4" FOREIGN KEY ("payer_org_id") REFERENCES "core"."organizations"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_d23171cd209525bbfb16" ON "commercial"."payments" ("payer_org_id");

ALTER TABLE "commercial"."payment_allocations" ADD CONSTRAINT "c_5a0b1501bac15c894a6d" FOREIGN KEY ("payment_id") REFERENCES "commercial"."payments"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_eb918162b3abe419cd01" ON "commercial"."payment_allocations" ("payment_id");

ALTER TABLE "commercial"."payment_allocations" ADD CONSTRAINT "c_b8b38134ae45f35325df" FOREIGN KEY ("invoice_id") REFERENCES "commercial"."invoices"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_acb493e04e4885584a68" ON "commercial"."payment_allocations" ("invoice_id");

ALTER TABLE "commercial"."credit_notes" ADD CONSTRAINT "c_aa933e3efe1c531a8734" FOREIGN KEY ("invoice_id") REFERENCES "commercial"."invoices"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_fc041c7d12f6a20ce263" ON "commercial"."credit_notes" ("invoice_id");

ALTER TABLE "billing"."time_entries" ADD CONSTRAINT "c_03ce8768af0c65ace212" FOREIGN KEY ("person_id") REFERENCES "core"."persons"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_5e197dc174315e38845c" ON "billing"."time_entries" ("person_id");

ALTER TABLE "billing"."time_entries" ADD CONSTRAINT "c_a694c832727f30095e3c" FOREIGN KEY ("ticket_id") REFERENCES "itsm"."tickets"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_2f3f21d75f4623909bf5" ON "billing"."time_entries" ("ticket_id");

ALTER TABLE "billing"."time_entries" ADD CONSTRAINT "c_4c433a3156e25ddf46c4" FOREIGN KEY ("task_id") REFERENCES "project"."tasks"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_28c42a8cfaa28e053f95" ON "billing"."time_entries" ("task_id");

ALTER TABLE "billing"."time_entries" ADD CONSTRAINT "c_c19085538622e7204477" FOREIGN KEY ("intervention_id") REFERENCES "itsm"."interventions"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_f54f2f257384f4a60612" ON "billing"."time_entries" ("intervention_id");

ALTER TABLE "billing"."time_approvals" ADD CONSTRAINT "c_d8d01e87777426bfeb99" FOREIGN KEY ("time_entry_id") REFERENCES "billing"."time_entries"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_37c1a9f09fa33c6efe0a" ON "billing"."time_approvals" ("time_entry_id");

ALTER TABLE "billing"."time_approvals" ADD CONSTRAINT "c_d95aa75db63d3fe00889" FOREIGN KEY ("reviewer_id") REFERENCES "iam"."principals"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_d922d866be96dad33382" ON "billing"."time_approvals" ("reviewer_id");

ALTER TABLE "billing"."expenses" ADD CONSTRAINT "c_432582d206366922afd1" FOREIGN KEY ("ticket_id") REFERENCES "itsm"."tickets"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_6a6564c0b6ccde6850ab" ON "billing"."expenses" ("ticket_id");

ALTER TABLE "billing"."expenses" ADD CONSTRAINT "c_35bfa5fe493863717914" FOREIGN KEY ("project_id") REFERENCES "project"."projects"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_c552bc209be450bf3778" ON "billing"."expenses" ("project_id");

ALTER TABLE "billing"."expenses" ADD CONSTRAINT "c_cef92e53a6fad53028fe" FOREIGN KEY ("person_id") REFERENCES "core"."persons"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_010ac8ce34e7db287939" ON "billing"."expenses" ("person_id");

ALTER TABLE "billing"."expenses" ADD CONSTRAINT "c_3989be3a2dba7ea569c3" FOREIGN KEY ("receipt_file_id") REFERENCES "docs"."files"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_dc2253496d7c0ca84d71" ON "billing"."expenses" ("receipt_file_id");

ALTER TABLE "billing"."usage_events" ADD CONSTRAINT "c_935394c89ee4940c3b2a" FOREIGN KEY ("customer_org_id") REFERENCES "core"."organizations"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_0e1bc2919a76e1b3f3c4" ON "billing"."usage_events" ("customer_org_id");

ALTER TABLE "billing"."usage_events" ADD CONSTRAINT "c_712d59e273209d165ccc" FOREIGN KEY ("contract_version_id") REFERENCES "commercial"."contract_versions"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_ff0347d1833097acec04" ON "billing"."usage_events" ("contract_version_id");

ALTER TABLE "billing"."usage_events" ADD CONSTRAINT "c_07adfd745a86ab1fdfaf" FOREIGN KEY ("time_entry_id") REFERENCES "billing"."time_entries"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_0029a93cc2c1a9f701d3" ON "billing"."usage_events" ("time_entry_id");

ALTER TABLE "billing"."usage_events" ADD CONSTRAINT "c_f19be34ffa0197bc53be" FOREIGN KEY ("intervention_id") REFERENCES "itsm"."interventions"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_15fd4d25f07d6a28a7e6" ON "billing"."usage_events" ("intervention_id");

ALTER TABLE "billing"."usage_events" ADD CONSTRAINT "c_dd6199d07143ed779f8b" FOREIGN KEY ("expense_id") REFERENCES "billing"."expenses"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_643f30d00b2b93af0a86" ON "billing"."usage_events" ("expense_id");

ALTER TABLE "billing"."usage_events" ADD CONSTRAINT "c_5872570f849d23190bcf" FOREIGN KEY ("component_id") REFERENCES "commercial"."contract_components"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_52c0615fef540f5e1294" ON "billing"."usage_events" ("component_id");

ALTER TABLE "billing"."valuation_runs" ADD CONSTRAINT "c_201a61a81ad0729b6295" FOREIGN KEY ("customer_org_id") REFERENCES "core"."organizations"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_c48a2fc97036201fb9bc" ON "billing"."valuation_runs" ("customer_org_id");

ALTER TABLE "billing"."valuation_runs" ADD CONSTRAINT "c_1a83db251c97ec82e9c3" FOREIGN KEY ("contract_id") REFERENCES "commercial"."contracts"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_d747e14cccfbec327b96" ON "billing"."valuation_runs" ("contract_id");

ALTER TABLE "billing"."valuation_lines" ADD CONSTRAINT "c_c0509bacd0b4d3c29d4d" FOREIGN KEY ("run_id") REFERENCES "billing"."valuation_runs"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_33c4b7b41cc3aa1a7a8f" ON "billing"."valuation_lines" ("run_id");

ALTER TABLE "billing"."valuation_lines" ADD CONSTRAINT "c_1db3438cd062df127916" FOREIGN KEY ("usage_event_id") REFERENCES "billing"."usage_events"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_580c824de4f1e2ac2b9b" ON "billing"."valuation_lines" ("usage_event_id");

ALTER TABLE "billing"."valuation_lines" ADD CONSTRAINT "c_025281b810e873257701" FOREIGN KEY ("component_id") REFERENCES "commercial"."contract_components"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_37806f509b0a3d6891d8" ON "billing"."valuation_lines" ("component_id");

ALTER TABLE "billing"."activity_statements" ADD CONSTRAINT "c_cf46922b696a1406ed21" FOREIGN KEY ("customer_org_id") REFERENCES "core"."organizations"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_c9863d43ba32b51fbd31" ON "billing"."activity_statements" ("customer_org_id");

ALTER TABLE "billing"."activity_statements" ADD CONSTRAINT "c_e553e62cca0bfefeddae" FOREIGN KEY ("contract_id") REFERENCES "commercial"."contracts"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_a8bb89d6bbd56c42cbbe" ON "billing"."activity_statements" ("contract_id");

ALTER TABLE "billing"."activity_statements" ADD CONSTRAINT "c_c18dd133c700daa1dc08" FOREIGN KEY ("approved_by") REFERENCES "iam"."principals"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_cfef2cd76d5ff5d41c27" ON "billing"."activity_statements" ("approved_by");

ALTER TABLE "billing"."statement_lines" ADD CONSTRAINT "c_4a1ba9125685042860c6" FOREIGN KEY ("statement_id") REFERENCES "billing"."activity_statements"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_764f1d4e3d2d7734fbd5" ON "billing"."statement_lines" ("statement_id");

ALTER TABLE "billing"."statement_lines" ADD CONSTRAINT "c_cf6b8a35da774ce3877a" FOREIGN KEY ("valuation_line_id") REFERENCES "billing"."valuation_lines"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_21c8a2480c1cc013a83f" ON "billing"."statement_lines" ("valuation_line_id");

ALTER TABLE "billing"."statement_exports" ADD CONSTRAINT "c_60840e278df547b271b8" FOREIGN KEY ("statement_id") REFERENCES "billing"."activity_statements"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_8d164ef0e20ec18a322a" ON "billing"."statement_exports" ("statement_id");

ALTER TABLE "billing"."statement_exports" ADD CONSTRAINT "c_7ad4cbdc45107911b149" FOREIGN KEY ("file_id") REFERENCES "docs"."files"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_8d515b78e90f6a265ef5" ON "billing"."statement_exports" ("file_id");

ALTER TABLE "billing"."statement_exports" ADD CONSTRAINT "c_2e4e2ed48253a00ff1ea" FOREIGN KEY ("exported_by") REFERENCES "iam"."principals"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_9f5eaafa7e9eb9c3f177" ON "billing"."statement_exports" ("exported_by");

ALTER TABLE "billing"."invoice_reconciliations" ADD CONSTRAINT "c_4fb0f8c91a47ad1540da" FOREIGN KEY ("statement_line_id") REFERENCES "billing"."statement_lines"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_44d84134b57ee6a2801e" ON "billing"."invoice_reconciliations" ("statement_line_id");

ALTER TABLE "knowledge"."spaces" ADD CONSTRAINT "c_bb8e76dfa12fda8f1b01" FOREIGN KEY ("owner_team_id") REFERENCES "core"."teams"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_28ebda20942d945f2c39" ON "knowledge"."spaces" ("owner_team_id");

ALTER TABLE "knowledge"."articles" ADD CONSTRAINT "c_307d11378873989dc94c" FOREIGN KEY ("space_id") REFERENCES "knowledge"."spaces"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_dd3aa5be428bae7deabf" ON "knowledge"."articles" ("space_id");

ALTER TABLE "knowledge"."articles" ADD CONSTRAINT "c_f2b2df4308519cec4063" FOREIGN KEY ("owner_id") REFERENCES "iam"."principals"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_d8fe7c6c30c0daa8d6fb" ON "knowledge"."articles" ("owner_id");

ALTER TABLE "knowledge"."article_versions" ADD CONSTRAINT "c_a4d6e0fbca943b15da06" FOREIGN KEY ("article_id") REFERENCES "knowledge"."articles"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_33d528e8ec2bf794d46f" ON "knowledge"."article_versions" ("article_id");

ALTER TABLE "knowledge"."article_versions" ADD CONSTRAINT "c_7b18535a4226e79ecacc" FOREIGN KEY ("author_id") REFERENCES "iam"."principals"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_ba08e04602ae133d28b4" ON "knowledge"."article_versions" ("author_id");

ALTER TABLE "knowledge"."article_versions" ADD CONSTRAINT "c_2e5688806a12a6fa97e5" FOREIGN KEY ("approved_by") REFERENCES "iam"."principals"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_75e04a3912f3164c434c" ON "knowledge"."article_versions" ("approved_by");

ALTER TABLE "knowledge"."article_links" ADD CONSTRAINT "c_433338e8697a3e47ac04" FOREIGN KEY ("article_id") REFERENCES "knowledge"."articles"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_dd613e167770a2ab3da1" ON "knowledge"."article_links" ("article_id");

ALTER TABLE "knowledge"."article_links" ADD CONSTRAINT "c_eae39f8e0fbe7a8c12e3" FOREIGN KEY ("ticket_id") REFERENCES "itsm"."tickets"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_9c2f6f5cd64b818b4ad5" ON "knowledge"."article_links" ("ticket_id");

ALTER TABLE "knowledge"."article_feedback" ADD CONSTRAINT "c_08e21eecad46de181b75" FOREIGN KEY ("article_id") REFERENCES "knowledge"."articles"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_7c9fe27dc6cc7e47994d" ON "knowledge"."article_feedback" ("article_id");

ALTER TABLE "knowledge"."article_feedback" ADD CONSTRAINT "c_397227efc63dd5d4b9ec" FOREIGN KEY ("principal_id") REFERENCES "iam"."principals"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_cd7d05ba6acd21f9fb1b" ON "knowledge"."article_feedback" ("principal_id");

ALTER TABLE "docs"."files" ADD CONSTRAINT "c_396bf4d114b6af07c60c" FOREIGN KEY ("uploaded_by") REFERENCES "iam"."principals"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_c3a4f473e58750cd766c" ON "docs"."files" ("uploaded_by");

ALTER TABLE "docs"."documents" ADD CONSTRAINT "c_1bebd379a652f173a74c" FOREIGN KEY ("owner_id") REFERENCES "iam"."principals"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_5cef5e57c724fea6be53" ON "docs"."documents" ("owner_id");

ALTER TABLE "docs"."document_versions" ADD CONSTRAINT "c_f8968d0f2fc4c40a759e" FOREIGN KEY ("document_id") REFERENCES "docs"."documents"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_7bf51d658b851f55d4a1" ON "docs"."document_versions" ("document_id");

ALTER TABLE "docs"."document_versions" ADD CONSTRAINT "c_294cf9e0e970cf1313f2" FOREIGN KEY ("file_id") REFERENCES "docs"."files"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_a5503e6efa8c9155af48" ON "docs"."document_versions" ("file_id");

ALTER TABLE "docs"."document_versions" ADD CONSTRAINT "c_7434ae063ee822585510" FOREIGN KEY ("authored_by") REFERENCES "iam"."principals"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_8c938c405701adb89618" ON "docs"."document_versions" ("authored_by");

ALTER TABLE "docs"."ticket_attachments" ADD CONSTRAINT "c_0fd16389dc135bbf9be4" FOREIGN KEY ("ticket_id") REFERENCES "itsm"."tickets"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_ca17bab881d1e862e86c" ON "docs"."ticket_attachments" ("ticket_id");

ALTER TABLE "docs"."ticket_attachments" ADD CONSTRAINT "c_8b4cd3e7bc35594b6bbe" FOREIGN KEY ("message_id") REFERENCES "itsm"."ticket_messages"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_032a43aad74456f454f4" ON "docs"."ticket_attachments" ("message_id");

ALTER TABLE "docs"."ticket_attachments" ADD CONSTRAINT "c_a0ebf9a2fc85a1e528f7" FOREIGN KEY ("file_id") REFERENCES "docs"."files"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_b6b41e2e5e2ec3d83a1b" ON "docs"."ticket_attachments" ("file_id");

ALTER TABLE "docs"."project_documents" ADD CONSTRAINT "c_df731dfdffb69d38bfd7" FOREIGN KEY ("project_id") REFERENCES "project"."projects"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_48a13019fd4368d514fb" ON "docs"."project_documents" ("project_id");

ALTER TABLE "docs"."project_documents" ADD CONSTRAINT "c_0d5204cc8a13a5068dd6" FOREIGN KEY ("document_id") REFERENCES "docs"."documents"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_3230f4e77bff7f3e7640" ON "docs"."project_documents" ("document_id");

ALTER TABLE "docs"."item_documents" ADD CONSTRAINT "c_c7853183218470cc7dcf" FOREIGN KEY ("item_id") REFERENCES "cmdb"."items"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_28efd1e0b3c2bf2a7a3c" ON "docs"."item_documents" ("item_id");

ALTER TABLE "docs"."item_documents" ADD CONSTRAINT "c_79b59a34cdb35acd1046" FOREIGN KEY ("document_id") REFERENCES "docs"."documents"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_280616757522d226ea01" ON "docs"."item_documents" ("document_id");

ALTER TABLE "docs"."document_access_events" ADD CONSTRAINT "c_d89e743205f28eceaac2" FOREIGN KEY ("file_id") REFERENCES "docs"."files"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_6ab729f65fe49fd79aba" ON "docs"."document_access_events" ("file_id");

ALTER TABLE "docs"."document_access_events" ADD CONSTRAINT "c_a0f0028bea93edd89517" FOREIGN KEY ("principal_id") REFERENCES "iam"."principals"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_6476dbfcc163bd5f16ce" ON "docs"."document_access_events" ("principal_id");

ALTER TABLE "comms"."mailboxes" ADD CONSTRAINT "c_bde70771619ec46cc930" FOREIGN KEY ("connection_id") REFERENCES "integration"."connections"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_e9e478a4ae5218b286fb" ON "comms"."mailboxes" ("connection_id");

ALTER TABLE "comms"."mailboxes" ADD CONSTRAINT "c_d8208679af41c5b7ce6c" FOREIGN KEY ("default_team_id") REFERENCES "core"."teams"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_be2ca0ced3daa3e4188f" ON "comms"."mailboxes" ("default_team_id");

ALTER TABLE "comms"."inbound_messages" ADD CONSTRAINT "c_3ffae7f140c57054a135" FOREIGN KEY ("mailbox_id") REFERENCES "comms"."mailboxes"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_86ca9b9cd6f978e66872" ON "comms"."inbound_messages" ("mailbox_id");

ALTER TABLE "comms"."inbound_messages" ADD CONSTRAINT "c_a087c288db2a76f0d94a" FOREIGN KEY ("ticket_id") REFERENCES "itsm"."tickets"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_8088b05809bebe07e670" ON "comms"."inbound_messages" ("ticket_id");

ALTER TABLE "comms"."inbound_messages" ADD CONSTRAINT "c_03829c3096658eaa0437" FOREIGN KEY ("raw_file_id") REFERENCES "docs"."files"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_caf828230710dbae705d" ON "comms"."inbound_messages" ("raw_file_id");

ALTER TABLE "comms"."outbound_messages" ADD CONSTRAINT "c_0ebb574111bd2c9e2763" FOREIGN KEY ("ticket_message_id") REFERENCES "itsm"."ticket_messages"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_6939a95e67eb076fb3e7" ON "comms"."outbound_messages" ("ticket_message_id");

ALTER TABLE "comms"."delivery_attempts" ADD CONSTRAINT "c_06f7f5d3e896c2a5c453" FOREIGN KEY ("outbound_id") REFERENCES "comms"."outbound_messages"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_60415ce16c904ff3e7e0" ON "comms"."delivery_attempts" ("outbound_id");

ALTER TABLE "comms"."notifications" ADD CONSTRAINT "c_ff32d69ce68204288711" FOREIGN KEY ("principal_id") REFERENCES "iam"."principals"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_86336df94767a26c52ec" ON "comms"."notifications" ("principal_id");

ALTER TABLE "comms"."survey_invitations" ADD CONSTRAINT "c_56ee4be496dfd775a365" FOREIGN KEY ("survey_id") REFERENCES "comms"."surveys"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_2d295f08ce7285bf9569" ON "comms"."survey_invitations" ("survey_id");

ALTER TABLE "comms"."survey_invitations" ADD CONSTRAINT "c_d8f788f03ee3085b5fa3" FOREIGN KEY ("ticket_id") REFERENCES "itsm"."tickets"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_c4e77d7d231e8d8055ee" ON "comms"."survey_invitations" ("ticket_id");

ALTER TABLE "comms"."survey_invitations" ADD CONSTRAINT "c_408bef96f5f5241e22a9" FOREIGN KEY ("person_id") REFERENCES "core"."persons"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_c949d675320705fdd15a" ON "comms"."survey_invitations" ("person_id");

ALTER TABLE "comms"."survey_answers" ADD CONSTRAINT "c_107b4605851ec663af0b" FOREIGN KEY ("invitation_id") REFERENCES "comms"."survey_invitations"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_882d8fe3a3ab9ff50d02" ON "comms"."survey_answers" ("invitation_id");

ALTER TABLE "integration"."external_mappings" ADD CONSTRAINT "c_2cf3233580d6336d5517" FOREIGN KEY ("connection_id") REFERENCES "integration"."connections"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_52ea4b03d612738d9f20" ON "integration"."external_mappings" ("connection_id");

ALTER TABLE "integration"."sync_runs" ADD CONSTRAINT "c_7016fe315d24a05235e2" FOREIGN KEY ("connection_id") REFERENCES "integration"."connections"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_fbff802034c09623b747" ON "integration"."sync_runs" ("connection_id");

ALTER TABLE "integration"."sync_conflicts" ADD CONSTRAINT "c_7001562a7ad0a6c54090" FOREIGN KEY ("run_id") REFERENCES "integration"."sync_runs"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_ae6e1aa2ccc384537197" ON "integration"."sync_conflicts" ("run_id");

ALTER TABLE "integration"."sync_conflicts" ADD CONSTRAINT "c_e1a6bf7661c12a52b999" FOREIGN KEY ("mapping_id") REFERENCES "integration"."external_mappings"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_3389bc2224fd7e43437d" ON "integration"."sync_conflicts" ("mapping_id");

ALTER TABLE "integration"."sync_conflicts" ADD CONSTRAINT "c_7636f386881c7ca3241b" FOREIGN KEY ("resolved_by") REFERENCES "iam"."principals"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_8f5bccdd56005efdeb64" ON "integration"."sync_conflicts" ("resolved_by");

ALTER TABLE "integration"."inbox_events" ADD CONSTRAINT "c_c0c0c390521590729408" FOREIGN KEY ("connection_id") REFERENCES "integration"."connections"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_ef12d8213db3c8560b18" ON "integration"."inbox_events" ("connection_id");

ALTER TABLE "integration"."webhook_subscriptions" ADD CONSTRAINT "c_03cdc1da04aa2d751cba" FOREIGN KEY ("connection_id") REFERENCES "integration"."connections"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_82c777dbaf22cc841eea" ON "integration"."webhook_subscriptions" ("connection_id");

ALTER TABLE "integration"."webhook_deliveries" ADD CONSTRAINT "c_25941f70ab8288e324be" FOREIGN KEY ("subscription_id") REFERENCES "integration"."webhook_subscriptions"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_cf6a34928bf66f3cb071" ON "integration"."webhook_deliveries" ("subscription_id");

ALTER TABLE "integration"."webhook_deliveries" ADD CONSTRAINT "c_1a43d9717677334485cd" FOREIGN KEY ("outbox_event_id") REFERENCES "integration"."outbox_events"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_8f39a42f3affec3984be" ON "integration"."webhook_deliveries" ("outbox_event_id");

ALTER TABLE "integration"."monitor_alerts" ADD CONSTRAINT "c_da899e2d1596e1317aee" FOREIGN KEY ("connection_id") REFERENCES "integration"."connections"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_a77a55baa6b2d0f12e5a" ON "integration"."monitor_alerts" ("connection_id");

ALTER TABLE "integration"."monitor_alerts" ADD CONSTRAINT "c_c67dd1d093e33ea9ba88" FOREIGN KEY ("item_id") REFERENCES "cmdb"."items"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_ce6007ad30888ca95d17" ON "integration"."monitor_alerts" ("item_id");

ALTER TABLE "integration"."monitor_alerts" ADD CONSTRAINT "c_f9deb567418a6b9b5019" FOREIGN KEY ("ticket_id") REFERENCES "itsm"."tickets"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_4afe12365aabc9ba380a" ON "integration"."monitor_alerts" ("ticket_id");

ALTER TABLE "integration"."import_jobs" ADD CONSTRAINT "c_593336a65e8257f8c189" FOREIGN KEY ("file_id") REFERENCES "docs"."files"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_3d24ffd8a1f0626f4a62" ON "integration"."import_jobs" ("file_id");

ALTER TABLE "integration"."import_rows" ADD CONSTRAINT "c_c8b9271594ad2a3a7dba" FOREIGN KEY ("job_id") REFERENCES "integration"."import_jobs"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_d4a4809679137726f923" ON "integration"."import_rows" ("job_id");

ALTER TABLE "reporting"."report_runs" ADD CONSTRAINT "c_8671f202718d6278baf2" FOREIGN KEY ("definition_id") REFERENCES "reporting"."report_definitions"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_c731fbd1f26b69e9148f" ON "reporting"."report_runs" ("definition_id");

ALTER TABLE "reporting"."report_runs" ADD CONSTRAINT "c_385665ddf7ccd82dda7e" FOREIGN KEY ("requested_by") REFERENCES "iam"."principals"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_56b066a000b0832688cc" ON "reporting"."report_runs" ("requested_by");

ALTER TABLE "reporting"."report_files" ADD CONSTRAINT "c_2783e448ae7476dc1641" FOREIGN KEY ("run_id") REFERENCES "reporting"."report_runs"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_ca2e22fb24e5b986998f" ON "reporting"."report_files" ("run_id");

ALTER TABLE "reporting"."report_files" ADD CONSTRAINT "c_0a0d437cc08a267ab2c1" FOREIGN KEY ("file_id") REFERENCES "docs"."files"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_99465450d7bad10c777a" ON "reporting"."report_files" ("file_id");

ALTER TABLE "reporting"."report_schedules" ADD CONSTRAINT "c_7d1458f16b411ed9a190" FOREIGN KEY ("definition_id") REFERENCES "reporting"."report_definitions"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_182f6cae06ecde5473b6" ON "reporting"."report_schedules" ("definition_id");

ALTER TABLE "reporting"."report_schedules" ADD CONSTRAINT "c_09f51931761476f9741b" FOREIGN KEY ("owner_id") REFERENCES "iam"."principals"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_ddca637f82c065de4897" ON "reporting"."report_schedules" ("owner_id");

ALTER TABLE "reporting"."dashboard_layouts" ADD CONSTRAINT "c_01177b23bd128105ad10" FOREIGN KEY ("principal_id") REFERENCES "iam"."principals"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_537d0118cd099726eb76" ON "reporting"."dashboard_layouts" ("principal_id");

ALTER TABLE "reporting"."daily_support_facts" ADD CONSTRAINT "c_1e7a1f38467e1a18d26b" FOREIGN KEY ("customer_org_id") REFERENCES "core"."organizations"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_4f4fbe89e8cfc5bd5a66" ON "reporting"."daily_support_facts" ("customer_org_id");

ALTER TABLE "reporting"."daily_support_facts" ADD CONSTRAINT "c_2de40e78bbabed4f5916" FOREIGN KEY ("team_id") REFERENCES "core"."teams"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_bba9874ac0a4eae7ca52" ON "reporting"."daily_support_facts" ("team_id");

ALTER TABLE "governance"."audit_events" ADD CONSTRAINT "c_e552d7349f20a318d63d" FOREIGN KEY ("actor_id") REFERENCES "iam"."principals"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_cd04c6ff33aa124a1af1" ON "governance"."audit_events" ("actor_id");

ALTER TABLE "governance"."field_values" ADD CONSTRAINT "c_01a1f07a0a8e1589f2a6" FOREIGN KEY ("definition_id") REFERENCES "governance"."field_definitions"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_5ac4baedb2754ed950f2" ON "governance"."field_values" ("definition_id");

ALTER TABLE "governance"."legal_holds" ADD CONSTRAINT "c_4755f729a24614897919" FOREIGN KEY ("authorized_by") REFERENCES "iam"."principals"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_9dddb82128836112ae61" ON "governance"."legal_holds" ("authorized_by");

ALTER TABLE "governance"."data_requests" ADD CONSTRAINT "c_703a23e7616e32e0fab7" FOREIGN KEY ("requester_person_id") REFERENCES "core"."persons"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_32601e6893735eb45a59" ON "governance"."data_requests" ("requester_person_id");

ALTER TABLE "governance"."purge_runs" ADD CONSTRAINT "c_73ac448b56ce321f61a4" FOREIGN KEY ("policy_id") REFERENCES "governance"."retention_policies"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_3df2055dbabb3baa1366" ON "governance"."purge_runs" ("policy_id");

ALTER TABLE "governance"."idempotency_keys" ADD CONSTRAINT "c_5ed00f30c0efb8b49314" FOREIGN KEY ("principal_id") REFERENCES "iam"."principals"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_fe3961424b69b6c9e08c" ON "governance"."idempotency_keys" ("principal_id");

ALTER TABLE "governance"."legacy_ids" ADD CONSTRAINT "c_0701f831d872740ac49f" FOREIGN KEY ("import_job_id") REFERENCES "integration"."import_jobs"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_a825e24be73aa9a240c0" ON "governance"."legacy_ids" ("import_job_id");

ALTER TABLE "core"."locations" ADD CONSTRAINT "c_f4b95bd9774061dcd019" UNIQUE ("id", "site_id");

ALTER TABLE "core"."locations" ADD CONSTRAINT "c_6d9cc69b17128d3f63a9" FOREIGN KEY ("parent_id", "site_id") REFERENCES "core"."locations" ("id", "site_id") DEFERRABLE INITIALLY IMMEDIATE;

ALTER TABLE "core"."sites" ADD CONSTRAINT "c_f2042de12eaab4e0f22f" UNIQUE ("id", "organization_id");

ALTER TABLE "core"."affiliations" ADD CONSTRAINT "c_94ed2aa724ce74661d82" FOREIGN KEY ("site_id", "organization_id") REFERENCES "core"."sites" ("id", "organization_id") DEFERRABLE INITIALLY IMMEDIATE;

ALTER TABLE "core"."teams" ADD CONSTRAINT "c_f59cb621067cd00ad83b" UNIQUE ("id", "organization_id");

ALTER TABLE "core"."teams" ADD CONSTRAINT "c_fbda1a31a727c3f17c17" FOREIGN KEY ("parent_id", "organization_id") REFERENCES "core"."teams" ("id", "organization_id") DEFERRABLE INITIALLY IMMEDIATE;

ALTER TABLE "crm"."stages" ADD CONSTRAINT "c_0066a8f832f17a467506" UNIQUE ("id", "pipeline_id");

ALTER TABLE "crm"."opportunities" ADD CONSTRAINT "c_5e2ca09ce695668d53a6" FOREIGN KEY ("stage_id", "pipeline_id") REFERENCES "crm"."stages" ("id", "pipeline_id") DEFERRABLE INITIALLY IMMEDIATE;

ALTER TABLE "web"."page_revisions" ADD CONSTRAINT "c_a58db91900ef724dd925" UNIQUE ("id", "page_id");

ALTER TABLE "web"."pages" ADD CONSTRAINT "c_0c961dfd1b52d6cf5721" FOREIGN KEY ("published_revision_id", "id") REFERENCES "web"."page_revisions" ("id", "page_id") DEFERRABLE INITIALLY IMMEDIATE;

ALTER TABLE "project"."project_parties" ADD CONSTRAINT "c_09723f44249a57192d28" FOREIGN KEY ("site_id", "organization_id") REFERENCES "core"."sites" ("id", "organization_id") DEFERRABLE INITIALLY IMMEDIATE;

ALTER TABLE "project"."phases" ADD CONSTRAINT "c_41b68833ea265a219890" UNIQUE ("id", "project_id");

ALTER TABLE "project"."milestones" ADD CONSTRAINT "c_f8d65c467bc97c7a2229" FOREIGN KEY ("phase_id", "project_id") REFERENCES "project"."phases" ("id", "project_id") DEFERRABLE INITIALLY IMMEDIATE;

ALTER TABLE "project"."tasks" ADD CONSTRAINT "c_f18665b3d677141266ca" FOREIGN KEY ("phase_id", "project_id") REFERENCES "project"."phases" ("id", "project_id") DEFERRABLE INITIALLY IMMEDIATE;

ALTER TABLE "project"."tasks" ADD CONSTRAINT "c_97cf3266683c374830cf" UNIQUE ("id", "project_id");

ALTER TABLE "project"."tasks" ADD CONSTRAINT "c_fe5e84b5339cf87f8feb" FOREIGN KEY ("parent_id", "project_id") REFERENCES "project"."tasks" ("id", "project_id") DEFERRABLE INITIALLY IMMEDIATE;

ALTER TABLE "project"."resource_demands" ADD CONSTRAINT "c_5ef2c4c51d4b4a1a8217" FOREIGN KEY ("task_id", "project_id") REFERENCES "project"."tasks" ("id", "project_id") DEFERRABLE INITIALLY IMMEDIATE;

ALTER TABLE "project"."milestones" ADD CONSTRAINT "c_86376804c5ea07e1303b" UNIQUE ("id", "project_id");

ALTER TABLE "project"."deliverables" ADD CONSTRAINT "c_19748f080c95fd5a4a5c" FOREIGN KEY ("milestone_id", "project_id") REFERENCES "project"."milestones" ("id", "project_id") DEFERRABLE INITIALLY IMMEDIATE;

ALTER TABLE "itsm"."tickets" ADD CONSTRAINT "c_9f66625edad91aa80f68" FOREIGN KEY ("site_id", "customer_org_id") REFERENCES "core"."sites" ("id", "organization_id") DEFERRABLE INITIALLY IMMEDIATE;

ALTER TABLE "core"."affiliations" ADD CONSTRAINT "c_0117a9eada7eca1edc1f" UNIQUE ("id", "organization_id");

ALTER TABLE "itsm"."tickets" ADD CONSTRAINT "c_ab548d2e85b50bc664c1" FOREIGN KEY ("requester_affiliation_id", "customer_org_id") REFERENCES "core"."affiliations" ("id", "organization_id") DEFERRABLE INITIALLY IMMEDIATE;

ALTER TABLE "itsm"."tickets" ADD CONSTRAINT "c_09435db25db366319e14" FOREIGN KEY ("beneficiary_affiliation_id", "customer_org_id") REFERENCES "core"."affiliations" ("id", "organization_id") DEFERRABLE INITIALLY IMMEDIATE;

ALTER TABLE "itsm"."tickets" ADD CONSTRAINT "c_ede6a16b5f511e191431" UNIQUE ("id", "customer_org_id");

ALTER TABLE "itsm"."tickets" ADD CONSTRAINT "c_bbddd5e5db6c3a1bd238" FOREIGN KEY ("parent_id", "customer_org_id") REFERENCES "itsm"."tickets" ("id", "customer_org_id") DEFERRABLE INITIALLY IMMEDIATE;

ALTER TABLE "itsm"."ticket_messages" ADD CONSTRAINT "c_8668741ca46e653d6483" UNIQUE ("id", "ticket_id");

ALTER TABLE "itsm"."waiting_periods" ADD CONSTRAINT "c_b3db85d860c87172216f" FOREIGN KEY ("question_message_id", "ticket_id") REFERENCES "itsm"."ticket_messages" ("id", "ticket_id") DEFERRABLE INITIALLY IMMEDIATE;

ALTER TABLE "workflow"."steps" ADD CONSTRAINT "c_0e652fd43048ffa6135c" UNIQUE ("id", "version_id");

ALTER TABLE "workflow"."edges" ADD CONSTRAINT "c_1acf5d2cec6203bb0be3" FOREIGN KEY ("from_step_id", "version_id") REFERENCES "workflow"."steps" ("id", "version_id") DEFERRABLE INITIALLY IMMEDIATE;

ALTER TABLE "workflow"."edges" ADD CONSTRAINT "c_a6f13ea6a738981f3546" FOREIGN KEY ("to_step_id", "version_id") REFERENCES "workflow"."steps" ("id", "version_id") DEFERRABLE INITIALLY IMMEDIATE;

ALTER TABLE "cmdb"."items" ADD CONSTRAINT "c_8e01f641c201d93bb862" FOREIGN KEY ("location_id", "site_id") REFERENCES "core"."locations" ("id", "site_id") DEFERRABLE INITIALLY IMMEDIATE;

ALTER TABLE "cmdb"."network_segments" ADD CONSTRAINT "c_06bd928dd95b77944494" FOREIGN KEY ("site_id", "owner_org_id") REFERENCES "core"."sites" ("id", "organization_id") DEFERRABLE INITIALLY IMMEDIATE;

ALTER TABLE "commercial"."contract_scopes" ADD CONSTRAINT "c_58d7985ded1c92675163" FOREIGN KEY ("site_id", "organization_id") REFERENCES "core"."sites" ("id", "organization_id") DEFERRABLE INITIALLY IMMEDIATE;

ALTER TABLE "itsm"."interventions" ADD CONSTRAINT "c_64dfe78c2d53058a0757" UNIQUE ("id", "ticket_id");

ALTER TABLE "billing"."time_entries" ADD CONSTRAINT "c_ba85e9d17551de5681f1" FOREIGN KEY ("intervention_id", "ticket_id") REFERENCES "itsm"."interventions" ("id", "ticket_id") DEFERRABLE INITIALLY IMMEDIATE;

ALTER TABLE "docs"."ticket_attachments" ADD CONSTRAINT "c_50af24e8b95078313884" FOREIGN KEY ("message_id", "ticket_id") REFERENCES "itsm"."ticket_messages" ("id", "ticket_id") DEFERRABLE INITIALLY IMMEDIATE;

CREATE TRIGGER b_no_cycle BEFORE INSERT OR UPDATE OF parent_id ON "core"."locations" FOR EACH ROW EXECUTE FUNCTION infrastructure.prevent_tree_cycle('parent_id');

CREATE TRIGGER b_no_cycle BEFORE INSERT OR UPDATE OF parent_id ON "core"."teams" FOR EACH ROW EXECUTE FUNCTION infrastructure.prevent_tree_cycle('parent_id');

CREATE TRIGGER b_no_cycle BEFORE INSERT OR UPDATE OF parent_id ON "project"."tasks" FOR EACH ROW EXECUTE FUNCTION infrastructure.prevent_tree_cycle('parent_id');

CREATE TRIGGER b_no_cycle BEFORE INSERT OR UPDATE OF parent_id ON "itsm"."categories" FOR EACH ROW EXECUTE FUNCTION infrastructure.prevent_tree_cycle('parent_id');

CREATE TRIGGER b_no_cycle BEFORE INSERT OR UPDATE OF parent_id ON "itsm"."tickets" FOR EACH ROW EXECUTE FUNCTION infrastructure.prevent_tree_cycle('parent_id');

-- Reference data only: no client, user or application data are imported.
CREATE UNIQUE INDEX installation_singleton ON core.installation ((true));
INSERT INTO core.installation(environment,timezone,locale,schema_version)
VALUES ('local','Europe/Paris','fr-FR','20261010_001');

INSERT INTO iam.applications(code,name,audience,enabled) VALUES
 ('CRM','GENESIS','genesis-api',true),('ITSM','ORBIT','orbit-api',true),
 ('PROJECT','Projets','project-api',false),('PEOPLE','Collaborateurs','people-api',false),
 ('COMMERCIAL','Commercial','commercial-api',false),('WEB','Vitrine','web-api',false);
INSERT INTO iam.roles(code,label,system_role) VALUES
 ('business_admin','Administration métier',true),('sales','Commercial',true),
 ('technician','Technicien',true),('collaborator','Collaborateur',true),('customer','Client',true);
INSERT INTO iam.permissions(application_id,resource_type,action,code)
SELECT a.id,'module',act,a.code||'.'||act FROM iam.applications a
CROSS JOIN unnest(ARRAY['read','create','update','delete','export','approve','administer']) act;
INSERT INTO itsm.ticket_types(code,label,class,active) VALUES
 ('incident','Incident','incident',true),('request','Demande','request',true),
 ('problem','Problème','problem',true),('change','Changement','change',true);
INSERT INTO itsm.statuses(code,label,state_class,is_terminal,portal_label) VALUES
 ('new','Nouveau','open',false,'Nouveau'),('triaged','Qualifié','open',false,'Qualifié'),
 ('assigned','Affecté','open',false,'Affecté'),('in_progress','En cours','active',false,'En cours'),
 ('waiting_customer','En attente client','waiting',false,'Votre réponse est attendue'),
 ('waiting_supplier','En attente fournisseur','waiting',false,'En attente'),
 ('waiting_internal','En attente interne','waiting',false,'En attente'),
 ('resolved','Résolu, à valider','resolved',false,'Résolution à valider'),
 ('closed','Clos','closed',true,'Clos'),('reopened','Réouvert','active',false,'Réouvert'),
 ('cancelled','Annulé','cancelled',true,'Annulé'),('duplicate','Doublon','duplicate',true,'Doublon');

ALTER TABLE itsm.priority_matrix ADD CONSTRAINT priority_context UNIQUE(impact,urgency,priority_code);
ALTER TABLE itsm.tickets ADD CONSTRAINT ticket_priority FOREIGN KEY(impact,urgency,priority_code)
 REFERENCES itsm.priority_matrix(impact,urgency,priority_code);

-- Scope columns added to the logical model let PostgreSQL enforce both parents.
ALTER TABLE workflow.step_runs ADD COLUMN version_id uuid NOT NULL;
ALTER TABLE workflow.instances ADD CONSTRAINT instance_version UNIQUE(id,version_id);
ALTER TABLE workflow.steps ADD CONSTRAINT step_version UNIQUE(id,version_id);
ALTER TABLE workflow.step_runs ADD CONSTRAINT run_instance_version FOREIGN KEY(instance_id,version_id) REFERENCES workflow.instances(id,version_id);
ALTER TABLE workflow.step_runs ADD CONSTRAINT run_step_version FOREIGN KEY(step_id,version_id) REFERENCES workflow.steps(id,version_id);
ALTER TABLE inventory.receipt_lines ADD COLUMN order_id uuid NOT NULL;
ALTER TABLE inventory.receipts ADD CONSTRAINT receipt_order UNIQUE(id,order_id);
ALTER TABLE inventory.purchase_lines ADD CONSTRAINT line_order UNIQUE(id,order_id);
ALTER TABLE inventory.receipt_lines ADD CONSTRAINT receipt_line_order FOREIGN KEY(receipt_id,order_id) REFERENCES inventory.receipts(id,order_id);
ALTER TABLE inventory.receipt_lines ADD CONSTRAINT purchase_line_order FOREIGN KEY(purchase_line_id,order_id) REFERENCES inventory.purchase_lines(id,order_id);

-- Half-open periods: touching intervals do not overlap.
ALTER TABLE schedule.bookings ADD CONSTRAINT no_exclusive_overlap
 EXCLUDE USING gist(resource_id WITH =,tstzrange(starts_at,ends_at,'[)') WITH &&)
 WHERE(exclusive AND status='confirmed');
ALTER TABLE people.employment_patterns ADD CONSTRAINT no_pattern_overlap
 EXCLUDE USING gist(employment_id WITH =,daterange(valid_from,valid_to,'[)') WITH &&);
ALTER TABLE cmdb.ownership_history ADD CONSTRAINT no_owner_overlap
 EXCLUDE USING gist(item_id WITH =,tstzrange(starts_at,ends_at,'[)') WITH &&);
ALTER TABLE itsm.assignment_history ADD CONSTRAINT no_assignment_overlap
 EXCLUDE USING gist(ticket_id WITH =,tstzrange(starts_at,ends_at,'[)') WITH &&);
ALTER TABLE service.sla_pauses ADD CONSTRAINT no_pause_overlap
 EXCLUDE USING gist(instance_id WITH =,tstzrange(starts_at,ends_at,'[)') WITH &&);
ALTER TABLE cmdb.ip_assignments ADD CONSTRAINT no_ip_overlap
 EXCLUDE USING gist(segment_id WITH =,address WITH =,tstzrange(starts_at,ends_at,'[)') WITH &&);
CREATE UNIQUE INDEX one_pending_resolution ON itsm.resolutions(ticket_id) WHERE status='pending';
CREATE UNIQUE INDEX one_active_wait ON itsm.waiting_periods(ticket_id,reason_id) WHERE ended_at IS NULL;
CREATE UNIQUE INDEX one_active_membership ON core.team_memberships(team_id,person_id,role_code) WHERE valid_to IS NULL;
CREATE UNIQUE INDEX unique_network_link ON cmdb.network_links
 (least(from_interface_id,to_interface_id),greatest(from_interface_id,to_interface_id),kind);
CREATE UNIQUE INDEX unique_time_usage ON billing.usage_events(time_entry_id) WHERE time_entry_id IS NOT NULL;
CREATE UNIQUE INDEX unique_expense_usage ON billing.usage_events(expense_id) WHERE expense_id IS NOT NULL;
CREATE UNIQUE INDEX unique_external_invoice_source ON commercial.invoice_lines(source_statement_line_key) WHERE source_statement_line_key IS NOT NULL;
CREATE UNIQUE INDEX unique_provider_message ON itsm.ticket_messages(channel,external_message_key) WHERE external_message_key IS NOT NULL;
CREATE UNIQUE INDEX unique_availability_source ON schedule.availability_blocks(resource_id,source_system,external_source_key) WHERE external_source_key IS NOT NULL;

CREATE FUNCTION infrastructure.prevent_edge_cycle() RETURNS trigger
LANGUAGE plpgsql SET search_path=pg_catalog AS $$
DECLARE source uuid; target uuid; cyclic boolean; predicate text;
BEGIN
 source := (to_jsonb(NEW)->>TG_ARGV[0])::uuid;
 target := (to_jsonb(NEW)->>TG_ARGV[1])::uuid;
 predicate := coalesce(TG_ARGV[2],'true');
 INSERT INTO infrastructure.graph_locks(graph_key) VALUES(TG_TABLE_SCHEMA||'.'||TG_TABLE_NAME)
 ON CONFLICT(graph_key) DO UPDATE SET revision=infrastructure.graph_locks.revision+1;
 EXECUTE format('WITH RECURSIVE reachable(id) AS (
  SELECT %2$I FROM %3$I.%4$I WHERE %1$I=$1 AND id<>$3 AND (%5$s)
  UNION SELECT t.%2$I FROM %3$I.%4$I t JOIN reachable r ON t.%1$I=r.id WHERE t.id<>$3 AND (%5$s)
 ) SELECT $1=$2 OR EXISTS(SELECT 1 FROM reachable WHERE id=$2)',
 TG_ARGV[0],TG_ARGV[1],TG_TABLE_SCHEMA,TG_TABLE_NAME,predicate)
 INTO cyclic USING target,source,NEW.id;
 IF cyclic THEN RAISE EXCEPTION 'Dependency cycle rejected' USING ERRCODE='23514'; END IF;
 RETURN NEW;
END $$;
CREATE TRIGGER b_edge_cycle BEFORE INSERT OR UPDATE ON project.task_dependencies
 FOR EACH ROW EXECUTE FUNCTION infrastructure.prevent_edge_cycle('predecessor_id','successor_id');
CREATE TRIGGER b_edge_cycle BEFORE INSERT OR UPDATE ON workflow.edges
 FOR EACH ROW EXECUTE FUNCTION infrastructure.prevent_edge_cycle('from_step_id','to_step_id');
ALTER TABLE core.organization_relations ADD CHECK(parent_id<>child_id);
CREATE TRIGGER b_edge_cycle BEFORE INSERT OR UPDATE ON core.organization_relations
 FOR EACH ROW WHEN(NEW.relation_type='hierarchy')
 EXECUTE FUNCTION infrastructure.prevent_edge_cycle('parent_id','child_id','relation_type = ''hierarchy''');
CREATE TRIGGER b_edge_cycle BEFORE INSERT OR UPDATE ON itsm.ticket_relations
 FOR EACH ROW WHEN(NEW.relation_type='blocks')
 EXECUTE FUNCTION infrastructure.prevent_edge_cycle('source_id','target_id','relation_type = ''blocks''');

-- Protect a published parent and its children (definitions, prices, invoices).
CREATE FUNCTION infrastructure.freeze_parent() RETURNS trigger
LANGUAGE plpgsql SET search_path=pg_catalog AS $$
DECLARE parent_key uuid; previous_key uuid; frozen boolean; row_data jsonb;
BEGIN
 IF TG_OP='DELETE' THEN row_data:=to_jsonb(OLD); ELSE row_data:=to_jsonb(NEW); END IF;
 parent_key:=(row_data->>TG_ARGV[2])::uuid;
 IF TG_OP='UPDATE' THEN previous_key:=(to_jsonb(OLD)->>TG_ARGV[2])::uuid; END IF;
 -- Row locking also serializes changes with publication of the parent.
 FOR frozen IN EXECUTE format('SELECT (%s) FROM %I.%I WHERE id=$1 OR id=$2 FOR UPDATE',
 TG_ARGV[3],TG_ARGV[0],TG_ARGV[1]) USING parent_key,previous_key LOOP
  IF frozen THEN RAISE EXCEPTION 'Published parent is immutable' USING ERRCODE='23514'; END IF;
 END LOOP;
 IF TG_OP='DELETE' THEN RETURN OLD; END IF;
 RETURN NEW;
END $$;
CREATE TRIGGER a_frozen_parent BEFORE INSERT OR UPDATE OR DELETE ON workflow.steps
 FOR EACH ROW EXECUTE FUNCTION infrastructure.freeze_parent('workflow','versions','version_id','published_at IS NOT NULL');
CREATE TRIGGER a_frozen_parent BEFORE INSERT OR UPDATE OR DELETE ON workflow.edges
 FOR EACH ROW EXECUTE FUNCTION infrastructure.freeze_parent('workflow','versions','version_id','published_at IS NOT NULL');
CREATE TRIGGER a_frozen_parent BEFORE INSERT OR UPDATE OR DELETE ON commercial.invoice_lines
 FOR EACH ROW EXECUTE FUNCTION infrastructure.freeze_parent('commercial','invoices','invoice_id','issued_on IS NOT NULL');
CREATE TRIGGER a_frozen_parent BEFORE INSERT OR UPDATE OR DELETE ON commercial.contract_components
 FOR EACH ROW EXECUTE FUNCTION infrastructure.freeze_parent('commercial','contract_versions','version_id','signed_at IS NOT NULL');
CREATE TRIGGER a_frozen_parent BEFORE INSERT OR UPDATE OR DELETE ON commercial.contract_scopes
 FOR EACH ROW EXECUTE FUNCTION infrastructure.freeze_parent('commercial','contract_versions','version_id','signed_at IS NOT NULL');
CREATE FUNCTION infrastructure.freeze_field() RETURNS trigger
LANGUAGE plpgsql SET search_path=pg_catalog AS $$
BEGIN
 IF (to_jsonb(OLD)->TG_ARGV[0]) IS DISTINCT FROM 'null'::jsonb THEN
  RAISE EXCEPTION 'Issued or signed object is immutable' USING ERRCODE='23514';
 END IF;
 IF TG_OP='DELETE' THEN RETURN OLD; END IF;
 RETURN NEW;
END $$;
CREATE TRIGGER a_issued BEFORE UPDATE OR DELETE ON commercial.invoices
 FOR EACH ROW EXECUTE FUNCTION infrastructure.freeze_field('issued_on');
CREATE TRIGGER a_signed BEFORE UPDATE OR DELETE ON commercial.contract_versions
 FOR EACH ROW EXECUTE FUNCTION infrastructure.freeze_field('signed_at');

-- No credentials or policies pretending to authenticate a caller.
-- Existing application accounts get no privileges on the new domain schemas.
REVOKE ALL ON ALL FUNCTIONS IN SCHEMA infrastructure FROM PUBLIC;

-- A client-visible attachment must never reveal an internal message.
CREATE FUNCTION infrastructure.check_attachment_visibility() RETURNS trigger
LANGUAGE plpgsql SET search_path=pg_catalog AS $$
DECLARE visibility_value text;
BEGIN
 IF NEW.message_id IS NOT NULL AND NEW.visibility='client' THEN
  SELECT visibility INTO visibility_value FROM itsm.ticket_messages WHERE id=NEW.message_id FOR UPDATE;
  IF visibility_value IS DISTINCT FROM 'client' THEN
   RAISE EXCEPTION 'Internal message cannot have a client-visible attachment' USING ERRCODE='23514';
  END IF;
 END IF;
 RETURN NEW;
END $$;
CREATE TRIGGER b_visibility BEFORE INSERT OR UPDATE ON docs.ticket_attachments
 FOR EACH ROW EXECUTE FUNCTION infrastructure.check_attachment_visibility();
CREATE FUNCTION infrastructure.check_message_visibility() RETURNS trigger
LANGUAGE plpgsql SET search_path=pg_catalog AS $$
BEGIN
 IF NEW.visibility='internal' AND EXISTS(SELECT 1 FROM docs.ticket_attachments WHERE message_id=NEW.id AND visibility='client') THEN
  RAISE EXCEPTION 'Restrict attachments before making the message internal' USING ERRCODE='23514';
 END IF;
 RETURN NEW;
END $$;
CREATE TRIGGER b_visibility BEFORE UPDATE OF visibility ON itsm.ticket_messages
 FOR EACH ROW EXECUTE FUNCTION infrastructure.check_message_visibility();

-- Frozen contract details cannot be changed through another child table.
CREATE TRIGGER a_frozen_parent BEFORE INSERT OR UPDATE OR DELETE ON commercial.contract_sla_bindings
 FOR EACH ROW EXECUTE FUNCTION infrastructure.freeze_parent('commercial','contract_versions','version_id','signed_at IS NOT NULL');
CREATE TRIGGER a_frozen_parent BEFORE INSERT OR UPDATE OR DELETE ON commercial.contract_payers
 FOR EACH ROW EXECUTE FUNCTION infrastructure.freeze_parent('commercial','contract_versions','version_id','signed_at IS NOT NULL');
ALTER TABLE commercial.contract_components ADD CONSTRAINT component_version UNIQUE(id,version_id);
ALTER TABLE commercial.rate_rules ADD COLUMN version_id uuid NOT NULL;
ALTER TABLE commercial.rate_rules ADD CONSTRAINT rate_component_version FOREIGN KEY(component_id,version_id)
 REFERENCES commercial.contract_components(id,version_id);
CREATE TRIGGER a_frozen_parent BEFORE INSERT OR UPDATE OR DELETE ON commercial.rate_rules
 FOR EACH ROW EXECUTE FUNCTION infrastructure.freeze_parent('commercial','contract_versions','version_id','signed_at IS NOT NULL');
ALTER TABLE billing.usage_events ADD CHECK(component_id IS NULL OR contract_version_id IS NOT NULL);
ALTER TABLE billing.usage_events ADD CONSTRAINT usage_component_version FOREIGN KEY(component_id,contract_version_id)
 REFERENCES commercial.contract_components(id,version_id);
ALTER TABLE itsm.tickets ADD CHECK(resolved_at>=opened_at AND closed_at>=opened_at);
ALTER TABLE itsm.resolutions ADD CHECK(approval_due_at>=proposed_at);
ALTER TABLE billing.time_entries ADD CHECK((started_at IS NULL)=(ended_at IS NULL));
REVOKE ALL ON ALL FUNCTIONS IN SCHEMA infrastructure FROM PUBLIC;


REVOKE ALL ON ALL TABLES IN SCHEMA "core" FROM PUBLIC;
REVOKE ALL ON ALL SEQUENCES IN SCHEMA "core" FROM PUBLIC;
REVOKE ALL ON ALL FUNCTIONS IN SCHEMA "core" FROM PUBLIC;

REVOKE ALL ON ALL TABLES IN SCHEMA "iam" FROM PUBLIC;
REVOKE ALL ON ALL SEQUENCES IN SCHEMA "iam" FROM PUBLIC;
REVOKE ALL ON ALL FUNCTIONS IN SCHEMA "iam" FROM PUBLIC;

REVOKE ALL ON ALL TABLES IN SCHEMA "crm" FROM PUBLIC;
REVOKE ALL ON ALL SEQUENCES IN SCHEMA "crm" FROM PUBLIC;
REVOKE ALL ON ALL FUNCTIONS IN SCHEMA "crm" FROM PUBLIC;

REVOKE ALL ON ALL TABLES IN SCHEMA "web" FROM PUBLIC;
REVOKE ALL ON ALL SEQUENCES IN SCHEMA "web" FROM PUBLIC;
REVOKE ALL ON ALL FUNCTIONS IN SCHEMA "web" FROM PUBLIC;

REVOKE ALL ON ALL TABLES IN SCHEMA "project" FROM PUBLIC;
REVOKE ALL ON ALL SEQUENCES IN SCHEMA "project" FROM PUBLIC;
REVOKE ALL ON ALL FUNCTIONS IN SCHEMA "project" FROM PUBLIC;

REVOKE ALL ON ALL TABLES IN SCHEMA "people" FROM PUBLIC;
REVOKE ALL ON ALL SEQUENCES IN SCHEMA "people" FROM PUBLIC;
REVOKE ALL ON ALL FUNCTIONS IN SCHEMA "people" FROM PUBLIC;

REVOKE ALL ON ALL TABLES IN SCHEMA "schedule" FROM PUBLIC;
REVOKE ALL ON ALL SEQUENCES IN SCHEMA "schedule" FROM PUBLIC;
REVOKE ALL ON ALL FUNCTIONS IN SCHEMA "schedule" FROM PUBLIC;

REVOKE ALL ON ALL TABLES IN SCHEMA "itsm" FROM PUBLIC;
REVOKE ALL ON ALL SEQUENCES IN SCHEMA "itsm" FROM PUBLIC;
REVOKE ALL ON ALL FUNCTIONS IN SCHEMA "itsm" FROM PUBLIC;

REVOKE ALL ON ALL TABLES IN SCHEMA "service" FROM PUBLIC;
REVOKE ALL ON ALL SEQUENCES IN SCHEMA "service" FROM PUBLIC;
REVOKE ALL ON ALL FUNCTIONS IN SCHEMA "service" FROM PUBLIC;

REVOKE ALL ON ALL TABLES IN SCHEMA "workflow" FROM PUBLIC;
REVOKE ALL ON ALL SEQUENCES IN SCHEMA "workflow" FROM PUBLIC;
REVOKE ALL ON ALL FUNCTIONS IN SCHEMA "workflow" FROM PUBLIC;

REVOKE ALL ON ALL TABLES IN SCHEMA "cmdb" FROM PUBLIC;
REVOKE ALL ON ALL SEQUENCES IN SCHEMA "cmdb" FROM PUBLIC;
REVOKE ALL ON ALL FUNCTIONS IN SCHEMA "cmdb" FROM PUBLIC;

REVOKE ALL ON ALL TABLES IN SCHEMA "inventory" FROM PUBLIC;
REVOKE ALL ON ALL SEQUENCES IN SCHEMA "inventory" FROM PUBLIC;
REVOKE ALL ON ALL FUNCTIONS IN SCHEMA "inventory" FROM PUBLIC;

REVOKE ALL ON ALL TABLES IN SCHEMA "commercial" FROM PUBLIC;
REVOKE ALL ON ALL SEQUENCES IN SCHEMA "commercial" FROM PUBLIC;
REVOKE ALL ON ALL FUNCTIONS IN SCHEMA "commercial" FROM PUBLIC;

REVOKE ALL ON ALL TABLES IN SCHEMA "billing" FROM PUBLIC;
REVOKE ALL ON ALL SEQUENCES IN SCHEMA "billing" FROM PUBLIC;
REVOKE ALL ON ALL FUNCTIONS IN SCHEMA "billing" FROM PUBLIC;

REVOKE ALL ON ALL TABLES IN SCHEMA "knowledge" FROM PUBLIC;
REVOKE ALL ON ALL SEQUENCES IN SCHEMA "knowledge" FROM PUBLIC;
REVOKE ALL ON ALL FUNCTIONS IN SCHEMA "knowledge" FROM PUBLIC;

REVOKE ALL ON ALL TABLES IN SCHEMA "docs" FROM PUBLIC;
REVOKE ALL ON ALL SEQUENCES IN SCHEMA "docs" FROM PUBLIC;
REVOKE ALL ON ALL FUNCTIONS IN SCHEMA "docs" FROM PUBLIC;

REVOKE ALL ON ALL TABLES IN SCHEMA "comms" FROM PUBLIC;
REVOKE ALL ON ALL SEQUENCES IN SCHEMA "comms" FROM PUBLIC;
REVOKE ALL ON ALL FUNCTIONS IN SCHEMA "comms" FROM PUBLIC;

REVOKE ALL ON ALL TABLES IN SCHEMA "integration" FROM PUBLIC;
REVOKE ALL ON ALL SEQUENCES IN SCHEMA "integration" FROM PUBLIC;
REVOKE ALL ON ALL FUNCTIONS IN SCHEMA "integration" FROM PUBLIC;

REVOKE ALL ON ALL TABLES IN SCHEMA "reporting" FROM PUBLIC;
REVOKE ALL ON ALL SEQUENCES IN SCHEMA "reporting" FROM PUBLIC;
REVOKE ALL ON ALL FUNCTIONS IN SCHEMA "reporting" FROM PUBLIC;

REVOKE ALL ON ALL TABLES IN SCHEMA "governance" FROM PUBLIC;
REVOKE ALL ON ALL SEQUENCES IN SCHEMA "governance" FROM PUBLIC;
REVOKE ALL ON ALL FUNCTIONS IN SCHEMA "governance" FROM PUBLIC;
INSERT INTO infrastructure.migrations(version,checksum) VALUES ('20261010_001_business','a4f11fa8dee0a5f30a09b5a7a4cc2ca3ecd2b37d383316ea722e97c41e5e6c94');
\endif
COMMIT;

INSERT INTO deployment.bundle_migrations(name,sha256) VALUES ('001-business.sql','78ac29f8a2b8f2783ee54dd208617b33130488d56f37d4d86a47e10523d70afa');
\endif


-- ===== 002-crm-agents.sql =====
SELECT EXISTS (SELECT FROM deployment.bundle_migrations WHERE name='002-crm-agents.sql') AS bundle_done \gset
\if :bundle_done
DO $$ BEGIN IF NOT EXISTS (SELECT FROM deployment.bundle_migrations WHERE name='002-crm-agents.sql' AND sha256='0b52497b8093d6d5bc6a1219089bd2032e144e4de87bb868f1a68a9fe35f5395') THEN RAISE EXCEPTION 'Empreinte différente : 002-crm-agents.sql'; END IF; END $$;
\else
-- Narrow read of the people who can use the CRM. The function runs as its owner
-- so the application role never receives the iam or core schemas.
CREATE OR REPLACE FUNCTION genesis.crm_agents()
RETURNS TABLE (id uuid, name text)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog
AS $$
  SELECT principal.id,
    COALESCE(
      NULLIF(btrim(concat_ws(' ', person.given_name, person.family_name)), ''),
      btrim(principal.display_name)
    ) AS name
  FROM iam.principals AS principal
  LEFT JOIN core.persons AS person
    ON person.id = principal.person_id
   AND person.status = 'active'
  WHERE principal.kind = 'human'
    AND principal.status = 'active'
    AND EXISTS (
      SELECT 1
      FROM iam.role_bindings AS binding
      JOIN iam.role_permissions AS grant_row
        ON grant_row.role_id = binding.role_id
       AND grant_row.effect = 'allow'
      JOIN iam.permissions AS permission
        ON permission.id = grant_row.permission_id
      JOIN iam.applications AS application
        ON application.id = permission.application_id
       AND application.code = 'CRM'
       AND application.enabled
      WHERE binding.principal_id = principal.id
        AND binding.valid_from <= clock_timestamp()
        AND (binding.valid_to IS NULL OR binding.valid_to >= clock_timestamp())
        AND NOT EXISTS (
          SELECT 1
          FROM iam.role_bindings AS denial_binding
          JOIN iam.role_permissions AS denial
            ON denial.role_id = denial_binding.role_id
           AND denial.effect = 'deny'
           AND denial.permission_id = permission.id
          WHERE denial_binding.principal_id = principal.id
            AND denial_binding.valid_from <= clock_timestamp()
            AND (denial_binding.valid_to IS NULL OR denial_binding.valid_to >= clock_timestamp())
        )
    )
  ORDER BY 2;
$$;

ALTER FUNCTION genesis.crm_agents() OWNER TO postgres;
REVOKE ALL ON FUNCTION genesis.crm_agents() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION genesis.crm_agents() TO genesis;

INSERT INTO deployment.bundle_migrations(name,sha256) VALUES ('002-crm-agents.sql','0b52497b8093d6d5bc6a1219089bd2032e144e4de87bb868f1a68a9fe35f5395');
\endif


-- ===== 003-identity.sql =====
SELECT EXISTS (SELECT FROM deployment.bundle_migrations WHERE name='003-identity.sql') AS bundle_done \gset
\if :bundle_done
DO $$ BEGIN IF NOT EXISTS (SELECT FROM deployment.bundle_migrations WHERE name='003-identity.sql' AND sha256='71d0108827bb9044bc4da3b8d2e144e01500cbb333675a2d2cac06591a2cf5b1') THEN RAISE EXCEPTION 'Empreinte différente : 003-identity.sql'; END IF; END $$;
\else
CREATE TABLE IF NOT EXISTS genesis.app_organizations (
  id text PRIMARY KEY,
  name text NOT NULL,
  status text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS genesis.app_users (
  id text PRIMARY KEY,
  email text NOT NULL UNIQUE,
  given_name text NOT NULL,
  family_name text NOT NULL,
  status text NOT NULL,
  issuer text NOT NULL DEFAULT '',
  subject text NOT NULL DEFAULT '',
  created_at timestamptz NOT NULL DEFAULT now(),
  last_seen_at timestamptz
);

CREATE UNIQUE INDEX IF NOT EXISTS app_users_issuer_subject
  ON genesis.app_users (issuer, subject)
  WHERE subject <> '';

CREATE TABLE IF NOT EXISTS genesis.app_memberships (
  id text PRIMARY KEY,
  user_id text NOT NULL REFERENCES genesis.app_users (id),
  organization_id text NOT NULL REFERENCES genesis.app_organizations (id),
  role text NOT NULL,
  apps jsonb NOT NULL DEFAULT '[]'::jsonb,
  UNIQUE (user_id, organization_id)
);

CREATE TABLE IF NOT EXISTS genesis.app_sessions (
  token_hash text PRIMARY KEY,
  user_id text NOT NULL REFERENCES genesis.app_users (id),
  created_at timestamptz NOT NULL DEFAULT now(),
  expires_at timestamptz NOT NULL,
  confirmed_at timestamptz NOT NULL DEFAULT now(),
  revoked_at timestamptz
);

CREATE TABLE IF NOT EXISTS genesis.app_login_events (
  id text PRIMARY KEY,
  user_id text NOT NULL DEFAULT '',
  at timestamptz NOT NULL DEFAULT now(),
  result text NOT NULL,
  address_hash text NOT NULL DEFAULT ''
);

CREATE TABLE IF NOT EXISTS genesis.app_oidc_states (
  state_hash text PRIMARY KEY,
  verifier text NOT NULL,
  nonce_hash text NOT NULL,
  return_to text NOT NULL,
  expires_at timestamptz NOT NULL
);

CREATE TABLE IF NOT EXISTS genesis.app_settings (
  id text PRIMARY KEY,
  value text NOT NULL
);

REVOKE ALL ON genesis.app_organizations, genesis.app_users, genesis.app_memberships, genesis.app_sessions, genesis.app_login_events, genesis.app_oidc_states, genesis.app_settings FROM PUBLIC;

INSERT INTO deployment.bundle_migrations(name,sha256) VALUES ('003-identity.sql','71d0108827bb9044bc4da3b8d2e144e01500cbb333675a2d2cac06591a2cf5b1');
\endif


-- ===== 004-local-identity.sql =====
SELECT EXISTS (SELECT FROM deployment.bundle_migrations WHERE name='004-local-identity.sql') AS bundle_done \gset
\if :bundle_done
DO $$ BEGIN IF NOT EXISTS (SELECT FROM deployment.bundle_migrations WHERE name='004-local-identity.sql' AND sha256='3873cdad2383eb705e6241186b002ca8f48cf284eca994d84e3780af496b2b54') THEN RAISE EXCEPTION 'Empreinte différente : 004-local-identity.sql'; END IF; END $$;
\else
BEGIN;

CREATE TABLE IF NOT EXISTS iam.local_accounts (
  principal_id uuid PRIMARY KEY REFERENCES iam.principals(id) ON DELETE RESTRICT,
  email text NOT NULL,
  password_hash text NOT NULL,
  failed_attempts integer NOT NULL DEFAULT 0 CHECK (failed_attempts >= 0),
  locked_until timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT local_accounts_email_format CHECK (email ~ '^[^[:space:]@]+@[^[:space:]@]+$')
);
CREATE UNIQUE INDEX IF NOT EXISTS local_accounts_email_unique ON iam.local_accounts (lower(email));
ALTER TABLE iam.local_accounts ENABLE ROW LEVEL SECURITY;
ALTER TABLE iam.local_accounts FORCE ROW LEVEL SECURITY;
REVOKE ALL ON iam.local_accounts FROM PUBLIC;

CREATE TABLE IF NOT EXISTS iam.local_sessions (
  token_hash text PRIMARY KEY CHECK (token_hash ~ '^[0-9a-f]{64}$'),
  principal_id uuid NOT NULL REFERENCES iam.principals(id) ON DELETE CASCADE,
  created_at timestamptz NOT NULL DEFAULT now(),
  expires_at timestamptz NOT NULL,
  confirmed_at timestamptz NOT NULL DEFAULT now(),
  revoked_at timestamptz
);
CREATE INDEX IF NOT EXISTS local_sessions_principal ON iam.local_sessions (principal_id);
ALTER TABLE iam.local_sessions ENABLE ROW LEVEL SECURITY;
ALTER TABLE iam.local_sessions FORCE ROW LEVEL SECURITY;
REVOKE ALL ON iam.local_sessions FROM PUBLIC;

CREATE OR REPLACE FUNCTION iam.crm_login_account(requested_email text)
RETURNS text LANGUAGE sql SECURITY DEFINER SET search_path = pg_catalog AS $$
  SELECT jsonb_build_object(
    'id', p.id, 'email', a.email, 'passwordHash', a.password_hash,
    'status', p.status, 'lockedUntil', a.locked_until
  )::text
  FROM iam.local_accounts a
  JOIN iam.principals p ON p.id = a.principal_id
  WHERE lower(a.email) = lower(requested_email)
  LIMIT 1;
$$;

CREATE OR REPLACE FUNCTION iam.crm_login_session(requested_hash text)
RETURNS text LANGUAGE sql SECURITY DEFINER SET search_path = pg_catalog AS $$
  SELECT jsonb_build_object(
    'id', p.id, 'email', a.email, 'givenName', p.display_name,
    'familyName', '', 'status', p.status, 'confirmedAt', s.confirmed_at,
    'memberships', jsonb_build_array(jsonb_build_object(
      'organizationId', 'org-prodigital', 'organizationName', 'ProDigital',
      'role', CASE role.code
        WHEN 'business_admin' THEN 'platform_admin'
        WHEN 'sales' THEN 'collaborator'
        WHEN 'technician' THEN 'collaborator'
        WHEN 'collaborator' THEN 'collaborator'
        ELSE 'reader' END,
      'apps', jsonb_build_array('crm', 'itsm', 'core')
    ))
  )::text
  FROM iam.local_sessions s
  JOIN iam.principals p ON p.id = s.principal_id
  JOIN iam.local_accounts a ON a.principal_id = p.id
  JOIN LATERAL (
    SELECT r.code FROM iam.role_bindings b
    JOIN iam.roles r ON r.id = b.role_id
    JOIN iam.access_scopes scope ON scope.id = b.scope_id
    WHERE b.principal_id = p.id AND scope.kind = 'installation'
      AND b.valid_from <= now() AND (b.valid_to IS NULL OR b.valid_to > now())
    ORDER BY CASE r.code
      WHEN 'business_admin' THEN 5 WHEN 'sales' THEN 4
      WHEN 'technician' THEN 3 WHEN 'collaborator' THEN 2 ELSE 1 END DESC
    LIMIT 1
  ) role ON true
  WHERE s.token_hash = requested_hash AND s.revoked_at IS NULL
    AND s.expires_at > now() AND p.status = 'active';
$$;

CREATE OR REPLACE FUNCTION iam.crm_record_login_attempt(account_id uuid, succeeded boolean)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog AS $$
BEGIN
  UPDATE iam.local_accounts
  SET failed_attempts = CASE WHEN succeeded THEN 0 ELSE failed_attempts + 1 END,
      locked_until = CASE WHEN succeeded THEN NULL
        WHEN failed_attempts + 1 >= 5 THEN now() + interval '15 minutes'
        ELSE locked_until END,
      updated_at = now()
  WHERE principal_id = account_id;
END $$;

CREATE OR REPLACE FUNCTION iam.crm_open_session(account_id uuid, requested_hash text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog AS $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM iam.local_accounts a
    JOIN iam.principals p ON p.id = a.principal_id
    JOIN iam.role_bindings b ON b.principal_id = p.id
    JOIN iam.access_scopes scope ON scope.id = b.scope_id
    WHERE a.principal_id = account_id AND p.status = 'active'
      AND (a.locked_until IS NULL OR a.locked_until <= now())
      AND scope.kind = 'installation' AND b.valid_from <= now()
      AND (b.valid_to IS NULL OR b.valid_to > now())
  ) THEN RAISE EXCEPTION 'Account not allowed'; END IF;
  INSERT INTO iam.local_sessions (token_hash, principal_id, expires_at)
  VALUES (requested_hash, account_id, now() + interval '8 hours');
END $$;

CREATE OR REPLACE FUNCTION iam.crm_touch_session(requested_hash text)
RETURNS void LANGUAGE sql SECURITY DEFINER SET search_path = pg_catalog AS $$
  UPDATE iam.local_sessions SET expires_at = now() + interval '8 hours'
  WHERE token_hash = requested_hash AND revoked_at IS NULL AND expires_at > now()
    AND expires_at < now() + interval '30 minutes'
    AND created_at > now() - interval '24 hours';
$$;

CREATE OR REPLACE FUNCTION iam.crm_confirm_session(requested_hash text)
RETURNS void LANGUAGE sql SECURITY DEFINER SET search_path = pg_catalog AS $$
  UPDATE iam.local_sessions SET confirmed_at = now(), expires_at = now() + interval '8 hours'
  WHERE token_hash = requested_hash AND revoked_at IS NULL AND expires_at > now();
$$;

CREATE OR REPLACE FUNCTION iam.crm_revoke_session(requested_hash text)
RETURNS void LANGUAGE sql SECURITY DEFINER SET search_path = pg_catalog AS $$
  UPDATE iam.local_sessions SET revoked_at = now()
  WHERE token_hash = requested_hash AND revoked_at IS NULL;
$$;

CREATE OR REPLACE FUNCTION iam.crm_revoke_user_sessions(account_id uuid)
RETURNS void LANGUAGE sql SECURITY DEFINER SET search_path = pg_catalog AS $$
  UPDATE iam.local_sessions SET revoked_at = now()
  WHERE principal_id = account_id AND revoked_at IS NULL;
$$;

CREATE OR REPLACE FUNCTION iam.crm_change_password(account_id uuid, new_hash text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog AS $$
BEGIN
  IF new_hash !~ '^scrypt:131072:8:1:[A-Za-z0-9_-]+:[A-Za-z0-9_-]+$' THEN
    RAISE EXCEPTION 'Invalid password hash';
  END IF;
  UPDATE iam.local_accounts SET password_hash = new_hash,
    failed_attempts = 0, locked_until = NULL, updated_at = now()
  WHERE principal_id = account_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Account not found'; END IF;
  UPDATE iam.local_sessions SET revoked_at = now()
  WHERE principal_id = account_id AND revoked_at IS NULL;
END $$;

REVOKE ALL ON FUNCTION iam.crm_login_account(text), iam.crm_login_session(text),
  iam.crm_record_login_attempt(uuid,boolean), iam.crm_open_session(uuid,text),
  iam.crm_touch_session(text), iam.crm_confirm_session(text),
  iam.crm_revoke_session(text), iam.crm_revoke_user_sessions(uuid),
  iam.crm_change_password(uuid,text) FROM PUBLIC;
GRANT USAGE ON SCHEMA iam TO genesis;
GRANT EXECUTE ON FUNCTION iam.crm_login_account(text), iam.crm_login_session(text),
  iam.crm_record_login_attempt(uuid,boolean), iam.crm_open_session(uuid,text),
  iam.crm_touch_session(text), iam.crm_confirm_session(text),
  iam.crm_revoke_session(text), iam.crm_revoke_user_sessions(uuid),
  iam.crm_change_password(uuid,text) TO genesis;

COMMIT;

INSERT INTO deployment.bundle_migrations(name,sha256) VALUES ('004-local-identity.sql','3873cdad2383eb705e6241186b002ca8f48cf284eca994d84e3780af496b2b54');
\endif


-- ===== 005-core-account-admin.sql =====
SELECT EXISTS (SELECT FROM deployment.bundle_migrations WHERE name='005-core-account-admin.sql') AS bundle_done \gset
\if :bundle_done
DO $$ BEGIN IF NOT EXISTS (SELECT FROM deployment.bundle_migrations WHERE name='005-core-account-admin.sql' AND sha256='3acbc70f52c2935b7376b1ab2775adeb4d6e970e74a0e49bbe15e5629b7d9f5f') THEN RAISE EXCEPTION 'Empreinte différente : 005-core-account-admin.sql'; END IF; END $$;
\else
BEGIN;

CREATE OR REPLACE FUNCTION iam.crm_admin_authorized(actor_hash text)
RETURNS boolean LANGUAGE sql SECURITY DEFINER SET search_path = pg_catalog AS $$
  SELECT EXISTS (
    SELECT 1 FROM iam.local_sessions s
    JOIN iam.principals p ON p.id = s.principal_id
    JOIN iam.role_bindings b ON b.principal_id = p.id
    JOIN iam.roles r ON r.id = b.role_id
    JOIN iam.access_scopes scope ON scope.id = b.scope_id
    WHERE s.token_hash = actor_hash AND s.revoked_at IS NULL AND s.expires_at > now()
      AND p.status = 'active' AND r.code = 'business_admin'
      AND scope.kind = 'installation' AND b.valid_from <= now()
      AND (b.valid_to IS NULL OR b.valid_to > now())
  );
$$;

CREATE OR REPLACE FUNCTION iam.crm_list_accounts(actor_hash text)
RETURNS text LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog AS $$
DECLARE result text;
BEGIN
  IF NOT iam.crm_admin_authorized(actor_hash) THEN RAISE EXCEPTION 'Forbidden'; END IF;
  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'id', p.id, 'email', a.email, 'displayName', p.display_name,
    'status', p.status, 'role', r.code, 'createdAt', a.created_at
  ) ORDER BY a.created_at), '[]'::jsonb)::text INTO result
  FROM iam.local_accounts a
  JOIN iam.principals p ON p.id = a.principal_id
  JOIN LATERAL (
    SELECT roles.code FROM iam.role_bindings b
    JOIN iam.roles roles ON roles.id = b.role_id
    JOIN iam.access_scopes scope ON scope.id = b.scope_id
    WHERE b.principal_id = p.id AND scope.kind = 'installation'
      AND b.valid_from <= now() AND (b.valid_to IS NULL OR b.valid_to > now())
    ORDER BY CASE roles.code WHEN 'business_admin' THEN 5 WHEN 'sales' THEN 4
      WHEN 'technician' THEN 3 ELSE 1 END DESC LIMIT 1
  ) r ON true;
  RETURN result;
END $$;

CREATE OR REPLACE FUNCTION iam.crm_create_account(
  actor_hash text, new_email text, new_name text, new_hash text, new_role text
) RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog AS $$
DECLARE account_id uuid;
DECLARE actor_id uuid;
DECLARE role_id uuid;
DECLARE scope_id uuid;
BEGIN
  IF NOT iam.crm_admin_authorized(actor_hash) THEN RAISE EXCEPTION 'Forbidden'; END IF;
  IF new_email !~ '^[^[:space:]@]+@[^[:space:]@]+$' OR length(new_email) > 254
    OR length(trim(new_name)) < 2 OR length(new_name) > 120
    OR new_hash !~ '^scrypt:131072:8:1:[A-Za-z0-9_-]+:[A-Za-z0-9_-]+$'
    OR new_role NOT IN ('business_admin','sales','technician','collaborator')
  THEN RAISE EXCEPTION 'Invalid account'; END IF;
  SELECT principal_id INTO actor_id FROM iam.local_sessions WHERE token_hash = actor_hash;
  SELECT id INTO role_id FROM iam.roles WHERE code = new_role;
  SELECT id INTO scope_id FROM iam.access_scopes WHERE kind = 'installation' ORDER BY created_at LIMIT 1;
  IF role_id IS NULL OR scope_id IS NULL THEN RAISE EXCEPTION 'Role or scope missing'; END IF;
  INSERT INTO iam.principals (kind, status, display_name)
  VALUES ('human','active',trim(new_name)) RETURNING id INTO account_id;
  INSERT INTO iam.local_accounts (principal_id, email, password_hash)
  VALUES (account_id, lower(new_email), new_hash);
  INSERT INTO iam.role_bindings (principal_id, role_id, scope_id, valid_from, granted_by)
  VALUES (account_id, role_id, scope_id, now(), actor_id);
  RETURN account_id;
END $$;

CREATE OR REPLACE FUNCTION iam.crm_set_account_status(actor_hash text, account_id uuid, new_status text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog AS $$
DECLARE actor_id uuid;
BEGIN
  IF NOT iam.crm_admin_authorized(actor_hash) THEN RAISE EXCEPTION 'Forbidden'; END IF;
  SELECT principal_id INTO actor_id FROM iam.local_sessions WHERE token_hash = actor_hash;
  IF account_id = actor_id OR new_status NOT IN ('active','inactive') THEN RAISE EXCEPTION 'Invalid status change'; END IF;
  UPDATE iam.principals SET status = new_status WHERE id = account_id
    AND EXISTS (SELECT 1 FROM iam.local_accounts WHERE principal_id = account_id);
  IF NOT FOUND THEN RAISE EXCEPTION 'Account not found'; END IF;
  IF new_status = 'inactive' THEN
    UPDATE iam.local_sessions SET revoked_at = now() WHERE principal_id = account_id AND revoked_at IS NULL;
  END IF;
END $$;

REVOKE ALL ON FUNCTION iam.crm_admin_authorized(text), iam.crm_list_accounts(text),
  iam.crm_create_account(text,text,text,text,text), iam.crm_set_account_status(text,uuid,text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION iam.crm_list_accounts(text),
  iam.crm_create_account(text,text,text,text,text), iam.crm_set_account_status(text,uuid,text) TO genesis;

COMMIT;

INSERT INTO deployment.bundle_migrations(name,sha256) VALUES ('005-core-account-admin.sql','3acbc70f52c2935b7376b1ab2775adeb4d6e970e74a0e49bbe15e5629b7d9f5f');
\endif


-- ===== 006-core-extensions.sql =====
SELECT EXISTS (SELECT FROM deployment.bundle_migrations WHERE name='006-core-extensions.sql') AS bundle_done \gset
\if :bundle_done
DO $$ BEGIN IF NOT EXISTS (SELECT FROM deployment.bundle_migrations WHERE name='006-core-extensions.sql' AND sha256='125c38380be25c67435decff7c4a2242e7319b631e1420cb0b3a5622f253053f') THEN RAISE EXCEPTION 'Empreinte différente : 006-core-extensions.sql'; END IF; END $$;
\else
\set ON_ERROR_STOP on
BEGIN;
SET LOCAL lock_timeout='15s';
SET LOCAL statement_timeout='180s';
SELECT pg_advisory_xact_lock(hashtextextended('prodigital-schema', 0));
CREATE SCHEMA IF NOT EXISTS infrastructure;
CREATE TABLE IF NOT EXISTS infrastructure.migrations (version text PRIMARY KEY, checksum text NOT NULL, applied_at timestamptz NOT NULL DEFAULT clock_timestamp());
SELECT EXISTS(SELECT 1 FROM infrastructure.migrations WHERE version='20261019_006_core_extensions') AS already_applied \gset
\if :already_applied
SELECT checksum='f7016d5b7b7b395ad407ff126159c24017df3f11a3f5844bdadb38eeae2a1464' AS checksum_matches FROM infrastructure.migrations WHERE version='20261019_006_core_extensions' \gset
\if :checksum_matches
\echo Migration already applied; checksum verified.
\else
DO $$ BEGIN RAISE EXCEPTION 'Migration checksum mismatch'; END $$;
\endif
\else
CREATE SCHEMA IF NOT EXISTS "advisory";
REVOKE ALL ON SCHEMA "advisory" FROM PUBLIC;

CREATE SCHEMA IF NOT EXISTS "ai";
REVOKE ALL ON SCHEMA "ai" FROM PUBLIC;

CREATE SCHEMA IF NOT EXISTS "commercial";
REVOKE ALL ON SCHEMA "commercial" FROM PUBLIC;

CREATE SCHEMA IF NOT EXISTS "core";
REVOKE ALL ON SCHEMA "core" FROM PUBLIC;

CREATE SCHEMA IF NOT EXISTS "delivery";
REVOKE ALL ON SCHEMA "delivery" FROM PUBLIC;

CREATE SCHEMA IF NOT EXISTS "governance";
REVOKE ALL ON SCHEMA "governance" FROM PUBLIC;

CREATE SCHEMA IF NOT EXISTS "studio";
REVOKE ALL ON SCHEMA "studio" FROM PUBLIC;

CREATE SCHEMA IF NOT EXISTS "success";
REVOKE ALL ON SCHEMA "success" FROM PUBLIC;

CREATE TABLE "core"."departments" (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "organization_id" uuid NOT NULL,
  "parent_id" uuid,
  "code" text NOT NULL,
  "name" text NOT NULL,
  "active" boolean NOT NULL,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  row_version bigint NOT NULL DEFAULT 1 CHECK (row_version > 0)
);

COMMENT ON TABLE "core"."departments" IS 'Services et unités organisationnelles | Catalogue: Code unique par organisation ; parent de la même organisation ; cycles interdits. Le chemin est calculé. Aucun droit implicite.';

ALTER TABLE "core"."departments" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "core"."departments" FORCE ROW LEVEL SECURITY;

CREATE TRIGGER z_touch BEFORE UPDATE ON "core"."departments" FOR EACH ROW EXECUTE FUNCTION infrastructure.touch_row();

ALTER TABLE "core"."departments" ADD CONSTRAINT "c_1154c6b80ae694bbda21" UNIQUE NULLS NOT DISTINCT ("organization_id", "code");

CREATE TABLE "core"."department_assignments" (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "affiliation_id" uuid NOT NULL,
  "department_id" uuid NOT NULL,
  "valid_from" date NOT NULL,
  "valid_to" date,
  "is_primary" boolean NOT NULL,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  row_version bigint NOT NULL DEFAULT 1 CHECK (row_version > 0)
);

COMMENT ON TABLE "core"."department_assignments" IS 'Rattachements historiques aux services | Catalogue: Affiliation et département de la même organisation ; dates ordonnées ; un seul rattachement principal actif à un instant ; période incluse dans celle de l’affiliation.';

ALTER TABLE "core"."department_assignments" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "core"."department_assignments" FORCE ROW LEVEL SECURITY;

CREATE TRIGGER z_touch BEFORE UPDATE ON "core"."department_assignments" FOR EACH ROW EXECUTE FUNCTION infrastructure.touch_row();

ALTER TABLE "core"."department_assignments" ADD CONSTRAINT "c_e7dc6b0f85dec67c70f6" CHECK ("valid_to" >= "valid_from");

CREATE TABLE "core"."affiliation_identifiers" (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "affiliation_id" uuid NOT NULL,
  "connection_id" uuid,
  "namespace" text NOT NULL,
  "value" text NOT NULL,
  "valid_from" date NOT NULL,
  "valid_to" date,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  row_version bigint NOT NULL DEFAULT 1 CHECK (row_version > 0)
);

COMMENT ON TABLE "core"."affiliation_identifiers" IS 'Matricules et identifiants de personnes par source | Catalogue: Identifiant texte, jamais entier ; unicité source/espace de noms/valeur pour les périodes actives, avec traitement explicite des sources NULL ; périmètre organisationnel contrôlé.';

ALTER TABLE "core"."affiliation_identifiers" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "core"."affiliation_identifiers" FORCE ROW LEVEL SECURITY;

CREATE TRIGGER z_touch BEFORE UPDATE ON "core"."affiliation_identifiers" FOR EACH ROW EXECUTE FUNCTION infrastructure.touch_row();

ALTER TABLE "core"."affiliation_identifiers" ADD CONSTRAINT "c_204d038894d80b666eeb" CHECK ("valid_to" >= "valid_from");

CREATE TABLE "commercial"."product_families" (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "code" text NOT NULL,
  "name" text NOT NULL,
  "parent_id" uuid,
  "active" boolean NOT NULL,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  row_version bigint NOT NULL DEFAULT 1 CHECK (row_version > 0)
);

COMMENT ON TABLE "commercial"."product_families" IS 'Familles de prestations et logiciels | Catalogue: Code unique ; hiérarchie sans cycle. Les familles web/conseil/support/SaaS sont une configuration à créer, pas des clients ni des tarifs.';

ALTER TABLE "commercial"."product_families" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "commercial"."product_families" FORCE ROW LEVEL SECURITY;

CREATE TRIGGER z_touch BEFORE UPDATE ON "commercial"."product_families" FOR EACH ROW EXECUTE FUNCTION infrastructure.touch_row();

ALTER TABLE "commercial"."product_families" ADD CONSTRAINT "c_a35c02ae86b6bb7171e0" UNIQUE NULLS NOT DISTINCT ("code");

CREATE TABLE "commercial"."product_family_memberships" (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "product_id" uuid NOT NULL,
  "family_id" uuid NOT NULL,
  "is_primary" boolean NOT NULL,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  row_version bigint NOT NULL DEFAULT 1 CHECK (row_version > 0)
);

COMMENT ON TABLE "commercial"."product_family_memberships" IS 'Classement des produits existants | Catalogue: Couple unique ; au plus une famille principale par produit. Pas de duplication du produit.';

ALTER TABLE "commercial"."product_family_memberships" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "commercial"."product_family_memberships" FORCE ROW LEVEL SECURITY;

CREATE TRIGGER z_touch BEFORE UPDATE ON "commercial"."product_family_memberships" FOR EACH ROW EXECUTE FUNCTION infrastructure.touch_row();

ALTER TABLE "commercial"."product_family_memberships" ADD CONSTRAINT "c_e3f65b51e97892e6d853" UNIQUE NULLS NOT DISTINCT ("product_id", "family_id");

CREATE TABLE "commercial"."product_bundles" (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "product_id" uuid NOT NULL,
  "version_no" integer NOT NULL,
  "status" text NOT NULL,
  "valid_from" timestamptz NOT NULL,
  "valid_to" timestamptz,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  row_version bigint NOT NULL DEFAULT 1 CHECK (row_version > 0)
);

COMMENT ON TABLE "commercial"."product_bundles" IS 'Versions de compositions d’offres | Catalogue: Version positive unique par produit ; états draft/published/retired ; version publiée immuable ; fenêtres publiées non chevauchantes.';

ALTER TABLE "commercial"."product_bundles" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "commercial"."product_bundles" FORCE ROW LEVEL SECURITY;

CREATE TRIGGER z_touch BEFORE UPDATE ON "commercial"."product_bundles" FOR EACH ROW EXECUTE FUNCTION infrastructure.touch_row();

ALTER TABLE "commercial"."product_bundles" ADD CONSTRAINT "c_550a0a67880c84245313" CHECK ("version_no" > 0);

ALTER TABLE "commercial"."product_bundles" ADD CONSTRAINT "c_9d85100fe780c038a4cb" CHECK ("valid_to" >= "valid_from");

ALTER TABLE "commercial"."product_bundles" ADD CONSTRAINT "c_6569c9dfec696cd57749" CHECK ("status" IN ('draft', 'published', 'retired'));

ALTER TABLE "commercial"."product_bundles" ADD CONSTRAINT "c_cb8a80b2fd17aa1e8e0b" UNIQUE NULLS NOT DISTINCT ("product_id", "version_no");

CREATE TABLE "commercial"."bundle_items" (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "bundle_id" uuid NOT NULL,
  "component_product_id" uuid NOT NULL,
  "quantity" numeric(20,6) NOT NULL,
  "unit" text NOT NULL,
  "optional" boolean NOT NULL,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  row_version bigint NOT NULL DEFAULT 1 CHECK (row_version > 0)
);

COMMENT ON TABLE "commercial"."bundle_items" IS 'Produits inclus dans une offre composée | Catalogue: Quantité strictement positive ; unité compatible ; pas d’auto-inclusion ni de cycle indirect ; lignes figées avec leur version publiée. Prix effectif dans le devis/contrat.';

ALTER TABLE "commercial"."bundle_items" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "commercial"."bundle_items" FORCE ROW LEVEL SECURITY;

CREATE TRIGGER z_touch BEFORE UPDATE ON "commercial"."bundle_items" FOR EACH ROW EXECUTE FUNCTION infrastructure.touch_row();

ALTER TABLE "commercial"."bundle_items" ADD CONSTRAINT "c_1f648d38010e5b22408d" CHECK ("quantity" <> 'NaN'::numeric);

ALTER TABLE "commercial"."bundle_items" ADD CONSTRAINT "c_93359f3b2d2c33fce5de" CHECK ("quantity" > 0);

ALTER TABLE "commercial"."bundle_items" ADD CONSTRAINT "c_7cac39e1f18f56afa8ba" UNIQUE NULLS NOT DISTINCT ("bundle_id", "component_product_id");

CREATE TABLE "governance"."data_quality_issues" (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "entity_type" text NOT NULL,
  "entity_id" uuid NOT NULL,
  "rule_code" text NOT NULL,
  "detected_at" timestamptz NOT NULL,
  "status" text NOT NULL,
  "assigned_to" uuid,
  "resolved_at" timestamptz,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  row_version bigint NOT NULL DEFAULT 1 CHECK (row_version > 0)
);

COMMENT ON TABLE "governance"."data_quality_issues" IS 'Anomalies de qualité à corriger | Catalogue: Référence typée vérifiée par registre ; open/triaged/resolved/ignored ; résolution datée et auditée ; aucune fusion automatique sur simple similarité.';

ALTER TABLE "governance"."data_quality_issues" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "governance"."data_quality_issues" FORCE ROW LEVEL SECURITY;

CREATE TRIGGER z_touch BEFORE UPDATE ON "governance"."data_quality_issues" FOR EACH ROW EXECUTE FUNCTION infrastructure.touch_row();

ALTER TABLE "governance"."data_quality_issues" ADD CONSTRAINT "c_2373355cc3aea0b2a159" CHECK ("status" IN ('open', 'triaged', 'resolved', 'ignored'));

CREATE TABLE "governance"."merge_operations" (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "entity_type" text NOT NULL,
  "source_id" uuid NOT NULL,
  "target_id" uuid NOT NULL,
  "requested_by" uuid NOT NULL,
  "approved_by" uuid,
  "executed_at" timestamptz,
  "status" text NOT NULL,
  "mapping_document_version_id" uuid,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  row_version bigint NOT NULL DEFAULT 1 CHECK (row_version > 0)
);

COMMENT ON TABLE "governance"."merge_operations" IS 'Fusions contrôlées de doublons | Catalogue: Source distincte de cible, même installation et périmètre compatible ; types autorisés limités ; dry-run avant application transactionnelle ; liens historiques et externes redirigés sans effacer audit.';

ALTER TABLE "governance"."merge_operations" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "governance"."merge_operations" FORCE ROW LEVEL SECURITY;

CREATE TRIGGER z_touch BEFORE UPDATE ON "governance"."merge_operations" FOR EACH ROW EXECUTE FUNCTION infrastructure.touch_row();

ALTER TABLE "governance"."merge_operations" ADD CONSTRAINT "c_25ff1413d9631bf1453d" CHECK (source_id <> target_id);

CREATE TABLE "delivery"."engagements" (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "code" text NOT NULL,
  "customer_organization_id" uuid NOT NULL,
  "provider_organization_id" uuid NOT NULL,
  "opportunity_id" uuid,
  "contract_version_id" uuid,
  "owner_id" uuid NOT NULL,
  "title" text NOT NULL,
  "status" text NOT NULL,
  "starts_on" date,
  "ends_on" date,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  row_version bigint NOT NULL DEFAULT 1 CHECK (row_version > 0)
);

COMMENT ON TABLE "delivery"."engagements" IS 'Missions client vendues ou en préparation | Catalogue: Code unique par prestataire ; draft/approved/in_progress/completed/cancelled ; approbation liée à une preuve d’accord ; couverture client vérifiée dans la version de contrat ; dates ordonnées.';

ALTER TABLE "delivery"."engagements" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "delivery"."engagements" FORCE ROW LEVEL SECURITY;

CREATE TRIGGER z_touch BEFORE UPDATE ON "delivery"."engagements" FOR EACH ROW EXECUTE FUNCTION infrastructure.touch_row();

ALTER TABLE "delivery"."engagements" ADD CONSTRAINT "c_c090f8093c050ada59ba" CHECK ("ends_on" >= "starts_on");

ALTER TABLE "delivery"."engagements" ADD CONSTRAINT "c_933ea821fa2f9a082600" CHECK ("status" IN ('draft', 'approved', 'in_progress', 'completed', 'cancelled'));

ALTER TABLE "delivery"."engagements" ADD CONSTRAINT "c_f2d87aaf41ddb2bc88b4" UNIQUE NULLS NOT DISTINCT ("provider_organization_id", "code");

CREATE TABLE "delivery"."engagement_lines" (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "engagement_id" uuid NOT NULL,
  "product_id" uuid NOT NULL,
  "source_quote_line_id" uuid,
  "contract_component_id" uuid,
  "description" text NOT NULL,
  "quantity" numeric(20,6) NOT NULL,
  "unit" text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  row_version bigint NOT NULL DEFAULT 1 CHECK (row_version > 0)
);

COMMENT ON TABLE "delivery"."engagement_lines" IS 'Périmètre de prestation accepté | Catalogue: Quantité positive ; ligne de devis cohérente avec le client ; composant appartenant à la version du contrat de la mission. Périmètre approuvé figé ; modifications par avenant.';

ALTER TABLE "delivery"."engagement_lines" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "delivery"."engagement_lines" FORCE ROW LEVEL SECURITY;

CREATE TRIGGER z_touch BEFORE UPDATE ON "delivery"."engagement_lines" FOR EACH ROW EXECUTE FUNCTION infrastructure.touch_row();

ALTER TABLE "delivery"."engagement_lines" ADD CONSTRAINT "c_4f39f8467d5f08470af3" CHECK ("quantity" <> 'NaN'::numeric);

ALTER TABLE "delivery"."engagement_lines" ADD CONSTRAINT "c_e529b23ba527e1315d79" CHECK ("quantity" > 0);

CREATE TABLE "delivery"."service_instances" (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "engagement_line_id" uuid NOT NULL,
  "customer_organization_id" uuid NOT NULL,
  "site_id" uuid,
  "name" text NOT NULL,
  "status" text NOT NULL,
  "owner_id" uuid,
  "activated_at" timestamptz,
  "retired_at" timestamptz,
  "external_installation_key" text,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  row_version bigint NOT NULL DEFAULT 1 CHECK (row_version > 0)
);

COMMENT ON TABLE "delivery"."service_instances" IS 'Services réellement fournis à un client | Catalogue: Client identique à la mission ; site de ce client ; planned/active/suspended/retired ; retraite après activation. Clé SaaS externe sans FK interbase. Couverture contractuelle résolue par les versions applicables.';

ALTER TABLE "delivery"."service_instances" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "delivery"."service_instances" FORCE ROW LEVEL SECURITY;

CREATE TRIGGER z_touch BEFORE UPDATE ON "delivery"."service_instances" FOR EACH ROW EXECUTE FUNCTION infrastructure.touch_row();

ALTER TABLE "delivery"."service_instances" ADD CONSTRAINT "c_8f8f7c6a4ef0e4fc2719" CHECK ("retired_at" >= "activated_at");

ALTER TABLE "delivery"."service_instances" ADD CONSTRAINT "c_b99ccb039bad34f3d18d" CHECK ("status" IN ('planned', 'active', 'suspended', 'retired'));

CREATE TABLE "delivery"."service_instance_assets" (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "service_instance_id" uuid NOT NULL,
  "item_id" uuid NOT NULL,
  "relation_kind" text NOT NULL,
  "valid_from" timestamptz NOT NULL,
  "valid_to" timestamptz,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  row_version bigint NOT NULL DEFAULT 1 CHECK (row_version > 0)
);

COMMENT ON TABLE "delivery"."service_instance_assets" IS 'Composants techniques d’un service | Catalogue: Lien daté unique sans chevauchement pour le même type ; propriété ou mandat valide sur l’actif. Autoriser infrastructure mutualisée uniquement avec mandat explicite.';

ALTER TABLE "delivery"."service_instance_assets" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "delivery"."service_instance_assets" FORCE ROW LEVEL SECURITY;

CREATE TRIGGER z_touch BEFORE UPDATE ON "delivery"."service_instance_assets" FOR EACH ROW EXECUTE FUNCTION infrastructure.touch_row();

ALTER TABLE "delivery"."service_instance_assets" ADD CONSTRAINT "c_4c7523882a2711fa21f5" CHECK ("valid_to" >= "valid_from");

CREATE TABLE "delivery"."service_instance_projects" (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "service_instance_id" uuid NOT NULL,
  "project_id" uuid NOT NULL,
  "relation_kind" text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  row_version bigint NOT NULL DEFAULT 1 CHECK (row_version > 0)
);

COMMENT ON TABLE "delivery"."service_instance_projects" IS 'Projets de réalisation ou évolution du service | Catalogue: Triplet unique ; client du projet cohérent avec celui du service ou partie explicitement autorisée ; ne donne pas automatiquement accès au projet.';

ALTER TABLE "delivery"."service_instance_projects" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "delivery"."service_instance_projects" FORCE ROW LEVEL SECURITY;

CREATE TRIGGER z_touch BEFORE UPDATE ON "delivery"."service_instance_projects" FOR EACH ROW EXECUTE FUNCTION infrastructure.touch_row();

ALTER TABLE "delivery"."service_instance_projects" ADD CONSTRAINT "c_2b1980aa5b24af48aa02" UNIQUE NULLS NOT DISTINCT ("service_instance_id", "project_id", "relation_kind");

CREATE TABLE "delivery"."service_instance_tickets" (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "service_instance_id" uuid NOT NULL,
  "ticket_id" uuid NOT NULL,
  "relation_kind" text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  row_version bigint NOT NULL DEFAULT 1 CHECK (row_version > 0)
);

COMMENT ON TABLE "delivery"."service_instance_tickets" IS 'Incidents et demandes liés au service | Catalogue: Triplet unique ; société concernée du ticket compatible avec le service et sa couverture. Les pièces et messages conservent leurs propres droits.';

ALTER TABLE "delivery"."service_instance_tickets" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "delivery"."service_instance_tickets" FORCE ROW LEVEL SECURITY;

CREATE TRIGGER z_touch BEFORE UPDATE ON "delivery"."service_instance_tickets" FOR EACH ROW EXECUTE FUNCTION infrastructure.touch_row();

ALTER TABLE "delivery"."service_instance_tickets" ADD CONSTRAINT "c_8efa38c480b12704423b" UNIQUE NULLS NOT DISTINCT ("service_instance_id", "ticket_id", "relation_kind");

CREATE TABLE "delivery"."change_orders" (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "engagement_id" uuid NOT NULL,
  "number" text NOT NULL,
  "description" text NOT NULL,
  "status" text NOT NULL,
  "proposed_contract_version_id" uuid,
  "approval_request_id" uuid,
  "effective_at" timestamptz,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  row_version bigint NOT NULL DEFAULT 1 CHECK (row_version > 0)
);

COMMENT ON TABLE "delivery"."change_orders" IS 'Évolutions du périmètre d’une mission | Catalogue: Numéro unique par mission ; requested/quoted/approved/rejected/applied ; application une seule fois après approbation ; avenant lié au même contrat/client ; ne réécrit pas la mission historique.';

ALTER TABLE "delivery"."change_orders" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "delivery"."change_orders" FORCE ROW LEVEL SECURITY;

CREATE TRIGGER z_touch BEFORE UPDATE ON "delivery"."change_orders" FOR EACH ROW EXECUTE FUNCTION infrastructure.touch_row();

ALTER TABLE "delivery"."change_orders" ADD CONSTRAINT "c_bc18988c17062cc67672" CHECK ("status" IN ('requested', 'quoted', 'approved', 'rejected', 'applied'));

ALTER TABLE "delivery"."change_orders" ADD CONSTRAINT "c_e7b418aa485b4b3bb138" UNIQUE NULLS NOT DISTINCT ("engagement_id", "number");

CREATE TABLE "delivery"."acceptance_criteria" (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "engagement_line_id" uuid NOT NULL,
  "description" text NOT NULL,
  "evidence_document_id" uuid,
  "acceptance_id" uuid,
  "status" text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  row_version bigint NOT NULL DEFAULT 1 CHECK (row_version > 0)
);

COMMENT ON TABLE "delivery"."acceptance_criteria" IS 'Critères vérifiables de recette | Catalogue: pending/passed/failed/waived ; dérogation motivée dans la décision de recette ; acceptation d’un projet rattaché à la même mission ; critère accepté non réécrit.';

ALTER TABLE "delivery"."acceptance_criteria" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "delivery"."acceptance_criteria" FORCE ROW LEVEL SECURITY;

CREATE TRIGGER z_touch BEFORE UPDATE ON "delivery"."acceptance_criteria" FOR EACH ROW EXECUTE FUNCTION infrastructure.touch_row();

ALTER TABLE "delivery"."acceptance_criteria" ADD CONSTRAINT "c_62c435883ac69b0cff9e" CHECK ("status" IN ('pending', 'passed', 'failed', 'waived'));

CREATE TABLE "delivery"."handovers" (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "service_instance_id" uuid NOT NULL,
  "recipient_affiliation_id" uuid NOT NULL,
  "document_version_id" uuid NOT NULL,
  "handed_over_by" uuid NOT NULL,
  "handed_over_at" timestamptz NOT NULL,
  "acceptance_id" uuid,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  row_version bigint NOT NULL DEFAULT 1 CHECK (row_version > 0)
);

COMMENT ON TABLE "delivery"."handovers" IS 'Passations au client ou à l’exploitation | Catalogue: Destinataire autorisé dans le contexte du client ; version documentaire exacte, immuable et accessible ; aucun secret copié ; passation distincte de l’acceptation contractuelle.';

ALTER TABLE "delivery"."handovers" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "delivery"."handovers" FORCE ROW LEVEL SECURITY;

CREATE TRIGGER z_touch BEFORE UPDATE ON "delivery"."handovers" FOR EACH ROW EXECUTE FUNCTION infrastructure.touch_row();

CREATE TRIGGER a_immutable BEFORE UPDATE OR DELETE ON "delivery"."handovers" FOR EACH ROW EXECUTE FUNCTION infrastructure.reject_mutation();

CREATE TRIGGER a_no_truncate BEFORE TRUNCATE ON "delivery"."handovers" FOR EACH STATEMENT EXECUTE FUNCTION infrastructure.reject_mutation();

CREATE TABLE "studio"."websites" (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "service_instance_id" uuid NOT NULL,
  "primary_domain_id" uuid,
  "name" text NOT NULL,
  "cms_name" text,
  "repository_url" text,
  "status" text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  row_version bigint NOT NULL DEFAULT 1 CHECK (row_version > 0)
);

COMMENT ON TABLE "studio"."websites" IS 'Sites web clients livrés | Catalogue: Une fiche par instance de service web ; domaines sous propriété ou mandat autorisé ; repository_url sans token ; état cohérent avec le service.';

ALTER TABLE "studio"."websites" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "studio"."websites" FORCE ROW LEVEL SECURITY;

CREATE TRIGGER z_touch BEFORE UPDATE ON "studio"."websites" FOR EACH ROW EXECUTE FUNCTION infrastructure.touch_row();

ALTER TABLE "studio"."websites" ADD CONSTRAINT "c_70a7c505da68354ba524" UNIQUE NULLS NOT DISTINCT ("service_instance_id");

CREATE TABLE "studio"."website_environments" (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "website_id" uuid NOT NULL,
  "code" text NOT NULL,
  "kind" text NOT NULL,
  "url" text NOT NULL,
  "hosting_service_id" uuid,
  "secret_ref" text,
  "active" boolean NOT NULL,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  row_version bigint NOT NULL DEFAULT 1 CHECK (row_version > 0)
);

COMMENT ON TABLE "studio"."website_environments" IS 'Environnements de chaque site client | Catalogue: Code unique par site ; production/staging/development ; hébergement cohérent avec le mandat ; secret_ref est une référence au coffre, jamais un secret.';

ALTER TABLE "studio"."website_environments" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "studio"."website_environments" FORCE ROW LEVEL SECURITY;

CREATE TRIGGER z_touch BEFORE UPDATE ON "studio"."website_environments" FOR EACH ROW EXECUTE FUNCTION infrastructure.touch_row();

ALTER TABLE "studio"."website_environments" ADD CONSTRAINT "c_8ef28227b98cb2d085f0" CHECK ("kind" IN ('production', 'staging', 'development'));

ALTER TABLE "studio"."website_environments" ADD CONSTRAINT "c_796f41f7cebe2b285c6d" UNIQUE NULLS NOT DISTINCT ("website_id", "code");

CREATE TABLE "studio"."website_releases" (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "environment_id" uuid NOT NULL,
  "release_key" text NOT NULL,
  "commit_ref" text,
  "deployed_at" timestamptz NOT NULL,
  "deployed_by" uuid NOT NULL,
  "change_ticket_id" uuid,
  "previous_release_id" uuid,
  "status" text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  row_version bigint NOT NULL DEFAULT 1 CHECK (row_version > 0)
);

COMMENT ON TABLE "studio"."website_releases" IS 'Historique de déploiement des sites | Catalogue: Clé unique par environnement ; prédécesseur du même environnement ; journal immuable, rollback par nouvel événement ; résultat succeeded/failed/rolled_back ; ticket du client concerné.';

ALTER TABLE "studio"."website_releases" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "studio"."website_releases" FORCE ROW LEVEL SECURITY;

CREATE TRIGGER z_touch BEFORE UPDATE ON "studio"."website_releases" FOR EACH ROW EXECUTE FUNCTION infrastructure.touch_row();

CREATE TRIGGER a_immutable BEFORE UPDATE OR DELETE ON "studio"."website_releases" FOR EACH ROW EXECUTE FUNCTION infrastructure.reject_mutation();

CREATE TRIGGER a_no_truncate BEFORE TRUNCATE ON "studio"."website_releases" FOR EACH STATEMENT EXECUTE FUNCTION infrastructure.reject_mutation();

ALTER TABLE "studio"."website_releases" ADD CONSTRAINT "c_c7e5af7c8e6a15961019" CHECK ("status" IN ('succeeded', 'failed', 'rolled_back'));

ALTER TABLE "studio"."website_releases" ADD CONSTRAINT "c_0f683847773d31a04c3e" UNIQUE NULLS NOT DISTINCT ("environment_id", "release_key");

CREATE TABLE "studio"."maintenance_plans" (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "website_id" uuid NOT NULL,
  "version_no" integer NOT NULL,
  "contract_component_id" uuid,
  "frequency_rule" text NOT NULL,
  "checks_schema" jsonb NOT NULL,
  "valid_from" timestamptz NOT NULL,
  "valid_to" timestamptz,
  "status" text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  row_version bigint NOT NULL DEFAULT 1 CHECK (row_version > 0)
);

COMMENT ON TABLE "studio"."maintenance_plans" IS 'Configurations versionnées de maintenance | Catalogue: Version unique par site ; schéma des contrôles validé et versionné ; politique publiée figée ; fenêtres actives non chevauchantes ; composant commercial couvrant ce client.';

ALTER TABLE "studio"."maintenance_plans" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "studio"."maintenance_plans" FORCE ROW LEVEL SECURITY;

CREATE TRIGGER z_touch BEFORE UPDATE ON "studio"."maintenance_plans" FOR EACH ROW EXECUTE FUNCTION infrastructure.touch_row();

ALTER TABLE "studio"."maintenance_plans" ADD CONSTRAINT "c_bfb14df9fec21a3a6e4d" CHECK ("version_no" > 0);

ALTER TABLE "studio"."maintenance_plans" ADD CONSTRAINT "c_3f0de96e1cebaf503102" CHECK ("valid_to" >= "valid_from");

ALTER TABLE "studio"."maintenance_plans" ADD CONSTRAINT "c_a82fcc54c939418d30e7" UNIQUE NULLS NOT DISTINCT ("website_id", "version_no");

CREATE TABLE "studio"."maintenance_runs" (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "plan_id" uuid NOT NULL,
  "scheduled_at" timestamptz NOT NULL,
  "started_at" timestamptz,
  "finished_at" timestamptz,
  "intervention_id" uuid,
  "report_version_id" uuid,
  "status" text NOT NULL,
  "idempotency_key" text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  row_version bigint NOT NULL DEFAULT 1 CHECK (row_version > 0)
);

COMMENT ON TABLE "studio"."maintenance_runs" IS 'Résultats d’opérations de maintenance | Catalogue: Clé unique ; ordre des dates ; queued/running/succeeded/failed/cancelled ; intervention et rapport du périmètre client ; un rapport final ne se réécrit pas.';

ALTER TABLE "studio"."maintenance_runs" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "studio"."maintenance_runs" FORCE ROW LEVEL SECURITY;

CREATE TRIGGER z_touch BEFORE UPDATE ON "studio"."maintenance_runs" FOR EACH ROW EXECUTE FUNCTION infrastructure.touch_row();

ALTER TABLE "studio"."maintenance_runs" ADD CONSTRAINT "c_e02d6263fcac28f6c7ba" CHECK ("finished_at" >= "started_at");

ALTER TABLE "studio"."maintenance_runs" ADD CONSTRAINT "c_383f5f7d39b457c39f9d" CHECK ("status" IN ('queued', 'running', 'succeeded', 'failed', 'cancelled'));

ALTER TABLE "studio"."maintenance_runs" ADD CONSTRAINT "c_e981c79e0870d24f68a4" UNIQUE NULLS NOT DISTINCT ("idempotency_key");

CREATE TABLE "advisory"."assessments" (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "engagement_id" uuid NOT NULL,
  "version_no" integer NOT NULL,
  "title" text NOT NULL,
  "scope" text NOT NULL,
  "methodology_version" text NOT NULL,
  "assessed_at" timestamptz,
  "assessor_id" uuid NOT NULL,
  "report_version_id" uuid,
  "status" text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  row_version bigint NOT NULL DEFAULT 1 CHECK (row_version > 0)
);

COMMENT ON TABLE "advisory"."assessments" IS 'Évaluations et audits de conseil | Catalogue: Version positive unique par mission ; draft/final/superseded ; rapport final figé avec ses constats ; nouvelle évaluation par nouvelle version.';

ALTER TABLE "advisory"."assessments" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "advisory"."assessments" FORCE ROW LEVEL SECURITY;

CREATE TRIGGER z_touch BEFORE UPDATE ON "advisory"."assessments" FOR EACH ROW EXECUTE FUNCTION infrastructure.touch_row();

ALTER TABLE "advisory"."assessments" ADD CONSTRAINT "c_f3b6260d535496785978" CHECK ("version_no" > 0);

ALTER TABLE "advisory"."assessments" ADD CONSTRAINT "c_541f012038ca524f51bf" CHECK ("status" IN ('draft', 'final', 'superseded'));

ALTER TABLE "advisory"."assessments" ADD CONSTRAINT "c_c7de2be8b80d9fd824ee" UNIQUE NULLS NOT DISTINCT ("engagement_id", "version_no");

CREATE TABLE "advisory"."findings" (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "assessment_id" uuid NOT NULL,
  "title" text NOT NULL,
  "description" text NOT NULL,
  "severity" text NOT NULL,
  "observed_at" timestamptz NOT NULL,
  "evidence_version_id" uuid,
  "item_id" uuid,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  row_version bigint NOT NULL DEFAULT 1 CHECK (row_version > 0)
);

COMMENT ON TABLE "advisory"."findings" IS 'Constats de conseil étayés | Catalogue: Preuve et actif du périmètre de la mission ; sévérité normalisée ; preuve ou justification exigée avant finalisation ; immuable avec l’évaluation finalisée.';

ALTER TABLE "advisory"."findings" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "advisory"."findings" FORCE ROW LEVEL SECURITY;

CREATE TRIGGER z_touch BEFORE UPDATE ON "advisory"."findings" FOR EACH ROW EXECUTE FUNCTION infrastructure.touch_row();

CREATE TABLE "advisory"."recommendations" (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "finding_id" uuid NOT NULL,
  "description" text NOT NULL,
  "priority" integer NOT NULL,
  "estimated_cost" numeric(20,6),
  "currency" text,
  "expected_outcome" text NOT NULL,
  "decision" text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  row_version bigint NOT NULL DEFAULT 1 CHECK (row_version > 0)
);

COMMENT ON TABLE "advisory"."recommendations" IS 'Recommandations reliées aux constats | Catalogue: Priorité positive ; coût non négatif ; coût et devise présents ensemble ; proposed/accepted/rejected/deferred ; décision auditée, sans réécrire le constat.';

ALTER TABLE "advisory"."recommendations" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "advisory"."recommendations" FORCE ROW LEVEL SECURITY;

CREATE TRIGGER z_touch BEFORE UPDATE ON "advisory"."recommendations" FOR EACH ROW EXECUTE FUNCTION infrastructure.touch_row();

ALTER TABLE "advisory"."recommendations" ADD CONSTRAINT "c_423e65a85a32bd993946" CHECK ("priority" > 0);

ALTER TABLE "advisory"."recommendations" ADD CONSTRAINT "c_57fb4da922d4f38e320a" CHECK ("estimated_cost" <> 'NaN'::numeric);

ALTER TABLE "advisory"."recommendations" ADD CONSTRAINT "c_b1cc27496a3a35208d7b" CHECK ("estimated_cost" >= 0);

ALTER TABLE "advisory"."recommendations" ADD CONSTRAINT "c_b49386f8f26938c8ff62" CHECK ("decision" IN ('proposed', 'accepted', 'rejected', 'deferred'));

ALTER TABLE "advisory"."recommendations" ADD CONSTRAINT "c_b538b82d9ce0e1e4ec66" CHECK ((estimated_cost IS NULL) = (currency IS NULL));

CREATE TABLE "advisory"."roadmap_items" (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "recommendation_id" uuid NOT NULL,
  "task_id" uuid,
  "owner_affiliation_id" uuid,
  "target_on" date,
  "status" text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  row_version bigint NOT NULL DEFAULT 1 CHECK (row_version > 0)
);

COMMENT ON TABLE "advisory"."roadmap_items" IS 'Mise en œuvre des recommandations | Catalogue: Tâche et responsable autorisés sur le client de la mission ; planned/in_progress/done/cancelled ; une recommandation peut produire plusieurs actions.';

ALTER TABLE "advisory"."roadmap_items" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "advisory"."roadmap_items" FORCE ROW LEVEL SECURITY;

CREATE TRIGGER z_touch BEFORE UPDATE ON "advisory"."roadmap_items" FOR EACH ROW EXECUTE FUNCTION infrastructure.touch_row();

ALTER TABLE "advisory"."roadmap_items" ADD CONSTRAINT "c_50aca9238727e3e00cff" CHECK ("status" IN ('planned', 'in_progress', 'done', 'cancelled'));

CREATE TABLE "success"."customer_plans" (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "organization_id" uuid NOT NULL,
  "owner_id" uuid NOT NULL,
  "title" text NOT NULL,
  "starts_on" date NOT NULL,
  "ends_on" date,
  "status" text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  row_version bigint NOT NULL DEFAULT 1 CHECK (row_version > 0)
);

COMMENT ON TABLE "success"."customer_plans" IS 'Plans d’accompagnement client | Catalogue: Dates ordonnées ; draft/active/completed/archived ; responsable habilité ; pas de copie du compte CRM.';

ALTER TABLE "success"."customer_plans" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "success"."customer_plans" FORCE ROW LEVEL SECURITY;

CREATE TRIGGER z_touch BEFORE UPDATE ON "success"."customer_plans" FOR EACH ROW EXECUTE FUNCTION infrastructure.touch_row();

ALTER TABLE "success"."customer_plans" ADD CONSTRAINT "c_d1e3b6254dbbfc9fe27b" CHECK ("ends_on" >= "starts_on");

ALTER TABLE "success"."customer_plans" ADD CONSTRAINT "c_315deb39b1b339828a51" CHECK ("status" IN ('draft', 'active', 'completed', 'archived'));

CREATE TABLE "success"."objectives" (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "plan_id" uuid NOT NULL,
  "name" text NOT NULL,
  "metric_definition_id" uuid,
  "unit" text NOT NULL,
  "baseline" numeric(20,6),
  "target" numeric(20,6),
  "target_on" date,
  "status" text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  row_version bigint NOT NULL DEFAULT 1 CHECK (row_version > 0)
);

COMMENT ON TABLE "success"."objectives" IS 'Objectifs mesurables du client | Catalogue: Unité cohérente avec l’indicateur ; objectif qualitatif possible avec valeurs numériques NULL ; calcul actuel dans le reporting, pas une valeur opaque dupliquée.';

ALTER TABLE "success"."objectives" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "success"."objectives" FORCE ROW LEVEL SECURITY;

CREATE TRIGGER z_touch BEFORE UPDATE ON "success"."objectives" FOR EACH ROW EXECUTE FUNCTION infrastructure.touch_row();

ALTER TABLE "success"."objectives" ADD CONSTRAINT "c_49abab3c51e715af9640" CHECK ("baseline" <> 'NaN'::numeric);

ALTER TABLE "success"."objectives" ADD CONSTRAINT "c_c93caceabf015398d2ba" CHECK ("target" <> 'NaN'::numeric);

CREATE TABLE "success"."reviews" (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "plan_id" uuid NOT NULL,
  "held_at" timestamptz NOT NULL,
  "author_id" uuid NOT NULL,
  "report_version_id" uuid,
  "assessment" text NOT NULL,
  "next_review_on" date,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  row_version bigint NOT NULL DEFAULT 1 CHECK (row_version > 0)
);

COMMENT ON TABLE "success"."reviews" IS 'Revues de service documentées | Catalogue: Rapport et participants dans le périmètre client ; synthèse sourcée ; prochaine date non antérieure à la revue ; modifications historisées.';

ALTER TABLE "success"."reviews" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "success"."reviews" FORCE ROW LEVEL SECURITY;

CREATE TRIGGER z_touch BEFORE UPDATE ON "success"."reviews" FOR EACH ROW EXECUTE FUNCTION infrastructure.touch_row();

CREATE TABLE "success"."renewal_cases" (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "organization_id" uuid NOT NULL,
  "contract_id" uuid NOT NULL,
  "opportunity_id" uuid,
  "owner_id" uuid NOT NULL,
  "due_on" date NOT NULL,
  "status" text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  row_version bigint NOT NULL DEFAULT 1 CHECK (row_version > 0)
);

COMMENT ON TABLE "success"."renewal_cases" IS 'Préparation des renouvellements | Catalogue: Contrat couvrant le client ; opportunité compatible ; unicité contrat/client/échéance ; open/qualified/renewed/lost/cancelled ; pas de renouvellement financier automatique.';

ALTER TABLE "success"."renewal_cases" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "success"."renewal_cases" FORCE ROW LEVEL SECURITY;

CREATE TRIGGER z_touch BEFORE UPDATE ON "success"."renewal_cases" FOR EACH ROW EXECUTE FUNCTION infrastructure.touch_row();

ALTER TABLE "success"."renewal_cases" ADD CONSTRAINT "c_ea2add94192f629b467b" CHECK ("status" IN ('open', 'qualified', 'renewed', 'lost', 'cancelled'));

ALTER TABLE "success"."renewal_cases" ADD CONSTRAINT "c_828745b3dc0c4dc755b0" UNIQUE NULLS NOT DISTINCT ("organization_id", "contract_id", "due_on");

CREATE TABLE "ai"."assistants" (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "code" text NOT NULL,
  "name" text NOT NULL,
  "purpose" text NOT NULL,
  "owner_id" uuid NOT NULL,
  "active" boolean NOT NULL,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  row_version bigint NOT NULL DEFAULT 1 CHECK (row_version > 0)
);

COMMENT ON TABLE "ai"."assistants" IS 'Assistants autorisés par finalité | Catalogue: Code unique par installation ; activation explicite ; aucun droit implicite du fait de l’existence d’un assistant.';

ALTER TABLE "ai"."assistants" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "ai"."assistants" FORCE ROW LEVEL SECURITY;

CREATE TRIGGER z_touch BEFORE UPDATE ON "ai"."assistants" FOR EACH ROW EXECUTE FUNCTION infrastructure.touch_row();

ALTER TABLE "ai"."assistants" ADD CONSTRAINT "c_ab5284957942394f4c61" UNIQUE NULLS NOT DISTINCT ("code");

CREATE TABLE "ai"."assistant_versions" (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "assistant_id" uuid NOT NULL,
  "version_no" integer NOT NULL,
  "provider" text NOT NULL,
  "model" text NOT NULL,
  "instructions_version_id" uuid NOT NULL,
  "config" jsonb NOT NULL,
  "status" text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  row_version bigint NOT NULL DEFAULT 1 CHECK (row_version > 0)
);

COMMENT ON TABLE "ai"."assistant_versions" IS 'Configurations d’assistants versionnées | Catalogue: Version positive unique ; configuration validée sans secret ; draft/published/retired ; version publiée immuable ; outils autorisés listés explicitement.';

ALTER TABLE "ai"."assistant_versions" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "ai"."assistant_versions" FORCE ROW LEVEL SECURITY;

CREATE TRIGGER z_touch BEFORE UPDATE ON "ai"."assistant_versions" FOR EACH ROW EXECUTE FUNCTION infrastructure.touch_row();

ALTER TABLE "ai"."assistant_versions" ADD CONSTRAINT "c_0f213037dcf1e1071e13" CHECK ("version_no" > 0);

ALTER TABLE "ai"."assistant_versions" ADD CONSTRAINT "c_0d876ff0c4cb6afd98ce" CHECK ("status" IN ('draft', 'published', 'retired'));

ALTER TABLE "ai"."assistant_versions" ADD CONSTRAINT "c_74849b90f2db3e677039" UNIQUE NULLS NOT DISTINCT ("assistant_id", "version_no");

CREATE TABLE "ai"."runs" (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "assistant_version_id" uuid NOT NULL,
  "actor_id" uuid NOT NULL,
  "organization_id" uuid,
  "started_at" timestamptz NOT NULL,
  "finished_at" timestamptz,
  "status" text NOT NULL,
  "correlation_id" text NOT NULL,
  "input_document_version_id" uuid,
  "output_document_version_id" uuid,
  "input_tokens" bigint,
  "output_tokens" bigint,
  "cost_amount" numeric(20,6),
  "currency" text,
  "cost_status" text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  row_version bigint NOT NULL DEFAULT 1 CHECK (row_version > 0)
);

COMMENT ON TABLE "ai"."runs" IS 'Exécutions d’assistants traçables | Catalogue: Identité et périmètre validés côté serveur ; dates ordonnées ; compteurs/coût non négatifs ; coût et devise cohérents ; unknown/estimated/confirmed pour le coût ; entrée brute non conservée par défaut.';

ALTER TABLE "ai"."runs" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "ai"."runs" FORCE ROW LEVEL SECURITY;

CREATE TRIGGER z_touch BEFORE UPDATE ON "ai"."runs" FOR EACH ROW EXECUTE FUNCTION infrastructure.touch_row();

ALTER TABLE "ai"."runs" ADD CONSTRAINT "c_b20946ef92933881a0b3" CHECK ("input_tokens" >= 0);

ALTER TABLE "ai"."runs" ADD CONSTRAINT "c_d939a4024cefa9d465d4" CHECK ("output_tokens" >= 0);

ALTER TABLE "ai"."runs" ADD CONSTRAINT "c_c3e5ba0f61ec6bf0aaad" CHECK ("cost_amount" <> 'NaN'::numeric);

ALTER TABLE "ai"."runs" ADD CONSTRAINT "c_25e3944e53e2210b6c51" CHECK ("cost_amount" >= 0);

ALTER TABLE "ai"."runs" ADD CONSTRAINT "c_97ff01ff260b1bceb05c" CHECK ("finished_at" >= "started_at");

ALTER TABLE "ai"."runs" ADD CONSTRAINT "c_34fc266460cda6d48721" CHECK ("cost_status" IN ('unknown', 'estimated', 'confirmed'));

ALTER TABLE "ai"."runs" ADD CONSTRAINT "c_50a3ddc43848b0eaa54f" CHECK ((cost_amount IS NULL) = (currency IS NULL));

CREATE TABLE "ai"."run_sources" (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "run_id" uuid NOT NULL,
  "document_version_id" uuid,
  "article_version_id" uuid,
  "locator" text,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  row_version bigint NOT NULL DEFAULT 1 CHECK (row_version > 0)
);

COMMENT ON TABLE "ai"."run_sources" IS 'Versions exactes des sources utilisées | Catalogue: Exactement une source document ou article ; accès vérifié au moment de la recherche et de la consultation ; suppression ou restriction répercutée sur index et caches.';

ALTER TABLE "ai"."run_sources" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "ai"."run_sources" FORCE ROW LEVEL SECURITY;

CREATE TRIGGER z_touch BEFORE UPDATE ON "ai"."run_sources" FOR EACH ROW EXECUTE FUNCTION infrastructure.touch_row();

ALTER TABLE "ai"."run_sources" ADD CONSTRAINT "c_d247ebc9e33b1edfb616" CHECK (num_nonnulls(document_version_id, article_version_id) = 1);

CREATE TABLE "ai"."action_proposals" (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "run_id" uuid NOT NULL,
  "action_type" text NOT NULL,
  "target_type" text NOT NULL,
  "target_id" uuid NOT NULL,
  "expected_row_version" bigint,
  "payload" jsonb NOT NULL,
  "payload_hash" text NOT NULL,
  "expires_at" timestamptz NOT NULL,
  "idempotency_key" text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  row_version bigint NOT NULL DEFAULT 1 CHECK (row_version > 0)
);

COMMENT ON TABLE "ai"."action_proposals" IS 'Actions proposées, sans exécution implicite | Catalogue: Proposition immuable ; clé unique ; cible typée validée par registre fermé dans l’API ; payload versionné et empreinte canonique ; autorisations et état recontrôlés à l’exécution.';

ALTER TABLE "ai"."action_proposals" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "ai"."action_proposals" FORCE ROW LEVEL SECURITY;

CREATE TRIGGER z_touch BEFORE UPDATE ON "ai"."action_proposals" FOR EACH ROW EXECUTE FUNCTION infrastructure.touch_row();

CREATE TRIGGER a_immutable BEFORE UPDATE OR DELETE ON "ai"."action_proposals" FOR EACH ROW EXECUTE FUNCTION infrastructure.reject_mutation();

CREATE TRIGGER a_no_truncate BEFORE TRUNCATE ON "ai"."action_proposals" FOR EACH STATEMENT EXECUTE FUNCTION infrastructure.reject_mutation();

ALTER TABLE "ai"."action_proposals" ADD CONSTRAINT "c_a2d888890f735180e77e" CHECK ("expected_row_version" > 0);

ALTER TABLE "ai"."action_proposals" ADD CONSTRAINT "c_296b9582f9429e0924cf" UNIQUE NULLS NOT DISTINCT ("idempotency_key");

CREATE TABLE "ai"."action_decisions" (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "proposal_id" uuid NOT NULL,
  "decided_by" uuid NOT NULL,
  "decision" text NOT NULL,
  "reason" text,
  "decided_at" timestamptz NOT NULL,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  row_version bigint NOT NULL DEFAULT 1 CHECK (row_version > 0)
);

COMMENT ON TABLE "ai"."action_decisions" IS 'Approbations ou refus d’actions proposées | Catalogue: Une décision finale par proposition ; approve/reject ; acteur habilité ; proposition non expirée ; aucune auto-approbation implicite ; décision journalisée et immuable.';

ALTER TABLE "ai"."action_decisions" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "ai"."action_decisions" FORCE ROW LEVEL SECURITY;

CREATE TRIGGER z_touch BEFORE UPDATE ON "ai"."action_decisions" FOR EACH ROW EXECUTE FUNCTION infrastructure.touch_row();

CREATE TRIGGER a_immutable BEFORE UPDATE OR DELETE ON "ai"."action_decisions" FOR EACH ROW EXECUTE FUNCTION infrastructure.reject_mutation();

CREATE TRIGGER a_no_truncate BEFORE TRUNCATE ON "ai"."action_decisions" FOR EACH STATEMENT EXECUTE FUNCTION infrastructure.reject_mutation();

ALTER TABLE "ai"."action_decisions" ADD CONSTRAINT "c_894e0d50c9048509c454" CHECK ("decision" IN ('approve', 'reject'));

ALTER TABLE "ai"."action_decisions" ADD CONSTRAINT "c_4d656bf1cca5bd69060e" UNIQUE NULLS NOT DISTINCT ("proposal_id");

CREATE TABLE "ai"."evaluation_cases" (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "assistant_id" uuid NOT NULL,
  "case_key" text NOT NULL,
  "version_no" integer NOT NULL,
  "input_version_id" uuid NOT NULL,
  "criteria" jsonb NOT NULL,
  "active" boolean NOT NULL,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  row_version bigint NOT NULL DEFAULT 1 CHECK (row_version > 0)
);

COMMENT ON TABLE "ai"."evaluation_cases" IS 'Cas de référence pour évaluer un assistant | Catalogue: Clé/version unique par assistant ; critères validés, sources autorisées et anonymisées selon besoin ; cas versionné ; pas de données d’un autre abonné.';

ALTER TABLE "ai"."evaluation_cases" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "ai"."evaluation_cases" FORCE ROW LEVEL SECURITY;

CREATE TRIGGER z_touch BEFORE UPDATE ON "ai"."evaluation_cases" FOR EACH ROW EXECUTE FUNCTION infrastructure.touch_row();

ALTER TABLE "ai"."evaluation_cases" ADD CONSTRAINT "c_ae0da9c77e685fc9e8b0" CHECK ("version_no" > 0);

ALTER TABLE "ai"."evaluation_cases" ADD CONSTRAINT "c_6b1e322841f7d2127a1d" UNIQUE NULLS NOT DISTINCT ("assistant_id", "case_key", "version_no");

CREATE TABLE "ai"."evaluation_results" (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "case_id" uuid NOT NULL,
  "run_id" uuid NOT NULL,
  "evaluated_at" timestamptz NOT NULL,
  "evaluator_version" text NOT NULL,
  "score" numeric(20,6),
  "passed" boolean NOT NULL,
  "evidence_version_id" uuid,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  row_version bigint NOT NULL DEFAULT 1 CHECK (row_version > 0)
);

COMMENT ON TABLE "ai"."evaluation_results" IS 'Résultats reproductibles des évaluations | Catalogue: Exécution du même assistant que le cas ; barème porté par le cas ; résultat immuable et évaluateur identifié ; score NULL si non applicable.';

ALTER TABLE "ai"."evaluation_results" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "ai"."evaluation_results" FORCE ROW LEVEL SECURITY;

CREATE TRIGGER z_touch BEFORE UPDATE ON "ai"."evaluation_results" FOR EACH ROW EXECUTE FUNCTION infrastructure.touch_row();

CREATE TRIGGER a_immutable BEFORE UPDATE OR DELETE ON "ai"."evaluation_results" FOR EACH ROW EXECUTE FUNCTION infrastructure.reject_mutation();

CREATE TRIGGER a_no_truncate BEFORE TRUNCATE ON "ai"."evaluation_results" FOR EACH STATEMENT EXECUTE FUNCTION infrastructure.reject_mutation();

ALTER TABLE "ai"."evaluation_results" ADD CONSTRAINT "c_d26825919cbccc947a63" CHECK ("score" <> 'NaN'::numeric);

ALTER TABLE "core"."departments" ADD CONSTRAINT "departments_id_org_unique" UNIQUE (id, organization_id);

ALTER TABLE "core"."departments" ADD CONSTRAINT "departments_parent_same_org" FOREIGN KEY (parent_id, organization_id) REFERENCES "core"."departments" (id, organization_id) DEFERRABLE INITIALLY IMMEDIATE;

CREATE TRIGGER b_no_cycle BEFORE INSERT OR UPDATE OF parent_id ON "core"."departments" FOR EACH ROW EXECUTE FUNCTION infrastructure.prevent_tree_cycle('parent_id');

CREATE TRIGGER b_no_cycle BEFORE INSERT OR UPDATE OF parent_id ON "commercial"."product_families" FOR EACH ROW EXECUTE FUNCTION infrastructure.prevent_tree_cycle('parent_id');

CREATE UNIQUE INDEX one_primary_family_per_product ON "commercial"."product_family_memberships" (product_id) WHERE is_primary;

ALTER TABLE "core"."departments" ADD CONSTRAINT "c_6504dd0cd785ece8106c" FOREIGN KEY ("organization_id") REFERENCES "core"."organizations" (id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_f409e70beace16b8aa55" ON "core"."departments" ("organization_id");

ALTER TABLE "core"."departments" ADD CONSTRAINT "c_b62183168a8e0dc64975" FOREIGN KEY ("parent_id") REFERENCES "core"."departments" (id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_7394ac55282efdeac74d" ON "core"."departments" ("parent_id");

ALTER TABLE "core"."department_assignments" ADD CONSTRAINT "c_f178c29628699fa00997" FOREIGN KEY ("affiliation_id") REFERENCES "core"."affiliations" (id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_7a705385d3b3f5081968" ON "core"."department_assignments" ("affiliation_id");

ALTER TABLE "core"."department_assignments" ADD CONSTRAINT "c_f22d5e7774728e2b86f0" FOREIGN KEY ("department_id") REFERENCES "core"."departments" (id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_2fa727828692aa049fc1" ON "core"."department_assignments" ("department_id");

ALTER TABLE "core"."affiliation_identifiers" ADD CONSTRAINT "c_f5c56392c10f6301c6c2" FOREIGN KEY ("affiliation_id") REFERENCES "core"."affiliations" (id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_fe9ced8edd60323ade2d" ON "core"."affiliation_identifiers" ("affiliation_id");

ALTER TABLE "core"."affiliation_identifiers" ADD CONSTRAINT "c_28e0b602a1aa373a24fb" FOREIGN KEY ("connection_id") REFERENCES "integration"."connections" (id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_b924b66d4a2a4d5ad554" ON "core"."affiliation_identifiers" ("connection_id");

ALTER TABLE "commercial"."product_families" ADD CONSTRAINT "c_089d2f43343c648d936e" FOREIGN KEY ("parent_id") REFERENCES "commercial"."product_families" (id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_405e9dc0cd41c70d1ba6" ON "commercial"."product_families" ("parent_id");

ALTER TABLE "commercial"."product_family_memberships" ADD CONSTRAINT "c_ec552df3786a47f04623" FOREIGN KEY ("product_id") REFERENCES "commercial"."products" (id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_81ca8abc007986bfe4d5" ON "commercial"."product_family_memberships" ("product_id");

ALTER TABLE "commercial"."product_family_memberships" ADD CONSTRAINT "c_ac67a40cfa4b2ad5dde1" FOREIGN KEY ("family_id") REFERENCES "commercial"."product_families" (id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_2b2bd0b6682d7cb134bf" ON "commercial"."product_family_memberships" ("family_id");

ALTER TABLE "commercial"."product_bundles" ADD CONSTRAINT "c_f96361cce7abdb3e603a" FOREIGN KEY ("product_id") REFERENCES "commercial"."products" (id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_edc9c343f217bf77ba2b" ON "commercial"."product_bundles" ("product_id");

ALTER TABLE "commercial"."bundle_items" ADD CONSTRAINT "c_d7b8dc006c4f8f28c148" FOREIGN KEY ("bundle_id") REFERENCES "commercial"."product_bundles" (id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_c57c5fe68dc374e08f5c" ON "commercial"."bundle_items" ("bundle_id");

ALTER TABLE "commercial"."bundle_items" ADD CONSTRAINT "c_a0cec71d36ceca75fe4c" FOREIGN KEY ("component_product_id") REFERENCES "commercial"."products" (id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_a5a21d388ea0df41504b" ON "commercial"."bundle_items" ("component_product_id");

ALTER TABLE "governance"."data_quality_issues" ADD CONSTRAINT "c_048b99d892cff90ed515" FOREIGN KEY ("assigned_to") REFERENCES "iam"."principals" (id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_a4849144514701c8fbc9" ON "governance"."data_quality_issues" ("assigned_to");

ALTER TABLE "governance"."merge_operations" ADD CONSTRAINT "c_7a12ccc847900763c467" FOREIGN KEY ("requested_by") REFERENCES "iam"."principals" (id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_f3e0047a103f248b387b" ON "governance"."merge_operations" ("requested_by");

ALTER TABLE "governance"."merge_operations" ADD CONSTRAINT "c_77ffafd5d9f3c4659385" FOREIGN KEY ("approved_by") REFERENCES "iam"."principals" (id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_71a8410f33aeaa32a133" ON "governance"."merge_operations" ("approved_by");

ALTER TABLE "governance"."merge_operations" ADD CONSTRAINT "c_a7a17e72753489663275" FOREIGN KEY ("mapping_document_version_id") REFERENCES "docs"."document_versions" (id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_a16d80fc5ad19a224654" ON "governance"."merge_operations" ("mapping_document_version_id");

ALTER TABLE "delivery"."engagements" ADD CONSTRAINT "c_8fab3a1d64a5b5dff051" FOREIGN KEY ("customer_organization_id") REFERENCES "core"."organizations" (id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_55cbb9af2dfc29c3f4d9" ON "delivery"."engagements" ("customer_organization_id");

ALTER TABLE "delivery"."engagements" ADD CONSTRAINT "c_aad241ed16acbbeced30" FOREIGN KEY ("provider_organization_id") REFERENCES "core"."organizations" (id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_2d41ab1da78aa6b6c2d3" ON "delivery"."engagements" ("provider_organization_id");

ALTER TABLE "delivery"."engagements" ADD CONSTRAINT "c_6bc47164d40600834d8e" FOREIGN KEY ("opportunity_id") REFERENCES "crm"."opportunities" (id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_5d4c14e298f96a94d4bc" ON "delivery"."engagements" ("opportunity_id");

ALTER TABLE "delivery"."engagements" ADD CONSTRAINT "c_31f1816b713e843f0488" FOREIGN KEY ("contract_version_id") REFERENCES "commercial"."contract_versions" (id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_d6dde12511fbf9c9ffc8" ON "delivery"."engagements" ("contract_version_id");

ALTER TABLE "delivery"."engagements" ADD CONSTRAINT "c_1f04f396f77ab005091a" FOREIGN KEY ("owner_id") REFERENCES "iam"."principals" (id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_13b40506e979078a25e1" ON "delivery"."engagements" ("owner_id");

ALTER TABLE "delivery"."engagement_lines" ADD CONSTRAINT "c_eb0b801700ae71447e62" FOREIGN KEY ("engagement_id") REFERENCES "delivery"."engagements" (id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_bd4c21288b700f9383f8" ON "delivery"."engagement_lines" ("engagement_id");

ALTER TABLE "delivery"."engagement_lines" ADD CONSTRAINT "c_2b3fd1680c74aa24b2c3" FOREIGN KEY ("product_id") REFERENCES "commercial"."products" (id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_b95e8115cbc700ce2274" ON "delivery"."engagement_lines" ("product_id");

ALTER TABLE "delivery"."engagement_lines" ADD CONSTRAINT "c_c6273598d55ba570338a" FOREIGN KEY ("source_quote_line_id") REFERENCES "commercial"."quote_lines" (id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_a8ced43d7d5e20c538c1" ON "delivery"."engagement_lines" ("source_quote_line_id");

ALTER TABLE "delivery"."engagement_lines" ADD CONSTRAINT "c_bfa78e9f44e7a71383e6" FOREIGN KEY ("contract_component_id") REFERENCES "commercial"."contract_components" (id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_81aad3045815ca3e2da5" ON "delivery"."engagement_lines" ("contract_component_id");

ALTER TABLE "delivery"."service_instances" ADD CONSTRAINT "c_0776580f7d86f7433917" FOREIGN KEY ("engagement_line_id") REFERENCES "delivery"."engagement_lines" (id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_f6097052d16d17b8c9b4" ON "delivery"."service_instances" ("engagement_line_id");

ALTER TABLE "delivery"."service_instances" ADD CONSTRAINT "c_7c0e30b6a3511b0556bb" FOREIGN KEY ("customer_organization_id") REFERENCES "core"."organizations" (id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_aed74391c7f39286313c" ON "delivery"."service_instances" ("customer_organization_id");

ALTER TABLE "delivery"."service_instances" ADD CONSTRAINT "c_935c027c7254b5ffa6d8" FOREIGN KEY ("site_id") REFERENCES "core"."sites" (id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_0fc8aaea8bba3302ace8" ON "delivery"."service_instances" ("site_id");

ALTER TABLE "delivery"."service_instances" ADD CONSTRAINT "c_9900942e260b2d7d8c0b" FOREIGN KEY ("owner_id") REFERENCES "iam"."principals" (id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_4b20c3cb2b67918cf5ad" ON "delivery"."service_instances" ("owner_id");

ALTER TABLE "delivery"."service_instance_assets" ADD CONSTRAINT "c_e8c6416831e9cd5ff17b" FOREIGN KEY ("service_instance_id") REFERENCES "delivery"."service_instances" (id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_c67528c49dca46651b96" ON "delivery"."service_instance_assets" ("service_instance_id");

ALTER TABLE "delivery"."service_instance_assets" ADD CONSTRAINT "c_224ae6e5d9f334bd7f79" FOREIGN KEY ("item_id") REFERENCES "cmdb"."items" (id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_8d97b05e64f6f8eb023f" ON "delivery"."service_instance_assets" ("item_id");

ALTER TABLE "delivery"."service_instance_projects" ADD CONSTRAINT "c_99a6d137ccc684262e22" FOREIGN KEY ("service_instance_id") REFERENCES "delivery"."service_instances" (id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_788d5ce66105946deac9" ON "delivery"."service_instance_projects" ("service_instance_id");

ALTER TABLE "delivery"."service_instance_projects" ADD CONSTRAINT "c_02ccddf9a3eca9eba8de" FOREIGN KEY ("project_id") REFERENCES "project"."projects" (id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_0fe5a86808417d433148" ON "delivery"."service_instance_projects" ("project_id");

ALTER TABLE "delivery"."service_instance_tickets" ADD CONSTRAINT "c_f5d7b3964d430648ac1a" FOREIGN KEY ("service_instance_id") REFERENCES "delivery"."service_instances" (id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_b3204abc6f5ac13d12c6" ON "delivery"."service_instance_tickets" ("service_instance_id");

ALTER TABLE "delivery"."service_instance_tickets" ADD CONSTRAINT "c_acb9fcae12f7cc91a31b" FOREIGN KEY ("ticket_id") REFERENCES "itsm"."tickets" (id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_ec59df41c873435266aa" ON "delivery"."service_instance_tickets" ("ticket_id");

ALTER TABLE "delivery"."change_orders" ADD CONSTRAINT "c_d85b875e1cc841a32cb9" FOREIGN KEY ("engagement_id") REFERENCES "delivery"."engagements" (id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_9ddd50e7424ba8910cd4" ON "delivery"."change_orders" ("engagement_id");

ALTER TABLE "delivery"."change_orders" ADD CONSTRAINT "c_79dd0124c8f982b5de06" FOREIGN KEY ("proposed_contract_version_id") REFERENCES "commercial"."contract_versions" (id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_f1854fe7bf8765dab151" ON "delivery"."change_orders" ("proposed_contract_version_id");

ALTER TABLE "delivery"."change_orders" ADD CONSTRAINT "c_421431eb53bae43cace3" FOREIGN KEY ("approval_request_id") REFERENCES "workflow"."approval_requests" (id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_0ac5a514db06e4d2d301" ON "delivery"."change_orders" ("approval_request_id");

ALTER TABLE "delivery"."acceptance_criteria" ADD CONSTRAINT "c_4b96c2f1e2d19dcb13de" FOREIGN KEY ("engagement_line_id") REFERENCES "delivery"."engagement_lines" (id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_192f0450524da3114f31" ON "delivery"."acceptance_criteria" ("engagement_line_id");

ALTER TABLE "delivery"."acceptance_criteria" ADD CONSTRAINT "c_51b7c240daa992a670e6" FOREIGN KEY ("evidence_document_id") REFERENCES "docs"."documents" (id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_08e31f07ab953738da53" ON "delivery"."acceptance_criteria" ("evidence_document_id");

ALTER TABLE "delivery"."acceptance_criteria" ADD CONSTRAINT "c_e91c99ea00e2aefc9096" FOREIGN KEY ("acceptance_id") REFERENCES "project"."acceptances" (id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_2962b00a6b513ac96552" ON "delivery"."acceptance_criteria" ("acceptance_id");

ALTER TABLE "delivery"."handovers" ADD CONSTRAINT "c_8e4d03c539b463cf080a" FOREIGN KEY ("service_instance_id") REFERENCES "delivery"."service_instances" (id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_606114f9d8bfab93ee4e" ON "delivery"."handovers" ("service_instance_id");

ALTER TABLE "delivery"."handovers" ADD CONSTRAINT "c_f202d65b568c6de32b26" FOREIGN KEY ("recipient_affiliation_id") REFERENCES "core"."affiliations" (id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_e741ee673938f3fe0ef9" ON "delivery"."handovers" ("recipient_affiliation_id");

ALTER TABLE "delivery"."handovers" ADD CONSTRAINT "c_47f486b5d1ff4ff4f79b" FOREIGN KEY ("document_version_id") REFERENCES "docs"."document_versions" (id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_39715d17fe0b32f133f7" ON "delivery"."handovers" ("document_version_id");

ALTER TABLE "delivery"."handovers" ADD CONSTRAINT "c_98a20d671b29ab88a0af" FOREIGN KEY ("handed_over_by") REFERENCES "iam"."principals" (id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_6be58e198197bf6b72fd" ON "delivery"."handovers" ("handed_over_by");

ALTER TABLE "delivery"."handovers" ADD CONSTRAINT "c_e727f15de9acb12b5c89" FOREIGN KEY ("acceptance_id") REFERENCES "project"."acceptances" (id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_5113737dba6d12f3e287" ON "delivery"."handovers" ("acceptance_id");

ALTER TABLE "studio"."websites" ADD CONSTRAINT "c_bd85573221ad2a923d54" FOREIGN KEY ("service_instance_id") REFERENCES "delivery"."service_instances" (id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_304c50b8923c45a150e1" ON "studio"."websites" ("service_instance_id");

ALTER TABLE "studio"."websites" ADD CONSTRAINT "c_f7c3c9269df168fd7e8b" FOREIGN KEY ("primary_domain_id") REFERENCES "cmdb"."domains" (id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_fd7376ebbf5f47ad0318" ON "studio"."websites" ("primary_domain_id");

ALTER TABLE "studio"."website_environments" ADD CONSTRAINT "c_c0fb3ac16c8681474c17" FOREIGN KEY ("website_id") REFERENCES "studio"."websites" (id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_771ed2385926150d3df7" ON "studio"."website_environments" ("website_id");

ALTER TABLE "studio"."website_environments" ADD CONSTRAINT "c_8217f3fe668afcf88edb" FOREIGN KEY ("hosting_service_id") REFERENCES "cmdb"."hosting_services" (id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_ca9cf64d2689429c78ac" ON "studio"."website_environments" ("hosting_service_id");

ALTER TABLE "studio"."website_releases" ADD CONSTRAINT "c_fe73ab5aee00e2261fc3" FOREIGN KEY ("environment_id") REFERENCES "studio"."website_environments" (id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_fa9d312b71f39c083d18" ON "studio"."website_releases" ("environment_id");

ALTER TABLE "studio"."website_releases" ADD CONSTRAINT "c_795eec883c1296555b1b" FOREIGN KEY ("deployed_by") REFERENCES "iam"."principals" (id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_8f5f82e4b61a04af395b" ON "studio"."website_releases" ("deployed_by");

ALTER TABLE "studio"."website_releases" ADD CONSTRAINT "c_b95a319445d571542892" FOREIGN KEY ("change_ticket_id") REFERENCES "itsm"."tickets" (id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_90810cba0416149e52f7" ON "studio"."website_releases" ("change_ticket_id");

ALTER TABLE "studio"."website_releases" ADD CONSTRAINT "c_31b2dccacd7cb747ce36" FOREIGN KEY ("previous_release_id") REFERENCES "studio"."website_releases" (id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_254e471ec5f36aef2444" ON "studio"."website_releases" ("previous_release_id");

ALTER TABLE "studio"."maintenance_plans" ADD CONSTRAINT "c_9349262e984f2f12e9e5" FOREIGN KEY ("website_id") REFERENCES "studio"."websites" (id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_45bd494c71a05e69dd32" ON "studio"."maintenance_plans" ("website_id");

ALTER TABLE "studio"."maintenance_plans" ADD CONSTRAINT "c_4b976914b35fd4d917a1" FOREIGN KEY ("contract_component_id") REFERENCES "commercial"."contract_components" (id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_98281892c8a20e744db2" ON "studio"."maintenance_plans" ("contract_component_id");

ALTER TABLE "studio"."maintenance_runs" ADD CONSTRAINT "c_398b550f8f30b1378888" FOREIGN KEY ("plan_id") REFERENCES "studio"."maintenance_plans" (id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_6abf948b13551a52db63" ON "studio"."maintenance_runs" ("plan_id");

ALTER TABLE "studio"."maintenance_runs" ADD CONSTRAINT "c_5f9cd3b101d6dd448e5b" FOREIGN KEY ("intervention_id") REFERENCES "itsm"."interventions" (id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_a5e8a1dd6b372b52d0f3" ON "studio"."maintenance_runs" ("intervention_id");

ALTER TABLE "studio"."maintenance_runs" ADD CONSTRAINT "c_7c5a152c358970f35bc1" FOREIGN KEY ("report_version_id") REFERENCES "docs"."document_versions" (id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_7811830885b189e46511" ON "studio"."maintenance_runs" ("report_version_id");

ALTER TABLE "advisory"."assessments" ADD CONSTRAINT "c_39ac93929fde19fdc3ba" FOREIGN KEY ("engagement_id") REFERENCES "delivery"."engagements" (id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_1da6bd9d995f02eaa1d9" ON "advisory"."assessments" ("engagement_id");

ALTER TABLE "advisory"."assessments" ADD CONSTRAINT "c_a4932d079086448f9d1c" FOREIGN KEY ("assessor_id") REFERENCES "iam"."principals" (id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_cce9fa28296a8dde8a05" ON "advisory"."assessments" ("assessor_id");

ALTER TABLE "advisory"."assessments" ADD CONSTRAINT "c_71039940d918be6d2973" FOREIGN KEY ("report_version_id") REFERENCES "docs"."document_versions" (id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_0968f9ede03bdff045f6" ON "advisory"."assessments" ("report_version_id");

ALTER TABLE "advisory"."findings" ADD CONSTRAINT "c_3f079abdf8fa5b1c0df3" FOREIGN KEY ("assessment_id") REFERENCES "advisory"."assessments" (id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_b1376cdeab3b385f187d" ON "advisory"."findings" ("assessment_id");

ALTER TABLE "advisory"."findings" ADD CONSTRAINT "c_d3068a126dc635a83b0f" FOREIGN KEY ("evidence_version_id") REFERENCES "docs"."document_versions" (id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_2b5a5926979dfbd219bc" ON "advisory"."findings" ("evidence_version_id");

ALTER TABLE "advisory"."findings" ADD CONSTRAINT "c_15bc1ebc5778aaba55a7" FOREIGN KEY ("item_id") REFERENCES "cmdb"."items" (id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_2180f539eec9ead14c6d" ON "advisory"."findings" ("item_id");

ALTER TABLE "advisory"."recommendations" ADD CONSTRAINT "c_2aa0bec656e74264bc5b" FOREIGN KEY ("finding_id") REFERENCES "advisory"."findings" (id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_0c5834ef5b92cd2d1430" ON "advisory"."recommendations" ("finding_id");

ALTER TABLE "advisory"."roadmap_items" ADD CONSTRAINT "c_2cbf191e9e748cc670b2" FOREIGN KEY ("recommendation_id") REFERENCES "advisory"."recommendations" (id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_d8dc1cf86410ce51e9bf" ON "advisory"."roadmap_items" ("recommendation_id");

ALTER TABLE "advisory"."roadmap_items" ADD CONSTRAINT "c_a524dcaef60b9ba8fdf5" FOREIGN KEY ("task_id") REFERENCES "project"."tasks" (id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_5a567d62c1a602b17e37" ON "advisory"."roadmap_items" ("task_id");

ALTER TABLE "advisory"."roadmap_items" ADD CONSTRAINT "c_134952c1f37528e2ae8b" FOREIGN KEY ("owner_affiliation_id") REFERENCES "core"."affiliations" (id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_814b0ad6b549b0fc26a9" ON "advisory"."roadmap_items" ("owner_affiliation_id");

ALTER TABLE "success"."customer_plans" ADD CONSTRAINT "c_7acaf0f9b78a2fbcaacd" FOREIGN KEY ("organization_id") REFERENCES "core"."organizations" (id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_18353dc33f8b5eca7cee" ON "success"."customer_plans" ("organization_id");

ALTER TABLE "success"."customer_plans" ADD CONSTRAINT "c_4e41317a017d756d1303" FOREIGN KEY ("owner_id") REFERENCES "iam"."principals" (id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_ea76e868416c1b10499a" ON "success"."customer_plans" ("owner_id");

ALTER TABLE "success"."objectives" ADD CONSTRAINT "c_65b5534dac0aaa1093fa" FOREIGN KEY ("plan_id") REFERENCES "success"."customer_plans" (id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_5dbcb86fc01f64dfda5b" ON "success"."objectives" ("plan_id");

ALTER TABLE "success"."objectives" ADD CONSTRAINT "c_fc0cf7305a55891feca9" FOREIGN KEY ("metric_definition_id") REFERENCES "reporting"."metric_definitions" (id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_dc982b7a7e60e50c4f1e" ON "success"."objectives" ("metric_definition_id");

ALTER TABLE "success"."reviews" ADD CONSTRAINT "c_484dddf683d3825ae54b" FOREIGN KEY ("plan_id") REFERENCES "success"."customer_plans" (id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_d767f689b0cb3af85cc0" ON "success"."reviews" ("plan_id");

ALTER TABLE "success"."reviews" ADD CONSTRAINT "c_ee242b0ea8532da5440a" FOREIGN KEY ("author_id") REFERENCES "iam"."principals" (id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_9011d330194daedb73bd" ON "success"."reviews" ("author_id");

ALTER TABLE "success"."reviews" ADD CONSTRAINT "c_107a1117be12e301ac15" FOREIGN KEY ("report_version_id") REFERENCES "docs"."document_versions" (id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_3da08735b1afd508510b" ON "success"."reviews" ("report_version_id");

ALTER TABLE "success"."renewal_cases" ADD CONSTRAINT "c_7c83abdc906977777ec9" FOREIGN KEY ("organization_id") REFERENCES "core"."organizations" (id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_3ba1cc4d2d75d7b36c8f" ON "success"."renewal_cases" ("organization_id");

ALTER TABLE "success"."renewal_cases" ADD CONSTRAINT "c_d2126f1e5bf657fa8cf3" FOREIGN KEY ("contract_id") REFERENCES "commercial"."contracts" (id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_c109d972e90c10aacbb1" ON "success"."renewal_cases" ("contract_id");

ALTER TABLE "success"."renewal_cases" ADD CONSTRAINT "c_b82974917abd126019c0" FOREIGN KEY ("opportunity_id") REFERENCES "crm"."opportunities" (id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_b35d30b4d6d050778cd9" ON "success"."renewal_cases" ("opportunity_id");

ALTER TABLE "success"."renewal_cases" ADD CONSTRAINT "c_7951c7f97963981109b5" FOREIGN KEY ("owner_id") REFERENCES "iam"."principals" (id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_5966e168659f768748d7" ON "success"."renewal_cases" ("owner_id");

ALTER TABLE "ai"."assistants" ADD CONSTRAINT "c_c10a8e843c4be926fce5" FOREIGN KEY ("owner_id") REFERENCES "iam"."principals" (id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_76806a4d14cd732846b1" ON "ai"."assistants" ("owner_id");

ALTER TABLE "ai"."assistant_versions" ADD CONSTRAINT "c_8673d2bacce3d24951b6" FOREIGN KEY ("assistant_id") REFERENCES "ai"."assistants" (id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_0af7b7a6d3ccfa4d04d3" ON "ai"."assistant_versions" ("assistant_id");

ALTER TABLE "ai"."assistant_versions" ADD CONSTRAINT "c_3a58cb68d9994ec00e97" FOREIGN KEY ("instructions_version_id") REFERENCES "docs"."document_versions" (id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_89353ca0eb9787f4f1ae" ON "ai"."assistant_versions" ("instructions_version_id");

ALTER TABLE "ai"."runs" ADD CONSTRAINT "c_21b0417ebbba8b1193be" FOREIGN KEY ("assistant_version_id") REFERENCES "ai"."assistant_versions" (id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_fea137df7d5fb5c636d4" ON "ai"."runs" ("assistant_version_id");

ALTER TABLE "ai"."runs" ADD CONSTRAINT "c_47c19b8df9dc548e9203" FOREIGN KEY ("actor_id") REFERENCES "iam"."principals" (id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_92d1017504accffddc5b" ON "ai"."runs" ("actor_id");

ALTER TABLE "ai"."runs" ADD CONSTRAINT "c_7c881ff0f06053d30764" FOREIGN KEY ("organization_id") REFERENCES "core"."organizations" (id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_f2447c24b0984f8314c5" ON "ai"."runs" ("organization_id");

ALTER TABLE "ai"."runs" ADD CONSTRAINT "c_ddc30e986fd2b295c6f4" FOREIGN KEY ("input_document_version_id") REFERENCES "docs"."document_versions" (id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_888027a24d5ff7553d1d" ON "ai"."runs" ("input_document_version_id");

ALTER TABLE "ai"."runs" ADD CONSTRAINT "c_099dc861376fc1760870" FOREIGN KEY ("output_document_version_id") REFERENCES "docs"."document_versions" (id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_32a5efe97ceedc5fcc6f" ON "ai"."runs" ("output_document_version_id");

ALTER TABLE "ai"."run_sources" ADD CONSTRAINT "c_a94a7edd93431197043b" FOREIGN KEY ("run_id") REFERENCES "ai"."runs" (id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_f9f822c8ea88fa7a7ea9" ON "ai"."run_sources" ("run_id");

ALTER TABLE "ai"."run_sources" ADD CONSTRAINT "c_0edb61b40a6b8aeaf666" FOREIGN KEY ("document_version_id") REFERENCES "docs"."document_versions" (id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_da17d5186ec43ca69b94" ON "ai"."run_sources" ("document_version_id");

ALTER TABLE "ai"."run_sources" ADD CONSTRAINT "c_05c5845d66fd8abb16c2" FOREIGN KEY ("article_version_id") REFERENCES "knowledge"."article_versions" (id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_650bf3a6138f99b3f7e4" ON "ai"."run_sources" ("article_version_id");

ALTER TABLE "ai"."action_proposals" ADD CONSTRAINT "c_f257fa0c1f7bdb5408c7" FOREIGN KEY ("run_id") REFERENCES "ai"."runs" (id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_b724802317b77aacc634" ON "ai"."action_proposals" ("run_id");

ALTER TABLE "ai"."action_decisions" ADD CONSTRAINT "c_92d9952bd7b858bb4980" FOREIGN KEY ("proposal_id") REFERENCES "ai"."action_proposals" (id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_2d88733656c99185ec77" ON "ai"."action_decisions" ("proposal_id");

ALTER TABLE "ai"."action_decisions" ADD CONSTRAINT "c_d21ada3592e94f452f21" FOREIGN KEY ("decided_by") REFERENCES "iam"."principals" (id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_be5421800baaddda5d7f" ON "ai"."action_decisions" ("decided_by");

ALTER TABLE "ai"."evaluation_cases" ADD CONSTRAINT "c_5cab9c163d0eace0c223" FOREIGN KEY ("assistant_id") REFERENCES "ai"."assistants" (id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_f79b31bc11c192f4fd89" ON "ai"."evaluation_cases" ("assistant_id");

ALTER TABLE "ai"."evaluation_cases" ADD CONSTRAINT "c_48b6133ad3224e06c8d1" FOREIGN KEY ("input_version_id") REFERENCES "docs"."document_versions" (id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_c8950cf6774a8525787d" ON "ai"."evaluation_cases" ("input_version_id");

ALTER TABLE "ai"."evaluation_results" ADD CONSTRAINT "c_22c07cb3a6a982e97c03" FOREIGN KEY ("case_id") REFERENCES "ai"."evaluation_cases" (id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_c14f50297e9ac3882bff" ON "ai"."evaluation_results" ("case_id");

ALTER TABLE "ai"."evaluation_results" ADD CONSTRAINT "c_7acdd21ff9d1c2ce2c43" FOREIGN KEY ("run_id") REFERENCES "ai"."runs" (id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_f9b6ea8bbeed104efad8" ON "ai"."evaluation_results" ("run_id");

ALTER TABLE "ai"."evaluation_results" ADD CONSTRAINT "c_1b4716e827577c672f7e" FOREIGN KEY ("evidence_version_id") REFERENCES "docs"."document_versions" (id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_e762767185872b6db247" ON "ai"."evaluation_results" ("evidence_version_id");

REVOKE ALL ON "core"."departments" FROM PUBLIC;

REVOKE ALL ON "core"."department_assignments" FROM PUBLIC;

REVOKE ALL ON "core"."affiliation_identifiers" FROM PUBLIC;

REVOKE ALL ON "commercial"."product_families" FROM PUBLIC;

REVOKE ALL ON "commercial"."product_family_memberships" FROM PUBLIC;

REVOKE ALL ON "commercial"."product_bundles" FROM PUBLIC;

REVOKE ALL ON "commercial"."bundle_items" FROM PUBLIC;

REVOKE ALL ON "governance"."data_quality_issues" FROM PUBLIC;

REVOKE ALL ON "governance"."merge_operations" FROM PUBLIC;

REVOKE ALL ON "delivery"."engagements" FROM PUBLIC;

REVOKE ALL ON "delivery"."engagement_lines" FROM PUBLIC;

REVOKE ALL ON "delivery"."service_instances" FROM PUBLIC;

REVOKE ALL ON "delivery"."service_instance_assets" FROM PUBLIC;

REVOKE ALL ON "delivery"."service_instance_projects" FROM PUBLIC;

REVOKE ALL ON "delivery"."service_instance_tickets" FROM PUBLIC;

REVOKE ALL ON "delivery"."change_orders" FROM PUBLIC;

REVOKE ALL ON "delivery"."acceptance_criteria" FROM PUBLIC;

REVOKE ALL ON "delivery"."handovers" FROM PUBLIC;

REVOKE ALL ON "studio"."websites" FROM PUBLIC;

REVOKE ALL ON "studio"."website_environments" FROM PUBLIC;

REVOKE ALL ON "studio"."website_releases" FROM PUBLIC;

REVOKE ALL ON "studio"."maintenance_plans" FROM PUBLIC;

REVOKE ALL ON "studio"."maintenance_runs" FROM PUBLIC;

REVOKE ALL ON "advisory"."assessments" FROM PUBLIC;

REVOKE ALL ON "advisory"."findings" FROM PUBLIC;

REVOKE ALL ON "advisory"."recommendations" FROM PUBLIC;

REVOKE ALL ON "advisory"."roadmap_items" FROM PUBLIC;

REVOKE ALL ON "success"."customer_plans" FROM PUBLIC;

REVOKE ALL ON "success"."objectives" FROM PUBLIC;

REVOKE ALL ON "success"."reviews" FROM PUBLIC;

REVOKE ALL ON "success"."renewal_cases" FROM PUBLIC;

REVOKE ALL ON "ai"."assistants" FROM PUBLIC;

REVOKE ALL ON "ai"."assistant_versions" FROM PUBLIC;

REVOKE ALL ON "ai"."runs" FROM PUBLIC;

REVOKE ALL ON "ai"."run_sources" FROM PUBLIC;

REVOKE ALL ON "ai"."action_proposals" FROM PUBLIC;

REVOKE ALL ON "ai"."action_decisions" FROM PUBLIC;

REVOKE ALL ON "ai"."evaluation_cases" FROM PUBLIC;

REVOKE ALL ON "ai"."evaluation_results" FROM PUBLIC;
INSERT INTO infrastructure.migrations(version,checksum) VALUES ('20261019_006_core_extensions','f7016d5b7b7b395ad407ff126159c24017df3f11a3f5844bdadb38eeae2a1464');
\endif
COMMIT;

INSERT INTO deployment.bundle_migrations(name,sha256) VALUES ('006-core-extensions.sql','125c38380be25c67435decff7c4a2242e7319b631e1420cb0b3a5622f253053f');
\endif


-- ===== 006-genesis-core-access.sql =====
SELECT EXISTS (SELECT FROM deployment.bundle_migrations WHERE name='006-genesis-core-access.sql') AS bundle_done \gset
\if :bundle_done
DO $$ BEGIN IF NOT EXISTS (SELECT FROM deployment.bundle_migrations WHERE name='006-genesis-core-access.sql' AND sha256='3068ae7c34cb0756f38ae1267a7d61a779fbf29a851f428de229f2811bdb6996') THEN RAISE EXCEPTION 'Empreinte différente : 006-genesis-core-access.sql'; END IF; END $$;
\else
-- Grant genesis role read access to core.installation for organization UUID resolution.
-- Required by PR #8 resolveOrganizationUuid fallback:
-- SELECT operator_organization_id FROM core.installation WHERE operator_organization_id IS NOT NULL
-- Without these grants, /api/itsm session calls fail with null org resolution when using CRM tenant slugs.

-- Schema access (idempotent)
GRANT USAGE ON SCHEMA core TO genesis;

-- Table access (idempotent)
GRANT SELECT ON core.installation TO genesis;

-- RLS policy: DROP then CREATE for idempotence
DROP POLICY IF EXISTS genesis_read_installation ON core.installation;
CREATE POLICY genesis_read_installation ON core.installation
  FOR SELECT
  TO genesis
  USING (true);

INSERT INTO deployment.bundle_migrations(name,sha256) VALUES ('006-genesis-core-access.sql','3068ae7c34cb0756f38ae1267a7d61a779fbf29a851f428de229f2811bdb6996');
\endif


-- ===== 007-itsm-history-attachments-access.sql =====
SELECT EXISTS (SELECT FROM deployment.bundle_migrations WHERE name='007-itsm-history-attachments-access.sql') AS bundle_done \gset
\if :bundle_done
DO $$ BEGIN IF NOT EXISTS (SELECT FROM deployment.bundle_migrations WHERE name='007-itsm-history-attachments-access.sql' AND sha256='f0275728102298513001560641553cef0542c1a3c5b4190a7dc9bb55803aa588') THEN RAISE EXCEPTION 'Empreinte différente : 007-itsm-history-attachments-access.sql'; END IF; END $$;
\else
-- 007: ITSM history + attachments access for the API runtime role.
-- The GENESIS API connects as `genesis` and runs ITSM queries under
-- `SET LOCAL ROLE orbit` with app.org_ids / app.audience (server/itsm-db.ts).
-- PR #10 (history + attachments) reads itsm.ticket_events and reads/writes
-- docs.files + docs.ticket_attachments; without these grants the API returned
-- 500 "permission denied for schema docs". All tables have FORCE RLS, so
-- policies are required in addition to grants. Idempotent.

BEGIN;

-- Schemas
GRANT USAGE ON SCHEMA itsm TO orbit;
GRANT USAGE ON SCHEMA docs TO orbit;
GRANT USAGE ON SCHEMA docs TO genesis;

-- Table privileges
GRANT SELECT, INSERT ON itsm.ticket_events TO orbit;          -- table is immutable (reject_mutation trigger)
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA docs TO orbit;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA docs TO orbit;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA docs
  GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO orbit;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA docs
  GRANT USAGE, SELECT ON SEQUENCES TO orbit;

-- RLS: itsm.ticket_events visible when the parent ticket is visible (orbit_tickets_org)
DROP POLICY IF EXISTS orbit_events_select ON itsm.ticket_events;
CREATE POLICY orbit_events_select ON itsm.ticket_events FOR SELECT TO orbit
  USING (EXISTS (SELECT 1 FROM itsm.tickets t WHERE t.id = ticket_events.ticket_id));
DROP POLICY IF EXISTS orbit_events_insert ON itsm.ticket_events;
CREATE POLICY orbit_events_insert ON itsm.ticket_events FOR INSERT TO orbit
  WITH CHECK (EXISTS (SELECT 1 FROM itsm.tickets t WHERE t.id = ticket_events.ticket_id));

-- RLS: docs.ticket_attachments, same model as orbit_msgs_* on itsm.ticket_messages
DROP POLICY IF EXISTS orbit_attach_select ON docs.ticket_attachments;
CREATE POLICY orbit_attach_select ON docs.ticket_attachments FOR SELECT TO orbit
  USING (EXISTS (SELECT 1 FROM itsm.tickets t WHERE t.id = ticket_attachments.ticket_id)
         AND (visibility = 'client' OR current_setting('app.audience', true) = 'internal'));
DROP POLICY IF EXISTS orbit_attach_insert ON docs.ticket_attachments;
CREATE POLICY orbit_attach_insert ON docs.ticket_attachments FOR INSERT TO orbit
  WITH CHECK (EXISTS (SELECT 1 FROM itsm.tickets t WHERE t.id = ticket_attachments.ticket_id)
              AND (visibility = 'client' OR current_setting('app.audience', true) = 'internal'));

-- RLS: docs.files visible through a visible ticket attachment. A file inserted in
-- the current transaction (created_at = now(), set explicitly by the API) and not
-- yet linked to any attachment is also visible so INSERT ... RETURNING works.
DROP POLICY IF EXISTS orbit_files_select ON docs.files;
CREATE POLICY orbit_files_select ON docs.files FOR SELECT TO orbit
  USING (
    EXISTS (SELECT 1 FROM docs.ticket_attachments ta WHERE ta.file_id = files.id)
    OR (created_at = now()
        AND NOT EXISTS (SELECT 1 FROM docs.ticket_attachments ta WHERE ta.file_id = files.id))
  );
DROP POLICY IF EXISTS orbit_files_insert ON docs.files;
CREATE POLICY orbit_files_insert ON docs.files FOR INSERT TO orbit
  WITH CHECK (created_at = now() AND scan_status = 'pending');

COMMIT;
INSERT INTO deployment.bundle_migrations(name,sha256) VALUES ('007-itsm-history-attachments-access.sql','f0275728102298513001560641553cef0542c1a3c5b4190a7dc9bb55803aa588');
\endif


-- ===== 008-sales-chain.sql =====
SELECT EXISTS (SELECT FROM deployment.bundle_migrations WHERE name='008-sales-chain.sql') AS bundle_done \gset
\if :bundle_done
DO $$ BEGIN IF NOT EXISTS (SELECT FROM deployment.bundle_migrations WHERE name='008-sales-chain.sql' AND sha256='fba492b44eec31671e8dbc38ac797f851f30ad9191e3b97f4e65ceaa185e92b3') THEN RAISE EXCEPTION 'Empreinte différente : 008-sales-chain.sql'; END IF; END $$;
\else
-- Sales chain access for genesis role
-- Grants USAGE on commercial/billing schemas and table privileges
-- RLS policies for genesis on existing commercial tables
--
-- NOTE: Tables already exist from 001-business.sql
-- This migration only grants access to genesis role for sales-chain API

\set ON_ERROR_STOP on

-- Grant schema usage to genesis
GRANT USAGE ON SCHEMA commercial TO genesis;

-- Grant table privileges on commercial.quotes and quote_lines
GRANT SELECT, INSERT, UPDATE ON commercial.quotes TO genesis;
GRANT SELECT, INSERT, UPDATE ON commercial.quote_lines TO genesis;

-- Grant table privileges on commercial.contracts
GRANT SELECT, INSERT, UPDATE ON commercial.contracts TO genesis;
GRANT SELECT, INSERT, UPDATE ON commercial.contract_versions TO genesis;
GRANT SELECT, INSERT, UPDATE ON commercial.contract_scopes TO genesis;

-- Grant table privileges on commercial.invoices and related
GRANT SELECT, INSERT, UPDATE ON commercial.invoices TO genesis;
GRANT SELECT, INSERT, UPDATE ON commercial.invoice_lines TO genesis;

-- Grant table privileges on commercial.payments
GRANT SELECT, INSERT, UPDATE ON commercial.payments TO genesis;
GRANT SELECT, INSERT, UPDATE ON commercial.payment_allocations TO genesis;

-- Grant privileges on commercial.products (needed for quote lines)
GRANT SELECT ON commercial.products TO genesis;

-- RLS policies: Allow genesis role to access all rows (foundation slice)
-- Future (Lot 8): Replace with multi-tenant policies

-- Quotes
DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies 
    WHERE schemaname = 'commercial' AND tablename = 'quotes' AND policyname = 'genesis_access_quotes'
  ) THEN
    CREATE POLICY genesis_access_quotes ON commercial.quotes
      FOR ALL TO genesis USING (true) WITH CHECK (true);
  END IF;
END $$;

-- Quote lines
DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies 
    WHERE schemaname = 'commercial' AND tablename = 'quote_lines' AND policyname = 'genesis_access_quote_lines'
  ) THEN
    CREATE POLICY genesis_access_quote_lines ON commercial.quote_lines
      FOR ALL TO genesis USING (true) WITH CHECK (true);
  END IF;
END $$;

-- Contracts
DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies 
    WHERE schemaname = 'commercial' AND tablename = 'contracts' AND policyname = 'genesis_access_contracts'
  ) THEN
    CREATE POLICY genesis_access_contracts ON commercial.contracts
      FOR ALL TO genesis USING (true) WITH CHECK (true);
  END IF;
END $$;

-- Contract versions
DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies 
    WHERE schemaname = 'commercial' AND tablename = 'contract_versions' AND policyname = 'genesis_access_contract_versions'
  ) THEN
    CREATE POLICY genesis_access_contract_versions ON commercial.contract_versions
      FOR ALL TO genesis USING (true) WITH CHECK (true);
  END IF;
END $$;

-- Contract scopes
DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies 
    WHERE schemaname = 'commercial' AND tablename = 'contract_scopes' AND policyname = 'genesis_access_contract_scopes'
  ) THEN
    CREATE POLICY genesis_access_contract_scopes ON commercial.contract_scopes
      FOR ALL TO genesis USING (true) WITH CHECK (true);
  END IF;
END $$;

-- Invoices
DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies 
    WHERE schemaname = 'commercial' AND tablename = 'invoices' AND policyname = 'genesis_access_invoices'
  ) THEN
    CREATE POLICY genesis_access_invoices ON commercial.invoices
      FOR ALL TO genesis USING (true) WITH CHECK (true);
  END IF;
END $$;

-- Invoice lines
DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies 
    WHERE schemaname = 'commercial' AND tablename = 'invoice_lines' AND policyname = 'genesis_access_invoice_lines'
  ) THEN
    CREATE POLICY genesis_access_invoice_lines ON commercial.invoice_lines
      FOR ALL TO genesis USING (true) WITH CHECK (true);
  END IF;
END $$;

-- Payments
DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies 
    WHERE schemaname = 'commercial' AND tablename = 'payments' AND policyname = 'genesis_access_payments'
  ) THEN
    CREATE POLICY genesis_access_payments ON commercial.payments
      FOR ALL TO genesis USING (true) WITH CHECK (true);
  END IF;
END $$;

-- Payment allocations
DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies 
    WHERE schemaname = 'commercial' AND tablename = 'payment_allocations' AND policyname = 'genesis_access_payment_allocations'
  ) THEN
    CREATE POLICY genesis_access_payment_allocations ON commercial.payment_allocations
      FOR ALL TO genesis USING (true) WITH CHECK (true);
  END IF;
END $$;

-- Products (read-only for genesis)
DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies 
    WHERE schemaname = 'commercial' AND tablename = 'products' AND policyname = 'genesis_read_products'
  ) THEN
    CREATE POLICY genesis_read_products ON commercial.products
      FOR SELECT TO genesis USING (true);
  END IF;
END $$;

-- Create indexes for common sales-chain queries (IF NOT EXISTS)
DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_indexes 
    WHERE schemaname = 'commercial' AND tablename = 'quotes' AND indexname = 'idx_quotes_customer_org'
  ) THEN
    CREATE INDEX idx_quotes_customer_org ON commercial.quotes(customer_org_id);
  END IF;
END $$;

DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_indexes 
    WHERE schemaname = 'commercial' AND tablename = 'quotes' AND indexname = 'idx_quotes_issuer_org'
  ) THEN
    CREATE INDEX idx_quotes_issuer_org ON commercial.quotes(issuer_org_id);
  END IF;
END $$;

DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_indexes 
    WHERE schemaname = 'commercial' AND tablename = 'quotes' AND indexname = 'idx_quotes_status'
  ) THEN
    CREATE INDEX idx_quotes_status ON commercial.quotes(status);
  END IF;
END $$;

DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_indexes 
    WHERE schemaname = 'commercial' AND tablename = 'contracts' AND indexname = 'idx_contracts_provider_org'
  ) THEN
    CREATE INDEX idx_contracts_provider_org ON commercial.contracts(provider_org_id);
  END IF;
END $$;

DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_indexes 
    WHERE schemaname = 'commercial' AND tablename = 'contracts' AND indexname = 'idx_contracts_signatory_org'
  ) THEN
    CREATE INDEX idx_contracts_signatory_org ON commercial.contracts(signatory_org_id);
  END IF;
END $$;

DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_indexes 
    WHERE schemaname = 'commercial' AND tablename = 'invoices' AND indexname = 'idx_invoices_payer_org'
  ) THEN
    CREATE INDEX idx_invoices_payer_org ON commercial.invoices(payer_org_id);
  END IF;
END $$;

DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_indexes 
    WHERE schemaname = 'commercial' AND tablename = 'invoices' AND indexname = 'idx_invoices_issuer_org'
  ) THEN
    CREATE INDEX idx_invoices_issuer_org ON commercial.invoices(issuer_org_id);
  END IF;
END $$;

INSERT INTO deployment.bundle_migrations(name,sha256) VALUES ('008-sales-chain.sql','fba492b44eec31671e8dbc38ac797f851f30ad9191e3b97f4e65ceaa185e92b3');
\endif


-- ===== 009-core-session-access.sql =====
SELECT EXISTS (SELECT FROM deployment.bundle_migrations WHERE name='009-core-session-access.sql') AS bundle_done \gset
\if :bundle_done
DO $$ BEGIN IF NOT EXISTS (SELECT FROM deployment.bundle_migrations WHERE name='009-core-session-access.sql' AND sha256='844194834e9a38c12bc5c584fba0a40819dccb20756705cf387a10ff3ccc1539') THEN RAISE EXCEPTION 'Empreinte différente : 009-core-session-access.sql'; END IF; END $$;
\else
-- Grant genesis role read access to core.organizations, core.persons, and core.affiliations.
-- Required for /api/core session API (PR: Lot 2-3 demo gap).
-- Allows GENESIS session to find and link Core organizations/persons as CRM clients/contacts by shared Core UUID.

-- Schema access (already granted by 006-genesis-core-access.sql, but idempotent)
GRANT USAGE ON SCHEMA core TO genesis;

-- Table access: SELECT only (read-only for session API)
GRANT SELECT ON core.organizations TO genesis;
GRANT SELECT ON core.persons TO genesis;
GRANT SELECT ON core.affiliations TO genesis;

-- RLS policies: DROP then CREATE for idempotence

-- Organizations: allow genesis to read all organizations
DROP POLICY IF EXISTS genesis_read_organizations ON core.organizations;
CREATE POLICY genesis_read_organizations ON core.organizations
  FOR SELECT
  TO genesis
  USING (true);

-- Persons: allow genesis to read all persons
DROP POLICY IF EXISTS genesis_read_persons ON core.persons;
CREATE POLICY genesis_read_persons ON core.persons
  FOR SELECT
  TO genesis
  USING (true);

-- Affiliations: allow genesis to read all affiliations
DROP POLICY IF EXISTS genesis_read_affiliations ON core.affiliations;
CREATE POLICY genesis_read_affiliations ON core.affiliations
  FOR SELECT
  TO genesis
  USING (true);

INSERT INTO deployment.bundle_migrations(name,sha256) VALUES ('009-core-session-access.sql','844194834e9a38c12bc5c584fba0a40819dccb20756705cf387a10ff3ccc1539');
\endif


-- ===== 010-project-session-access.sql =====
SELECT EXISTS (SELECT FROM deployment.bundle_migrations WHERE name='010-project-session-access.sql') AS bundle_done \gset
\if :bundle_done
DO $$ BEGIN IF NOT EXISTS (SELECT FROM deployment.bundle_migrations WHERE name='010-project-session-access.sql' AND sha256='8c222039f734364caed89829a8ea35b6c1b852ab7ffbfde23d144806226496c9') THEN RAISE EXCEPTION 'Empreinte différente : 010-project-session-access.sql'; END IF; END $$;
\else
-- Lot 5: Grant genesis role session access to project.* schema
-- Pattern: mirror 006-genesis-core-access.sql for ITSM
-- Enable /api/projects (session cookie auth) to read/write live project.* tables

-- Schema access (idempotent)
GRANT USAGE ON SCHEMA project TO genesis;

-- Table access (idempotent)
GRANT SELECT, INSERT, UPDATE, DELETE ON project.projects TO genesis;
GRANT SELECT, INSERT, UPDATE, DELETE ON project.phases TO genesis;
GRANT SELECT, INSERT, UPDATE, DELETE ON project.milestones TO genesis;
GRANT SELECT, INSERT, UPDATE, DELETE ON project.deliverables TO genesis;
GRANT SELECT, INSERT, UPDATE, DELETE ON project.acceptances TO genesis;
GRANT SELECT, INSERT, UPDATE, DELETE ON project.tasks TO genesis;
GRANT SELECT, INSERT, UPDATE, DELETE ON project.task_assignees TO genesis;
GRANT SELECT, INSERT, UPDATE, DELETE ON project.task_dependencies TO genesis;
GRANT SELECT, INSERT, UPDATE, DELETE ON project.memberships TO genesis;
GRANT SELECT, INSERT, UPDATE, DELETE ON project.project_parties TO genesis;
GRANT SELECT, INSERT, UPDATE, DELETE ON project.resource_demands TO genesis;
GRANT SELECT, INSERT, UPDATE, DELETE ON project.budget_lines TO genesis;
GRANT SELECT, INSERT, UPDATE, DELETE ON project.risks TO genesis;
GRANT SELECT, INSERT, UPDATE, DELETE ON project.decisions TO genesis;
GRANT SELECT, INSERT, UPDATE, DELETE ON project.baselines TO genesis;

-- Enable RLS on all project tables (idempotent)
ALTER TABLE project.projects ENABLE ROW LEVEL SECURITY;
ALTER TABLE project.phases ENABLE ROW LEVEL SECURITY;
ALTER TABLE project.milestones ENABLE ROW LEVEL SECURITY;
ALTER TABLE project.deliverables ENABLE ROW LEVEL SECURITY;
ALTER TABLE project.acceptances ENABLE ROW LEVEL SECURITY;
ALTER TABLE project.tasks ENABLE ROW LEVEL SECURITY;
ALTER TABLE project.task_assignees ENABLE ROW LEVEL SECURITY;
ALTER TABLE project.task_dependencies ENABLE ROW LEVEL SECURITY;
ALTER TABLE project.memberships ENABLE ROW LEVEL SECURITY;
ALTER TABLE project.project_parties ENABLE ROW LEVEL SECURITY;
ALTER TABLE project.resource_demands ENABLE ROW LEVEL SECURITY;
ALTER TABLE project.budget_lines ENABLE ROW LEVEL SECURITY;
ALTER TABLE project.risks ENABLE ROW LEVEL SECURITY;
ALTER TABLE project.decisions ENABLE ROW LEVEL SECURITY;
ALTER TABLE project.baselines ENABLE ROW LEVEL SECURITY;

-- RLS policies for genesis role (idempotent: DROP + CREATE)

-- Projects
DROP POLICY IF EXISTS genesis_read_projects ON project.projects;
CREATE POLICY genesis_read_projects ON project.projects
  FOR SELECT
  TO genesis
  USING (true);

DROP POLICY IF EXISTS genesis_write_projects ON project.projects;
CREATE POLICY genesis_write_projects ON project.projects
  FOR ALL
  TO genesis
  USING (true)
  WITH CHECK (true);

-- Phases
DROP POLICY IF EXISTS genesis_read_phases ON project.phases;
CREATE POLICY genesis_read_phases ON project.phases
  FOR SELECT
  TO genesis
  USING (true);

DROP POLICY IF EXISTS genesis_write_phases ON project.phases;
CREATE POLICY genesis_write_phases ON project.phases
  FOR ALL
  TO genesis
  USING (true)
  WITH CHECK (true);

-- Milestones
DROP POLICY IF EXISTS genesis_read_milestones ON project.milestones;
CREATE POLICY genesis_read_milestones ON project.milestones
  FOR SELECT
  TO genesis
  USING (true);

DROP POLICY IF EXISTS genesis_write_milestones ON project.milestones;
CREATE POLICY genesis_write_milestones ON project.milestones
  FOR ALL
  TO genesis
  USING (true)
  WITH CHECK (true);

-- Deliverables
DROP POLICY IF EXISTS genesis_read_deliverables ON project.deliverables;
CREATE POLICY genesis_read_deliverables ON project.deliverables
  FOR SELECT
  TO genesis
  USING (true);

DROP POLICY IF EXISTS genesis_write_deliverables ON project.deliverables;
CREATE POLICY genesis_write_deliverables ON project.deliverables
  FOR ALL
  TO genesis
  USING (true)
  WITH CHECK (true);

-- Acceptances
DROP POLICY IF EXISTS genesis_read_acceptances ON project.acceptances;
CREATE POLICY genesis_read_acceptances ON project.acceptances
  FOR SELECT
  TO genesis
  USING (true);

DROP POLICY IF EXISTS genesis_write_acceptances ON project.acceptances;
CREATE POLICY genesis_write_acceptances ON project.acceptances
  FOR ALL
  TO genesis
  USING (true)
  WITH CHECK (true);

-- Tasks
DROP POLICY IF EXISTS genesis_read_tasks ON project.tasks;
CREATE POLICY genesis_read_tasks ON project.tasks
  FOR SELECT
  TO genesis
  USING (true);

DROP POLICY IF EXISTS genesis_write_tasks ON project.tasks;
CREATE POLICY genesis_write_tasks ON project.tasks
  FOR ALL
  TO genesis
  USING (true)
  WITH CHECK (true);

-- Task assignees
DROP POLICY IF EXISTS genesis_read_task_assignees ON project.task_assignees;
CREATE POLICY genesis_read_task_assignees ON project.task_assignees
  FOR SELECT
  TO genesis
  USING (true);

DROP POLICY IF EXISTS genesis_write_task_assignees ON project.task_assignees;
CREATE POLICY genesis_write_task_assignees ON project.task_assignees
  FOR ALL
  TO genesis
  USING (true)
  WITH CHECK (true);

-- Task dependencies
DROP POLICY IF EXISTS genesis_read_task_dependencies ON project.task_dependencies;
CREATE POLICY genesis_read_task_dependencies ON project.task_dependencies
  FOR SELECT
  TO genesis
  USING (true);

DROP POLICY IF EXISTS genesis_write_task_dependencies ON project.task_dependencies;
CREATE POLICY genesis_write_task_dependencies ON project.task_dependencies
  FOR ALL
  TO genesis
  USING (true)
  WITH CHECK (true);

-- Memberships
DROP POLICY IF EXISTS genesis_read_memberships ON project.memberships;
CREATE POLICY genesis_read_memberships ON project.memberships
  FOR SELECT
  TO genesis
  USING (true);

DROP POLICY IF EXISTS genesis_write_memberships ON project.memberships;
CREATE POLICY genesis_write_memberships ON project.memberships
  FOR ALL
  TO genesis
  USING (true)
  WITH CHECK (true);

-- Project parties
DROP POLICY IF EXISTS genesis_read_project_parties ON project.project_parties;
CREATE POLICY genesis_read_project_parties ON project.project_parties
  FOR SELECT
  TO genesis
  USING (true);

DROP POLICY IF EXISTS genesis_write_project_parties ON project.project_parties;
CREATE POLICY genesis_write_project_parties ON project.project_parties
  FOR ALL
  TO genesis
  USING (true)
  WITH CHECK (true);

-- Resource demands
DROP POLICY IF EXISTS genesis_read_resource_demands ON project.resource_demands;
CREATE POLICY genesis_read_resource_demands ON project.resource_demands
  FOR SELECT
  TO genesis
  USING (true);

DROP POLICY IF EXISTS genesis_write_resource_demands ON project.resource_demands;
CREATE POLICY genesis_write_resource_demands ON project.resource_demands
  FOR ALL
  TO genesis
  USING (true)
  WITH CHECK (true);

-- Budget lines
DROP POLICY IF EXISTS genesis_read_budget_lines ON project.budget_lines;
CREATE POLICY genesis_read_budget_lines ON project.budget_lines
  FOR SELECT
  TO genesis
  USING (true);

DROP POLICY IF EXISTS genesis_write_budget_lines ON project.budget_lines;
CREATE POLICY genesis_write_budget_lines ON project.budget_lines
  FOR ALL
  TO genesis
  USING (true)
  WITH CHECK (true);

-- Risks
DROP POLICY IF EXISTS genesis_read_risks ON project.risks;
CREATE POLICY genesis_read_risks ON project.risks
  FOR SELECT
  TO genesis
  USING (true);

DROP POLICY IF EXISTS genesis_write_risks ON project.risks;
CREATE POLICY genesis_write_risks ON project.risks
  FOR ALL
  TO genesis
  USING (true)
  WITH CHECK (true);

-- Decisions
DROP POLICY IF EXISTS genesis_read_decisions ON project.decisions;
CREATE POLICY genesis_read_decisions ON project.decisions
  FOR SELECT
  TO genesis
  USING (true);

DROP POLICY IF EXISTS genesis_write_decisions ON project.decisions;
CREATE POLICY genesis_write_decisions ON project.decisions
  FOR ALL
  TO genesis
  USING (true)
  WITH CHECK (true);

-- Baselines
DROP POLICY IF EXISTS genesis_read_baselines ON project.baselines;
CREATE POLICY genesis_read_baselines ON project.baselines
  FOR SELECT
  TO genesis
  USING (true);

DROP POLICY IF EXISTS genesis_write_baselines ON project.baselines;
CREATE POLICY genesis_write_baselines ON project.baselines
  FOR ALL
  TO genesis
  USING (true)
  WITH CHECK (true);

INSERT INTO deployment.bundle_migrations(name,sha256) VALUES ('010-project-session-access.sql','8c222039f734364caed89829a8ea35b6c1b852ab7ffbfde23d144806226496c9');
\endif


-- ===== 011-ops-session-access.sql =====
SELECT EXISTS (SELECT FROM deployment.bundle_migrations WHERE name='011-ops-session-access.sql') AS bundle_done \gset
\if :bundle_done
DO $$ BEGIN IF NOT EXISTS (SELECT FROM deployment.bundle_migrations WHERE name='011-ops-session-access.sql' AND sha256='71c0b64734199edd31d2198ae2970a2fa1608b44b25049a897c08f8497987c58') THEN RAISE EXCEPTION 'Empreinte différente : 011-ops-session-access.sql'; END IF; END $$;
\else
-- Grant genesis role access to ops schemas for ORBIT session APIs (Lot 6).
-- Required schemas: itsm, cmdb, commercial, service, delivery, project
-- Tables: contracts, tickets, items, catalog_items, service_instances, linking tables
-- Pattern: grants + RLS policies for genesis role (mirror 006-genesis-core-access.sql)

-- Schema access (idempotent)
GRANT USAGE ON SCHEMA itsm TO genesis;
GRANT USAGE ON SCHEMA cmdb TO genesis;
GRANT USAGE ON SCHEMA commercial TO genesis;
GRANT USAGE ON SCHEMA service TO genesis;
GRANT USAGE ON SCHEMA delivery TO genesis;
GRANT USAGE ON SCHEMA project TO genesis;

-- Commercial contracts (read-only for listing and detail)
GRANT SELECT ON commercial.contracts TO genesis;
GRANT SELECT ON commercial.contract_versions TO genesis;
GRANT SELECT ON commercial.contract_components TO genesis;
GRANT SELECT ON commercial.contract_scopes TO genesis;

-- ITSM tickets and linking tables (read + write for creating links)
GRANT SELECT ON itsm.tickets TO genesis;
GRANT SELECT ON itsm.ticket_types TO genesis;
GRANT SELECT ON itsm.statuses TO genesis;
GRANT SELECT, INSERT, UPDATE ON itsm.ticket_assets TO genesis;
GRANT SELECT, INSERT, UPDATE ON itsm.ticket_projects TO genesis;

-- CMDB items (read-only for asset browsing)
GRANT SELECT ON cmdb.items TO genesis;
GRANT SELECT ON cmdb.item_types TO genesis;

-- Service catalog (read-only, equivalent to service instances browsing)
GRANT SELECT ON service.catalog_items TO genesis;

-- Delivery service instances and linking tables (read-only browsing)
GRANT SELECT ON delivery.service_instances TO genesis;
GRANT SELECT ON delivery.service_instance_tickets TO genesis;
GRANT SELECT ON delivery.service_instance_projects TO genesis;
GRANT SELECT ON delivery.service_instance_assets TO genesis;
GRANT SELECT ON delivery.engagements TO genesis;
GRANT SELECT ON delivery.engagement_lines TO genesis;

-- Project (read-only for linking context)
GRANT SELECT ON project.projects TO genesis;

-- Core organizations and sites (needed for filtering)
GRANT SELECT ON core.organizations TO genesis;
GRANT SELECT ON core.sites TO genesis;

-- RLS policies: genesis can read all rows (mirror 006 pattern)
-- Only create policies if RLS is already enabled

DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM pg_policies 
    WHERE schemaname = 'commercial' AND tablename = 'contracts'
  ) THEN
    DROP POLICY IF EXISTS genesis_read_contracts ON commercial.contracts;
    CREATE POLICY genesis_read_contracts ON commercial.contracts
      FOR SELECT TO genesis USING (true);
  END IF;

  IF EXISTS (
    SELECT 1 FROM pg_policies 
    WHERE schemaname = 'itsm' AND tablename = 'tickets'
  ) THEN
    DROP POLICY IF EXISTS genesis_read_tickets ON itsm.tickets;
    CREATE POLICY genesis_read_tickets ON itsm.tickets
      FOR SELECT TO genesis USING (true);
      
    DROP POLICY IF EXISTS genesis_manage_ticket_assets ON itsm.ticket_assets;
    CREATE POLICY genesis_manage_ticket_assets ON itsm.ticket_assets
      FOR ALL TO genesis USING (true) WITH CHECK (true);
      
    DROP POLICY IF EXISTS genesis_manage_ticket_projects ON itsm.ticket_projects;
    CREATE POLICY genesis_manage_ticket_projects ON itsm.ticket_projects
      FOR ALL TO genesis USING (true) WITH CHECK (true);
  END IF;

  IF EXISTS (
    SELECT 1 FROM pg_policies 
    WHERE schemaname = 'cmdb' AND tablename = 'items'
  ) THEN
    DROP POLICY IF EXISTS genesis_read_items ON cmdb.items;
    CREATE POLICY genesis_read_items ON cmdb.items
      FOR SELECT TO genesis USING (true);
  END IF;

  IF EXISTS (
    SELECT 1 FROM pg_policies 
    WHERE schemaname = 'service' AND tablename = 'catalog_items'
  ) THEN
    DROP POLICY IF EXISTS genesis_read_catalog_items ON service.catalog_items;
    CREATE POLICY genesis_read_catalog_items ON service.catalog_items
      FOR SELECT TO genesis USING (true);
  END IF;

  IF EXISTS (
    SELECT 1 FROM pg_policies 
    WHERE schemaname = 'delivery' AND tablename = 'service_instances'
  ) THEN
    DROP POLICY IF EXISTS genesis_read_service_instances ON delivery.service_instances;
    CREATE POLICY genesis_read_service_instances ON delivery.service_instances
      FOR SELECT TO genesis USING (true);
  END IF;
END $$;

INSERT INTO deployment.bundle_migrations(name,sha256) VALUES ('011-ops-session-access.sql','71c0b64734199edd31d2198ae2970a2fa1608b44b25049a897c08f8497987c58');
\endif


-- ===== 012-core-write-access.sql =====
SELECT EXISTS (SELECT FROM deployment.bundle_migrations WHERE name='012-core-write-access.sql') AS bundle_done \gset
\if :bundle_done
DO $$ BEGIN IF NOT EXISTS (SELECT FROM deployment.bundle_migrations WHERE name='012-core-write-access.sql' AND sha256='3fb0bfe25e65bd5bebf3c2cc83b04d957044fa45c8bb3d2baa848a12a81405f0') THEN RAISE EXCEPTION 'Empreinte différente : 012-core-write-access.sql'; END IF; END $$;
\else
-- Grant genesis role INSERT access to core.organizations, core.persons, core.affiliations, and core.person_contacts.
-- Required for /api/core session API write endpoints (POST organizations/persons/affiliations).
-- Allows Site Lot7 to promote web.contact_requests into Core via GENESIS session.

-- Table access: add INSERT to existing SELECT grants (idempotent)
GRANT SELECT, INSERT ON core.organizations TO genesis;
GRANT SELECT, INSERT ON core.persons TO genesis;
GRANT SELECT, INSERT ON core.affiliations TO genesis;
GRANT SELECT, INSERT ON core.person_contacts TO genesis;

-- RLS policies: DROP then CREATE for idempotence

-- Organizations: allow genesis to insert all organizations
DROP POLICY IF EXISTS genesis_insert_organizations ON core.organizations;
CREATE POLICY genesis_insert_organizations ON core.organizations
  FOR INSERT
  TO genesis
  WITH CHECK (true);

-- Persons: allow genesis to insert all persons
DROP POLICY IF EXISTS genesis_insert_persons ON core.persons;
CREATE POLICY genesis_insert_persons ON core.persons
  FOR INSERT
  TO genesis
  WITH CHECK (true);

-- Person contacts: allow genesis to insert email addresses for new persons
DROP POLICY IF EXISTS genesis_insert_person_contacts ON core.person_contacts;
CREATE POLICY genesis_insert_person_contacts ON core.person_contacts
  FOR INSERT
  TO genesis
  WITH CHECK (true);

-- Affiliations: allow genesis to insert all affiliations
DROP POLICY IF EXISTS genesis_insert_affiliations ON core.affiliations;
CREATE POLICY genesis_insert_affiliations ON core.affiliations
  FOR INSERT
  TO genesis
  WITH CHECK (true);

INSERT INTO deployment.bundle_migrations(name,sha256) VALUES ('012-core-write-access.sql','3fb0bfe25e65bd5bebf3c2cc83b04d957044fa45c8bb3d2baa848a12a81405f0');
\endif


-- ===== 015-sales-lead-ingest.sql =====
SELECT EXISTS (SELECT FROM deployment.bundle_migrations WHERE name='015-sales-lead-ingest.sql') AS bundle_done \gset
\if :bundle_done
DO $$ BEGIN IF NOT EXISTS (SELECT FROM deployment.bundle_migrations WHERE name='015-sales-lead-ingest.sql' AND sha256='2e5ddcbc7acdf33ed246d12fed99f563a81fed375149a9b84032778e2cf0267e') THEN RAISE EXCEPTION 'Empreinte différente : 015-sales-lead-ingest.sql'; END IF; END $$;
\else
-- Site Lot7 / A2: service-token ingest of contact-form leads.
-- Grants genesis INSERT/SELECT on the existing inbound-form table web.contact_requests.
-- No new CRM tables: opportunity/quote/crm.leads were rejected as the first artefact
-- (they require org/account/pipeline/owner FKs or cannot store form fields).
--
-- Apply as postgres on database prodigital (Coolify):
--   psql "$DATABASE_URL_AS_POSTGRES" -v ON_ERROR_STOP=1 -f infra/prodigital/database/015-sales-lead-ingest.sql
--
-- NOTE: Tables already exist from 001-business.sql.
-- This migration only grants access and adds an operational idempotency table
-- in the genesis-owned schema.

\set ON_ERROR_STOP on

-- Inbound form rows (the sales artefact created by POST /api/sales/public/leads)
GRANT USAGE ON SCHEMA web TO genesis;
GRANT SELECT, INSERT ON web.contact_requests TO genesis;

-- RLS: foundation slice — genesis may insert and re-read ingested requests
DROP POLICY IF EXISTS genesis_insert_contact_requests ON web.contact_requests;
CREATE POLICY genesis_insert_contact_requests ON web.contact_requests
  FOR INSERT
  TO genesis
  WITH CHECK (true);

DROP POLICY IF EXISTS genesis_select_contact_requests ON web.contact_requests;
CREATE POLICY genesis_select_contact_requests ON web.contact_requests
  FOR SELECT
  TO genesis
  USING (true);

-- Idempotency keys for the Site → GENESIS ingest (7-day retention, enforced in API)
CREATE TABLE IF NOT EXISTS genesis.sales_lead_ingest_keys (
  key text PRIMARY KEY,
  request_hash text NOT NULL,
  result_id uuid NOT NULL,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  expires_at timestamptz NOT NULL
);

GRANT SELECT, INSERT, UPDATE, DELETE ON genesis.sales_lead_ingest_keys TO genesis;

INSERT INTO deployment.bundle_migrations(name,sha256) VALUES ('015-sales-lead-ingest.sql','2e5ddcbc7acdf33ed246d12fed99f563a81fed375149a9b84032778e2cf0267e');
\endif


-- ===== 016-core-mfa.sql =====
SELECT EXISTS (SELECT FROM deployment.bundle_migrations WHERE name='016-core-mfa.sql') AS bundle_done \gset
\if :bundle_done
DO $$ BEGIN IF NOT EXISTS (SELECT FROM deployment.bundle_migrations WHERE name='016-core-mfa.sql' AND sha256='cd7ec5dee4448640d64d280f637cfdea818eae072bec6eeb512116a084bb0550') THEN RAISE EXCEPTION 'Empreinte différente : 016-core-mfa.sql'; END IF; END $$;
\else
-- MFA for Core local identity (iam.principals / iam.local_accounts / iam.local_sessions).
-- identity_links forbids MFA secrets in the métier database; secrets stay in iam,
-- reachable only via SECURITY DEFINER functions (same pattern as 004-local-identity.sql).
-- No parallel genesis MFA tables.
--
-- Apply as postgres on database prodigital (Coolify):
--   psql "$DATABASE_URL_AS_POSTGRES" -v ON_ERROR_STOP=1 -f infra/prodigital/database/016-core-mfa.sql

BEGIN;

ALTER TABLE iam.local_sessions
  ADD COLUMN IF NOT EXISTS mfa_verified_at timestamptz;

CREATE TABLE IF NOT EXISTS iam.local_mfa_factors (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  principal_id uuid NOT NULL REFERENCES iam.principals(id) ON DELETE CASCADE,
  kind text NOT NULL CHECK (kind IN ('totp')),
  status text NOT NULL CHECK (status IN ('pending', 'active', 'disabled')),
  label text NOT NULL DEFAULT 'Authenticator',
  secret text NOT NULL CHECK (secret ~ '^[A-Z2-7]{16,64}$'),
  last_timestep bigint,
  enrolled_at timestamptz,
  last_used_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS local_mfa_factors_principal
  ON iam.local_mfa_factors (principal_id);
CREATE UNIQUE INDEX IF NOT EXISTS local_mfa_factors_one_open_totp
  ON iam.local_mfa_factors (principal_id)
  WHERE kind = 'totp' AND status IN ('pending', 'active');

CREATE TABLE IF NOT EXISTS iam.local_mfa_challenges (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  principal_id uuid NOT NULL REFERENCES iam.principals(id) ON DELETE CASCADE,
  factor_id uuid NOT NULL REFERENCES iam.local_mfa_factors(id) ON DELETE CASCADE,
  purpose text NOT NULL CHECK (purpose IN ('enroll', 'verify')),
  status text NOT NULL CHECK (status IN ('pending', 'consumed', 'expired')),
  expires_at timestamptz NOT NULL,
  failed_attempts integer NOT NULL DEFAULT 0 CHECK (failed_attempts >= 0),
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS local_mfa_challenges_principal
  ON iam.local_mfa_challenges (principal_id);

ALTER TABLE iam.local_mfa_factors ENABLE ROW LEVEL SECURITY;
ALTER TABLE iam.local_mfa_factors FORCE ROW LEVEL SECURITY;
ALTER TABLE iam.local_mfa_challenges ENABLE ROW LEVEL SECURITY;
ALTER TABLE iam.local_mfa_challenges FORCE ROW LEVEL SECURITY;
REVOKE ALL ON iam.local_mfa_factors FROM PUBLIC;
REVOKE ALL ON iam.local_mfa_challenges FROM PUBLIC;

CREATE OR REPLACE FUNCTION iam.mfa_actor(actor_hash text)
RETURNS uuid LANGUAGE sql STABLE SECURITY DEFINER SET search_path = pg_catalog AS $$
  SELECT s.principal_id
  FROM iam.local_sessions s
  JOIN iam.principals p ON p.id = s.principal_id
  WHERE s.token_hash = actor_hash
    AND s.revoked_at IS NULL
    AND s.expires_at > now()
    AND p.status = 'active';
$$;

CREATE OR REPLACE FUNCTION iam.mfa_status(actor_hash text)
RETURNS text LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog AS $$
DECLARE
  actor uuid;
  enrolled boolean;
  verified boolean;
  result jsonb;
BEGIN
  actor := iam.mfa_actor(actor_hash);
  IF actor IS NULL THEN RAISE EXCEPTION 'Unauthorized'; END IF;

  SELECT EXISTS (
    SELECT 1 FROM iam.local_mfa_factors
    WHERE principal_id = actor AND status = 'active'
  ) INTO enrolled;

  SELECT (s.mfa_verified_at IS NOT NULL)
  FROM iam.local_sessions s
  WHERE s.token_hash = actor_hash
  INTO verified;

  SELECT jsonb_build_object(
    'principalId', actor,
    'enrolled', enrolled,
    'required', false,
    'sessionMfaVerified', COALESCE(verified, false),
    'factors', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'id', f.id,
        'kind', f.kind,
        'status', f.status,
        'label', f.label,
        'enrolledAt', f.enrolled_at,
        'createdAt', f.created_at
      ) ORDER BY f.created_at)
      FROM iam.local_mfa_factors f
      WHERE f.principal_id = actor AND f.status IN ('pending', 'active')
    ), '[]'::jsonb)
  ) INTO result;

  RETURN result::text;
END $$;

CREATE OR REPLACE FUNCTION iam.mfa_enroll_start(actor_hash text, new_secret text)
RETURNS text LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog AS $$
DECLARE
  actor uuid;
  factor_id uuid;
  challenge_id uuid;
  expires timestamptz;
BEGIN
  actor := iam.mfa_actor(actor_hash);
  IF actor IS NULL THEN RAISE EXCEPTION 'Unauthorized'; END IF;
  IF new_secret !~ '^[A-Z2-7]{16,64}$' THEN RAISE EXCEPTION 'Invalid secret'; END IF;
  IF EXISTS (
    SELECT 1 FROM iam.local_mfa_factors
    WHERE principal_id = actor AND status = 'active'
  ) THEN RAISE EXCEPTION 'Already enrolled'; END IF;

  expires := now() + interval '15 minutes';

  UPDATE iam.local_mfa_challenges
    SET status = 'expired'
    WHERE principal_id = actor AND status = 'pending';
  UPDATE iam.local_mfa_factors
    SET status = 'disabled', updated_at = now()
    WHERE principal_id = actor AND status = 'pending';

  INSERT INTO iam.local_mfa_factors (principal_id, kind, status, secret)
  VALUES (actor, 'totp', 'pending', new_secret)
  RETURNING id INTO factor_id;

  INSERT INTO iam.local_mfa_challenges (principal_id, factor_id, purpose, status, expires_at)
  VALUES (actor, factor_id, 'enroll', 'pending', expires)
  RETURNING id INTO challenge_id;

  RETURN jsonb_build_object(
    'enrollmentId', factor_id,
    'challengeId', challenge_id,
    'factorId', factor_id,
    'kind', 'totp',
    'status', 'pending',
    'expiresAt', expires
  )::text;
EXCEPTION WHEN unique_violation THEN
  RAISE EXCEPTION 'Already enrolled';
END $$;

CREATE OR REPLACE FUNCTION iam.mfa_challenge_start(actor_hash text, requested_factor uuid)
RETURNS text LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog AS $$
DECLARE
  actor uuid;
  factor_id uuid;
  challenge_id uuid;
  factor_kind text;
  expires timestamptz;
BEGIN
  actor := iam.mfa_actor(actor_hash);
  IF actor IS NULL THEN RAISE EXCEPTION 'Unauthorized'; END IF;

  IF requested_factor IS NOT NULL THEN
    SELECT id, kind INTO factor_id, factor_kind
    FROM iam.local_mfa_factors
    WHERE id = requested_factor AND principal_id = actor AND status = 'active';
  ELSE
    SELECT id, kind INTO factor_id, factor_kind
    FROM iam.local_mfa_factors
    WHERE principal_id = actor AND status = 'active'
    ORDER BY enrolled_at DESC NULLS LAST, created_at DESC
    LIMIT 1;
  END IF;

  IF factor_id IS NULL THEN RAISE EXCEPTION 'Not enrolled'; END IF;

  expires := now() + interval '5 minutes';

  UPDATE iam.local_mfa_challenges
    SET status = 'expired'
    WHERE principal_id = actor AND status = 'pending' AND purpose = 'verify';

  INSERT INTO iam.local_mfa_challenges (principal_id, factor_id, purpose, status, expires_at)
  VALUES (actor, factor_id, 'verify', 'pending', expires)
  RETURNING id INTO challenge_id;

  RETURN jsonb_build_object(
    'challengeId', challenge_id,
    'factorId', factor_id,
    'kind', factor_kind,
    'status', 'pending',
    'expiresAt', expires
  )::text;
END $$;

CREATE OR REPLACE FUNCTION iam.mfa_load_verify(actor_hash text, enrollment_id uuid, challenge_id uuid)
RETURNS text LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog AS $$
DECLARE
  actor uuid;
  rec record;
BEGIN
  actor := iam.mfa_actor(actor_hash);
  IF actor IS NULL THEN RAISE EXCEPTION 'Unauthorized'; END IF;

  IF challenge_id IS NOT NULL THEN
    SELECT c.id AS challenge_id, c.factor_id, c.purpose, c.status, c.expires_at,
           c.failed_attempts, f.secret, f.last_timestep, f.status AS factor_status
    INTO rec
    FROM iam.local_mfa_challenges c
    JOIN iam.local_mfa_factors f ON f.id = c.factor_id
    WHERE c.id = challenge_id AND c.principal_id = actor;
  ELSIF enrollment_id IS NOT NULL THEN
    SELECT c.id AS challenge_id, c.factor_id, c.purpose, c.status, c.expires_at,
           c.failed_attempts, f.secret, f.last_timestep, f.status AS factor_status
    INTO rec
    FROM iam.local_mfa_factors f
    JOIN iam.local_mfa_challenges c ON c.factor_id = f.id AND c.purpose = 'enroll' AND c.status = 'pending'
    WHERE f.id = enrollment_id AND f.principal_id = actor
    ORDER BY c.created_at DESC
    LIMIT 1;
  ELSE
    SELECT c.id AS challenge_id, c.factor_id, c.purpose, c.status, c.expires_at,
           c.failed_attempts, f.secret, f.last_timestep, f.status AS factor_status
    INTO rec
    FROM iam.local_mfa_challenges c
    JOIN iam.local_mfa_factors f ON f.id = c.factor_id
    WHERE c.principal_id = actor AND c.status = 'pending'
    ORDER BY c.created_at DESC
    LIMIT 1;
  END IF;

  IF rec.challenge_id IS NULL THEN RAISE EXCEPTION 'Challenge not found'; END IF;
  IF rec.status <> 'pending' OR rec.expires_at <= now() THEN
    UPDATE iam.local_mfa_challenges SET status = 'expired'
    WHERE id = rec.challenge_id AND status = 'pending';
    RAISE EXCEPTION 'Challenge expired';
  END IF;
  IF rec.failed_attempts >= 5 THEN RAISE EXCEPTION 'Locked'; END IF;
  IF rec.purpose = 'enroll' AND rec.factor_status <> 'pending' THEN RAISE EXCEPTION 'Challenge expired'; END IF;
  IF rec.purpose = 'verify' AND rec.factor_status <> 'active' THEN RAISE EXCEPTION 'Not enrolled'; END IF;

  RETURN jsonb_build_object(
    'challengeId', rec.challenge_id,
    'factorId', rec.factor_id,
    'purpose', rec.purpose,
    'secret', rec.secret,
    'lastTimestep', rec.last_timestep
  )::text;
END $$;

CREATE OR REPLACE FUNCTION iam.mfa_complete_verify(actor_hash text, challenge_id uuid, timestep bigint)
RETURNS text LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog AS $$
DECLARE
  actor uuid;
  rec record;
BEGIN
  actor := iam.mfa_actor(actor_hash);
  IF actor IS NULL THEN RAISE EXCEPTION 'Unauthorized'; END IF;
  IF timestep IS NULL OR timestep < 0 THEN RAISE EXCEPTION 'Invalid code'; END IF;

  SELECT c.id, c.factor_id, c.purpose, c.status, c.expires_at, f.status AS factor_status
  INTO rec
  FROM iam.local_mfa_challenges c
  JOIN iam.local_mfa_factors f ON f.id = c.factor_id
  WHERE c.id = challenge_id AND c.principal_id = actor
  FOR UPDATE OF c;

  IF rec.id IS NULL THEN RAISE EXCEPTION 'Challenge not found'; END IF;
  IF rec.status <> 'pending' OR rec.expires_at <= now() THEN RAISE EXCEPTION 'Challenge expired'; END IF;

  IF rec.purpose = 'enroll' THEN
    UPDATE iam.local_mfa_factors
      SET status = 'active', enrolled_at = now(), last_used_at = now(),
          last_timestep = timestep, updated_at = now()
      WHERE id = rec.factor_id AND principal_id = actor AND status = 'pending';
    IF NOT FOUND THEN RAISE EXCEPTION 'Challenge expired'; END IF;
  ELSE
    UPDATE iam.local_mfa_factors
      SET last_used_at = now(), last_timestep = timestep, updated_at = now()
      WHERE id = rec.factor_id AND principal_id = actor AND status = 'active';
    IF NOT FOUND THEN RAISE EXCEPTION 'Not enrolled'; END IF;
  END IF;

  UPDATE iam.local_mfa_challenges
    SET status = 'consumed'
    WHERE id = rec.id AND status = 'pending';

  UPDATE iam.local_sessions
    SET mfa_verified_at = now(), confirmed_at = now(), expires_at = now() + interval '8 hours'
    WHERE token_hash = actor_hash AND revoked_at IS NULL AND expires_at > now();

  RETURN jsonb_build_object(
    'ok', true,
    'purpose', rec.purpose,
    'factorId', rec.factor_id,
    'challengeId', rec.id,
    'enrolled', true,
    'sessionMfaVerified', true
  )::text;
END $$;

CREATE OR REPLACE FUNCTION iam.mfa_fail_verify(actor_hash text, challenge_id uuid)
RETURNS text LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog AS $$
DECLARE
  actor uuid;
  attempts integer;
  locked boolean;
BEGIN
  actor := iam.mfa_actor(actor_hash);
  IF actor IS NULL THEN RAISE EXCEPTION 'Unauthorized'; END IF;

  UPDATE iam.local_mfa_challenges
    SET failed_attempts = failed_attempts + 1,
        status = CASE WHEN failed_attempts + 1 >= 5 THEN 'expired' ELSE status END
    WHERE id = challenge_id AND principal_id = actor AND status = 'pending'
    RETURNING failed_attempts, status = 'expired' INTO attempts, locked;

  IF attempts IS NULL THEN RAISE EXCEPTION 'Challenge not found'; END IF;
  IF locked THEN RAISE EXCEPTION 'Locked'; END IF;
  RETURN jsonb_build_object('ok', false, 'failedAttempts', attempts)::text;
END $$;

REVOKE ALL ON FUNCTION iam.mfa_actor(text), iam.mfa_status(text),
  iam.mfa_enroll_start(text, text), iam.mfa_challenge_start(text, uuid),
  iam.mfa_load_verify(text, uuid, uuid), iam.mfa_complete_verify(text, uuid, bigint),
  iam.mfa_fail_verify(text, uuid) FROM PUBLIC;
GRANT USAGE ON SCHEMA iam TO genesis;
GRANT EXECUTE ON FUNCTION iam.mfa_status(text),
  iam.mfa_enroll_start(text, text), iam.mfa_challenge_start(text, uuid),
  iam.mfa_load_verify(text, uuid, uuid), iam.mfa_complete_verify(text, uuid, bigint),
  iam.mfa_fail_verify(text, uuid) TO genesis;

COMMIT;

INSERT INTO deployment.bundle_migrations(name,sha256) VALUES ('016-core-mfa.sql','cd7ec5dee4448640d64d280f637cfdea818eae072bec6eeb512116a084bb0550');
\endif


-- ===== 016-sales-opportunities-access.sql =====
SELECT EXISTS (SELECT FROM deployment.bundle_migrations WHERE name='016-sales-opportunities-access.sql') AS bundle_done \gset
\if :bundle_done
DO $$ BEGIN IF NOT EXISTS (SELECT FROM deployment.bundle_migrations WHERE name='016-sales-opportunities-access.sql' AND sha256='83a3ab701251dea8e319496f4e5ff079be70d76d16477e67d89644e7ba530917') THEN RAISE EXCEPTION 'Empreinte différente : 016-sales-opportunities-access.sql'; END IF; END $$;
\else
-- Session CRM opportunities for genesis (Lot 4 gap on live Coolify).
-- Reuses existing Core tables from 001-business.sql: crm.opportunities,
-- crm.accounts, crm.pipelines, crm.stages, crm.opportunity_lines,
-- crm.opportunity_history. No parallel sales tables.
--
-- Adds optional UTM attribution columns on crm.opportunities (aligned with
-- Core conventions: optional text, snake_case) when they are missing.
-- Seeds the default commercial pipeline if it is not already present.
--
-- Apply as postgres on database prodigital (Coolify):
--   psql "$DATABASE_URL_AS_POSTGRES" -v ON_ERROR_STOP=1 -f infra/prodigital/database/016-sales-opportunities-access.sql
--
-- NOTE: Tables already exist from 001-business.sql.
-- This migration grants genesis access, adds UTM columns, and seeds catalog rows.

\set ON_ERROR_STOP on

GRANT USAGE ON SCHEMA crm TO genesis;

GRANT SELECT, INSERT, UPDATE ON crm.accounts TO genesis;
GRANT SELECT ON crm.pipelines TO genesis;
GRANT SELECT ON crm.stages TO genesis;
GRANT SELECT, INSERT, UPDATE ON crm.opportunities TO genesis;
GRANT SELECT, INSERT ON crm.opportunity_lines TO genesis;
GRANT SELECT, INSERT ON crm.opportunity_history TO genesis;

-- Optional UTM attribution (no-op when already present)
ALTER TABLE crm.opportunities ADD COLUMN IF NOT EXISTS utm_source text;
ALTER TABLE crm.opportunities ADD COLUMN IF NOT EXISTS utm_medium text;
ALTER TABLE crm.opportunities ADD COLUMN IF NOT EXISTS utm_campaign text;
ALTER TABLE crm.opportunities ADD COLUMN IF NOT EXISTS utm_content text;
ALTER TABLE crm.opportunities ADD COLUMN IF NOT EXISTS utm_term text;

COMMENT ON COLUMN crm.opportunities.utm_source IS 'Attribution UTM source (campagne / formulaire).';
COMMENT ON COLUMN crm.opportunities.utm_medium IS 'Attribution UTM medium.';
COMMENT ON COLUMN crm.opportunities.utm_campaign IS 'Attribution UTM campaign.';
COMMENT ON COLUMN crm.opportunities.utm_content IS 'Attribution UTM content.';
COMMENT ON COLUMN crm.opportunities.utm_term IS 'Attribution UTM term.';

-- RLS: foundation slice — genesis may read/write CRM sales rows (mirror 008/012)
DROP POLICY IF EXISTS genesis_select_accounts ON crm.accounts;
CREATE POLICY genesis_select_accounts ON crm.accounts
  FOR SELECT TO genesis USING (true);

DROP POLICY IF EXISTS genesis_insert_accounts ON crm.accounts;
CREATE POLICY genesis_insert_accounts ON crm.accounts
  FOR INSERT TO genesis WITH CHECK (true);

DROP POLICY IF EXISTS genesis_update_accounts ON crm.accounts;
CREATE POLICY genesis_update_accounts ON crm.accounts
  FOR UPDATE TO genesis USING (true) WITH CHECK (true);

DROP POLICY IF EXISTS genesis_select_pipelines ON crm.pipelines;
CREATE POLICY genesis_select_pipelines ON crm.pipelines
  FOR SELECT TO genesis USING (true);

DROP POLICY IF EXISTS genesis_select_stages ON crm.stages;
CREATE POLICY genesis_select_stages ON crm.stages
  FOR SELECT TO genesis USING (true);

DROP POLICY IF EXISTS genesis_select_opportunities ON crm.opportunities;
CREATE POLICY genesis_select_opportunities ON crm.opportunities
  FOR SELECT TO genesis USING (true);

DROP POLICY IF EXISTS genesis_insert_opportunities ON crm.opportunities;
CREATE POLICY genesis_insert_opportunities ON crm.opportunities
  FOR INSERT TO genesis WITH CHECK (true);

DROP POLICY IF EXISTS genesis_update_opportunities ON crm.opportunities;
CREATE POLICY genesis_update_opportunities ON crm.opportunities
  FOR UPDATE TO genesis USING (true) WITH CHECK (true);

DROP POLICY IF EXISTS genesis_select_opportunity_lines ON crm.opportunity_lines;
CREATE POLICY genesis_select_opportunity_lines ON crm.opportunity_lines
  FOR SELECT TO genesis USING (true);

DROP POLICY IF EXISTS genesis_insert_opportunity_lines ON crm.opportunity_lines;
CREATE POLICY genesis_insert_opportunity_lines ON crm.opportunity_lines
  FOR INSERT TO genesis WITH CHECK (true);

DROP POLICY IF EXISTS genesis_select_opportunity_history ON crm.opportunity_history;
CREATE POLICY genesis_select_opportunity_history ON crm.opportunity_history
  FOR SELECT TO genesis USING (true);

DROP POLICY IF EXISTS genesis_insert_opportunity_history ON crm.opportunity_history;
CREATE POLICY genesis_insert_opportunity_history ON crm.opportunity_history
  FOR INSERT TO genesis WITH CHECK (true);

-- Default commercial pipeline (idempotent). Superuser applying this file
-- bypasses FORCE RLS. Codes match GENESIS UI stages (src/stages.ts).
INSERT INTO crm.pipelines (code, label, active)
SELECT 'sales', 'Pipeline commercial', true
WHERE NOT EXISTS (SELECT 1 FROM crm.pipelines WHERE code = 'sales');

INSERT INTO crm.stages (pipeline_id, code, label, position, probability, terminal_kind)
SELECT p.id, v.code, v.label, v.position, v.probability, v.terminal_kind
FROM crm.pipelines p
CROSS JOIN (
  VALUES
    ('nouveau', 'Nouveau lead', 1, 0.10, NULL::text),
    ('qualifie', 'Qualifié', 2, 0.25, NULL::text),
    ('demo', 'Démo / RDV', 3, 0.40, NULL::text),
    ('proposition', 'Proposition', 4, 0.55, NULL::text),
    ('negociation', 'Négociation', 5, 0.75, NULL::text),
    ('gagne', 'Gagné', 6, 1.00, 'won'),
    ('perdu', 'Perdu', 7, 0.00, 'lost')
) AS v(code, label, position, probability, terminal_kind)
WHERE p.code = 'sales'
  AND NOT EXISTS (
    SELECT 1 FROM crm.stages s
    WHERE s.pipeline_id = p.id AND s.code = v.code
  )
  AND NOT EXISTS (
    SELECT 1 FROM crm.stages s
    WHERE s.pipeline_id = p.id AND s.position = v.position
  );

INSERT INTO deployment.bundle_migrations(name,sha256) VALUES ('016-sales-opportunities-access.sql','83a3ab701251dea8e319496f4e5ff079be70d76d16477e67d89644e7ba530917');
\endif


-- ===== 017-sales-lead-utm.sql =====
SELECT EXISTS (SELECT FROM deployment.bundle_migrations WHERE name='017-sales-lead-utm.sql') AS bundle_done \gset
\if :bundle_done
DO $$ BEGIN IF NOT EXISTS (SELECT FROM deployment.bundle_migrations WHERE name='017-sales-lead-utm.sql' AND sha256='ebdad5f1be55ef614d2e17b39c9f58a85f374fd6fd1d94e79cc162c8ba3ca97b') THEN RAISE EXCEPTION 'Empreinte différente : 017-sales-lead-utm.sql'; END IF; END $$;
\else
-- Site → GENESIS public lead ingest: optional UTM attribution on the
-- existing inbound-form row (web.contact_requests). Same column names as
-- crm.opportunities (migration 016). No parallel tables.
--
-- Grants already exist from 015-sales-lead-ingest.sql (SELECT/INSERT).
-- This file only adds nullable UTM columns when they are missing.
--
-- Apply as postgres on database prodigital (Coolify):
--   psql "$DATABASE_URL_AS_POSTGRES" -v ON_ERROR_STOP=1 -f infra/prodigital/database/017-sales-lead-utm.sql
--
-- NOTE: Table already exists from 001-business.sql.
-- Public ingest still writes web.contact_requests (not crm.opportunities):
-- an anonymous form must not invent account / pipeline / owner FKs.

\set ON_ERROR_STOP on

ALTER TABLE web.contact_requests ADD COLUMN IF NOT EXISTS utm_source text;
ALTER TABLE web.contact_requests ADD COLUMN IF NOT EXISTS utm_medium text;
ALTER TABLE web.contact_requests ADD COLUMN IF NOT EXISTS utm_campaign text;
ALTER TABLE web.contact_requests ADD COLUMN IF NOT EXISTS utm_content text;
ALTER TABLE web.contact_requests ADD COLUMN IF NOT EXISTS utm_term text;

COMMENT ON COLUMN web.contact_requests.utm_source IS 'Attribution UTM source (campagne / formulaire Site).';
COMMENT ON COLUMN web.contact_requests.utm_medium IS 'Attribution UTM medium.';
COMMENT ON COLUMN web.contact_requests.utm_campaign IS 'Attribution UTM campaign.';
COMMENT ON COLUMN web.contact_requests.utm_content IS 'Attribution UTM content.';
COMMENT ON COLUMN web.contact_requests.utm_term IS 'Attribution UTM term.';

INSERT INTO deployment.bundle_migrations(name,sha256) VALUES ('017-sales-lead-utm.sql','ebdad5f1be55ef614d2e17b39c9f58a85f374fd6fd1d94e79cc162c8ba3ca97b');
\endif


-- ===== 019-core-offboard-write.sql =====
SELECT EXISTS (SELECT FROM deployment.bundle_migrations WHERE name='019-core-offboard-write.sql') AS bundle_done \gset
\if :bundle_done
DO $$ BEGIN IF NOT EXISTS (SELECT FROM deployment.bundle_migrations WHERE name='019-core-offboard-write.sql' AND sha256='ccc617ced255ae6b8453f68d435fd5678e5a3690f31e9deac1ebc5f2d26a090f') THEN RAISE EXCEPTION 'Empreinte différente : 019-core-offboard-write.sql'; END IF; END $$;
\else
-- Grant genesis UPDATE on Core identity tables used by offboard.
-- Database: prodigital (NOT prodigital_platform)
-- Run as: postgres
--
-- Completes 009 (SELECT) + 012 (INSERT). Offboard marks rows in place:
-- deactivate organization, close affiliations, anonymize exclusive persons.
-- No DELETE. No parallel tables.

GRANT SELECT, INSERT, UPDATE ON core.organizations TO genesis;
GRANT SELECT, INSERT, UPDATE ON core.persons TO genesis;
GRANT SELECT, INSERT, UPDATE ON core.affiliations TO genesis;
GRANT SELECT, INSERT, UPDATE ON core.person_contacts TO genesis;

DROP POLICY IF EXISTS genesis_update_organizations ON core.organizations;
CREATE POLICY genesis_update_organizations ON core.organizations
  FOR UPDATE
  TO genesis
  USING (true)
  WITH CHECK (true);

DROP POLICY IF EXISTS genesis_update_persons ON core.persons;
CREATE POLICY genesis_update_persons ON core.persons
  FOR UPDATE
  TO genesis
  USING (true)
  WITH CHECK (true);

DROP POLICY IF EXISTS genesis_update_affiliations ON core.affiliations;
CREATE POLICY genesis_update_affiliations ON core.affiliations
  FOR UPDATE
  TO genesis
  USING (true)
  WITH CHECK (true);

DROP POLICY IF EXISTS genesis_update_person_contacts ON core.person_contacts;
CREATE POLICY genesis_update_person_contacts ON core.person_contacts
  FOR UPDATE
  TO genesis
  USING (true)
  WITH CHECK (true);

INSERT INTO deployment.bundle_migrations(name,sha256) VALUES ('019-core-offboard-write.sql','ccc617ced255ae6b8453f68d435fd5678e5a3690f31e9deac1ebc5f2d26a090f');
\endif


-- ===== 020-itsm-ticket-event-journal.sql =====
SELECT EXISTS (SELECT FROM deployment.bundle_migrations WHERE name='020-itsm-ticket-event-journal.sql') AS bundle_done \gset
\if :bundle_done
DO $$ BEGIN IF NOT EXISTS (SELECT FROM deployment.bundle_migrations WHERE name='020-itsm-ticket-event-journal.sql' AND sha256='29e6d56a86654cf39676782635a0e317db549d26644d7da8c4ac61dc60bcfd25') THEN RAISE EXCEPTION 'Empreinte différente : 020-itsm-ticket-event-journal.sql'; END IF; END $$;
\else
-- 020: journal atomique itsm.ticket_events on every ticket insert / status change.
-- PR #13 already inserts from the API, but a transition can still commit without a
-- matching event: invalid actor_id (FK to iam.principals — session ids are principals,
-- machine agent ids like agt-… are not), RLS WITH CHECK, or a write path that skips
-- insertTicketEvent. Catalogue: « Écriture atomique avec la modification ».
--
-- This migration does not add a parallel table. it reuses itsm.ticket_events.
-- SECURITY DEFINER (owner postgres) so the insert is not subject to orbit RLS;
-- listing still goes through orbit_events_select (007).
--
-- Apply as postgres on database prodigital (Coolify / PF-YANIS):
--   psql "$DATABASE_URL_AS_POSTGRES" -v ON_ERROR_STOP=1 -f infra/prodigital/database/020-itsm-ticket-event-journal.sql
--
-- Idempotent. Does not touch MFA / quotas / offboard / backup / sales.

BEGIN;

CREATE OR REPLACE FUNCTION itsm.record_ticket_event(
  p_ticket_id uuid,
  p_event_type text,
  p_actor_id uuid,
  p_from_status_id uuid,
  p_to_status_id uuid,
  p_payload jsonb
) RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog
AS $$
DECLARE
  v_actor uuid;
  v_id uuid;
  v_corr text;
BEGIN
  IF p_ticket_id IS NULL OR p_event_type IS NULL OR btrim(p_event_type) = '' THEN
    RAISE EXCEPTION 'itsm.record_ticket_event: ticket_id and event_type are required';
  END IF;

  -- Same transaction (now() is the transaction timestamp): app + trigger share one row.
  SELECT e.id INTO v_id
  FROM itsm.ticket_events AS e
  WHERE e.ticket_id = p_ticket_id
    AND e.event_type = p_event_type
    AND e.from_status_id IS NOT DISTINCT FROM p_from_status_id
    AND e.to_status_id IS NOT DISTINCT FROM p_to_status_id
    AND e.occurred_at = now()
  LIMIT 1;
  IF v_id IS NOT NULL THEN
    RETURN v_id;
  END IF;

  v_actor := NULL;
  IF p_actor_id IS NOT NULL THEN
    SELECT p.id INTO v_actor FROM iam.principals AS p WHERE p.id = p_actor_id;
  END IF;

  v_corr := 'evt-' || replace(gen_random_uuid()::text, '-', '');

  INSERT INTO itsm.ticket_events (
    ticket_id, event_type, actor_id, occurred_at,
    from_status_id, to_status_id, payload, correlation_id
  ) VALUES (
    p_ticket_id,
    p_event_type,
    v_actor,
    now(),
    p_from_status_id,
    p_to_status_id,
    COALESCE(p_payload, '{}'::jsonb),
    v_corr
  )
  RETURNING id INTO v_id;

  RETURN v_id;
END;
$$;

ALTER FUNCTION itsm.record_ticket_event(uuid, text, uuid, uuid, uuid, jsonb) OWNER TO postgres;
REVOKE ALL ON FUNCTION itsm.record_ticket_event(uuid, text, uuid, uuid, uuid, jsonb) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION itsm.record_ticket_event(uuid, text, uuid, uuid, uuid, jsonb) TO orbit;

CREATE OR REPLACE FUNCTION itsm.tg_ticket_status_event()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog
AS $$
DECLARE
  v_actor uuid;
  v_actor_txt text;
  v_from_code text;
  v_to_code text;
  v_type_code text;
BEGIN
  v_actor_txt := nullif(current_setting('app.actor_id', true), '');
  IF v_actor_txt IS NOT NULL THEN
    BEGIN
      v_actor := v_actor_txt::uuid;
    EXCEPTION WHEN invalid_text_representation THEN
      v_actor := NULL;
    END;
  END IF;

  IF TG_OP = 'INSERT' THEN
    SELECT tt.code INTO v_type_code FROM itsm.ticket_types AS tt WHERE tt.id = NEW.type_id;
    PERFORM itsm.record_ticket_event(
      NEW.id,
      'created',
      v_actor,
      NULL,
      NEW.status_id,
      jsonb_build_object(
        'title', NEW.title,
        'type', v_type_code,
        'priority', NEW.priority_code,
        'source', NEW.source
      )
    );
    RETURN NEW;
  END IF;

  IF TG_OP = 'UPDATE' AND OLD.status_id IS DISTINCT FROM NEW.status_id THEN
    SELECT s.code INTO v_from_code FROM itsm.statuses AS s WHERE s.id = OLD.status_id;
    SELECT s.code INTO v_to_code FROM itsm.statuses AS s WHERE s.id = NEW.status_id;
    PERFORM itsm.record_ticket_event(
      NEW.id,
      'transition',
      v_actor,
      OLD.status_id,
      NEW.status_id,
      jsonb_build_object(
        'from_status', v_from_code,
        'to_status', v_to_code
      )
    );
  END IF;

  RETURN NEW;
END;
$$;

ALTER FUNCTION itsm.tg_ticket_status_event() OWNER TO postgres;
REVOKE ALL ON FUNCTION itsm.tg_ticket_status_event() FROM PUBLIC;

DROP TRIGGER IF EXISTS c_ticket_status_event ON itsm.tickets;
CREATE TRIGGER c_ticket_status_event
  AFTER INSERT OR UPDATE OF status_id ON itsm.tickets
  FOR EACH ROW
  EXECUTE FUNCTION itsm.tg_ticket_status_event();

COMMENT ON FUNCTION itsm.record_ticket_event(uuid, text, uuid, uuid, uuid, jsonb) IS
  'Insert itsm.ticket_events (created/transition). Nulls actor_id when it is not iam.principals.id. Dedups per transaction.';
COMMENT ON FUNCTION itsm.tg_ticket_status_event() IS
  'AFTER INSERT/UPDATE OF status_id on itsm.tickets: write a matching itsm.ticket_events row. Reads app.actor_id.';

COMMIT;

INSERT INTO deployment.bundle_migrations(name,sha256) VALUES ('020-itsm-ticket-event-journal.sql','29e6d56a86654cf39676782635a0e317db549d26644d7da8c4ac61dc60bcfd25');
\endif


-- ===== 021-assistants-session-access.sql =====
SELECT EXISTS (SELECT FROM deployment.bundle_migrations WHERE name='021-assistants-session-access.sql') AS bundle_done \gset
\if :bundle_done
DO $$ BEGIN IF NOT EXISTS (SELECT FROM deployment.bundle_migrations WHERE name='021-assistants-session-access.sql' AND sha256='cdad30381d9d3dfa73e72b547f5877229e8d39226375f93071479ff017549866') THEN RAISE EXCEPTION 'Empreinte différente : 021-assistants-session-access.sql'; END IF; END $$;
\else
-- Lot 9 foundation: session API for Console assistants (read + human approval).
-- Database: prodigital (NOT prodigital_platform)
-- Run as: postgres
--
-- Reuses iam.principals / iam.identity_links / iam.service_credentials for
-- ProDigital Copilot and ProDigital Tech (no second SSO, no genesis.* copies).
-- workflow.approval_requests cannot store an assistant proposal: it requires
-- instance_id or ticket_id. Smallest new table is iam.assistant_proposals.
-- Decisions are kept on that row; governance.audit_events is the immutable log.
--
-- After 020-itsm-ticket-event-journal.sql.
--   psql "$DATABASE_URL_AS_POSTGRES" -v ON_ERROR_STOP=1 -f infra/prodigital/database/021-assistants-session-access.sql

BEGIN;

CREATE TABLE IF NOT EXISTS iam.assistant_proposals (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  proposed_by uuid NOT NULL REFERENCES iam.principals(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE,
  organization_id uuid REFERENCES core.organizations(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE,
  action_code text NOT NULL CHECK (char_length(action_code) BETWEEN 1 AND 120),
  target_type text NOT NULL CHECK (char_length(target_type) BETWEEN 1 AND 80),
  target_id uuid,
  summary text NOT NULL CHECK (char_length(summary) BETWEEN 1 AND 2000),
  payload jsonb NOT NULL DEFAULT '{}'::jsonb,
  status text NOT NULL CHECK (status IN ('pending', 'approved', 'refused', 'expired')),
  due_at timestamptz,
  decided_at timestamptz,
  decided_by uuid REFERENCES iam.principals(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE,
  decision_reason text CHECK (decision_reason IS NULL OR char_length(decision_reason) <= 2000),
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  row_version bigint NOT NULL DEFAULT 1 CHECK (row_version > 0)
);

COMMENT ON TABLE iam.assistant_proposals IS
  'Propositions d’action des assistants (Lot 9) | Pas d’exécution métier ici : approbation humaine + audit seulement.';

CREATE INDEX IF NOT EXISTS assistant_proposals_status ON iam.assistant_proposals (status, created_at DESC);
CREATE INDEX IF NOT EXISTS assistant_proposals_org ON iam.assistant_proposals (organization_id);
CREATE INDEX IF NOT EXISTS assistant_proposals_proposed_by ON iam.assistant_proposals (proposed_by);
CREATE INDEX IF NOT EXISTS assistant_proposals_decided_at ON iam.assistant_proposals (decided_at DESC);

DROP TRIGGER IF EXISTS z_touch ON iam.assistant_proposals;
CREATE TRIGGER z_touch BEFORE UPDATE ON iam.assistant_proposals
  FOR EACH ROW EXECUTE FUNCTION infrastructure.touch_row();

ALTER TABLE iam.assistant_proposals ENABLE ROW LEVEL SECURITY;
ALTER TABLE iam.assistant_proposals FORCE ROW LEVEL SECURITY;

GRANT USAGE ON SCHEMA iam TO genesis;
GRANT USAGE ON SCHEMA governance TO genesis;

GRANT SELECT ON iam.principals TO genesis;
GRANT SELECT ON iam.identity_links TO genesis;
GRANT SELECT ON iam.service_credentials TO genesis;
GRANT SELECT ON iam.roles TO genesis;
GRANT SELECT ON iam.role_bindings TO genesis;
GRANT SELECT ON iam.access_scopes TO genesis;
GRANT SELECT, INSERT, UPDATE ON iam.assistant_proposals TO genesis;
GRANT SELECT, INSERT ON governance.audit_events TO genesis;

DROP POLICY IF EXISTS genesis_read_principals ON iam.principals;
CREATE POLICY genesis_read_principals ON iam.principals
  FOR SELECT TO genesis USING (true);

DROP POLICY IF EXISTS genesis_read_identity_links ON iam.identity_links;
CREATE POLICY genesis_read_identity_links ON iam.identity_links
  FOR SELECT TO genesis USING (true);

DROP POLICY IF EXISTS genesis_read_service_credentials ON iam.service_credentials;
CREATE POLICY genesis_read_service_credentials ON iam.service_credentials
  FOR SELECT TO genesis USING (true);

DROP POLICY IF EXISTS genesis_read_roles ON iam.roles;
CREATE POLICY genesis_read_roles ON iam.roles
  FOR SELECT TO genesis USING (true);

DROP POLICY IF EXISTS genesis_read_role_bindings ON iam.role_bindings;
CREATE POLICY genesis_read_role_bindings ON iam.role_bindings
  FOR SELECT TO genesis USING (true);

DROP POLICY IF EXISTS genesis_read_access_scopes ON iam.access_scopes;
CREATE POLICY genesis_read_access_scopes ON iam.access_scopes
  FOR SELECT TO genesis USING (true);

DROP POLICY IF EXISTS genesis_read_assistant_proposals ON iam.assistant_proposals;
CREATE POLICY genesis_read_assistant_proposals ON iam.assistant_proposals
  FOR SELECT TO genesis USING (true);

DROP POLICY IF EXISTS genesis_insert_assistant_proposals ON iam.assistant_proposals;
CREATE POLICY genesis_insert_assistant_proposals ON iam.assistant_proposals
  FOR INSERT TO genesis WITH CHECK (true);

DROP POLICY IF EXISTS genesis_update_assistant_proposals ON iam.assistant_proposals;
CREATE POLICY genesis_update_assistant_proposals ON iam.assistant_proposals
  FOR UPDATE TO genesis USING (true) WITH CHECK (true);

DROP POLICY IF EXISTS genesis_read_audit_events ON governance.audit_events;
CREATE POLICY genesis_read_audit_events ON governance.audit_events
  FOR SELECT TO genesis USING (true);

DROP POLICY IF EXISTS genesis_insert_audit_events ON governance.audit_events;
CREATE POLICY genesis_insert_audit_events ON governance.audit_events
  FOR INSERT TO genesis WITH CHECK (true);

INSERT INTO iam.access_scopes (kind)
SELECT 'installation'
WHERE NOT EXISTS (SELECT 1 FROM iam.access_scopes WHERE kind = 'installation');

-- Copilot / Tech : identités IAM stables (issuer + subject), pas un second SSO.
INSERT INTO iam.principals (kind, status, display_name)
SELECT v.kind, v.status, v.display_name
FROM (VALUES
  ('service', 'active', 'ProDigital Copilot', 'copilot'),
  ('service', 'active', 'ProDigital Tech', 'tech')
) AS v(kind, status, display_name, subject)
WHERE NOT EXISTS (
  SELECT 1 FROM iam.identity_links l
  WHERE l.issuer = 'prodigital.assistants' AND l.subject = v.subject
);

INSERT INTO iam.identity_links (principal_id, issuer, subject)
SELECT p.id, 'prodigital.assistants', v.subject
FROM (VALUES
  ('ProDigital Copilot', 'copilot'),
  ('ProDigital Tech', 'tech')
) AS v(display_name, subject)
JOIN LATERAL (
  SELECT p.id FROM iam.principals p
  WHERE p.kind = 'service' AND p.display_name = v.display_name
  ORDER BY p.created_at DESC
  LIMIT 1
) p ON true
ON CONFLICT (issuer, subject) DO NOTHING;

INSERT INTO iam.service_credentials (principal_id, key_fingerprint, secret_ref, scopes)
SELECT l.principal_id, 'assistants:' || l.subject, NULL,
  CASE l.subject
    WHEN 'copilot' THEN jsonb_build_array('core.read', 'crm.read', 'itsm.read', 'project.read', 'ops.read')
    ELSE jsonb_build_array('core.read', 'ops.read', 'itsm.read', 'ops.diagnose')
  END
FROM iam.identity_links l
WHERE l.issuer = 'prodigital.assistants' AND l.subject IN ('copilot', 'tech')
ON CONFLICT (key_fingerprint) DO NOTHING;

INSERT INTO iam.role_bindings (principal_id, role_id, scope_id, valid_from, granted_by)
SELECT l.principal_id, r.id, s.id, clock_timestamp(), l.principal_id
FROM iam.identity_links l
JOIN iam.roles r ON r.code = CASE l.subject WHEN 'tech' THEN 'technician' ELSE 'collaborator' END
JOIN LATERAL (
  SELECT scope.id FROM iam.access_scopes scope
  WHERE scope.kind = 'installation'
  ORDER BY scope.created_at
  LIMIT 1
) s ON true
WHERE l.issuer = 'prodigital.assistants' AND l.subject IN ('copilot', 'tech')
  AND NOT EXISTS (
    SELECT 1 FROM iam.role_bindings b
    WHERE b.principal_id = l.principal_id AND b.role_id = r.id AND b.scope_id = s.id
  );

COMMIT;

INSERT INTO deployment.bundle_migrations(name,sha256) VALUES ('021-assistants-session-access.sql','cdad30381d9d3dfa73e72b547f5877229e8d39226375f93071479ff017549866');
\endif


-- ===== 022-amc-registry-lifecycle.sql =====
SELECT EXISTS (SELECT FROM deployment.bundle_migrations WHERE name='022-amc-registry-lifecycle.sql') AS bundle_done \gset
\if :bundle_done
DO $$ BEGIN IF NOT EXISTS (SELECT FROM deployment.bundle_migrations WHERE name='022-amc-registry-lifecycle.sql' AND sha256='7e3968f25c52c0d0505f30ed1315f39585b88f7ee911d6ca65ef27cb37792485') THEN RAISE EXCEPTION 'Empreinte différente : 022-amc-registry-lifecycle.sql'; END IF; END $$;
\else
-- Lot A — Agent Management Center : registre + lifecycle (+ crochets missions/KPI/approbations).
-- Database: prodigital (NOT prodigital_platform)
-- Run as: postgres  AFTER  021-assistants-session-access.sql
--
--   psql "$DATABASE_URL_AS_POSTGRES" -v ON_ERROR_STOP=1 -f infra/prodigital/database/022-amc-registry-lifecycle.sql
--
-- Additif, idempotent-safe, aucun DROP de table existante, aucun seed (Lot B),
-- aucun secret. Étendre iam.assistant_* — pas de schéma parallèle.
--
-- Rollback (manuel, hors prod destructive par défaut) :
--   ALTER TABLE iam.assistant_proposals DROP COLUMN IF EXISTS mission_id;
--   ALTER TABLE iam.assistant_proposals DROP COLUMN IF EXISTS autonomy_gate;
--   ALTER TABLE iam.assistant_proposals DROP COLUMN IF EXISTS source_engine;
--   DROP TABLE IF EXISTS iam.assistant_kpis;
--   DROP TABLE IF EXISTS iam.assistant_missions;
--   DROP TABLE IF EXISTS iam.assistant_lifecycle_events;
--   DROP TABLE IF EXISTS iam.assistant_agents;
--   DROP FUNCTION IF EXISTS iam.assistant_lifecycle_allowed(text, text);
--   DROP FUNCTION IF EXISTS iam.guard_assistant_lifecycle();
--   DROP FUNCTION IF EXISTS iam.journal_assistant_lifecycle();
--   DROP FUNCTION IF EXISTS iam.touch_assistant_agent();
-- Ne pas DROP iam.assistant_proposals ni iam.principals.

BEGIN;

CREATE OR REPLACE FUNCTION iam.assistant_lifecycle_allowed(from_status text, to_status text)
RETURNS boolean
LANGUAGE sql
IMMUTABLE
SET search_path = pg_catalog
AS $$
  SELECT CASE
    WHEN from_status IS NULL OR to_status IS NULL THEN false
    WHEN from_status = to_status THEN true
    WHEN from_status = 'PROPOSED'
      AND to_status IN ('ACTIVE', 'REJECTED', 'DELETION_PENDING') THEN true
    WHEN from_status = 'REJECTED'
      AND to_status IN ('PROPOSED', 'DELETION_PENDING') THEN true
    WHEN from_status = 'ACTIVE'
      AND to_status IN ('SUSPENDED', 'ARCHIVED', 'DELETION_PENDING') THEN true
    WHEN from_status = 'SUSPENDED'
      AND to_status IN ('ACTIVE', 'ARCHIVED', 'DELETION_PENDING') THEN true
    WHEN from_status = 'ARCHIVED'
      AND to_status IN ('ACTIVE', 'DELETION_PENDING') THEN true
    WHEN from_status = 'DELETION_PENDING'
      AND to_status IN ('DELETED', 'PROPOSED', 'REJECTED', 'ACTIVE', 'SUSPENDED', 'ARCHIVED') THEN true
    ELSE false
  END;
$$;

COMMENT ON FUNCTION iam.assistant_lifecycle_allowed(text, text) IS
  'Transitions AMC | DELETED terminal ; Copilot/Tech bloqués à part via protected.';

-- Fiche agent 1:1 sur iam.principals (PK = principal_id, comme local_accounts).
-- Pas de colonne id : GET /api/assistants/:id et /registry/:id partagent l’UUID principal.
CREATE TABLE IF NOT EXISTS iam.assistant_agents (
  principal_id uuid PRIMARY KEY
    REFERENCES iam.principals(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE,
  code text NOT NULL CHECK (char_length(code) BETWEEN 1 AND 80),
  display_name text NOT NULL CHECK (char_length(display_name) BETWEEN 1 AND 200),
  agent_kind text NOT NULL CHECK (agent_kind IN ('platform_copilot', 'app_copilot', 'executor', 'tech')),
  department text NOT NULL CHECK (char_length(department) BETWEEN 1 AND 80),
  manager_principal_id uuid
    REFERENCES iam.assistant_agents(principal_id) ON DELETE NO ACTION DEFERRABLE INITIALLY DEFERRED,
  supervisor_human_id uuid
    REFERENCES iam.principals(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE,
  mission_summary text CHECK (mission_summary IS NULL OR char_length(mission_summary) <= 4000),
  application_code text NOT NULL CHECK (application_code IN (
    'PLATFORM', 'CROSS', 'GENESIS', 'ORBIT', 'OPS', 'GROWTH', 'PORTAL', 'CORE'
  )),
  role_code text NOT NULL CHECK (role_code IN (
    'sales', 'technician', 'collaborator', 'business_admin', 'reader'
  )),
  autonomy_level text NOT NULL DEFAULT 'brouillon'
    CHECK (autonomy_level IN ('lecture', 'brouillon', 'publish_depense')),
  kpi_profile_code text CHECK (kpi_profile_code IS NULL OR char_length(kpi_profile_code) <= 80),
  lifecycle_status text NOT NULL DEFAULT 'PROPOSED' CHECK (lifecycle_status IN (
    'PROPOSED', 'REJECTED', 'ACTIVE', 'SUSPENDED', 'ARCHIVED', 'DELETION_PENDING', 'DELETED'
  )),
  protected boolean NOT NULL DEFAULT false,
  grok_agent_id uuid,
  email text CHECK (email IS NULL OR email ~ '^[^[:space:]@]+@[^[:space:]@]+$'),
  organization_id uuid
    REFERENCES core.organizations(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE,
  notes text CHECK (notes IS NULL OR char_length(notes) <= 4000),
  proposed_at timestamptz,
  activated_at timestamptz,
  archived_at timestamptz,
  deletion_requested_at timestamptz,
  deleted_at timestamptz,
  lifecycle_changed_by uuid
    REFERENCES iam.principals(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE,
  lifecycle_reason text CHECK (lifecycle_reason IS NULL OR char_length(lifecycle_reason) <= 2000),
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  row_version bigint NOT NULL DEFAULT 1 CHECK (row_version > 0),
  CONSTRAINT assistant_agents_protected_alive CHECK (
    NOT protected OR lifecycle_status NOT IN ('DELETION_PENDING', 'DELETED')
  ),
  CONSTRAINT assistant_agents_manager_not_self CHECK (
    manager_principal_id IS NULL OR manager_principal_id <> principal_id
  )
);

COMMENT ON TABLE iam.assistant_agents IS
  'Fiches AMC (Lot A) | Identité = iam.principals ; overlay registre+lifecycle. Seed = Lot B.';

CREATE UNIQUE INDEX IF NOT EXISTS assistant_agents_code_unique
  ON iam.assistant_agents (code);
CREATE UNIQUE INDEX IF NOT EXISTS assistant_agents_grok_id_unique
  ON iam.assistant_agents (grok_agent_id)
  WHERE grok_agent_id IS NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS assistant_agents_email_unique
  ON iam.assistant_agents (lower(email))
  WHERE email IS NOT NULL;
CREATE INDEX IF NOT EXISTS assistant_agents_lifecycle
  ON iam.assistant_agents (lifecycle_status, created_at DESC);
CREATE INDEX IF NOT EXISTS assistant_agents_manager
  ON iam.assistant_agents (manager_principal_id);
CREATE INDEX IF NOT EXISTS assistant_agents_department
  ON iam.assistant_agents (department);

CREATE TABLE IF NOT EXISTS iam.assistant_lifecycle_events (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  agent_principal_id uuid NOT NULL
    REFERENCES iam.assistant_agents(principal_id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE,
  from_status text NOT NULL,
  to_status text NOT NULL,
  reason text CHECK (reason IS NULL OR char_length(reason) <= 2000),
  actor_id uuid
    REFERENCES iam.principals(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE,
  occurred_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  row_version bigint NOT NULL DEFAULT 1 CHECK (row_version > 0)
);

COMMENT ON TABLE iam.assistant_lifecycle_events IS
  'Journal des transitions lifecycle AMC | Complète governance.audit_events, ne le remplace pas.';

CREATE INDEX IF NOT EXISTS assistant_lifecycle_events_agent
  ON iam.assistant_lifecycle_events (agent_principal_id, occurred_at DESC);

-- Stub Mission Engine (Lot C remplira l’API d’écriture).
CREATE TABLE IF NOT EXISTS iam.assistant_missions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  agent_principal_id uuid NOT NULL
    REFERENCES iam.assistant_agents(principal_id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE,
  title text NOT NULL CHECK (char_length(title) BETWEEN 1 AND 200),
  status text NOT NULL DEFAULT 'draft' CHECK (status IN (
    'draft', 'assigned', 'in_progress', 'done', 'cancelled', 'blocked'
  )),
  due_at timestamptz,
  result jsonb NOT NULL DEFAULT '{}'::jsonb,
  assigned_by uuid
    REFERENCES iam.principals(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  row_version bigint NOT NULL DEFAULT 1 CHECK (row_version > 0)
);

COMMENT ON TABLE iam.assistant_missions IS
  'Missions AMC (stub Lot A) | create/assign/status/due/result = Lot C.';

CREATE INDEX IF NOT EXISTS assistant_missions_agent
  ON iam.assistant_missions (agent_principal_id, created_at DESC);
CREATE INDEX IF NOT EXISTS assistant_missions_status
  ON iam.assistant_missions (status, due_at);

-- Stub KPI Engine (Lot E).
CREATE TABLE IF NOT EXISTS iam.assistant_kpis (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  agent_principal_id uuid NOT NULL
    REFERENCES iam.assistant_agents(principal_id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE,
  code text NOT NULL CHECK (char_length(code) BETWEEN 1 AND 80),
  period_start date,
  period_end date,
  value numeric,
  payload jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  row_version bigint NOT NULL DEFAULT 1 CHECK (row_version > 0),
  CONSTRAINT assistant_kpis_period CHECK (
    period_start IS NULL OR period_end IS NULL OR period_end >= period_start
  )
);

COMMENT ON TABLE iam.assistant_kpis IS
  'KPI AMC (stub Lot A) | moteur = Lot E. Pas de reporting générique ici.';

CREATE INDEX IF NOT EXISTS assistant_kpis_agent
  ON iam.assistant_kpis (agent_principal_id, code, period_start DESC);

-- Approval Engine : étendre Lot 9, ne pas créer iam.assistant_approvals.
ALTER TABLE iam.assistant_proposals
  ADD COLUMN IF NOT EXISTS mission_id uuid;
ALTER TABLE iam.assistant_proposals
  ADD COLUMN IF NOT EXISTS autonomy_gate text;
ALTER TABLE iam.assistant_proposals
  ADD COLUMN IF NOT EXISTS source_engine text NOT NULL DEFAULT 'lot9';

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'assistant_proposals_mission_fk'
  ) THEN
    ALTER TABLE iam.assistant_proposals
      ADD CONSTRAINT assistant_proposals_mission_fk
      FOREIGN KEY (mission_id) REFERENCES iam.assistant_missions(id)
      ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
  END IF;
END $$;

ALTER TABLE iam.assistant_proposals
  DROP CONSTRAINT IF EXISTS assistant_proposals_autonomy_gate_check;
ALTER TABLE iam.assistant_proposals
  ADD CONSTRAINT assistant_proposals_autonomy_gate_check
  CHECK (autonomy_gate IS NULL OR autonomy_gate IN ('lecture', 'brouillon', 'publish_depense'));

ALTER TABLE iam.assistant_proposals
  DROP CONSTRAINT IF EXISTS assistant_proposals_source_engine_check;
ALTER TABLE iam.assistant_proposals
  ADD CONSTRAINT assistant_proposals_source_engine_check
  CHECK (source_engine IN ('lot9', 'amc_approval', 'amc_lifecycle', 'amc_mission'));

CREATE INDEX IF NOT EXISTS assistant_proposals_mission
  ON iam.assistant_proposals (mission_id)
  WHERE mission_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS assistant_proposals_source
  ON iam.assistant_proposals (source_engine, status);

-- touch_row() historique exige NEW.id : cette table a principal_id.
CREATE OR REPLACE FUNCTION iam.touch_assistant_agent()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = pg_catalog
AS $$
BEGIN
  IF NEW.principal_id <> OLD.principal_id OR NEW.created_at <> OLD.created_at THEN
    RAISE EXCEPTION 'Identity and creation time are immutable' USING ERRCODE = '23514';
  END IF;
  NEW.updated_at := clock_timestamp();
  NEW.row_version := OLD.row_version + 1;
  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION iam.guard_assistant_lifecycle()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = pg_catalog
AS $$
BEGIN
  IF NEW.lifecycle_status IS NOT DISTINCT FROM OLD.lifecycle_status THEN
    RETURN NEW;
  END IF;
  IF OLD.lifecycle_status = 'DELETED' THEN
    RAISE EXCEPTION 'terminal_deleted' USING ERRCODE = 'P0001';
  END IF;
  IF NOT iam.assistant_lifecycle_allowed(OLD.lifecycle_status, NEW.lifecycle_status) THEN
    RAISE EXCEPTION 'invalid_transition' USING ERRCODE = 'P0001';
  END IF;
  IF NEW.protected AND NEW.lifecycle_status IN ('DELETION_PENDING', 'DELETED') THEN
    RAISE EXCEPTION 'protected_agent' USING ERRCODE = 'P0001';
  END IF;
  IF NEW.lifecycle_status = 'ACTIVE' AND NEW.activated_at IS NULL THEN
    NEW.activated_at := clock_timestamp();
  END IF;
  IF NEW.lifecycle_status = 'ARCHIVED' AND NEW.archived_at IS NULL THEN
    NEW.archived_at := clock_timestamp();
  END IF;
  IF NEW.lifecycle_status = 'DELETION_PENDING' AND NEW.deletion_requested_at IS NULL THEN
    NEW.deletion_requested_at := clock_timestamp();
  END IF;
  IF NEW.lifecycle_status = 'DELETED' AND NEW.deleted_at IS NULL THEN
    NEW.deleted_at := clock_timestamp();
  END IF;
  IF NEW.lifecycle_status = 'PROPOSED' AND NEW.proposed_at IS NULL THEN
    NEW.proposed_at := clock_timestamp();
  END IF;
  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION iam.journal_assistant_lifecycle()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = pg_catalog
AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    -- Naissance de fiche (Lot B seed en ACTIVE) : pas de faux PROPOSED→ACTIVE.
    INSERT INTO iam.assistant_lifecycle_events (
      agent_principal_id, from_status, to_status, reason, actor_id
    ) VALUES (
      NEW.principal_id, NEW.lifecycle_status, NEW.lifecycle_status,
      COALESCE(NEW.lifecycle_reason, 'insert'), NEW.lifecycle_changed_by
    );
    RETURN NEW;
  END IF;
  IF NEW.lifecycle_status IS DISTINCT FROM OLD.lifecycle_status THEN
    INSERT INTO iam.assistant_lifecycle_events (
      agent_principal_id, from_status, to_status, reason, actor_id
    ) VALUES (
      NEW.principal_id, OLD.lifecycle_status, NEW.lifecycle_status,
      NEW.lifecycle_reason, NEW.lifecycle_changed_by
    );
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS z_touch_assistant_agent ON iam.assistant_agents;
CREATE TRIGGER z_touch_assistant_agent
  BEFORE UPDATE ON iam.assistant_agents
  FOR EACH ROW EXECUTE FUNCTION iam.touch_assistant_agent();

DROP TRIGGER IF EXISTS amc_guard_lifecycle ON iam.assistant_agents;
CREATE TRIGGER amc_guard_lifecycle
  BEFORE UPDATE ON iam.assistant_agents
  FOR EACH ROW EXECUTE FUNCTION iam.guard_assistant_lifecycle();

DROP TRIGGER IF EXISTS amc_journal_lifecycle ON iam.assistant_agents;
CREATE TRIGGER amc_journal_lifecycle
  AFTER INSERT OR UPDATE ON iam.assistant_agents
  FOR EACH ROW EXECUTE FUNCTION iam.journal_assistant_lifecycle();

DROP TRIGGER IF EXISTS z_touch ON iam.assistant_lifecycle_events;
CREATE TRIGGER z_touch BEFORE UPDATE ON iam.assistant_lifecycle_events
  FOR EACH ROW EXECUTE FUNCTION infrastructure.touch_row();

DROP TRIGGER IF EXISTS z_touch ON iam.assistant_missions;
CREATE TRIGGER z_touch BEFORE UPDATE ON iam.assistant_missions
  FOR EACH ROW EXECUTE FUNCTION infrastructure.touch_row();

DROP TRIGGER IF EXISTS z_touch ON iam.assistant_kpis;
CREATE TRIGGER z_touch BEFORE UPDATE ON iam.assistant_kpis
  FOR EACH ROW EXECUTE FUNCTION infrastructure.touch_row();

ALTER TABLE iam.assistant_agents ENABLE ROW LEVEL SECURITY;
ALTER TABLE iam.assistant_agents FORCE ROW LEVEL SECURITY;
ALTER TABLE iam.assistant_lifecycle_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE iam.assistant_lifecycle_events FORCE ROW LEVEL SECURITY;
ALTER TABLE iam.assistant_missions ENABLE ROW LEVEL SECURITY;
ALTER TABLE iam.assistant_missions FORCE ROW LEVEL SECURITY;
ALTER TABLE iam.assistant_kpis ENABLE ROW LEVEL SECURITY;
ALTER TABLE iam.assistant_kpis FORCE ROW LEVEL SECURITY;

GRANT USAGE ON SCHEMA iam TO genesis;
GRANT SELECT, INSERT, UPDATE ON iam.assistant_agents TO genesis;
GRANT SELECT, INSERT ON iam.assistant_lifecycle_events TO genesis;
GRANT SELECT, INSERT, UPDATE ON iam.assistant_missions TO genesis;
GRANT SELECT, INSERT, UPDATE ON iam.assistant_kpis TO genesis;
GRANT SELECT, INSERT ON governance.audit_events TO genesis;

DROP POLICY IF EXISTS genesis_read_assistant_agents ON iam.assistant_agents;
CREATE POLICY genesis_read_assistant_agents ON iam.assistant_agents
  FOR SELECT TO genesis USING (true);
DROP POLICY IF EXISTS genesis_write_assistant_agents ON iam.assistant_agents;
CREATE POLICY genesis_write_assistant_agents ON iam.assistant_agents
  FOR INSERT TO genesis WITH CHECK (true);
DROP POLICY IF EXISTS genesis_update_assistant_agents ON iam.assistant_agents;
CREATE POLICY genesis_update_assistant_agents ON iam.assistant_agents
  FOR UPDATE TO genesis USING (true) WITH CHECK (true);

DROP POLICY IF EXISTS genesis_read_assistant_lifecycle_events ON iam.assistant_lifecycle_events;
CREATE POLICY genesis_read_assistant_lifecycle_events ON iam.assistant_lifecycle_events
  FOR SELECT TO genesis USING (true);
DROP POLICY IF EXISTS genesis_insert_assistant_lifecycle_events ON iam.assistant_lifecycle_events;
CREATE POLICY genesis_insert_assistant_lifecycle_events ON iam.assistant_lifecycle_events
  FOR INSERT TO genesis WITH CHECK (true);

DROP POLICY IF EXISTS genesis_read_assistant_missions ON iam.assistant_missions;
CREATE POLICY genesis_read_assistant_missions ON iam.assistant_missions
  FOR SELECT TO genesis USING (true);
DROP POLICY IF EXISTS genesis_write_assistant_missions ON iam.assistant_missions;
CREATE POLICY genesis_write_assistant_missions ON iam.assistant_missions
  FOR INSERT TO genesis WITH CHECK (true);
DROP POLICY IF EXISTS genesis_update_assistant_missions ON iam.assistant_missions;
CREATE POLICY genesis_update_assistant_missions ON iam.assistant_missions
  FOR UPDATE TO genesis USING (true) WITH CHECK (true);

DROP POLICY IF EXISTS genesis_read_assistant_kpis ON iam.assistant_kpis;
CREATE POLICY genesis_read_assistant_kpis ON iam.assistant_kpis
  FOR SELECT TO genesis USING (true);
DROP POLICY IF EXISTS genesis_write_assistant_kpis ON iam.assistant_kpis;
CREATE POLICY genesis_write_assistant_kpis ON iam.assistant_kpis
  FOR INSERT TO genesis WITH CHECK (true);
DROP POLICY IF EXISTS genesis_update_assistant_kpis ON iam.assistant_kpis;
CREATE POLICY genesis_update_assistant_kpis ON iam.assistant_kpis
  FOR UPDATE TO genesis USING (true) WITH CHECK (true);

COMMIT;

INSERT INTO deployment.bundle_migrations(name,sha256) VALUES ('022-amc-registry-lifecycle.sql','7e3968f25c52c0d0505f30ed1315f39585b88f7ee911d6ca65ef27cb37792485');
\endif


-- ===== 024-amc-mission-engine.sql =====
SELECT EXISTS (SELECT FROM deployment.bundle_migrations WHERE name='024-amc-mission-engine.sql') AS bundle_done \gset
\if :bundle_done
DO $$ BEGIN IF NOT EXISTS (SELECT FROM deployment.bundle_migrations WHERE name='024-amc-mission-engine.sql' AND sha256='7c73280bdcfa034ad4845b3d9b81f2831e8659c3e59a115d8bcd18d9993c25be') THEN RAISE EXCEPTION 'Empreinte différente : 024-amc-mission-engine.sql'; END IF; END $$;
\else
-- Lot C — Mission Engine MVP (create / assign / status / due / result).
-- Database: prodigital (NOT prodigital_platform)
-- Run as: postgres  AFTER  022-amc-registry-lifecycle.sql
--         (023 seed recommended so les agents du registre existent)
--
--   psql "$DATABASE_URL_AS_POSTGRES" -v ON_ERROR_STOP=1 \
--     -f infra/prodigital/database/024-amc-mission-engine.sql
--
-- Additif, idempotent-safe. Aucun DROP de table. Aucun seed.
-- Ne pas appliquer depuis Coolify / prod via cet agent.
--
-- Rollback (manuel) :
--   ALTER TABLE iam.assistant_missions DROP CONSTRAINT IF EXISTS assistant_missions_assigned_has_agent;
--   ALTER TABLE iam.assistant_missions DROP CONSTRAINT IF EXISTS assistant_missions_autonomy_gate_check;
--   ALTER TABLE iam.assistant_missions DROP COLUMN IF EXISTS description;
--   ALTER TABLE iam.assistant_missions DROP COLUMN IF EXISTS autonomy_gate;
--   ALTER TABLE iam.assistant_missions DROP COLUMN IF EXISTS created_by;
--   DROP FUNCTION IF EXISTS iam.assistant_mission_status_allowed(text, text);
--   DROP FUNCTION IF EXISTS iam.guard_assistant_mission();
--   -- agent_principal_id redevient NOT NULL seulement si aucune mission draft sans agent.
-- Ne pas DROP iam.assistant_missions (table 022).

BEGIN;

ALTER TABLE iam.assistant_missions
  ALTER COLUMN agent_principal_id DROP NOT NULL;

ALTER TABLE iam.assistant_missions
  ADD COLUMN IF NOT EXISTS description text;
ALTER TABLE iam.assistant_missions
  ADD COLUMN IF NOT EXISTS autonomy_gate text;
ALTER TABLE iam.assistant_missions
  ADD COLUMN IF NOT EXISTS created_by uuid;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'assistant_missions_created_by_fk'
  ) THEN
    ALTER TABLE iam.assistant_missions
      ADD CONSTRAINT assistant_missions_created_by_fk
      FOREIGN KEY (created_by) REFERENCES iam.principals(id)
      ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
  END IF;
END $$;

ALTER TABLE iam.assistant_missions
  DROP CONSTRAINT IF EXISTS assistant_missions_description_len;
ALTER TABLE iam.assistant_missions
  ADD CONSTRAINT assistant_missions_description_len
  CHECK (description IS NULL OR char_length(description) <= 4000);

ALTER TABLE iam.assistant_missions
  DROP CONSTRAINT IF EXISTS assistant_missions_autonomy_gate_check;
ALTER TABLE iam.assistant_missions
  ADD CONSTRAINT assistant_missions_autonomy_gate_check
  CHECK (autonomy_gate IS NULL OR autonomy_gate IN ('lecture', 'brouillon', 'publish_depense'));

ALTER TABLE iam.assistant_missions
  DROP CONSTRAINT IF EXISTS assistant_missions_assigned_has_agent;
ALTER TABLE iam.assistant_missions
  ADD CONSTRAINT assistant_missions_assigned_has_agent
  CHECK (
    status IN ('draft', 'cancelled')
    OR agent_principal_id IS NOT NULL
  );

CREATE OR REPLACE FUNCTION iam.assistant_mission_status_allowed(from_status text, to_status text)
RETURNS boolean
LANGUAGE sql
IMMUTABLE
SET search_path = pg_catalog
AS $$
  SELECT CASE
    WHEN from_status IS NULL OR to_status IS NULL THEN false
    WHEN from_status = to_status THEN true
    WHEN from_status = 'draft' AND to_status IN ('assigned', 'cancelled') THEN true
    WHEN from_status = 'assigned' AND to_status IN ('in_progress', 'cancelled', 'draft') THEN true
    WHEN from_status = 'in_progress' AND to_status IN ('done', 'blocked', 'cancelled') THEN true
    WHEN from_status = 'blocked' AND to_status IN ('in_progress', 'cancelled') THEN true
    ELSE false
  END;
$$;

COMMENT ON FUNCTION iam.assistant_mission_status_allowed(text, text) IS
  'Transitions missions AMC | done et cancelled sont terminales en MVP.';

CREATE OR REPLACE FUNCTION iam.guard_assistant_mission()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = pg_catalog
AS $$
BEGIN
  IF NEW.status IS DISTINCT FROM OLD.status THEN
    IF NOT iam.assistant_mission_status_allowed(OLD.status, NEW.status) THEN
      RAISE EXCEPTION 'invalid_transition' USING ERRCODE = 'P0001';
    END IF;
  END IF;
  IF NEW.status IN ('assigned', 'in_progress', 'done', 'blocked')
     AND NEW.agent_principal_id IS NULL THEN
    RAISE EXCEPTION 'agent_required' USING ERRCODE = 'P0001';
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS amc_guard_mission ON iam.assistant_missions;
CREATE TRIGGER amc_guard_mission
  BEFORE UPDATE ON iam.assistant_missions
  FOR EACH ROW EXECUTE FUNCTION iam.guard_assistant_mission();

COMMENT ON TABLE iam.assistant_missions IS
  'Missions AMC (Lot C) | create/assign/status/due/result. publish_depense → Approval Engine (Lot D), pas d’exécution ici.';

COMMIT;

INSERT INTO deployment.bundle_migrations(name,sha256) VALUES ('024-amc-mission-engine.sql','7c73280bdcfa034ad4845b3d9b81f2831e8659c3e59a115d8bcd18d9993c25be');
\endif


-- ===== 025-amc-approval-engine.sql =====
SELECT EXISTS (SELECT FROM deployment.bundle_migrations WHERE name='025-amc-approval-engine.sql') AS bundle_done \gset
\if :bundle_done
DO $$ BEGIN IF NOT EXISTS (SELECT FROM deployment.bundle_migrations WHERE name='025-amc-approval-engine.sql' AND sha256='59341ebf3c2fb9b9af6372df3711da355e6d0c45f71c8c17db60803c6bca00c9') THEN RAISE EXCEPTION 'Empreinte différente : 025-amc-approval-engine.sql'; END IF; END $$;
\else
-- Lot D — Approval Engine MVP (proposals for autonomy gates, esp. publish_depense).
-- Database: prodigital (NOT prodigital_platform)
-- Run as: postgres  AFTER  022-amc-registry-lifecycle.sql
--         (024 Mission Engine required so missions exist to propose against)
--
--   psql "$DATABASE_URL_AS_POSTGRES" -v ON_ERROR_STOP=1 \
--     -f infra/prodigital/database/025-amc-approval-engine.sql
--
-- Additif, idempotent-safe. Aucun DROP de table. Aucun seed.
-- Ne pas appliquer depuis Coolify / prod via cet agent.
--
-- Réutilise iam.assistant_proposals (Lot 9 + crochets 022). Pas de table parallèle.
--
-- Rollback (manuel) :
--   DROP INDEX IF EXISTS iam.assistant_proposals_one_pending_mission;
--   DROP INDEX IF EXISTS iam.assistant_proposals_mission_gate;
-- Ne pas DROP iam.assistant_proposals ni les colonnes 022.

BEGIN;

-- Une seule proposition pending par mission (file d’approbation AMC).
CREATE UNIQUE INDEX IF NOT EXISTS assistant_proposals_one_pending_mission
  ON iam.assistant_proposals (mission_id)
  WHERE status = 'pending' AND mission_id IS NOT NULL;

-- Lookup « approved + publish_depense » pour lever le 409 Lot C.
CREATE INDEX IF NOT EXISTS assistant_proposals_mission_gate
  ON iam.assistant_proposals (mission_id, status, autonomy_gate)
  WHERE mission_id IS NOT NULL;

COMMENT ON TABLE iam.assistant_proposals IS
  'Propositions d’action (Lot 9) + Approval Engine AMC (Lot D) | pending→approved|refused|expired. Pas d’exécution métier.';

COMMENT ON COLUMN iam.assistant_proposals.mission_id IS
  'Mission AMC (Lot C) liée à cette proposition. NULL = proposition Lot 9 hors mission.';

COMMENT ON COLUMN iam.assistant_proposals.autonomy_gate IS
  'Gate visée : lecture | brouillon | publish_depense. Lot D lève le 409 done si approved + publish_depense.';

COMMENT ON COLUMN iam.assistant_proposals.source_engine IS
  'lot9 (défaut) | amc_approval (Lot D) | amc_lifecycle | amc_mission.';

COMMENT ON TABLE iam.assistant_missions IS
  'Missions AMC (Lot C) | create/assign/status/due/result. publish_depense → Approval Engine (Lot D), pas d’exécution ici.';

COMMENT ON TABLE iam.assistant_kpis IS
  'KPI AMC (stub Lot A) | moteur + audit exploitable = Lot E. Pas de reporting générique ici.';

COMMIT;

INSERT INTO deployment.bundle_migrations(name,sha256) VALUES ('025-amc-approval-engine.sql','59341ebf3c2fb9b9af6372df3711da355e6d0c45f71c8c17db60803c6bca00c9');
\endif


-- ===== 026-amc-kpi-audit.sql =====
SELECT EXISTS (SELECT FROM deployment.bundle_migrations WHERE name='026-amc-kpi-audit.sql') AS bundle_done \gset
\if :bundle_done
DO $$ BEGIN IF NOT EXISTS (SELECT FROM deployment.bundle_migrations WHERE name='026-amc-kpi-audit.sql' AND sha256='b197bde723a4c05f2c4a2426242d51394a143cfff4acd1432bec787f0cebe2d6') THEN RAISE EXCEPTION 'Empreinte différente : 026-amc-kpi-audit.sql'; END IF; END $$;
\else
-- Lot E — KPI Engine + Audit Logs (points iam.assistant_kpis + lecture AMC de governance.audit_events).
-- Database: prodigital (NOT prodigital_platform)
-- Run as: postgres  AFTER  022-amc-registry-lifecycle.sql
--
--   psql "$DATABASE_URL_AS_POSTGRES" -v ON_ERROR_STOP=1 \
--     -f infra/prodigital/database/026-amc-kpi-audit.sql
--
-- Additif, idempotent-safe. Aucun DROP de table. Aucun seed.
-- Ne pas appliquer depuis Coolify / prod via cet agent.
--
-- Rollback (manuel) :
--   ALTER TABLE iam.assistant_kpis DROP CONSTRAINT IF EXISTS assistant_kpis_recorded_by_fk;
--   ALTER TABLE iam.assistant_kpis DROP COLUMN IF EXISTS recorded_by;
--   DROP INDEX IF EXISTS iam.assistant_kpis_agent_code_period;
--   DROP INDEX IF EXISTS iam.assistant_kpis_agent_code_open;
--   DROP INDEX IF EXISTS iam.assistant_kpis_code;
--   DROP INDEX IF EXISTS governance.audit_events_resource_occurred;
--   DROP INDEX IF EXISTS governance.audit_events_action_occurred;
-- Ne pas DROP iam.assistant_kpis ni governance.audit_events.

BEGIN;

ALTER TABLE iam.assistant_kpis
  ADD COLUMN IF NOT EXISTS recorded_by uuid;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'assistant_kpis_recorded_by_fk'
  ) THEN
    ALTER TABLE iam.assistant_kpis
      ADD CONSTRAINT assistant_kpis_recorded_by_fk
      FOREIGN KEY (recorded_by) REFERENCES iam.principals(id)
      ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
  END IF;
END $$;

CREATE UNIQUE INDEX IF NOT EXISTS assistant_kpis_agent_code_period
  ON iam.assistant_kpis (agent_principal_id, lower(code), period_start)
  WHERE period_start IS NOT NULL;

CREATE UNIQUE INDEX IF NOT EXISTS assistant_kpis_agent_code_open
  ON iam.assistant_kpis (agent_principal_id, lower(code))
  WHERE period_start IS NULL;

CREATE INDEX IF NOT EXISTS assistant_kpis_code
  ON iam.assistant_kpis (lower(code), period_start DESC);

CREATE INDEX IF NOT EXISTS audit_events_resource_occurred
  ON governance.audit_events (resource_type, occurred_at DESC);

CREATE INDEX IF NOT EXISTS audit_events_action_occurred
  ON governance.audit_events (action, occurred_at DESC);

COMMENT ON TABLE iam.assistant_kpis IS
  'KPI AMC (Lot E) | Points par agent/code/période. Pas de reporting générique ni Cost Control.';

COMMENT ON COLUMN iam.assistant_kpis.recorded_by IS
  'Principal humain qui a posé le point (session). NULL = insert technique.';

COMMIT;

INSERT INTO deployment.bundle_migrations(name,sha256) VALUES ('026-amc-kpi-audit.sql','b197bde723a4c05f2c4a2426242d51394a143cfff4acd1432bec787f0cebe2d6');
\endif


-- ===== 035-crm-agents-tenant.sql =====
SELECT EXISTS (SELECT FROM deployment.bundle_migrations WHERE name='035-crm-agents-tenant.sql') AS bundle_done \gset
\if :bundle_done
DO $$ BEGIN IF NOT EXISTS (SELECT FROM deployment.bundle_migrations WHERE name='035-crm-agents-tenant.sql' AND sha256='ebdde561bbc481a8e4d448e3152e8f529720c88eb3b3e1a75493d9cd38eb0d2d') THEN RAISE EXCEPTION 'Empreinte différente : 035-crm-agents-tenant.sql'; END IF; END $$;
\else
-- Lot 1C. Explicit operator migration; never run automatically by the application.
-- Preserve the existing function's owner/ACL; remove its unscoped data surface.
BEGIN;
CREATE OR REPLACE FUNCTION genesis.crm_agents()
RETURNS TABLE (id uuid, name text)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = pg_catalog
AS $$ SELECT NULL::uuid, NULL::text WHERE false; $$;

-- UUID organizations require an explicit CRM organization-scoped grant.
-- Installation grants alone do not establish tenant membership.
CREATE OR REPLACE FUNCTION genesis.crm_agents(requested_organization text)
RETURNS TABLE (id uuid, name text)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = pg_catalog
AS $$
  SELECT principal.id,
    COALESCE(NULLIF(btrim(concat_ws(' ', person.given_name, person.family_name)), ''), btrim(principal.display_name))
  FROM iam.principals principal
  LEFT JOIN core.persons person ON person.id = principal.person_id AND person.status = 'active'
  WHERE principal.kind = 'human' AND principal.status = 'active'
    AND EXISTS (
      SELECT 1 FROM iam.role_bindings binding
      JOIN iam.access_scopes scope ON scope.id = binding.scope_id
        AND scope.kind = 'organization' AND scope.organization_id::text = requested_organization
      JOIN iam.role_permissions grant_row ON grant_row.role_id = binding.role_id AND grant_row.effect = 'allow'
      JOIN iam.permissions permission ON permission.id = grant_row.permission_id
      JOIN iam.applications application ON application.id = permission.application_id
        AND application.code = 'CRM' AND application.enabled
      WHERE binding.principal_id = principal.id
        AND binding.valid_from <= now() AND (binding.valid_to IS NULL OR binding.valid_to > now())
        AND NOT EXISTS (
          SELECT 1 FROM iam.role_bindings denial_binding
          JOIN iam.access_scopes denial_scope ON denial_scope.id = denial_binding.scope_id
            AND (denial_scope.kind = 'installation' OR
              (denial_scope.kind = 'organization' AND denial_scope.organization_id::text = requested_organization))
          JOIN iam.role_permissions denial ON denial.role_id = denial_binding.role_id
            AND denial.effect = 'deny' AND denial.permission_id = permission.id
          WHERE denial_binding.principal_id = principal.id
            AND denial_binding.valid_from <= now()
            AND (denial_binding.valid_to IS NULL OR denial_binding.valid_to > now())
        )
    )
  ORDER BY 2;
$$;
ALTER FUNCTION genesis.crm_agents(text) OWNER TO postgres;
REVOKE ALL ON FUNCTION genesis.crm_agents(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION genesis.crm_agents(text) TO genesis;
COMMIT;

INSERT INTO deployment.bundle_migrations(name,sha256) VALUES ('035-crm-agents-tenant.sql','ebdde561bbc481a8e4d448e3152e8f529720c88eb3b3e1a75493d9cd38eb0d2d');
\endif

-- ===== site-001.sql =====
SELECT EXISTS (SELECT FROM deployment.bundle_migrations WHERE name='site-001.sql') AS bundle_done \gset
\if :bundle_done
DO $$ BEGIN IF NOT EXISTS (SELECT FROM deployment.bundle_migrations WHERE name='site-001.sql' AND sha256='669f139ee7ace7864b46f2a4e27b917ae9c37685494d15ed9c0c3e94ac1d89ad') THEN RAISE EXCEPTION 'Empreinte différente : site-001.sql'; END IF; END $$;
\else
BEGIN;
SELECT pg_advisory_xact_lock(hashtext('site.migrations'));
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

CREATE TABLE IF NOT EXISTS site.schema_migrations (name text PRIMARY KEY, applied_at timestamptz NOT NULL DEFAULT clock_timestamp());
INSERT INTO site.schema_migrations(name) VALUES ('001-site-contact.sql') ON CONFLICT DO NOTHING;
-- Droits minimaux du rôle applicatif de l'API du site (`site_vitrine`).
-- À exécuter par le propriétaire, après `npm run migrate` et après avoir créé le rôle :
--   CREATE ROLE site_vitrine LOGIN PASSWORD '<mot de passe fort>';
--
-- L'API peut enregistrer une demande et suivre ses opérations ; elle ne peut ni
-- modifier ni supprimer une demande, et n'a aucun accès aux autres schémas.

GRANT USAGE ON SCHEMA site TO site_vitrine;
GRANT SELECT, INSERT ON site.contact_submissions TO site_vitrine;
GRANT SELECT, INSERT, UPDATE ON site.contact_operations TO site_vitrine;
GRANT SELECT, INSERT ON site.contact_events TO site_vitrine;

GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA site TO site_vitrine;
GRANT CONNECT ON DATABASE prodigital TO site_vitrine;
COMMIT;

INSERT INTO deployment.bundle_migrations(name,sha256) VALUES ('site-001.sql','669f139ee7ace7864b46f2a4e27b917ae9c37685494d15ed9c0c3e94ac1d89ad');
\endif

-- ===== site-core-readonly.sql =====
SELECT EXISTS (SELECT FROM deployment.bundle_migrations WHERE name='site-core-readonly.sql') AS bundle_done \gset
\if :bundle_done
DO $$ BEGIN IF NOT EXISTS (SELECT FROM deployment.bundle_migrations WHERE name='site-core-readonly.sql' AND sha256='1b3c06c46b985bc46b07c702fc7da6bbd2ada851968322a25eb2dde45832f5e9') THEN RAISE EXCEPTION 'Empreinte différente : site-core-readonly.sql'; END IF; END $$;
\else
-- Genesis CRM : récapitulatif des demandes du site en lecture seule.
--
-- À appliquer sur la base Core `prodigital` (propriétaire du schéma `web`),
-- là où vivent les migrations Genesis (infra/prodigital/database/).
--
-- Contexte : POST /api/sales/public/leads (Genesis) crée la demande dans
-- web.contact_requests. Le rôle `genesis` n'y a déjà que SELECT/INSERT
-- (migration 015) ; ce trigger étend la garantie à tous les rôles : pour une
-- demande venue du site (source = 'site_web'), le contenu d'origine —
-- identité, sujet et récapitulatif (`message`) — ne peut plus être modifié.
-- Le statut et les champs de suivi restent modifiables (traitement, promotion).
--
--   psql "$DATABASE_URL_AS_OWNER" -v ON_ERROR_STOP=1 -f core-contact-requests-readonly.sql

CREATE OR REPLACE FUNCTION web.contact_requests_site_original_readonly() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
  IF OLD.source = 'site_web' AND (
       NEW.given_name   IS DISTINCT FROM OLD.given_name
    OR NEW.family_name  IS DISTINCT FROM OLD.family_name
    OR NEW.email        IS DISTINCT FROM OLD.email
    OR NEW.subject      IS DISTINCT FROM OLD.subject
    OR NEW.message      IS DISTINCT FROM OLD.message
    OR NEW.budget_band  IS DISTINCT FROM OLD.budget_band
    OR NEW.source       IS DISTINCT FROM OLD.source
    OR NEW.received_at  IS DISTINCT FROM OLD.received_at
  ) THEN
    RAISE EXCEPTION 'Le récapitulatif d''une demande du site est en lecture seule (id %).', OLD.id
      USING ERRCODE = 'insufficient_privilege';
  END IF;
  RETURN NEW;
END;
$$;

-- Nommé pour s'exécuter avant `z_touch` (ordre alphabétique des triggers BEFORE).
DROP TRIGGER IF EXISTS a_site_original_readonly ON web.contact_requests;
CREATE TRIGGER a_site_original_readonly
  BEFORE UPDATE ON web.contact_requests
  FOR EACH ROW EXECUTE FUNCTION web.contact_requests_site_original_readonly();

-- Pas de suppression silencieuse d'une demande du site.
CREATE OR REPLACE FUNCTION web.contact_requests_site_no_delete() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
  IF OLD.source = 'site_web' THEN
    RAISE EXCEPTION 'Une demande du site ne peut pas être supprimée (id %).', OLD.id
      USING ERRCODE = 'insufficient_privilege';
  END IF;
  RETURN OLD;
END;
$$;

DROP TRIGGER IF EXISTS a_site_no_delete ON web.contact_requests;
CREATE TRIGGER a_site_no_delete
  BEFORE DELETE ON web.contact_requests
  FOR EACH ROW EXECUTE FUNCTION web.contact_requests_site_no_delete();

INSERT INTO deployment.bundle_migrations(name,sha256) VALUES ('site-core-readonly.sql','1b3c06c46b985bc46b07c702fc7da6bbd2ada851968322a25eb2dde45832f5e9');
\endif
