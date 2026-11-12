-- ProDigital : export des migrations existantes, 2026-11-12.
-- Exécuter avec psql, comme administrateur PostgreSQL 15+, dans prodigital_platform.
-- Sauvegarder la base avant import. Ne pas lancer deux imports simultanés.
-- Ce fichier contient des commandes psql (\if, \gset) : pas un éditeur SQL générique.
-- Les nouveaux rôles sont NOLOGIN, sans mot de passe. Activer ensuite par \password.
\set ON_ERROR_STOP on
DO $$ BEGIN
 IF current_database() <> 'prodigital_platform' THEN RAISE EXCEPTION 'Connectez-vous à la base prodigital_platform'; END IF;
 IF current_setting('server_version_num')::int < 150000 THEN RAISE EXCEPTION 'PostgreSQL 15 minimum'; END IF;
END $$;
DO $$ BEGIN IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname='genesis') THEN CREATE ROLE genesis NOLOGIN; END IF; END $$;
CREATE SCHEMA IF NOT EXISTS deployment;
REVOKE ALL ON SCHEMA deployment FROM PUBLIC;
CREATE TABLE IF NOT EXISTS deployment.bundle_migrations (name text PRIMARY KEY, sha256 text NOT NULL, applied_at timestamptz NOT NULL DEFAULT now());
GRANT CONNECT ON DATABASE prodigital_platform TO genesis;

-- ===== 001-platform.sql =====
SELECT EXISTS (SELECT FROM deployment.bundle_migrations WHERE name='001-platform.sql') AS bundle_done \gset
\if :bundle_done
DO $$ BEGIN IF NOT EXISTS (SELECT FROM deployment.bundle_migrations WHERE name='001-platform.sql' AND sha256='e0b0d930c9ebb1e49d3af072bac05171f7e693895bf4afeb325828aaec5205f8') THEN RAISE EXCEPTION 'Empreinte différente : 001-platform.sql'; END IF; END $$;
\else
\set ON_ERROR_STOP on
BEGIN;
SET LOCAL lock_timeout='15s';
SET LOCAL statement_timeout='180s';
SELECT pg_advisory_xact_lock(hashtextextended('prodigital-schema',0));
CREATE SCHEMA IF NOT EXISTS infrastructure;
REVOKE ALL ON SCHEMA infrastructure FROM PUBLIC;
CREATE TABLE IF NOT EXISTS infrastructure.migrations (version text PRIMARY KEY,checksum text NOT NULL,applied_at timestamptz NOT NULL DEFAULT clock_timestamp());
SELECT EXISTS(SELECT 1 FROM infrastructure.migrations WHERE version='20261010_001_platform') AS already_applied \gset
\if :already_applied
SELECT checksum='b101f85942f2758dae98111d3844acdf52676352f127647776067611bf1c59d3' AS checksum_matches FROM infrastructure.migrations WHERE version='20261010_001_platform' \gset
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


CREATE SCHEMA "platform";
REVOKE ALL ON SCHEMA "platform" FROM PUBLIC;

CREATE TABLE "platform"."operators" (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "issuer" text NOT NULL,
  "subject" text NOT NULL,
  "display_name" text NOT NULL,
  "status" text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  row_version bigint NOT NULL DEFAULT 1 CHECK(row_version>0)
);

COMMENT ON TABLE "platform"."operators" IS 'Administrateurs de la plateforme | Catalogue: Identités éditeur distinctes des administrateurs métier ; authentification renforcée.';

ALTER TABLE "platform"."operators" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "platform"."operators" FORCE ROW LEVEL SECURITY;

CREATE TRIGGER z_touch BEFORE UPDATE ON "platform"."operators" FOR EACH ROW EXECUTE FUNCTION infrastructure.touch_row();

ALTER TABLE "platform"."operators" ADD CONSTRAINT "c_d56b44e81482e054489b" UNIQUE NULLS NOT DISTINCT ("issuer", "subject");

CREATE TABLE "platform"."subscribers" (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "legal_name" text NOT NULL,
  "billing_reference" text NOT NULL,
  "commercial_account_external_id" text,
  "status" text NOT NULL,
  "primary_contact" text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  row_version bigint NOT NULL DEFAULT 1 CHECK(row_version>0)
);

COMMENT ON TABLE "platform"."subscribers" IS 'Entreprises qui louent l’outil | Catalogue: Ce sont les abonnés, pas les clients dépannés par les abonnés.';

ALTER TABLE "platform"."subscribers" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "platform"."subscribers" FORCE ROW LEVEL SECURITY;

CREATE TRIGGER z_touch BEFORE UPDATE ON "platform"."subscribers" FOR EACH ROW EXECUTE FUNCTION infrastructure.touch_row();

CREATE TABLE "platform"."installations" (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "subscriber_id" uuid NOT NULL,
  "instance_key" text NOT NULL,
  "environment" text NOT NULL,
  "domain_name" text NOT NULL,
  "status" text NOT NULL,
  "release_id" uuid,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  row_version bigint NOT NULL DEFAULT 1 CHECK(row_version>0)
);

COMMENT ON TABLE "platform"."installations" IS 'Instances indépendantes | Catalogue: Un abonné peut avoir production et test ; chaque base ne contient qu’une installation métier.';

ALTER TABLE "platform"."installations" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "platform"."installations" FORCE ROW LEVEL SECURITY;

CREATE TRIGGER z_touch BEFORE UPDATE ON "platform"."installations" FOR EACH ROW EXECUTE FUNCTION infrastructure.touch_row();

ALTER TABLE "platform"."installations" ADD CONSTRAINT "c_ff2659c077f3bf6a284c" UNIQUE NULLS NOT DISTINCT ("instance_key");

ALTER TABLE "platform"."installations" ADD CONSTRAINT "c_3dd0e40222dcc0357bc0" UNIQUE NULLS NOT DISTINCT ("domain_name");

CREATE TABLE "platform"."database_resources" (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "installation_id" uuid NOT NULL,
  "cluster_ref" text NOT NULL,
  "database_name" text NOT NULL,
  "application_role_ref" text NOT NULL,
  "credential_secret_ref" text NOT NULL,
  "schema_version" text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  row_version bigint NOT NULL DEFAULT 1 CHECK(row_version>0)
);

