import { createHmac } from "node:crypto";
import type { IncomingMessage, ServerResponse } from "node:http";
import type { AddressInfo } from "node:net";
import { simpleParser } from "mailparser";
import { SMTPServer } from "smtp-server";
import { afterAll, beforeAll, describe, expect, it } from "vitest";
import type { Config } from "../src/config.js";
import { Worker } from "../src/worker/worker.js";
import { call, closeAll, listen, log, pool, startStack, twoOrganizations, type Stack } from "./helpers.js";
import type { Pool } from "../src/shared/db.js";

let s: Stack, orgA: string, orgB: string, tokenA: string, tokenB: string, db: Pool, cfg: Config["worker"], worker: Worker;
const SIGNING = "signature-de-test-0123456789";
const hooks: Array<{ key: string; event: any; valid: boolean }> = [];
const mails: Array<{ subject: string; to: string; text: string }> = [];
let hookBehaviour: (req: IncomingMessage, res: ServerResponse) => void | Promise<void> = (_req, res) => { res.end(JSON.stringify({ id: "ext-1" })); };
let hookUrl: string, connectionId: string;

const post = async (token: string, subject: string) => (await call(s.core, "POST", "/requests", { token, body: { subject, message: "Message de test pour les workers." } })).body.data.id as string;
const outboxOf = async (requestId: string) => (await db.query("SELECT id, status, attempts, last_error, available_at > clock_timestamp() AS later FROM integration.outbox WHERE payload->>'request_id' = $1", [requestId])).rows[0];
const connect = async (token: string, org: string, provider: string, ref: string, secret: unknown) => {
  const c = (await call(s.core, "POST", "/connections", { token, body: { provider, name: `${provider} ${ref}` } })).body.data;
  await call(s.core, "PATCH", `/connections/${c.id}`, { token, body: { status: "enabled" }, headers: { "If-Match": c.version } });
  process.env[`PD_SECRET_${ref.toUpperCase().replace(/-/g, "_")}`] = JSON.stringify(secret);
  await worker.ops.setSecretReference(org, c.id, ref);
  return c.id as string;
};
const disable = async (token: string, id: string) => {
  const c = (await call(s.core, "GET", `/connections/${id}`, { token })).body.data;
  await call(s.core, "PATCH", `/connections/${id}`, { token, body: { status: "disabled" }, headers: { "If-Match": c.version } });
};
const drainAll = async (w = worker) => { while (await w.drain()) { /* jusqu'à épuisement */ } };

beforeAll(async () => {
  s = await startStack(); const orgs = await twoOrganizations(s); orgA = orgs.orgA; orgB = orgs.orgB;
  tokenA = (await s.member(orgs.a, "owner")).token; tokenB = (await s.member(orgs.b, "owner")).token;
  db = pool("pd_core_worker", 6);
  const hook = await listen(async (req, res) => {
    let body = ""; for await (const chunk of req) body += chunk;
    hooks.push({ key: String(req.headers["idempotency-key"]), event: JSON.parse(body), valid: req.headers["x-prodigital-signature"] === `sha256=${createHmac("sha256", SIGNING).update(body).digest("hex")}` });
    res.setHeader("Content-Type", "application/json"); await hookBehaviour(req, res);
  });
  hookUrl = hook.url;
  const smtp = new SMTPServer({ authOptional: true, disabledCommands: ["STARTTLS"], onData(stream, _session, done) { let raw = ""; stream.on("data", (c) => (raw += c)); stream.on("end", () => { void simpleParser(raw).then((m) => { mails.push({ subject: m.subject ?? "", to: (m.to as { text?: string } | undefined)?.text ?? "", text: m.text ?? "" }); done(); }); }); } });
  await new Promise<void>((r) => smtp.listen(0, "127.0.0.1", r));
  cfg = { ...s.config.worker, databaseUrl: "", batch: 5, leaseMs: 60_000, backoffSeconds: [1], allowInsecureWebhooks: true, webhookTimeoutMs: 3000,
    smtp: { host: "127.0.0.1", port: (smtp.server.address() as AddressInfo).port, security: "off", user: "", password: "", from: "core@example.com" } };
  worker = new Worker(db, cfg, log);
  await drainAll(); // événements laissés par les autres suites (organisations sans connexion)
});
afterAll(closeAll);

