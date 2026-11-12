import { randomUUID } from "node:crypto";
import { z } from "zod";
import { unprocessable } from "../../shared/errors.js";
import { country, defineResource, email, optional, phone, text, uuid, type ResourceDef } from "../resource.js";

/*
 * MATRICE D'ACCÈS (issue des GRANT et politiques de prodigital-core.sql — voir README) :
 * les ressources ci-dessous n'exposent que ce que pd_core_api peut réellement faire.
 * Aucune suppression : le SQL n'accorde ni DELETE ni TRUNCATE.
 */
const TIMES = ["created_at", "updated_at"] as const;
const ARCHIVED_AT = { set: "archived_at = COALESCE(archived_at, now())", unset: "archived_at = NULL", active: "archived_at IS NULL" };
const url = z.url({ protocol: /^https?$/ }).max(500);

// ───────────── core : annuaire (directory.read / directory.write) ─────────────
const company = { name: text(200), kind: z.enum(["prospect", "customer", "supplier", "partner", "other"]).optional(),
  legal_name: optional(text(200)), registration_number: optional(text(50)), email: optional(email), phone: optional(phone), website: optional(url) };
const companies = defineResource({
  name: "companies", table: "core.companies", tag: "core", title: "Entreprises du carnet d'adresses",
  read: "directory.read", write: "directory.write",
  columns: ["id", "name", "kind", "legal_name", "registration_number", "email", "phone", "website", "archived_at", ...TIMES],
  create: z.strictObject(company), update: z.strictObject(company).partial(),
  filters: { kind: { column: "kind", schema: company.kind } }, search: ["name", "legal_name", "email"],
  sorts: ["name", "created_at", "updated_at"], defaultSort: "name", archive: ARCHIVED_AT,
});

const contact = { given_name: text(80), family_name: text(80), email: optional(email), phone: optional(phone), job_title: optional(text(120)) };
const contacts = defineResource({
  name: "contacts", table: "core.contacts", tag: "core", title: "Contacts",
  read: "directory.read", write: "directory.write",
  columns: ["id", "given_name", "family_name", "email", "phone", "job_title", "archived_at", ...TIMES],
  create: z.strictObject(contact), update: z.strictObject(contact).partial(),
  filters: { email: { column: "email", schema: email } }, search: ["given_name", "family_name", "email"],
  sorts: ["family_name", "given_name", "created_at", "updated_at"], defaultSort: "family_name", archive: ARCHIVED_AT,
});

const companyContacts = defineResource({
  name: "company-contacts", table: "core.company_contacts", tag: "core", title: "Rattachements contact ↔ entreprise",
  read: "directory.read", write: "directory.write",
  columns: ["id", "company_id", "contact_id", "relationship", ...TIMES],
  create: z.strictObject({ company_id: uuid, contact_id: uuid, relationship: optional(text(100)) }),
  update: z.strictObject({ relationship: optional(text(100)) }),
  filters: { company_id: { column: "company_id", schema: uuid }, contact_id: { column: "contact_id", schema: uuid } },
  sorts: ["created_at"], defaultSort: "-created_at",
});

const address = { label: text(50).optional(), line1: text(200), line2: optional(text(200)), postal_code: optional(text(20)), city: text(120), country_code: country };
const addresses = defineResource({
  name: "addresses", table: "core.addresses", tag: "core", title: "Adresses (d'une entreprise ou d'un contact)",
  read: "directory.read", write: "directory.write",
  columns: ["id", "company_id", "contact_id", "label", "line1", "line2", "postal_code", "city", "country_code", ...TIMES],
  create: z.strictObject({ company_id: uuid.optional(), contact_id: uuid.optional(), ...address })
    .refine((v) => Number(!!v.company_id) + Number(!!v.contact_id) === 1, { message: "Fournir company_id ou contact_id, pas les deux." }) as never,
  update: z.strictObject(address).partial(),
  filters: { company_id: { column: "company_id", schema: uuid }, contact_id: { column: "contact_id", schema: uuid } },
  sorts: ["created_at", "city"], defaultSort: "-created_at",
});