COMMENT ON TABLE "platform"."database_resources" IS 'Bases dédiées et accès privés | Catalogue: UNIQUE installation ; secrets hors base ; rôle applicatif dédié limité à sa base.';

ALTER TABLE "platform"."database_resources" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "platform"."database_resources" FORCE ROW LEVEL SECURITY;

CREATE TRIGGER z_touch BEFORE UPDATE ON "platform"."database_resources" FOR EACH ROW EXECUTE FUNCTION infrastructure.touch_row();

ALTER TABLE "platform"."database_resources" ADD CONSTRAINT "c_39b77f4836f3f6cb6168" UNIQUE NULLS NOT DISTINCT ("installation_id");

ALTER TABLE "platform"."database_resources" ADD CONSTRAINT "c_d398d22d637cec0439f4" UNIQUE NULLS NOT DISTINCT ("cluster_ref", "database_name");

CREATE TABLE "platform"."storage_resources" (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "installation_id" uuid NOT NULL,
  "storage_namespace" text NOT NULL,
  "access_policy_ref" text NOT NULL,
  "encryption_key_ref" text,
  "region" text,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  row_version bigint NOT NULL DEFAULT 1 CHECK(row_version>0)
);

COMMENT ON TABLE "platform"."storage_resources" IS 'Stockage des fichiers par installation | Catalogue: Isolation également des pièces, exports et sauvegardes ; pas seulement des tables.';

ALTER TABLE "platform"."storage_resources" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "platform"."storage_resources" FORCE ROW LEVEL SECURITY;

CREATE TRIGGER z_touch BEFORE UPDATE ON "platform"."storage_resources" FOR EACH ROW EXECUTE FUNCTION infrastructure.touch_row();

ALTER TABLE "platform"."storage_resources" ADD CONSTRAINT "c_5dc460ff8c4cbbe6ce20" UNIQUE NULLS NOT DISTINCT ("storage_namespace");

CREATE TABLE "platform"."plans" (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "code" text NOT NULL,
  "name" text NOT NULL,
  "active" boolean NOT NULL,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  row_version bigint NOT NULL DEFAULT 1 CHECK(row_version>0)
);

COMMENT ON TABLE "platform"."plans" IS 'Offres commercialisées | Catalogue: Aucun prix ni limite inventé ; offres à définir commercialement.';

ALTER TABLE "platform"."plans" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "platform"."plans" FORCE ROW LEVEL SECURITY;

CREATE TRIGGER z_touch BEFORE UPDATE ON "platform"."plans" FOR EACH ROW EXECUTE FUNCTION infrastructure.touch_row();

ALTER TABLE "platform"."plans" ADD CONSTRAINT "c_42f250fb01b2eb3eae42" UNIQUE NULLS NOT DISTINCT ("code");

CREATE TABLE "platform"."plan_versions" (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "plan_id" uuid NOT NULL,
  "version_no" integer NOT NULL,
  "effective_from" date NOT NULL,
  "currency" text NOT NULL,
  "price" numeric(20,6),
  "billing_period" text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  row_version bigint NOT NULL DEFAULT 1 CHECK(row_version>0)
);

COMMENT ON TABLE "platform"."plan_versions" IS 'Versions des offres | Catalogue: Un contrat conserve sa version d’offre ; pas de changement rétroactif implicite.';

ALTER TABLE "platform"."plan_versions" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "platform"."plan_versions" FORCE ROW LEVEL SECURITY;

CREATE TRIGGER z_touch BEFORE UPDATE ON "platform"."plan_versions" FOR EACH ROW EXECUTE FUNCTION infrastructure.touch_row();

ALTER TABLE "platform"."plan_versions" ADD CONSTRAINT "c_2b80bed1a79fa8c643e9" CHECK ("version_no" > 0);

ALTER TABLE "platform"."plan_versions" ADD CONSTRAINT "c_b88eca56957c888f0a15" CHECK ("currency" ~ '^[A-Z]{3}$');

ALTER TABLE "platform"."plan_versions" ADD CONSTRAINT "c_db9a149329fe263377cc" CHECK ("price" <> 'NaN'::numeric);

ALTER TABLE "platform"."plan_versions" ADD CONSTRAINT "c_52007898fd7b1f889dd2" UNIQUE NULLS NOT DISTINCT ("plan_id", "version_no");

CREATE TABLE "platform"."features" (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "code" text NOT NULL,
  "label" text NOT NULL,
  "minimum_release" text,
  "unit" text,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  row_version bigint NOT NULL DEFAULT 1 CHECK(row_version>0)
);

COMMENT ON TABLE "platform"."features" IS 'Fonctionnalités activables | Catalogue: Modules, rapports, connecteurs, stockage ; distinction activation/droit utilisateur.';

ALTER TABLE "platform"."features" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "platform"."features" FORCE ROW LEVEL SECURITY;

CREATE TRIGGER z_touch BEFORE UPDATE ON "platform"."features" FOR EACH ROW EXECUTE FUNCTION infrastructure.touch_row();

ALTER TABLE "platform"."features" ADD CONSTRAINT "c_f8a0b7d2c201e4ef637b" UNIQUE NULLS NOT DISTINCT ("code");

CREATE TABLE "platform"."plan_entitlements" (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "plan_version_id" uuid NOT NULL,
  "feature_id" uuid NOT NULL,
  "enabled" boolean NOT NULL,
  "quota_value" bigint,
  "quota_period" text,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  row_version bigint NOT NULL DEFAULT 1 CHECK(row_version>0)
);

COMMENT ON TABLE "platform"."plan_entitlements" IS 'Droits et limites d’une offre | Catalogue: UNIQUE offre + fonctionnalité ; unité explicite ; null signifie limite non définie, pas illimité implicite.';

ALTER TABLE "platform"."plan_entitlements" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "platform"."plan_entitlements" FORCE ROW LEVEL SECURITY;

CREATE TRIGGER z_touch BEFORE UPDATE ON "platform"."plan_entitlements" FOR EACH ROW EXECUTE FUNCTION infrastructure.touch_row();

