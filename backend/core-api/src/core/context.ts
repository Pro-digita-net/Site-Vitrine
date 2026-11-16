import { forbidden, unauthorized } from "../shared/errors.js";
import { transaction, type Db, type Pool } from "../shared/db.js";
import type { Permission } from "../shared/tokens.js";

/** Contexte vérifié par PostgreSQL pour la durée d'une transaction. Jamais construit à partir d'un identifiant client. */
export interface Ctx { db: Db; userId: string; organizationId: string; permissions: ReadonlySet<Permission> }

export const requirePermission = (ctx: Ctx, ...needed: Permission[]) => {
  for (const p of needed) if (!ctx.permissions.has(p)) throw forbidden(`Permission requise : ${p}.`);
};

export type Run = <T>(token: string, fn: (ctx: Ctx) => Promise<T>, readOnly?: boolean) => Promise<T>;

/**
 * Ouvre une transaction, y positionne le jeton en local (`set_config(..., true)` : effacé au
 * COMMIT/ROLLBACK, donc aucune fuite entre requêtes du pool), puis laisse la base dériver
 * l'utilisateur, l'organisation et les permissions. Les politiques RLS s'appuient sur ce même contexte.
 */
export const contextRunner = (pool: Pool): Run => (token, fn, readOnly = false) =>
  transaction(pool, async (db) => {
    await db.query("SELECT pg_catalog.set_config('app.access_token', $1, true)", [token]);
    const { rows } = await db.query<{ user_id: string | null; organization_id: string | null; permissions: Permission[] }>(
      `SELECT iam.current_user_id() AS user_id, iam.current_organization_id() AS organization_id,
              ARRAY(SELECT p::text FROM unnest(enum_range(NULL::iam.permission)) AS p WHERE iam.permitted(p)) AS permissions`);
    const row = rows[0];
    if (!row?.user_id || !row.organization_id) throw unauthorized();
    return fn({ db, userId: row.user_id, organizationId: row.organization_id, permissions: new Set(row.permissions) });
  }, readOnly);
