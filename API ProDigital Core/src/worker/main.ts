import { loadConfig } from "../config.js";
import { createPool } from "../shared/db.js";
import { baseApp, finishApp, Metrics } from "../shared/http.js";
import { createLogger } from "../shared/logger.js";
import { serve } from "../shared/serve.js";
import { Worker } from "./worker.js";

const config = loadConfig();
const log = createLogger("core-worker");
if (!config.worker.databaseUrl) { log.error({}, "WORKER_DATABASE_URL est obligatoire (compte pd_core_worker)."); process.exit(1); }
if (!config.worker.smtp.host || !config.worker.smtp.from) log.warn({}, "SMTP non configuré : les notifications e-mail resteront en attente puis en échec, relançables.");
const pool = createPool(config.worker.databaseUrl, { max: 4, ssl: config.databaseSsl, application: "core-worker", log });
const metrics = new Metrics();
const worker = new Worker(pool, config.worker, log, metrics);
worker.start();

// Port de santé uniquement (healthz, readyz, metrics) : aucune route métier.
const app = finishApp(baseApp({ log, metrics, trustProxy: false, metricsToken: config.metricsToken, ready: () => pool.query("SELECT 1") }), log);
serve(() => app.listen(config.port, "0.0.0.0", () => log.info({ port: config.port }, "Worker Core démarré")), log, async () => { await worker.stop(); await pool.end(); });
