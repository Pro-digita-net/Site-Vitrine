import { createHash } from "node:crypto";
import { AppError, badRequest, conflict, forbidden, notFound } from "../shared/errors.js";
import { requirePermission, type Ctx } from "./context.js";
import { ResourceRepository, type ListQuery } from "./repository.js";
import type { ResourceDef, Row } from "./resource.js";

/**
 * Couche métier d'une ressource : permissions, règles, version. Réutilisable hors HTTP
 * (autres SaaS, agents) dès lors qu'un contexte vérifié est fourni.
 */
export class ResourceService {
  readonly repo: ResourceRepository;
  constructor(readonly def: ResourceDef) { this.repo = new ResourceRepository(def); }

  private canRead(ctx: Ctx) { if (this.def.read) requirePermission(ctx, this.def.read); }
  canWrite(ctx: Ctx) {
    if (!this.def.write) throw forbidden();
    // Une écriture relit la ligne (RETURNING) : la base exige aussi le droit de lecture.
    requirePermission(ctx, this.def.write); this.canRead(ctx);
  }

  async list(ctx: Ctx, query: ListQuery) {
    this.canRead(ctx);
    const { rows, hasMore } = await this.repo.list(ctx.db, ctx.organizationId, query);
    return { data: rows, page: { limit: query.limit, offset: query.offset, has_more: hasMore } };
  }

  async get(ctx: Ctx, id: string): Promise<Row> {
    this.canRead(ctx);
    const row = await this.repo.get(ctx.db, ctx.organizationId, id);
    if (!row) throw notFound(); // inexistant ou hors organisation : même réponse
    return row;
  }

  async create(ctx: Ctx, input: Row): Promise<Row> {
    this.canWrite(ctx);
    const values = this.def.hooks?.beforeCreate ? await this.def.hooks.beforeCreate(ctx, input) : input;
    const row = await this.repo.insert(ctx.db, values);
    await this.def.hooks?.afterCreate?.(ctx, row);
    return row;
  }

  async update(ctx: Ctx, id: string, version: string, input: Row): Promise<Row> {
    this.canWrite(ctx);
    if (!Object.keys(input).length) throw badRequest("Aucun champ à modifier.");
    const row = await this.repo.update(ctx.db, ctx.organizationId, id, version, input);
    if (row) return row;
    if (!(await this.repo.get(ctx.db, ctx.organizationId, id))) throw notFound();
    throw new AppError(412, "version_mismatch", "La ressource a été modifiée depuis sa lecture : la relire puis réessayer.");
  }

  async setArchived(ctx: Ctx, id: string, archived: boolean): Promise<Row> {
    this.canWrite(ctx);
    if (!this.def.archive) throw forbidden();
    const row = await this.repo.setArchived(ctx.db, ctx.organizationId, id, archived);
    if (!row) throw notFound();
    return row;
  }
}

const canonical = (value: unknown): string =>
  value && typeof value === "object" && !Array.isArray(value)
    ? `{${Object.keys(value).sort().map((k) => `${JSON.stringify(k)}:${canonical((value as Row)[k])}`).join(",")}}`
    : Array.isArray(value) ? `[${value.map(canonical).join(",")}]` : JSON.stringify(value) ?? "null";

export const IDEMPOTENCY_KEY = /^[A-Za-z0-9._:-]{8,128}$/;

/**
 * Idempotence d'une création, dans la transaction de la création elle-même :
 * même clé + même contenu → réponse d'origine ; même clé + autre contenu → 409.
 * Deux envois simultanés : le second échoue sur la clé primaire, est annulé, puis rejoué en lecture.
 */
export async function idempotent(ctx: Ctx, key: string | undefined, scope: string, input: unknown, fn: () => Promise<Row>): Promise<{ status: number; body: Row; replayed: boolean }> {
  if (!key) return { status: 201, body: { data: await fn() }, replayed: false };
  const hash = createHash("sha256").update(`${scope}\n${canonical(input)}`).digest("hex");
  const { rows } = await ctx.db.query<{ scope: string; request_hash: string; status_code: number; response: Row }>(
    "SELECT scope, request_hash, status_code, response FROM core.idempotency_keys WHERE organization_id = $1 AND key = $2", [ctx.organizationId, key]);
  const previous = rows[0];
  if (previous) {
    if (previous.request_hash !== hash || previous.scope !== scope) throw conflict("Cette clé d'idempotence a déjà servi pour une autre requête.", "idempotency_conflict");
    return { status: previous.status_code, body: previous.response, replayed: true };
  }
  const body = { data: await fn() };
  await ctx.db.query("INSERT INTO core.idempotency_keys (key, scope, request_hash, status_code, response) VALUES ($1, $2, $3, 201, $4::jsonb)",
    [key, scope, hash, JSON.stringify(body)]);
  return { status: 201, body, replayed: false };
}
export const isIdempotencyRace = (error: unknown) =>
  (error as { code?: string })?.code === "23505" && (error as { constraint?: string })?.constraint === "idempotency_keys_pkey";
