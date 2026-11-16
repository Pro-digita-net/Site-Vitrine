import { afterAll, beforeAll, describe, expect, it } from "vitest";
import { contextRunner } from "../src/core/context.js";
import { call, closeAll, pool, startStack, twoOrganizations, type Reply, type Stack } from "./helpers.js";

let s: Stack, api: (method: string, path: string, opts?: Parameters<typeof call>[3]) => Promise<Reply>;
let orgA: string, orgB: string;
let ownerA: Awaited<ReturnType<Stack["member"]>>, editorA: typeof ownerA, viewerA: typeof ownerA, ownerB: typeof ownerA;
const created = async (path: string, token: string, body: unknown) => {
  const r = await api("POST", path, { token, body });
  expect(r.status, JSON.stringify(r.body)).toBe(201);
  return r.body.data;
};

beforeAll(async () => {
  s = await startStack(); api = (m, p, o) => call(s.core, m, p, o);
  const orgs = await twoOrganizations(s); orgA = orgs.orgA; orgB = orgs.orgB;
  ownerA = await s.member(orgs.a, "owner"); editorA = await s.member(orgs.a, "editor"); viewerA = await s.member(orgs.a, "viewer");
  ownerB = await s.member(orgs.b, "owner");
});
afterAll(closeAll);

describe("exploitation", () => {
  it("santé, disponibilité, OpenAPI et métriques protégées", async () => {
    const root = s.core.replace("/api/v1", "");
    expect((await call(root, "GET", "/healthz")).body).toEqual({ status: "ok" });
    expect((await call(root, "GET", "/readyz")).status).toBe(200);
    const doc = (await api("GET", "/openapi.json")).body;
    expect(doc.openapi).toBe("3.0.3");
    expect(Object.keys(doc.paths)).toEqual(expect.arrayContaining(["/companies", "/companies/{id}/archive", "/audit-events", "/site/contact-submissions"]));
    expect(doc.paths["/companies/{id}"].delete).toBeUndefined();
    expect((await call(root, "GET", "/metrics")).status).toBe(404);
    const metrics = await call(root, "GET", "/metrics", { headers: { Authorization: `Bearer ${"m".repeat(40)}` } });
    expect(metrics.status).toBe(200); expect(metrics.body).toContain("http_requests_total"); expect(metrics.body).toContain("pg_pool_total");
  });
  it("erreurs au format commun, avec identifiant de corrélation", async () => {
    const r = await api("GET", "/companies", { headers: { "X-Request-Id": "trace-12345678" } });
    expect(r.status).toBe(401);
    expect(r.body).toEqual({ error: { code: "unauthorized", message: expect.any(String), request_id: "trace-12345678" } });
    expect(r.headers.get("x-request-id")).toBe("trace-12345678");
    expect((await api("GET", "/inconnu", { token: ownerA.token })).body.error.code).toBe("not_found");
    expect((await api("POST", "/companies", { token: ownerA.token, raw: "{oops" })).body.error.code).toBe("invalid_json");
    expect((await api("POST", "/companies", { token: ownerA.token, body: { name: "x".repeat(70_000) } })).status).toBe(413);
  });
  it("limitation de débit : 429 avec Retry-After", async () => {
    const limited = await startStack({ max: 5 });
    const statuses = [];
    for (let i = 0; i < 7; i++) statuses.push((await call(limited.core, "GET", "/me", { token: ownerA.token })).status);
    expect(statuses).toEqual([200, 200, 200, 200, 200, 429, 429]);
    expect(Number((await call(limited.core, "GET", "/me", { token: ownerA.token })).headers.get("retry-after"))).toBeGreaterThan(0);
  });
});

describe("authentification", () => {
  it("refuse l'absence de jeton, un jeton malformé ou inconnu", async () => {
    const attempts: Array<Record<string, string>> = [{}, { Authorization: "Bearer court" }, { Authorization: "Basic abc" }, { Authorization: `Bearer ${"A".repeat(43)}` }, { Authorization: `Bearer ${ownerA.token}' OR '1'='1` }];
    for (const headers of attempts)
      expect((await api("GET", "/me", { headers })).status).toBe(401);
  });
  it("le contexte vient du jeton : utilisateur, organisation, permissions effectives", async () => {
    const owner = (await api("GET", "/me", { token: ownerA.token })).body.data;
    expect(owner).toMatchObject({ user_id: ownerA.userId, organization_id: orgA });
    expect(owner.permissions).toHaveLength(11);
    const viewer = (await api("GET", "/me", { token: viewerA.token })).body.data;
    expect(viewer.permissions).toEqual(["catalog.read", "directory.read", "documents.read", "requests.read"]);
    expect((await api("GET", "/organization", { token: ownerB.token })).body.data.id).toBe(orgB);
  });
});

