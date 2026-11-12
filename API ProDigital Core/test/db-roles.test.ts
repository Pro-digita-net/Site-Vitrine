// Contrôle direct des droits PostgreSQL avec les VRAIS comptes applicatifs (aucun superuser) :
// ce que l'API ne peut pas faire, même si son code était compromis.
import { afterAll, beforeAll, describe, expect, it } from "vitest";
import { transaction, type Pool } from "../src/shared/db.js";
import { call, closeAll, pool, SITE_ORG, startStack, twoOrganizations, type Stack } from "./helpers.js";

let s: Stack, orgA: string, orgB: string, tokenA: string, tokenB: string, companyA: string;
let core: Pool, iam: Pool, worker: Pool, site: Pool;
const denied = async (db: Pool, sql: string, params: unknown[] = [], code = "42501") =>
  expect(await db.query(sql, params).then(() => "autorisé", (e) => e.code), sql).toBe(code);
/** Exécute du SQL brut avec le contexte d'un jeton, comme le ferait un code applicatif détourné. */
const asToken = <T>(token: string, fn: (db: import("pg").PoolClient) => Promise<T>) => transaction(core, async (db) => {
  await db.query("SELECT set_config('app.access_token', $1, true)", [token]); return fn(db);
});
const errorCode = (p: Promise<unknown>) => p.then(() => "autorisé", (e) => e.code);

beforeAll(async () => {
  s = await startStack(); const orgs = await twoOrganizations(s); orgA = orgs.orgA; orgB = orgs.orgB;
  tokenA = (await s.member(orgs.a, "owner")).token; tokenB = (await s.member(orgs.b, "owner")).token;
  companyA = (await call(s.core, "POST", "/companies", { token: tokenA, body: { name: "Cible A" } })).body.data.id;
  core = pool("pd_core_api", 2); iam = pool("pd_iam_admin", 2); worker = pool("pd_core_worker", 2); site = pool("pd_site_api", 2);
});
afterAll(closeAll);

describe("comptes techniques", () => {
  it("aucun n'est superuser, propriétaire, BYPASSRLS, créateur de rôle ou membre d'un autre rôle", async () => {
    for (const [db, name] of [[core, "pd_core_api"], [iam, "pd_iam_admin"], [worker, "pd_core_worker"], [site, "pd_site_api"]] as const) {
      const r = (await db.query(`SELECT session_user::text AS s, current_user::text AS c, rolsuper, rolbypassrls, rolcreaterole, rolcreatedb, rolinherit,
        (SELECT count(*) FROM pg_auth_members WHERE member = r.oid) AS memberships,
        (SELECT count(*) FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace WHERE c.relowner = r.oid AND n.nspname NOT LIKE 'pg_%') AS owned
        FROM pg_roles r WHERE rolname = current_user`)).rows[0];
      expect(r).toEqual({ s: name, c: name, rolsuper: false, rolbypassrls: false, rolcreaterole: false, rolcreatedb: false, rolinherit: false, memberships: "0", owned: "0" });
      for (const sql of ["SET ROLE postgres", "SET SESSION AUTHORIZATION postgres", "CREATE TABLE public.t(i int)", "CREATE ROLE intrus", "ALTER ROLE pd_core_api BYPASSRLS"])
        expect(await errorCode(db.query(sql)), `${name}: ${sql}`).not.toBe("autorisé");
    }
    for (const role of ["pd_iam_admin", "pd_site_api", "pd_core_worker"]) expect(await errorCode(core.query(`SET ROLE ${role}`))).toBe("42501");
  });
  it("toute table portant une organisation a la RLS activée et forcée", async () => {
    const { rows } = await core.query(`SELECT n.nspname || '.' || c.relname AS t FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
      JOIN pg_attribute a ON a.attrelid = c.oid AND a.attname = 'organization_id' AND NOT a.attisdropped
      WHERE c.relkind = 'r' AND n.nspname IN ('core','catalog','documents','web','integration','notifications','audit','site') AND NOT (c.relrowsecurity AND c.relforcerowsecurity)`);
    expect(rows).toEqual([]);
  });
});

