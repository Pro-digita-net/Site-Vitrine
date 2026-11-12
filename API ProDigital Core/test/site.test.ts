// Non-régression du site vitrine : l'API existante du formulaire (dossier ../server, non modifiée) est lancée
// telle quelle sur le socle Core avec le compte pd_site_api ; l'API Core en assure ensuite la lecture et la relance.
import { spawn, type ChildProcess } from "node:child_process";
import { createServer } from "node:net";
import { fileURLToPath } from "node:url";
import { afterAll, beforeAll, describe, expect, it } from "vitest";
import { call, closeAll, pool, SITE_ORG, startStack, twoOrganizations, urls, type Stack } from "./helpers.js";
import type { Pool } from "../src/shared/db.js";

let s: Stack, site: Pool, child: ChildProcess, siteApi: string, staff: string, viewer: string, outsider: string;
const freePort = () => new Promise<number>((resolve) => { const srv = createServer(); srv.listen(0, "127.0.0.1", () => { const { port } = srv.address() as { port: number }; srv.close(() => resolve(port)); }); });
const form = (suffix: string) => ({ given_name: "Camille", family_name: "Nova", email: `camille.nova+${suffix}@example.com`, company: "Atelier Nova", subject: "Création web",
  message: `Je souhaite un site pour présenter mes créations (${suffix}).`, answers: { projectType: "Créer un site vitrine", goal: "Présenter mes créations" }, website: "" });
const submit = (key: string, body: unknown) => call(siteApi, "POST", "/api/contact-requests", { body, headers: { "Idempotency-Key": key, Origin: "https://pro-digital.net" } });
const until = async (check: () => Promise<boolean>, ms = 15_000) => { const end = Date.now() + ms; while (!(await check())) { if (Date.now() > end) throw new Error("délai dépassé"); await new Promise((r) => setTimeout(r, 200)); } };

beforeAll(async () => {
  s = await startStack(); site = pool("pd_site_api", 2);
  const orgs = await twoOrganizations(s);
  staff = (await s.member("prodigital", "admin", "equipe")).token; viewer = (await s.member("prodigital", "viewer", "lecteur")).token;
  outsider = (await s.member(orgs.a, "owner")).token;
  const port = await freePort();
  // Ni SMTP ni jeton Genesis : les opérations doivent rester tracées et relançables, jamais perdues.
  child = spawn(process.execPath, ["src/index.js"], { cwd: fileURLToPath(new URL("../../server", import.meta.url)), stdio: "ignore",
    env: { PATH: process.env.PATH, SystemRoot: process.env.SystemRoot, DATABASE_URL: urls.pd_site_api, PORT: String(port), WORKER_POLL_MS: "300", WORKER_BACKOFF_SECONDS: "1", RATE_LIMIT_MAX: "100" } as NodeJS.ProcessEnv });
  siteApi = `http://127.0.0.1:${port}`;
  await until(async () => (await fetch(`${siteApi}/api/health`).then((r) => r.ok, () => false)));
});
afterAll(async () => { child?.kill(); await closeAll(); });

