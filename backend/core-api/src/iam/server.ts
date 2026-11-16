import { loadConfig } from "../config.js";
import { createPool } from "../shared/db.js";
import { createLogger } from "../shared/logger.js";
import { serve } from "../shared/serve.js";
import { createIamApp } from "./app.js";

const config = loadConfig();
const log = createLogger("core-iam");
if (!config.iam.databaseUrl) { log.error({}, "IAM_DATABASE_URL est obligatoire (compte pd_iam_admin)."); process.exit(1); }
if (!config.iam.oidc.issuer || !config.iam.oidc.audience) log.warn({}, "OIDC_ISSUER / OIDC_AUDIENCE absents : la connexion et l'acceptation d'invitation répondront 503.");
const pool = createPool(config.iam.databaseUrl, { max: 5, ssl: config.databaseSsl, application: "core-iam", log });
const { app } = createIamApp({ config, pool, log });
serve(() => app.listen(config.port, "0.0.0.0", () => log.info({ port: config.port }, "Service IAM démarré")), log, () => pool.end());
