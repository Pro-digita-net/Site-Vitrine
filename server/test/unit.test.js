import assert from "node:assert/strict";
import { test } from "node:test";
import { getContactQuestions, subjectGroups } from "../../src/contactQuestions.js";
import { explainStorageFailure, validationSummary } from "../src/app.js";
import { explainSmtpFailure, notificationHtml, notificationRows, notificationSubject, notificationText } from "../src/email.js";
import { genesisIdempotencyKey, genesisPayload } from "../src/genesis.js";
import { naturalKey, parseSubmission, requestHash, ValidationError } from "../src/submission.js";
import { genesisComment } from "../src/summary.js";
import { nextRetryAt } from "../src/worker.js";

const base = {
  given_name: " Camille ", family_name: "Nova", email: " Camille.Nova@Example.com ", company: "Atelier Nova",
  subject: "Création web", message: "Je souhaite un site pour présenter mes créations.\nMerci.",
  answers: { projectType: "Créer un site vitrine", goal: "Présenter mes créations", budget: "De 1 000 à 3 000 €", deadline: "Dès que possible" },
};
const stored = (input = base) => ({ ...parseSubmission(input), id: "8d33e9b7-ed9e-49be-8eb5-cdb6ee8e1d98", created_at: new Date("2026-11-10T10:00:00Z") });

test("normalise et ne garde que les champs du sujet choisi", () => {
  const s = parseSubmission({ ...base, answers: { ...base.answers, supportNeed: "À définir ensemble", inconnu: "x" } });
  assert.equal(s.given_name, "Camille");
  assert.equal(s.email, "camille.nova@example.com");
  assert.equal(s.subject_group, "Expertise");
  assert.deepEqual(s.details.map((d) => d.id), ["projectType", "goal", "deadline", "budget"]);
});

test("exige les champs obligatoires du sujet, refuse les valeurs hors liste", () => {
  const errors = (input) => {
    try { parseSubmission(input); return []; } catch (e) { assert.ok(e instanceof ValidationError); return e.errors.map((x) => x.field); }
  };
  assert.deepEqual(errors({ ...base, answers: {} }), ["answers.projectType", "answers.goal"]);
  assert.deepEqual(errors({ ...base, answers: { ...base.answers, budget: "1 million" } }), ["answers.budget"]);
  assert.deepEqual(errors({ ...base, subject: "Sujet inventé" }), ["subject"]);
  assert.deepEqual(errors({ ...base, email: "pas-un-email", message: "court" }), ["email", "message"]);
  assert.deepEqual(errors({}), ["given_name", "family_name", "email", "subject", "message"]);
});

test("tous les sujets du site sont acceptés avec leurs champs obligatoires", () => {
  const subjects = subjectGroups.flatMap((g) => g.items.map((i) => i.name)).concat("Autre besoin");
  for (const subject of subjects) {
    const answers = Object.fromEntries(getContactQuestions(subject).fields.map((f) => [f.id, f.options?.[0] ?? "Réponse"]));
    const s = parseSubmission({ ...base, subject, answers });
    assert.equal(s.details.length, getContactQuestions(subject).fields.length, subject);
  }
});

test("les empreintes distinguent contenu et doublon naturel", () => {
  const a = parseSubmission(base);
  const b = parseSubmission({ ...base, answers: { ...base.answers, budget: "Plus de 10 000 €" } });
  assert.notEqual(requestHash(a), requestHash(b));
  assert.equal(naturalKey(a), naturalKey(b));
});

test("le récapitulatif Genesis reprend toutes les informations et reste sous 8 000 caractères", () => {
  const row = stored();
  const comment = genesisComment(row);
  for (const expected of ["Camille Nova", "camille.nova@example.com", "Atelier Nova", "Expertise : Création web", "Budget envisagé : De 1 000 à 3 000 €", "Échéance souhaitée : Dès que possible", "Je souhaite un site", row.id, "Lecture seule"]) {
    assert.ok(comment.includes(expected), expected);
  }
  const long = stored({ ...base, message: "x".repeat(5000), answers: { ...base.answers, goal: "y".repeat(400), features: "z".repeat(400), existingSite: "w".repeat(400) } });
  assert.ok(genesisComment({ ...long, company: "c".repeat(150) }).length <= 8000);
});

