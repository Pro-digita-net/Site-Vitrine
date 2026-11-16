// Récapitulatif texte d'une demande : version texte de l'e-mail et
// commentaire (lecture seule) transmis à Genesis CRM. Construit uniquement à
// partir de la ligne enregistrée en base, donc identique à chaque relance.

const GENESIS_MESSAGE_MAX = 8000;

const parisDate = (value) =>
  new Intl.DateTimeFormat("fr-FR", { dateStyle: "long", timeStyle: "short", timeZone: "Europe/Paris" }).format(new Date(value));

export const fullName = (row) => `${row.given_name} ${row.family_name}`.trim();

export function summaryLines(row) {
  const details = Array.isArray(row.details) ? row.details : [];
  return [
    "DEMANDE REÇUE VIA LE SITE PRO-DIGITAL.NET",
    `Référence : ${row.id}`,
    `Reçue le : ${parisDate(row.created_at)} (heure de Paris)`,
    "",
    "COORDONNÉES",
    `Contact : ${fullName(row)}`,
    `E-mail : ${row.email}`,
    `Entreprise : ${row.company || "Non précisée"}`,
    "",
    "SUJET",
    `${row.subject_group} : ${row.subject}`,
    ...(details.length ? ["", "INFORMATIONS COMPLÉMENTAIRES", ...details.map((d) => `${d.label} : ${d.value}`)] : []),
    "",
    "MESSAGE DU CLIENT",
    row.message,
  ];
}

export function summaryText(row) {
  return summaryLines(row).join("\n");
}

/** Commentaire Genesis : récapitulatif complet, borné à la limite de l'API (8 000 caractères). */
export function genesisComment(row) {
  const text = [
    ...summaryLines(row),
    "",
    "— Récapitulatif d’origine transmis automatiquement par le site. Lecture seule.",
  ].join("\n");
  if (text.length <= GENESIS_MESSAGE_MAX) return text;
  const note = `\n[… récapitulatif tronqué, version complète : demande ${row.id} dans la base du site]`;
  return text.slice(0, GENESIS_MESSAGE_MAX - note.length) + note;
}
