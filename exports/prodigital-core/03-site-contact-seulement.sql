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
DO $$ BEGIN IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname='site_vitrine') THEN CREATE ROLE site_vitrine NOLOGIN; END IF; END $$;
CREATE SCHEMA IF NOT EXISTS deployment;
REVOKE ALL ON SCHEMA deployment FROM PUBLIC;
CREATE TABLE IF NOT EXISTS deployment.bundle_migrations (name text PRIMARY KEY, sha256 text NOT NULL, applied_at timestamptz NOT NULL DEFAULT now());
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
