// Parcours complet, sans simulation du code métier :
//   navigateur/HTTP → API du site → PostgreSQL réel (conteneur jetable)
//                   → e-mail par SMTP réel (serveur de réception local)
//                   → Genesis CRM : le VRAI handler POST /api/sales/public/leads
//                     du dépôt Genesis (GENESIS_REPO), avec le vrai schéma
//                     web.contact_requests et les vraies migrations 015 et 017.
//
//   node test/e2e.mjs            exécute tous les scénarios puis nettoie
//   node test/e2e.mjs --serve    démarre la pile et la laisse tourner (tests navigateur)
//
// Prérequis : Docker, et le dépôt Genesis en local (GENESIS_REPO, défaut C:/GENESIS).

import assert from "node:assert/strict";
import { execFile, execFileSync, spawn } from "node:child_process";
import { promisify } from "node:util";
import { randomBytes, randomUUID } from "node:crypto";
import { mkdirSync, readFileSync, writeFileSync } from "node:fs";
import http from "node:http";
import { pathToFileURL } from "node:url";
import { simpleParser } from "mailparser";
import pg from "pg";
import { SMTPServer } from "smtp-server";

const SERVE = process.argv.includes("--serve");
const GENESIS_REPO = (process.env.GENESIS_REPO || "C:/GENESIS").replace(/\\/g, "/");
const PG_IMAGE = process.env.E2E_PG_IMAGE || "postgres:16-alpine";
const PORTS = { pg: 55432, api: 58788, genesis: 58787, smtp: 52525 };
const CONTAINER = "site-vitrine-e2e-pg";
const secret = () => randomBytes(18).toString("hex");
const pw = { owner: secret(), genesis: secret(), site: secret(), smtp: secret() };
const GENESIS_TOKEN = randomBytes(32).toString("hex");
const url = (user, password) => `postgresql://${user}:${password}@127.0.0.1:${PORTS.pg}/prodigital`;
const API = `http://127.0.0.1:${PORTS.api}`;
const execFileAsync = promisify(execFile);
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

let passed = 0;
const ok = (label) => { passed += 1; console.log(`  ✔ ${label}`); };
const step = (label) => console.log(`\n▶ ${label}`);
async function waitFor(fn, label, timeoutMs = 15000) {
  const end = Date.now() + timeoutMs;
  let last;
  while (Date.now() < end) {
    try { last = await fn(); if (last) return last; } catch (error) { last = error; }
    await sleep(150);
  }
  throw new Error(`Délai dépassé : ${label} (dernier état : ${last instanceof Error ? last.message : JSON.stringify(last)})`);
}

// ---------------------------------------------------------------- PostgreSQL
const docker = (...args) => execFileSync("docker", args, { stdio: ["ignore", "pipe", "pipe"] }).toString().trim();
function startPostgres() {
  try { docker("rm", "-f", CONTAINER); } catch {}
  docker("run", "-d", "--name", CONTAINER, "-e", `POSTGRES_PASSWORD=${pw.owner}`, "-e", "POSTGRES_DB=prodigital",
    "-p", `127.0.0.1:${PORTS.pg}:5432`, PG_IMAGE);
}
const owner = () => new pg.Client({ connectionString: url("postgres", pw.owner) });
async function sql(text, params) {
  const client = owner();
  await client.connect();
  try { return await client.query(text, params); } finally { await client.end(); }
}
const stripPsql = (file) => readFileSync(file, "utf8").split(/\r?\n/).filter((l) => !l.startsWith("\\")).join("\n");

