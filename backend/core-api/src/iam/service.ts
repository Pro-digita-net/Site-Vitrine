import { randomBytes } from "node:crypto";
import { AppError, badRequest, conflict, forbidden, notFound, unauthorized, unprocessable } from "../shared/errors.js";
import { transaction, type Db, type Pool } from "../shared/db.js";
import { generateToken, hashToken, PERMISSIONS, type Permission } from "../shared/tokens.js";
import type { IdentityVerifier, VerifiedIdentity } from "./oidc.js";

export type Role = "owner" | "admin" | "editor" | "viewer";
const READ: Permission[] = ["directory.read", "catalog.read", "documents.read", "requests.read"];
const WRITE: Permission[] = ["directory.write", "catalog.write", "documents.write", "requests.write"];
/** Plafond de permissions par rôle. La base refuse en plus toute écriture à un viewer. */
export const ROLE_SCOPES: Record<Role, readonly Permission[]> = { viewer: READ, editor: [...READ, ...WRITE], admin: PERMISSIONS, owner: PERMISSIONS };

export interface Actor { tokenId: string; userId: string; organizationId: string; role: Role; kind: "session" | "api_key" }
export interface IamOptions { sessionTtlHours: number; invitationTtlHours: number; apiKeyMaxDays: number }
const TOKEN_COLUMNS = "id, user_id, kind, label, scopes::text[] AS scopes, created_at, expires_at, revoked_at";

/**
 * Cycle de vie des identités, appartenances et jetons. Seul composant connecté avec pd_iam_admin ;
 * l'API métier (pd_core_api) n'a aucun droit sur ces tables. Toute écriture est journalisée dans audit.events.
 */
export class IamService {
  constructor(private pool: Pool, private verify: IdentityVerifier, private opts: IamOptions) {}

  private tx<T>(fn: (db: Db) => Promise<T>) { return transaction(this.pool, fn); }
  private audit(db: Db, organizationId: string, actorUserId: string | null, action: string, entityType: string, entityId: string | null) {
    return db.query(`INSERT INTO audit.events (organization_id, actor_user_id, actor_database_role, action, entity_type, entity_id) VALUES ($1, $2, session_user, $3, $4, $5)`,
      [organizationId, actorUserId, action, entityType, entityId]);
  }
  private async issue(db: Db, organizationId: string, userId: string, kind: "session" | "api_key", scopes: readonly Permission[], ttlMs: number, label: string, actorUserId: string | null) {
    const token = generateToken();
    const { rows } = await db.query(
      `INSERT INTO iam.access_tokens (organization_id, user_id, token_hash, kind, label, scopes, expires_at)
       VALUES ($1, $2, $3, $4, $5, $6::iam.permission[], now() + ($7::bigint * interval '1 millisecond')) RETURNING ${TOKEN_COLUMNS}`,
      [organizationId, userId, hashToken(token), kind, label, [...scopes], Math.round(ttlMs)]);
    await this.audit(db, organizationId, actorUserId, `iam.${kind}.issued`, "iam.access_tokens", rows[0].id);
    return { token, ...rows[0], organization_id: organizationId };
  }

  /** Résout l'appelant à partir de son jeton opaque, avec les mêmes conditions que iam.context(). */
  async authenticate(token: string | null): Promise<Actor> {
    if (!token) throw unauthorized();
    const { rows } = await this.pool.query(
      `SELECT t.id AS token_id, t.user_id, t.organization_id, m.role, t.kind
         FROM iam.access_tokens t JOIN iam.memberships m USING (organization_id, user_id)
         JOIN iam.users u ON u.id = t.user_id JOIN core.organizations o ON o.id = t.organization_id
        WHERE t.token_hash = $1 AND t.revoked_at IS NULL AND t.expires_at > now() AND m.status = 'active' AND u.status = 'active' AND o.status = 'active'`,
      [hashToken(token)]);
    const r = rows[0];
    if (!r) throw unauthorized();
    return { tokenId: r.token_id, userId: r.user_id, organizationId: r.organization_id, role: r.role, kind: r.kind };
  }
  /** L'administration IAM exige une session humaine owner/admin : une clé API ne gère pas les accès. */
  private admin(actor: Actor) { if (actor.kind !== "session" || (actor.role !== "owner" && actor.role !== "admin")) throw forbidden(); }

