// Configuration lue une fois au démarrage. Aucun secret n'a de valeur par défaut.

const env = process.env;
const text = (name, fallback = "") => (env[name] ?? fallback).trim();
const int = (name, fallback) => {
  const value = Number.parseInt(env[name] ?? "", 10);
  return Number.isFinite(value) ? value : fallback;
};

export const config = {
  port: int("PORT", 8788),
  databaseUrl: text("DATABASE_URL"),
  databaseSsl: text("DATABASE_SSL"),
  // Origines autorisées à poster le formulaire (séparées par des virgules).
  allowedOrigins: text("ALLOWED_ORIGINS", "https://pro-digital.net,https://www.pro-digital.net")
    .split(",").map((origin) => origin.trim()).filter(Boolean),
  trustProxy: text("TRUST_PROXY", "true") !== "false",

  genesis: {
    url: text("GENESIS_URL", "https://genesis.pro-digital.net").replace(/\/$/, ""),
    serviceToken: text("GENESIS_SERVICE_TOKEN"),
    timeoutMs: int("GENESIS_TIMEOUT_MS", 12000),
  },

  smtp: {
    host: text("SMTP_HOST"),
    port: int("SMTP_PORT", 465),
    // "ssl" (465), "starttls" (587) ou "off" (relais local de test uniquement).
    security: text("SMTP_SECURITY", "ssl"),
    user: text("SMTP_USER"),
    password: text("SMTP_PASSWORD"),
    from: text("SMTP_FROM"),
    to: text("CONTACT_NOTIFY_TO", "contact@pro-digital.net"),
  },

  publicSiteUrl: text("PUBLIC_SITE_URL", "https://pro-digital.net").replace(/\/$/, ""),

  worker: {
    pollMs: int("WORKER_POLL_MS", 15000),
    leaseMs: int("WORKER_LEASE_MS", 120000),
    // Délais entre tentatives ; au-delà, l'opération passe en `failed`
    // (aucune perte : relance manuelle avec `npm run ops -- retry <id>`).
    backoffSeconds: text("WORKER_BACKOFF_SECONDS")
      ? text("WORKER_BACKOFF_SECONDS").split(",").map(Number).filter((n) => n > 0)
      : [30, 120, 600, 1800, 3600, 3 * 3600, 6 * 3600, 12 * 3600],
  },

  rateLimit: {
    windowMs: int("RATE_LIMIT_WINDOW_MS", 10 * 60 * 1000),
    max: int("RATE_LIMIT_MAX", 8),
  },
};

export function missingConfig() {
  const missing = [];
  if (!config.databaseUrl) missing.push("DATABASE_URL");
  if (!config.genesis.serviceToken) missing.push("GENESIS_SERVICE_TOKEN");
  if (!config.smtp.host) missing.push("SMTP_HOST");
  if (!config.smtp.from) missing.push("SMTP_FROM");
  if (config.smtp.security !== "off" && !config.smtp.user) missing.push("SMTP_USER");
  if (config.smtp.security !== "off" && !config.smtp.password) missing.push("SMTP_PASSWORD");
  return missing;
}
