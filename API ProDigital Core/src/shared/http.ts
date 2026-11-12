import express, { type ErrorRequestHandler, type Request, type RequestHandler } from "express";
import { createHash, randomUUID, timingSafeEqual } from "node:crypto";
import { ZodError } from "zod";
import { AppError, fromPgError } from "./errors.js";
import type { Logger } from "./logger.js";

declare module "express-serve-static-core" { interface Request { id: string } }

/** Compteurs techniques exposés au format texte Prometheus. */
export class Metrics {
  private counts = new Map<string, number>();
  private seconds = 0;
  private gauges: Array<() => Record<string, number>> = [];
  hit(method: string, status: number, seconds: number) {
    const key = `${method}|${Math.floor(status / 100)}xx`;
    this.counts.set(key, (this.counts.get(key) ?? 0) + 1); this.seconds += seconds;
  }
  inc(name: string, by = 1) { this.counts.set(`#${name}`, (this.counts.get(`#${name}`) ?? 0) + by); }
  gauge(fn: () => Record<string, number>) { this.gauges.push(fn); }
  render(): string {
    const lines: string[] = []; let total = 0;
    for (const [key, n] of this.counts) {
      if (key.startsWith("#")) { lines.push(`${key.slice(1)} ${n}`); continue; }
      const [method, status] = key.split("|"); total += n;
      lines.push(`http_requests_total{method="${method}",status="${status}"} ${n}`);
    }
    lines.push(`http_request_duration_seconds_sum ${this.seconds.toFixed(3)}`, `http_request_duration_seconds_count ${total}`);
    for (const fn of this.gauges) for (const [k, v] of Object.entries(fn())) lines.push(`${k} ${v}`);
    lines.push(`process_resident_memory_bytes ${process.memoryUsage().rss}`, `process_uptime_seconds ${Math.round(process.uptime())}`);
    return lines.join("\n") + "\n";
  }
}

/** Limite par fenêtre fixe, en mémoire (par instance). La clé est hachée : jamais de jeton en clair. */
export function rateLimit(opts: { windowMs: number; max: number; key?: (req: Request) => string }): RequestHandler {
  const hits = new Map<string, { n: number; reset: number }>();
  setInterval(() => { const now = Date.now(); for (const [k, v] of hits) if (v.reset < now) hits.delete(k); }, opts.windowMs).unref();
  return (req, res, next) => {
    const key = createHash("sha256").update(opts.key?.(req) ?? req.ip ?? "?").digest("base64").slice(0, 24);
    const now = Date.now();
    let slot = hits.get(key);
    if (!slot || slot.reset < now) { slot = { n: 0, reset: now + opts.windowMs }; hits.set(key, slot); }
    slot.n += 1;
    res.setHeader("RateLimit-Limit", opts.max); res.setHeader("RateLimit-Remaining", Math.max(0, opts.max - slot.n));
    if (slot.n > opts.max) {
      res.setHeader("Retry-After", Math.ceil((slot.reset - now) / 1000));
      return next(new AppError(429, "rate_limited", "Trop de requêtes."));
    }
    next();
  };
}

export interface AppOptions { log: Logger; metrics: Metrics; trustProxy: boolean; metricsToken: string; ready: () => Promise<unknown>; bodyLimit?: string }

/** Socle commun : corrélation, en-têtes de sécurité, journal d'accès, santé, métriques, JSON borné. */
export function baseApp(o: AppOptions) {
  const app = express();
  app.disable("x-powered-by"); app.set("etag", false); app.set("query parser", "simple");
  if (o.trustProxy) app.set("trust proxy", 1);
  app.use((req, res, next) => {
    const given = req.get("x-request-id");
    req.id = given && /^[A-Za-z0-9._-]{8,64}$/.test(given) ? given : randomUUID();
    res.setHeader("X-Request-Id", req.id); res.setHeader("X-Content-Type-Options", "nosniff");
    res.setHeader("Cache-Control", "no-store"); res.setHeader("Referrer-Policy", "no-referrer");
    res.setHeader("Content-Security-Policy", "default-src 'none'; frame-ancestors 'none'");
    const start = process.hrtime.bigint();
    res.on("finish", () => {
      const seconds = Number(process.hrtime.bigint() - start) / 1e9;
      o.metrics.hit(req.method, res.statusCode, seconds);
      // Chemin sans query string : ni terme de recherche ni jeton dans les journaux.
      o.log.info({ request_id: req.id, method: req.method, path: req.path, status: res.statusCode, ms: Math.round(seconds * 1000) }, "request");
    });
    next();
  });
  app.get("/healthz", (_req, res) => { res.json({ status: "ok" }); });
  app.get("/readyz", async (_req, res) => {
    try { await o.ready(); res.json({ status: "ready" }); } catch { res.status(503).json({ status: "unavailable" }); }
  });
  app.get("/metrics", (req, res, next) => {
    const given = Buffer.from(req.get("authorization") ?? "");
    const expected = Buffer.from(`Bearer ${o.metricsToken}`);
    if (!o.metricsToken || given.length !== expected.length || !timingSafeEqual(given, expected)) return next(new AppError(404, "not_found", "Ressource introuvable."));
    res.type("text/plain").send(o.metrics.render());
  });
  app.use(express.json({ limit: o.bodyLimit ?? "64kb", strict: true }));
  return app;
}

/** 404 + gestion centralisée des erreurs : aucun détail interne ne sort. */
export function finishApp(app: express.Express, log: Logger) {
  app.use((_req, _res, next) => next(new AppError(404, "not_found", "Ressource introuvable.")));
  const handler: ErrorRequestHandler = (error, req, res, _next) => {
    let e: AppError;
    if (error instanceof AppError) e = error;
    else if (error instanceof ZodError) e = new AppError(400, "invalid_request", "Paramètres invalides.", error.issues.map((i) => ({ field: i.path.join("."), message: i.message })));
    else if (error?.type === "entity.too.large") e = new AppError(413, "payload_too_large", "Corps de requête trop volumineux.");
    else if (typeof error?.type === "string" && error.type.startsWith("entity.")) e = new AppError(400, "invalid_json", "Corps JSON invalide.");
    else e = fromPgError(error) ?? new AppError(500, "internal_error", "Erreur interne.");
    if (e.status >= 500) log.error({ request_id: req.id, error }, "request failed");
    if (res.headersSent) { res.end(); return; }
    res.status(e.status).json({ error: { code: e.code, message: e.message, ...(e.details ? { details: e.details } : {}), request_id: req.id } });
  };
  app.use(handler);
  return app;
}
