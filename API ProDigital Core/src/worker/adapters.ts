import { createHmac } from "node:crypto";
import { readFile } from "node:fs/promises";
import path from "node:path";
import nodemailer from "nodemailer";
import type { Config } from "../config.js";

type WorkerConfig = Config["worker"];
export const VAULT_REFERENCE = /^[a-z0-9][a-z0-9_-]{0,62}$/;

/** Erreur dont le message peut être conservé en base : jamais d'URL, de secret ni de réponse distante. */
export class DeliveryError extends Error {}

/**
 * Coffre : la base ne contient qu'une référence. Le secret est lu dans un fichier monté
 * (secrets Docker/Coolify, SECRETS_DIR/<référence>) ou, à défaut, dans PD_SECRET_<RÉFÉRENCE>.
 */
export async function resolveSecret(cfg: WorkerConfig, reference: string): Promise<Record<string, unknown>> {
  if (!VAULT_REFERENCE.test(reference)) throw new DeliveryError("Référence de secret invalide");
  let raw = process.env[`PD_SECRET_${reference.toUpperCase().replace(/-/g, "_")}`];
  if (!raw) try { raw = await readFile(path.join(cfg.secretsDir, reference), "utf8"); } catch { /* absent */ }
  if (!raw) throw new DeliveryError("Secret absent du coffre pour cette connexion");
  try {
    const value: unknown = JSON.parse(raw);
    if (value && typeof value === "object" && !Array.isArray(value)) return value as Record<string, unknown>;
  } catch { /* format invalide */ }
  throw new DeliveryError("Secret illisible : objet JSON attendu");
}

/** Webhook signé (HMAC-SHA256 du corps). Le destinataire déduplique avec Idempotency-Key. */
export async function sendWebhook(cfg: WorkerConfig, secret: Record<string, unknown>, event: { id: string; type: string; organization_id: string; data: unknown }): Promise<string | null> {
  const { url, signing_secret: key } = secret;
  if (typeof url !== "string" || typeof key !== "string" || key.length < 16) throw new DeliveryError("Secret de webhook incomplet (url, signing_secret ≥ 16 caractères)");
  let target: URL;
  try { target = new URL(url); } catch { throw new DeliveryError("URL de webhook invalide"); }
  if (target.protocol !== "https:" && !(cfg.allowInsecureWebhooks && target.protocol === "http:")) throw new DeliveryError("Le webhook doit utiliser HTTPS");
  const body = JSON.stringify(event);
  let response: Response;
  try {
    response = await fetch(target, { method: "POST", body, redirect: "error", signal: AbortSignal.timeout(cfg.webhookTimeoutMs), headers: {
      "Content-Type": "application/json", "User-Agent": "ProDigital-Core/1", "Idempotency-Key": event.id, "X-ProDigital-Event": event.type,
      "X-ProDigital-Signature": `sha256=${createHmac("sha256", key).update(body).digest("hex")}` } });
  } catch (error) { throw new DeliveryError(`Webhook injoignable (${(error as Error).name})`); }
  if (!response.ok) throw new DeliveryError(`Webhook refusé (HTTP ${response.status})`);
  try {
    const reply = (await response.json()) as { id?: unknown };
    return typeof reply?.id === "string" && reply.id.length <= 200 ? reply.id : null;
  } catch { return null; }
}

export const EMAIL_TEMPLATES: Record<string, (payload: Record<string, unknown>) => { subject: string; text: string }> = {
  web_request_created: (p) => ({
    subject: `Nouvelle demande : ${String(p.subject ?? "").replace(/[\r\n]+/g, " ").slice(0, 150)}`,
    text: `Une nouvelle demande a été enregistrée dans ProDigital Core.\n\nSujet : ${String(p.subject ?? "")}\nRéférence : ${String(p.request_id ?? "")}\n\nLe détail est consultable dans votre espace.`,
  }),
};

export function createMailer(cfg: WorkerConfig) {
  const { smtp } = cfg;
  const transport = smtp.host && smtp.from ? nodemailer.createTransport({
    host: smtp.host, port: smtp.port, secure: smtp.security === "ssl", requireTLS: smtp.security === "starttls", ignoreTLS: smtp.security === "off",
    auth: smtp.user ? { user: smtp.user, pass: smtp.password } : undefined, connectionTimeout: 10_000, socketTimeout: 20_000,
  }) : null;
  return async (to: string, template: string, payload: Record<string, unknown>): Promise<void> => {
    const render = EMAIL_TEMPLATES[template];
    if (!render) throw new DeliveryError("Modèle de notification inconnu");
    if (!transport) throw new DeliveryError("Messagerie non configurée (SMTP_HOST, SMTP_FROM)");
    try { await transport.sendMail({ from: smtp.from, to, ...render(payload) }); }
    catch (error) { throw new DeliveryError(`Envoi SMTP refusé (${(error as { code?: string }).code ?? (error as Error).name})`); }
  };
}
