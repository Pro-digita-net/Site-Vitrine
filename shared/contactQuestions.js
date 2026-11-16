import { services, formations, products } from "./data.js";

const select = (id, label, options, required = false) => ({ id, label, options, required, type: "select" });
const text = (id, label, placeholder, required = false) => ({ id, label, placeholder, required, type: "text" });
const deadline = select("deadline", "Échéance souhaitée", ["Dès que possible", "Dans le mois", "Dans 1 à 3 mois", "Dans plus de 3 mois", "À définir ensemble"]);
const budget = select("budget", "Budget envisagé", ["Moins de 1 000 €", "De 1 000 à 3 000 €", "De 3 000 à 10 000 €", "Plus de 10 000 €", "À définir ensemble"]);
const teamSize = select("teamSize", "Nombre de personnes concernées", ["Moi uniquement", "2 à 10", "11 à 50", "51 à 250", "Plus de 250", "À préciser"]);

export const subjectGroups = [
  { label: "Nos expertises", items: services },
  { label: "Nos formations", items: formations },
  { label: "Nos logiciels à venir", items: products },
];
export const isKnownSubject = (subject) => subject === "Autre besoin" || subjectGroups.some(group => group.items.some(item => item.name === subject));
// Premier choix du formulaire : une expertise, ou une famille (« Formations », « Logiciels »)
// dont l'élément précis se choisit ensuite dans une seconde liste.
const families = { Formations: formations, Logiciels: products };
export const subjectTopics = [...services.map(item => item.name), ...Object.keys(families), "Autre besoin"];
// Les mêmes choix, regroupés pour l'affichage : les expertises, puis les catalogues.
export const subjectTopicGroups = [
  { label: "Nos expertises", names: services.map(item => item.name) },
  { label: "Nos catalogues", names: Object.keys(families) },
];
/** Premier choix correspondant à un sujet (ex. « Genesis CRM » → « Logiciels »). */
export const topicOf = (subject) => Object.keys(families).find(topic => families[topic].some(item => item.name === subject)) || (isKnownSubject(subject) ? subject : "");
/** Éléments d'une famille, par catégorie puis par nom ; null si le choix n'est pas une famille. */
export function topicItems(topic) {
  if (!families[topic]) return null;
  const byName = (a, b) => a.localeCompare(b, "fr");
  const groups = new Map();
  for (const item of families[topic]) groups.set(item.category, [...(groups.get(item.category) || []), item.name]);
  return [...groups].sort(([a], [b]) => byName(a, b)).map(([category, names]) => ({ category, names: names.sort(byName) }));
}
// Libellé court du type de sujet (ligne « Expertise » de la notification e-mail).
export function subjectGroupLabel(subject) {
  if (services.some(item => item.name === subject)) return "Expertise";
  if (formations.some(item => item.name === subject)) return "Formation";
  if (products.some(item => item.name === subject)) return "Logiciel";
  return "Sujet";
}

