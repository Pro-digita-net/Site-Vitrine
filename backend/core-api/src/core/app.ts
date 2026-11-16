import { Router } from "express";
import { z } from "zod";
import type { Config } from "../config.js";
import type { Pool } from "../shared/db.js";
import { baseApp, finishApp, Metrics, rateLimit } from "../shared/http.js";
import type { Logger } from "../shared/logger.js";
import { contextRunner, requirePermission } from "./context.js";
import { createWithIdempotency, idOf, resourceRouter, tokenOf } from "./controller.js";
import { buildOpenApi } from "./openapi.js";
import { resources } from "./resources/index.js";
import { currentOrganization, listPreferences, me, preferenceInput, recordPreference, SiteContactService } from "./services/special.js";

export interface CoreDeps { config: Config; pool: Pool; sitePool: Pool | null; log: Logger; metrics?: Metrics }

export function createCoreApp({ config, pool, sitePool, log, metrics = new Metrics() }: CoreDeps) {
  metrics.gauge(() => ({ pg_pool_total: pool.totalCount, pg_pool_idle: pool.idleCount, pg_pool_waiting: pool.waitingCount }));
  const app = baseApp({ log, metrics, trustProxy: config.trustProxy, metricsToken: config.metricsToken, ready: () => pool.query("SELECT 1") });
  const run = contextRunner(pool);
  const site = new SiteContactService(sitePool);
  const openapi = buildOpenApi(resources);
  const v1 = Router();

  // Par adresse cliente : faire varier de faux jetons ne contourne pas la limite.
  v1.use(rateLimit(config.rateLimit));
  v1.get("/openapi.json", (_req, res) => { res.json(openapi); });
  v1.get("/me", async (req, res) => { res.json({ data: await run(tokenOf(req), async (ctx) => me(ctx), true) }); });
  v1.get("/organization", async (req, res) => { res.json({ data: await run(tokenOf(req), currentOrganization, true) }); });

  for (const def of resources) v1.use(`/${def.name}`, resourceRouter(def, run));

  v1.get("/contacts/:id/communication-preferences", async (req, res) => {
    const id = idOf(req);
    res.json({ data: await run(tokenOf(req), (ctx) => listPreferences(ctx, id), true) });
  });
  v1.post("/contacts/:id/communication-preferences", async (req, res) => {
    const id = idOf(req); const input = preferenceInput.parse(req.body);
    const out = await createWithIdempotency(run, req, `POST /contacts/${id}/communication-preferences`, input, (ctx) => requirePermission(ctx, "directory.write", "directory.read"), (ctx) => recordPreference(ctx, id, input));
    res.status(out.status).json(out.body);
  });

  const paging = z.strictObject({ limit: z.coerce.number().int().min(1).max(100).default(25), offset: z.coerce.number().int().min(0).max(100_000).default(0) });
  v1.get("/site/contact-submissions", async (req, res) => {
    const { limit, offset } = paging.parse(req.query);
    const sitePool_ = await run(tokenOf(req), (ctx) => site.authorize(ctx), true);
    res.json(await site.list(sitePool_, limit, offset));
  });
  v1.get("/site/contact-submissions/:id", async (req, res) => {
    const id = idOf(req);
    res.json({ data: await site.get(await run(tokenOf(req), (ctx) => site.authorize(ctx), true), id) });
  });
  v1.post("/site/contact-submissions/:id/retry", async (req, res) => {
    const id = idOf(req);
    res.json({ data: await site.retry(await run(tokenOf(req), (ctx) => site.authorize(ctx, true), true), id) });
  });

  app.use("/api/v1", v1);
  return finishApp(app, log);
}
