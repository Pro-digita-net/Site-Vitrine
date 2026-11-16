import { execFileSync } from "node:child_process";
import { fileURLToPath } from "node:url";
import { afterAll, beforeAll, describe, expect, it } from "vitest";
import { createIamApp } from "../src/iam/app.js";
import { createOidcVerifier } from "../src/iam/oidc.js";
import { IamService } from "../src/iam/service.js";
import { hashToken } from "../src/shared/tokens.js";
import { call, closeAll, listen, log, startStack, twoOrganizations, urls, type Reply, type Stack } from "./helpers.js";

let s: Stack, orgs: Awaited<ReturnType<typeof twoOrganizations>>;
let ownerA: Awaited<ReturnType<Stack["member"]>>, adminA: typeof ownerA, viewerA: typeof ownerA, ownerB: typeof ownerA;
const iam = (method: string, path: string, opts?: Parameters<typeof call>[3]): Promise<Reply> => call(s.iamUrl, method, `/iam/v1${path}`, opts);
const me = (token: string) => call(s.core, "GET", "/me", { token });

beforeAll(async () => {
  s = await startStack(); orgs = await twoOrganizations(s);
  ownerA = await s.member(orgs.a, "owner"); adminA = await s.member(orgs.a, "admin"); viewerA = await s.member(orgs.a, "viewer");
  ownerB = await s.member(orgs.b, "owner");
});
afterAll(closeAll);

describe("connexion par identité vérifiée (OIDC) → jeton opaque", () => {
  it("émet une session opaque dont seule l'empreinte SHA-256 est stockée", async () => {
    const r = await s.login(ownerA.sub, orgs.a);
    expect(r.status).toBe(201);
    const { token, kind, scopes, expires_at, organization_id } = r.body.data;
    expect(token).toMatch(/^[A-Za-z0-9_-]{43}$/); expect(kind).toBe("session"); expect(scopes).toHaveLength(11); expect(organization_id).toBe(orgs.orgA);
    expect(new Date(expires_at).getTime()).toBeGreaterThan(Date.now());
    const row = (await s.iamPool.query("SELECT token_hash FROM iam.access_tokens WHERE id = $1", [r.body.data.id])).rows[0];
    expect(Buffer.compare(row.token_hash, hashToken(token))).toBe(0);
    expect((await s.iamPool.query("SELECT count(*) AS n FROM iam.access_tokens WHERE encode(token_hash, 'escape') = $1 OR label = $1", [token])).rows[0].n).toBe("0");
    expect((await me(token)).status).toBe(200);
  });
  it("refuse signature forgée, mauvais émetteur, mauvaise audience, jeton expiré, alg none, identité inconnue", async () => {
    const bad = [
      await s.idp.sign({ sub: ownerA.sub }, { key: s.idp.forgedKey }), await s.idp.sign({ sub: ownerA.sub }, { issuer: "https://evil.invalid" }),
      await s.idp.sign({ sub: ownerA.sub }, { audience: "autre-application" }), await s.idp.sign({ sub: ownerA.sub }, { exp: Math.floor(Date.now() / 1000) - 3600 }),
      `${Buffer.from('{"alg":"none"}').toString("base64url")}.${Buffer.from(JSON.stringify({ sub: ownerA.sub, iss: s.idp.oidc.issuer, aud: s.idp.oidc.audience })).toString("base64url")}.`,
      await s.idp.sign({ sub: "inconnu-de-la-base" }),
    ];
    for (const id_token of bad) {
      const r = await iam("POST", "/sessions", { body: { id_token, organization: orgs.a } });
      expect(r.status).toBe(401); expect(r.body.error.code).toBe("unauthorized");
    }
    // Identité valide mais organisation où elle n'a aucun accès : même réponse, aucune fuite d'existence.
    expect((await s.login(ownerA.sub, orgs.b)).status).toBe(401);
    expect((await iam("POST", "/sessions", { body: { id_token: "x".repeat(30), organization: orgs.a, role: "owner" } })).status).toBe(400);
  });
  it("demande l'organisation quand l'identité en a plusieurs", async () => {
    await s.iam.platform.setMembership(orgs.b, viewerA.email, "viewer");
    const r = await s.login(viewerA.sub);
    expect(r.status).toBe(409); expect(r.body.error.details.organizations.sort()).toEqual([orgs.a, orgs.b].sort());
    expect((await me((await s.login(viewerA.sub, orgs.b)).body.data.token)).body.data.organization_id).toBe(orgs.orgB);
  });
  it("répond 503 explicite si aucun fournisseur d'identité n'est configuré", async () => {
    const { app } = createIamApp({ config: { ...s.config, iam: { ...s.config.iam, oidc: { issuer: "", audience: "", jwksUri: "" } } }, pool: s.iamPool, log });
    const { url } = await listen(app);
    const r = await call(url, "POST", "/iam/v1/sessions", { body: { id_token: await s.idp.sign({ sub: ownerA.sub }) } });
    expect(r.status).toBe(503); expect(r.body.error.code).toBe("not_configured");
  });
});