ALTER TABLE "platform"."plan_entitlements" ADD CONSTRAINT "c_d5446431ab371f61c450" CHECK ("quota_value" >= 0);

ALTER TABLE "platform"."plan_entitlements" ADD CONSTRAINT "c_f25ca9933664adfd1de3" UNIQUE NULLS NOT DISTINCT ("plan_version_id", "feature_id");

CREATE TABLE "platform"."subscriptions" (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "subscriber_id" uuid NOT NULL,
  "plan_version_id" uuid NOT NULL,
  "starts_on" date NOT NULL,
  "ends_on" date,
  "status" text NOT NULL,
  "commercial_contract_external_id" text,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  row_version bigint NOT NULL DEFAULT 1 CHECK(row_version>0)
);

COMMENT ON TABLE "platform"."subscriptions" IS 'Abonnements souscrits | Catalogue: Contrat commercial éditeur via référence externe, sans FK interbase.';

ALTER TABLE "platform"."subscriptions" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "platform"."subscriptions" FORCE ROW LEVEL SECURITY;

CREATE TRIGGER z_touch BEFORE UPDATE ON "platform"."subscriptions" FOR EACH ROW EXECUTE FUNCTION infrastructure.touch_row();

ALTER TABLE "platform"."subscriptions" ADD CONSTRAINT "c_9affe2a620c75b615665" CHECK ("ends_on" >= "starts_on");

CREATE TABLE "platform"."subscription_installations" (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "subscription_id" uuid NOT NULL,
  "installation_id" uuid NOT NULL,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  row_version bigint NOT NULL DEFAULT 1 CHECK(row_version>0)
);

COMMENT ON TABLE "platform"."subscription_installations" IS 'Installations couvertes par un abonnement | Catalogue: Cohérence même abonné ; droits effectifs déterministes.';

ALTER TABLE "platform"."subscription_installations" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "platform"."subscription_installations" FORCE ROW LEVEL SECURITY;

CREATE TRIGGER z_touch BEFORE UPDATE ON "platform"."subscription_installations" FOR EACH ROW EXECUTE FUNCTION infrastructure.touch_row();

ALTER TABLE "platform"."subscription_installations" ADD CONSTRAINT "c_ecb1d42232c71a63cce2" UNIQUE NULLS NOT DISTINCT ("subscription_id", "installation_id");

CREATE TABLE "platform"."entitlement_overrides" (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "subscription_id" uuid NOT NULL,
  "feature_id" uuid NOT NULL,
  "enabled" boolean NOT NULL,
  "quota_value" bigint,
  "starts_at" timestamptz NOT NULL,
  "ends_at" timestamptz,
  "reason" text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  row_version bigint NOT NULL DEFAULT 1 CHECK(row_version>0)
);

COMMENT ON TABLE "platform"."entitlement_overrides" IS 'Options et dérogations datées | Catalogue: Priorité des options définie ; historique de changement conservé.';

ALTER TABLE "platform"."entitlement_overrides" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "platform"."entitlement_overrides" FORCE ROW LEVEL SECURITY;

CREATE TRIGGER z_touch BEFORE UPDATE ON "platform"."entitlement_overrides" FOR EACH ROW EXECUTE FUNCTION infrastructure.touch_row();

ALTER TABLE "platform"."entitlement_overrides" ADD CONSTRAINT "c_a8367f8b8ad1c72a1069" CHECK ("quota_value" >= 0);

ALTER TABLE "platform"."entitlement_overrides" ADD CONSTRAINT "c_53db3c8271fe05c17d65" CHECK ("ends_at" > "starts_at");

CREATE TABLE "platform"."usage_counters" (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "installation_id" uuid NOT NULL,
  "metric" text NOT NULL,
  "period_start" timestamptz NOT NULL,
  "period_end" timestamptz NOT NULL,
  "value" bigint NOT NULL,
  "measured_at" timestamptz NOT NULL,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  row_version bigint NOT NULL DEFAULT 1 CHECK(row_version>0)
);

COMMENT ON TABLE "platform"."usage_counters" IS 'Consommation de ressources | Catalogue: Mesures techniques seulement : octets, comptes, appels ; pas de contenu métier.';

ALTER TABLE "platform"."usage_counters" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "platform"."usage_counters" FORCE ROW LEVEL SECURITY;

CREATE TRIGGER z_touch BEFORE UPDATE ON "platform"."usage_counters" FOR EACH ROW EXECUTE FUNCTION infrastructure.touch_row();

ALTER TABLE "platform"."usage_counters" ADD CONSTRAINT "c_e3dbc725a1a9613d9c47" CHECK ("period_end" > "period_start");

ALTER TABLE "platform"."usage_counters" ADD CONSTRAINT "c_ffc7218b83655682d911" UNIQUE NULLS NOT DISTINCT ("installation_id", "metric", "period_start", "period_end");

CREATE TABLE "platform"."releases" (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "version" text NOT NULL,
  "released_at" timestamptz,
  "minimum_schema_version" text NOT NULL,
  "status" text NOT NULL,
  "release_notes" text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  row_version bigint NOT NULL DEFAULT 1 CHECK(row_version>0)
);

COMMENT ON TABLE "platform"."releases" IS 'Versions du produit | Catalogue: Même code maintenu et migrations versionnées ; éviter forks client non maîtrisés.';

ALTER TABLE "platform"."releases" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "platform"."releases" FORCE ROW LEVEL SECURITY;

CREATE TRIGGER z_touch BEFORE UPDATE ON "platform"."releases" FOR EACH ROW EXECUTE FUNCTION infrastructure.touch_row();

ALTER TABLE "platform"."releases" ADD CONSTRAINT "c_cb588e3b9cf69107d29c" UNIQUE NULLS NOT DISTINCT ("version");

CREATE TABLE "platform"."deployments" (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "installation_id" uuid NOT NULL,
  "release_id" uuid NOT NULL,
  "started_at" timestamptz NOT NULL,
  "finished_at" timestamptz,
  "status" text NOT NULL,
  "backup_ref" text,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  row_version bigint NOT NULL DEFAULT 1 CHECK(row_version>0)
);

