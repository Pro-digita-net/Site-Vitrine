import { z } from "zod";
import { AppError, notFound } from "../../shared/errors.js";
import { transaction, type Pool } from "../../shared/db.js";
import { requirePermission, type Ctx } from "../context.js";
import { text } from "../resource.js";

// ───────────── Profil et organisation courante ─────────────
export const me = (ctx: Ctx) => ({ user_id: ctx.userId, organization_id: ctx.organizationId, permissions: [...ctx.permissions].sort() });

export async function currentOrganization(ctx: Ctx) {
  const { rows } = await ctx.db.query(
    `SELECT id, slug, name, legal_name, registration_number, country_code, timezone, locale, status, created_at, updated_at
       FROM core.organizations WHERE id = $1`, [ctx.organizationId]);
  if (!rows[0]) throw notFound();
  return rows[0];
}

// ───────────── Consentements : journal en ajout seul, via fonctions dédiées ─────────────
export const preferenceInput = z.strictObject({
  purpose: z.string().regex(/^[a-z][a-z0-9_.-]{1,63}$/), channel: z.enum(["email", "sms", "phone"]), allowed: z.boolean(),
  source: text(100), notice_version: text(50).nullable().optional(),
});
const PREFERENCE = "id, contact_id, purpose, channel, allowed, recorded_at, source, notice_version";

async function assertContact(ctx: Ctx, contactId: string) {
  const { rowCount } = await ctx.db.query("SELECT 1 FROM core.contacts WHERE organization_id = $1 AND id = $2", [ctx.organizationId, contactId]);
  if (!rowCount) throw notFound();
}
export async function listPreferences(ctx: Ctx, contactId: string) {
  requirePermission(ctx, "directory.read"); await assertContact(ctx, contactId);
  return (await ctx.db.query(`SELECT ${PREFERENCE} FROM web.list_communication_preferences($1)`, [contactId])).rows;
}
export async function recordPreference(ctx: Ctx, contactId: string, input: z.infer<typeof preferenceInput>) {
  requirePermission(ctx, "directory.write", "directory.read"); await assertContact(ctx, contactId);
  const { rows } = await ctx.db.query(`SELECT ${PREFERENCE} FROM web.record_communication_preference($1, $2, $3, $4, $5, $6)`,
    [contactId, input.purpose, input.channel, input.allowed, input.source, input.notice_version ?? null]);
  return rows[0];
}

// ───────────── Demandes du formulaire du site ProDigital ─────────────
/**
 * Lecture et relance des demandes du site vitrine. pd_core_api n'a aucun droit sur le schéma `site` :
 * ce service utilise une connexion distincte (compte pd_site_api), et seulement pour un membre
 * authentifié de l'organisation liée au site. Les autres organisations reçoivent 404.
 */
export class SiteContactService {
  private siteOrganization?: string;
  constructor(private pool: Pool | null) {}

  async authorize(ctx: Ctx, write = false) {
    requirePermission(ctx, "requests.read", ...(write ? ["requests.write" as const] : []));
    if (!this.pool) throw new AppError(503, "not_configured", "Accès aux demandes du site non configuré (SITE_DATABASE_URL).");
    this.siteOrganization ??= (await this.pool.query<{ id: string | null }>("SELECT iam.site_organization_id() AS id")).rows[0]?.id ?? undefined;
    if (!this.siteOrganization || this.siteOrganization !== ctx.organizationId) throw notFound();
    return this.pool;
  }

  async list(pool: Pool, limit: number, offset: number) {
    const { rows } = await pool.query(
      `SELECT s.id, s.created_at, s.given_name, s.family_name, s.email, s.company, s.subject, s.subject_group,
              (SELECT jsonb_object_agg(o.kind, o.status) FROM site.contact_operations o WHERE o.submission_id = s.id) AS operations
         FROM site.contact_submissions s ORDER BY s.created_at DESC, s.id LIMIT $1 OFFSET $2`, [limit + 1, offset]);
    return { data: rows.slice(0, limit), page: { limit, offset, has_more: rows.length > limit } };
  }

  async get(pool: Pool, id: string) {
    const submission = (await pool.query(
      `SELECT id, created_at, given_name, family_name, email, company, subject, subject_group, details, message, source
         FROM site.contact_submissions WHERE id = $1`, [id])).rows[0];
    if (!submission) throw notFound();
    const operations = (await pool.query(
      `SELECT kind, status, attempts, next_attempt_at, last_error, external_id, completed_at FROM site.contact_operations WHERE submission_id = $1 ORDER BY kind`, [id])).rows;
    const events = (await pool.query("SELECT at, kind, event, detail FROM site.contact_events WHERE submission_id = $1 ORDER BY at, id LIMIT 500", [id])).rows;
    return { ...submission, operations, events };
  }

  /** Relance des opérations abandonnées (failed) ; n'affecte ni les opérations réussies ni la demande, immuable. */
  retry(pool: Pool, id: string) {
    return transaction(pool, async (db) => {
      if (!(await db.query("SELECT 1 FROM site.contact_submissions WHERE id = $1", [id])).rowCount) throw notFound();
      const { rows } = await db.query<{ kind: string }>(
        `UPDATE site.contact_operations SET status = 'pending', next_attempt_at = clock_timestamp(), locked_until = NULL, updated_at = clock_timestamp()
          WHERE submission_id = $1 AND status = 'failed' RETURNING kind`, [id]);
      for (const row of rows) await db.query("INSERT INTO site.contact_events (submission_id, kind, event, detail) VALUES ($1, $2, 'manual_retry', 'Relance depuis l''API Core')", [id, row.kind]);
      return { requeued: rows.map((r) => r.kind) };
    });
  }
}