describe("expiration et révocation", () => {
  it("un jeton expiré est refusé par la base elle-même", async () => {
    const short = new IamService(s.iamPool, createOidcVerifier(s.idp.oidc), { ...s.config.iam, sessionTtlHours: 1.2 / 3600 });
    const { token } = await short.login(await s.idp.sign({ sub: ownerA.sub }), orgs.a);
    expect((await me(token)).status).toBe(200);
    await new Promise((r) => setTimeout(r, 1500));
    expect((await me(token)).status).toBe(401);
    expect((await iam("GET", "/members", { token })).status).toBe(401);
  });
  it("la déconnexion révoque immédiatement, sur l'API métier comme sur l'IAM", async () => {
    const token = (await s.login(adminA.sub, orgs.a)).body.data.token;
    expect((await me(token)).status).toBe(200);
    expect((await iam("DELETE", "/sessions/current", { token })).status).toBe(204);
    expect((await me(token)).status).toBe(401);
    expect((await iam("DELETE", "/sessions/current", { token })).status).toBe(401);
    expect((await iam("DELETE", "/sessions/current")).status).toBe(401);
  });
  it("suspendre un membre coupe tous ses accès ; le réactiver ne ressuscite pas ses anciens jetons", async () => {
    const victim = await s.member(orgs.a, "editor", "suspendu");
    expect((await me(victim.token)).status).toBe(200);
    expect((await iam("PATCH", `/members/${victim.userId}`, { token: ownerA.token, body: { status: "suspended" } })).status).toBe(200);
    expect((await me(victim.token)).status).toBe(401);
    expect((await s.login(victim.sub, orgs.a)).status).toBe(401);
    await iam("PATCH", `/members/${victim.userId}`, { token: ownerA.token, body: { status: "active" } });
    expect((await me(victim.token)).status).toBe(401);
    expect((await s.login(victim.sub, orgs.a)).status).toBe(201);
  });
  it("suspendre l'organisation coupe tous ses jetons", async () => {
    const slug = `ferme-${s.run}`;
    await s.iam.platform.createOrganization(slug, "Fermée");
    const member = await s.member(slug, "owner", "ferme");
    await s.iam.platform.setOrganizationStatus(slug, "suspended");
    expect((await me(member.token)).status).toBe(401);
    expect((await iam("GET", "/members", { token: member.token })).status).toBe(401);
  });
});

describe("appartenances et rôles", () => {
  it("réservé aux sessions owner/admin : ni viewer, ni clé API, ni autre organisation", async () => {
    expect((await iam("GET", "/members", { token: viewerA.token })).status).toBe(403);
    const key = (await iam("POST", "/api-keys", { token: ownerA.token, body: { label: "automate", scopes: ["directory.read", "directory.write"], expires_in_days: 1 } })).body.data.token;
    for (const [method, path, body] of [["GET", "/members", undefined], ["GET", "/tokens", undefined], ["POST", "/api-keys", { label: "x", scopes: ["audit.read"], expires_in_days: 1 }],
      ["POST", "/invitations", { email: "x@example.com", role: "admin" }]] as const)
      expect((await iam(method, path, { token: key, body })).status, path).toBe(403);
    const members = (await iam("GET", "/members", { token: adminA.token })).body.data;
    expect(members.map((m: any) => m.user_id)).toEqual(expect.arrayContaining([ownerA.userId, adminA.userId, viewerA.userId]));
    expect(members.map((m: any) => m.user_id)).not.toContain(ownerB.userId);
    expect((await iam("PATCH", `/members/${ownerA.userId}`, { token: ownerB.token, body: { role: "viewer" } })).status).toBe(404);
  });
  it("pas d'escalade : un admin ne nomme ni ne touche un propriétaire, nul ne modifie sa propre appartenance", async () => {
    expect((await iam("PATCH", `/members/${viewerA.userId}`, { token: adminA.token, body: { role: "owner" } })).status).toBe(403);
    expect((await iam("PATCH", `/members/${ownerA.userId}`, { token: adminA.token, body: { role: "viewer" } })).status).toBe(403);
    expect((await iam("PATCH", `/members/${ownerA.userId}`, { token: adminA.token, body: { status: "suspended" } })).status).toBe(403);
    expect((await iam("PATCH", `/members/${adminA.userId}`, { token: adminA.token, body: { role: "owner" } })).status).toBe(403);
    expect((await iam("PATCH", `/members/${viewerA.userId}`, { token: adminA.token, body: {} })).status).toBe(400);
    const promoted = await s.member(orgs.a, "viewer", "promu");
    expect((await iam("PATCH", `/members/${promoted.userId}`, { token: adminA.token, body: { role: "editor" } })).body.data.role).toBe("editor");
    // Changement de rôle : l'ancien jeton (émis pour un viewer) est révoqué.
    expect((await me(promoted.token)).status).toBe(401);
    expect((await me((await s.login(promoted.sub, orgs.a)).body.data.token)).body.data.permissions).toContain("directory.write");
  });
  it("deux propriétaires qui se rétrogradent en même temps : l'organisation garde un propriétaire", async () => {
    const slug = `duo-${s.run}`;
    const org = await s.iam.platform.createOrganization(slug, "Duo");
    const o1 = await s.member(slug, "owner", "duo"), o2 = await s.member(slug, "owner", "duo");
    // Les deux appelants sont déjà authentifiés : seul le verrou sur les propriétaires les départage.
    const [a1, a2] = [await s.iam.authenticate(o1.token), await s.iam.authenticate(o2.token)];
    const results = await Promise.allSettled([s.iam.updateMember(a1, o2.userId, { role: "viewer" }), s.iam.updateMember(a2, o1.userId, { role: "viewer" })]);
    expect(results.map((r) => r.status).sort()).toEqual(["fulfilled", "rejected"]);
    expect((results.find((r) => r.status === "rejected") as PromiseRejectedResult).reason.status).toBe(409);
    const owners = (await s.iamPool.query("SELECT count(*) AS n FROM iam.memberships WHERE organization_id = $1 AND role = 'owner' AND status = 'active'", [org.id])).rows[0].n;
    expect(owners).toBe("1");
  });
});

