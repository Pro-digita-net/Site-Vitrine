import React, { useEffect, useState } from "react";
import { createRoot } from "react-dom/client";
import {
  HashRouter,
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
} from "lucide-react";
import { products, services, projects, contactEmail } from "./data";
import { usePageMotion } from "./motion";
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
          <NavLink to="/projets">Projets</NavLink>
          <NavLink to="/solutions">
            Nos SaaS <span className="nav-tag">À venir</span>
          </NavLink>
          <Link className="mobile-contact" to="/contact">
            Contact
          </Link>
        </nav>
        <Link className="header-contact" to="/contact">
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
    <footer className="footer">
      <div className="container footer-top">
        <Brand />
        <p>
          Une idée claire.
          <br />
          Une exécution précise.
        </p>
        <div>
          <Link to="/expertises">Nos expertises</Link>
          <Link to="/solutions">Catalogue SaaS</Link>
          <Link to="/contact">Contact</Link>
        </div>
        <a href={`mailto:${contactEmail}`}>
          {contactEmail}
          <Arrow />
        </a>
      </div>
      <div className="container footer-bottom">
        <span>© {new Date().getFullYear()} ProDigital</span>
        <span>Web · Conseil IT · Support · SaaS</span>
        <Link to="/confidentialite">Confidentialité</Link>
      </div>
    </footer>
  );
}
function ContactBand() {
  return (
    <section className="contact-band">
      <div className="container contact-inner">
        <div>
          <Eyebrow number="ET APRÈS ?">
            UNE CONVERSATION, POUR COMMENCER
          </Eyebrow>
          <h2>
            La suite s’écrit
            <br />
            <em>ensemble.</em>
          </h2>
        </div>
        <div className="contact-side">
          <p>
            Une idée, un besoin, un projet ?<br />
            Prenons le temps d’en parler et de définir les prochaines étapes.
          </p>
          <Button />
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
              "Mise à jour logiciel",
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
            <div className="invoice-summary"><span>Montant facturé<strong>4 250,00 €</strong></span><span className="invoice-stamp"><Check size={12} /> À jour</span></div>
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
              Un workflow. Moins de répétition.
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
          Découvrir la solution <ArrowRight size={16} />
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
          <p>{service.short}</p>
          <div className="service-tags">{service.tags.map((tag) => <span key={tag}>{tag}</span>)}</div>
          <span className="text-link">
            Explorer cette expertise <Arrow />
          </span>
        </Link>
      ))}
    </div>
  );
}
function Method() {
  return (
    <section className="method section">
      <div className="container">
        <div className="section-heading">
          <Eyebrow number="05">NOTRE MÉTHODE</Eyebrow>
          <h2>
            De la première idée
            <br />
            <em>à la prochaine étape.</em>
          </h2>
        </div>
        <div className="method-grid">
          {[
            [
              "Écouter",
              "Comprendre vos enjeux, vos utilisateurs et vos contraintes.",
            ],
            [
              "Concevoir",
              "Donner une structure claire à la solution et à son expérience.",
            ],
            ["Réaliser", "Construire, vérifier et préparer la mise en ligne."],
            ["Accompagner", "Faire évoluer vos outils avec votre activité."],
          ].map(([title, description], i) => (
            <div key={title}>
              <span className="step-index">0{i + 1}</span>
              <h3>{title}</h3>
              <p>{description}</p>
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
          <p className="hero-italic">L’IT suit le mouvement.</p>
          <p className="hero-description">
            Un site qui vous ressemble. Une informatique qui vous simplifie la vie.
            Création web, conseil et support IT : avançons ensemble.
          </p>
          <div className="hero-actions">
            <Button />
            <Link className="quiet-link" to="/expertises">
              Découvrir nos expertises <ArrowUpRight size={16} />
            </Link>
          </div>
        </div>
        <div className="hero-mobile-foot"><p>Des sites qui vous ressemblent.<br />Des outils qui vous simplifient la vie.</p><button type="button" onClick={() => document.getElementById("home-offers")?.scrollIntoView({ behavior: window.matchMedia("(prefers-reduced-motion: reduce)").matches ? "instant" : "smooth" })}><span>Faites<br />défiler</span><ArrowDown size={18} /></button></div><div className="hero-art">
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
            Un digital utile.
            <br className="mobile-break" /> Un impact <em>durable.</em>
          </h2>
          <p>
            Des sites qui vous ressemblent. Des outils qui vous simplifient la
            vie.
            <br />
            Nous relions le design, la technologie et vos enjeux métier.
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
              Une vision d’ensemble, une attention
              <br />
              portée à chaque détail.
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
            <Eyebrow number="06">L’ÉCOSYSTÈME PRODIGITAL</Eyebrow>
            <h2>
              Vos ambitions.
              <br />
              <em>Les bons outils.</em>
            </h2>
          </div>
          <div className="section-intro">
            <p>
              CRM, ITSM, base de connaissances, facturation…
              Nous préparons des outils pour simplifier votre quotidien.
              Découvrez les solutions à venir.
            </p>
            <Link className="quiet-link" to="/solutions">
              Tout le catalogue <Arrow />
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
          <span>Un besoin spécifique ? Construisons la bonne réponse.</span>
          <Button to="/solutions" secondary>
            Explorer le catalogue
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
      <Breadcrumb items={[{ label: "Nos SaaS" }]} />
      <section className="container page-heading catalog-heading">
        <Eyebrow number="LE CATALOGUE">SOLUTIONS SAAS</Eyebrow>
        <h1>
          À chaque besoin,
          <br />
          <em>le bon outil.</em>
        </h1>
        <p>
          Notre écosystème se construit : CRM, ITSM, connaissances et facturation.
          <br className="desktop-break" /> Découvrez nos futurs outils et partagez vos besoins.
        </p>
        <div className="catalog-notice"><span className="availability"><i />Solutions à venir</span><span>Des aperçus pour découvrir notre vision. Les dates de lancement seront annoncées ici.</span></div>
      </section>
      <section className="container catalog-content">
        <div className="catalog-controls">
          <label className="search-field">
            <Search size={20} />
            <input
              type="search"
              aria-label="Rechercher une solution"
              placeholder="Rechercher une solution, un usage…"
              value={query}
              onChange={(e) => change("q", e.target.value)}
            />
          </label>
          <span className="result-count" aria-live="polite">
            {filtered.length} solution{filtered.length !== 1 ? "s" : ""}
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
            <h2>Aucune solution ne correspond.</h2>
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
          { label: "Nos SaaS", to: "/solutions" },
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
            Discuter de mon besoin
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
          <Eyebrow number="01">POUR VOTRE ACTIVITÉ</Eyebrow>
          <h2>
            Un usage clair.
            <br />
            <em>Une solution adaptée.</em>
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
          Cette solution est à venir. Les interfaces et les données sont illustratives ;
          les fonctionnalités présentées décrivent la direction envisagée.
          Contactez-nous pour partager vos besoins et échanger sur le projet.
        </p>
      </section>
      <section className="container section">
        <div className="section-heading split">
          <h2>
            À découvrir <em>aussi.</em>
          </h2>
          <Link to="/solutions" className="quiet-link">
            Tout le catalogue <Arrow />
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
function ExpertiseIndex() {
  return (
    <>
      <Breadcrumb items={[{ label: "Nos expertises" }]} />
      <section className="container page-heading">
        <Eyebrow number="LE SAVOIR-FAIRE">WEB & IT</Eyebrow>
        <h1>
          De l’idée
          <br />
          <em>au quotidien.</em>
        </h1>
        <p>
          Créer votre présence en ligne, éclairer vos choix technologiques
          <br className="desktop-break" /> et accompagner vos outils dans la
          durée.
        </p>
      </section>
      <section className="dark section">
        <div className="container">
          <ServiceCards />
        </div>
      </section>
      <Method />
      <ContactBand />
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
              id === "creation-web"
                ? "/assets/architecture.webp"
                : "/assets/reference/studio-photo.webp"
            }
            alt={
              id === "creation-web"
                ? "Architecture contemporaine, inspiration pour un projet web"
                : "Carnet de conception et outils de travail sur un bureau"
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
              Avancer avec
              <br />
              <em>une vision claire.</em>
            </h2>
          </div>
          <div className="feature-list">
            {service.deliverables.map((d, i) => (
              <div key={d}>
                <span>0{i + 1}</span>
                <h3>{d}</h3>
                <Arrow />
              </div>
            ))}
          </div>
        </div>
      </section>
      <section className="container section detail-grid">
        <h2>
          Ça vous
          <br />
          <em>parle ?</em>
        </h2>
        <div className="questions">
          {service.questions.map((q) => (
            <p key={q}>
              <Check />
              {q}
            </p>
          ))}
          <Button
            to={`/contact?service=${encodeURIComponent(service.name)}`}
            secondary
          >
            Discutons-en
          </Button>
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
          Deux projets concepts pour explorer notre approche du design,
          <br className="desktop-break" /> des contenus et des outils
          numériques.
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
            Une idée claire.
            <br />
            <em>
              Une attention
              <br />à chaque détail.
            </em>
          </h1>
          <p>
            Nous réunissons création web, conseil IT, support et solutions SaaS
            autour d’une même intention. Concevoir des outils utiles, cohérents
            et agréables à utiliser.
          </p>
          <Button secondary>Faisons connaissance</Button>
        </div>
        <img
          src="/assets/reference/studio-photo.webp"
          alt="Carnet de croquis et stylo dans un espace de travail lumineux"
        />
      </section>
      <Method />
      <section className="container section studio-values">
        <Eyebrow number="NOTRE APPROCHE">FAIRE SIMPLE, FAIRE JUSTE</Eyebrow>
        <h2>
          Comprendre avant de concevoir.
          <br />
          <em>Accompagner après le lancement.</em>
        </h2>
        <p>
          Chaque projet commence par un échange. Nous clarifions les besoins,
          choisissons une direction et avançons étape par étape. Le design et la
          technique prennent leur sens lorsqu’ils servent votre activité.
        </p>
      </section>
      <ContactBand />
    </>
  );
}

function Contact() {
  const [params] = useSearchParams();
  const initial = params.get("solution") || params.get("service") || "";
  const [form, setForm] = useState({
    name: "",
    email: "",
    company: "",
    subject: initial,
    message: "",
  });
  const [prepared, setPrepared] = useState(false);
  const update = (e) => {
    setForm({ ...form, [e.target.name]: e.target.value });
    setPrepared(false);
  };
  const body = () =>
    `Bonjour ProDigital,\n\n${form.message}\n\nSujet : ${form.subject || "À définir"}\nNom : ${form.name}\nEntreprise : ${form.company || "Non précisée"}\nE-mail : ${form.email}`;
  const emailHref = `mailto:${contactEmail}?subject=${encodeURIComponent("Projet ProDigital — " + (form.subject || "Premier échange"))}&body=${encodeURIComponent(body())}`;
  function submit(e) {
    e.preventDefault();
    setPrepared(true);
  }
  function download() {
    const blob = new Blob([body()], { type: "text/plain;charset=utf-8" });
    const url = URL.createObjectURL(blob);
    const a = document.createElement("a");
    a.href = url;
    a.download = "mon-projet-prodigital.txt";
    a.click();
    setTimeout(() => URL.revokeObjectURL(url), 1000);
  }
  return (
    <>
      <Breadcrumb items={[{ label: "Contact" }]} />
      <section className="container contact-page">
        <div className="contact-copy">
          <Eyebrow number="PREMIER ÉCHANGE">FAISONS CONNAISSANCE</Eyebrow>
          <h1>
            La suite s’écrit
            <br />
            <em>ensemble.</em>
          </h1>
          <p>
            Parlez-nous de votre activité, de vos idées et de ce que vous
            aimeriez simplifier. Nous définirons les prochaines étapes avec
            vous.
          </p>
          <a className="contact-mail" href={`mailto:${contactEmail}`}>
            <Mail />
            {contactEmail}
            <Arrow />
          </a>
          <div className="contact-next">
            <h3>Et ensuite ?</h3>
            <p>
              <span>01</span> Nous prenons connaissance de votre besoin.
            </p>
            <p>
              <span>02</span> Nous échangeons pour préciser le projet.
            </p>
            <p>
              <span>03</span> Nous définissons une approche adaptée.
            </p>
          </div>
        </div>
        <form className="contact-form" onSubmit={submit}>
          <h2>Parlons de votre projet.</h2>
          <p className="form-intro">
            Préparez votre message, puis envoyez-le avec votre messagerie.
          </p>
          <div className="form-row">
            <label>
              Votre nom <span>*</span>
              <input
                name="name"
                autoComplete="name"
                value={form.name}
                onChange={update}
                required
                maxLength={100}
              />
            </label>
            <label>
              Votre entreprise
              <input
                name="company"
                autoComplete="organization"
                value={form.company}
                onChange={update}
                maxLength={150}
              />
            </label>
          </div>
          <label>
            Votre e-mail <span>*</span>
            <input
              type="email"
              name="email"
              autoComplete="email"
              value={form.email}
              onChange={update}
              required
              maxLength={200}
            />
          </label>
          <label>
            Votre sujet
            <select name="subject" value={form.subject} onChange={update}>
              <option value="">Choisir un sujet</option>
              <optgroup label="Nos expertises">
                {services.map((s) => (
                  <option key={s.id}>{s.name}</option>
                ))}
              </optgroup>
              <optgroup label="Nos solutions">
                {products.map((p) => (
                  <option key={p.id}>{p.name}</option>
                ))}
              </optgroup>
              <option>Autre besoin</option>
            </select>
          </label>
          <label>
            Quelques mots sur votre projet <span>*</span>
            <textarea
              name="message"
              rows={5}
              placeholder="Votre besoin, vos objectifs, votre contexte…"
              value={form.message}
              onChange={update}
              required
              minLength={10}
              maxLength={5000}
            />
          </label>
          <p className="form-privacy">
            Les champs marqués * sont obligatoires. Votre message est envoyé
            uniquement lorsque vous le validez dans votre messagerie.
          </p>
          <button type="submit" className="button">
            Préparer mon message <Arrow />
          </button>
          {prepared && (
            <div className="prepared" role="status">
              <Check />
              <div>
                <h3>Votre message est prêt.</h3>
                <p>
                  Ouvrez votre messagerie pour le relire et l’envoyer à{" "}
                  {contactEmail}.
                </p>
                <a className="button" href={emailHref}>
                  Ouvrir ma messagerie <Mail size={17} />
                </a>
                <button
                  type="button"
                  className="download-link"
                  onClick={download}
                >
                  <Download size={16} />
                  Télécharger mon message
                </button>
              </div>
            </div>
          )}
        </form>
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
          Des échanges
          <br />
          <em>en confiance.</em>
        </h1>
        <h2>Formulaire de contact</h2>
        <p>
          Le formulaire prépare un message dans votre navigateur. Il ouvre
          ensuite votre application de messagerie à votre demande. L’envoi
          intervient lorsque vous le confirmez dans cette application. Vous
          pouvez également télécharger le message préparé.
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
    const segment = pathname.split("/").filter(Boolean).pop();
    const item =
      products.find((p) => p.id === segment) ||
      services.find((s) => s.id === segment) ||
      projects.find((p) => p.id === segment);
    const labels = {
      solutions: "Solutions SaaS",
      expertises: "Nos expertises",
      projets: "Nos projets",
      studio: "Le studio",
      contact: "Contact",
      confidentialite: "Confidentialité",
    };
    document.title = `${item?.name || labels[segment] || "Studio digital & solutions SaaS"} — ProDigital`;
  }, [pathname]);
  return null;
}
function Shell() {
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
    <HashRouter>
      <Shell />
    </HashRouter>
  );
}
createRoot(document.getElementById("root")).render(
  <React.StrictMode>
    <App />
  </React.StrictMode>,
);