const teams = defineResource({
  name: "teams", table: "core.teams", tag: "core", title: "Équipes",
  read: "directory.read", write: "directory.write",
  columns: ["id", "name", "archived_at", ...TIMES],
  create: z.strictObject({ name: text(120) }), update: z.strictObject({ name: text(120) }).partial(),
  search: ["name"], sorts: ["name", "created_at"], defaultSort: "name", archive: ARCHIVED_AT,
});

const teamMembers = defineResource({
  name: "team-members", table: "core.team_members", tag: "core", title: "Membres d'équipe (utilisateurs membres de l'organisation)",
  read: "directory.read", write: "directory.write",
  columns: ["id", "team_id", "user_id", ...TIMES],
  create: z.strictObject({ team_id: uuid, user_id: uuid }),
  filters: { team_id: { column: "team_id", schema: uuid }, user_id: { column: "user_id", schema: uuid } },
  sorts: ["created_at"], defaultSort: "-created_at",
});

// ───────────── core : plateforme, lecture seule (SELECT uniquement dans le SQL) ─────────────
const applications = defineResource({
  name: "applications", table: "core.applications", tag: "core", title: "Applications de la plateforme (lecture seule)",
  read: null, columns: ["code", "name", "active"], orgScoped: false, byId: false, sorts: ["code"], defaultSort: "code", tiebreak: "code",
});
const applicationPlans = defineResource({
  name: "application-plans", table: "core.application_plans", tag: "core", title: "Offres publiées (lecture seule)",
  read: null, columns: ["application_code", "code", "name", "limits", "published"], orgScoped: false, byId: false,
  filters: { application_code: { column: "application_code", schema: text(50) } },
  sorts: ["application_code", "name"], defaultSort: "application_code", tiebreak: "application_code, code",
});
const subscriptions = defineResource({
  name: "subscriptions", table: "core.subscriptions", tag: "core", title: "Abonnements de l'organisation (lecture seule)",
  read: null, columns: ["id", "application_code", "plan_code", "status", "starts_at", "ends_at", ...TIMES],
  filters: { application_code: { column: "application_code", schema: text(50) },
    status: { column: "status", schema: z.enum(["pending", "trialing", "active", "past_due", "suspended", "cancelled", "ended"]) } },
  sorts: ["starts_at", "created_at"], defaultSort: "-starts_at",
});
const organizationApplications = defineResource({
  name: "organization-applications", table: "core.organization_applications", tag: "core", title: "Applications activées (lecture seule)",
  read: null, columns: ["application_code", "status", "starts_at", "ends_at"], byId: false,
  sorts: ["application_code"], defaultSort: "application_code", tiebreak: "application_code",
});

// ───────────── catalog (catalog.read / catalog.write) ─────────────
const offering = { slug: z.string().regex(/^[a-z0-9][a-z0-9-]{1,80}$/), name: text(200), kind: z.enum(["service", "course", "software"]),
  description: z.string().trim().max(10_000).optional(), status: z.enum(["draft", "published", "archived"]).optional() };
const offerings = defineResource({
  name: "offerings", table: "catalog.offerings", tag: "catalog", title: "Offres : prestations, formations, logiciels",
  read: "catalog.read", write: "catalog.write",
  columns: ["id", "slug", "name", "kind", "description", "status", ...TIMES],
  create: z.strictObject(offering), update: z.strictObject({ slug: offering.slug, name: offering.name, description: offering.description, status: offering.status }).partial(),
  filters: { kind: { column: "kind", schema: offering.kind }, status: { column: "status", schema: z.enum(["draft", "published", "archived"]) } },
  search: ["name", "slug"], sorts: ["name", "created_at", "updated_at"], defaultSort: "name",
  archive: { set: "status = 'archived'", unset: "status = 'draft'" },
});