describe("pd_core_api (API métier)", () => {
  it("sans jeton valide : aucune donnée, même en SQL direct", async () => {
    for (const table of ["core.companies", "core.contacts", "web.requests", "audit.events", "core.organizations", "core.subscriptions", "core.idempotency_keys"])
      expect((await core.query(`SELECT count(*) AS n FROM ${table}`)).rows[0].n, table).toBe("0");
    expect(await asToken("A".repeat(43), async (db) => (await db.query("SELECT count(*) AS n FROM core.companies")).rows[0].n)).toBe("0");
    await denied(core, "INSERT INTO core.companies (name) VALUES ('sans contexte')");
    await denied(core, "INSERT INTO core.companies (organization_id, name) VALUES ($1, 'forcée')", [orgA]);
  });
  it("référentiel d'identité, files internes, secrets et site : inaccessibles", async () => {
    for (const sql of ["SELECT * FROM iam.users", "SELECT * FROM iam.access_tokens", "SELECT * FROM iam.memberships", "SELECT * FROM iam.identities", "SELECT * FROM iam.invitations",
      "SELECT * FROM iam.service_bindings", "SELECT * FROM iam.context()", "SELECT iam.site_organization_id()", "SELECT * FROM integration.outbox", "SELECT * FROM integration.connection_secrets",
      "SELECT * FROM integration.external_references", "SELECT * FROM web.communication_preferences", "SELECT * FROM notifications.deliveries", "SELECT * FROM site.contact_submissions",
      "SELECT * FROM site.contact_operations", "SELECT * FROM core_meta.migrations", "INSERT INTO iam.access_tokens (organization_id, user_id, token_hash, kind, scopes, expires_at) SELECT organization_id, user_id, sha256('x'), 'session', scopes, now() + interval '1 day' FROM iam.access_tokens LIMIT 1",
      "INSERT INTO integration.outbox (organization_id, event_type, payload, idempotency_key) VALUES (gen_random_uuid(), 'x', '{}', 'xxxxxxxx')"])
      await denied(core, sql);
  });
  it("ni DELETE, ni TRUNCATE, ni désactivation de la RLS, ni écriture de l'audit ou de la plateforme", async () => {
    await asToken(tokenA, async (db) => {
      for (const sql of ["DELETE FROM core.companies", "TRUNCATE core.companies", "DELETE FROM audit.events", "UPDATE audit.events SET action = 'x'", "INSERT INTO audit.events (organization_id, actor_database_role, action, entity_type) VALUES (iam.current_organization_id(), 'x', 'x', 'x')",
        "ALTER TABLE core.companies DISABLE ROW LEVEL SECURITY", "DROP POLICY tenant_boundary ON core.companies", "UPDATE core.organizations SET name = 'x'", "UPDATE core.subscriptions SET status = 'active'",
        "INSERT INTO core.organization_applications (organization_id, application_code, status) VALUES (iam.current_organization_id(), 'crm', 'enabled')", "UPDATE core.applications SET active = true",
        "DELETE FROM core.idempotency_keys", "UPDATE core.idempotency_keys SET response = '{}'", "DELETE FROM web.requests", "DROP TABLE core.companies"]) {
        await db.query("SAVEPOINT s");
        expect(await errorCode(db.query(sql)), sql).toBe("42501");
        await db.query("ROLLBACK TO SAVEPOINT s");
      }
      await db.query("SAVEPOINT s");
      await db.query("SET LOCAL row_security = off");
      expect(await errorCode(db.query("SELECT * FROM core.companies"))).toBe("42501"); // refus plutôt que contournement
      await db.query("ROLLBACK TO SAVEPOINT s");
    });
  });
  it("avec un jeton A : impossible de lire, d'écrire ou de déplacer des données vers B, ni de falsifier le contexte", async () => {
    await asToken(tokenB, async (db) => {
      await db.query("SELECT set_config('app.organization_id', $1, true), set_config('app.current_organization_id', $1, true), set_config('app.user_id', $1, true)", [orgA]);
      expect((await db.query("SELECT iam.current_organization_id() AS o")).rows[0].o).toBe(orgB);
      expect((await db.query("SELECT count(*) AS n FROM core.companies WHERE id = $1 OR organization_id = $2", [companyA, orgA])).rows[0].n).toBe("0");
      expect((await db.query("UPDATE core.companies SET name = 'piraté' WHERE id = $1", [companyA])).rowCount).toBe(0);
      for (const [sql, params] of [["INSERT INTO core.companies (organization_id, name) VALUES ($1, 'chez A')", [orgA]], ["INSERT INTO web.requests (organization_id, subject, message) VALUES ($1, 's', 'm')", [orgA]],
        ["INSERT INTO core.idempotency_keys (organization_id, key, scope, request_hash, status_code, response) VALUES ($1, 'cle-chez-a', 's', 'h', 201, '{}')", [orgA]]] as const) {
        await db.query("SAVEPOINT s");
        expect(await errorCode(db.query(sql, [...params])), sql).toBe("42501");
        await db.query("ROLLBACK TO SAVEPOINT s");
      }
      const own = (await db.query("INSERT INTO core.companies (name) VALUES ('Chez B') RETURNING id, organization_id")).rows[0];
      expect(own.organization_id).toBe(orgB);
      for (const sql of ["UPDATE core.companies SET organization_id = $2 WHERE id = $1", "UPDATE core.companies SET id = $2 WHERE id = $1"]) {
        await db.query("SAVEPOINT s");
        expect(await errorCode(db.query(sql, [own.id, orgA])), sql).toBe("42501");
        await db.query("ROLLBACK TO SAVEPOINT s");
      }
      // Fonctions bornées : elles n'agissent que dans l'organisation du jeton.
      await db.query("SAVEPOINT s");
      expect(await errorCode(db.query("SELECT integration.publish_request_created((SELECT gen_random_uuid()))"))).toBe("P0002");
      await db.query("ROLLBACK TO SAVEPOINT s");
      expect((await db.query("SELECT count(*) AS n FROM web.list_communication_preferences($1)", [companyA])).rows[0].n).toBe("0");
    });
    expect((await call(s.core, "GET", `/companies/${companyA}`, { token: tokenA })).body.data.name).toBe("Cible A");
  });
  it("les fonctions bornées refusent sans contexte ni permission", async () => {
    await denied(core, "SELECT integration.publish_request_created(gen_random_uuid())");
    await denied(core, "SELECT web.record_communication_preference(gen_random_uuid(), 'newsletter', 'email', true, 'x', NULL)");
    expect((await core.query("SELECT count(*) AS n FROM web.list_communication_preferences(gen_random_uuid())")).rows[0].n).toBe("0");
  });
});

