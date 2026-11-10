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
      "Un logiciel en préparation pour réunir vos contacts, vos opportunités commerciales et les actions à suivre.",
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
    category: "Gestion informatique",
    type: "itsm",
    status: "À venir",
    tagline: "Un point de suivi pour vos demandes informatiques.",
    description:
      "Un logiciel en préparation pour suivre les demandes d’assistance, les incidents et le matériel informatique.",
    icon: "layers",
    featured: true,
    features: [
      "Organisation des tickets et incidents",
      "Suivi des services informatiques",
      "Inventaire du matériel informatique",
    ],
    audience:
      "Pour les équipes informatiques qui souhaitent retrouver les demandes en cours, leur statut et les équipements concernés.",
  },
  {
    id: "base-de-connaissances",
    name: "Base de connaissances",
    category: "Connaissances",
    type: "knowledge",
    status: "À venir",
    tagline: "Le savoir partagé. Le temps retrouvé.",
    description: "Un logiciel en préparation pour regrouper vos procédures, vos guides et les réponses aux questions fréquentes.",
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
    name: "Portail client",
    category: "Collaboration",
    type: "portal",
    status: "À venir",
    tagline: "Un espace commun. Des échanges simples.",
    description:
      "Un espace client en préparation pour réunir les demandes, les documents partagés et les échanges liés à un projet.",
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
      "Un projet d’outil pour enchaîner des tâches répétitives : recevoir une demande, en préparer un résumé et prévenir la personne concernée.",
    icon: "workflow",
    featured: false,
    features: [
      "Enchaînement de tâches à partir d’une demande",
      "Notifications aux personnes concernées",
      "Résumés assistés par IA, à vérifier avant utilisation",
    ],
    audience:
      "Pour les équipes qui identifient des tâches répétitives et souhaitent étudier une automatisation adaptée.",
  },
];

