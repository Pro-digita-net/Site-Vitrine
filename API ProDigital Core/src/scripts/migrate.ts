// Migrations contrôlées : lancées à la main par un administrateur, jamais au démarrage des services.
//   MIGRATION_DATABASE_URL=postgresql://<administrateur>@.../prodigital node dist/scripts/migrate.js [--dry-run]
// Chaque fichier db/migrations/NNN_*.sql s'applique une seule fois, dans une transaction, avec son empreinte.
import { createHash } from "node:crypto";
import { readdir, readFile } from "node:fs/promises";
import pg from "pg";

const url = process.env.MIGRATION_DATABASE_URL;
if (!url) { console.error("MIGRATION_DATABASE_URL est obligatoire (compte administrateur, utilisé uniquement pour cette commande)."); process.exit(1); }
const dryRun = process.argv.includes("--dry-run");
const dir = new URL("../../db/migrations/", import.meta.url);
const client = new pg.Client({ connectionString: url, application_name: "core-migrate" });
await client.connect();
try {
  await client.query("BEGIN");
  await client.query("SET LOCAL lock_timeout = '15s'");
  await client.query("SELECT pg_advisory_xact_lock(hashtextextended('prodigital-core-migrations', 0))");
  const installed = await client.query("SELECT to_regclass('core_meta.migrations') IS NOT NULL AS ok");
  if (!installed.rows[0].ok || !(await client.query("SELECT 1 FROM core_meta.migrations WHERE version = 'foundation_v1'")).rowCount)
    throw new Error("Socle absent : installer d'abord db/foundation/prodigital-core.sql avec psql (voir README).");
  const applied = new Map((await client.query("SELECT version, sha256 FROM core_meta.migrations")).rows.map((r) => [r.version as string, r.sha256 as string]));
  for (const file of (await readdir(dir)).filter((f) => /^\d{3}_[a-z0-9_]+\.sql$/.test(f)).sort()) {
    const version = file.replace(/\.sql$/, "");
    const sql = await readFile(new URL(file, dir), "utf8");
    const sha256 = createHash("sha256").update(sql.replace(/\r\n/g, "\n")).digest("hex");
    if (applied.has(version)) {
      if (applied.get(version) !== sha256) throw new Error(`${version} déjà appliquée avec un contenu différent : écrire une nouvelle migration.`);
      console.log(`= ${version} (déjà appliquée)`); continue;
    }
    if (dryRun) { console.log(`~ ${version} (serait appliquée)`); continue; }
    await client.query(sql);
    await client.query("INSERT INTO core_meta.migrations (version, sha256) VALUES ($1, $2)", [version, sha256]);
    console.log(`+ ${version}`);
  }
  await client.query("COMMIT");
} catch (error) {
  await client.query("ROLLBACK").catch(() => {});
  console.error(`Migration annulée, aucune modification conservée : ${(error as Error).message}`);
  process.exitCode = 1;
} finally { await client.end(); }