const course = { objectives: optional(z.string().trim().max(5000)), prerequisites: optional(z.string().trim().max(5000)),
  level: optional(text(50)), duration_minutes: optional(z.number().int().min(1).max(1_000_000)) };
const courses = defineResource({
  name: "courses", table: "catalog.courses", tag: "catalog", title: "Descriptifs de formation (une par offre de type course)",
  read: "catalog.read", write: "catalog.write",
  columns: ["id", "offering_id", "objectives", "prerequisites", "level", "duration_minutes", ...TIMES],
  create: z.strictObject({ offering_id: uuid, ...course }), update: z.strictObject(course).partial(),
  filters: { offering_id: { column: "offering_id", schema: uuid } }, sorts: ["created_at"], defaultSort: "-created_at",
  hooks: { async beforeCreate(ctx, input) {
    const { rows } = await ctx.db.query<{ kind: string }>("SELECT kind FROM catalog.offerings WHERE organization_id = $1 AND id = $2", [ctx.organizationId, input.offering_id]);
    if (rows[0]?.kind !== "course") throw unprocessable("L'offre référencée doit exister et être de type course.");
    return input;
  } },
});

const courseModule = { position: z.number().int().min(1).max(10_000), title: text(200), content: z.string().trim().max(50_000).optional() };
const courseModules = defineResource({
  name: "course-modules", table: "catalog.course_modules", tag: "catalog", title: "Modules d'une formation",
  read: "catalog.read", write: "catalog.write",
  columns: ["id", "course_id", "position", "title", "content", ...TIMES],
  create: z.strictObject({ course_id: uuid, ...courseModule }), update: z.strictObject(courseModule).partial(),
  filters: { course_id: { column: "course_id", schema: uuid } }, sorts: ["position", "created_at"], defaultSort: "position",
});

// ───────────── documents : métadonnées uniquement (documents.read / documents.write) ─────────────
const files = defineResource({
  name: "files", table: "documents.files", tag: "documents", title: "Métadonnées de fichiers privés (le contenu vit dans le stockage externe)",
  read: "documents.read", write: "documents.write",
  columns: ["id", "name", "media_type", "storage_key", "size_bytes", "sha256", "archived_at", ...TIMES],
  create: z.strictObject({ name: text(255), media_type: z.string().regex(/^[a-z0-9][a-z0-9.+-]{0,62}\/[a-z0-9][a-z0-9.+-]{0,62}$/),
    size_bytes: z.number().int().min(0).max(Number.MAX_SAFE_INTEGER), sha256: optional(z.string().regex(/^[a-f0-9]{64}$/)) }),
  update: z.strictObject({ name: text(255) }).partial(),
  search: ["name"], sorts: ["name", "created_at", "size_bytes"], defaultSort: "-created_at", archive: ARCHIVED_AT,
  // La clé de stockage est générée par le serveur, préfixée par l'organisation : jamais choisie par le client.
  hooks: { beforeCreate: (ctx, input) => ({ ...input, storage_key: `${ctx.organizationId}/${randomUUID()}` }) },
});

const attachments = defineResource({
  name: "attachments", table: "documents.attachments", tag: "documents", title: "Rattachement d'un fichier à une entreprise ou un contact",
  read: "documents.read", write: "documents.write",
  columns: ["id", "file_id", "company_id", "contact_id", ...TIMES],
  create: z.strictObject({ file_id: uuid, company_id: uuid.optional(), contact_id: uuid.optional() })
    .refine((v) => Number(!!v.company_id) + Number(!!v.contact_id) === 1, { message: "Fournir company_id ou contact_id, pas les deux." }) as never,
  filters: { file_id: { column: "file_id", schema: uuid }, company_id: { column: "company_id", schema: uuid }, contact_id: { column: "contact_id", schema: uuid } },
  sorts: ["created_at"], defaultSort: "-created_at",
});

// ───────────── web : demandes (requests.read / requests.write) ─────────────
const requestStatus = z.enum(["new", "in_progress", "closed", "spam"]);
const details = z.record(z.string().max(60), z.union([z.string().max(2000), z.number(), z.boolean(), z.null()]))
  .refine((v) => Object.keys(v).length <= 40, { message: "40 champs au maximum." });