  // ───────────── Sessions ─────────────
  async login(idToken: string, organizationSlug?: string) {
    const identity = await this.verify(idToken);
    return this.tx(async (db) => {
      const { rows } = await db.query(
        `SELECT m.organization_id, m.user_id, m.role, o.slug FROM iam.identities i JOIN iam.users u ON u.id = i.user_id AND u.status = 'active'
           JOIN iam.memberships m ON m.user_id = u.id AND m.status = 'active' JOIN core.organizations o ON o.id = m.organization_id AND o.status = 'active'
          WHERE i.issuer = $1 AND i.subject = $2 ORDER BY o.slug`, [identity.issuer, identity.subject]);
      const matches = organizationSlug ? rows.filter((r) => r.slug === organizationSlug) : rows;
      if (!matches.length) throw unauthorized(); // identité inconnue ou sans accès : réponse identique
      if (matches.length > 1) throw new AppError(409, "organization_required", "Préciser l'organisation.", { organizations: matches.map((r) => r.slug) });
      const m = matches[0];
      return this.issue(db, m.organization_id, m.user_id, "session", ROLE_SCOPES[m.role as Role], this.opts.sessionTtlHours * 3_600_000, "session", m.user_id);
    });
  }

  private async revoke(db: Db, organizationId: string, tokenId: string, actorUserId: string | null) {
    const { rowCount } = await db.query("UPDATE iam.access_tokens SET revoked_at = now() WHERE organization_id = $1 AND id = $2 AND revoked_at IS NULL", [organizationId, tokenId]);
    if (rowCount) await this.audit(db, organizationId, actorUserId, "iam.token.revoked", "iam.access_tokens", tokenId);
    return !!rowCount;
  }
  logout(actor: Actor) { return this.tx((db) => this.revoke(db, actor.organizationId, actor.tokenId, actor.userId)); }

  // ───────────── Membres ─────────────
  async listMembers(actor: Actor) {
    this.admin(actor);
    return (await this.pool.query(
      `SELECT m.user_id, u.email, u.given_name, u.family_name, m.role, m.status, u.status AS user_status, m.created_at
         FROM iam.memberships m JOIN iam.users u ON u.id = m.user_id WHERE m.organization_id = $1 ORDER BY u.family_name, u.given_name LIMIT 1000`, [actor.organizationId])).rows;
  }

  updateMember(actor: Actor, userId: string, change: { role?: Role; status?: "active" | "suspended" | "revoked" }) {
    this.admin(actor);
    if (userId === actor.userId) throw forbidden("Un membre ne modifie pas sa propre appartenance.");
    return this.tx(async (db) => {
      // Verrouille les propriétaires actifs : deux rétrogradations simultanées ne peuvent pas laisser l'organisation sans propriétaire.
      const owners = (await db.query("SELECT user_id FROM iam.memberships WHERE organization_id = $1 AND role = 'owner' AND status = 'active' FOR UPDATE", [actor.organizationId])).rows.map((r) => r.user_id);
      const target = (await db.query("SELECT role, status FROM iam.memberships WHERE organization_id = $1 AND user_id = $2 FOR UPDATE", [actor.organizationId, userId])).rows[0];
      if (!target) throw notFound();
      if ((target.role === "owner" || change.role === "owner") && actor.role !== "owner") throw forbidden("Réservé à un propriétaire.");
      const role = change.role ?? target.role, status = change.status ?? target.status;
      if (owners.includes(userId) && (role !== "owner" || status !== "active") && owners.length === 1) throw conflict("L'organisation doit conserver un propriétaire actif.");
      const { rows } = await db.query("UPDATE iam.memberships SET role = $3, status = $4 WHERE organization_id = $1 AND user_id = $2 RETURNING user_id, role, status", [actor.organizationId, userId, role, status]);
      // Perte d'accès ou changement de rôle : tous les jetons du membre sont révoqués.
      if (status !== "active" || role !== target.role) await db.query("UPDATE iam.access_tokens SET revoked_at = now() WHERE organization_id = $1 AND user_id = $2 AND revoked_at IS NULL", [actor.organizationId, userId]);
      await this.audit(db, actor.organizationId, actor.userId, "iam.membership.updated", "iam.memberships", userId);
      return rows[0];
    });
  }