describe("annuaire : cycle complet", () => {
  it("crée, lit, recherche, trie, pagine, modifie avec version, archive et restaure", async () => {
    const tag = `Zeta${s.run}`;
    const a = await created("/companies", ownerA.token, { name: `${tag} Alpha`, kind: "customer", email: "Contact@Alpha.Example" });
    const b = await created("/companies", editorA.token, { name: `${tag} Beta` });
    expect(a).toMatchObject({ name: `${tag} Alpha`, kind: "customer", email: "contact@alpha.example", archived_at: null });
    expect(a.organization_id).toBeUndefined(); expect(a.version).toMatch(/^\d+$/); expect(b.kind).toBe("prospect");

    const got = await api("GET", `/companies/${a.id}`, { token: viewerA.token });
    expect(got.body.data).toEqual(a); expect(got.headers.get("etag")).toBe(`"${a.version}"`);

    const page1 = (await api("GET", `/companies?q=${tag}&sort=-name&limit=1`, { token: ownerA.token })).body;
    expect(page1.data.map((c: any) => c.name)).toEqual([`${tag} Beta`]); expect(page1.page).toEqual({ limit: 1, offset: 0, has_more: true });
    const page2 = (await api("GET", `/companies?q=${tag}&sort=-name&limit=1&offset=1`, { token: ownerA.token })).body;
    expect(page2.data[0].id).toBe(a.id); expect(page2.page.has_more).toBe(false);
    expect((await api("GET", `/companies?q=${tag}&kind=customer`, { token: ownerA.token })).body.data).toHaveLength(1);

    expect((await api("PATCH", `/companies/${a.id}`, { token: ownerA.token, body: { phone: "01 02 03 04 05" } })).status).toBe(428);
    const patched = await api("PATCH", `/companies/${a.id}`, { token: ownerA.token, body: { phone: "01 02 03 04 05", website: null }, headers: { "If-Match": `"${a.version}"` } });
    expect(patched.status).toBe(200); expect(patched.body.data.phone).toBe("01 02 03 04 05"); expect(patched.body.data.version).not.toBe(a.version);
    expect((await api("PATCH", `/companies/${a.id}`, { token: ownerA.token, body: { name: "Écrasement" }, headers: { "If-Match": a.version } })).status).toBe(412);
    expect((await api("PATCH", `/companies/${a.id}`, { token: ownerA.token, body: {}, headers: { "If-Match": patched.body.data.version } })).status).toBe(400);

    const archived = await api("POST", `/companies/${a.id}/archive`, { token: ownerA.token });
    expect(archived.body.data.archived_at).not.toBeNull();
    expect((await api("GET", `/companies?q=${tag}`, { token: ownerA.token })).body.data.map((c: any) => c.id)).toEqual([b.id]);
    expect((await api("GET", `/companies?q=${tag}&archived=true`, { token: ownerA.token })).body.data.map((c: any) => c.id)).toEqual([a.id]);
    expect((await api("GET", `/companies?q=${tag}&archived=all`, { token: ownerA.token })).body.data).toHaveLength(2);
    expect((await api("POST", `/companies/${a.id}/restore`, { token: ownerA.token })).body.data.archived_at).toBeNull();
  });

  it("contacts, rattachements, adresses, équipes et membres", async () => {
    const company = await created("/companies", ownerA.token, { name: "Atelier Nova" });
    const contact = await created("/contacts", ownerA.token, { given_name: "Camille", family_name: "Nova", email: "camille.nova@example.com" });
    const link = await created("/company-contacts", ownerA.token, { company_id: company.id, contact_id: contact.id, relationship: "Gérante" });
    expect((await api("GET", `/company-contacts?company_id=${company.id}`, { token: ownerA.token })).body.data[0].id).toBe(link.id);
    const address = await created("/addresses", ownerA.token, { company_id: company.id, line1: "1 rue de la Paix", city: "Paris", country_code: "FR" });
    expect(address.label).toBe("main");
    const team = await created("/teams", ownerA.token, { name: `Support ${s.run}` });
    const member = await created("/team-members", ownerA.token, { team_id: team.id, user_id: editorA.userId });
    expect(member.user_id).toBe(editorA.userId);
    // Un utilisateur d'une autre organisation n'est pas membre : la clé composite refuse.
    expect((await api("POST", "/team-members", { token: ownerA.token, body: { team_id: team.id, user_id: ownerB.userId } })).status).toBe(422);
  });

  it("aucune suppression n'existe, quel que soit le rôle", async () => {
    const company = await created("/companies", ownerA.token, { name: "À conserver" });
    for (const path of [`/companies/${company.id}`, "/companies", `/audit-events/${company.id}`, `/contacts/${company.id}`])
      expect((await api("DELETE", path, { token: ownerA.token })).status).toBe(404);
    expect((await api("PUT", `/companies/${company.id}`, { token: ownerA.token, body: { name: "x" } })).status).toBe(404);
    expect((await api("GET", `/companies/${company.id}`, { token: ownerA.token })).status).toBe(200);
  });
});

