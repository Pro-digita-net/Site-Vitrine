import React, { useEffect, useState } from "react";
import { createRoot } from "react-dom/client";
import {
  BrowserRouter,
  Routes,
  Route,
  Link,
  NavLink,
  useLocation,
  useParams,
  useSearchParams,
} from "react-router-dom";
import {
  ArrowUpRight,
  ArrowRight,
  ArrowDown,
  Menu,
  X,
  Monitor,
  Layers,
  Headphones,
  Users,
  Folder,
  Workflow,
  Search,
  Check,
  ChevronLeft,
  ChevronRight,
  ChevronDown,
  Mail,
  Download,
  Plus,
  LayoutDashboard,
  Bell,
  FileText,
  MessageSquare,
  CircleHelp,
  Sparkles,
  BookOpen,
  GraduationCap,
  Shield,
  Globe,
  LayoutTemplate,
  Table2,
  Lock,
  Clock3,
} from "lucide-react";
import {
  products,
  formations,
  services,
  expertiseSituations,
  projects,
  contactEmail,
} from "./data";
import { usePageMotion } from "./motion";
import { updateMetadata } from "./seo.js";
import ContactForm from "./ContactForm.jsx";
import "./styles.css";

const icons = {
  monitor: Monitor,
  layers: Layers,
  headphones: Headphones,
  users: Users,
  folder: Folder,
  workflow: Workflow,
  book: BookOpen,
  file: FileText,
  globe: Globe,
  layout: LayoutTemplate,
  table: Table2,
  mail: Mail,
  shield: Shield,
  sparkles: Sparkles,
  lock: Lock,
  graduation: GraduationCap,
};
function Icon({ name, ...props }) {
  const Component = icons[name] || Layers;
  return <Component {...props} />;
}
function Arrow() {
  return <ArrowUpRight size={18} aria-hidden="true" />;
}
function Button({
  to = "/contact",
  children = "Parlons de votre projet",
  secondary = false,
  className = "",
}) {
  return (
    <Link
      className={`button ${secondary ? "secondary" : ""} ${className}`}
      to={to}
    >
      {children}
      <Arrow />
    </Link>
  );
}
function Eyebrow({ number, children }) {
  return (
    <p className="eyebrow">
      <span>{number}</span>
      <i />
      {children}
    </p>
  );
}
function Brand() {
  return (
    <Link to="/" className="brand" aria-label="ProDigital, accueil">
      <img src="/assets/brand/prodigital-connexion.svg" alt="" />
      <span>
        ProDigital<span className="brand-dot">®</span>
      </span>
    </Link>
  );
}