describe("invitations", () => {
  const accept = async (token: string, claims: Record<string, unknown>) => iam("POST", "/invitations/accept", { body: { invitation_token: token, id_token: await s.idp.sign(claims) } });
  it("acceptation avec e-mail vérifié correspondant : compte, identité, appartenance et session créés", async () => {
    const email = `invite-${s.run}@example.com`;
    const invitation = await iam("POST", "/invitations", { token: adminA.token, body: { email: email.toUpperCase(), role: "editor" } });
    expect(invitation.status).toBe(201);
    const secret = invitation.body.data.token;
    expect((await accept(secret, { sub: `inv-${s.run}`, email, email_verified: false })).status).toBe(401);
    expect((await accept(secret, { sub: `inv-${s.run}`, email: "autre@example.com", email_verified: true })).status).toBe(401);
    expect((await accept("A".repeat(43), { sub: `inv-${s.run}`, email, email_verified: true })).status).toBe(401);
    const ok = await accept(secret, { sub: `inv-${s.run}`, email, email_verified: true, given_name: "Inès", family_name: "Vitée" });
    expect(ok.status).toBe(201);
    const session = (await me(ok.body.data.token)).body.data;
    expect(session.organization_id).toBe(orgs.orgA); expect(session.permissions).toContain("directory.write"); expect(session.permissions).not.toContain("audit.read");
    expect((await accept(secret, { sub: `inv-${s.run}`, email, email_verified: true })).status).toBe(401); // usage unique
    expect((await s.login(`inv-${s.run}`, orgs.a)).status).toBe(201);
    const listed = (await iam("GET", "/invitations", { token: adminA.token })).body.data;
    expect(JSON.stringify(listed)).not.toContain(secret); expect(listed[0].accepted_at).not.toBeNull();
  });
  it("une invitation révoquée ou d'une autre organisation est inutilisable", async () => {
    const email = `revoquee-${s.run}@example.com`;
    const invitation = (await iam("POST", "/invitations", { token: ownerA.token, body: { email, role: "viewer" } })).body.data;
    expect((await iam("DELETE", `/invitations/${invitation.id}`, { token: ownerB.token })).status).toBe(404);
    expect((await iam("DELETE", `/invitations/${invitation.id}`, { token: ownerA.token })).status).toBe(204);
    expect((await accept(invitation.token, { sub: `rev-${s.run}`, email, email_verified: true })).status).toBe(401);
    expect((await iam("POST", "/invitations", { token: ownerA.token, body: { email, role: "owner" } })).status).toBe(400);
    expect((await iam("POST", "/invitations", { token: viewerA.token, body: { email, role: "viewer" } })).status).toBe(403);
  });
});

