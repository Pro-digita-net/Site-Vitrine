// Configuration par environnement. Aucun secret n'a de valeur par défaut.
const text = (name: string, fallback = "") => (process.env[name] ?? fallback).trim();
const int = (name: string, fallback: number) => { const n = Number.parseInt(process.env[name] ?? "", 10); return Number.isFinite(n) ? n : fallback; };

export const loadConfig = () => ({
  port: int("PORT", 8080),
  trustProxy: text("TRUST_PROXY", "true") !== "false",
  databaseSsl: text("DATABASE_SSL"),
  poolMax: int("DATABASE_POOL_MAX", 10),
  metricsToken: text("METRICS_TOKEN"),
  rateLimit: { windowMs: int("RATE_LIMIT_WINDOW_MS", 60_000), max: int("RATE_LIMIT_MAX", 300), authMax: int("RATE_LIMIT_AUTH_MAX", 20) },
  core: { databaseUrl: text("CORE_DATABASE_URL"), siteDatabaseUrl: text("SITE_DATABASE_URL") },
  iam: {
    databaseUrl: text("IAM_DATABASE_URL"),
    oidc: { issuer: text("OIDC_ISSUER"), audience: text("OIDC_AUDIENCE"), jwksUri: text("OIDC_JWKS_URI") },
    sessionTtlHours: int("SESSION_TTL_HOURS", 12), invitationTtlHours: int("INVITATION_TTL_HOURS", 72), apiKeyMaxDays: int("API_KEY_MAX_DAYS", 365),
  },
  worker: {
    databaseUrl: text("WORKER_DATABASE_URL"), pollMs: int("WORKER_POLL_MS", 5000), leaseMs: int("WORKER_LEASE_MS", 120_000), batch: int("WORKER_BATCH", 10),
    backoffSeconds: text("WORKER_BACKOFF_SECONDS", "30,120,600,1800,3600,10800").split(",").map(Number).filter((n) => n > 0),
    secretsDir: text("SECRETS_DIR", "/run/secrets"), allowInsecureWebhooks: text("ALLOW_INSECURE_WEBHOOKS") === "true", webhookTimeoutMs: int("WEBHOOK_TIMEOUT_MS", 10_000),
    smtp: { host: text("SMTP_HOST"), port: int("SMTP_PORT", 465), security: text("SMTP_SECURITY", "ssl"), user: text("SMTP_USER"), password: text("SMTP_PASSWORD"), from: text("SMTP_FROM") },
  },
});
export type Config = ReturnType<typeof loadConfig>;