describe("formulaire du site sur le socle Core (compte pd_site_api)", () => {
  let id: string;
  it("enregistre la demande une seule fois, rattachée à ProDigital, avec ses deux opérations", async () => {
    const key = `site-${s.run}-0001`, body = form(s.run);
    const [first, second] = await Promise.all([submit(key, body), submit(key, body)]);
    expect([200, 201]).toContain(first.status); expect([200, 201]).toContain(second.status);
    id = first.body.id; expect(id).toMatch(/^[0-9a-f-]{36}$/); expect(second.body.id).toBe(id);
    expect((await submit(key, { ...body, message: "Un autre contenu avec la même clé d'envoi." })).status).toBe(409);
    expect((await submit(`site-${s.run}-0002`, body)).body.id).toBe(id); // doublon naturel sur 24 h
    const rows = (await site.query("SELECT organization_id, subject_group, jsonb_array_length(details) AS details FROM site.contact_submissions WHERE email = $1", [body.email])).rows;
    expect(rows).toEqual([{ organization_id: SITE_ORG, subject_group: "Expertise", details: 2 }]);
    const operations = (await site.query("SELECT kind, organization_id FROM site.contact_operations WHERE submission_id = $1 ORDER BY kind", [id])).rows;
    expect(operations).toEqual([{ kind: "crm", organization_id: SITE_ORG }, { kind: "email", organization_id: SITE_ORG }]);
    expect((await submit(`site-${s.run}-0003`, { ...form("x"), email: "pas-un-email" })).status).toBe(400);
  });
  it("trace les tentatives e-mail et CRM sans perdre la demande quand les services externes manquent", async () => {
    await until(async () => (await site.query("SELECT count(*) AS n FROM site.contact_operations WHERE submission_id = $1 AND status = 'failed'", [id])).rows[0].n === "2");
    const events = (await site.query("SELECT kind, event FROM site.contact_events WHERE submission_id = $1", [id])).rows.map((e) => `${e.kind}:${e.event}`);
    expect(events).toEqual(expect.arrayContaining(["submission:recorded", "submission:duplicate_ignored", "email:retry_scheduled", "email:failed", "crm:failed"]));
    expect((await site.query("SELECT count(*) AS n FROM site.contact_submissions WHERE id = $1", [id])).rows[0].n).toBe("1");
  });
  it("la demande est immuable et non supprimable, même pour le compte du site", async () => {
    for (const sql of ["UPDATE site.contact_submissions SET message = 'réécrit' WHERE id = $1", "DELETE FROM site.contact_submissions WHERE id = $1", "DELETE FROM site.contact_operations WHERE submission_id = $1"])
      expect(await site.query(sql, [id]).then(() => "autorisé", (e) => e.code), sql).toBe("42501");
  });

  it("API Core : lecture réservée aux membres de ProDigital, 404 pour les autres organisations", async () => {
    const list = await call(s.core, "GET", "/site/contact-submissions?limit=100", { token: viewer });
    expect(list.status).toBe(200);
    expect(list.body.data.find((r: any) => r.id === id)).toMatchObject({ subject: "Création web", operations: { email: "failed", crm: "failed" } });
    const detail = (await call(s.core, "GET", `/site/contact-submissions/${id}`, { token: staff })).body.data;
    expect(detail).toMatchObject({ id, given_name: "Camille", company: "Atelier Nova", source: "site_web" });
    expect(detail.operations.map((o: any) => o.kind)).toEqual(["crm", "email"]); expect(detail.events.length).toBeGreaterThanOrEqual(4);
    for (const path of ["/site/contact-submissions", `/site/contact-submissions/${id}`]) {
      expect((await call(s.core, "GET", path, { token: outsider })).status).toBe(404);
      expect((await call(s.core, "GET", path)).status).toBe(401);
    }
    expect((await call(s.core, "POST", `/site/contact-submissions/${id}/retry`, { token: outsider })).status).toBe(404);
    expect((await call(s.core, "GET", "/site/contact-submissions/00000000-0000-4000-8000-0000000000aa", { token: staff })).status).toBe(404);
  });
  it("API Core : relance des opérations en échec, reprise par le worker du site", async () => {
    expect((await call(s.core, "POST", `/site/contact-submissions/${id}/retry`, { token: viewer })).status).toBe(403);
    const retry = await call(s.core, "POST", `/site/contact-submissions/${id}/retry`, { token: staff });
    expect(retry.status).toBe(200); expect(retry.body.data.requeued.sort()).toEqual(["crm", "email"]);
    await until(async () => (await site.query("SELECT count(*) AS n FROM site.contact_events WHERE submission_id = $1 AND event = 'manual_retry'", [id])).rows[0].n === "2");
    await until(async () => (await site.query("SELECT min(attempts) AS n FROM site.contact_operations WHERE submission_id = $1", [id])).rows[0].n >= 2);
    expect((await call(s.core, "GET", `/site/contact-submissions/${id}`, { token: staff })).body.data.message).toContain("présenter mes créations");
  });
});