// Catalogue de formations : mêmes champs que les logiciels (catalogue + page détail).
// Contenus conçus avec l’assistance de l’IA, proposés à tarif accessible.
export const formations = [
  {
    id: "bases-du-web",
    name: "Bases du web",
    category: "Création web",
    type: "web",
    status: "Petit prix",
    price: "19 €",
    tagline: "Comprendre comment un site est construit.",
    description:
      "Une formation courte pour découvrir le HTML, le CSS et l’organisation d’une page web, sans jargon inutile.",
    icon: "monitor",
    featured: true,
    duration: "3 h",
    format: "En ligne · à votre rythme",
    features: [
      "Structure d’une page HTML",
      "Styles CSS essentiels",
      "Bonnes pratiques de lisibilité",
    ],
    audience:
      "Pour les débutants, les créateurs d’activité et toute personne qui souhaite comprendre le web avant de faire réaliser un site.",
  },
  {
    id: "site-vitrine",
    name: "Créer un site vitrine",
    category: "Création web",
    type: "web",
    status: "Petit prix",
    price: "29 €",
    tagline: "De l’idée à une présence en ligne claire.",
    description:
      "Les étapes pour préparer, structurer et publier un site vitrine : pages utiles, contenus, parcours et mise en ligne.",
    icon: "globe",
    featured: true,
    duration: "4 h",
    format: "En ligne · à votre rythme",
    features: [
      "Définir les pages et le message",
      "Organiser le parcours visiteur",
      "Préparer la publication",
    ],
    audience:
      "Pour les indépendants et les TPE qui veulent lancer ou refondre un site vitrine avec méthode.",
  },
  {
    id: "wordpress-essentiel",
    name: "WordPress essentiel",
    category: "Création web",
    type: "cms",
    status: "Petit prix",
    price: "29 €",
    tagline: "Gérer votre site sans dépendre de personne.",
    description:
      "Prise en main de WordPress : pages, articles, médias, menus et gestes utiles pour faire évoluer votre site au quotidien.",
    icon: "layout",
    featured: true,
    duration: "3 h 30",
    format: "En ligne · à votre rythme",
    features: [
      "Pages, articles et médias",
      "Menus et réglages utiles",
      "Gestes de maintenance simples",
    ],
    audience:
      "Pour les personnes qui héritent d’un site WordPress ou souhaitent le faire évoluer en autonomie.",
  },
  {
    id: "excel-quotidien",
    name: "Excel du quotidien",
    category: "Bureautique",
    type: "office",
    status: "Petit prix",
    price: "19 €",
    tagline: "Des tableaux utiles, sans complexité.",
    description:
      "Les bases d’Excel pour classer, calculer et présenter des informations utiles au travail quotidien.",
    icon: "table",
    featured: true,
    duration: "3 h",
    format: "En ligne · à votre rythme",
    features: [
      "Organisation des données",
      "Formules essentielles",
      "Tableaux et filtres",
    ],
    audience:
      "Pour les collaborateurs qui manipulent des listes, des suivis ou des bilans simples dans Excel.",
  },
  {
    id: "microsoft-365",
    name: "Microsoft 365 au travail",
    category: "Bureautique",
    type: "office",
    status: "Petit prix",
    price: "24 €",
    tagline: "Outlook, Teams et OneDrive, sans friction.",
    description:
      "Une formation pratique pour mieux utiliser la messagerie, les réunions et le partage de fichiers dans Microsoft 365.",
    icon: "mail",
    featured: false,
    duration: "3 h",
    format: "En ligne · à votre rythme",
    features: [
      "Messagerie et organisation",
      "Réunions et collaboration",
      "Fichiers partagés et versions",
    ],
    audience:
      "Pour les équipes qui utilisent Microsoft 365 et souhaitent gagner du temps sur les gestes du quotidien.",
  },
  {
    id: "securite-numerique",
    name: "Sécurité numérique",
    category: "Sécurité",
    type: "security",
    status: "Petit prix",
    price: "19 €",
    tagline: "Les bons réflexes face aux risques courants.",
    description:
      "Reconnaître le phishing, protéger ses comptes et adopter les gestes essentiels pour limiter les incidents au quotidien.",
    icon: "shield",
    featured: true,
    duration: "2 h 30",
    format: "En ligne · à votre rythme",
    features: [
      "Mots de passe et double authentification",
      "Repérer les tentatives de fraude",
      "Réagir en cas d’incident",
    ],
    audience:
      "Pour tous les utilisateurs qui souhaitent réduire les risques liés aux e-mails, aux comptes et aux appareils.",
  },
  {
    id: "ia-au-travail",
    name: "L’IA au travail",
    category: "Intelligence artificielle",
    type: "ai",
    status: "Petit prix",
    price: "24 €",
    tagline: "Demander mieux. Gagner du temps.",
    description:
      "Apprendre à utiliser ChatGPT et les assistants IA pour rédiger, résumer et préparer des tâches, avec un regard critique sur les résultats.",
    icon: "sparkles",
    featured: true,
    duration: "3 h",
    format: "En ligne · à votre rythme",
    features: [
      "Formuler des demandes efficaces",
      "Rédiger et résumer plus vite",
      "Vérifier et corriger les réponses",
    ],
    audience:
      "Pour les professionnels qui veulent intégrer l’IA dans leur travail sans perdre le contrôle sur le contenu produit.",
  },
  {
    id: "support-premier-niveau",
    name: "Support IT de premier niveau",
    category: "Assistance IT",
    type: "support",
    status: "Petit prix",
    price: "29 €",
    tagline: "Diagnostiquer. Orienter. Débloquer.",
    description:
      "Les gestes essentiels pour analyser une panne simple, guider un utilisateur et savoir quand transmettre à un spécialiste.",
    icon: "headphones",
    featured: false,
    duration: "4 h",
    format: "En ligne · à votre rythme",
    features: [
      "Recueillir les bons éléments",
      "Vérifications de base",
      "Suivi et escalade",
    ],
    audience:
      "Pour les référents informatiques, les assistants et les personnes qui assistent déjà leurs collègues au quotidien.",
  },
  {
    id: "rgpd-essentiel",
    name: "RGPD essentiel",
    category: "Conformité",
    type: "data",
    status: "Petit prix",
    price: "19 €",
    tagline: "Les bases pour traiter les données correctement.",
    description:
      "Comprendre les principes du RGPD appliqués aux petites structures : formulaires, conservation, droits des personnes.",
    icon: "lock",
    featured: false,
    duration: "2 h 30",
    format: "En ligne · à votre rythme",
    features: [
      "Principes et vocabulaire utiles",
      "Formulaires et consentement",
      "Droits des personnes",
    ],
    audience:
      "Pour les indépendants et les TPE qui collectent des données via un site, un formulaire ou un outil métier.",
  },
  {
    id: "automatiser-avec-ia",
    name: "Automatiser avec l’IA",
    category: "Productivité",
    type: "ai",
    status: "Petit prix",
    price: "29 €",
    tagline: "Moins de tâches répétitives. Plus de temps utile.",
    description:
      "Identifier les tâches répétitives et les enchaîner avec l’aide de l’IA : résumés, préparations de messages, check-lists.",
    icon: "workflow",
    featured: false,
    duration: "3 h 30",
    format: "En ligne · à votre rythme",
    features: [
      "Repérer les tâches à automatiser",
      "Construire des enchaînements simples",
      "Contrôler le résultat avant envoi",
    ],
    audience:
      "Pour les personnes qui perdent du temps sur des tâches répétitives et souhaitent tester une automatisation légère.",
  },
];

