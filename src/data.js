// Chaque entrée alimente automatiquement le catalogue et sa page détaillée.
export const products = [
  {
    id: "genesis-crm",
    name: "Genesis CRM",
    category: "Relation client",
    type: "crm",
    status: "À venir",
    tagline: "Chaque relation mérite un suivi clair.",
    description:
      "Centralisez vos prospects, vos clients et vos opportunités dans un même espace.",
    icon: "users",
    featured: true,
    features: [
      "Suivi des prospects et des clients",
      "Vue des opportunités commerciales",
      "Organisation des activités",
    ],
    audience:
      "Pour les équipes qui souhaitent structurer leur relation client et retrouver une vue commune sur leur activité.",
  },
  {
    id: "orbit-itsm",
    name: "Orbit ITSM",
    category: "Gestion IT",
    type: "itsm",
    status: "À venir",
    tagline: "Votre activité IT, sous contrôle.",
    description:
      "Organisez les tickets, les incidents et les actifs de votre environnement IT.",
    icon: "layers",
    featured: true,
    features: [
      "Organisation des tickets et incidents",
      "Suivi des services IT",
      "Vue sur les actifs informatiques",
    ],
    audience:
      "Pour les équipes IT qui souhaitent centraliser leurs demandes et mieux organiser leur travail quotidien.",
  },
  {
    id: "base-de-connaissances",
    name: "Base de connaissances",
    category: "Connaissances",
    type: "knowledge",
    status: "À venir",
    tagline: "Le savoir partagé. Le temps retrouvé.",
    description: "Retrouvez vos procédures, guides et réponses utiles dans une base commune.",
    icon: "book",
    featured: true,
    features: ["Organisation des articles et procédures", "Recherche dans les connaissances", "Partage des bonnes pratiques"],
    audience: "Pour les équipes qui souhaitent rendre leur savoir accessible et éviter de répondre plusieurs fois aux mêmes questions.",
  },
  {
    id: "facturation",
    name: "Facturation",
    category: "Gestion d’activité",
    type: "invoice",
    status: "À venir",
    tagline: "Vos factures, en toute simplicité.",
    description: "Un futur outil pour préparer vos devis, créer vos factures et suivre vos règlements.",
    icon: "file",
    featured: true,
    features: ["Préparation des devis", "Création des factures", "Suivi des règlements"],
    audience: "Pour les indépendants et les petites entreprises qui souhaitent simplifier leur gestion administrative au quotidien.",
  },
  {
    id: "portail-client",
    name: "Portail Client",
    category: "Collaboration",
    type: "portal",
    status: "À venir",
    tagline: "Un espace commun. Des échanges simples.",
    description:
      "Réunissez demandes, documents et échanges dans un espace dédié à vos clients.",
    icon: "folder",
    featured: false,
    features: [
      "Centralisation des demandes",
      "Accès aux documents",
      "Organisation des échanges",
    ],
    audience:
      "Pour les entreprises qui souhaitent proposer à leurs clients un point d’entrée clair pour leurs échanges.",
  },
  {
    id: "automatisation-ia",
    name: "Automatisation & IA",
    category: "Automatisation",
    type: "flow",
    status: "À venir",
    tagline: "Moins de répétition. Plus de temps utile.",
    description:
      "Simplifiez vos workflows, vos notifications et vos tâches métier récurrentes.",
    icon: "workflow",
    featured: false,
    features: [
      "Organisation des workflows",
      "Automatisation des notifications",
      "Assistants métier",
    ],
    audience:
      "Pour les équipes qui identifient des tâches répétitives et souhaitent étudier une automatisation adaptée.",
  },
];
export const services = [
  {
    id: "creation-web",
    name: "Création web",
    icon: "monitor",
    number: "01",
    short: "Des sites singuliers. Des expériences évidentes.",
    tags: ["Sites vitrines", "E-commerce", "Sur mesure"],
    description:
      "Site vitrine, boutique en ligne ou projet sur mesure : une présence web pensée pour votre activité, vos utilisateurs et vos objectifs. Du premier échange à la mise en ligne, chaque détail a sa place.",
    deliverables: [
      "Cadrage du projet et de ses objectifs",
      "Architecture de contenu et parcours",
      "Direction artistique et interfaces responsive",
      "Développement et préparation au lancement",
    ],
    questions: [
      "Vous lancez une activité ou une nouvelle offre ?",
      "Votre site actuel ne reflète plus votre entreprise ?",
      "Vous souhaitez simplifier le parcours de vos visiteurs ?",
    ],
  },
  {
    id: "conseil-it",
    name: "Conseil IT",
    icon: "layers",
    number: "02",
    short: "Des choix éclairés. Une direction claire.",
    tags: ["Mini-audit", "Conseil", "Formation"],
    description:
      "Un mini-audit pour faire le point, du conseil pour choisir les bons outils et des formations pour mieux les utiliser. Un accompagnement concret, adapté à votre niveau et à votre activité.",
    deliverables: [
      "Mini-audit de vos outils et de votre environnement",
      "Identification des priorités",
      "Recommandations et choix de solutions",
      "Formation et prise en main de vos outils",
    ],
    questions: [
      "Vos outils répondent-ils encore à vos besoins ?",
      "Vous devez choisir ou faire évoluer une solution ?",
      "Vous souhaitez clarifier les étapes de votre projet IT ?",
    ],
  },
  {
    id: "support-it",
    name: "Support IT",
    icon: "headphones",
    number: "03",
    short: "Des outils fiables. Un quotidien plus serein.",
    tags: ["Helpdesk N1", "Assistance", "Suivi"],
    description:
      "Un helpdesk de niveau 1 pour les difficultés informatiques du quotidien : accès, postes de travail et utilisation des logiciels. Les demandes sont qualifiées, suivies et orientées vers le bon interlocuteur si nécessaire.",
    deliverables: [
      "Qualification des demandes et des incidents",
      "Assistance à l’utilisation des outils",
      "Suivi des interventions",
      "Orientation des incidents nécessitant un niveau d’expertise supérieur",
    ],
    questions: [
      "Des incidents perturbent votre activité ?",
      "Vos équipes ont besoin d’un accompagnement ?",
      "Vous souhaitez mieux organiser le suivi de vos outils ?",
    ],
  },
];
export const projects = [
  {
    id: "atelier-morel",
    name: "Atelier Morel",
    category: "Direction artistique · Création web",
    image: "/assets/reference/architecture-screen-hd.svg",
    photo: "/assets/architecture.webp",
    title: "Laisser l’architecture parler.",
    description:
      "Un concept de portfolio architectural qui donne toute sa place aux images et à la découverte des projets.",
    challenge:
      "Présenter un univers architectural avec une navigation claire et des visuels capables de raconter chaque réalisation.",
    choices: [
      "Photographies grand format et hiérarchie éditoriale",
      "Navigation épurée pour découvrir les projets",
      "Déclinaison des interfaces sur ordinateur et mobile",
    ],
  },
  {
    id: "espace-pro",
    name: "Espace Pro",
    category: "Conception d’interface · Outil métier",
    image: "/assets/reference/dashboard-screen-hd.svg",
    photo: "/assets/desk.webp",
    title: "Rendre l’information lisible.",
    description:
      "Un concept d’espace de travail pour centraliser le suivi des projets et rendre les priorités visibles.",
    challenge:
      "Rassembler les informations de suivi dans une interface organisée, facile à parcourir au quotidien.",
    choices: [
      "Vue d’ensemble des projets et des tâches",
      "Statuts visuels pour faciliter la lecture",
      "Navigation latérale et regroupement des informations",
    ],
  },
];
export const contactEmail = "contact@pro-digital.net";
