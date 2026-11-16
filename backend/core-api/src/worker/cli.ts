// Exploitation des files, à lancer dans le conteneur core-worker : node dist/worker/cli.js <commande>
import { parseArgs } from "node:util";
import { z } from "zod";
import { loadConfig } from "../config.js";
import { createPool } from "../shared/db.js";
import { createLogger } from "../shared/logger.js";
import { VAULT_REFERENCE } from "./adapters.js";
import { Worker } from "./worker.js";

const USAGE = `Commandes :
  outbox:list      [--status pending|running|succeeded|failed]
  outbox:retry     --id <uuid>          (remet en file un événement en échec)
  deliveries:list  [--status ...]
  deliveries:retry --id <uuid>
  secret:set       --org <uuid> --connection <uuid> --ref <référence du coffre>
  drain                                  (un cycle de traitement immédiat)`;

const { positionals, values } = parseArgs({ allowPositionals: true, options: { status: { type: "string" }, id: { type: "string" }, org: { type: "string" }, connection: { type: "string" }, ref: { type: "string" } } });
const need = <T>(name: keyof typeof values, schema: z.ZodType<T>): T => {
  const parsed = schema.safeParse(values[name]);
  if (!parsed.success) { console.error(`Option --${name} absente ou invalide.\n\n${USAGE}`); process.exit(2); }
  return parsed.data;
};
const status = z.enum(["pending", "running", "succeeded", "failed"]).optional();

const config = loadConfig();
if (!config.worker.databaseUrl) { console.error("WORKER_DATABASE_URL est obligatoire (compte pd_core_worker)."); process.exit(1); }
const log = createLogger("core-worker-cli");
const pool = createPool(config.worker.databaseUrl, { max: 2, ssl: config.databaseSsl, application: "core-worker-cli", log });
const worker = new Worker(pool, config.worker, log);

const commands: Record<string, () => Promise<unknown>> = {
  "outbox:list": () => worker.ops.list("outbox", need("status", status)),
  "outbox:retry": async () => ({ requeued: await worker.ops.retry("outbox", need("id", z.uuid())) }),
  "deliveries:list": () => worker.ops.list("deliveries", need("status", status)),
  "deliveries:retry": async () => ({ requeued: await worker.ops.retry("deliveries", need("id", z.uuid())) }),
  "secret:set": async () => ({ saved: await worker.ops.setSecretReference(need("org", z.uuid()), need("connection", z.uuid()), need("ref", z.string().regex(VAULT_REFERENCE))) }),
  drain: async () => ({ processed: await worker.drain() }),
};
const command = commands[positionals[0] ?? ""];
if (!command) { console.log(USAGE); process.exit(positionals[0] ? 2 : 0); }
try { console.log(JSON.stringify(await command(), null, 2)); }
catch (error) { console.error(`Échec : ${(error as Error).message}`); process.exitCode = 1; }
finally { await pool.end(); }
