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