test("le corps Genesis est déterministe et porte le budget", () => {
  const row = stored();
  assert.deepEqual(genesisPayload(row), genesisPayload(row));
  assert.equal(genesisPayload(row).budget_band, "De 1 000 à 3 000 €");
  assert.equal(genesisPayload(row).source, "site_web");
  assert.equal(genesisIdempotencyKey(row), `site-vitrine:${row.id}`);
});

test("l'e-mail suit le modèle et échappe le contenu du client", () => {
  const row = stored({ ...base, company: "<script>alert(1)</script>", message: "Bonjour <b>vous</b>\n2e ligne" });
  const html = notificationHtml(row);
  for (const expected of ["Assistant ProDigital", "Une nouvelle demande vous attend.", "Son message", "Répondre à la demande", "Référence de votre échange", row.id, "Votre assistant ProDigital", "Budget envisagé", "mailto:camille.nova%40example.com"]) {
    assert.ok(html.includes(expected), expected);
  }
  assert.ok(!html.includes("<script>alert(1)</script>"));
  assert.ok(html.includes("Bonjour &lt;b&gt;vous&lt;/b&gt;<br>2e ligne"));
  assert.deepEqual(notificationRows(row).slice(0, 4).map((r) => r[0]), ["Contact", "E-mail", "Entreprise", "Expertise"]);
  assert.ok(notificationText(row).includes("Budget envisagé : De 1 000 à 3 000 €"));
  assert.ok(!/[\r\n]/.test(notificationSubject({ ...row, subject: "Création web\r\nBcc: x@y.z" })));
});

test("chaque échec d'enregistrement nomme sa cause", () => {
  assert.match(explainStorageFailure({ code: "ECONNREFUSED" }), /injoignable \(code ECONNREFUSED\)/);
  assert.match(explainStorageFailure({ code: "28P01" }), /identifiant de connexion/);
  assert.match(explainStorageFailure({ code: "23505", constraint: "contact_submissions_idempotency_key_key" }), /idempotency_key_key/);
  assert.match(explainStorageFailure({ code: "23502", column: "email" }), /colonne email/);
  assert.match(explainStorageFailure({ code: "42P01", table: "site.contact_submissions" }), /site\.contact_submissions/);
  assert.match(explainStorageFailure(new Error("DATABASE_URL non configuré")), /DATABASE_URL/);
  assert.match(explainStorageFailure({ name: "TypeError" }), /TypeError/);
  assert.match(validationSummary([{ field: "email", message: "Merci d’indiquer une adresse e-mail valide." }]), /e-mail valide/);
  assert.match(validationSummary([
    { field: "given_name", message: "Merci d’indiquer votre prénom." },
    { field: "message", message: "Décrivez votre demande en au moins 10 caractères." },
  ]), /2 informations empêchent l’envoi/);
});

test("un refus SMTP dit le code et la réponse, pas le secret", () => {
  const error = explainSmtpFailure({ code: "EAUTH", responseCode: 535, response: "535 Authentication failed", command: "AUTH PLAIN secret" });
  assert.match(error.message, /EAUTH/);
  assert.match(error.message, /SMTP 535/);
  assert.match(error.message, /Authentication failed/);
  assert.equal(error.message.includes("secret"), false);
  assert.equal(error.retryable, true);
  assert.equal(explainSmtpFailure({ code: "EENVELOPE" }).retryable, false);
});

test("les relances s'espacent puis s'arrêtent ; une erreur définitive n'est pas relancée", () => {
  assert.ok(nextRetryAt(1) > new Date());
  assert.ok(nextRetryAt(2) > nextRetryAt(1));
  assert.equal(nextRetryAt(99), null);
  assert.equal(nextRetryAt(1, false), null);
});
