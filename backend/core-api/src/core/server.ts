import { loadConfig } from "../config.js";
import { createPool } from "../shared/db.js";
import { createLogger } from "../shared/logger.js";
import { serve } from "../shared/serve.js";
import { createCoreApp } from "./app.js";

const config = loadConfig();
const log = createLogger("core-api");
if (!config.core.databaseUrl) { log.error({}, "CORE_DATABASE_URL est obligatoire (compte pd_core_api)."); process.exit(1); }
const pool = createPool(config.core.databaseUrl, { max: config.poolMax, ssl: config.databaseSsl, application: "core-api", log });
const sitePool = config.core.siteDatabaseUrl ? createPool(config.core.siteDatabaseUrl, { max: 3, ssl: config.databaseSsl, application: "core-api-site", log }) : null;
if (!sitePool) log.warn({}, "SITE_DATABASE_URL absent : les routes /site répondront 503.");

const app = createCoreApp({ config, pool, sitePool, log });
serve(() => app.listen(config.port, "0.0.0.0", () => log.info({ port: config.port }, "API Core démarrée")), log, async () => { await pool.end(); await sitePool?.end(); });
