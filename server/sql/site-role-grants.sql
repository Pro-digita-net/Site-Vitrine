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
