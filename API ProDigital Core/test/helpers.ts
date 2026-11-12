import { readFileSync } from "node:fs";
import { createServer, type Server } from "node:http";
import type { AddressInfo } from "node:net";
import { exportJWK, generateKeyPair, SignJWT } from "jose";
import { loadConfig, type Config } from "../src/config.js";
import { createCoreApp } from "../src/core/app.js";
import { createIamApp } from "../src/iam/app.js";
import { createOidcVerifier } from "../src/iam/oidc.js";
import { IamService, type Role } from "../src/iam/service.js";
import { createPool, type Pool } from "../src/shared/db.js";
import { createLogger } from "../src/shared/logger.js";

process.env.LOG_LEVEL = "silent";
export const urls = JSON.parse(readFileSync(new URL(".runtime.json", import.meta.url), "utf8")) as Record<"pd_core_api" | "pd_site_api" | "pd_iam_admin" | "pd_core_worker", string>;
export const log = createLogger("test");
export const SITE_ORG = "00000000-0000-4000-8000-000000000001";

const closers: Array<() => Promise<unknown>> = [];
export const closeAll = async () => { for (const close of closers.splice(0).reverse()) await close().catch(() => {}); };
export const pool = (role: keyof typeof urls, max = 5): Pool => { const p = createPool(urls[role], { max, application: `test-${role}`, log }); closers.push(() => p.end()); return p; };
export const listen = (handler: Parameters<typeof createServer>[1]): Promise<{ url: string; server: Server }> => new Promise((resolve) => {
  const server = createServer(handler);
  server.listen(0, "127.0.0.1", () => { closers.push(() => new Promise((r) => { server.closeAllConnections(); server.close(r); })); resolve({ url: `http://127.0.0.1:${(server.address() as AddressInfo).port}`, server }); });
});

export interface Reply { status: number; body: any; headers: Headers }
export async function call(base: string, method: string, path: string, opts: { token?: string; body?: unknown; headers?: Record<string, string>; raw?: string } = {}): Promise<Reply> {
  const response = await fetch(base + path, { method, body: opts.raw ?? (opts.body === undefined ? undefined : JSON.stringify(opts.body)),
    headers: { ...(opts.body !== undefined || opts.raw ? { "Content-Type": "application/json" } : {}), ...(opts.token ? { Authorization: `Bearer ${opts.token}` } : {}), ...opts.headers } });
  const textBody = await response.text();
  let body: unknown = textBody; try { body = JSON.parse(textBody); } catch { /* texte brut */ }
  return { status: response.status, body, headers: response.headers };
}

/** Fournisseur d'identité de test : vraies clés RSA, JWKS servi en HTTP, vérification cryptographique réelle. */
export async function identityProvider() {
  const { publicKey, privateKey } = await generateKeyPair("RS256");
  const jwk = { ...(await exportJWK(publicKey)), kid: "test-key", alg: "RS256", use: "sig" };
  const { url } = await listen((_req, res) => { res.setHeader("Content-Type", "application/json"); res.end(JSON.stringify({ keys: [jwk] })); });
  const issuer = "https://idp.test.invalid", audience = "prodigital-core";
  const sign = (claims: Record<string, unknown>, o: { key?: CryptoKey; issuer?: string; audience?: string; exp?: string | number } = {}) =>
    new SignJWT(claims).setProtectedHeader({ alg: "RS256", kid: "test-key" }).setIssuedAt().setIssuer(o.issuer ?? issuer).setAudience(o.audience ?? audience)
      .setExpirationTime(o.exp ?? "5m").sign(o.key ?? privateKey);
  return { oidc: { issuer, audience, jwksUri: url }, sign, forgedKey: (await generateKeyPair("RS256")).privateKey };
}

export interface Stack {
  config: Config; core: string; iamUrl: string; iam: IamService; idp: Awaited<ReturnType<typeof identityProvider>>;
  corePool: Pool; iamPool: Pool; run: string;
  /** Crée un utilisateur relié à une identité OIDC et membre de l'organisation, puis ouvre une vraie session. */
  member(org: string, role: Role, name?: string): Promise<{ token: string; userId: string; email: string; sub: string }>;
  login(sub: string, org?: string): Promise<Reply>;
}

/** Démarre l'API métier et le service IAM sur des ports éphémères, chacun avec son compte PostgreSQL. */
export async function startStack(overrides: Partial<Config["rateLimit"]> = {}): Promise<Stack> {
  const idp = await identityProvider();
  const base = loadConfig();
  const config: Config = { ...base, trustProxy: false, metricsToken: "m".repeat(40), rateLimit: { windowMs: 60_000, max: 100_000, authMax: 100_000, ...overrides },
    iam: { ...base.iam, oidc: idp.oidc, sessionTtlHours: 1 } };
  const corePool = pool("pd_core_api", 8), iamPool = pool("pd_iam_admin"), sitePool = pool("pd_site_api", 2);
  const core = await listen(createCoreApp({ config, pool: corePool, sitePool, log }));
  const iamApp = createIamApp({ config, pool: iamPool, log, verifier: createOidcVerifier(idp.oidc) });
  const iamHttp = await listen(iamApp.app);
  const run = Math.random().toString(36).slice(2, 8);
  let n = 0;
  const login = async (sub: string, org?: string) => call(iamHttp.url, "POST", "/iam/v1/sessions", { body: { id_token: await idp.sign({ sub }), ...(org ? { organization: org } : {}) } });
  return { config, core: `${core.url}/api/v1`, iamUrl: iamHttp.url, iam: iamApp.iam, idp, corePool, iamPool, run, login,
    async member(org, role, name = role) {
      const email = `${name}-${run}-${++n}@example.com`, sub = `sub-${run}-${n}`;
      const user = await iamApp.iam.platform.createUser(email, name, "Test");
      await iamApp.iam.platform.linkIdentity(email, idp.oidc.issuer, sub);
      await iamApp.iam.platform.setMembership(org, email, role);
      const reply = await login(sub, org);
      if (reply.status !== 201) throw new Error(`Connexion de test refusée : ${reply.status} ${JSON.stringify(reply.body)}`);
      return { token: reply.body.data.token, userId: user.id, email, sub };
    } };
}

/** Deux organisations de test, créées par le composant IAM (jamais par un superuser). */
export async function twoOrganizations(stack: Stack) {
  const a = `acme-${stack.run}`, b = `globex-${stack.run}`;
  const orgA = await stack.iam.platform.createOrganization(a, "Acme"), orgB = await stack.iam.platform.createOrganization(b, "Globex");
  return { a, b, orgA: orgA.id as string, orgB: orgB.id as string };
}
