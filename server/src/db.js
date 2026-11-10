import pg from "pg";
import { readdir, readFile } from "node:fs/promises";
import { config } from "./config.js";

let pool;

export function getPool() {
  if (!config.databaseUrl) throw new Error("DATABASE_URL non configuré");
  pool ??= new pg.Pool({
    connectionString: config.databaseUrl,
    max: 5,
    idleTimeoutMillis: 30000,
    connectionTimeoutMillis: 5000,
    ssl: config.databaseSsl === "require" ? { rejectUnauthorized: true } : undefined,
  });
  // Une connexion au repos coupée (redémarrage de la base) ne doit pas arrêter l'API :
  // le pool en rouvre une à la requête suivante.
  pool.on("error", () => {});
  return pool;
}

export async function withTransaction(fn) {
  const client = await getPool().connect();
  try {
    await client.query("BEGIN");
    const result = await fn(client);
    await client.query("COMMIT");
    return result;
  } catch (error) {
    await client.query("ROLLBACK").catch(() => {});
    throw error;
  } finally {
    client.release();
  }
}

/** Applique les fichiers de server/migrations dans l'ordre, une seule fois chacun. */
export async function migrate(log = console.log) {
  const dir = new URL("../migrations/", import.meta.url);
  const files = (await readdir(dir)).filter((name) => name.endsWith(".sql")).sort();
  await withTransaction(async (client) => {
    await client.query("SELECT pg_advisory_xact_lock(hashtext('site.migrations'))");
    await client.query("CREATE SCHEMA IF NOT EXISTS site");
    await client.query(
      "CREATE TABLE IF NOT EXISTS site.schema_migrations (name text PRIMARY KEY, applied_at timestamptz NOT NULL DEFAULT clock_timestamp())",
    );
    const { rows } = await client.query("SELECT name FROM site.schema_migrations");
    const applied = new Set(rows.map((row) => row.name));
    for (const name of files) {
      if (applied.has(name)) continue;
      await client.query(await readFile(new URL(name, dir), "utf8"));
      await client.query("INSERT INTO site.schema_migrations (name) VALUES ($1)", [name]);
      log(`Migration appliquée : ${name}`);
    }
  });
}

export async function closePool() {
  await pool?.end();
  pool = undefined;
}