describe("validation et injection", () => {
  it("refuse les champs non autorisés (mass assignment)", async () => {
    for (const extra of [{ organization_id: orgB }, { id: "00000000-0000-4000-8000-00000000000a" }, { created_at: "2000-01-01" }, { archived_at: null }, { is_admin: true }])
      expect((await api("POST", "/companies", { token: ownerA.token, body: { name: "Test", ...extra } })).status).toBe(400);
    const company = await created("/companies", ownerA.token, { name: "Stable" });
    const r = await api("PATCH", `/companies/${company.id}`, { token: ownerA.token, body: { organization_id: orgB }, headers: { "If-Match": company.version } });
    expect(r.status).toBe(400); expect(r.body.error.details[0].message).toBeDefined();
    expect((await api("POST", "/files", { token: ownerA.token, body: { name: "a.pdf", media_type: "application/pdf", size_bytes: 1, storage_key: `${orgB}/vol` } })).status).toBe(400);
  });
  it("valide paramètres, identifiants et bornes", async () => {
    for (const path of ["/companies/pas-un-uuid", "/companies?limit=1000", "/companies?limit=abc", "/companies?offset=-1", "/companies?sort=password", "/companies?inconnu=1",
      "/companies?kind=hacker", "/companies?limit=1&limit=2", "/company-contacts?company_id=1%20OR%201=1", `/companies?q=${"x".repeat(101)}`])
      expect((await api("GET", path, { token: ownerA.token })).status, path).toBe(400);
    expect((await api("POST", "/contacts", { token: ownerA.token, body: { given_name: "", family_name: "X" } })).status).toBe(400);
    expect((await api("POST", "/addresses", { token: ownerA.token, body: { line1: "x", city: "y", country_code: "France" } })).status).toBe(400);
  });
  it("neutralise les injections SQL dans la recherche, le tri, les filtres et les valeurs", async () => {
    const before = (await api("GET", "/companies?limit=100&archived=all", { token: ownerA.token })).body.data.length;
    const payloads = ["' OR '1'='1", "'; DROP TABLE core.companies; --", "%' UNION SELECT token_hash::text FROM iam.access_tokens --", "\\", "x') OR organization_id IS NOT NULL --"];
    for (const p of payloads) {
      const r = await api("GET", `/companies?q=${encodeURIComponent(p)}`, { token: ownerA.token });
      expect(r.status).toBe(200); expect(r.body.data).toEqual([]);
    }
    for (const sort of ["name;DROP TABLE core.companies", "name DESC,(SELECT 1)", "(select pg_sleep(5))"])
      expect((await api("GET", `/companies?sort=${encodeURIComponent(sort)}`, { token: ownerA.token })).status).toBe(400);
    const evil = "Robert'); DROP TABLE core.companies;--";
    const stored = await created("/companies", ownerA.token, { name: evil });
    expect((await api("GET", `/companies/${stored.id}`, { token: ownerA.token })).body.data.name).toBe(evil);
    // Les jokers LIKE sont des caractères ordinaires : « % » ne ramène pas tout.
    await created("/companies", ownerA.token, { name: `100% bio ${s.run}` });
    const wild = (await api("GET", "/companies?q=%25&limit=100", { token: ownerA.token })).body.data;
    expect(wild.length).toBeGreaterThan(0); expect(wild.every((c: any) => c.name.includes("%"))).toBe(true);
    expect((await api("GET", "/companies?q=_&limit=100", { token: ownerA.token })).body.data).toEqual([]);
    expect((await api("GET", "/companies?limit=100&archived=all", { token: ownerA.token })).body.data.length).toBe(before + 2);
  });
});