async function prepareDatabase() {
  await waitFor(async () => (await sql("SELECT 1")).rowCount === 1, "PostgreSQL prêt", 60000);
  // Socle Core minimal, repris tel quel de Genesis infra/prodigital/database/001-business.sql.
  await sql(`
    CREATE SCHEMA web; CREATE SCHEMA genesis; CREATE SCHEMA infrastructure;
    CREATE ROLE genesis LOGIN PASSWORD '${pw.genesis}';
    CREATE ROLE site_vitrine LOGIN PASSWORD '${pw.site}';
    GRANT USAGE, CREATE ON SCHEMA genesis TO genesis;
    CREATE FUNCTION infrastructure.touch_row() RETURNS trigger LANGUAGE plpgsql AS $$
      BEGIN NEW.updated_at := clock_timestamp(); NEW.row_version := OLD.row_version + 1; RETURN NEW; END $$;
    CREATE TABLE "web"."contact_requests" (
      id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
      "given_name" text NOT NULL, "family_name" text NOT NULL, "email" text NOT NULL,
      "phone" text, "company_text" text, "subject" text NOT NULL, "message" text NOT NULL,
      "budget_band" text, "requested_date" date, "source" text NOT NULL, "notice_version" text NOT NULL,
      "status" text NOT NULL, "received_at" timestamptz NOT NULL,
      created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
      updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
      row_version bigint NOT NULL DEFAULT 1 CHECK(row_version>0));
    ALTER TABLE "web"."contact_requests" ENABLE ROW LEVEL SECURITY;
    ALTER TABLE "web"."contact_requests" FORCE ROW LEVEL SECURITY;
    CREATE TRIGGER z_touch BEFORE UPDATE ON "web"."contact_requests" FOR EACH ROW EXECUTE FUNCTION infrastructure.touch_row();
  `);
  // Vraies migrations Genesis de l'ingestion de leads.
  await sql(stripPsql(`${GENESIS_REPO}/infra/prodigital/database/015-sales-lead-ingest.sql`));
  await sql(stripPsql(`${GENESIS_REPO}/infra/prodigital/database/017-sales-lead-utm.sql`));
  // Migration du site (propriétaire), puis lecture seule Genesis, puis droits minimaux de l'API.
  execFileSync(process.execPath, ["src/cli.js", "migrate"], { env: { ...process.env, DATABASE_URL: url("postgres", pw.owner) }, stdio: "inherit" });
  await sql(readFileSync(new URL("../sql/core-contact-requests-readonly.sql", import.meta.url), "utf8"));
  await sql(readFileSync(new URL("../sql/site-role-grants.sql", import.meta.url), "utf8"));
}

// ------------------------------------------------------------ Genesis (réel)
let genesisServer;
let genesisHandler;
async function startGenesis() {
  process.env.DATABASE_URL = url("genesis", pw.genesis); // rôle `genesis`, droits de la migration 015
  process.env.GENESIS_SERVICE_TOKEN = GENESIS_TOKEN;
  genesisHandler ??= (await import(pathToFileURL(`${GENESIS_REPO}/server/sales-lead-http.ts`).href)).handleSalesLeadHttp;
  genesisServer = http.createServer((req, res) => {
    if (!genesisHandler(req, res)) { res.statusCode = 404; res.end(); }
  });
  await new Promise((resolve) => genesisServer.listen(PORTS.genesis, "127.0.0.1", resolve));
}
async function stopGenesis() {
  genesisServer?.closeAllConnections();
  await new Promise((resolve) => genesisServer.close(resolve));
  genesisServer = null;
}

