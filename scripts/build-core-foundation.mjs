// Produit le fichier d'installation autonome du socle commun ; ne se connecte à aucune base.
import fs from 'node:fs';
import path from 'node:path';
import { createHash } from 'node:crypto';
const dir = path.resolve('exports/prodigital-core-v1');
fs.mkdirSync(dir, { recursive: true });
const base = fs.readFileSync(path.join(dir, 'foundation-source.sql'), 'utf8');
const contact = fs.readFileSync('server/migrations/001-site-contact.sql', 'utf8');
const policies = [];
const domains = {
  'core.companies': 'directory', 'core.contacts': 'directory',
  'core.company_contacts': 'directory', 'core.addresses': 'directory',
  'core.teams': 'directory', 'core.team_members': 'directory',
  'catalog.offerings': 'catalog', 'catalog.courses': 'catalog',
  'catalog.course_modules': 'catalog', 'documents.files': 'documents',
  'documents.attachments': 'documents', 'web.requests': 'requests',
  'web.request_notes': 'requests', 'integration.connections': 'integrations',
};
for (const [table, scope] of Object.entries(domains)) {
  policies.push(`
ALTER TABLE ${table} ENABLE ROW LEVEL SECURITY;
ALTER TABLE ${table} FORCE ROW LEVEL SECURITY;
CREATE INDEX ON ${table}(organization_id);
CREATE POLICY tenant_boundary ON ${table} AS RESTRICTIVE TO pd_core_api
 USING (organization_id = (SELECT iam.current_organization_id()))
 WITH CHECK (organization_id = (SELECT iam.current_organization_id()));
CREATE POLICY scoped_read ON ${table} FOR SELECT TO pd_core_api USING ((SELECT iam.permitted('${scope}.read')));
CREATE POLICY scoped_insert ON ${table} FOR INSERT TO pd_core_api WITH CHECK ((SELECT iam.permitted('${scope}.write')));
CREATE POLICY scoped_update ON ${table} FOR UPDATE TO pd_core_api
 USING ((SELECT iam.permitted('${scope}.write'))) WITH CHECK ((SELECT iam.permitted('${scope}.write')));
-- Pas de DELETE/TRUNCATE accordé : archivage par les champs métier.
GRANT SELECT, INSERT, UPDATE ON ${table} TO pd_core_api;
CREATE TRIGGER preserve_identity BEFORE UPDATE ON ${table} FOR EACH ROW EXECUTE FUNCTION core_meta.touch_row();
CREATE TRIGGER audit_change AFTER INSERT OR UPDATE OR DELETE ON ${table} FOR EACH ROW EXECUTE FUNCTION audit.record_change();
`);
}
const site = `
-- Tables compatibles avec l'API du formulaire actuellement dans le dépôt.
${contact}
ALTER TABLE site.contact_submissions ADD COLUMN organization_id uuid NOT NULL DEFAULT iam.site_organization_id() REFERENCES core.organizations(id);
ALTER TABLE site.contact_submissions ADD CONSTRAINT contact_tenant_identity UNIQUE(organization_id,id);
ALTER TABLE site.contact_operations ADD COLUMN organization_id uuid NOT NULL DEFAULT iam.site_organization_id() REFERENCES core.organizations(id);
ALTER TABLE site.contact_operations ADD CONSTRAINT contact_operation_tenant_fk FOREIGN KEY(organization_id,submission_id) REFERENCES site.contact_submissions(organization_id,id);
ALTER TABLE site.contact_events ADD COLUMN organization_id uuid NOT NULL DEFAULT iam.site_organization_id() REFERENCES core.organizations(id);
ALTER TABLE site.contact_events ADD CONSTRAINT contact_event_tenant_fk FOREIGN KEY(organization_id,submission_id) REFERENCES site.contact_submissions(organization_id,id);
${['contact_submissions','contact_operations','contact_events'].map(name => `
ALTER TABLE site.${name} ENABLE ROW LEVEL SECURITY;
ALTER TABLE site.${name} FORCE ROW LEVEL SECURITY;
CREATE INDEX ON site.${name}(organization_id);
CREATE POLICY site_isolation ON site.${name} TO pd_site_api
 USING (organization_id = (SELECT iam.site_organization_id()))
 WITH CHECK (organization_id = (SELECT iam.site_organization_id()));
`).join('\n')}
CREATE TABLE site.schema_migrations(name text PRIMARY KEY, applied_at timestamptz NOT NULL DEFAULT clock_timestamp());
INSERT INTO site.schema_migrations(name) VALUES ('001-site-contact.sql');
GRANT USAGE ON SCHEMA site TO pd_site_api;
GRANT SELECT, INSERT ON site.contact_submissions, site.contact_events TO pd_site_api;
GRANT SELECT, INSERT, UPDATE ON site.contact_operations TO pd_site_api;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA site TO pd_site_api;
-- Le rôle API multi-entreprises n'a aucun accès direct aux demandes du site ProDigital.
REVOKE ALL ON ALL FUNCTIONS IN SCHEMA site FROM PUBLIC;
`;
const body = base.replace('-- GENERATED_TENANT_POLICIES', () => policies.join('\n')).replace('-- GENERATED_SITE_SCHEMA', () => site);
const digest = createHash('sha256').update(body).digest('hex');
const header = `-- PRODIGITAL CORE V1 : BASE COMMUNE, installation neuve uniquement.
-- PostgreSQL 15+ ; exécuter comme administrateur avec psql -d prodigital -f prodigital-core.sql
-- Ne pas importer les anciens exports Genesis avec ce fichier. Lire INSTALLATION.md.
-- Aucun mot de passe ni compte humain préconfiguré. Aucun changement de production automatique.
\\set ON_ERROR_STOP on
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
SELECT EXISTS(SELECT FROM core_meta.migrations WHERE version='foundation_v1') AS installed \\gset
\\if :installed
DO $$ BEGIN IF NOT EXISTS(SELECT FROM core_meta.migrations WHERE version='foundation_v1' AND sha256='${digest}') THEN RAISE EXCEPTION 'Version déjà installée avec un SQL différent : migration nécessaire'; END IF; END $$;
\\echo ProDigital Core V1 deja installe, empreinte verifiee.
\\else
-- Refus de mélanger ce modèle avec une base Core/Genesis existante.
DO $$ BEGIN
 IF EXISTS(SELECT FROM pg_namespace WHERE nspname IN ('core','iam','site','catalog','documents','web','integration','audit','notifications','genesis','crm','itsm','platform'))
 THEN RAISE EXCEPTION 'Base déjà structurée : installer sur une base vierge ou préparer une migration des données. Aucune table existante supprimée.'; END IF;
 IF EXISTS(SELECT FROM pg_roles WHERE rolname IN ('pd_core_api','pd_site_api'))
 THEN RAISE EXCEPTION 'Rôles pd_core_api/pd_site_api déjà présents sur ce serveur : contrôler les rôles avant installation.'; END IF;
END $$;
`;
fs.writeFileSync(path.join(dir, 'prodigital-core.sql'), header+body+`\nINSERT INTO core_meta.migrations(version,sha256) VALUES ('foundation_v1','${digest}');\n\\endif\nCOMMIT;\n`);
console.log('Fichier généré : exports/prodigital-core-v1/prodigital-core.sql');