describe("isolation entre organisations", () => {
  it("B ne voit, ne modifie ni n'archive rien de A (lecture, écriture, références croisées)", async () => {
    const companyA = await created("/companies", ownerA.token, { name: `Secret A ${s.run}` });
    const contactA = await created("/contacts", ownerA.token, { given_name: "Alice", family_name: "A" });
    const requestA = await created("/requests", ownerA.token, { subject: "Confidentiel A", message: "Message réservé à A." });
    const companyB = await created("/companies", ownerB.token, { name: "Société B" });
    const contactB = await created("/contacts", ownerB.token, { given_name: "Bob", family_name: "B" });

    expect((await api("GET", `/companies/${companyA.id}`, { token: ownerB.token })).status).toBe(404);
    expect((await api("PATCH", `/companies/${companyA.id}`, { token: ownerB.token, body: { name: "Piraté" }, headers: { "If-Match": companyA.version } })).status).toBe(404);
    expect((await api("POST", `/companies/${companyA.id}/archive`, { token: ownerB.token })).status).toBe(404);
    expect((await api("GET", `/requests/${requestA.id}`, { token: ownerB.token })).status).toBe(404);
    expect((await api("GET", `/contacts/${contactA.id}/communication-preferences`, { token: ownerB.token })).status).toBe(404);
    for (const path of ["/companies?limit=100&archived=all", "/contacts?limit=100", "/requests?limit=100", "/audit-events?limit=100"]) {
      const rows = (await api("GET", path, { token: ownerB.token })).body.data;
      const leaked = JSON.stringify(rows);
      for (const id of [companyA.id, contactA.id, requestA.id]) expect(leaked.includes(id), path).toBe(false);
    }
    expect((await api("GET", `/companies?q=${encodeURIComponent("Secret A")}`, { token: ownerB.token })).body.data).toEqual([]);
    // Références croisées : les clés étrangères composites refusent, sans révéler l'existence de la cible.
    const cross = [
      ["/company-contacts", { company_id: companyA.id, contact_id: contactB.id }], ["/company-contacts", { company_id: companyB.id, contact_id: contactA.id }],
      ["/addresses", { company_id: companyA.id, line1: "x", city: "y", country_code: "FR" }], ["/requests", { subject: "s", message: "message croisé", contact_id: contactA.id }],
      ["/request-notes", { request_id: requestA.id, body: "note pirate" }],
    ] as const;
    for (const [path, body] of cross) {
      const r = await api("POST", path, { token: ownerB.token, body });
      expect(r.status, path).toBe(422); expect(JSON.stringify(r.body)).not.toMatch(/fkey|constraint|organization_id/);
    }
    expect((await api("GET", `/companies/${companyA.id}`, { token: ownerA.token })).body.data.name).toBe(`Secret A ${s.run}`);
    expect((await api("GET", "/organization", { token: ownerB.token })).body.data.id).toBe(orgB);
  });
  it("une même clé d'idempotence est indépendante d'une organisation à l'autre", async () => {
    const key = `shared-key-${s.run}`;
    const a = await api("POST", "/teams", { token: ownerA.token, body: { name: "Équipe partagée" }, headers: { "Idempotency-Key": key } });
    const b = await api("POST", "/teams", { token: ownerB.token, body: { name: "Équipe partagée" }, headers: { "Idempotency-Key": key } });
    expect([a.status, b.status]).toEqual([201, 201]); expect(a.body.data.id).not.toBe(b.body.data.id);
  });
});