const requests = defineResource({
  name: "requests", table: "web.requests", tag: "web", title: "Demandes entrantes",
  read: "requests.read", write: "requests.write",
  columns: ["id", "company_id", "contact_id", "subject", "message", "source", "status", "details", ...TIMES],
  create: z.strictObject({ subject: text(200), message: text(5000), source: z.string().regex(/^[a-z][a-z0-9_-]{1,39}$/).optional(),
    company_id: optional(uuid), contact_id: optional(uuid), details: details.optional() }),
  // Le contenu d'origine (sujet, message, source) ne se réécrit pas : seuls le suivi et les liens évoluent.
  update: z.strictObject({ status: requestStatus, company_id: optional(uuid), contact_id: optional(uuid) }).partial(),
  filters: { status: { column: "status", schema: requestStatus }, company_id: { column: "company_id", schema: uuid }, contact_id: { column: "contact_id", schema: uuid } },
  search: ["subject"], sorts: ["created_at", "updated_at"], defaultSort: "-created_at",
  hooks: {
    beforeCreate: (_ctx, input) => ({ ...input, details: input.details === undefined ? undefined : JSON.stringify(input.details) }),
    // Outbox transactionnelle : l'événement est écrit dans la même transaction que la demande.
    async afterCreate(ctx, row) { await ctx.db.query("SELECT integration.publish_request_created($1)", [row.id]); },
  },
});

const requestNotes = defineResource({
  name: "request-notes", table: "web.request_notes", tag: "web", title: "Notes internes d'une demande",
  read: "requests.read", write: "requests.write",
  columns: ["id", "request_id", "body", ...TIMES],
  create: z.strictObject({ request_id: uuid, body: text(5000) }), update: z.strictObject({ body: text(5000) }).partial(),
  filters: { request_id: { column: "request_id", schema: uuid } }, sorts: ["created_at"], defaultSort: "created_at",
});

// ───────────── integration (integrations.read / integrations.write) ─────────────
export const PROVIDERS = ["webhook", "email"] as const;
const connections = defineResource({
  name: "connections", table: "integration.connections", tag: "integration", title: "Connexions externes (le secret reste dans le coffre, jamais exposé)",
  read: "integrations.read", write: "integrations.write",
  columns: ["id", "provider", "name", "status", ...TIMES],
  create: z.strictObject({ provider: z.enum(PROVIDERS), name: text(120) }),
  // « error » est un état posé par l'exploitation, pas par le client.
  update: z.strictObject({ name: text(120), status: z.enum(["disabled", "enabled"]) }).partial(),
  filters: { provider: { column: "provider", schema: z.enum(PROVIDERS) }, status: { column: "status", schema: z.enum(["disabled", "enabled", "error"]) } },
  sorts: ["name", "created_at"], defaultSort: "name",
});

// ───────────── audit : lecture seule (audit.read) ─────────────
const auditEvents = defineResource({
  name: "audit-events", table: "audit.events", tag: "audit", title: "Journal d'audit de l'organisation (lecture seule)",
  read: "audit.read", columns: ["id", "actor_user_id", "actor_database_role", "action", "entity_type", "entity_id", "occurred_at"],
  filters: { entity_type: { column: "entity_type", schema: z.string().regex(/^[a-z_]+\.[a-z_]+$/) }, entity_id: { column: "entity_id", schema: uuid },
    actor_user_id: { column: "actor_user_id", schema: uuid }, action: { column: "action", schema: z.string().regex(/^[A-Za-z._]{1,60}$/) } },
  sorts: ["occurred_at"], defaultSort: "-occurred_at",
});

export const resources: ResourceDef[] = [
  companies, contacts, companyContacts, addresses, teams, teamMembers, applications, applicationPlans, subscriptions, organizationApplications,
  offerings, courses, courseModules, files, attachments, requests, requestNotes, connections, auditEvents,
];
