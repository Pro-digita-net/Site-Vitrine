// Amorçage et exploitation IAM, à lancer par un opérateur dans le conteneur core-iam :
//   node dist/iam/cli.js <commande> --option valeur
// Aucun compte par défaut : le premier propriétaire est créé explicitement ici.
import { parseArgs } from "node:util";
import { z } from "zod";
import { loadConfig } from "../config.js";
import { createPool } from "../shared/db.js";
import { createLogger } from "../shared/logger.js";
import { PERMISSIONS } from "../shared/tokens.js";
import { createOidcVerifier } from "./oidc.js";
import { IamService } from "./service.js";

const USAGE = `Commandes :
  org:list
  org:create     --slug <slug> --name <nom>
  org:status     --slug <slug> --status active|suspended|archived
  app:set        --org <slug> --app <code> --status enabled|disabled|suspended
  user:create    --email <e-mail> --given-name <prénom> --family-name <nom>
  identity:link  --email <e-mail> --issuer <émetteur OIDC> --subject <sub>
  member:set     --org <slug> --email <e-mail> --role owner|admin|editor|viewer
  token:issue    --org <slug> --email <e-mail> --label <libellé> --scopes a,b --days <n>   (clé API, affichée une seule fois)
  token:revoke   --id <uuid>`;

const { positionals, values } = parseArgs({ allowPositionals: true, options: Object.fromEntries(
  ["slug", "name", "status", "org", "app", "email", "given-name", "family-name", "issuer", "subject", "role", "label", "scopes", "days", "id"].map((k) => [k, { type: "string" as const }])) });
const need = <T>(name: string, schema: z.ZodType<T>): T => {
  const parsed = schema.safeParse(values[name]);
  if (!parsed.success) { console.error(`Option --${name} absente ou invalide.\n\n${USAGE}`); process.exit(2); }
  return parsed.data;
};
const slug = z.string().regex(/^[a-z0-9][a-z0-9-]{1,62}$/), str = z.string().trim().min(1).max(200), mail = z.email().max(254);

const config = loadConfig();
if (!config.iam.databaseUrl) { console.error("IAM_DATABASE_URL est obligatoire (compte pd_iam_admin)."); process.exit(1); }
const pool = createPool(config.iam.databaseUrl, { max: 2, ssl: config.databaseSsl, application: "core-iam-cli", log: createLogger("core-iam-cli") });
const { platform } = new IamService(pool, createOidcVerifier(config.iam.oidc), config.iam);

const commands: Record<string, () => Promise<unknown>> = {
  "org:list": () => platform.listOrganizations(),
  "org:create": () => platform.createOrganization(need("slug", slug), need("name", str)),
  "org:status": () => platform.setOrganizationStatus(need("slug", slug), need("status", z.enum(["active", "suspended", "archived"]))),
  "app:set": () => platform.setApplication(need("org", slug), need("app", str), need("status", z.enum(["enabled", "disabled", "suspended"]))),
  "user:create": () => platform.createUser(need("email", mail), need("given-name", str), need("family-name", str)),
  "identity:link": () => platform.linkIdentity(need("email", mail), need("issuer", str), need("subject", str)),
  "member:set": () => platform.setMembership(need("org", slug), need("email", mail), need("role", z.enum(["owner", "admin", "editor", "viewer"]))),
  "token:issue": () => platform.issueApiKey(need("org", slug), need("email", mail), {
    label: need("label", str), expires_in_days: need("days", z.coerce.number().int().min(1)),
    scopes: need("scopes", z.string().transform((v) => v.split(",").map((s) => s.trim())).pipe(z.array(z.enum(PERMISSIONS)).min(1))) }),
  "token:revoke": () => platform.revokeToken(need("id", z.uuid())),
};

const command = commands[positionals[0] ?? ""];
if (!command) { console.log(USAGE); process.exit(positionals[0] ? 2 : 0); }
try { console.log(JSON.stringify((await command()) ?? { ok: true }, null, 2)); }
catch (error) { console.error(`Échec : ${(error as Error).message}`); process.exitCode = 1; }
finally { await pool.end(); }