describe("permissions et scopes", () => {
  it("viewer : lecture seule ; editor : pas d'audit ni d'intégrations", async () => {
    expect((await api("GET", "/companies", { token: viewerA.token })).status).toBe(200);
    const denied: Array<[string, string, string, unknown]> = [
      ["POST", "/companies", viewerA.token, { name: "Refus" }], ["POST", "/requests", viewerA.token, { subject: "s", message: "message refusé" }],
      ["GET", "/audit-events", viewerA.token, undefined], ["GET", "/audit-events", editorA.token, undefined],
      ["GET", "/connections", editorA.token, undefined], ["POST", "/connections", editorA.token, { provider: "webhook", name: "x" }],
    ];
    for (const [method, path, token, body] of denied) {
      const r = await api(method, path, { token, body });
      expect(r.status, `${method} ${path}`).toBe(403); expect(r.body.error.code).toBe("forbidden");
    }
    const company = await created("/companies", editorA.token, { name: "Par un éditeur" });
    expect((await api("PATCH", `/companies/${company.id}`, { token: viewerA.token, body: { name: "x" }, headers: { "If-Match": company.version } })).status).toBe(403);
    expect((await api("POST", `/companies/${company.id}/archive`, { token: viewerA.token })).status).toBe(403);
  });
  it("une clé API limitée n'accède qu'à ses scopes", async () => {
    const key = await call(s.iamUrl, "POST", "/iam/v1/api-keys", { token: ownerA.token, body: { label: "catalogue seul", scopes: ["catalog.read"], expires_in_days: 1 } });
    expect(key.status).toBe(201);
    const token = key.body.data.token;
    expect((await api("GET", "/offerings", { token })).status).toBe(200);
    expect((await api("GET", "/companies", { token })).status).toBe(403);
    expect((await api("POST", "/offerings", { token, body: { slug: "x-1", name: "x", kind: "service" } })).status).toBe(403);
    expect((await api("GET", "/me", { token })).body.data.permissions).toEqual(["catalog.read"]);
  });
  it("la plateforme est en lecture seule : aucune écriture d'abonnement, d'application ou d'organisation", async () => {
    expect((await api("GET", "/applications", { token: viewerA.token })).body.data.map((a: any) => a.code)).toEqual(["crm", "formations", "itsm", "site"]);
    for (const path of ["/subscriptions", "/application-plans", "/organization-applications"]) {
      expect((await api("GET", path, { token: ownerA.token })).body.data).toEqual([]);
      expect((await api("POST", path, { token: ownerA.token, body: {} })).status).toBe(404);
    }
    expect((await api("PATCH", "/organization", { token: ownerA.token, body: { name: "x" } })).status).toBe(404);
  });
});