  // ───────────── Invitations ─────────────
  createInvitation(actor: Actor, email: string, role: Exclude<Role, "owner">) {
    this.admin(actor);
    return this.tx(async (db) => {
      const token = generateToken();
      const { rows } = await db.query(
        `INSERT INTO iam.invitations (organization_id, email, role, token_hash, expires_at) VALUES ($1, $2, $3, $4, now() + ($5::int * interval '1 hour'))
         RETURNING id, email, role, expires_at, created_at`, [actor.organizationId, email, role, hashToken(token), this.opts.invitationTtlHours]);
      await this.audit(db, actor.organizationId, actor.userId, "iam.invitation.created", "iam.invitations", rows[0].id);
      return { ...rows[0], token }; // affiché une seule fois ; seul son SHA-256 est conservé
    });
  }
  async listInvitations(actor: Actor) {
    this.admin(actor);
    return (await this.pool.query("SELECT id, email, role, expires_at, accepted_at, revoked_at, created_at FROM iam.invitations WHERE organization_id = $1 ORDER BY created_at DESC LIMIT 500", [actor.organizationId])).rows;
  }
  revokeInvitation(actor: Actor, id: string) {
    this.admin(actor);
    return this.tx(async (db) => {
      const { rowCount } = await db.query("UPDATE iam.invitations SET revoked_at = now() WHERE organization_id = $1 AND id = $2 AND accepted_at IS NULL AND revoked_at IS NULL", [actor.organizationId, id]);
      if (!rowCount) throw notFound();
      await this.audit(db, actor.organizationId, actor.userId, "iam.invitation.revoked", "iam.invitations", id);
    });
  }

  private async userFor(db: Db, identity: VerifiedIdentity): Promise<string> {
    const known = (await db.query("SELECT user_id FROM iam.identities WHERE issuer = $1 AND subject = $2", [identity.issuer, identity.subject])).rows[0];
    if (known) return known.user_id;
    let user = (await db.query("SELECT id FROM iam.users WHERE lower(email) = $1", [identity.email])).rows[0];
    user ??= (await db.query("INSERT INTO iam.users (email, given_name, family_name) VALUES ($1, $2, $3) RETURNING id",
      [identity.email, identity.givenName ?? identity.email!.split("@")[0], identity.familyName ?? ""])).rows[0];
    await db.query("INSERT INTO iam.identities (user_id, issuer, subject) VALUES ($1, $2, $3)", [user.id, identity.issuer, identity.subject]);
    return user.id;
  }