COMMENT ON TABLE "platform"."deployments" IS 'Déploiements par installation | Catalogue: Déploiement progressif ; compatibilité vérifiée, retour applicatif distinct d’un retour de données.';

ALTER TABLE "platform"."deployments" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "platform"."deployments" FORCE ROW LEVEL SECURITY;

CREATE TRIGGER z_touch BEFORE UPDATE ON "platform"."deployments" FOR EACH ROW EXECUTE FUNCTION infrastructure.touch_row();

ALTER TABLE "platform"."deployments" ADD CONSTRAINT "c_a3676e0e3d895bbadeb8" CHECK ("finished_at" >= "started_at");

CREATE TABLE "platform"."backup_runs" (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "installation_id" uuid NOT NULL,
  "kind" text NOT NULL,
  "started_at" timestamptz NOT NULL,
  "finished_at" timestamptz,
  "status" text NOT NULL,
  "storage_ref" text NOT NULL,
  "retained_until" timestamptz NOT NULL,
  "encryption_key_ref" text,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  row_version bigint NOT NULL DEFAULT 1 CHECK(row_version>0)
);

COMMENT ON TABLE "platform"."backup_runs" IS 'Sauvegardes par installation | Catalogue: Métadonnées seulement ; base et fichiers restaurables au même point cohérent.';

ALTER TABLE "platform"."backup_runs" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "platform"."backup_runs" FORCE ROW LEVEL SECURITY;

CREATE TRIGGER z_touch BEFORE UPDATE ON "platform"."backup_runs" FOR EACH ROW EXECUTE FUNCTION infrastructure.touch_row();

ALTER TABLE "platform"."backup_runs" ADD CONSTRAINT "c_86aea9e963816399f093" CHECK ("finished_at" >= "started_at");

CREATE TABLE "platform"."restore_tests" (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "backup_run_id" uuid NOT NULL,
  "tested_at" timestamptz NOT NULL,
  "target_environment" text NOT NULL,
  "result" text NOT NULL,
  "duration_seconds" integer NOT NULL,
  "verified_by" uuid NOT NULL,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  row_version bigint NOT NULL DEFAULT 1 CHECK(row_version>0)
);

COMMENT ON TABLE "platform"."restore_tests" IS 'Preuves de restauration | Catalogue: Restaurer en environnement isolé ; ne pas écraser la production pour tester.';

ALTER TABLE "platform"."restore_tests" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "platform"."restore_tests" FORCE ROW LEVEL SECURITY;

CREATE TRIGGER z_touch BEFORE UPDATE ON "platform"."restore_tests" FOR EACH ROW EXECUTE FUNCTION infrastructure.touch_row();

ALTER TABLE "platform"."restore_tests" ADD CONSTRAINT "c_1d308a4e3cb1e4b3c2d6" CHECK ("duration_seconds" >= 0);

CREATE TABLE "platform"."support_access_grants" (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "installation_id" uuid NOT NULL,
  "operator_id" uuid NOT NULL,
  "approved_by_external_subject" text NOT NULL,
  "scope" jsonb NOT NULL,
  "reason" text NOT NULL,
  "starts_at" timestamptz NOT NULL,
  "ends_at" timestamptz NOT NULL,
  "revoked_at" timestamptz,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  row_version bigint NOT NULL DEFAULT 1 CHECK(row_version>0)
);

COMMENT ON TABLE "platform"."support_access_grants" IS 'Accès exceptionnel de l’éditeur | Catalogue: Accès temporaire justifié et audité ; aucun accès permanent au contenu par le seul rôle commercial.';

ALTER TABLE "platform"."support_access_grants" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "platform"."support_access_grants" FORCE ROW LEVEL SECURITY;

CREATE TRIGGER z_touch BEFORE UPDATE ON "platform"."support_access_grants" FOR EACH ROW EXECUTE FUNCTION infrastructure.touch_row();

ALTER TABLE "platform"."support_access_grants" ADD CONSTRAINT "c_2bf2bb954185803ae8d5" CHECK ("ends_at" > "starts_at");

CREATE TABLE "platform"."platform_audit_events" (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "operator_id" uuid,
  "installation_id" uuid,
  "action" text NOT NULL,
  "occurred_at" timestamptz NOT NULL,
  "request_id" text NOT NULL,
  "details" jsonb NOT NULL,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  row_version bigint NOT NULL DEFAULT 1 CHECK(row_version>0)
);

COMMENT ON TABLE "platform"."platform_audit_events" IS 'Journal de l’administration éditeur | Catalogue: Ne pas y recopier les tickets ni secrets clients.';

ALTER TABLE "platform"."platform_audit_events" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "platform"."platform_audit_events" FORCE ROW LEVEL SECURITY;

CREATE TRIGGER z_touch BEFORE UPDATE ON "platform"."platform_audit_events" FOR EACH ROW EXECUTE FUNCTION infrastructure.touch_row();

CREATE TRIGGER a_immutable BEFORE UPDATE OR DELETE ON "platform"."platform_audit_events" FOR EACH ROW EXECUTE FUNCTION infrastructure.reject_mutation();
CREATE TRIGGER a_no_truncate BEFORE TRUNCATE ON "platform"."platform_audit_events" FOR EACH STATEMENT EXECUTE FUNCTION infrastructure.reject_mutation();

CREATE TABLE "platform"."offboarding_jobs" (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "installation_id" uuid NOT NULL,
  "requested_at" timestamptz NOT NULL,
  "export_ref" text,
  "access_cutoff_at" timestamptz,
  "delete_after" timestamptz,
  "status" text NOT NULL,
  "completed_at" timestamptz,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  row_version bigint NOT NULL DEFAULT 1 CHECK(row_version>0)
);

COMMENT ON TABLE "platform"."offboarding_jobs" IS 'Export et fermeture d’un abonnement | Catalogue: Export contrôlé avant fin d’accès selon procédure ; traitement des fichiers, sauvegardes et clés.';

ALTER TABLE "platform"."offboarding_jobs" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "platform"."offboarding_jobs" FORCE ROW LEVEL SECURITY;

CREATE TRIGGER z_touch BEFORE UPDATE ON "platform"."offboarding_jobs" FOR EACH ROW EXECUTE FUNCTION infrastructure.touch_row();

