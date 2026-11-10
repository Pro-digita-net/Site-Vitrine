import { createApp, log } from "./app.js";
import { config, missingConfig } from "./config.js";
import { closePool, migrate } from "./db.js";
import { startWorker } from "./worker.js";

const missing = missingConfig();
if (missing.includes("DATABASE_URL")) {
  log.error({ missing }, "Configuration incomplète : DATABASE_URL est obligatoire, arrêt.");
  process.exit(1);
}
if (missing.length) {
  // Les demandes restent enregistrées ; les opérations concernées attendront la configuration.
  log.warn({ missing }, "Configuration incomplète : les opérations concernées resteront en attente");
}

if (process.env.MIGRATE_ON_START === "true") await migrate((msg) => log.info({}, msg));

const worker = startWorker(log);
const server = createApp({ worker });
server.listen(config.port, "0.0.0.0", () => log.info({ port: config.port }, "API du formulaire de contact démarrée"));

async function shutdown(signal) {
  log.info({ signal }, "Arrêt en cours");
  server.close();
  await worker.stop();
  await closePool();
  process.exit(0);
}
process.on("SIGTERM", () => void shutdown("SIGTERM"));
process.on("SIGINT", () => void shutdown("SIGINT"));
