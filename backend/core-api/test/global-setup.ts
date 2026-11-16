// Base PostgreSQL 15 jetable : installation du socle par psql (comme en production), migration par
// le script du projet, puis activation des comptes applicatifs. Les tests n'utilisent ensuite QUE ces comptes.
import { execFileSync } from "node:child_process";
import { randomBytes } from "node:crypto";
import { writeFileSync, rmSync } from "node:fs";
import { fileURLToPath } from "node:url";
import pg from "pg";

const root = fileURLToPath(new URL("..", import.meta.url));
const runtimeFile = fileURLToPath(new URL(".runtime.json", import.meta.url));
const NAME = "pd-core-test-pg", PORT = 55440;
const docker = (...args: string[]) => execFileSync("docker", args, { cwd: root, encoding: "utf8", stdio: ["ignore", "pipe", "pipe"] });
const psql = (...args: string[]) => docker("exec", NAME, "psql", "-U", "postgres", "-d", "prodigital", "-v", "ON_ERROR_STOP=1", "-q", ...args);

export default async function setup() {
  const adminPassword = randomBytes(18).toString("hex");
  try { docker("rm", "-f", NAME); } catch { /* aucun conteneur précédent */ }
  docker("run", "-d", "--name", NAME, "-e", `POSTGRES_PASSWORD=${adminPassword}`, "-e", "POSTGRES_DB=prodigital",
    "-p", `127.0.0.1:${PORT}:5432`, "--tmpfs", "/var/lib/postgresql/data", process.env.TEST_PG_IMAGE ?? "postgres:15-alpine");
  const adminUrl = `postgresql://postgres:${adminPassword}@127.0.0.1:${PORT}/prodigital`;
  for (let i = 0; ; i++) {
    const client = new pg.Client({ connectionString: adminUrl });
    try { await client.connect(); await client.query("SELECT 1"); await client.end(); break; }
    catch (error) { await client.end().catch(() => {}); if (i > 80) throw error; await new Promise((r) => setTimeout(r, 500)); }
  }
  docker("cp", "db/foundation/prodigital-core.sql", `${NAME}:/tmp/prodigital-core.sql`);
  psql("-f", "/tmp/prodigital-core.sql");
  psql("-f", "/tmp/prodigital-core.sql"); // réimport : empreinte vérifiée, rien n'est réinitialisé
  const migrate = (...extra: string[]) => execFileSync(process.execPath, ["--import", "tsx", "src/scripts/migrate.ts", ...extra],
    { cwd: root, encoding: "utf8", env: { ...process.env, MIGRATION_DATABASE_URL: adminUrl } });
  const first = migrate();
  // Procédure de retour arrière : vérifiée à chaque exécution, puis migrations réappliquées.
  for (const file of ["003_function_privileges.sql", "002_core_api_runtime.sql"]) { docker("cp", `db/rollback/${file}`, `${NAME}:/tmp/rollback.sql`); psql("-1", "-f", "/tmp/rollback.sql"); }
  if (!migrate("--dry-run").includes("~ 002_core_api_runtime") || !migrate().includes("+ 003_function_privileges")) throw new Error("Retour arrière ou réapplication en échec");
  const second = migrate();
  if (!first.includes("+ 002_core_api_runtime") || !first.includes("+ 003_function_privileges") || !second.includes("= 003_function_privileges")) throw new Error(`Migration inattendue :\n${first}\n${second}`);

  // Activation des comptes (geste d'administrateur décrit dans le README) : mot de passe propre à chaque rôle.
  const urls: Record<string, string> = {};
  for (const role of ["pd_core_api", "pd_site_api", "pd_iam_admin", "pd_core_worker"]) {
    const password = randomBytes(18).toString("hex");
    psql("-c", `ALTER ROLE ${role} LOGIN PASSWORD '${password}'`);
    urls[role] = `postgresql://${role}:${password}@127.0.0.1:${PORT}/prodigital`;
  }
  writeFileSync(runtimeFile, JSON.stringify(urls));
  return async () => {
    if (process.env.KEEP_TEST_PG) return;
    rmSync(runtimeFile, { force: true });
    try { docker("rm", "-f", NAME); } catch { /* déjà supprimé */ }
  };
}