  /** Acceptation : l'identité doit être vérifiée par le fournisseur et son e-mail vérifié doit être celui invité. */
  async acceptInvitation(invitationToken: string, idToken: string) {
    const identity = await this.verify(idToken);
    return this.tx(async (db) => {
      const inv = (await db.query(
        `SELECT i.id, i.organization_id, i.email, i.role FROM iam.invitations i JOIN core.organizations o ON o.id = i.organization_id AND o.status = 'active'
          WHERE i.token_hash = $1 AND i.accepted_at IS NULL AND i.revoked_at IS NULL AND i.expires_at > now() FOR UPDATE OF i`, [hashToken(invitationToken)])).rows[0];
      if (!inv || !identity.emailVerified || identity.email !== String(inv.email).toLowerCase()) throw unauthorized();
      const userId = await this.userFor(db, identity);
      if ((await db.query("SELECT 1 FROM iam.users WHERE id = $1 AND status = 'active'", [userId])).rowCount !== 1) throw unauthorized();
      const existing = (await db.query("SELECT status FROM iam.memberships WHERE organization_id = $1 AND user_id = $2 FOR UPDATE", [inv.organization_id, userId])).rows[0];
      if (existing?.status === "active") throw conflict("Cet utilisateur est déjà membre de l'organisation.");
      if (existing) await db.query("UPDATE iam.memberships SET role = $3, status = 'active' WHERE organization_id = $1 AND user_id = $2", [inv.organization_id, userId, inv.role]);
      else await db.query("INSERT INTO iam.memberships (organization_id, user_id, role) VALUES ($1, $2, $3)", [inv.organization_id, userId, inv.role]);
      await db.query("UPDATE iam.invitations SET accepted_at = now() WHERE id = $1", [inv.id]);
      await this.audit(db, inv.organization_id, userId, "iam.invitation.accepted", "iam.invitations", inv.id);
      return this.issue(db, inv.organization_id, userId, "session", ROLE_SCOPES[inv.role as Role], this.opts.sessionTtlHours * 3_600_000, "session", userId);
    });
  }

  // ───────────── Jetons et comptes de service (communications interservices) ─────────────
  async listTokens(actor: Actor) {
    this.admin(actor);
    return (await this.pool.query(`SELECT ${TOKEN_COLUMNS} FROM iam.access_tokens WHERE organization_id = $1 ORDER BY created_at DESC LIMIT 500`, [actor.organizationId])).rows;
  }
  createApiKey(actor: Actor, input: { user_id?: string; label: string; scopes: Permission[]; expires_in_days: number }) {
    this.admin(actor);
    return this.tx((db) => this.apiKey(db, actor.organizationId, input.user_id ?? actor.userId, input, actor.userId));
  }
  private async apiKey(db: Db, organizationId: string, userId: string, input: { label: string; scopes: Permission[]; expires_in_days: number }, actorUserId: string | null) {
    if (input.expires_in_days < 1 || input.expires_in_days > this.opts.apiKeyMaxDays) throw badRequest(`Durée de validité : 1 à ${this.opts.apiKeyMaxDays} jours.`);
    const member = (await db.query("SELECT role FROM iam.memberships WHERE organization_id = $1 AND user_id = $2 AND status = 'active'", [organizationId, userId])).rows[0];
    if (!member) throw unprocessable("Le titulaire doit être un membre actif de l'organisation.");
    const allowed = ROLE_SCOPES[member.role as Role];
    const scopes = [...new Set(input.scopes)];
    if (!scopes.length || scopes.some((s) => !allowed.includes(s))) throw unprocessable("Permissions demandées supérieures au rôle du titulaire.");
    return this.issue(db, organizationId, userId, "api_key", scopes, input.expires_in_days * 86_400_000, input.label, actorUserId);
  }
  revokeToken(actor: Actor, tokenId: string) {
    this.admin(actor);
    return this.tx(async (db) => { if (!(await this.revoke(db, actor.organizationId, tokenId, actor.userId))) throw notFound(); });
  }
  /** Compte technique sans identité de connexion : il ne peut agir que par clé API, dans cette organisation. */
  createServiceAccount(actor: Actor, name: string, role: Exclude<Role, "owner">) {
    this.admin(actor);
    return this.tx(async (db) => {
      const email = `svc-${randomBytes(8).toString("hex")}@service.invalid`;
      const user = (await db.query("INSERT INTO iam.users (email, given_name, family_name) VALUES ($1, 'Service', $2) RETURNING id", [email, name])).rows[0];
      await db.query("INSERT INTO iam.memberships (organization_id, user_id, role) VALUES ($1, $2, $3)", [actor.organizationId, user.id, role]);
      await this.audit(db, actor.organizationId, actor.userId, "iam.service_account.created", "iam.users", user.id);
      return { user_id: user.id, name, role };
    });
  }