function Header() {
  const [open, setOpen] = useState(false);
  const { pathname } = useLocation();
  useEffect(() => {
    setOpen(false);
  }, [pathname]);
  useEffect(() => {
    if (!open) return;
    const onKey = (e) => {
      if (e.key === "Escape") setOpen(false);
    };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [open]);
  return (
    <header className="header">
      <div className="header-inner">
        <Brand />
        <nav
          id="main-nav"
          className={open ? "nav open" : "nav"}
          aria-label="Navigation principale"
        >
          <NavLink to="/studio">Le studio</NavLink>
          <NavLink to="/expertises">Expertises</NavLink>
          <NavLink to="/formations">
            Formations <span className="nav-tag">Petit prix</span>
          </NavLink>
          <NavLink to="/projets">Projets</NavLink>
          <NavLink to="/solutions">
            Nos logiciels <span className="nav-tag">À venir</span>
          </NavLink>
          <Link className="mobile-contact" to="/contact">
            Contact
          </Link>
        </nav>
        <Link className="button" to="/contact">
          Parlons de votre projet <Arrow />
        </Link>
        <button
          className="menu-button"
          aria-expanded={open}
          aria-controls="main-nav"
          aria-label={open ? "Fermer le menu" : "Ouvrir le menu"}
          onClick={() => setOpen(!open)}
        >
          {open ? <X /> : <Menu />}
        </button>
      </div>
    </header>
  );
}
function Footer() {
  return (
    <footer className="footer" itemScope itemType="https://schema.org/Organization">
      <meta itemProp="name" content="ProDigital" />
      <meta itemProp="url" content="https://pro-digital.net" />
      <meta itemProp="email" content={contactEmail} />
      <div className="container footer-top">
        <Brand />
        <p>
          Création web.
          <br />
          Conseil et assistance informatique.
        </p>
        <div>
          <Link to="/expertises">Nos expertises</Link>
          <Link to="/formations">Formations</Link>
          <Link to="/solutions">Nos logiciels</Link>
          <Link to="/contact">Contact</Link>
        </div>
        <a href={`mailto:${contactEmail}`}>
          {contactEmail}
          <Arrow />
        </a>
      </div>
      <div className="container footer-bottom">
        <span>© {new Date().getFullYear()} ProDigital</span>
        <span>Web · Conseil · Formations · Futurs logiciels</span>
        <Link to="/confidentialite">Confidentialité</Link>
      </div>
    </footer>
  );
}
function ContactBand({
  eyebrowNumber = "ET APRÈS ?",
  eyebrow = "UNE CONVERSATION, POUR COMMENCER",
  title = (
    <>
      La suite s’écrit
      <br />
      <em>ensemble.</em>
    </>
  ),
  description = (
    <>
      Un site à créer, un outil à choisir, un problème à résoudre ?<br />
      Décrivez votre situation pour que nous puissions étudier la demande.
    </>
  ),
  buttonLabel = "Parlons de votre projet",
  to = "/contact",
} = {}) {
  return (
    <section className="contact-band">
      <div className="container contact-inner">
        <div>
          <Eyebrow number={eyebrowNumber}>{eyebrow}</Eyebrow>
          <h2>{title}</h2>
        </div>
        <div className="contact-side">
          <p>{description}</p>
          <Button to={to}>{buttonLabel}</Button>
        </div>
      </div>
    </section>
  );
}
function Breadcrumb({ items }) {
  return (
    <nav className="breadcrumb container" aria-label="Fil d’Ariane">
      <Link to="/">Accueil</Link>
      {items.map((item, i) => (
        <React.Fragment key={i}>
          <span aria-hidden="true">/</span>
          {item.to ? (
            <Link to={item.to}>{item.label}</Link>
          ) : (
            <span aria-current="page">{item.label}</span>
          )}
        </React.Fragment>
      ))}
    </nav>
  );
}

function ProductPreview({ type = "crm", large = false }) {
  return (
    <div
      className={`product-preview ${type} ${large ? "large" : ""}`}
      aria-label="Aperçu illustratif de l’interface"
    >
      <div className="preview-sidebar">
        <div className="preview-mark">
          <Layers size={18} />
        </div>
        <LayoutDashboard />
        <Users />
        <Folder />
        <MessageSquare />
        <div className="sidebar-bottom">
          <CircleHelp />
        </div>
      </div>
      <div className="preview-app">
        <div className="preview-top">
          <span>
            {type === "crm"
              ? "Genesis"
              : type === "itsm"
                ? "Orbit"
                : type === "portal"
                  ? "Votre espace"
                  : type === "knowledge"
                    ? "Connaissances"
                    : type === "invoice"
                      ? "Facturation"
                      : "Automatisations"}
            <small> / Vue d’ensemble</small>
          </span>
          <Bell size={12} />
          <span className="avatar">PD</span>
        </div>
        {type === "crm" && (
          <div className="preview-body">
            <div className="preview-heading">
              Votre activité, en un regard.<span>↗</span>
            </div>
            <div className="mini-stats">
              <div>
                <small>Prospects</small>
                <strong>24</strong>
                <span>À suivre</span>
              </div>
              <div>
                <small>Opportunités</small>
                <strong>12</strong>
                <span>En cours</span>
              </div>
              <div>
                <small>Clients</small>
                <strong>86</strong>
                <span>Relations actives</span>
              </div>
            </div>
            <div className="chart-panel">
              <span>Activité commerciale</span>
              <svg viewBox="0 0 300 80" aria-hidden="true">
                <path
                  d="M0 65H300M0 40H300M0 15H300"
                  stroke="#e9edf4"
                  fill="none"
                />
                <path
                  d="M0 70L35 60L70 63L105 38L140 47L175 22L210 30L245 12L280 18L300 3"
                  stroke="#345cff"
                  strokeWidth="3"
                  fill="none"
                />
                <path
                  d="M0 70L35 60L70 63L105 38L140 47L175 22L210 30L245 12L280 18L300 3V80H0Z"
                  fill="#345cff"
                  opacity=".07"
                />
              </svg>
            </div>
          </div>
        )}
        {type === "itsm" && (
          <div className="preview-body">
            <div className="preview-heading">
              Centre de services<span className="mini-pill">Tickets</span>
            </div>
            <div className="ticket-head">
              <span>Demande</span>
              <span>Statut</span>
            </div>
            {[
              "Accès à une application",
              "Configuration du poste",
              "Connexion réseau",
              "Mise à jour du logiciel",
            ].map((x, i) => (
              <div className="ticket-row" key={x}>
                <span>
                  <span className="checkbox" />
                  {x}
                </span>
                <b className={`status status-${i % 3}`}>
                  {["Ouvert", "En cours", "Résolu"][i % 3]}
                </b>
              </div>
            ))}
            <div className="ticket-footer">
              Toutes vos demandes, au même endroit.
            </div>
          </div>
        )}
        {type === "knowledge" && (
          <div className="preview-body knowledge-body">
            <div className="preview-heading">Une réponse à portée de main.<BookOpen size={13} /></div>
            <div className="knowledge-search"><Search size={11} /> Rechercher un article, une procédure…</div>
            <div className="knowledge-topics"><span>Premiers pas</span><span>Outils & accès</span><span>Procédures</span></div>
            {["Bien démarrer avec vos outils", "Configurer votre espace de travail", "Les réponses aux questions fréquentes"].map((title) => (
              <div className="knowledge-row" key={title}><FileText size={12} /><span>{title}</span><ChevronRight size={12} /></div>
            ))}
          </div>
        )}
        {type === "invoice" && (
          <div className="preview-body invoice-body">
            <div className="preview-heading">Chaque facture, au bon endroit.<span className="mini-pill">Ce mois-ci</span></div>
            <div className="invoice-summary"><span>Montant facturé<strong>3 050,00 €</strong></span><span className="invoice-stamp"><Check size={12} /> À jour</span></div>
            {[["FAC-001", "1 800,00 €", "Réglée"], ["FAC-002", "1 250,00 €", "Envoyée"], ["FAC-003", "1 200,00 €", "Brouillon"]].map(([ref, amount, status], i) => (
              <div className="invoice-row" key={ref}><span>{ref}</span><strong>{amount}</strong><span className={`status status-${[2, 0, 1][i]}`}>{status}</span></div>
            ))}
          </div>
        )}
        {type === "portal" && (
          <div className="preview-body">
            <div className="preview-heading">Bienvenue dans votre espace.</div>
            <p className="preview-sub">Retrouvez l’essentiel, simplement.</p>
            <div className="portal-grid">
              {[
                [MessageSquare, "Demandes"],
                [Folder, "Documents"],
                [Users, "Échanges"],
              ].map(([I, label]) => (
                <div key={label}>
                  <I />
                  <span>{label}</span>
                  <ArrowRight size={13} />
                </div>
              ))}
            </div>
            <div className="portal-note">
              <span className="small-dot" /> Votre espace de collaboration
            </div>
          </div>
        )}
        {type === "flow" && (
          <div className="preview-body">
            <div className="preview-heading">
              Des tâches qui s’enchaînent.
            </div>
            <p className="preview-sub">Vos outils travaillent ensemble.</p>
            <div className="workflow">
              {[
                [Bell, "Déclencheur"],
                [Sparkles, "Assistant IA"],
                [Check, "Action"],
              ].map(([I, label], i) => (
                <React.Fragment key={label}>
                  {i > 0 && <ArrowRight className="workflow-arrow" />}
                  <div>
                    <I />
                    <span>{label}</span>
                  </div>
                </React.Fragment>
              ))}
            </div>
            <div className="flow-note">
              <span className="small-dot" /> Exemple de parcours automatisé
            </div>
          </div>
        )}
      </div>
    </div>
  );
}
function ProductCard({ product }) {
  return (
    <Link className="product-card" to={`/solutions/${product.id}`}>
      <div className="product-art">
        <ProductPreview type={product.type} />
        <span className="preview-label">Aperçu illustratif</span>
      </div>
      <div className="product-info">
        <div className="product-meta"><span className="category-label">{product.category}</span><span className="availability"><i />{product.status}</span></div>
        <div className="product-title">
          <h3>{product.name}</h3>
          <span className="round-arrow">
            <Arrow />
          </span>
        </div>
        <p>{product.description}</p>
        <span className="text-link">
          Découvrir le logiciel à venir <ArrowRight size={16} />
        </span>
      </div>
    </Link>
  );
}
function FormationPreview({ formation, large = false }) {
  const modules = formation.features.slice(0, large ? 3 : 3);
  return (
    <div
      className={`product-preview formation ${large ? "large" : ""}`}
      aria-label="Aperçu illustratif de la formation"
    >
      <div className="preview-sidebar">
        <div className="preview-mark">
          <GraduationCap size={18} />
        </div>
        <BookOpen />
        <Monitor />
        <Sparkles />
        <Check />
        <div className="sidebar-bottom">
          <CircleHelp />
        </div>
      </div>
      <div className="preview-app">
        <div className="preview-top">
          <span>
            Formation
            <small> / {formation.category}</small>
          </span>
          <span className="avatar">PD</span>
        </div>
        <div className="preview-body formation-body">
          <div className="preview-heading">
            {formation.name}
            <span className="mini-pill">{formation.price}</span>
          </div>
          <p className="preview-sub">{formation.tagline}</p>
          <div className="formation-meta">
            <span>
              <Clock3 size={11} /> {formation.duration}
            </span>
            <span>{formation.format}</span>
          </div>
          {modules.map((module, i) => (
            <div className="formation-row" key={module}>
              <span>0{i + 1}</span>
              <span>{module}</span>
              <Check size={12} />
            </div>
          ))}
        </div>
      </div>
    </div>
  );
}
function FormationCard({ formation }) {
  return (
    <Link className="product-card" to={`/formations/${formation.id}`}>
      <div className="product-art">
        <FormationPreview formation={formation} />
        <span className="preview-label">Aperçu illustratif</span>
      </div>
      <div className="product-info">
        <div className="product-meta">
          <span className="category-label">{formation.category}</span>
          <span className="availability price">
            <i />
            {formation.price}
          </span>
        </div>
        <div className="product-title">
          <h3>{formation.name}</h3>
          <span className="round-arrow">
            <Arrow />
          </span>
        </div>
        <p>{formation.description}</p>
        <span className="text-link">
          Découvrir la formation <ArrowRight size={16} />
        </span>
      </div>
    </Link>
  );
}
function ServiceCards() {
  return (
    <div className="services-grid">
      {services.map((service) => (
        <Link
          className="service-card"
          to={`/expertises/${service.id}`}
          key={service.id}
        >
          <div className="service-card-top">
            <Icon name={service.icon} />
            <span>{service.number}</span>
          </div>
          <h3>{service.name}</h3>
          <p>{service.teaser || service.short}</p>
          <div className="service-tags">{service.tags.map((tag) => <span key={tag}>{tag}</span>)}</div>
          <span className="text-link">
            Explorer cette expertise <Arrow />
          </span>
        </Link>
      ))}
    </div>
  );
}
function FeatureList({ items }) {
  const [open, setOpen] = useState(null);
  return (
    <div className="feature-list">
      {items.map((item, i) => {
        const title = typeof item === "string" ? item : item.title;
        const description = typeof item === "string" ? "" : item.description;
        const detailId = `feature-detail-${i}`;
        const isOpen = open === i;
        const canToggle = Boolean(description);
        return (
          <div
            key={title}
            className={`feature-item${isOpen ? " is-open" : ""}${canToggle ? " is-toggle" : ""}`}
          >
            <span>0{i + 1}</span>
            <div className="feature-copy">
              <h3>{title}</h3>
              {canToggle && (
                <div
                  className="feature-detail"
                  hidden={!isOpen}
                  id={detailId}
                >
                  <p>{description}</p>
                </div>
              )}
            </div>
            {canToggle ? (
              <button
                type="button"
                className="feature-toggle"
                aria-expanded={isOpen}
                aria-controls={detailId}
                aria-label={
                  isOpen
                    ? `Masquer le détail de ${title}`
                    : `Afficher le détail de ${title}`
                }
                onClick={() => setOpen(isOpen ? null : i)}
              >
                <ChevronDown size={18} />
              </button>
            ) : (
              <Check size={20} />
            )}
          </div>
        );
      })}
    </div>
  );
}
const defaultMethodSteps = [
  [
    "Écouter",
    "Clarifier votre besoin, vos contraintes et vos priorités.",
  ],
  [
    "Concevoir",
    "Définir la structure du projet et les choix à valider ensemble.",
  ],
  ["Réaliser", "Construire la solution, la tester et préparer son lancement."],
  ["Accompagner", "Faciliter la prise en main et définir les évolutions utiles."],
];
function Method({
  number = "05",
  title = (
    <>
      Un projet clair,
      <br />
      <em>étape par étape.</em>
    </>
  ),
  steps = defaultMethodSteps,
} = {}) {
  const [hoveredStep, setHoveredStep] = useState(null);
  return (
    <section className="method section">
      <div className="container">
        <div className="section-heading">
          <Eyebrow number={number}>NOTRE MÉTHODE</Eyebrow>
          <h2>{title}</h2>
        </div>
        <div
          className="method-grid"
          onPointerLeave={() => setHoveredStep(null)}
          style={{ "--method-hover": hoveredStep === null ? undefined : hoveredStep / 3 }}
        >
          <div className="method-path" aria-hidden="true"><span className="method-path-fill" /></div>
          {steps.map(([title, description], i) => (
            <div
              key={title}
              className={`method-step${hoveredStep === i ? " is-active" : ""}`}
              onPointerEnter={(event) => { if (event.pointerType !== "touch") setHoveredStep(i); }}
              style={{ "--hover-reached": hoveredStep === null ? undefined : Number(i <= hoveredStep) }}
            >
              <span className="method-node" aria-hidden="true" />
              <div className="method-step-copy">
              <span className="step-index">0{i + 1}</span>
              <h3>{title}</h3>
              <p>{description}</p>
              </div>
            </div>
          ))}
        </div>
      </div>
    </section>
  );
}
function Home() {
  return (
    <>
      <section className="hero container">
        <div className="hero-copy">
          <Eyebrow number="01">STUDIO DIGITAL & IT</Eyebrow>
          <h1>
            Le digital
            <br />
            <span className="hero-verb">prend</span> <em>forme.</em>
          </h1>
          <p className="hero-italic">Création web et accompagnement informatique.</p>
          <p className="hero-description">
            Indépendants, TPE, PME et groupes : nous créons vos sites web,
            vous conseillons sur vos outils et accompagnons vos équipes
            dans leur quotidien informatique.
          </p>
          <div className="hero-actions">
            <Button />
            <Link className="quiet-link" to="/expertises">
              Découvrir nos expertises <ArrowUpRight size={16} />
            </Link>
          </div>
        </div>
        <div className="hero-mobile-foot"><p>Création de sites web.<br />Conseil et assistance informatique.</p><button type="button" onClick={() => document.getElementById("home-offers")?.scrollIntoView({ behavior: window.matchMedia("(prefers-reduced-motion: reduce)").matches ? "instant" : "smooth" })}><span>Faites<br />défiler</span><ArrowDown size={18} /></button></div><div className="hero-art">
          <div className="hero-frame">
            <img
              src="/assets/brand/connexion-office.webp"
              srcSet="/assets/brand/connexion-office-640.webp 640w, /assets/brand/connexion-office.webp 1254w"
              sizes="(max-width: 680px) calc(100vw - 40px), (max-width: 1400px) 46vw, 600px"
              alt="Sculpture ProDigital en métal bleu sur un bureau, dans un atelier lumineux"
              fetchPriority="high"
            />
          </div>
          <div className="art-note"><span className="art-note-symbol"><ArrowUpRight size={20} /></span><div>Relier les idées.<br /><strong>Créer l’essentiel.</strong></div></div>
          <div className="art-caption">
            <span>DU CONCEPT AU CONCRET</span>
            <span>ProDigital — Studio</span>
          </div>
        </div>
      </section>
      <div id="home-offers" className="offer-strip container" aria-label="Nos domaines d’intervention">
        <span>À VOS CÔTÉS,<br /><strong>À CHAQUE ÉTAPE.</strong></span>
        {services.map((service) => <Link key={service.id} to={`/expertises/${service.id}`}><Icon name={service.icon} /><span>{service.name}<small>{service.tags.join(" · ")}</small></span><Arrow /></Link>)}
      </div>
      <section className="vision container">
        <Eyebrow number="02">NOTRE VISION</Eyebrow>
        <div>
          <h2>
            Partir de vos usages.
            <br className="mobile-break" /> Choisir <em>l’essentiel.</em>
          </h2>
          <p>
            Avant de choisir une solution, nous cherchons à comprendre ce qui
            fonctionne déjà et ce qui vous freine.
            <br />
            Ces observations guident les fonctionnalités, les contenus et les priorités du projet.
          </p>
        </div>
      </section>
      <section className="expertises section dark">
        <div className="container">
          <div className="section-heading split">
            <div>
              <Eyebrow number="03">NOS EXPERTISES</Eyebrow>
              <h2>
                Trois expertises.
                <br />
                <em>Une même exigence.</em>
              </h2>
            </div>
            <p>
              Créer votre site, choisir vos outils
              <br />
              ou obtenir une assistance informatique.
            </p>
          </div>
          <ServiceCards />
        </div>
      </section>
      <section className="section container">
        <div className="section-heading split">
          <div>
            <Eyebrow number="04">PROJETS SÉLECTIONNÉS</Eyebrow>
            <h2>
              Des idées.
              <br />
              <em>Du caractère.</em>
            </h2>
          </div>
          <Link className="quiet-link" to="/projets">
            Explorer les projets <Arrow />
          </Link>
        </div>
        <div className="projects-grid">
          {projects.map((project, i) => (
            <Link
              to={`/projets/${project.id}`}
              className={`project-card project-${i}`}
              key={project.id}
            >
              <div className="project-image">
                <img
                  src={project.image}
                  alt={`Interface du concept ${project.name}`}
                  loading="lazy"
                  decoding="async"
                />
                <span className="project-badge">PROJET CONCEPT</span>
                <span className="round-arrow">
                  <Arrow />
                </span>
              </div>
              <div className="project-caption">
                <h3>{project.name}</h3>
                <span>{project.category}</span>
              </div>
            </Link>
          ))}
        </div>
      </section>
      <Method />
      <section className="section container home-solutions">
        <div className="section-heading split">
          <div>
            <Eyebrow number="06">NOS FUTURS OUTILS</Eyebrow>
            <h2>
              Des usages concrets.
              <br />
              <em>Des logiciels à venir.</em>
            </h2>
          </div>
          <div className="section-intro">
            <p>
              Suivi des clients, assistance informatique, procédures et facturation :
              découvrez les usages envisagés pour nos futurs logiciels
              et partagez les difficultés que vous aimeriez résoudre.
            </p>
            <Link className="quiet-link" to="/solutions">
              Tous les logiciels à venir <Arrow />
            </Link>
          </div>
        </div>
        <div className="products-grid">
          {products
            .filter((p) => p.featured)
            .slice(0, 4)
            .map((product) => (
              <ProductCard product={product} key={product.id} />
            ))}
        </div>
        <div className="catalog-footer">
          <span>Quel outil serait utile à votre équipe ? Découvrez les projets envisagés.</span>
          <Button to="/solutions" secondary>
            Explorer nos futurs logiciels
          </Button>
        </div>
      </section>
      <section className="section container home-formations">
        <div className="section-heading split">
          <div>
            <Eyebrow number="07">NOS FORMATIONS</Eyebrow>
            <h2>
              Apprendre vite.
              <br />
              <em>Payer peu.</em>
            </h2>
          </div>
          <div className="section-intro">
            <p>
              Web, bureautique, sécurité, IA et assistance IT :
              des formations courtes conçues avec l’assistance de l’IA,
              proposées à tarif accessible.
            </p>
            <Link className="quiet-link" to="/formations">
              Tout le catalogue <Arrow />
            </Link>
          </div>
        </div>
        <div className="products-grid">
          {formations
            .filter((f) => f.featured)
            .slice(0, 4)
            .map((formation) => (
              <FormationCard formation={formation} key={formation.id} />
            ))}
        </div>
        <div className="catalog-footer">
          <span>Des contenus clairs, créés avec l’IA, pour monter en compétence sans budget élevé.</span>
          <Button to="/formations" secondary>
            Explorer les formations
          </Button>
        </div>
      </section>
      <ContactBand />
    </>
  );
}

function Catalog() {
  const [params, setParams] = useSearchParams();
  const query = params.get("q") || "";
  const category = params.get("categorie") || "Tous les usages";
  const categories = [
    "Tous les usages",
    ...new Set(products.map((p) => p.category)),
  ];
  const normalize = (value) =>
    value
      .normalize("NFD")
      .replace(/[\u0300-\u036f]/g, "")
      .toLowerCase();
  const filtered = products.filter(
    (p) =>
      (category === "Tous les usages" || p.category === category) &&
      normalize(`${p.name} ${p.category} ${p.description}`).includes(
        normalize(query),
      ),
  );
  const pageSize = 6,
    pages = Math.max(1, Math.ceil(filtered.length / pageSize));
  const page = Math.min(
    pages,
    Math.max(1, Number.parseInt(params.get("page"), 10) || 1),
  );
  function change(key, value) {
    const next = new URLSearchParams(params);
    if (value) next.set(key, value);
    else next.delete(key);
    next.delete("page");
    setParams(next, { replace: true });
  }
  return (
    <>
      <Breadcrumb items={[{ label: "Nos logiciels" }]} />
      <section className="container page-heading catalog-heading">
        <Eyebrow number="LE CATALOGUE">LOGICIELS À VENIR</Eyebrow>
        <h1>
          Nos futurs logiciels,
          <br />
          <em>vos usages en tête.</em>
        </h1>
        <p>
          Relation client, assistance informatique, partage des connaissances et facturation.
          <br className="desktop-break" /> Ces logiciels sont en préparation et ne sont pas encore disponibles.
        </p>
        <div className="catalog-notice"><span className="availability"><i />Logiciels à venir</span><span>Les aperçus illustrent des fonctionnalités envisagées. Aucune date de lancement n’est annoncée pour le moment.</span></div>
      </section>
      <section className="container catalog-content">
        <div className="catalog-controls">
          <label className="search-field">
            <Search size={20} />
            <input
              type="search"
              aria-label="Rechercher un logiciel"
              placeholder="Rechercher un logiciel, un usage…"
              value={query}
              onChange={(e) => change("q", e.target.value)}
            />
          </label>
          <span className="result-count" aria-live="polite">
            {filtered.length} logiciel{filtered.length !== 1 ? "s" : ""} à venir
          </span>
        </div>
        <div className="filter-list" aria-label="Filtrer par usage">
          {categories.map((c) => (
            <button
              key={c}
              className={category === c ? "filter active" : "filter"}
              aria-pressed={category === c}
              onClick={() =>
                change("categorie", c === "Tous les usages" ? "" : c)
              }
            >
              {c}
            </button>
          ))}
        </div>
        {filtered.length ? (
          <div className="products-grid">
            {filtered.slice((page - 1) * pageSize, page * pageSize).map((p) => (
              <ProductCard product={p} key={p.id} />
            ))}
          </div>
        ) : (
          <div className="empty-state">
            <Search />
            <h2>Aucun logiciel ne correspond à votre recherche.</h2>
            <p>Essayez un autre mot-clé ou élargissez les filtres.</p>
            <button className="button" onClick={() => setParams({})}>
              Réinitialiser la recherche <ArrowRight size={18} />
            </button>
          </div>
        )}
        {pages > 1 && (
          <nav className="pagination" aria-label="Pages du catalogue">
            <button
              disabled={page === 1}
              onClick={() => {
                const next = new URLSearchParams(params);
                next.set("page", String(page - 1));
                setParams(next);
              }}
              aria-label="Page précédente"
            >
              <ChevronLeft />
            </button>
            <span>
              Page {page} sur {pages}
            </span>
            <button
              disabled={page === pages}
              onClick={() => {
                const next = new URLSearchParams(params);
                next.set("page", String(page + 1));
                setParams(next);
              }}
              aria-label="Page suivante"
            >
              <ChevronRight />
            </button>
          </nav>
        )}
        <div className="catalog-help">
          <Icon name="workflow" />
          <div>
            <h2>Votre besoin sort du cadre ?</h2>
            <p>
              Parlons de vos outils, de vos usages et de ce que vous souhaitez
              simplifier.
            </p>
          </div>
          <Button secondary>Échangeons</Button>
        </div>
      </section>
      <ContactBand />
    </>
  );
}
function ProductDetail() {
  const { id } = useParams();
  const product = products.find((p) => p.id === id);
  if (!product) return <NotFound />;
  return (
    <>
      <Breadcrumb
        items={[
          { label: "Nos logiciels", to: "/solutions" },
          { label: product.name },
        ]}
      />
      <section className="container product-detail-hero">
        <div>
          <div className="product-meta detail-meta"><span className="category-label">{product.category}</span><span className="availability"><i />{product.status}</span></div>
          <h1>{product.name}</h1>
          <h2>
            <em>{product.tagline}</em>
          </h2>
          <p>{product.description}</p>
          <Button to={`/contact?solution=${encodeURIComponent(product.name)}`}>
            Partager mon besoin
          </Button>
        </div>
        <div className="detail-preview">
          <ProductPreview type={product.type} large />
          <span className="preview-label">
            Interface illustrative · données de démonstration
          </span>
        </div>
      </section>
      <section className="container detail-grid section">
        <div>
          <Eyebrow number="01">FONCTIONNALITÉS ENVISAGÉES</Eyebrow>
          <h2>
            Pour quels usages,
            <br />
            <em>pour quelles équipes ?</em>
          </h2>
          <p>{product.audience}</p>
        </div>
        <div className="feature-list">
          {product.features.map((feature, i) => (
            <div key={feature}>
              <span>0{i + 1}</span>
              <h3>{feature}</h3>
              <Check size={20} />
            </div>
          ))}
        </div>
      </section>
      <section className="container product-disclaimer">
        <CircleHelp />
        <p>
          Ce logiciel n’est pas encore disponible. Les interfaces et les données sont illustratives ;
          les fonctionnalités envisagées peuvent évoluer.
          Vous pouvez nous contacter pour expliquer vos usages et contribuer à la réflexion.
        </p>
      </section>
      <section className="container section">
        <div className="section-heading split">
          <h2>
            À découvrir <em>aussi.</em>
          </h2>
          <Link to="/solutions" className="quiet-link">
            Tous les logiciels à venir <Arrow />
          </Link>
        </div>
        <div className="related-grid">
          {products
            .filter((p) => p.id !== id)
            .slice(0, 3)
            .map((p) => (
              <Link
                to={`/solutions/${p.id}`}
                className="related-card"
                key={p.id}
              >
                <Icon name={p.icon} />
                <span>{p.category}</span>
                <h3>{p.name}</h3>
                <Arrow />
              </Link>
            ))}
        </div>
      </section>
      <ContactBand />
    </>
  );
}
function FormationsCatalog() {
  const [params, setParams] = useSearchParams();
  const query = params.get("q") || "";
  const category = params.get("categorie") || "Tous les thèmes";
  const categories = [
    "Tous les thèmes",
    ...new Set(formations.map((f) => f.category)),
  ];
  const normalize = (value) =>
    value
      .normalize("NFD")
      .replace(/[\u0300-\u036f]/g, "")
      .toLowerCase();
  const filtered = formations.filter(
    (f) =>
      (category === "Tous les thèmes" || f.category === category) &&
      normalize(`${f.name} ${f.category} ${f.description}`).includes(
        normalize(query),
      ),
  );
  const pageSize = 6,
    pages = Math.max(1, Math.ceil(filtered.length / pageSize));
  const page = Math.min(
    pages,
    Math.max(1, Number.parseInt(params.get("page"), 10) || 1),
  );
  function change(key, value) {
    const next = new URLSearchParams(params);
    if (value) next.set(key, value);
    else next.delete(key);
    next.delete("page");
    setParams(next, { replace: true });
  }
  return (
    <>
      <Breadcrumb items={[{ label: "Formations" }]} />
      <section className="container page-heading catalog-heading">
        <Eyebrow number="LE CATALOGUE">FORMATIONS</Eyebrow>
        <h1>
          Monter en compétence,
          <br />
          <em>sans se ruiner.</em>
        </h1>
        <p>
          Web, bureautique, sécurité, IA et assistance IT.
          <br className="desktop-break" /> Des formations courtes, conçues avec
          l’assistance de l’IA, proposées à petit prix.
        </p>
        <div className="catalog-notice">
          <span className="availability price">
            <i />
            À partir de 19 €
          </span>
          <span>
            Contenus créés avec l’assistance de l’IA pour rester clairs, à jour
            et accessibles. Format en ligne, à votre rythme.
          </span>
        </div>
      </section>
      <section className="container catalog-content">
        <div className="catalog-controls">
          <label className="search-field">
            <Search size={20} />
            <input
              type="search"
              aria-label="Rechercher une formation"
              placeholder="Rechercher une formation, un thème…"
              value={query}
              onChange={(e) => change("q", e.target.value)}
            />
          </label>
          <span className="result-count" aria-live="polite">
            {filtered.length} formation{filtered.length !== 1 ? "s" : ""}
          </span>
        </div>
        <div className="filter-list" aria-label="Filtrer par thème">
          {categories.map((c) => (
            <button
              key={c}
              className={category === c ? "filter active" : "filter"}
              aria-pressed={category === c}
              onClick={() =>
                change("categorie", c === "Tous les thèmes" ? "" : c)
              }
            >
              {c}
            </button>
          ))}
        </div>
        {filtered.length ? (
          <div className="products-grid">
            {filtered.slice((page - 1) * pageSize, page * pageSize).map((f) => (
              <FormationCard formation={f} key={f.id} />
            ))}
          </div>
        ) : (
          <div className="empty-state">
            <Search />
            <h2>Aucune formation ne correspond à votre recherche.</h2>
            <p>Essayez un autre mot-clé ou élargissez les filtres.</p>
            <button className="button" onClick={() => setParams({})}>
              Réinitialiser la recherche <ArrowRight size={18} />
            </button>
          </div>
        )}
        {pages > 1 && (
          <nav className="pagination" aria-label="Pages du catalogue">
            <button
              disabled={page === 1}
              onClick={() => {
                const next = new URLSearchParams(params);
                next.set("page", String(page - 1));
                setParams(next);
              }}
              aria-label="Page précédente"
            >
              <ChevronLeft />
            </button>
            <span>
              Page {page} sur {pages}
            </span>
            <button
              disabled={page === pages}
              onClick={() => {
                const next = new URLSearchParams(params);
                next.set("page", String(page + 1));
                setParams(next);
              }}
              aria-label="Page suivante"
            >
              <ChevronRight />
            </button>
          </nav>
        )}
        <div className="catalog-help">
          <Icon name="graduation" />
          <div>
            <h2>Besoin d’une formation sur mesure ?</h2>
            <p>
              Nous pouvons adapter un parcours à votre niveau, votre outil ou
              votre équipe.
            </p>
          </div>
          <Button secondary>Échangeons</Button>
        </div>
      </section>
      <ContactBand />
    </>
  );
}
function FormationDetail() {
  const { id } = useParams();
  const formation = formations.find((f) => f.id === id);
  if (!formation) return <NotFound />;
  return (
    <>
      <Breadcrumb
        items={[
          { label: "Formations", to: "/formations" },
          { label: formation.name },
        ]}
      />
      <section className="container product-detail-hero">
        <div>
          <div className="product-meta detail-meta">
            <span className="category-label">{formation.category}</span>
            <span className="availability price">
              <i />
              {formation.price}
            </span>
          </div>
          <h1>{formation.name}</h1>
          <h2>
            <em>{formation.tagline}</em>
          </h2>
          <p>{formation.description}</p>
          <p className="formation-detail-meta">
            <span>
              <Clock3 size={16} /> {formation.duration}
            </span>
            <span>{formation.format}</span>
          </p>
          <Button
            to={`/contact?formation=${encodeURIComponent(formation.name)}`}
          >
            Demander cette formation
          </Button>
        </div>
        <div className="detail-preview">
          <FormationPreview formation={formation} large />
          <span className="preview-label">
            Parcours illustratif · contenu assisté par IA
          </span>
        </div>
      </section>
      <section className="container detail-grid section">
        <div>
          <Eyebrow number="01">AU PROGRAMME</Eyebrow>
          <h2>
            Ce que vous
            <br />
            <em>allez apprendre.</em>
          </h2>
          <p>{formation.audience}</p>
        </div>
        <div className="feature-list">
          {formation.features.map((feature, i) => (
            <div key={feature}>
              <span>0{i + 1}</span>
              <h3>{feature}</h3>
              <Check size={20} />
            </div>
          ))}
        </div>
      </section>
      <section className="container product-disclaimer">
        <CircleHelp />
        <p>
          Cette formation est conçue avec l’assistance de l’IA pour rester claire
          et accessible. Le contenu peut évoluer. Contactez-nous pour confirmer
          le tarif, le format et l’accès.
        </p>
      </section>
      <section className="container section">
        <div className="section-heading split">
          <h2>
            À découvrir <em>aussi.</em>
          </h2>
          <Link to="/formations" className="quiet-link">
            Toutes les formations <Arrow />
          </Link>
        </div>
        <div className="related-grid">
          {formations
            .filter((f) => f.id !== id)
            .slice(0, 3)
            .map((f) => (
              <Link
                to={`/formations/${f.id}`}
                className="related-card"
                key={f.id}
              >
                <Icon name={f.icon} />
                <span>{f.category}</span>
                <h3>{f.name}</h3>
                <Arrow />
              </Link>
            ))}
        </div>
      </section>
      <ContactBand />
    </>
  );
}
function ExpertiseIndex() {
  return (
    <>
      <Breadcrumb items={[{ label: "Nos expertises" }]} />
      <section className="container page-heading expertise-intro">
        <Eyebrow number="LE SAVOIR-FAIRE">WEB & IT</Eyebrow>
        <h1>
          De l’idée
          <br />
          <em>au quotidien.</em>
        </h1>
        <p>
          De la création de votre site internet à l’accompagnement de votre
          environnement informatique, ProDigital vous aide à construire,
          optimiser et maintenir des solutions adaptées à vos besoins.
        </p>
        <p>
          Trois domaines d’expertise, un même objectif : simplifier votre
          quotidien et accompagner le développement de votre activité.
        </p>
      </section>
      <section className="dark section">
        <div className="container">
          <div className="section-heading split">
            <div>
              <Eyebrow number="01">TROIS DOMAINES</Eyebrow>
              <h2>
                Des expertises concrètes.
                <br />
                <em>Des prestations claires.</em>
              </h2>
            </div>
            <p>
              Choisissez le domaine qui correspond à votre besoin,
              <br className="desktop-break" /> puis découvrez le détail des prestations.
            </p>
          </div>
          <ServiceCards />
        </div>
      </section>
      <section className="section container expertise-panels">
        {services.map((service) => (
          <article className="expertise-panel" key={service.id}>
            <div className="expertise-panel-copy">
              <Eyebrow number={service.number}>NOTRE EXPERTISE</Eyebrow>
              <h2>{service.name}</h2>
              <p className="expertise-panel-lead">
                <em>{service.short}</em>
              </p>
              <p>{service.description}</p>
              <div className="expertise-panel-actions">
                <Button
                  to={`/expertises/${service.id}`}
                  secondary
                  className="expertise-panel-cta"
                >
                  Voir le détail
                </Button>
                {service.id === "conseil-it" && (
                  <Link className="quiet-link" to="/formations">
                    Catalogue de formations <Arrow />
                  </Link>
                )}
              </div>
            </div>
            <FeatureList items={service.deliverables} />
          </article>
        ))}
      </section>
      <section className="section container expertise-situations">
        <div className="section-heading">
          <Eyebrow number="02">VOTRE SITUATION</Eyebrow>
          <h2>
            Des solutions adaptées
            <br />
            <em>à votre réalité.</em>
          </h2>
        </div>
        <div className="situations-grid">
          {expertiseSituations.map((situation, i) => (
            <div className="situation-item" key={situation.id}>
              <span className="step-index">0{i + 1}</span>
              <h3>{situation.title}</h3>
              <p>{situation.description}</p>
            </div>
          ))}
        </div>
      </section>
      <Method
        number="03"
        steps={[
          [
            "Comprendre",
            "Identifier les objectifs, les contraintes et les besoins.",
          ],
          [
            "Proposer",
            "Définir une solution adaptée avec un périmètre clair.",
          ],
          [
            "Réaliser",
            "Mettre en œuvre, vérifier et livrer la prestation.",
          ],
          [
            "Accompagner",
            "Assurer le suivi convenu et les évolutions nécessaires.",
          ],
        ]}
      />
      <ContactBand
        eyebrowNumber="ET MAINTENANT ?"
        eyebrow="PRENONS CONTACT"
        title={
          <>
            Parlons de votre
            <br />
            <em>prochain projet.</em>
          </>
        }
        description="Un site à créer, une question informatique ou un besoin d’accompagnement ? Présentez-nous votre situation et échangeons sur les solutions envisageables."
        buttonLabel="Parlons de votre projet"
        to="/contact"
      />
    </>
  );
}
function ServiceDetail() {
  const { id } = useParams();
  const service = services.find((s) => s.id === id);
  if (!service) return <NotFound />;
  return (
    <>
      <Breadcrumb
        items={[
          { label: "Expertises", to: "/expertises" },
          { label: service.name },
        ]}
      />
      <section className="container service-hero">
        <div>
          <Eyebrow number={service.number}>NOTRE EXPERTISE</Eyebrow>
          <h1>{service.name}</h1>
          <h2>
            <em>{service.short}</em>
          </h2>
          <p>{service.description}</p>
          <Button to={`/contact?service=${encodeURIComponent(service.name)}`}>
            Parlons de votre besoin
          </Button>
        </div>
        <div className="service-photo">
          <img
            src={
              id === "creation-web" ? "/assets/photos/developpement-web.jpg" :
              id === "conseil-it" ? "/assets/photos/conseil-informatique.jpg" :
              "/assets/photos/assistance-informatique.jpg"
            }
            srcSet={
              id === "creation-web" ? "/assets/photos/developpement-web-640.jpg 640w, /assets/photos/developpement-web.jpg 1600w" :
              id === "conseil-it" ? "/assets/photos/conseil-informatique-640.jpg 640w, /assets/photos/conseil-informatique.jpg 1600w" :
              "/assets/photos/assistance-informatique-640.jpg 640w, /assets/photos/assistance-informatique.jpg 1600w"
            }
            sizes="(max-width: 760px) 90vw, 45vw"
            alt={
              id === "creation-web" ? "Développement d’un site web : code affiché sur un ordinateur portable et un écran" :
              id === "conseil-it" ? "Deux professionnels examinent un besoin autour d’un ordinateur et de notes" :
              "Professionnelle équipée d’un casque pour une assistance à distance sur ordinateur"
            }
          />
          <span>
            <Icon name={service.icon} /> {service.name}
          </span>
        </div>
      </section>
      <section className="section dark">
        <div className="container detail-grid">
          <div>
            <Eyebrow number="L’ACCOMPAGNEMENT">DU CADRAGE À L’ACTION</Eyebrow>
            <h2>
              Ce que comprend
              <br />
              <em>l’accompagnement.</em>
            </h2>
          </div>
          <FeatureList items={service.deliverables} />
        </div>
      </section>
      <section className="container section detail-grid questions-section">
        <div className="questions-heading">
          <Eyebrow number="03">PASSER À L’ACTION</Eyebrow>
          <h2>
            Ça vous
            <br />
            <em>parle ?</em>
          </h2>
        </div>
        <div className="questions">
          <ul className="questions-list">
            {service.questions.map((q) => (
              <li key={q}>
                <Check aria-hidden="true" />
                <span>{q}</span>
              </li>
            ))}
          </ul>
          <div className="questions-actions">
            <Button to={`/contact?service=${encodeURIComponent(service.name)}`}>
              Discutons-en
            </Button>
            {service.id === "conseil-it" ? (
              <Link className="quiet-link" to="/formations">
                Voir le catalogue de formations <Arrow />
              </Link>
            ) : (
              <Link className="quiet-link" to="/expertises">
                Toutes nos expertises <Arrow />
              </Link>
            )}
          </div>
        </div>
      </section>
      <ContactBand />
    </>
  );
}
function Projects() {
  return (
    <>
      <Breadcrumb items={[{ label: "Projets" }]} />
      <section className="container page-heading">
        <Eyebrow number="EXPLORATIONS">DESIGN & INTERFACES</Eyebrow>
        <h1>
          Donner forme
          <br />
          <em>aux idées.</em>
        </h1>
        <p>
          Deux projets concepts pour expliquer nos choix de design et d’organisation des contenus.
          <br className="desktop-break" /> Des explorations de conception,
          sans commande client ni résultats commerciaux revendiqués.
        </p>
      </section>
      <section className="container project-list">
        {projects.map((p, i) => (
          <Link
            key={p.id}
            className="project-list-item"
            to={`/projets/${p.id}`}
          >
            <div>
              <Eyebrow number={`0${i + 1}`}>PROJET CONCEPT</Eyebrow>
              <h2>{p.name}</h2>
              <p>{p.description}</p>
              <span className="text-link">
                Découvrir le projet <Arrow />
              </span>
            </div>
            <img src={p.image} alt={`Aperçu du concept ${p.name}`} decoding="async" />
          </Link>
        ))}
      </section>
      <ContactBand />
    </>
  );
}
function ProjectDetail() {
  const { id } = useParams();
  const project = projects.find((p) => p.id === id);
  if (!project) return <NotFound />;
  return (
    <>
      <Breadcrumb
        items={[{ label: "Projets", to: "/projets" }, { label: project.name }]}
      />
      <section className="container page-heading">
        <Eyebrow number="PROJET CONCEPT">{project.category}</Eyebrow>
        <h1>{project.name}</h1>
        <p>{project.description}</p>
      </section>
      <div className="container case-image">
        <img
          src={project.image}
          alt={`Interface complète du projet concept ${project.name}`}
        />
      </div>
      <section className="container section detail-grid">
        <div>
          <Eyebrow number="L’INTENTION">{project.title}</Eyebrow>
          <h2>
            Chaque choix
            <br />
            <em>a son rôle.</em>
          </h2>
          <p>{project.challenge}</p>
        </div>
        <div className="feature-list">
          {project.choices.map((choice, i) => (
            <div key={choice}>
              <span>0{i + 1}</span>
              <h3>{choice}</h3>
            </div>
          ))}
        </div>
      </section>
      <ContactBand />
    </>
  );
}
function Studio() {
  return (
    <>
      <Breadcrumb items={[{ label: "Le studio" }]} />
      <section className="container studio-hero">
        <div>
          <Eyebrow number="PRODIGITAL">STUDIO DIGITAL & IT</Eyebrow>
          <h1>
            Le web et l’informatique,
            <br />
            <em>
              au service
              <br />de vos usages.
            </em>
          </h1>
          <p>
            ProDigital réunit une équipe d’agents et de développeurs spécialisés
            dans les interfaces web et les fonctionnalités côté serveur.
            Nous nous appuyons sur plus de 8 ans d’expérience en développement web
            et 5 ans en support informatique pour accompagner les indépendants,
            les TPE, les PME et les groupes.
          </p>
          <Button secondary>Faisons connaissance</Button>
        </div>
        <img
          src="/assets/photos/collaboration.jpg"
          srcSet="/assets/photos/collaboration-640.jpg 640w, /assets/photos/collaboration.jpg 1600w"
          sizes="(max-width: 760px) 90vw, 45vw"
          alt="Photo d’illustration : collaboration autour de plusieurs ordinateurs portables"
        />
      </section>
      <Method />
      <section className="container section studio-values">
        <Eyebrow number="NOTRE EXPÉRIENCE">AU CONTACT DES UTILISATEURS</Eyebrow>
        <h2>
          L’expérience du terrain.
          <br />
          <em>Le savoir à partager.</em>
        </h2>
        <p>
          Notre expérience au sein de différentes directions des systèmes d’information
          (DSI) nous a appris à comprendre les contraintes des équipes et les difficultés
          des utilisateurs. Formés, diplômés et certifiés, nous associons ces compétences
          à une approche pratique. Nos formations sur mesure permettent d’acquérir
          des bases solides et d’approfondir les sujets de notre catalogue,
          selon votre niveau et vos objectifs.
        </p>
      </section>
      <ContactBand />
    </>
  );
}

function Contact() {
  const [params] = useSearchParams();
  const initial =
    params.get("formation") ||
    params.get("solution") ||
    params.get("service") ||
    "";
  return (
    <>
      <Breadcrumb items={[{ label: "Contact" }]} />
      <section className="container contact-page">
        <div className="contact-copy">
          <Eyebrow number="PREMIER ÉCHANGE">FAISONS CONNAISSANCE</Eyebrow>
          <h1>
            Présentez-nous
            <br />
            <em>votre projet.</em>
          </h1>
          <p>
            Décrivez ce que vous souhaitez créer ou améliorer, les outils déjà utilisés
            et votre échéance si vous en avez une. Ces éléments nous aideront à
            comprendre votre demande avant le premier échange.
          </p>
          <a className="contact-mail" href={`mailto:${contactEmail}`}>
            <Mail />
            {contactEmail}
            <Arrow />
          </a>
          <div className="contact-next">
            <h3>Et ensuite ?</h3>
            <p>
              <span>01</span> Nous lisons votre message pour comprendre la demande.
            </p>
            <p>
              <span>02</span> Nous précisons ensemble les objectifs et les contraintes.
            </p>
            <p>
              <span>03</span> Nous déterminons si nous pouvons intervenir et dans quel périmètre.
            </p>
          </div>
        </div>
        <ContactForm initialSubject={initial} />
      </section>
    </>
  );
}
function Privacy() {
  return (
    <>
      <Breadcrumb items={[{ label: "Confidentialité" }]} />
      <article className="container legal-page">
        <Eyebrow number="VOS DONNÉES">CONFIDENTIALITÉ</Eyebrow>
        <h1>
          Confidentialité
          <br />
          <em>et données personnelles.</em>
        </h1>
        <h2>Formulaire de contact</h2>
        <p>
          Lorsque vous envoyez le formulaire, les informations saisies
          (identité, e-mail, entreprise, sujet, précisions et message) sont
          transmises à ProDigital, enregistrées sur nos serveurs et dans notre
          outil de suivi des demandes, puis signalées à notre équipe par
          e-mail. Elles servent uniquement à traiter votre demande et à vous
          répondre. Rien n’est transmis tant que vous n’avez pas cliqué sur
          « Envoyer ma demande ».
        </p>
        <h2>Mesure d’audience</h2>
        <p>
          Cette version du site n’intègre pas d’outil publicitaire ni de mesure
          d’audience ajouté par ProDigital. L’hébergement et les services de
          messagerie peuvent traiter les données techniques nécessaires à leur
          fonctionnement.
        </p>
        <h2>Nous contacter</h2>
        <p>
          Pour toute question relative à vos échanges ou à vos données, écrivez
          à <a href={`mailto:${contactEmail}`}>{contactEmail}</a>.
        </p>
      </article>
    </>
  );
}
function NotFound() {
  return (
    <section className="container not-found">
      <Eyebrow number="404">PAGE INTROUVABLE</Eyebrow>
      <h1>
        Reprenons
        <br />
        <em>le bon chemin.</em>
      </h1>
      <p>Cette page n’existe pas ou a changé d’adresse.</p>
      <Button to="/">Revenir à l’accueil</Button>
    </section>
  );
}
function RouteEffects() {
  const { pathname } = useLocation();
  useEffect(() => {
    updateMetadata(pathname);
  }, [pathname]);
  return null;
}
export function Shell() {
  const location = useLocation();
  usePageMotion(location.pathname);
  return (
    <>
      <RouteEffects />
      <a
        className="skip-link"
        href="#main"
        onClick={(e) => {
          e.preventDefault();
          document.getElementById("main").focus();
        }}
      >
        Aller au contenu
      </a>
      <Header />
      <main id="main" tabIndex={-1}>
        {/* La clé remonte la page à chaque navigation : les animations repartent d’un DOM neuf. */}
        <Routes location={location} key={location.pathname}>
          <Route path="/" element={<Home />} />
          <Route path="/solutions" element={<Catalog />} />
          <Route path="/solutions/:id" element={<ProductDetail />} />
          <Route path="/formations" element={<FormationsCatalog />} />
          <Route path="/formations/:id" element={<FormationDetail />} />
          <Route path="/expertises" element={<ExpertiseIndex />} />
          <Route path="/expertises/:id" element={<ServiceDetail />} />
          <Route path="/projets" element={<Projects />} />
          <Route path="/projets/:id" element={<ProjectDetail />} />
          <Route path="/studio" element={<Studio />} />
          <Route path="/contact" element={<Contact />} />
          <Route path="/confidentialite" element={<Privacy />} />
          <Route path="*" element={<NotFound />} />
        </Routes>
      </main>
      <Footer />
    </>
  );
}
function App() {
  return (
    <BrowserRouter>
      <Shell />
    </BrowserRouter>
  );
}
if (typeof document !== "undefined") {
if (location.hash.startsWith("#/")) history.replaceState(null, "", location.hash.slice(1));
createRoot(document.getElementById("root")).render(
  <React.StrictMode>
    <App />
  </React.StrictMode>,
);

}
