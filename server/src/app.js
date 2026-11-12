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

const clip = (value, max = 120) => String(value ?? "").replace(/[\r\n\u0000]+/g, " ").trim().slice(0, max);

/** Nomme la cause d'un échec d'enregistrement, sans hôte, mot de passe ni valeur saisie. */
export function explainStorageFailure(error) {
  const code = String(error?.code ?? "");
  const constraint = typeof error?.constraint === "string" ? error.constraint : "";
  const column = typeof error?.column === "string" ? error.column : "";
  const where = constraint ? ` (contrainte ${constraint})` : column ? ` (colonne ${column})` : "";
  const tail = " Votre demande n’a pas été enregistrée.";
  if (/DATABASE_URL/i.test(String(error?.message ?? ""))) {
    return `La variable DATABASE_URL est absente : la base n’a pas pu être contactée.${tail}`;
  }
  if (["ECONNREFUSED", "ENOTFOUND", "EAI_AGAIN", "EHOSTUNREACH", "ETIMEDOUT", "ECONNRESET"].includes(code)) {
    return `La base de données est injoignable (code ${code}).${tail}`;
  }
  const network = {
    "57P01": "Le serveur de base est en cours d’arrêt",
    "57P02": "Le serveur de base a coupé la session",
    "57P03": "Le serveur de base est en cours de démarrage",
    "08001": "La connexion à la base a été refusée",
    "08003": "La connexion à la base est déjà fermée",
    "08004": "La base a rejeté la connexion",
    "08006": "La connexion à la base a échoué",
    "53300": "La base n’accepte plus de connexions",
    "28P01": "L’identifiant de connexion à la base a été refusé",
    "28000": "L’autorisation de connexion à la base a été refusée",
    "3D000": "La base de données configurée n’existe pas",
  };
  if (network[code]) return `${network[code]} (code ${code}).${tail}`;
  if (code === "42P01") return `Table absente${error?.table ? ` : ${error.table}` : ""}. Le service de contact n’est pas initialisé.${tail}`;
  if (code === "3F000") return `Schéma absent${error?.schema ? ` : ${error.schema}` : ""}. Le service de contact n’est pas initialisé.${tail}`;
  if (code === "42703") return `Colonne absente en base${column ? ` : ${column}` : ""}. Le schéma du service de contact est en retard.${tail}`;
  if (code === "42501") return `Le service de contact n’a pas le droit d’écrire la demande (code 42501).${tail}`;
  if (code === "23505") return `Doublon refusé par la base${where}.${tail}`;
  if (code === "23503") return `Référence inconnue refusée par la base${where}.${tail}`;
  if (code === "23502") return `Champ obligatoire absent en base${where}.${tail}`;
  if (code === "23514") return `Règle de la base non respectée${where}.${tail}`;
  if (code === "22001") return `Une valeur dépasse la longueur autorisée en base${where}.${tail}`;
  if (code === "22P02") return `Une valeur a un format refusé par la base (code 22P02).${tail}`;
  if (code.startsWith("23") || code.startsWith("22")) return `La base a refusé les données (code ${code})${where}.${tail}`;
  const name = code || error?.name || "sans code";
  return `Erreur inattendue pendant l’enregistrement (${name}).${tail}`;
}

export function validationSummary(errors) {
  if (errors.length === 1) return errors[0].message;
  const list = errors.map((item) => item.message.replace(/\.$/, "")).join(" ; ");
  return `${errors.length} informations empêchent l’envoi : ${list}.`;
}

async function handleSubmit(req, res, worker) {
  if (!originAllowed(req)) {
    const origin = clip(req.headers.origin, 200) || "absente";
    return send(res, 403, { error: "origin", message: `Origine refusée : « ${origin} » n’est pas autorisée à envoyer une demande.` });
  }
  const contentType = String(req.headers["content-type"] ?? "");
  if (!contentType.startsWith("application/json")) {
    const received = clip(contentType, 80);
    return send(res, 415, {
      error: "content_type",
      message: received
        ? `Format refusé : Content-Type « ${received} ». Seul application/json est accepté.`
        : "Format refusé : l’en-tête Content-Type est absent. application/json est requis.",
    });
  }
  if (rateLimited(clientIp(req))) {
    const minutes = Math.max(1, Math.round(config.rateLimit.windowMs / 60000));
    return send(res, 429, {
      error: "rate_limited",
      message: `Trop d’envois depuis cette adresse : ${config.rateLimit.max} demandes maximum en ${minutes} minutes.`,
    }, { "Retry-After": "600" });
  }
  const rawKey = req.headers["idempotency-key"];
  const key = String(rawKey ?? "").trim();
  if (!isValidIdempotencyKey(key)) {
    const message = rawKey === undefined || key === ""
      ? "En-tête Idempotency-Key absent : chaque envoi doit porter une clé de 8 à 128 caractères."
      : `En-tête Idempotency-Key refusé (« ${clip(key, 40)} ») : 8 à 128 caractères parmi lettres, chiffres, point, tiret, underscore et deux-points.`;
    return send(res, 400, { error: "idempotency_key", message });
  }

  const body = await readJson(req);
  // Champ piège invisible pour les humains : rempli = robot.
  if (typeof body.website === "string" && body.website.trim()) {
    log.warn({ ip_hint: "honeypot" }, "Envoi refusé (champ piège rempli)");
    return send(res, 400, { error: "honeypot", message: "Envoi refusé : le champ anti-robot « website » contenait du texte. Laissez-le vide." });
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
        if (req.method !== "POST") {
          return send(res, 405, {
            error: "method",
            message: `Méthode ${req.method || "inconnue"} refusée sur /api/contact-requests : seul POST est accepté.`,
          }, { Allow: "POST" });
        }
        return await handleSubmit(req, res, worker);
      }
      return send(res, 404, {
        error: "not_found",
        message: `Adresse introuvable : ${req.method || "requête"} ${clip(url.pathname, 160)} ne correspond à aucune route du service de contact.`,
      });
    } catch (error) {
      if (error instanceof ValidationError) {
        return send(res, 400, { error: "validation", message: validationSummary(error.errors), errors: error.errors });
      }
      if (error instanceof ConflictError) return send(res, 409, { error: "conflict", message: error.message });
      if (error?.status === 413) {
        return send(res, 413, { error: "too_large", message: `La demande dépasse ${MAX_BODY_BYTES / 1024} Ko et a été refusée avant l’enregistrement.` });
      }
      if (error?.status === 400) {
        return send(res, 400, { error: "invalid_json", message: "Le corps envoyé n’est pas un JSON valide. La demande n’a pas été enregistrée." });
      }
      const code = String(error?.code ?? "");
      if (["ECONNRESET", "EPIPE", "ECONNABORTED"].includes(code)) {
        return send(res, 400, { error: "incomplete", message: `La connexion a été coupée pendant l’envoi (code ${code}). La demande n’a pas été enregistrée.` });
      }
      // Base indisponible ou erreur inattendue : rien n'est enregistré, le navigateur sait pourquoi.
      log.error({ error: error?.message, code: error?.code }, "Erreur lors du traitement d'une demande");
      return send(res, 503, { error: "unavailable", message: explainStorageFailure(error) });
    }
  });
}