describe("outbox → webhook", () => {
  it("livre l'événement signé à la connexion de son organisation, une seule fois", async () => {
    connectionId = await connect(tokenA, orgA, "webhook", `hook-a-${s.run}`, { url: hookUrl, signing_secret: SIGNING });
    const requestId = await post(tokenA, "Événement signé");
    expect(await outboxOf(requestId)).toMatchObject({ status: "pending", attempts: 0 });
    await drainAll();
    const outbox = await outboxOf(requestId);
    expect(outbox).toMatchObject({ status: "succeeded", attempts: 1, last_error: null });
    const delivered = hooks.filter((h) => h.event.data.request_id === requestId);
    expect(delivered).toHaveLength(1);
    expect(delivered[0]).toMatchObject({ valid: true, key: outbox.id, event: { id: outbox.id, type: "web.request.created", organization_id: orgA, data: { subject: "Événement signé", status: "new" } } });
    expect(delivered[0]!.event.data.message).toBeUndefined(); // le message du demandeur ne quitte pas la base
    await drainAll();
    expect(hooks.filter((h) => h.event.data.request_id === requestId)).toHaveLength(1);
    const ref = (await db.query("SELECT external_id, entity_type FROM integration.external_references WHERE organization_id = $1 AND local_id = $2", [orgA, requestId])).rows;
    expect(ref).toEqual([{ external_id: "ext-1", entity_type: "web.request" }]);
  });
  it("les événements de B ne sont jamais envoyés à la connexion de A", async () => {
    const requestB = await post(tokenB, "Privé B");
    await drainAll();
    expect((await outboxOf(requestB)).status).toBe("succeeded");
    expect(hooks.some((h) => h.event.organization_id === orgB || h.event.data.request_id === requestB)).toBe(false);
  });
  it("échec distant : nouvelle tentative différée, puis abandon, puis relance manuelle — sans fuite de secret", async () => {
    hookBehaviour = (_req, res) => { res.statusCode = 500; res.end("{}"); };
    const requestId = await post(tokenA, "Destinataire en panne");
    await drainAll();
    let outbox = await outboxOf(requestId);
    expect(outbox).toMatchObject({ status: "pending", attempts: 1, last_error: "Webhook refusé (HTTP 500)", later: true });
    expect(await worker.drain()).toBe(0); // pas avant l'échéance
    await new Promise((r) => setTimeout(r, 1200));
    await drainAll();
    outbox = await outboxOf(requestId);
    expect(outbox).toMatchObject({ status: "failed", attempts: 2 });
    expect(outbox.last_error).not.toContain(hookUrl); expect(outbox.last_error).not.toContain(SIGNING);
    hookBehaviour = (_req, res) => { res.end("{}"); };
    await drainAll();
    expect((await outboxOf(requestId)).status).toBe("failed"); // un échec définitif n'est pas repris seul
    expect(await worker.ops.retry("outbox", outbox.id)).toBe(1);
    await drainAll();
    expect(await outboxOf(requestId)).toMatchObject({ status: "succeeded", attempts: 3, last_error: null });
  });
  it("deux workers concurrents : chaque événement est traité une seule fois", async () => {
    const ids = await Promise.all(Array.from({ length: 14 }, (_, i) => post(tokenA, `Concurrence ${i}`)));
    const second = new Worker(pool("pd_core_worker", 4), cfg, log);
    await Promise.all([drainAll(), drainAll(second), drainAll(), drainAll(second)]);
    const delivered = hooks.filter((h) => ids.includes(h.event.data.request_id));
    expect(delivered).toHaveLength(14); expect(new Set(delivered.map((h) => h.key)).size).toBe(14);
    const states = (await db.query("SELECT status, attempts FROM integration.outbox WHERE payload->>'request_id' = ANY($1)", [ids])).rows;
    expect(states.every((r) => r.status === "succeeded" && r.attempts === 1)).toBe(true);
  });
  it("bail expiré (worker arrêté en plein traitement) : repris par un autre, clôture protégée", async () => {
    let release!: () => void; const gate = new Promise<void>((r) => (release = r));
    let calls = 0;
    hookBehaviour = async (_req, res) => { if (++calls === 1) await gate; res.end("{}"); };
    const requestId = await post(tokenA, "Bail expiré");
    const slow = new Worker(pool("pd_core_worker", 2), { ...cfg, leaseMs: 200 }, log);
    const stuck = slow.drainOutbox();
    await new Promise((r) => setTimeout(r, 500));
    await drainAll(); // un second worker reprend l'événement dont le bail a expiré
    expect(await outboxOf(requestId)).toMatchObject({ status: "succeeded", attempts: 2 });
    release(); await stuck; // le premier termine en retard : sa clôture (tentative 1) est ignorée
    expect(await outboxOf(requestId)).toMatchObject({ status: "succeeded", attempts: 2 });
    const delivered = hooks.filter((h) => h.event.data.request_id === requestId);
    expect(new Set(delivered.map((h) => h.key)).size).toBe(1); // même Idempotency-Key : le destinataire déduplique
    hookBehaviour = (_req, res) => { res.end("{}"); };
  });
  it("connexion sans secret ou secret invalide : en attente avec un motif clair, jamais d'envoi en clair", async () => {
    await disable(tokenA, connectionId);
    const orphan = (await call(s.core, "POST", "/connections", { token: tokenA, body: { provider: "webhook", name: "sans secret" } })).body.data;
    await call(s.core, "PATCH", `/connections/${orphan.id}`, { token: tokenA, body: { status: "enabled" }, headers: { "If-Match": orphan.version } });
    const first = await post(tokenA, "Sans secret");
    await drainAll();
    expect(await outboxOf(first)).toMatchObject({ status: "pending", last_error: "Connexion activée sans secret enregistré" });
    process.env[`PD_SECRET_HTTP_${s.run.toUpperCase()}`] = JSON.stringify({ url: "ftp://exemple.invalid/x", signing_secret: SIGNING });
    await worker.ops.setSecretReference(orgA, orphan.id, `http-${s.run}`);
    await db.query("UPDATE integration.outbox SET available_at = clock_timestamp() WHERE id = $1", [(await outboxOf(first)).id]);
    await drainAll();
    expect((await outboxOf(first)).last_error).toBe("Le webhook doit utiliser HTTPS");
    await disable(tokenA, orphan.id);
  });
});