export const services = [
  {
    id: "creation-web",
    name: "Création web",
    icon: "monitor",
    number: "01",
    short: "Une présence digitale à votre image, conçue pour vos objectifs.",
    teaser: "Sites modernes, performants et pensés pour valoriser votre activité.",
    tags: ["Sites vitrines", "E-commerce", "Sur mesure"],
    description:
      "Nous concevons des sites internet modernes, performants et adaptés à votre activité. Chaque projet est pensé pour valoriser votre entreprise, offrir une expérience fluide à vos visiteurs et faciliter la prise de contact.",
    deliverables: [
      {
        title: "Sites vitrines professionnels",
        description:
          "Un site clair pour présenter votre activité, vos services et faciliter la prise de contact.",
      },
      {
        title: "Sites e-commerce",
        description:
          "Une boutique en ligne pour présenter vos produits, gérer les commandes et accompagner vos ventes.",
      },
      {
        title: "Refonte et modernisation",
        description:
          "Mise à jour de votre site existant : design, structure, lisibilité et expérience mobile.",
      },
      {
        title: "Développement web sur mesure",
        description:
          "Des pages ou fonctionnalités spécifiques adaptées à votre métier, au-delà d’un modèle standard.",
      },
      {
        title: "Optimisation mobile, performance et SEO",
        description:
          "Un site rapide, agréable sur mobile et mieux préparé pour être trouvé sur les moteurs de recherche.",
      },
      {
        title: "Mise en ligne, maintenance et évolutions",
        description:
          "Publication du site, suivi après lancement et évolutions selon vos besoins.",
      },
    ],
    questions: [
      "Vous lancez une activité ou une nouvelle offre ?",
      "Votre site actuel ne reflète plus votre entreprise ?",
      "Vous souhaitez simplifier le parcours de vos visiteurs ?",
    ],
  },
  {
    id: "conseil-it",
    name: "Conseil IT & Formation",
    icon: "layers",
    number: "02",
    short: "Les bons outils, les bonnes décisions, les bonnes pratiques.",
    teaser: "Choisir vos outils, optimiser votre environnement et monter en compétence.",
    tags: ["Audit", "Conseil", "Formations"],
    description:
      "Nous accompagnons les professionnels dans leurs choix technologiques, l’amélioration de leur environnement informatique et le développement de leurs compétences numériques.",
    deliverables: [
      {
        title: "Diagnostic et audit informatique",
        description:
          "Un état des lieux de vos outils, usages et points de friction pour identifier les priorités.",
      },
      {
        title: "Conseil en équipements et logiciels",
        description:
          "Des recommandations concrètes pour choisir ou faire évoluer vos postes, logiciels et services.",
      },
      {
        title: "Optimisation des outils de travail",
        description:
          "Réorganisation des usages du quotidien pour gagner en clarté, en temps et en fiabilité.",
      },
      {
        title: "Accompagnement à la transformation digitale",
        description:
          "Un cadrage progressif pour faire évoluer vos méthodes et vos outils sans tout bouleverser.",
      },
      {
        title: "Sensibilisation aux risques numériques",
        description:
          "Les bons réflexes face au phishing, aux mots de passe et aux incidents courants.",
      },
      {
        title: "Formations Excel, bureautique et cybersécurité du quotidien",
        description:
          "Des parcours courts et accessibles pour monter en compétence, seuls ou en équipe.",
      },
    ],
    questions: [
      "Vos outils répondent-ils encore à vos besoins ?",
      "Vous devez choisir ou faire évoluer une solution ?",
      "Vous souhaitez former vos équipes ou monter en compétence ?",
    ],
  },
  {
    id: "support-it",
    name: "Support & Assistance IT",
    icon: "headphones",
    number: "03",
    short: "Un problème informatique ne devrait pas freiner votre activité.",
    teaser: "Assistance adaptée pour garder vos outils opérationnels au quotidien.",
    tags: ["Diagnostic", "Assistance", "Suivi"],
    description:
      "Nous aidons les professionnels à résoudre leurs difficultés informatiques et à maintenir leurs outils opérationnels grâce à une assistance adaptée à leurs besoins.",
    deliverables: [
      {
        title: "Diagnostic et résolution d’incidents",
        description:
          "Analyse du problème, vérification des causes probables et actions pour rétablir le service.",
      },
      {
        title: "Assistance à distance ou sur site selon disponibilité",
        description:
          "Une aide adaptée à la situation : prise en main à distance ou intervention sur place si nécessaire.",
      },
      {
        title: "Configuration des logiciels et messageries",
        description:
          "Mise en place et réglages des outils du quotidien : messagerie, accès, applications métier.",
      },
      {
        title: "Installation et paramétrage des postes",
        description:
          "Préparation des ordinateurs, comptes utilisateurs et logiciels pour un démarrage serein.",
      },
      {
        title: "Maintenance et optimisation informatique",
        description:
          "Entretien régulier et ajustements pour limiter les pannes et garder un environnement stable.",
      },
      {
        title: "Suivi des demandes et accompagnement utilisateurs",
        description:
          "Un suivi clair des demandes et une aide pour que chacun retrouve ses marques sur les outils.",
      },
    ],
    questions: [
      "Des incidents perturbent votre activité ?",
      "Vos équipes ont besoin d’un accompagnement ?",
      "Vous souhaitez mieux organiser le suivi de vos outils ?",
    ],
  },
];