  // ───────────── Amorçage et exploitation (CLI uniquement, jamais exposé en HTTP) ─────────────
  readonly platform = {
    listOrganizations: async () => (await this.pool.query("SELECT id, slug, name, status, created_at FROM core.organizations ORDER BY slug")).rows,
    createOrganization: (slug: string, name: string) => this.tx(async (db) => {
      const org = (await db.query("INSERT INTO core.organizations (slug, name) VALUES ($1, $2) RETURNING id, slug, name, status", [slug, name])).rows[0];
      await this.audit(db, org.id, null, "iam.organization.created", "core.organizations", org.id);
      return org;
    }),
    setOrganizationStatus: (slug: string, status: string) => this.tx(async (db) => {
      const org = (await db.query("UPDATE core.organizations SET status = $2, updated_at = now() WHERE slug = $1 RETURNING id, slug, status", [slug, status])).rows[0];
      if (!org) throw notFound();
      await this.audit(db, org.id, null, "iam.organization.status", "core.organizations", org.id);
      return org;
    }),
    setApplication: (slug: string, application: string, status: string) => this.tx(async (db) => {
      const org = await this.org(db, slug);
      const current = (await db.query("UPDATE core.organization_applications SET status = $3 WHERE organization_id = $1 AND application_code = $2 RETURNING application_code, status", [org, application, status])).rows[0];
      const row = current ?? (await db.query("INSERT INTO core.organization_applications (organization_id, application_code, status, starts_at) VALUES ($1, $2, $3, now()) RETURNING application_code, status", [org, application, status])).rows[0];
      await this.audit(db, org, null, "iam.application.status", "core.organization_applications", null);
      return row;
    }),
    createUser: async (email: string, givenName: string, familyName: string) =>
      (await this.pool.query("INSERT INTO iam.users (email, given_name, family_name) VALUES ($1, $2, $3) RETURNING id, email", [email.toLowerCase(), givenName, familyName])).rows[0],
    linkIdentity: async (email: string, issuer: string, subject: string) => {
      const user = await this.user(this.pool, email);
      return (await this.pool.query("INSERT INTO iam.identities (user_id, issuer, subject) VALUES ($1, $2, $3) RETURNING id, user_id, issuer", [user, issuer, subject])).rows[0];
    },
    setMembership: (slug: string, email: string, role: Role) => this.tx(async (db) => {
      const org = await this.org(db, slug), user = await this.user(db, email);
      const updated = (await db.query("UPDATE iam.memberships SET role = $3, status = 'active' WHERE organization_id = $1 AND user_id = $2 RETURNING user_id, role, status", [org, user, role])).rows[0];
      const row = updated ?? (await db.query("INSERT INTO iam.memberships (organization_id, user_id, role) VALUES ($1, $2, $3) RETURNING user_id, role, status", [org, user, role])).rows[0];
      await this.audit(db, org, null, "iam.membership.set", "iam.memberships", user);
      return row;
    }),
    issueApiKey: (slug: string, email: string, input: { label: string; scopes: Permission[]; expires_in_days: number }) =>
      this.tx(async (db) => this.apiKey(db, await this.org(db, slug), await this.user(db, email), input, null)),
    revokeToken: (tokenId: string) => this.tx(async (db) => {
      const row = (await db.query("SELECT organization_id FROM iam.access_tokens WHERE id = $1", [tokenId])).rows[0];
      if (!row || !(await this.revoke(db, row.organization_id, tokenId, null))) throw notFound();
    }),
  };
  private async org(db: Db | Pool, slug: string): Promise<string> {
    const row = (await db.query("SELECT id FROM core.organizations WHERE slug = $1", [slug])).rows[0];
    if (!row) throw notFound(); return row.id;
  }
  private async user(db: Db | Pool, email: string): Promise<string> {
    const row = (await db.query("SELECT id FROM iam.users WHERE lower(email) = $1", [email.toLowerCase()])).rows[0];
    if (!row) throw notFound(); return row.id;
  }
}