describe("outbox → notification e-mail", () => {
  it("crée une notification par destinataire, l'envoie par SMTP, sans doublon", async () => {
    const emailConnection = await connect(tokenA, orgA, "email", `mail-a-${s.run}`, { to: "equipe@example.com" });
    const requestId = await post(tokenA, "Notification e-mail");
    await drainAll();
    const rows = (await db.query("SELECT status, attempts, recipient, delivered_at IS NOT NULL AS sent FROM notifications.deliveries WHERE organization_id = $1 AND payload->>'request_id' = $2", [orgA, requestId])).rows;
    expect(rows).toEqual([{ status: "succeeded", attempts: 1, recipient: "equipe@example.com", sent: true }]);
    const mail = mails.filter((m) => m.text.includes(requestId));
    expect(mail).toHaveLength(1); expect(mail[0]).toMatchObject({ subject: "Nouvelle demande : Notification e-mail", to: "equipe@example.com" });
    expect(mail[0]!.text).not.toContain("Message de test pour les workers");
    await drainAll();
    expect(mails.filter((m) => m.text.includes(requestId))).toHaveLength(1);
    await disable(tokenA, emailConnection);
  });
  it("messagerie non configurée : la notification attend puis échoue avec un motif explicite, et reste relançable", async () => {
    const offline = new Worker(pool("pd_core_worker", 2), { ...cfg, smtp: { ...cfg.smtp, host: "" } }, log);
    const emailConnection = await connect(tokenA, orgA, "email", `mail-b-${s.run}`, { to: "equipe@example.com" });
    const requestId = await post(tokenA, "Sans SMTP");
    await drainAll(offline);
    const state = async () => (await db.query("SELECT id, status, attempts, last_error FROM notifications.deliveries WHERE organization_id = $1 AND payload->>'request_id' = $2", [orgA, requestId])).rows[0];
    expect(await state()).toMatchObject({ status: "pending", attempts: 1, last_error: "Messagerie non configurée (SMTP_HOST, SMTP_FROM)" });
    await new Promise((r) => setTimeout(r, 1200));
    await drainAll(offline);
    const failed = await state();
    expect(failed).toMatchObject({ status: "failed", attempts: 2 });
    expect(await worker.ops.retry("deliveries", failed.id)).toBe(1);
    await drainAll(); // la messagerie est revenue
    expect(await state()).toMatchObject({ status: "succeeded", attempts: 3 });
    expect(mails.filter((m) => m.text.includes(requestId))).toHaveLength(1);
    await disable(tokenA, emailConnection);
  });
});
