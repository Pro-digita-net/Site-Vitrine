import { z } from "zod";
import { PERMISSIONS } from "../shared/tokens.js";
import { listQuerySchema } from "./controller.js";
import type { ResourceDef } from "./resource.js";
import { preferenceInput } from "./services/special.js";

const json = (schema: z.ZodType) => z.toJSONSchema(schema, { io: "input", unrepresentable: "any", target: "openapi-3.0" }) as Record<string, unknown>;
const ref = (name: string) => ({ $ref: `#/components/schemas/${name}` });
const body = (schema: unknown) => ({ required: true, content: { "application/json": { schema } } });
const ok = (schema: unknown, description = "Succès") => ({ description, content: { "application/json": { schema } } });
const ERRORS = Object.fromEntries([[400, "Requête invalide"], [401, "Jeton absent, invalide, expiré ou révoqué"], [403, "Permission insuffisante"],
  [404, "Introuvable ou hors organisation"], [409, "Conflit"], [422, "Règle du référentiel non respectée"], [429, "Trop de requêtes"]]
  .map(([code, description]) => [code, { description, content: { "application/json": { schema: ref("Error") } } }]));
const idParam = { name: "id", in: "path", required: true, schema: { type: "string", format: "uuid" } };
const pascal = (name: string) => name.replace(/(^|-)([a-z])/g, (_m, _d, c: string) => c.toUpperCase());

/** Document OpenAPI 3 dérivé des définitions de ressources : la documentation ne peut pas diverger du code. */
export function buildOpenApi(resources: ResourceDef[]) {
  const paths: Record<string, unknown> = {};
  const schemas: Record<string, unknown> = {
    Error: { type: "object", required: ["error"], properties: { error: { type: "object", required: ["code", "message", "request_id"],
      properties: { code: { type: "string" }, message: { type: "string" }, details: {}, request_id: { type: "string" } } } } },
    Page: { type: "object", properties: { limit: { type: "integer" }, offset: { type: "integer" }, has_more: { type: "boolean" } } },
  };
  for (const def of resources) {
    const name = pascal(def.name);
    const perms = (write: boolean) => `Permissions : ${[def.read, write ? def.write : null].filter(Boolean).join(" + ") || "jeton valide"}.`;
    schemas[name] = { type: "object", properties: Object.fromEntries([...def.columns, ...(def.columns.includes("updated_at") ? ["version"] : [])].map((c) => [c, {}])) };
    const query = json(listQuerySchema(def)) as { properties?: Record<string, unknown> };
    const collection: Record<string, unknown> = { get: { tags: [def.tag], summary: `Lister — ${def.title}`, description: perms(false),
      parameters: Object.entries(query.properties ?? {}).map(([n, schema]) => ({ name: n, in: "query", schema })),
      responses: { 200: ok({ type: "object", properties: { data: { type: "array", items: ref(name) }, page: ref("Page") } }), ...ERRORS } } };
    const item: Record<string, unknown> = {};
    if (def.byId !== false) item.get = { tags: [def.tag], summary: `Lire — ${def.title}`, description: perms(false), parameters: [idParam], responses: { 200: ok({ type: "object", properties: { data: ref(name) } }), ...ERRORS } };
    if (def.create) {
      schemas[`${name}Create`] = json(def.create);
      collection.post = { tags: [def.tag], summary: `Créer — ${def.title}`, description: perms(true),
        parameters: [{ name: "Idempotency-Key", in: "header", schema: { type: "string", pattern: "^[A-Za-z0-9._:-]{8,128}$" }, description: "Rejoue la réponse d'origine pour un même contenu ; 409 si le contenu diffère." }],
        requestBody: body(ref(`${name}Create`)), responses: { 201: ok({ type: "object", properties: { data: ref(name) } }, "Créé"), ...ERRORS } };
    }
    if (def.update) {
      schemas[`${name}Update`] = json(def.update);
      item.patch = { tags: [def.tag], summary: `Modifier — ${def.title}`, description: perms(true),
        parameters: [idParam, { name: "If-Match", in: "header", required: true, schema: { type: "string" }, description: "Version lue (champ version). 412 si la ressource a changé, 428 si absent." }],
        requestBody: body(ref(`${name}Update`)), responses: { 200: ok({ type: "object", properties: { data: ref(name) } }), 412: { description: "Version périmée" }, 428: { description: "If-Match requis" }, ...ERRORS } };
    }
    paths[`/${def.name}`] = collection;
    if (Object.keys(item).length) paths[`/${def.name}/{id}`] = item;
    if (def.archive && def.write) for (const action of ["archive", "restore"])
      paths[`/${def.name}/{id}/${action}`] = { post: { tags: [def.tag], summary: `${action === "archive" ? "Archiver" : "Restaurer"} — ${def.title}`, description: `${perms(true)} Aucune suppression physique n'existe.`,
        parameters: [idParam], responses: { 200: ok({ type: "object", properties: { data: ref(name) } }), ...ERRORS } } };
  }
  schemas.CommunicationPreferenceCreate = json(preferenceInput);
  const simple = (tag: string, summary: string, description: string, extra: Record<string, unknown> = {}) => ({ tags: [tag], summary, description, responses: { 200: ok({ type: "object" }), ...ERRORS }, ...extra });
  Object.assign(paths, {
    "/me": { get: simple("iam", "Contexte du jeton", "Utilisateur, organisation et permissions effectives, dérivés du jeton par PostgreSQL.") },
    "/organization": { get: simple("core", "Organisation courante", "Lecture seule.") },
    "/contacts/{id}/communication-preferences": {
      get: simple("web", "Historique des préférences de communication", "Permission : directory.read. Journal en ajout seul.", { parameters: [idParam] }),
      post: simple("web", "Enregistrer une préférence", "Permissions : directory.read + directory.write. Ni modification ni suppression.", { parameters: [idParam], requestBody: body(ref("CommunicationPreferenceCreate")) }),
    },
    "/site/contact-submissions": { get: simple("site", "Demandes du formulaire du site", "Réservé aux membres de l'organisation liée au site (requests.read) ; 404 pour les autres.") },
    "/site/contact-submissions/{id}": { get: simple("site", "Demande, opérations e-mail/CRM et historique", "Lecture seule : la demande est immuable.", { parameters: [idParam] }) },
    "/site/contact-submissions/{id}/retry": { post: simple("site", "Relancer les opérations en échec", "Permissions : requests.read + requests.write.", { parameters: [idParam] }) },
  });
  return {
    openapi: "3.0.3",
    info: { title: "ProDigital Core API", version: "1.0.0", description: "API REST multi-entreprises. Authentification par jeton opaque (Bearer) émis par le service IAM. Isolation par Row-Level Security PostgreSQL. Aucune suppression physique." },
    servers: [{ url: "/api/v1" }],
    security: [{ bearer: [] }],
    components: { securitySchemes: { bearer: { type: "http", scheme: "bearer", description: `Jeton opaque. Permissions possibles : ${PERMISSIONS.join(", ")}.` } }, schemas },
    paths,
  };
}
