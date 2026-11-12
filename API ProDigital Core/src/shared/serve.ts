import type { Server } from "node:http";
import type { Logger } from "./logger.js";

/** Démarrage et arrêt propre : fin des requêtes en cours, puis fermeture des connexions. */
export function serve(listen: () => Server, log: Logger, close: () => Promise<unknown>) {
  const server = listen();
  server.requestTimeout = 30_000; server.headersTimeout = 15_000; server.keepAliveTimeout = 65_000;
  let stopping = false;
  const shutdown = (signal: string) => {
    if (stopping) return; stopping = true;
    log.info({ signal }, "arrêt en cours");
    const force = setTimeout(() => process.exit(1), 15_000); force.unref();
    server.close(() => { void close().catch(() => {}).finally(() => process.exit(0)); });
    server.closeIdleConnections();
  };
  process.on("SIGTERM", () => shutdown("SIGTERM")); process.on("SIGINT", () => shutdown("SIGINT"));
  process.on("unhandledRejection", (error) => log.error({ error }, "rejet non géré"));
  return server;
}