describe("catalogue, documents, demandes, consentements", () => {
  it("offres, formations et modules, avec leurs règles", async () => {
    const service = await created("/offerings", ownerA.token, { slug: `audit-${s.run}`, name: "Audit", kind: "service" });
    const training = await created("/offerings", ownerA.token, { slug: `excel-${s.run}`, name: "Excel", kind: "course", status: "published" });
    const dup = await api("POST", "/offerings", { token: ownerA.token, body: { slug: `excel-${s.run}`, name: "Doublon", kind: "course" } });
    expect(dup.status).toBe(409); expect(JSON.stringify(dup.body)).not.toMatch(/offerings_|_key/);
    expect((await api("POST", "/courses", { token: ownerA.token, body: { offering_id: service.id } })).status).toBe(422);
    const course = await created("/courses", ownerA.token, { offering_id: training.id, level: "Débutant", duration_minutes: 420 });
    expect((await api("POST", "/courses", { token: ownerA.token, body: { offering_id: training.id } })).status).toBe(409);
    await created("/course-modules", ownerA.token, { course_id: course.id, position: 1, title: "Bases" });
    expect((await api("POST", "/course-modules", { token: ownerA.token, body: { course_id: course.id, position: 1, title: "Doublon" } })).status).toBe(409);
    expect((await api("POST", "/courses", { token: ownerA.token, body: { offering_id: training.id, duration_minutes: 0 } })).status).toBe(400);
    const archived = await api("POST", `/offerings/${training.id}/archive`, { token: ownerA.token });
    expect(archived.body.data.status).toBe("archived");
    expect((await api("GET", `/offerings?status=archived&kind=course`, { token: ownerA.token })).body.data.map((o: any) => o.id)).toContain(training.id);
  });
  it("fichiers : clé de stockage générée par le serveur et préfixée par l'organisation", async () => {
    const file = await created("/files", ownerA.token, { name: "devis.pdf", media_type: "application/pdf", size_bytes: 20480, sha256: "a".repeat(64) });
    expect(file.storage_key).toMatch(new RegExp(`^${orgA}/[0-9a-f-]{36}$`));
    const company = await created("/companies", ownerA.token, { name: "Client fichier" });
    await created("/attachments", ownerA.token, { file_id: file.id, company_id: company.id });
    expect((await api("POST", "/attachments", { token: ownerA.token, body: { file_id: file.id } })).status).toBe(400);
    expect((await api("POST", "/attachments", { token: ownerB.token, body: { file_id: file.id, company_id: company.id } })).status).toBe(422);
    expect((await api("GET", `/files/${file.id}`, { token: ownerB.token })).status).toBe(404);
  });
  it("demandes : création, suivi, notes ; le contenu d'origine ne se réécrit pas", async () => {
    const request = await created("/requests", editorA.token, { subject: "Besoin de support", message: "Nous cherchons un support informatique.", details: { budget: "200 à 500 €", users: 12 } });
    expect(request).toMatchObject({ status: "new", source: "api", details: { budget: "200 à 500 €", users: 12 } });
    expect((await api("PATCH", `/requests/${request.id}`, { token: editorA.token, body: { subject: "Réécrit" }, headers: { "If-Match": request.version } })).status).toBe(400);
    const updated = await api("PATCH", `/requests/${request.id}`, { token: editorA.token, body: { status: "in_progress" }, headers: { "If-Match": request.version } });
    expect(updated.body.data.status).toBe("in_progress");
    await created("/request-notes", editorA.token, { request_id: request.id, body: "Rappeler lundi." });
    expect((await api("GET", `/request-notes?request_id=${request.id}`, { token: viewerA.token })).body.data).toHaveLength(1);
    expect((await api("GET", "/requests?status=in_progress", { token: viewerA.token })).body.data.map((r: any) => r.id)).toContain(request.id);
  });
  it("consentements : journal en ajout seul, réservé à l'organisation", async () => {
    const contact = await created("/contacts", ownerA.token, { given_name: "Dana", family_name: "Consent" });
    const path = `/contacts/${contact.id}/communication-preferences`;
    const first = await created(path, ownerA.token, { purpose: "newsletter", channel: "email", allowed: true, source: "formulaire", notice_version: "2026-11" });
    await created(path, ownerA.token, { purpose: "newsletter", channel: "email", allowed: false, source: "désinscription" });
    const history = (await api("GET", path, { token: viewerA.token })).body.data;
    expect(history.map((p: any) => p.allowed)).toEqual([false, true]); expect(history[1].id).toBe(first.id);
    expect((await api("POST", path, { token: viewerA.token, body: { purpose: "newsletter", channel: "email", allowed: true, source: "x" } })).status).toBe(403);
    expect((await api("POST", path, { token: ownerB.token, body: { purpose: "newsletter", channel: "email", allowed: true, source: "x" } })).status).toBe(404);
    expect((await api("POST", path, { token: ownerA.token, body: { purpose: "newsletter", channel: "fax", allowed: true, source: "x" } })).status).toBe(400);
    for (const method of ["PATCH", "DELETE", "PUT"]) expect((await api(method, `${path}/${first.id}`, { token: ownerA.token, body: {} })).status).toBe(404);
  });
  it("audit : chaque écriture est tracée et attribuée à son auteur", async () => {
    const company = await created("/companies", editorA.token, { name: "Tracée" });
    await api("POST", `/companies/${company.id}/archive`, { token: ownerA.token });
    const events = (await api("GET", `/audit-events?entity_id=${company.id}&sort=occurred_at`, { token: ownerA.token })).body.data;
    expect(events.map((e: any) => [e.action, e.entity_type, e.actor_user_id])).toEqual([["INSERT", "core.companies", editorA.userId], ["UPDATE", "core.companies", ownerA.userId]]);
    expect(events[0].actor_database_role).toBe("pd_core_api");
  });
});

