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