export function getContactQuestions(subject) {
  if (!isKnownSubject(subject)) return { title: "", hint: "", fields: [] };
  const service = services.find(item => item.name === subject);
  if (service?.id === "creation-web") return {
    title: "Votre projet web",
    hint: "Le type de projet et son objectif nous aident à cerner le travail à prévoir.",
    fields: [
      select("projectType", "Quel projet souhaitez-vous réaliser ?", ["Créer un site vitrine", "Créer une boutique en ligne", "Refondre un site existant", "Créer une application ou un outil sur mesure", "J’ai besoin de conseil pour choisir"], true),
      text("goal", "Quel est votre objectif principal ?", "Ex. : présenter mes services et recevoir des demandes de devis", true),
      text("existingSite", "Adresse de votre site actuel", "Ex. : www.mon-entreprise.fr"),
      text("features", "Fonctionnalités souhaitées", "Ex. : réservation, paiement, espace client, plusieurs langues"),
      select("content", "Textes, images et identité visuelle", ["Tout est prêt", "Une partie est prête", "J’ai besoin d’accompagnement", "À préciser"]),
      deadline, budget,
    ],
  };
  if (service?.id === "conseil-it") return {
    title: "Vos outils et vos priorités",
    hint: "Précisez le point à améliorer pour orienter notre analyse.",
    fields: [
      select("requestType", "Quel accompagnement recherchez-vous ?", ["Faire un état des lieux / mini-audit", "Choisir ou remplacer un outil", "Mieux organiser nos outils et nos usages", "Être conseillé sur une formation", "À définir ensemble"], true),
      text("goal", "Quelle difficulté souhaitez-vous résoudre ?", "Ex. : trop de fichiers dispersés et de saisies en double", true),
      text("tools", "Outils actuellement utilisés", "Ex. : Microsoft 365, logiciel de gestion, tableurs"),
      teamSize,
      text("constraints", "Contraintes à prendre en compte", "Ex. : outils à conserver, compatibilité, sites multiples"),
      deadline, budget,
    ],
  };
  if (service?.id === "support-it") return {
    title: "Votre besoin de support informatique",
    hint: "Ces éléments nous aident à préparer une proposition de support adaptée à votre entreprise.",
    fields: [
      select("supportNeed", "Quel support recherchez-vous ?", ["Une assistance au quotidien pour nos utilisateurs", "Confier l’ensemble de notre support informatique", "Renforcer notre équipe informatique", "Un support ponctuel, pour un projet ou une période", "À définir ensemble"], true),
      { ...teamSize, label: "Combien d’utilisateurs à accompagner ?", required: true },
      select("currentSupport", "Comment le support est-il assuré aujourd’hui ?", ["Personne en particulier", "Un collaborateur, en plus de son poste", "Une équipe ou un service interne", "Un prestataire externe", "À préciser"]),
      text("environment", "Équipements et logiciels à couvrir", "Ex. : 15 PC Windows, Microsoft 365, imprimantes, logiciel métier"),
      select("coverage", "Plages horaires souhaitées", ["Heures de bureau", "Horaires étendus", "À définir ensemble"]),
      select("interventionMode", "Mode d’intervention souhaité", ["À distance", "Sur site", "Les deux", "À définir ensemble"]),
      text("sites", "Nombre de sites et localisation", "Ex. : un bureau à Lyon, deux personnes en télétravail"),
      select("budget", "Budget mensuel envisagé", ["Moins de 200 € par mois", "De 200 à 500 € par mois", "De 500 à 1 500 € par mois", "Plus de 1 500 € par mois", "À définir ensemble"]),
      { ...deadline, label: "Date de démarrage souhaitée" },
      { ...text("phone", "Téléphone pour vous joindre", "Ex. : 06 12 34 56 78"), type: "tel" },
    ],
  };
  if (formations.some(item => item.name === subject)) return {
    title: "Votre besoin de formation",
    hint: "Votre objectif et votre niveau nous aident à vous orienter vers un contenu adapté.",
    fields: [
      select("level", "Votre niveau actuel", ["Débutant : je découvre le sujet", "Intermédiaire : je pratique déjà", "Avancé : je souhaite approfondir", "Je ne sais pas encore"], true),
      text("goal", "Que souhaitez-vous savoir faire ?", "Ex. : organiser mes données et créer un tableau de suivi", true),
      teamSize,
      text("tools", "Outils ou versions utilisés", "Ex. : Excel Microsoft 365 sur Windows"),
      text("expectations", "Questions ou besoins d’apprentissage particuliers", "Ex. : exercices pratiques, accessibilité, notions à revoir"),
      deadline,
    ],
  };
  const product = products.find(item => item.name === subject);
  if (product) return {
    title: "Vos attentes pour ce futur logiciel",
    hint: "Ce logiciel est à venir. Vos réponses nous aident à comprendre vos usages ; il ne s’agit pas d’une commande.",
    fields: [
      text("goal", "Quelle tâche souhaitez-vous simplifier ?", "Ex. : suivre les demandes et éviter les oublis", true),
      select("priority", "Votre priorité", ({
        crm: ["Suivre les contacts et les clients", "Suivre les opportunités commerciales", "Organiser les relances"],
        itsm: ["Centraliser les demandes d’assistance", "Suivre les incidents", "Inventorier le matériel"],
        knowledge: ["Retrouver les procédures", "Partager le savoir de l’équipe", "Réduire les questions répétitives"],
        invoice: ["Préparer les devis", "Créer les factures", "Suivre les règlements"],
        portal: ["Partager des documents", "Suivre les demandes des clients", "Regrouper les échanges"],
        flow: ["Enchaîner des tâches répétitives", "Préparer des résumés", "Automatiser des notifications"],
      }[product.type] || []).concat("Autre / à préciser")),
      text("tools", "Comment faites-vous aujourd’hui ?", "Ex. : e-mails, tableurs ou logiciel existant"),
      teamSize,
      text("integrations", "Outils à connecter ou contraintes importantes", "Ex. : messagerie, logiciel de gestion, import de données"),
      deadline,
    ],
  };
  return {
    title: "Précisons votre demande",
    hint: "Décrivez votre besoin dans le message. Ces précisions sont facultatives.",
    fields: [text("activity", "Votre activité ou votre secteur", "Ex. : commerce, association, cabinet de conseil"), deadline],
  };
}

export function buildContactMessage(form, answers) {
  const details = getContactQuestions(form.subject).fields
    .filter(field => String(answers[field.id] ?? "").trim())
    .map(field => `${field.label} : ${String(answers[field.id]).trim()}`);
  return [
    "Bonjour ProDigital,", form.message.trim(),
    `Sujet : ${form.subject || "À définir"}`,
    ...(details.length ? ["PRÉCISIONS SUR LA DEMANDE", ...details] : []),
    "COORDONNÉES", `Nom : ${`${form.given_name.trim()} ${form.family_name.trim()}`.trim()}`,
    `Entreprise : ${form.company.trim() || "Non précisée"}`, `E-mail : ${form.email.trim()}`,
  ].join("\n\n");
}
