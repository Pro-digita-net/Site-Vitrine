import { Router, type Request } from "express";
import { z } from "zod";
import { AppError, badRequest, unauthorized } from "../shared/errors.js";
import { bearer } from "../shared/tokens.js";
import type { Ctx, Run } from "./context.js";
import { uuid, type ResourceDef, type Row } from "./resource.js";
import { IDEMPOTENCY_KEY, idempotent, isIdempotencyRace, ResourceService } from "./service.js";

export const tokenOf = (req: Request) => { const token = bearer(req.get("authorization")); if (!token) throw unauthorized(); return token; };
export const idOf = (req: Request, name = "id") => uuid.parse(req.params[name]);

export function idempotencyKey(req: Request): string | undefined {
  const key = req.get("idempotency-key");
  if (key !== undefined && !IDEMPOTENCY_KEY.test(key)) throw badRequest("En-tête Idempotency-Key invalide (8 à 128 caractères [A-Za-z0-9._:-]).");
  return key;
}

function versionOf(req: Request): string {
  const match = /^"?(\d{1,20})"?$/.exec(req.get("if-match") ?? "");
  if (!match) throw new AppError(428, "precondition_required", "En-tête If-Match requis : fournir la version lue (champ version).");
  return match[1]!;
}

export function listQuerySchema(def: ResourceDef) {
  const sorts = def.sorts.flatMap((s) => [s, `-${s}`]) as [string, ...string[]];
  return z.strictObject({
    limit: z.coerce.number().int().min(1).max(100).default(25),
    offset: z.coerce.number().int().min(0).max(100_000).default(0),
    sort: z.enum(sorts).default(def.defaultSort),
    ...(def.search ? { q: z.string().trim().min(1).max(100).optional() } : {}),
    ...(def.archive?.active ? { archived: z.enum(["false", "true", "all"]).default("false") } : {}),
    ...Object.fromEntries(Object.entries(def.filters ?? {}).map(([name, f]) => [name, f.schema.optional()])),
  });
}

/** Création idempotente : un envoi concurrent de la même clé est rejoué en lecture après annulation. */
export async function createWithIdempotency(run: Run, req: Request, scope: string, input: unknown, guard: (ctx: Ctx) => void, fn: (ctx: Ctx) => Promise<Row>) {
  const token = tokenOf(req); const key = idempotencyKey(req);
  const attempt = () => run(token, (ctx) => { guard(ctx); return idempotent(ctx, key, scope, input, () => fn(ctx)); });
  try { return await attempt(); } catch (error) { if (!isIdempotencyRace(error)) throw error; return attempt(); }
}

/** Routes et contrôleurs d'une ressource : uniquement les opérations déclarées par sa définition. */
export function resourceRouter(def: ResourceDef, run: Run): Router {
  const router = Router();
  const service = new ResourceService(def);
  const query = listQuerySchema(def);

  router.get("/", async (req, res) => {
    const { limit, offset, sort, q, archived, ...filters } = query.parse(req.query) as Row & { limit: number; offset: number; sort: string };
    res.json(await run(tokenOf(req), (ctx) => service.list(ctx, { limit, offset, sort, q: q as string | undefined, archived: archived as never, filters }), true));
  });
  if (def.byId !== false) router.get("/:id", async (req, res) => {
    const id = idOf(req);
    const row = await run(tokenOf(req), (ctx) => service.get(ctx, id), true);
    if (row.version) res.setHeader("ETag", `"${String(row.version)}"`);
    res.json({ data: row });
  });
  if (def.create) router.post("/", async (req, res) => {
    const input = def.create!.parse(req.body);
    const out = await createWithIdempotency(run, req, `POST /${def.name}`, input, (ctx) => service.canWrite(ctx), (ctx) => service.create(ctx, input));
    if (out.replayed) res.setHeader("Idempotency-Replayed", "true");
    res.status(out.status).json(out.body);
  });
  if (def.update) router.patch("/:id", async (req, res) => {
    const id = idOf(req); const version = versionOf(req); const input = def.update!.parse(req.body);
    res.json({ data: await run(tokenOf(req), (ctx) => service.update(ctx, id, version, input)) });
  });
  if (def.archive && def.write) {
    for (const [action, archived] of [["archive", true], ["restore", false]] as const) router.post(`/:id/${action}`, async (req, res) => {
      const id = idOf(req);
      res.json({ data: await run(tokenOf(req), (ctx) => service.setArchived(ctx, id, archived)) });
    });
  }
  return router;
}