export const expertiseSituations = [
  {
    id: "lancement",
    title: "Vous lancez votre activité ?",
    description:
      "Nous vous aidons à construire votre présence en ligne et à choisir vos premiers outils numériques.",
  },
  {
    id: "croissance",
    title: "Votre entreprise se développe ?",
    description:
      "Nous accompagnons l’évolution de vos équipements, logiciels et méthodes de travail.",
  },
  {
    id: "incidents",
    title: "Vous rencontrez des difficultés informatiques ?",
    description:
      "Nous vous aidons à identifier les problèmes, trouver des solutions et limiter leur réapparition.",
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
      "Le besoin imaginé : permettre à un visiteur de découvrir le travail d’un atelier d’architecture. La difficulté : laisser de la place aux photographies tout en gardant des repères pour parcourir les projets. Ce concept explore cet équilibre, sans représenter une commande client.",
    choices: [
      "Des photographies grand format pour mettre les réalisations au premier plan",
      "Des titres et une navigation épurés pour guider la découverte des projets",
      "Une présentation adaptée au mobile pour conserver la lisibilité des images et des textes",
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
      "Le besoin imaginé : retrouver les projets en cours et les tâches à suivre dans un même espace. La difficulté : rendre les priorités visibles sans surcharger l’écran. Ce concept d’interface explore une organisation de l’information, sans représenter un logiciel livré à un client.",
    choices: [
      "Une vue d’ensemble pour repérer les projets et les tâches à suivre",
      "Des statuts distincts pour identifier ce qui est en cours ou terminé",
      "Une navigation latérale pour accéder aux informations par rubrique",
    ],
  },
];
export const contactEmail = "contact@pro-digital.net";
