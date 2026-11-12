import fs from 'node:fs';
import path from 'node:path';
import { createHash } from 'node:crypto';

const source = process.argv[2] || 'C:/GENESIS/infra/prodigital/database';
const out = path.resolve('exports/prodigital-core');
fs.mkdirSync(out, { recursive: true });
const hash = s => createHash('sha256').update(s).digest('hex');
const platform = ['001-platform.sql', '013-platform-session-access.sql', '014-platform-lifecycle-access.sql', '018-platform-quotas-access.sql', '019-platform-offboard-access.sql'];
const core = fs.readdirSync(source).filter(n => /^\d.*\.sql$/.test(n)
  && !platform.includes(n) && !/seed/.test(n) && !/^03[0-4]/.test(n)).sort();
const manifest = {};
const preamble = (database, roles) => `-- ProDigital : export des migrations existantes, 2026-11-12.
-- Exécuter avec psql, comme administrateur PostgreSQL 15+, dans ${database}.
-- Sauvegarder la base avant import. Ne pas lancer deux imports simultanés.
-- Ce fichier contient des commandes psql (\\if, \\gset) : pas un éditeur SQL générique.
-- Les nouveaux rôles sont NOLOGIN, sans mot de passe. Activer ensuite par \\password.
\\set ON_ERROR_STOP on
DO $$ BEGIN
 IF current_database() <> '${database}' THEN RAISE EXCEPTION 'Connectez-vous à la base ${database}'; END IF;
 IF current_setting('server_version_num')::int < 150000 THEN RAISE EXCEPTION 'PostgreSQL 15 minimum'; END IF;
END $$;
${roles.map(role => `DO $$ BEGIN IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname='${role}') THEN CREATE ROLE ${role} NOLOGIN; END IF; END $$;`).join('\n')}
CREATE SCHEMA IF NOT EXISTS deployment;
REVOKE ALL ON SCHEMA deployment FROM PUBLIC;
CREATE TABLE IF NOT EXISTS deployment.bundle_migrations (name text PRIMARY KEY, sha256 text NOT NULL, applied_at timestamptz NOT NULL DEFAULT now());
`;
function migration(name, body) {
  const digest = hash(body);
  manifest[name] = digest;
  return `\n-- ===== ${name} =====
SELECT EXISTS (SELECT FROM deployment.bundle_migrations WHERE name='${name}') AS bundle_done \\gset
\\if :bundle_done
DO $$ BEGIN IF NOT EXISTS (SELECT FROM deployment.bundle_migrations WHERE name='${name}' AND sha256='${digest}') THEN RAISE EXCEPTION 'Empreinte différente : ${name}'; END IF; END $$;
\\else
${body}
INSERT INTO deployment.bundle_migrations(name,sha256) VALUES ('${name}','${digest}');
\\endif
`;
}
function site() {
  return `BEGIN;
SELECT pg_advisory_xact_lock(hashtext('site.migrations'));
${fs.readFileSync('server/migrations/001-site-contact.sql','utf8')}
CREATE TABLE IF NOT EXISTS site.schema_migrations (name text PRIMARY KEY, applied_at timestamptz NOT NULL DEFAULT clock_timestamp());
INSERT INTO site.schema_migrations(name) VALUES ('001-site-contact.sql') ON CONFLICT DO NOTHING;
${fs.readFileSync('server/sql/site-role-grants.sql','utf8')}
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA site TO site_vitrine;
GRANT CONNECT ON DATABASE prodigital TO site_vitrine;
COMMIT;
`;
}
const bootstrap = `CREATE SCHEMA IF NOT EXISTS genesis AUTHORIZATION genesis;
CREATE SCHEMA IF NOT EXISTS orbit AUTHORIZATION orbit;
CREATE SCHEMA IF NOT EXISTS common;
GRANT USAGE ON SCHEMA common TO genesis, orbit;
GRANT CONNECT, TEMPORARY ON DATABASE prodigital TO genesis;
GRANT CONNECT ON DATABASE prodigital TO orbit;
ALTER ROLE genesis IN DATABASE prodigital SET search_path=genesis,common;
ALTER ROLE orbit IN DATABASE prodigital SET search_path=orbit,common;
`;
const read = n => fs.readFileSync(path.join(source,n),'utf8');
fs.writeFileSync(path.join(out,'01-prodigital-core-complet.sql'), preamble('prodigital',['genesis','orbit','site_vitrine'])+bootstrap+core.map(n=>migration(n,read(n))).join('\n')+migration('site-001.sql',site())+migration('site-core-readonly.sql',fs.readFileSync('server/sql/core-contact-requests-readonly.sql','utf8')));
fs.writeFileSync(path.join(out,'02-prodigital-platform.sql'), preamble('prodigital_platform',['genesis'])+'GRANT CONNECT ON DATABASE prodigital_platform TO genesis;\n'+platform.map(n=>migration(n,read(n))).join('\n'));
fs.writeFileSync(path.join(out,'03-site-contact-seulement.sql'), preamble('prodigital',['site_vitrine'])+site());
fs.writeFileSync(path.join(out,'manifest.json'),JSON.stringify({ source, core, platform, excluded:'Seeds de démonstration / inventaire et migrations SaaS 030–034 destinées aux installations abonnées. Les règles common/business/platform sont déjà intégrées aux migrations 001.',sha256:manifest },null,2));
console.log(`Export créé : ${core.length} migrations Core, ${platform.length} migrations Platform, schéma site et droits.`);
