import http from "node:http";
import { config } from "./config.js";
import { getPool } from "./db.js";
import { ConflictError, createSubmission } from "./store.js";
import { isValidIdempotencyKey, parseSubmission, ValidationError } from "./submission.js";

const MAX_BODY_BYTES = 32 * 1024;

// Journal JSON sur une ligne, sans données personnelles (seulement des identifiants).
export const log = {
  info: (data, msg) => console.log(JSON.stringify({ level: "info", time: new Date().toISOString(), msg, ...data })),
  warn: (data, msg) => console.warn(JSON.stringify({ level: "warn", time: new Date().toISOString(), msg, ...data })),
  error: (data, msg) => console.error(JSON.stringify({ level: "error", time: new Date().toISOString(), msg, ...data })),
};

function send(res, status, body, headers = {}) {
  res.writeHead(status, {
    "Content-Type": "application/json; charset=utf-8",
    "Cache-Control": "no-store",
    "X-Content-Type-Options": "nosniff",
    ...headers,
  });
  res.end(JSON.stringify(body));
}

function readJson(req) {
  return new Promise((resolve, reject) => {
    const chunks = [];
    let size = 0;
    req.on("data", (chunk) => {
      size += chunk.length;
      if (size > MAX_BODY_BYTES) {
        reject(Object.assign(new Error("too_large"), { status: 413 }));
        req.destroy();
        return;
      }
      chunks.push(chunk);
    });
    req.on("end", () => {
      try {
        resolve(JSON.parse(Buffer.concat(chunks).toString("utf8") || "{}"));
      } catch {
        reject(Object.assign(new Error("invalid_json"), { status: 400 }));
      }
    });
    req.on("error", reject);
  });
}

function clientIp(req) {
  if (config.trustProxy) {
    const forwarded = String(req.headers["x-forwarded-for"] ?? "").split(",")[0].trim();
    if (forwarded) return forwarded;
  }
  return req.socket.remoteAddress ?? "inconnu";
}

// Limitation simple par adresse IP (fenêtre glissante, en mémoire).
const hits = new Map();
function rateLimited(ip) {
  const now = Date.now();
  const recent = (hits.get(ip) ?? []).filter((t) => now - t < config.rateLimit.windowMs);
  recent.push(now);
  hits.set(ip, recent);
  if (hits.size > 5000) for (const [key, list] of hits) if (now - list.at(-1) > config.rateLimit.windowMs) hits.delete(key);
  return recent.length > config.rateLimit.max;
}

function originAllowed(req) {
  const origin = req.headers.origin;
  // Les navigateurs envoient toujours Origin sur un POST fetch ; son absence = client non navigateur (tests, curl).
  return !origin || config.allowedOrigins.includes(origin);
}

async function handleSubmit(req, res, worker) {
  if (!originAllowed(req)) return send(res, 403, { error: "origin", message: "Origine non autorisée." });
  if (!String(req.headers["content-type"] ?? "").startsWith("application/json")) {
    return send(res, 415, { error: "content_type", message: "Format de requête non pris en charge." });
  }
  if (rateLimited(clientIp(req))) {
    return send(res, 429, { error: "rate_limited", message: "Trop d’envois rapprochés. Merci de réessayer dans quelques minutes." }, { "Retry-After": "600" });
  }
  const key = String(req.headers["idempotency-key"] ?? "").trim();
  if (!isValidIdempotencyKey(key)) {
    return send(res, 400, { error: "idempotency_key", message: "Requête invalide : clé d’envoi manquante." });
  }

  const body = await readJson(req);
  // Champ piège invisible pour les humains : rempli = robot.
  if (typeof body.website === "string" && body.website.trim()) {
    log.warn({ ip_hint: "honeypot" }, "Envoi refusé (champ piège rempli)");
    return send(res, 400, { error: "rejected", message: "Votre demande n’a pas pu être prise en compte." });
  }

  const submission = parseSubmission(body);
  const { row, created } = await createSubmission(submission, key);
  log.info({ id: row.id, created }, created ? "Demande enregistrée" : "Demande déjà enregistrée (doublon évité)");
  worker?.kick();
  return send(res, created ? 201 : 200, {
    id: row.id,
    duplicate: !created,
    received_at: row.created_at,
  });
}

export function createApp({ worker } = {}) {
  return http.createServer(async (req, res) => {
    const url = new URL(req.url ?? "/", "http://localhost");
    try {
      if (url.pathname === "/api/health" && req.method === "GET") {
        try {
          await getPool().query("SELECT 1");
          return send(res, 200, { status: "ok" });
        } catch {
          return send(res, 503, { status: "degraded", database: "indisponible" });
        }
      }
      if (url.pathname === "/api/contact-requests") {
        if (req.method !== "POST") return send(res, 405, { error: "method" }, { Allow: "POST" });
        return await handleSubmit(req, res, worker);
      }
      return send(res, 404, { error: "not_found" });
    } catch (error) {
      if (error instanceof ValidationError) {
        return send(res, 400, { error: "validation", message: "Certaines informations sont à vérifier.", errors: error.errors });
      }
      if (error instanceof ConflictError) return send(res, 409, { error: "conflict", message: error.message });
      if (error?.status === 413) return send(res, 413, { error: "too_large", message: "Votre demande est trop volumineuse." });
      if (error?.status === 400) return send(res, 400, { error: "bad_request", message: "Requête invalide." });
      // Base indisponible ou erreur inattendue : rien n'est enregistré, le navigateur le sait.
      log.error({ error: error?.message, code: error?.code }, "Erreur lors du traitement d'une demande");
      return send(res, 503, { error: "unavailable", message: "Le service est momentanément indisponible. Votre demande n’a pas été enregistrée." });
    }
  });
}
