import pg from "pg";
import type { Logger } from "./logger.js";

export type Db = pg.PoolClient;
export type Pool = pg.Pool;
// Les dates sortent en ISO 8601 ; les bigint restent des chaînes exactes.
pg.types.setTypeParser(1184, (v) => new Date(v).toISOString());

export function createPool(url: string, opts: { max?: number; ssl?: string; application: string; log: Logger }): Pool {
  if (!url) throw new Error(`${opts.application} : URL PostgreSQL non configurée`);
  const pool = new pg.Pool({
    connectionString: url, max: opts.max ?? 10, idleTimeoutMillis: 30_000, connectionTimeoutMillis: 5_000,
    statement_timeout: 15_000, query_timeout: 20_000, application_name: opts.application,
    ssl: opts.ssl === "require" ? { rejectUnauthorized: true } : undefined,
  });
  pool.on("error", (error) => opts.log.warn({ error }, "connexion PostgreSQL au repos perdue"));
  return pool;
}

/** Transaction : COMMIT si `fn` aboutit, ROLLBACK sinon. Une connexion dont le ROLLBACK échoue est détruite. */
export async function transaction<T>(pool: Pool, fn: (db: Db) => Promise<T>, readOnly = false): Promise<T> {
  const client = await pool.connect();
  let broken: Error | undefined;
  try {
    await client.query(readOnly ? "BEGIN READ ONLY" : "BEGIN");
    const result = await fn(client);
    await client.query("COMMIT");
    return result;
  } catch (error) {
    await client.query("ROLLBACK").catch((e: Error) => { broken = e; });
    throw error;
  } finally {
    client.release(broken);
  }
}