describe("clés API et comptes de service (interservices)", () => {
  it("permissions bornées par le rôle du titulaire, durée bornée, révocation immédiate", async () => {
    const over = await iam("POST", "/api-keys", { token: ownerA.token, body: { user_id: viewerA.userId, label: "trop large", scopes: ["directory.read", "directory.write"], expires_in_days: 1 } });
    expect(over.status).toBe(422);
    expect((await iam("POST", "/api-keys", { token: ownerA.token, body: { label: "x", scopes: ["tout.lire"], expires_in_days: 1 } })).status).toBe(400);
    expect((await iam("POST", "/api-keys", { token: ownerA.token, body: { label: "x", scopes: ["audit.read"], expires_in_days: 400 } })).status).toBe(400);
    expect((await iam("POST", "/api-keys", { token: ownerA.token, body: { user_id: ownerB.userId, label: "x", scopes: ["audit.read"], expires_in_days: 1 } })).status).toBe(422);
    const key = (await iam("POST", "/api-keys", { token: ownerA.token, body: { label: "lecture annuaire", scopes: ["directory.read"], expires_in_days: 30 } })).body.data;
    expect(key.kind).toBe("api_key"); expect((await me(key.token)).body.data.permissions).toEqual(["directory.read"]);
    const listed = (await iam("GET", "/tokens", { token: ownerA.token })).body.data;
    expect(listed.find((t: any) => t.id === key.id)).toMatchObject({ label: "lecture annuaire", scopes: ["directory.read"], revoked_at: null });
    expect(JSON.stringify(listed)).not.toMatch(/token_hash|"token"/);
    expect((await iam("DELETE", `/tokens/${key.id}`, { token: ownerB.token })).status).toBe(404);
    expect((await me(key.token)).status).toBe(200);
    expect((await iam("DELETE", `/tokens/${key.id}`, { token: ownerA.token })).status).toBe(204);
    expect((await me(key.token)).status).toBe(401);
    expect((await iam("DELETE", `/tokens/${key.id}`, { token: ownerA.token })).status).toBe(404);
  });
  it("un compte de service agit par clé API dans son organisation et ne peut pas se connecter", async () => {
    const account = (await iam("POST", "/service-accounts", { token: ownerA.token, body: { name: "Genesis CRM", role: "editor" } })).body.data;
    const key = (await iam("POST", "/api-keys", { token: ownerA.token, body: { user_id: account.user_id, label: "genesis", scopes: ["requests.read", "requests.write"], expires_in_days: 90 } })).body.data;
    const request = await call(s.core, "POST", "/requests", { token: key.token, body: { subject: "Depuis un service", message: "Créée par un compte de service." } });
    expect(request.status).toBe(201);
    expect((await call(s.core, "GET", "/companies", { token: key.token })).status).toBe(403);
    expect((await iam("POST", "/service-accounts", { token: adminA.token, body: { name: "x", role: "owner" } })).status).toBe(400);
    const audit = (await call(s.core, "GET", `/audit-events?entity_id=${account.user_id}`, { token: ownerA.token })).body.data;
    expect(audit.map((e: any) => [e.action, e.actor_database_role, e.actor_user_id])).toEqual([["iam.service_account.created", "pd_iam_admin", ownerA.userId]]);
  });
});

describe("CLI d'amorçage (compte pd_iam_admin)", () => {
  const cli = (...args: string[]) => execFileSync(process.execPath, ["--import", "tsx", "src/iam/cli.ts", ...args],
    { cwd: fileURLToPath(new URL("..", import.meta.url)), encoding: "utf8", env: { ...process.env, IAM_DATABASE_URL: urls.pd_iam_admin, LOG_LEVEL: "silent" } });
  it("crée organisation, utilisateur, identité, propriétaire et clé API sans compte par défaut", () => {
    const slug = `cli-${s.run}`, email = `cli-${s.run}@example.com`;
    expect(JSON.parse(cli("org:create", "--slug", slug, "--name", "Depuis la CLI")).slug).toBe(slug);
    cli("user:create", "--email", email, "--given-name", "Ada", "--family-name", "Cli");
    cli("identity:link", "--email", email, "--issuer", s.idp.oidc.issuer, "--subject", `cli-${s.run}`);
    expect(JSON.parse(cli("member:set", "--org", slug, "--email", email, "--role", "owner")).role).toBe("owner");
    const key = JSON.parse(cli("token:issue", "--org", slug, "--email", email, "--label", "amorçage", "--scopes", "directory.read,audit.read", "--days", "1"));
    expect(key.token).toMatch(/^[A-Za-z0-9_-]{43}$/);
    expect(JSON.parse(cli("org:list")).map((o: any) => o.slug)).toEqual(expect.arrayContaining(["prodigital", slug]));
    expect(() => cli("member:set", "--org", slug, "--email", email, "--role", "root")).toThrow();
  });
});