ALTER TABLE "platform"."installations" ADD CONSTRAINT "c_86696e0be2f4fb394909" FOREIGN KEY ("subscriber_id") REFERENCES "platform"."subscribers"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_338facd04ddd3576fa79" ON "platform"."installations" ("subscriber_id");

ALTER TABLE "platform"."installations" ADD CONSTRAINT "c_468680cc1385ace1caea" FOREIGN KEY ("release_id") REFERENCES "platform"."releases"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_e6528de6b98b5389f8c8" ON "platform"."installations" ("release_id");

ALTER TABLE "platform"."database_resources" ADD CONSTRAINT "c_21d39ec13503f45a6273" FOREIGN KEY ("installation_id") REFERENCES "platform"."installations"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_0a26ec42d43ce5a2f5ef" ON "platform"."database_resources" ("installation_id");

ALTER TABLE "platform"."storage_resources" ADD CONSTRAINT "c_ff66689924c7fa7a3503" FOREIGN KEY ("installation_id") REFERENCES "platform"."installations"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_d0aefd0592748ddd8cda" ON "platform"."storage_resources" ("installation_id");

ALTER TABLE "platform"."plan_versions" ADD CONSTRAINT "c_1bf0584b214d9a0d93ae" FOREIGN KEY ("plan_id") REFERENCES "platform"."plans"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_80f30d62a82c4a852aa1" ON "platform"."plan_versions" ("plan_id");

ALTER TABLE "platform"."plan_entitlements" ADD CONSTRAINT "c_3ff9f7129f9f641d0949" FOREIGN KEY ("plan_version_id") REFERENCES "platform"."plan_versions"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_297ddaadb61f739c61e9" ON "platform"."plan_entitlements" ("plan_version_id");

ALTER TABLE "platform"."plan_entitlements" ADD CONSTRAINT "c_50ea95623a409b57e287" FOREIGN KEY ("feature_id") REFERENCES "platform"."features"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_65bf72e36ba07a0f746e" ON "platform"."plan_entitlements" ("feature_id");

ALTER TABLE "platform"."subscriptions" ADD CONSTRAINT "c_495980546946c9fb769e" FOREIGN KEY ("subscriber_id") REFERENCES "platform"."subscribers"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_8cdcd7039d153b979ea8" ON "platform"."subscriptions" ("subscriber_id");

ALTER TABLE "platform"."subscriptions" ADD CONSTRAINT "c_2e591fd22eca7b918756" FOREIGN KEY ("plan_version_id") REFERENCES "platform"."plan_versions"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_4a7fc6548d090d302753" ON "platform"."subscriptions" ("plan_version_id");

ALTER TABLE "platform"."subscription_installations" ADD CONSTRAINT "c_d25d252ef7d9be1fc990" FOREIGN KEY ("subscription_id") REFERENCES "platform"."subscriptions"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_18f34491d11d5be6e98e" ON "platform"."subscription_installations" ("subscription_id");

ALTER TABLE "platform"."subscription_installations" ADD CONSTRAINT "c_cdeb6547b870e15328ab" FOREIGN KEY ("installation_id") REFERENCES "platform"."installations"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_2f0b18054c1442a9b486" ON "platform"."subscription_installations" ("installation_id");

ALTER TABLE "platform"."entitlement_overrides" ADD CONSTRAINT "c_b16e4683c3e5841c0f57" FOREIGN KEY ("subscription_id") REFERENCES "platform"."subscriptions"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_8a1c5f360bbd95cba706" ON "platform"."entitlement_overrides" ("subscription_id");

ALTER TABLE "platform"."entitlement_overrides" ADD CONSTRAINT "c_3214772fdbea0723d97d" FOREIGN KEY ("feature_id") REFERENCES "platform"."features"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_cca3433dbda9b09683bd" ON "platform"."entitlement_overrides" ("feature_id");

ALTER TABLE "platform"."usage_counters" ADD CONSTRAINT "c_c36f457c0a736818eb03" FOREIGN KEY ("installation_id") REFERENCES "platform"."installations"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_55702f5cb360406ea42b" ON "platform"."usage_counters" ("installation_id");

ALTER TABLE "platform"."deployments" ADD CONSTRAINT "c_6f1b4b89e4923627377c" FOREIGN KEY ("installation_id") REFERENCES "platform"."installations"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_32f756b1cf64c9df4271" ON "platform"."deployments" ("installation_id");

ALTER TABLE "platform"."deployments" ADD CONSTRAINT "c_8d5a2a316e387d47edc8" FOREIGN KEY ("release_id") REFERENCES "platform"."releases"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_3a4d290ad05b9f28d983" ON "platform"."deployments" ("release_id");

ALTER TABLE "platform"."backup_runs" ADD CONSTRAINT "c_ae0094658ffe2ee0ab5b" FOREIGN KEY ("installation_id") REFERENCES "platform"."installations"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_004953085c24a484c383" ON "platform"."backup_runs" ("installation_id");

ALTER TABLE "platform"."restore_tests" ADD CONSTRAINT "c_6b5d010a2138463a927f" FOREIGN KEY ("backup_run_id") REFERENCES "platform"."backup_runs"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_df54573790b047caa635" ON "platform"."restore_tests" ("backup_run_id");

ALTER TABLE "platform"."restore_tests" ADD CONSTRAINT "c_6b91bc1774497574aa2a" FOREIGN KEY ("verified_by") REFERENCES "platform"."operators"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_158406434b07a1d49f70" ON "platform"."restore_tests" ("verified_by");

ALTER TABLE "platform"."support_access_grants" ADD CONSTRAINT "c_793d1ad96769e51906be" FOREIGN KEY ("installation_id") REFERENCES "platform"."installations"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_550a4db9702378a2f551" ON "platform"."support_access_grants" ("installation_id");

ALTER TABLE "platform"."support_access_grants" ADD CONSTRAINT "c_68dc6f1f82c2228ae436" FOREIGN KEY ("operator_id") REFERENCES "platform"."operators"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_b9dd05da28f8bdeb2bf1" ON "platform"."support_access_grants" ("operator_id");

