// Validation et normalisation d'une demande. Une seule source de vérité pour
// les sujets et leurs champs complémentaires : src/contactQuestions.js, le
// module déjà utilisé par le formulaire du site.

import { createHash } from "node:crypto";
import { getContactQuestions, isKnownSubject, subjectGroupLabel } from "../../src/contactQuestions.js";

const LIMITS = { name: 80, email: 254, company: 150, message: 5000, answer: 400 };
const EMAIL_RE = /^[^\s@<>"(),;:]+@[^\s@<>"(),;:]+\.[^\s@<>"(),;:]{2,}$/;
const KEY_RE = /^[A-Za-z0-9._:-]{8,128}$/;

export class ValidationError extends Error {
  constructor(errors) {
    super("validation");
    this.errors = errors;
  }
}

// Texte sur une ligne : espaces normalisés, caractères de contrôle retirés.
const line = (value) =>
  typeof value === "string" ? value.replace(/[\u0000-\u001f\u007f]+/g, " ").replace(/\s+/g, " ").trim() : "";
// Texte libre : retours à la ligne conservés, le reste nettoyé.
const block = (value) =>
  typeof value === "string"
    ? value.replace(/\r\n?/g, "\n").replace(/[\u0000-\u0009\u000b-\u001f\u007f]+/g, " ").replace(/\n{3,}/g, "\n\n").trim()
    : "";

export function isValidIdempotencyKey(value) {
  return typeof value === "string" && KEY_RE.test(value);
}

/**
 * @returns {{ given_name, family_name, email, company, subject, subject_group, details, message }}
 * @throws {ValidationError}
 */
export function parseSubmission(body) {
  const input = body && typeof body === "object" && !Array.isArray(body) ? body : {};
  const errors = [];
  const fail = (field, message) => errors.push({ field, message });

  const given_name = line(input.given_name);
  const family_name = line(input.family_name);
  const email = line(input.email).toLowerCase();
  const company = line(input.company);
  const subject = line(input.subject);
  const message = block(input.message);

  if (!given_name) fail("given_name", "Merci d’indiquer votre prénom.");
  else if (given_name.length > LIMITS.name) fail("given_name", "Le prénom est trop long.");
  if (!family_name) fail("family_name", "Merci d’indiquer votre nom.");
  else if (family_name.length > LIMITS.name) fail("family_name", "Le nom est trop long.");
  if (!email || email.length > LIMITS.email || !EMAIL_RE.test(email)) fail("email", "Merci d’indiquer une adresse e-mail valide.");
  if (company.length > LIMITS.company) fail("company", "Le nom de l’entreprise est trop long.");
  if (!isKnownSubject(subject)) fail("subject", "Merci de choisir un sujet dans la liste.");
  if (message.length < 10) fail("message", "Décrivez votre demande en au moins 10 caractères.");
  else if (message.length > LIMITS.message) fail("message", "Votre message est trop long (5 000 caractères maximum).");

  // Seuls les champs du sujet choisi sont retenus, dans l'ordre du formulaire.
  const answers = input.answers && typeof input.answers === "object" && !Array.isArray(input.answers) ? input.answers : {};
  const details = [];
  if (isKnownSubject(subject)) {
    for (const field of getContactQuestions(subject).fields) {
      const value = line(answers[field.id]);
      if (!value) {
        if (field.required) fail(`answers.${field.id}`, `Merci de renseigner « ${field.label} ».`);
        continue;
      }
      if (value.length > LIMITS.answer) fail(`answers.${field.id}`, `La réponse « ${field.label} » est trop longue.`);
      else if (field.type === "select" && !field.options.includes(value)) fail(`answers.${field.id}`, `Merci de choisir une réponse proposée pour « ${field.label} ».`);
      else details.push({ id: field.id, label: field.label, value, required: Boolean(field.required) });
    }
  }

  if (errors.length) throw new ValidationError(errors);
  return {
    given_name,
    family_name,
    email,
    company: company || null,
    subject,
    subject_group: subjectGroupLabel(subject),
    details,
    message,
  };
}

const sha256 = (value) => createHash("sha256").update(value).digest("hex");

export function requestHash(submission) {
  return sha256(JSON.stringify([
    submission.given_name, submission.family_name, submission.email, submission.company ?? "",
    submission.subject, submission.details.map((d) => [d.id, d.value]), submission.message,
  ]));
}

export function naturalKey(submission) {
  return sha256(JSON.stringify([submission.email, submission.subject, submission.message]));
}

export const detailValue = (submission, id) => submission.details.find((d) => d.id === id)?.value ?? null;