// ------------------------------------------------------- Réception SMTP locale
const inbox = [];
let smtpServer;
const MAIL_DIR = process.env.E2E_MAIL_DIR;
async function startSmtp() {
  smtpServer = new SMTPServer({
    disabledCommands: ["STARTTLS"], allowInsecureAuth: true, authOptional: false, logger: false,
    onAuth: (auth, _session, done) =>
      auth.username === "contact@pro-digital.net" && auth.password === pw.smtp ? done(null, { user: auth.username }) : done(new Error("Identifiants refusés")),
    onData: (stream, session, done) => {
      const chunks = [];
      stream.on("data", (c) => chunks.push(c));
      stream.on("end", async () => {
        const raw = Buffer.concat(chunks);
        const mail = await simpleParser(raw);
        inbox.push({ mail, envelope: session.envelope });
        if (MAIL_DIR) {
          mkdirSync(MAIL_DIR, { recursive: true });
          const html = mail.html.replace(/cid:[^"]+/g, () => `data:image/png;base64,${mail.attachments[0].content.toString("base64")}`);
          writeFileSync(`${MAIL_DIR}/dernier-email.html`, html);
          writeFileSync(`${MAIL_DIR}/dernier-email.txt`, `Sujet: ${mail.subject}\nDe: ${mail.from.text}\nÀ: ${mail.to.text}\nRépondre à: ${mail.replyTo?.text}\n\n${mail.text}`);
        }
        done();
      });
    },
  });
  // Une connexion coupée par l'arrêt brutal de l'API (scénario 6) ne doit pas arrêter le banc.
  smtpServer.on("error", () => {});
  await new Promise((resolve) => smtpServer.listen(PORTS.smtp, "127.0.0.1", resolve));
}
const stopSmtp = () => new Promise((resolve) => smtpServer.close(resolve));
const mailsFor = (id) => inbox.filter((m) => m.mail.headers.get("x-prodigital-request") === id);

// ------------------------------------------------------------------ API du site
let api;
async function startApi(overrides = {}) {
  api = spawn(process.execPath, ["src/index.js"], {
    stdio: ["ignore", "pipe", "pipe"],
    env: {
      ...process.env,
      PORT: String(PORTS.api),
      DATABASE_URL: url("site_vitrine", pw.site),
      ALLOWED_ORIGINS: "http://127.0.0.1:5199,http://localhost:5199",
      GENESIS_URL: `http://127.0.0.1:${PORTS.genesis}`,
      GENESIS_SERVICE_TOKEN: GENESIS_TOKEN,
      GENESIS_TIMEOUT_MS: "3000",
      SMTP_HOST: "127.0.0.1", SMTP_PORT: String(PORTS.smtp), SMTP_SECURITY: "off",
      SMTP_USER: "contact@pro-digital.net", SMTP_PASSWORD: pw.smtp,
      SMTP_FROM: "contact@pro-digital.net", CONTACT_NOTIFY_TO: "contact@pro-digital.net",
      WORKER_POLL_MS: "300", WORKER_LEASE_MS: "3000", WORKER_BACKOFF_SECONDS: "1,1,1,1,1,1,1,1,1,1,1,1", RATE_LIMIT_MAX: "1000",
      ...overrides,
    },
  });
  api.logs = "";
  api.stdout.on("data", (d) => (api.logs += d));
  api.stderr.on("data", (d) => (api.logs += d));
  await waitFor(async () => (await fetch(`${API}/api/health`)).ok, "API prête");
}
async function stopApi() {
  if (!api) return;
  const done = new Promise((resolve) => api.once("exit", resolve));
  api.kill();
  await done;
  api = null;
}

// --------------------------------------------------------------------- Outils
const person = (n) => ({ given_name: "Camille", family_name: `Nova${n}`, email: `camille.nova+${n}@example.com`, company: "Atelier Nova" });
const webRequest = (n, extra = {}) => ({
  ...person(n),
  subject: "Création web",
  answers: {
    projectType: "Créer un site vitrine", goal: "Présenter mes créations et recevoir des demandes",
    existingSite: "www.atelier-nova.example", features: "Prise de rendez-vous en ligne",
    content: "Une partie est prête", deadline: "Dès que possible", budget: "De 1 000 à 3 000 €",
  },
  message: `Bonjour, je souhaite un site pour mettre en avant mes créations (essai ${n}).\nMerci d'avance.`,
  ...extra,
});
async function post(body, { key = randomUUID(), headers = {} } = {}) {
  const response = await fetch(`${API}/api/contact-requests`, {
    method: "POST",
    headers: { "Content-Type": "application/json", ...(key ? { "Idempotency-Key": key } : {}), ...headers },
    body: JSON.stringify(body),
  });
  return { status: response.status, data: await response.json().catch(() => ({})) };
}
const ops = async (id) =>
  Object.fromEntries((await sql("SELECT kind, status, attempts, last_error, external_id FROM site.contact_operations WHERE submission_id = $1", [id])).rows.map((r) => [r.kind, r]));
const settled = (id, expected) => waitFor(async () => {
  const state = await ops(id);
  if (Object.entries(expected).every(([kind, status]) => state[kind]?.status === status)) return state;
  throw new Error(JSON.stringify(Object.fromEntries(Object.entries(state).map(([k, v]) => [k, `${v.status}/${v.attempts} ${v.last_error ?? ""}`]))));
}, `opérations ${JSON.stringify(expected)} pour ${id}`);
const leadsFor = async (email) => (await sql("SELECT * FROM web.contact_requests WHERE email = $1 ORDER BY received_at", [email])).rows;
const count = async (table) => Number((await sql(`SELECT count(*) FROM ${table}`)).rows[0].count);
const expectDbError = async (client, text, params, pattern, label) => {
  await assert.rejects(client.query(text, params), pattern, label);
};

// ------------------------------------------------------------------ Scénarios
async function scenarios() {
  step("1. Parcours nominal : enregistrement + e-mail + Genesis");
  const body1 = webRequest(1);
  const r1 = await post(body1);
  assert.equal(r1.status, 201);
  assert.match(r1.data.id, /^[0-9a-f-]{36}$/);
  const id1 = r1.data.id;
  ok(`201, demande enregistrée ${id1}`);
  const row1 = (await sql("SELECT * FROM site.contact_submissions WHERE id = $1", [id1])).rows[0];
  assert.equal(row1.email, "camille.nova+1@example.com");
  assert.equal(row1.subject, "Création web");
  assert.equal(row1.company, "Atelier Nova");
  assert.equal(row1.details.length, 7);
  assert.ok(row1.created_at instanceof Date);
  ok("BDD : coordonnées, entreprise, sujet, 7 informations complémentaires, date, identifiant unique");
  const s1 = await settled(id1, { email: "succeeded", crm: "succeeded" });
  ok("les deux opérations passent à « succeeded »");

  const [m1] = mailsFor(id1);
  assert.equal(mailsFor(id1).length, 1);
  assert.equal(m1.mail.to.text, "contact@pro-digital.net");
  assert.equal(m1.mail.replyTo.value[0].address, "camille.nova+1@example.com");
  assert.equal(m1.mail.from.value[0].name, "Assistant ProDigital");
  assert.equal(m1.mail.subject, "Nouvelle demande — Création web — Camille Nova1");
  for (const expected of ["Une nouvelle demande vous attend.", "Atelier Nova", "Budget envisagé", "De 1 000 à 3 000 €", "Échéance souhaitée", "Prise de rendez-vous en ligne", "www.atelier-nova.example", "Répondre à la demande", id1]) {
    assert.ok(m1.mail.html.includes(expected), `HTML sans « ${expected} »`);
    if (expected !== "Répondre à la demande" && expected !== "Une nouvelle demande vous attend.") assert.ok(m1.mail.text.includes(expected), `texte sans « ${expected} »`);
  }
  assert.equal(m1.mail.attachments.length, 1);
  ok("e-mail reçu par SMTP authentifié : modèle, destinataire, Reply-To client, tous les champs, logo");

  const leads1 = await leadsFor("camille.nova+1@example.com");
  assert.equal(leads1.length, 1);
  assert.equal(leads1[0].id, s1.crm.external_id);
  assert.equal(leads1[0].source, "site_web");
  assert.equal(leads1[0].status, "recue");
  assert.equal(leads1[0].budget_band, "De 1 000 à 3 000 €");
  for (const expected of ["Camille Nova1", "Atelier Nova", "Expertise : Création web", "Quel projet souhaitez-vous réaliser ? : Créer un site vitrine", "Budget envisagé : De 1 000 à 3 000 €", "Échéance souhaitée : Dès que possible", "mettre en avant mes créations", id1]) {
    assert.ok(leads1[0].message.includes(expected), `récapitulatif Genesis sans « ${expected} »`);
  }
  ok(`Genesis (vrai handler) : lead ${leads1[0].id} créé, récapitulatif complet`);

  step("2. Doublons et doubles soumissions");
  const key2 = randomUUID();
  const burst = await Promise.all(Array.from({ length: 6 }, () => post(webRequest(2), { key: key2 })));
  assert.deepEqual(burst.map((r) => r.status).sort(), [200, 200, 200, 200, 200, 201]);
  assert.equal(new Set(burst.map((r) => r.data.id)).size, 1);
  const id2 = burst[0].data.id;
  await settled(id2, { email: "succeeded", crm: "succeeded" });
  await sleep(1200);
  assert.equal(mailsFor(id2).length, 1);
  assert.equal((await leadsFor("camille.nova+2@example.com")).length, 1);
  ok("6 envois simultanés, même clé → 1 demande, 1 e-mail, 1 lead Genesis");
  const again = await post(webRequest(2));
  assert.equal(again.status, 200);
  assert.equal(again.data.id, id2);
  assert.equal(again.data.duplicate, true);
  ok("même contenu, nouvelle clé (rechargement de page) → rattaché à la demande existante");
  const conflict = await post(webRequest(2, { message: "Un tout autre message, avec la même clé." }), { key: key2 });
  assert.equal(conflict.status, 409);
  ok("même clé, contenu différent → 409, rien de créé");
  assert.equal(await count("site.contact_submissions"), 2);

  step("3. Validation côté serveur");
  const invalid = [
    ["champ obligatoire du sujet manquant", webRequest(3, { answers: { projectType: "Créer un site vitrine" } }), 400],
    ["sujet inconnu", webRequest(3, { subject: "Sujet inventé" }), 400],
    ["réponse hors liste", webRequest(3, { answers: { ...webRequest(3).answers, budget: "Gratuit" } }), 400],
    ["e-mail invalide", webRequest(3, { email: "pas-un-email" }), 400],
    ["champ piège rempli (robot)", webRequest(3, { website: "http://spam.example" }), 400],
  ];
  for (const [label, body, status] of invalid) {
    const r = await post(body);
    assert.equal(r.status, status, label);
    assert.equal(r.data.id, undefined);
  }
  assert.equal((await post(webRequest(3), { key: null })).status, 400);
  assert.equal((await post(webRequest(3), { headers: { Origin: "https://site-pirate.example" } })).status, 403);
  assert.equal(await count("site.contact_submissions"), 2);
  ok("7 envois invalides refusés (400/403), aucune ligne créée, aucune confirmation");
  const support = await post({ ...person(4), subject: "Support IT", answers: { supportNeed: "Une assistance au quotidien pour nos utilisateurs", teamSize: "11 à 50", budget: "De 200 à 500 € par mois", phone: "06 12 34 56 78" }, message: "Nous cherchons un prestataire pour le support de nos 20 postes." });
  assert.equal(support.status, 201);
  await settled(support.data.id, { email: "succeeded", crm: "succeeded" });
  assert.ok(mailsFor(support.data.id)[0].mail.html.includes("06 12 34 56 78"));
  const supportLead = (await leadsFor("camille.nova+4@example.com"))[0];
  assert.ok(supportLead.message.includes("Combien d’utilisateurs à accompagner ? : 11 à 50"));
  assert.ok(supportLead.message.includes("Téléphone pour vous joindre : 06 12 34 56 78"));
  assert.equal(supportLead.budget_band, "De 200 à 500 € par mois");
  ok("autre sujet (Support IT) : ses propres champs, facultatifs vides ignorés");

  step("4. Genesis indisponible : la demande n'est pas perdue");
  await stopGenesis();
  const r5 = await post(webRequest(5));
  assert.equal(r5.status, 201);
  const id5 = r5.data.id;
  await settled(id5, { email: "succeeded" });
  const down = await waitFor(async () => { const s = await ops(id5); return s.crm.attempts >= 2 && s.crm.status !== "succeeded" && s; }, "relances CRM");
  assert.match(down.crm.last_error, /Genesis injoignable/);
  assert.equal((await leadsFor("camille.nova+5@example.com")).length, 0);
  ok(`client confirmé (201), e-mail parti, CRM en attente après ${down.crm.attempts} tentatives : « ${down.crm.last_error} »`);
  await startGenesis();
  const up = await settled(id5, { crm: "succeeded" });
  assert.equal((await leadsFor("camille.nova+5@example.com")).length, 1);
  assert.equal(mailsFor(id5).length, 1);
  ok(`Genesis de retour → transmis automatiquement (tentative ${up.crm.attempts}), 1 seul lead, e-mail non renvoyé`);

  step("5. Messagerie indisponible, indépendamment du CRM");
  await stopSmtp();
  const r6 = await post(webRequest(6));
  assert.equal(r6.status, 201);
  const id6 = r6.data.id;
  await settled(id6, { crm: "succeeded" });
  const mailDown = await waitFor(async () => { const s = await ops(id6); return s.email.attempts >= 2 && s.email.status !== "succeeded" && s; }, "relances e-mail");
  ok(`CRM créé malgré la panne ; e-mail en attente : « ${mailDown.email.last_error} »`);
  await startSmtp();
  await settled(id6, { email: "succeeded" });
  assert.equal(mailsFor(id6).length, 1);
  assert.equal((await leadsFor("camille.nova+6@example.com")).length, 1);
  ok("messagerie de retour → 1 e-mail envoyé, lead non dupliqué");

  step("6. Jeton Genesis invalide, arrêt brutal et reprise");
  await stopApi();
  await startApi({ GENESIS_SERVICE_TOKEN: "jeton-invalide" });
  const r7 = await post(webRequest(7));
  const id7 = r7.data.id;
  const refused = await waitFor(async () => { const s = await ops(id7); return s.crm.attempts >= 1 && s.crm.last_error && s; }, "refus du jeton");
  assert.match(refused.crm.last_error, /HTTP 401/);
  ok(`Genesis (vrai contrôle du jeton) refuse : « ${refused.crm.last_error} »`);
  await stopApi();
  await startApi();
  await settled(id7, { email: "succeeded", crm: "succeeded" });
  assert.equal((await leadsFor("camille.nova+7@example.com")).length, 1);
  assert.equal(mailsFor(id7).length, 1);
  ok("après redémarrage avec le bon jeton : reprise automatique (y compris d'une opération interrompue en cours), 1 lead, 1 e-mail");

  step("7. Abandon automatique puis relance manuelle");
  await stopApi();
  await stopGenesis();
  await startApi({ WORKER_BACKOFF_SECONDS: "1" });
  const r8 = await post(webRequest(8));
  const id8 = r8.data.id;
  await settled(id8, { email: "succeeded", crm: "failed" });
  ok("après épuisement des tentatives : CRM « failed », demande et e-mail intacts");
  await startGenesis();
  // Asynchrone : Genesis tourne dans ce même processus et doit pouvoir répondre.
  const { stdout: cli } = await execFileAsync(process.execPath, ["src/cli.js", "retry", id8], {
    env: { ...process.env, DATABASE_URL: url("site_vitrine", pw.site), GENESIS_URL: `http://127.0.0.1:${PORTS.genesis}`, GENESIS_SERVICE_TOKEN: GENESIS_TOKEN },
  });
  await settled(id8, { crm: "succeeded" });
  assert.equal((await leadsFor("camille.nova+8@example.com")).length, 1);
  assert.equal(mailsFor(id8).length, 1);
  ok(`relance manuelle (« ${cli.trim().split("\n")[0]} ») → lead créé, e-mail non renvoyé`);
  await stopApi();
  await startApi();

  step("8. Traçabilité");
  const trail = (await sql("SELECT kind, event FROM site.contact_events WHERE submission_id = $1 ORDER BY at, id", [id5])).rows.map((e) => `${e.kind}:${e.event}`);
  assert.equal(trail[0], "submission:recorded");
  assert.ok(trail.includes("email:succeeded") && trail.includes("crm:retry_scheduled") && trail.at(-1) === "crm:succeeded");
  ok(`historique de la demande ${id5.slice(0, 8)}… : ${trail.join(" → ")}`);

  step("9. Lecture seule");
  const lead = (await leadsFor("camille.nova+1@example.com"))[0];
  const asGenesis = new pg.Client({ connectionString: url("genesis", pw.genesis) });
  const asOwner = owner();
  const asSite = new pg.Client({ connectionString: url("site_vitrine", pw.site) });
  await Promise.all([asGenesis.connect(), asOwner.connect(), asSite.connect()]);
  try {
    await expectDbError(asGenesis, "UPDATE web.contact_requests SET message = 'modifié' WHERE id = $1", [lead.id], /permission denied/, "rôle genesis");
    ok("Genesis (rôle applicatif) ne peut pas modifier le récapitulatif : permission refusée");
    await expectDbError(asOwner, "UPDATE web.contact_requests SET message = 'modifié' WHERE id = $1", [lead.id], /lecture seule/, "propriétaire");
    await expectDbError(asOwner, "UPDATE web.contact_requests SET email = 'autre@example.com' WHERE id = $1", [lead.id], /lecture seule/, "propriétaire");
    await expectDbError(asOwner, "DELETE FROM web.contact_requests WHERE id = $1", [lead.id], /ne peut pas être supprimée/, "suppression");
    ok("même le propriétaire de la base ne peut ni modifier ni supprimer le contenu d'origine (trigger)");
    await asOwner.query("UPDATE web.contact_requests SET status = 'en_cours' WHERE id = $1", [lead.id]);
    const after = (await leadsFor("camille.nova+1@example.com"))[0];
    assert.equal(after.status, "en_cours");
    assert.equal(after.message, lead.message);
    ok("le statut de traitement reste modifiable, le récapitulatif est inchangé");
    await expectDbError(asSite, "UPDATE site.contact_submissions SET message = 'modifié' WHERE id = $1", [id1], /permission denied/, "rôle site");
    await expectDbError(asOwner, "UPDATE site.contact_submissions SET message = 'modifié' WHERE id = $1", [id1], /lecture seule/, "propriétaire");
    await expectDbError(asSite, "SELECT 1 FROM web.contact_requests LIMIT 1", [], /permission denied/, "cloisonnement");
    ok("la demande d'origine côté site est immuable ; l'API du site n'a aucun accès au schéma web");
  } finally {
    await Promise.all([asGenesis.end(), asOwner.end(), asSite.end()]);
  }

  step("10. Base indisponible : pas de fausse confirmation");
  // Le pool du code Genesis (genesis-db.ts) n'écoute pas les erreurs de connexion au repos :
  // on les absorbe ici pour que l'arrêt volontaire de la base n'arrête pas le banc.
  process.on("uncaughtException", (error) => { if (!["57P01", "ECONNRESET"].includes(error?.code)) throw error; });
  const before = { mails: inbox.length };
  docker("stop", "-t", "1", CONTAINER);
  const r9 = await post(webRequest(9));
  assert.equal(r9.status, 503);
  assert.equal(r9.data.id, undefined);
  assert.equal((await fetch(`${API}/api/health`)).status, 503);
  await sleep(800);
  assert.equal(inbox.length, before.mails);
  ok("503 sans identifiant : le formulaire n'affiche pas de confirmation, aucun e-mail, aucun lead");
  docker("start", CONTAINER);
  await waitFor(async () => (await fetch(`${API}/api/health`)).ok, "API rétablie", 60000);
  const r10 = await post(webRequest(9));
  assert.equal(r10.status, 201);
  await settled(r10.data.id, { email: "succeeded", crm: "succeeded" });
  ok("base de retour → le même envoi aboutit normalement");
}

// ------------------------------------------------------------------- Exécution
async function teardown() {
  await stopApi().catch(() => {});
  if (genesisServer) await stopGenesis().catch(() => {});
  if (smtpServer) await stopSmtp().catch(() => {});
  try { docker("rm", "-f", CONTAINER); } catch {}
}

let failed = false;
try {
  step("Préparation : PostgreSQL jetable, schémas, Genesis réel, réception SMTP, API");
  startPostgres();
  await prepareDatabase();
  await startGenesis();
  await startSmtp();
  await startApi();
  ok("pile démarrée");
  if (SERVE) {
    console.log(`\nPile prête : API ${API} — Ctrl+C pour arrêter.`);
    process.on("SIGINT", async () => { await teardown(); process.exit(0); });
    process.on("SIGTERM", async () => { await teardown(); process.exit(0); });
    await new Promise(() => {});
  }
  await scenarios();
  console.log(`\n${passed} vérifications réussies.`);
} catch (error) {
  failed = true;
  console.error(`\n✘ ÉCHEC : ${error.stack || error}`);
  if (api?.logs) console.error(`\n--- journal de l'API ---\n${api.logs.split("\n").slice(-25).join("\n")}`);
} finally {
  if (!SERVE || failed) await teardown();
  process.exit(failed ? 1 : 0);
}