ALTER TABLE "platform"."platform_audit_events" ADD CONSTRAINT "c_2b67bc8d7aa4e646ce19" FOREIGN KEY ("operator_id") REFERENCES "platform"."operators"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_b32444f42185196e6009" ON "platform"."platform_audit_events" ("operator_id");

ALTER TABLE "platform"."platform_audit_events" ADD CONSTRAINT "c_c78a88558fbc12696a3e" FOREIGN KEY ("installation_id") REFERENCES "platform"."installations"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_3ae7482334f17225b5de" ON "platform"."platform_audit_events" ("installation_id");

ALTER TABLE "platform"."offboarding_jobs" ADD CONSTRAINT "c_4f19a84c128a2a495481" FOREIGN KEY ("installation_id") REFERENCES "platform"."installations"(id) ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX "c_01cd0ba02cd9d884d3ba" ON "platform"."offboarding_jobs" ("installation_id");

ALTER TABLE platform.subscription_installations ADD COLUMN subscriber_id uuid NOT NULL;
ALTER TABLE platform.subscriptions ADD CONSTRAINT subscription_subscriber UNIQUE(id,subscriber_id);
ALTER TABLE platform.installations ADD CONSTRAINT installation_subscriber UNIQUE(id,subscriber_id);
ALTER TABLE platform.subscription_installations ADD CONSTRAINT same_subscription_subscriber
 FOREIGN KEY(subscription_id,subscriber_id) REFERENCES platform.subscriptions(id,subscriber_id);
ALTER TABLE platform.subscription_installations ADD CONSTRAINT same_installation_subscriber
 FOREIGN KEY(installation_id,subscriber_id) REFERENCES platform.installations(id,subscriber_id);
ALTER TABLE platform.usage_counters ADD CHECK(value>=0);
ALTER TABLE platform.plan_versions ADD CHECK(price>=0);
ALTER TABLE platform.entitlement_overrides ADD CONSTRAINT non_overlapping_overrides
 EXCLUDE USING gist(subscription_id WITH =,feature_id WITH =,tstzrange(starts_at,ends_at,'[)') WITH &&);
REVOKE ALL ON DATABASE :DBNAME FROM PUBLIC;
REVOKE ALL ON ALL FUNCTIONS IN SCHEMA infrastructure FROM PUBLIC;


REVOKE ALL ON ALL TABLES IN SCHEMA "platform" FROM PUBLIC;
REVOKE ALL ON ALL SEQUENCES IN SCHEMA "platform" FROM PUBLIC;
REVOKE ALL ON ALL FUNCTIONS IN SCHEMA "platform" FROM PUBLIC;
INSERT INTO infrastructure.migrations(version,checksum) VALUES ('20261010_001_platform','b101f85942f2758dae98111d3844acdf52676352f127647776067611bf1c59d3');
\endif
COMMIT;

INSERT INTO deployment.bundle_migrations(name,sha256) VALUES ('001-platform.sql','e0b0d930c9ebb1e49d3af072bac05171f7e693895bf4afeb325828aaec5205f8');
\endif


-- ===== 013-platform-session-access.sql =====
SELECT EXISTS (SELECT FROM deployment.bundle_migrations WHERE name='013-platform-session-access.sql') AS bundle_done \gset
\if :bundle_done
DO $$ BEGIN IF NOT EXISTS (SELECT FROM deployment.bundle_migrations WHERE name='013-platform-session-access.sql' AND sha256='a1486dfb5876bd9b3c479d48d4570b6b3f86f2582afb2c0f651121628ede32ad') THEN RAISE EXCEPTION 'Empreinte différente : 013-platform-session-access.sql'; END IF; END $$;
\else
-- ========================================================================
-- IMPORTANT: This migration MUST be run against database prodigital_platform
-- as user postgres, NOT against database prodigital.
--
-- Before running this file, connect genesis to prodigital_platform:
--   GRANT CONNECT ON DATABASE prodigital_platform TO genesis;
-- (This cannot be included in a single-database migration script)
-- ========================================================================

-- Grant genesis role session access to platform.* schema
-- Required for /api/platform session API (Lot8 SaaS)
-- Allows GENESIS session to read/write platform subscribers, plans, subscriptions, installations

-- Schema access (idempotent)
GRANT USAGE ON SCHEMA platform TO genesis;

-- Table access: SELECT, INSERT, UPDATE (no DELETE - platform data is long-lived)
GRANT SELECT, INSERT, UPDATE ON platform.operators TO genesis;
GRANT SELECT, INSERT, UPDATE ON platform.subscribers TO genesis;
GRANT SELECT, INSERT, UPDATE ON platform.installations TO genesis;
GRANT SELECT, INSERT, UPDATE ON platform.plans TO genesis;
GRANT SELECT, INSERT, UPDATE ON platform.plan_versions TO genesis;
GRANT SELECT, INSERT, UPDATE ON platform.features TO genesis;
GRANT SELECT, INSERT, UPDATE ON platform.plan_entitlements TO genesis;
GRANT SELECT, INSERT, UPDATE ON platform.subscriptions TO genesis;
GRANT SELECT, INSERT, UPDATE ON platform.subscription_installations TO genesis;
GRANT SELECT, INSERT, UPDATE ON platform.offboarding_jobs TO genesis;

-- Sequence access (for INSERT operations)
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA platform TO genesis;

-- Default privileges for future tables (if any)
ALTER DEFAULT PRIVILEGES IN SCHEMA platform 
  GRANT SELECT, INSERT, UPDATE ON TABLES TO genesis;

ALTER DEFAULT PRIVILEGES IN SCHEMA platform 
  GRANT USAGE, SELECT ON SEQUENCES TO genesis;

-- RLS is enabled on platform tables by 001-platform.sql
-- Check if permissive policies are needed:

-- Note: If RLS policies do not exist for genesis role, add them here.
-- Based on the schema, RLS is enabled but no policies are visible in 001-platform.sql.
-- This means ONLY superuser can access until policies are added.

-- Add permissive policies for genesis role

-- Operators
DROP POLICY IF EXISTS genesis_read_operators ON platform.operators;
CREATE POLICY genesis_read_operators ON platform.operators
  FOR SELECT
  TO genesis
  USING (true);

