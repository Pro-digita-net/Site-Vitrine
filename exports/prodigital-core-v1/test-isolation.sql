-- UNIQUEMENT sur une copie de test. Aucune donnée de test n'est conservée : ROLLBACK final.
\set ON_ERROR_STOP on
BEGIN;
CREATE FUNCTION pg_temp.expect_denied(statement text, expected_code text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
 BEGIN EXECUTE statement;
 EXCEPTION WHEN OTHERS THEN
  IF SQLSTATE=expected_code THEN RETURN; ELSE RAISE; END IF;
 END;
 RAISE EXCEPTION 'Accès interdit accepté : %', statement;
END $$;

INSERT INTO core.organizations(id,slug,name) VALUES
 ('10000000-0000-4000-8000-000000000001','test-a','Entreprise A'),
 ('20000000-0000-4000-8000-000000000001','test-b','Entreprise B');
INSERT INTO iam.users(id,email,given_name,family_name) VALUES
 ('10000000-0000-4000-8000-000000000002','a@example.invalid','Alice','Test'),
 ('20000000-0000-4000-8000-000000000002','b@example.invalid','Bob','Test'),
 ('30000000-0000-4000-8000-000000000002','v@example.invalid','Viewer','Test');
INSERT INTO iam.memberships(organization_id,user_id,role) VALUES
 ('10000000-0000-4000-8000-000000000001','10000000-0000-4000-8000-000000000002','editor'),
 ('20000000-0000-4000-8000-000000000001','20000000-0000-4000-8000-000000000002','owner'),
 ('10000000-0000-4000-8000-000000000001','30000000-0000-4000-8000-000000000002','viewer');
INSERT INTO iam.access_tokens(organization_id,user_id,token_hash,kind,scopes,expires_at) VALUES
 ('10000000-0000-4000-8000-000000000001','10000000-0000-4000-8000-000000000002',sha256(convert_to(repeat('a',64),'UTF8')),'api_key',ARRAY['directory.read','directory.write','catalog.read','catalog.write','documents.read','documents.write','requests.read','requests.write','integrations.read','integrations.write','audit.read']::iam.permission[],now()+interval '1 hour'),
 ('20000000-0000-4000-8000-000000000001','20000000-0000-4000-8000-000000000002',sha256(convert_to(repeat('b',64),'UTF8')),'session',ARRAY['directory.read','directory.write']::iam.permission[],now()+interval '1 hour'),
 ('10000000-0000-4000-8000-000000000001','30000000-0000-4000-8000-000000000002',sha256(convert_to(repeat('v',64),'UTF8')),'session',ARRAY['directory.read','directory.write']::iam.permission[],now()+interval '1 hour'),
 ('10000000-0000-4000-8000-000000000001','10000000-0000-4000-8000-000000000002',sha256(convert_to(repeat('s',64),'UTF8')),'api_key',ARRAY['directory.read']::iam.permission[],now()+interval '1 hour');
INSERT INTO iam.access_tokens(organization_id,user_id,token_hash,kind,scopes,created_at,expires_at,revoked_at) VALUES
 ('10000000-0000-4000-8000-000000000001','10000000-0000-4000-8000-000000000002',sha256(convert_to(repeat('x',64),'UTF8')),'session',ARRAY['directory.read']::iam.permission[],now()-interval '2 hours',now()-interval '1 hour',NULL),
 ('10000000-0000-4000-8000-000000000001','10000000-0000-4000-8000-000000000002',sha256(convert_to(repeat('r',64),'UTF8')),'api_key',ARRAY['directory.read']::iam.permission[],now(),now()+interval '1 hour',now());
INSERT INTO core.companies(organization_id,id,name) VALUES
 ('00000000-0000-4000-8000-000000000001','00000000-0000-4000-8000-000000000010','Confidentiel ProDigital'),
 ('10000000-0000-4000-8000-000000000001','10000000-0000-4000-8000-000000000010','Client A'),
 ('20000000-0000-4000-8000-000000000001','20000000-0000-4000-8000-000000000010','Client B');
INSERT INTO core.application_plans(application_code,code,name,published) VALUES
 ('crm','visible-test','Plan test visible',true),('crm','private-test','Plan privé',false);
INSERT INTO core.subscriptions(organization_id,application_code,plan_code,status,starts_at) VALUES
 ('10000000-0000-4000-8000-000000000001','crm','visible-test','active',now()),
 ('20000000-0000-4000-8000-000000000001','crm','private-test','active',now());
INSERT INTO site.contact_submissions(organization_id,idempotency_key,request_hash,natural_key,given_name,family_name,email,subject,subject_group,message)
 VALUES ('20000000-0000-4000-8000-000000000001','private-b-site-test','test','test','Private','B','b@example.invalid','Privé','autre','Demande privée entreprise B.');

SET SESSION AUTHORIZATION pd_core_api;
DO $$ BEGIN
 ASSERT (SELECT count(*) FROM core.companies)=0,'Sans jeton : aucune ligne';
 ASSERT iam.current_organization_id() IS NULL,'Sans jeton : aucune organisation';
END $$;
SELECT set_config('app.access_token',repeat('a',64),true);
DO $$ BEGIN
 ASSERT (SELECT count(*) FROM core.companies)=1,'A ne voit que ses données';
 ASSERT (SELECT count(*) FROM core.organizations)=1,'A ne voit pas le profil ProDigital';
 ASSERT (SELECT name FROM core.companies)='Client A';
 ASSERT (SELECT count(*) FROM core.subscriptions)=1,'Abonnement privé de A seulement';
 ASSERT (SELECT count(*) FROM core.application_plans)=1,'Seul le plan publié est visible';
END $$;
-- Falsifier les identifiants du contexte ne change pas le tenant du jeton.
SELECT set_config('app.organization_id','00000000-0000-4000-8000-000000000001',true);
SELECT set_config('app.user_id','20000000-0000-4000-8000-000000000002',true);
DO $$ BEGIN
 ASSERT iam.current_organization_id()='10000000-0000-4000-8000-000000000001'::uuid;
 ASSERT iam.current_user_id()='10000000-0000-4000-8000-000000000002'::uuid;
 ASSERT NOT EXISTS(SELECT FROM core.companies WHERE organization_id='00000000-0000-4000-8000-000000000001');
 UPDATE core.companies SET name='Intrusion' WHERE organization_id='20000000-0000-4000-8000-000000000001';
 ASSERT NOT FOUND,'UPDATE inter-entreprises doit affecter zéro ligne';
END $$;
SELECT pg_temp.expect_denied($q$INSERT INTO core.companies(organization_id,name) VALUES ('20000000-0000-4000-8000-000000000001','Intrusion')$q$,'42501');
SELECT pg_temp.expect_denied($q$UPDATE core.companies SET organization_id='20000000-0000-4000-8000-000000000001'$q$,'42501');
SELECT pg_temp.expect_denied($q$SELECT * FROM iam.access_tokens$q$,'42501');
SELECT pg_temp.expect_denied($q$SELECT * FROM iam.users$q$,'42501');
SELECT pg_temp.expect_denied($q$SELECT * FROM iam.memberships$q$,'42501');
SELECT pg_temp.expect_denied($q$UPDATE iam.memberships SET role='owner'$q$,'42501');
SELECT pg_temp.expect_denied($q$UPDATE core.subscriptions SET status='active'$q$,'42501');
SELECT pg_temp.expect_denied($q$UPDATE core.organization_applications SET status='enabled'$q$,'42501');
SELECT pg_temp.expect_denied($q$SELECT * FROM site.contact_submissions$q$,'42501');
SELECT pg_temp.expect_denied($q$SELECT * FROM integration.connection_secrets$q$,'42501');
SELECT pg_temp.expect_denied($q$TRUNCATE core.companies$q$,'42501');
SELECT pg_temp.expect_denied($q$DELETE FROM core.companies$q$,'42501');
SELECT pg_temp.expect_denied($q$ALTER TABLE core.companies DISABLE ROW LEVEL SECURITY$q$,'42501');
SELECT pg_temp.expect_denied($q$SET ROLE postgres$q$,'42501');
SELECT pg_temp.expect_denied($q$SET ROLE pd_site_api$q$,'42501');
SELECT pg_temp.expect_denied($q$CREATE TABLE public.attack(id int)$q$,'42501');
SELECT set_config('row_security','off',true);
SELECT pg_temp.expect_denied($q$SELECT * FROM core.companies$q$,'42501');
SELECT set_config('row_security','on',true);

INSERT INTO core.contacts(id,given_name,family_name) VALUES ('10000000-0000-4000-8000-000000000020','Contact','A');
SELECT pg_temp.expect_denied($q$INSERT INTO core.company_contacts(company_id,contact_id) VALUES ('20000000-0000-4000-8000-000000000010','10000000-0000-4000-8000-000000000020')$q$,'23503');
INSERT INTO core.company_contacts(company_id,contact_id) VALUES ('10000000-0000-4000-8000-000000000010','10000000-0000-4000-8000-000000000020');
UPDATE core.companies SET name='Client A modifié';
DO $$ BEGIN
 ASSERT EXISTS(SELECT FROM audit.events WHERE action='UPDATE' AND actor_user_id='10000000-0000-4000-8000-000000000002');
 ASSERT NOT EXISTS(SELECT FROM audit.events WHERE organization_id <> '10000000-0000-4000-8000-000000000001');
END $$;
SELECT pg_temp.expect_denied($q$UPDATE audit.events SET action='falsifie'$q$,'42501');
-- Même avec un scope write, un membre viewer reste en lecture seule.
SELECT set_config('app.access_token',repeat('v',64),true);
DO $$ BEGIN ASSERT (SELECT count(*) FROM core.companies)=1; ASSERT NOT iam.permitted('directory.write'); END $$;
SELECT pg_temp.expect_denied($q$INSERT INTO core.companies(name) VALUES ('Viewer write')$q$,'42501');
SELECT set_config('app.access_token',repeat('s',64),true);
DO $$ BEGIN ASSERT NOT iam.permitted('directory.write'); ASSERT (SELECT count(*) FROM core.contacts)=1; END $$;
SELECT pg_temp.expect_denied($q$INSERT INTO catalog.offerings(slug,name,kind) VALUES ('x','X','service')$q$,'42501');
SELECT set_config('app.access_token',repeat('b',64),true);
DO $$ BEGIN ASSERT (SELECT count(*) FROM core.companies)=1; ASSERT (SELECT name FROM core.companies)='Client B'; END $$;
SELECT set_config('app.access_token',repeat('x',64),true);
DO $$ BEGIN ASSERT (SELECT count(*) FROM core.companies)=0,'Jeton expiré'; END $$;
SELECT set_config('app.access_token',repeat('r',64),true);
DO $$ BEGIN ASSERT (SELECT count(*) FROM core.companies)=0,'Jeton révoqué'; END $$;
SELECT set_config('app.access_token',repeat('z',64),true);
DO $$ BEGIN ASSERT (SELECT count(*) FROM core.companies)=0,'Jeton inconnu'; END $$;
RESET SESSION AUTHORIZATION;
UPDATE iam.memberships SET status='suspended' WHERE user_id='10000000-0000-4000-8000-000000000002';
SET SESSION AUTHORIZATION pd_core_api;
SELECT set_config('app.access_token',repeat('a',64),true);
DO $$ BEGIN ASSERT (SELECT count(*) FROM core.companies)=0,'Appartenance suspendue'; END $$;
RESET SESSION AUTHORIZATION;
UPDATE iam.memberships SET status='active' WHERE user_id='10000000-0000-4000-8000-000000000002';
UPDATE core.organizations SET status='suspended' WHERE slug='test-a';
SET SESSION AUTHORIZATION pd_core_api;
DO $$ BEGIN ASSERT (SELECT count(*) FROM core.companies)=0,'Organisation suspendue'; END $$;
RESET SESSION AUTHORIZATION;

-- Le service du site ne choisit jamais son entreprise : liaison par session_user.
SET SESSION AUTHORIZATION pd_site_api;
DO $$ BEGIN
 ASSERT iam.site_organization_id()='00000000-0000-4000-8000-000000000001'::uuid;
 ASSERT (SELECT count(*) FROM site.contact_submissions)=0,'Le site ne lit pas les demandes B';
END $$;
INSERT INTO site.contact_submissions(idempotency_key,request_hash,natural_key,given_name,family_name,email,subject,subject_group,message)
 VALUES ('test-isolation-site','test','test','Test','SQL','test@example.invalid','Test','autre','Test technique annulé à la fin.') RETURNING id AS submission_id \gset
INSERT INTO site.contact_operations(submission_id,kind) VALUES (:'submission_id','email'),(:'submission_id','crm');
INSERT INTO site.contact_events(submission_id,kind,event) VALUES (:'submission_id','submission','recorded');
UPDATE site.contact_operations SET attempts=1,status='running' WHERE submission_id=:'submission_id' AND kind='email';
SELECT pg_temp.expect_denied($q$SELECT * FROM core.companies$q$,'42501');
SELECT pg_temp.expect_denied($q$SELECT * FROM iam.service_bindings$q$,'42501');
SELECT pg_temp.expect_denied($q$UPDATE site.contact_operations SET organization_id='10000000-0000-4000-8000-000000000001'$q$,'42501');
SELECT pg_temp.expect_denied($q$DELETE FROM site.contact_submissions$q$,'42501');
RESET SESSION AUTHORIZATION;
DO $$ BEGIN
 ASSERT NOT EXISTS(SELECT FROM pg_roles WHERE rolname IN ('pd_core_api','pd_site_api') AND (rolsuper OR rolbypassrls OR rolcreaterole OR rolcreatedb));
 ASSERT NOT EXISTS(SELECT FROM pg_auth_members m JOIN pg_roles r ON r.oid=m.member WHERE r.rolname IN ('pd_core_api','pd_site_api'));
 ASSERT NOT EXISTS(
  SELECT FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
  JOIN pg_attribute a ON a.attrelid=c.oid AND a.attname='organization_id'
  WHERE c.relkind='r' AND n.nspname IN ('core','catalog','documents','web','integration','notifications','audit','site')
  AND (NOT c.relrowsecurity OR NOT c.relforcerowsecurity)
 ),'Toutes les tables métier avec organisation ont une RLS forcée';
END $$;
ROLLBACK;
\echo SUCCES : isolation, scopes, droits, jetons, references, audit et formulaire verifies. Donnees de test annulees.
