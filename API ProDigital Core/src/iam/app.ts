import { Router, type Request } from "express";
import { z } from "zod";
import type { Config } from "../config.js";
import type { Pool } from "../shared/db.js";
import { baseApp, finishApp, Metrics, rateLimit } from "../shared/http.js";
import type { Logger } from "../shared/logger.js";
import { bearer, PERMISSIONS } from "../shared/tokens.js";
import { createOidcVerifier, type IdentityVerifier } from "./oidc.js";
import { IamService } from "./service.js";

const uuid = z.uuid();
const jwt = z.string().min(20).max(8192);
const opaque = z.string().regex(/^[A-Za-z0-9_-]{43,128}$/);
const invitedRole = z.enum(["admin", "editor", "viewer"]);
const schemas = {
  login: z.strictObject({ id_token: jwt, organization: z.string().regex(/^[a-z0-9][a-z0-9-]{1,62}$/).optional() }),
  member: z.strictObject({ role: z.enum(["owner", "admin", "editor", "viewer"]).optional(), status: z.enum(["active", "suspended", "revoked"]).optional() })
    .refine((v) => v.role || v.status, { message: "Fournir role ou status." }),
  invitation: z.strictObject({ email: z.email().max(254).transform((v) => v.toLowerCase()), role: invitedRole }),
  accept: z.strictObject({ invitation_token: opaque, id_token: jwt }),
  apiKey: z.strictObject({ user_id: uuid.optional(), label: z.string().trim().min(1).max(100), scopes: z.array(z.enum(PERMISSIONS)).min(1).max(PERMISSIONS.length), expires_in_days: z.number().int().min(1).max(3650) }),
  serviceAccount: z.strictObject({ name: z.string().trim().min(1).max(100), role: invitedRole }),
};

export interface IamDeps { config: Config; pool: Pool; log: Logger; metrics?: Metrics; verifier?: IdentityVerifier }

/** Service IAM : émission et révocation des accès. Processus et compte PostgreSQL distincts de l'API métier. */
export function createIamApp({ config, pool, log, metrics = new Metrics(), verifier }: IamDeps) {
  const iam = new IamService(pool, verifier ?? createOidcVerifier(config.iam.oidc), config.iam);
  const app = baseApp({ log, metrics, trustProxy: config.trustProxy, metricsToken: config.metricsToken, ready: () => pool.query("SELECT 1"), bodyLimit: "16kb" });
  const actor = (req: Request) => iam.authenticate(bearer(req.get("authorization")));
  const v1 = Router();
  // Limite stricte, par adresse, sur les points d'entrée non authentifiés.
  const strict = rateLimit({ windowMs: config.rateLimit.windowMs, max: config.rateLimit.authMax });
  v1.use(rateLimit(config.rateLimit));

  v1.post("/sessions", strict, async (req, res) => {
    const input = schemas.login.parse(req.body);
    res.status(201).json({ data: await iam.login(input.id_token, input.organization) });
  });
  v1.delete("/sessions/current", async (req, res) => { await iam.logout(await actor(req)); res.status(204).end(); });

  v1.get("/members", async (req, res) => { res.json({ data: await iam.listMembers(await actor(req)) }); });
  v1.patch("/members/:userId", async (req, res) => {
    const userId = uuid.parse(req.params.userId); const input = schemas.member.parse(req.body);
    res.json({ data: await iam.updateMember(await actor(req), userId, input) });
  });

  v1.get("/invitations", async (req, res) => { res.json({ data: await iam.listInvitations(await actor(req)) }); });
  v1.post("/invitations", async (req, res) => {
    const input = schemas.invitation.parse(req.body);
    res.status(201).json({ data: await iam.createInvitation(await actor(req), input.email, input.role) });
  });
  v1.post("/invitations/accept", strict, async (req, res) => {
    const input = schemas.accept.parse(req.body);
    res.status(201).json({ data: await iam.acceptInvitation(input.invitation_token, input.id_token) });
  });
  v1.delete("/invitations/:id", async (req, res) => { const id = uuid.parse(req.params.id); await iam.revokeInvitation(await actor(req), id); res.status(204).end(); });

  v1.get("/tokens", async (req, res) => { res.json({ data: await iam.listTokens(await actor(req)) }); });
  v1.post("/api-keys", async (req, res) => {
    const input = schemas.apiKey.parse(req.body);
    res.status(201).json({ data: await iam.createApiKey(await actor(req), input) });
  });
  v1.delete("/tokens/:id", async (req, res) => { const id = uuid.parse(req.params.id); await iam.revokeToken(await actor(req), id); res.status(204).end(); });
  v1.post("/service-accounts", async (req, res) => {
    const input = schemas.serviceAccount.parse(req.body);
    res.status(201).json({ data: await iam.createServiceAccount(await actor(req), input.name, input.role) });
  });

  app.use("/iam/v1", v1);
  return { app: finishApp(app, log), iam };
}