DROP POLICY IF EXISTS genesis_write_operators ON platform.operators;
CREATE POLICY genesis_write_operators ON platform.operators
  FOR ALL
  TO genesis
  USING (true)
  WITH CHECK (true);

-- Subscribers
DROP POLICY IF EXISTS genesis_read_subscribers ON platform.subscribers;
CREATE POLICY genesis_read_subscribers ON platform.subscribers
  FOR SELECT
  TO genesis
  USING (true);

DROP POLICY IF EXISTS genesis_write_subscribers ON platform.subscribers;
CREATE POLICY genesis_write_subscribers ON platform.subscribers
  FOR ALL
  TO genesis
  USING (true)
  WITH CHECK (true);

-- Installations
DROP POLICY IF EXISTS genesis_read_installations ON platform.installations;
CREATE POLICY genesis_read_installations ON platform.installations
  FOR SELECT
  TO genesis
  USING (true);

DROP POLICY IF EXISTS genesis_write_installations ON platform.installations;
CREATE POLICY genesis_write_installations ON platform.installations
  FOR ALL
  TO genesis
  USING (true)
  WITH CHECK (true);

-- Plans
DROP POLICY IF EXISTS genesis_read_plans ON platform.plans;
CREATE POLICY genesis_read_plans ON platform.plans
  FOR SELECT
  TO genesis
  USING (true);

DROP POLICY IF EXISTS genesis_write_plans ON platform.plans;
CREATE POLICY genesis_write_plans ON platform.plans
  FOR ALL
  TO genesis
  USING (true)
  WITH CHECK (true);

-- Plan versions
DROP POLICY IF EXISTS genesis_read_plan_versions ON platform.plan_versions;
CREATE POLICY genesis_read_plan_versions ON platform.plan_versions
  FOR SELECT
  TO genesis
  USING (true);

DROP POLICY IF EXISTS genesis_write_plan_versions ON platform.plan_versions;
CREATE POLICY genesis_write_plan_versions ON platform.plan_versions
  FOR ALL
  TO genesis
  USING (true)
  WITH CHECK (true);

-- Features
DROP POLICY IF EXISTS genesis_read_features ON platform.features;
CREATE POLICY genesis_read_features ON platform.features
  FOR SELECT
  TO genesis
  USING (true);

DROP POLICY IF EXISTS genesis_write_features ON platform.features;
CREATE POLICY genesis_write_features ON platform.features
  FOR ALL
  TO genesis
  USING (true)
  WITH CHECK (true);

-- Plan entitlements
DROP POLICY IF EXISTS genesis_read_plan_entitlements ON platform.plan_entitlements;
CREATE POLICY genesis_read_plan_entitlements ON platform.plan_entitlements
  FOR SELECT
  TO genesis
  USING (true);

DROP POLICY IF EXISTS genesis_write_plan_entitlements ON platform.plan_entitlements;
CREATE POLICY genesis_write_plan_entitlements ON platform.plan_entitlements
  FOR ALL
  TO genesis
  USING (true)
  WITH CHECK (true);

-- Subscriptions
DROP POLICY IF EXISTS genesis_read_subscriptions ON platform.subscriptions;
CREATE POLICY genesis_read_subscriptions ON platform.subscriptions
  FOR SELECT
  TO genesis
  USING (true);

DROP POLICY IF EXISTS genesis_write_subscriptions ON platform.subscriptions;
CREATE POLICY genesis_write_subscriptions ON platform.subscriptions
  FOR ALL
  TO genesis
  USING (true)
  WITH CHECK (true);

-- Subscription installations
DROP POLICY IF EXISTS genesis_read_subscription_installations ON platform.subscription_installations;
CREATE POLICY genesis_read_subscription_installations ON platform.subscription_installations
  FOR SELECT
  TO genesis
  USING (true);

DROP POLICY IF EXISTS genesis_write_subscription_installations ON platform.subscription_installations;
CREATE POLICY genesis_write_subscription_installations ON platform.subscription_installations
  FOR ALL
  TO genesis
  USING (true)
  WITH CHECK (true);

-- Offboarding jobs
DROP POLICY IF EXISTS genesis_read_offboarding_jobs ON platform.offboarding_jobs;
CREATE POLICY genesis_read_offboarding_jobs ON platform.offboarding_jobs
  FOR SELECT
  TO genesis
  USING (true);

DROP POLICY IF EXISTS genesis_write_offboarding_jobs ON platform.offboarding_jobs;
CREATE POLICY genesis_write_offboarding_jobs ON platform.offboarding_jobs
  FOR ALL
  TO genesis
  USING (true)
  WITH CHECK (true);

INSERT INTO deployment.bundle_migrations(name,sha256) VALUES ('013-platform-session-access.sql','a1486dfb5876bd9b3c479d48d4570b6b3f86f2582afb2c0f651121628ede32ad');
\endif


-- ===== 014-platform-lifecycle-access.sql =====
SELECT EXISTS (SELECT FROM deployment.bundle_migrations WHERE name='014-platform-lifecycle-access.sql') AS bundle_done \gset
\if :bundle_done
DO $$ BEGIN IF NOT EXISTS (SELECT FROM deployment.bundle_migrations WHERE name='014-platform-lifecycle-access.sql' AND sha256='c2d3dedfdf51ebbeb9d0624f84f80b4e254b908c97a663498bedbf9f2df5e599') THEN RAISE EXCEPTION 'Empreinte différente : 014-platform-lifecycle-access.sql'; END IF; END $$;
\else
-- ========================================================================
-- IMPORTANT: This migration MUST be run against database prodigital_platform
-- as user postgres, NOT against database prodigital.
-- ========================================================================

-- Grant genesis role session access to platform backup/restore lifecycle tables
-- Required for /api/platform backup-runs and restore-tests (Lot8 lifecycle)
-- 013-platform-session-access.sql already covers installations, offboarding_jobs,
-- subscribers, plans, subscriptions. Do not re-grant those tables here.

-- Table access: SELECT, INSERT, UPDATE (no DELETE - platform data is long-lived)
GRANT SELECT, INSERT, UPDATE ON platform.backup_runs TO genesis;
GRANT SELECT, INSERT, UPDATE ON platform.restore_tests TO genesis;

