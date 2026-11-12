-- Vérification des droits réels du site : toutes les écritures sont annulées.
\set ON_ERROR_STOP on
BEGIN;
SET LOCAL ROLE site_vitrine;
INSERT INTO site.contact_submissions
 (idempotency_key, request_hash, natural_key, given_name, family_name, email, subject, subject_group, message)
 VALUES ('sql-check-' || gen_random_uuid(), 'validation', 'validation', 'Test', 'SQL', 'test@example.invalid', 'Vérification SQL', 'autre', 'Vérification technique annulée à la fin du test.')
 RETURNING id AS test_id \gset
INSERT INTO site.contact_operations(submission_id,kind) VALUES (:'test_id','email'),(:'test_id','crm');
INSERT INTO site.contact_events(submission_id,kind,event) VALUES (:'test_id','submission','recorded');
UPDATE site.contact_operations SET status='running',attempts=1 WHERE submission_id=:'test_id' AND kind='email';
SELECT kind,status FROM site.contact_operations WHERE submission_id=:'test_id';
ROLLBACK;
SELECT schemaname,count(*) AS tables FROM pg_tables
 WHERE schemaname NOT IN ('pg_catalog','information_schema') GROUP BY schemaname ORDER BY schemaname;