describe("pd_iam_admin (composant IAM)", () => {
  it("gère les accès mais ne lit aucune donnée métier, ne supprime rien, ne réécrit pas un jeton", async () => {
    for (const sql of ["SELECT * FROM core.companies", "SELECT * FROM core.contacts", "SELECT * FROM web.requests", "SELECT * FROM documents.files", "SELECT * FROM site.contact_submissions",
      "SELECT * FROM integration.connection_secrets", "SELECT * FROM integration.outbox", "SELECT * FROM audit.events", "SELECT * FROM iam.service_bindings", "SELECT * FROM core.subscriptions",
      "DELETE FROM iam.users", "DELETE FROM iam.access_tokens", "DELETE FROM iam.memberships", "DELETE FROM core.organizations", "TRUNCATE iam.access_tokens",
      "UPDATE iam.access_tokens SET token_hash = sha256('x')", "UPDATE iam.access_tokens SET scopes = scopes", "UPDATE iam.access_tokens SET expires_at = now() + interval '10 years'",
      "UPDATE iam.memberships SET organization_id = gen_random_uuid()", "UPDATE iam.service_bindings SET active = false", "UPDATE core.organizations SET id = gen_random_uuid()", "UPDATE audit.events SET action = 'x'"])
      await denied(iam, sql);
    await denied(iam, "INSERT INTO audit.events (organization_id, actor_database_role, action, entity_type) VALUES ($1, 'postgres', 'faux', 'x')", [orgA]); // signature imposée
  });
  it("une révocation est définitive", async () => {
    const key = (await call(s.iamUrl, "POST", "/iam/v1/api-keys", { token: tokenA, body: { label: "à révoquer", scopes: ["audit.read"], expires_in_days: 1 } })).body.data;
    await call(s.iamUrl, "DELETE", `/iam/v1/tokens/${key.id}`, { token: tokenA });
    await denied(iam, "UPDATE iam.access_tokens SET revoked_at = NULL WHERE id = $1", [key.id]);
    await denied(iam, "UPDATE iam.access_tokens SET revoked_at = now() + interval '1 day' WHERE id = $1", [key.id]);
    expect((await call(s.core, "GET", "/me", { token: key.token })).status).toBe(401);
  });
});

describe("pd_core_worker et pd_site_api", () => {
  it("le worker ne voit que ses files : ni annuaire, ni demandes, ni identités ; il ne crée ni ne supprime d'événement", async () => {
    for (const sql of ["SELECT * FROM core.companies", "SELECT * FROM web.requests", "SELECT * FROM iam.users", "SELECT * FROM iam.access_tokens", "SELECT * FROM site.contact_submissions",
      "SELECT * FROM audit.events", "SELECT * FROM web.communication_preferences", "DELETE FROM integration.outbox", "DELETE FROM notifications.deliveries", "DELETE FROM integration.connection_secrets",
      "INSERT INTO integration.outbox (organization_id, event_type, payload, idempotency_key) VALUES (gen_random_uuid(), 'x', '{}', 'xxxxxxxx')",
      "UPDATE integration.outbox SET payload = '{}'", "UPDATE integration.outbox SET organization_id = gen_random_uuid()", "UPDATE integration.connections SET status = 'enabled'", "UPDATE notifications.deliveries SET recipient = 'x@y.z'"])
      await denied(worker, sql);
  });
  it("le compte du site est lié à ProDigital par session_user et n'accède à rien d'autre", async () => {
    expect((await site.query("SELECT iam.site_organization_id() AS o")).rows[0].o).toBe(SITE_ORG);
    for (const sql of ["SELECT * FROM core.companies", "SELECT * FROM core.organizations", "SELECT * FROM iam.users", "SELECT * FROM iam.access_tokens", "SELECT * FROM web.requests",
      "SELECT * FROM integration.outbox", "SELECT iam.current_organization_id()", "DELETE FROM site.contact_submissions", "TRUNCATE site.contact_events", "DELETE FROM site.contact_events",
      "UPDATE site.contact_events SET detail = 'x'", "UPDATE site.contact_submissions SET message = 'réécrit'"])
      await denied(site, sql);
    await denied(site, "INSERT INTO site.contact_submissions (organization_id, idempotency_key, request_hash, natural_key, given_name, family_name, email, subject, subject_group, message) VALUES ($1, 'cle-autre-org', 'h', 'n', 'a', 'b', 'a@b.c', 's', 'g', 'message de test')", [orgA]);
  });
});