-- RLS is enabled on these tables by 001-platform.sql with no genesis policies.
-- Add permissive policies for genesis role (idempotent: DROP + CREATE).

-- Backup runs
DROP POLICY IF EXISTS genesis_read_backup_runs ON platform.backup_runs;
CREATE POLICY genesis_read_backup_runs ON platform.backup_runs
  FOR SELECT
  TO genesis
  USING (true);

DROP POLICY IF EXISTS genesis_write_backup_runs ON platform.backup_runs;
CREATE POLICY genesis_write_backup_runs ON platform.backup_runs
  FOR ALL
  TO genesis
  USING (true)
  WITH CHECK (true);

-- Restore tests
DROP POLICY IF EXISTS genesis_read_restore_tests ON platform.restore_tests;
CREATE POLICY genesis_read_restore_tests ON platform.restore_tests
  FOR SELECT
  TO genesis
  USING (true);

DROP POLICY IF EXISTS genesis_write_restore_tests ON platform.restore_tests;
CREATE POLICY genesis_write_restore_tests ON platform.restore_tests
  FOR ALL
  TO genesis
  USING (true)
  WITH CHECK (true);

INSERT INTO deployment.bundle_migrations(name,sha256) VALUES ('014-platform-lifecycle-access.sql','c2d3dedfdf51ebbeb9d0624f84f80b4e254b908c97a663498bedbf9f2df5e599');
\endif


-- ===== 018-platform-quotas-access.sql =====
SELECT EXISTS (SELECT FROM deployment.bundle_migrations WHERE name='018-platform-quotas-access.sql') AS bundle_done \gset
\if :bundle_done
DO $$ BEGIN IF NOT EXISTS (SELECT FROM deployment.bundle_migrations WHERE name='018-platform-quotas-access.sql' AND sha256='86f8c2315f10df68fc57e215e8b3203de98d382349016c7bc1403e1c7140c556') THEN RAISE EXCEPTION 'Empreinte différente : 018-platform-quotas-access.sql'; END IF; END $$;
\else
-- ========================================================================
-- IMPORTANT: This migration MUST be run against database prodigital_platform
-- as user postgres, NOT against database prodigital.
-- ========================================================================
-- Lot8 SaaS: quotas (plan_entitlements + usage_counters + overrides) and
-- renewal (platform.subscriptions.ends_on). No new tables.
-- 013 already grants plans/features/plan_entitlements/subscriptions.
-- This file only covers usage_counters and entitlement_overrides.

GRANT SELECT, INSERT, UPDATE ON platform.usage_counters TO genesis;
GRANT SELECT ON platform.entitlement_overrides TO genesis;

DROP POLICY IF EXISTS genesis_read_usage_counters ON platform.usage_counters;
CREATE POLICY genesis_read_usage_counters ON platform.usage_counters
  FOR SELECT
  TO genesis
  USING (true);

DROP POLICY IF EXISTS genesis_write_usage_counters ON platform.usage_counters;
CREATE POLICY genesis_write_usage_counters ON platform.usage_counters
  FOR ALL
  TO genesis
  USING (true)
  WITH CHECK (true);

DROP POLICY IF EXISTS genesis_read_entitlement_overrides ON platform.entitlement_overrides;
CREATE POLICY genesis_read_entitlement_overrides ON platform.entitlement_overrides
  FOR SELECT
  TO genesis
  USING (true);

INSERT INTO deployment.bundle_migrations(name,sha256) VALUES ('018-platform-quotas-access.sql','86f8c2315f10df68fc57e215e8b3203de98d382349016c7bc1403e1c7140c556');
\endif


-- ===== 019-platform-offboard-access.sql =====
SELECT EXISTS (SELECT FROM deployment.bundle_migrations WHERE name='019-platform-offboard-access.sql') AS bundle_done \gset
\if :bundle_done
DO $$ BEGIN IF NOT EXISTS (SELECT FROM deployment.bundle_migrations WHERE name='019-platform-offboard-access.sql' AND sha256='1952fcab4ba3e8ddd906da3b0f3096bacdc630bddcbe849d245967d219edc84d') THEN RAISE EXCEPTION 'Empreinte différente : 019-platform-offboard-access.sql'; END IF; END $$;
\else
-- ========================================================================
-- IMPORTANT: Run against database prodigital_platform as postgres,
-- NOT against database prodigital.
-- ========================================================================
--
-- B5 offboard completes platform.offboarding_jobs in place and:
-- - revokes platform.support_access_grants
-- - appends platform.platform_audit_events
-- 013 already covers installations, subscribers, subscriptions, offboarding_jobs.
-- 014 covers backup_runs / restore_tests. Do not re-grant those here.

GRANT SELECT, INSERT, UPDATE ON platform.support_access_grants TO genesis;
GRANT SELECT, INSERT ON platform.platform_audit_events TO genesis;

DROP POLICY IF EXISTS genesis_read_support_access_grants ON platform.support_access_grants;
CREATE POLICY genesis_read_support_access_grants ON platform.support_access_grants
  FOR SELECT
  TO genesis
  USING (true);

DROP POLICY IF EXISTS genesis_write_support_access_grants ON platform.support_access_grants;
CREATE POLICY genesis_write_support_access_grants ON platform.support_access_grants
  FOR ALL
  TO genesis
  USING (true)
  WITH CHECK (true);

DROP POLICY IF EXISTS genesis_read_platform_audit_events ON platform.platform_audit_events;
CREATE POLICY genesis_read_platform_audit_events ON platform.platform_audit_events
  FOR SELECT
  TO genesis
  USING (true);

DROP POLICY IF EXISTS genesis_insert_platform_audit_events ON platform.platform_audit_events;
CREATE POLICY genesis_insert_platform_audit_events ON platform.platform_audit_events
  FOR INSERT
  TO genesis
  WITH CHECK (true);

INSERT INTO deployment.bundle_migrations(name,sha256) VALUES ('019-platform-offboard-access.sql','1952fcab4ba3e8ddd906da3b0f3096bacdc630bddcbe849d245967d219edc84d');
\endif