describe("transactions, concurrence, idempotence", () => {
  it("annule toute la transaction en cas d'erreur et ne laisse aucun jeton sur les connexions du pool", async () => {
    const run = contextRunner(s.corePool);
    const name = `Fantôme ${s.run}`;
    await expect(run(ownerA.token, async (ctx) => {
      await ctx.db.query("INSERT INTO core.companies (name) VALUES ($1)", [name]);
      await ctx.db.query("INSERT INTO core.contacts (given_name, family_name) VALUES ($1, 'Fantôme')", [name]);
      throw new Error("panne simulée après deux écritures");
    })).rejects.toThrow("panne simulée");
    expect((await api("GET", `/companies?q=${encodeURIComponent(name)}`, { token: ownerA.token })).body.data).toEqual([]);
    expect((await api("GET", `/contacts?q=${encodeURIComponent(name)}`, { token: ownerA.token })).body.data).toEqual([]);
    // Demande refusée par une clé étrangère : ni demande ni événement d'outbox ne subsistent.
    const worker = pool("pd_core_worker", 1);
    const count = async () => Number((await worker.query("SELECT count(*) AS n FROM integration.outbox WHERE organization_id = $1", [orgA])).rows[0].n);
    const before = await count();
    expect((await api("POST", "/requests", { token: ownerA.token, body: { subject: "x", message: "contact inexistant", contact_id: "00000000-0000-4000-8000-0000000000ff" } })).status).toBe(422);
    expect(await count()).toBe(before);
    await created("/requests", ownerA.token, { subject: "Valide", message: "Demande valide, événement attendu." });
    expect(await count()).toBe(before + 1);
    // Chaque connexion rendue au pool est vierge : le jeton était local à la transaction.
    const clients = await Promise.all(Array.from({ length: 8 }, () => s.corePool.connect()));
    try {
      for (const client of clients) {
        expect((await client.query("SELECT current_setting('app.access_token', true) AS t")).rows[0].t ?? "").toBe("");
        expect((await client.query("SELECT count(*) AS n FROM core.companies")).rows[0].n).toBe("0");
      }
    } finally { clients.forEach((c) => c.release()); }
  });
  it("deux modifications simultanées de la même version : une seule aboutit", async () => {
    const company = await created("/companies", ownerA.token, { name: "Concurrente" });
    const attempts = await Promise.all(["Version 1", "Version 2", "Version 3", "Version 4"].map((name) =>
      api("PATCH", `/companies/${company.id}`, { token: ownerA.token, body: { name }, headers: { "If-Match": company.version } })));
    expect(attempts.map((r) => r.status).sort()).toEqual([200, 412, 412, 412]);
  });
  it("Idempotency-Key : envois simultanés = une seule création ; contenu différent = 409", async () => {
    const key = `idem-${s.run}-0001`, body = { subject: "Demande unique", message: "Envoyée douze fois en parallèle." };
    const replies = await Promise.all(Array.from({ length: 12 }, () => api("POST", "/requests", { token: ownerA.token, body, headers: { "Idempotency-Key": key } })));
    expect(replies.map((r) => r.status)).toEqual(Array(12).fill(201));
    expect(new Set(replies.map((r) => r.body.data.id)).size).toBe(1);
    expect((await api("GET", `/requests?q=${encodeURIComponent("Demande unique")}`, { token: ownerA.token })).body.data).toHaveLength(1);
    const replay = await api("POST", "/requests", { token: ownerA.token, body, headers: { "Idempotency-Key": key } });
    expect(replay.headers.get("idempotency-replayed")).toBe("true"); expect(replay.body.data.id).toBe(replies[0]!.body.data.id);
    expect((await api("POST", "/requests", { token: ownerA.token, body: { ...body, subject: "Autre" }, headers: { "Idempotency-Key": key } })).body.error.code).toBe("idempotency_conflict");
    // Un viewer ne peut pas rejouer la réponse d'une création qu'il n'a pas le droit de faire.
    expect((await api("POST", "/requests", { token: viewerA.token, body, headers: { "Idempotency-Key": key } })).status).toBe(403);
    expect((await api("POST", "/requests", { token: ownerA.token, body, headers: { "Idempotency-Key": "court" } })).status).toBe(400);
  });
});
