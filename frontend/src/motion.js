import gsap from "gsap";
import { ScrollTrigger } from "gsap/ScrollTrigger";
import { SplitText } from "gsap/SplitText";
import { useGSAP } from "@gsap/react";

gsap.registerPlugin(useGSAP, ScrollTrigger, SplitText);
// Les sélecteurs couvrent toutes les pages : une cible absente est normale.
gsap.config({ nullTargetWarn: false });

const MOTION_OK = "(prefers-reduced-motion: no-preference)";
const FINE_POINTER = "(hover: hover) and (pointer: fine)";

// Blocs « au-dessus de la ligne de flottaison » : animés au chargement de la page.
const INTRO_BLOCKS = [
  ".hero-copy",
  ".page-heading",
  ".product-detail-hero > div:first-child",
  ".service-hero > div:first-child",
  ".studio-hero > div:first-child",
  ".contact-copy",
  ".legal-page",
  ".not-found",
].join(",");

// Titres de section révélés ligne par ligne au scroll.
const SCROLL_HEADINGS = [
  ".section-heading h2",
  ".contact-inner h2",
  ".detail-grid h2",
  ".expertise-panel-copy h2",
  ".studio-values h2",
].join(",");

// Groupes révélés au scroll ; chaque entrée forme sa propre cascade.
const SCROLL_GROUPS = [
  ".offer-strip > *",
  // Le titre « vision » garde son retour à la ligne conditionnel : fondu simple, sans découpe.
  ".vision > .eyebrow, .vision > div > *",
  ".section-heading .eyebrow, .section-heading > p, .section-heading > .quiet-link, .section-intro",
  ".services-grid > *",
  ".expertise-panel",
  ".situations-grid > *",
  ".projects-grid > *",
  ".home-solutions .products-grid > *",
  ".home-formations .products-grid > *",
  ".catalog-footer",
  ".catalog-controls, .filter-list",
  ".catalog-help",
  ".detail-grid > div:first-child > .eyebrow, .detail-grid > div:first-child > p",
  ".feature-list > div",
  ".product-disclaimer",
  ".related-grid > *",
  ".questions > *",
  ".project-list-item",
  ".case-image",
  ".studio-values > .eyebrow, .studio-values > p",
  ".contact-band .eyebrow, .contact-side > *",
  ".footer-top > *, .footer-bottom",
];

let headerShown = false;

function splitLines(el, vars) {
  SplitText.create(el, {
    type: "lines",
    mask: "lines",
    autoSplit: true,
    linesClass: "split-line",
    onSplit: (self) =>
      gsap.from(self.lines, {
        yPercent: 110,
        duration: 1.05,
        ease: "expo.out",
        stagger: 0.09,
        ...vars,
      }),
  });
}

function intro() {
  if (!headerShown) {
    gsap.from(".header", {
      autoAlpha: 0,
      y: -14,
      duration: 0.7,
      ease: "power3.out",
      clearProps: "all",
    });
    // Posé en différé : le double montage de StrictMode annule cet appel.
    gsap.delayedCall(0.2, () => (headerShown = true));
  }

  gsap.from(".breadcrumb", { autoAlpha: 0, duration: 0.6, ease: "power2.out" });

  gsap.utils.toArray(INTRO_BLOCKS).forEach((block) => {
    const title = block.querySelector(":scope > h1");
    const rest = [...block.children].filter((child) => child !== title);
    if (title) splitLines(title, { delay: 0.12 });
    gsap.from(rest, {
      autoAlpha: 0,
      y: 22,
      duration: 0.9,
      ease: "power3.out",
      stagger: (i) => (i === 0 ? 0.05 : 0.3 + Math.min(i, 8) * 0.08),
    });
  });

  // Visuels d’en-tête
  gsap.fromTo(
    ".hero-frame",
    { clipPath: "inset(100% -60px -60px -60px)" },
    {
      clipPath: "inset(0% -60px -60px -60px)",
      duration: 1.4,
      ease: "expo.out",
      delay: 0.15,
      clearProps: "clipPath",
    },
  );
  gsap.from(".art-note", {
    autoAlpha: 0,
    yPercent: 40,
    duration: 0.8,
    ease: "power3.out",
    delay: 0.95,
  });
  gsap.from(".art-caption", { autoAlpha: 0, duration: 0.8, delay: 1.1 });
  gsap.from(".hero-mobile-foot", {
    autoAlpha: 0,
    y: 18,
    duration: 0.9,
    ease: "power3.out",
    delay: 0.55,
  });
  gsap.fromTo(
    ".service-photo img, .studio-hero > img",
    { clipPath: "inset(100% 0% 0% 0%)" },
    {
      clipPath: "inset(0% 0% 0% 0%)",
      duration: 1.4,
      ease: "expo.out",
      delay: 0.15,
      clearProps: "clipPath",
    },
  );
  gsap.from(".service-photo > span", {
    autoAlpha: 0,
    y: 14,
    duration: 0.7,
    ease: "power3.out",
    delay: 0.85,
  });
  gsap.from(".detail-preview, .contact-form", {
    autoAlpha: 0,
    y: 34,
    duration: 1,
    ease: "power3.out",
    delay: 0.25,
  });
  // Catalogue : la grille change avec les filtres, on l’anime donc au chargement
  // plutôt qu’au scroll (aucune carte ne peut rester masquée).
  gsap.from(".catalog-content .products-grid > *", {
    autoAlpha: 0,
    y: 28,
    duration: 0.9,
    ease: "power3.out",
    stagger: 0.07,
    delay: 0.45,
  });
}

function heroDepth() {
  const hero = document.querySelector(".hero");
  const image = hero?.querySelector(".hero-frame > img");
  if (!image) return;

  // Zoom d’entrée, puis parallaxe au scroll une fois l’image posée.
  let parallax;
  const cleanups = [() => parallax?.scrollTrigger?.kill(), () => parallax?.kill()];
  const cleanup = () => cleanups.forEach((fn) => fn());
  gsap.from(image, {
    scale: 1.14,
    duration: 1.8,
    ease: "power3.out",
    delay: 0.15,
    onComplete: () =>
      (parallax = gsap.to(image, {
        yPercent: 7,
        scale: 1.1,
        transformOrigin: "50% 100%",
        ease: "none",
        scrollTrigger: {
          trigger: hero,
          start: "top top",
          end: "bottom top",
          scrub: 0.6,
        },
      })),
  });

  // Légère profondeur au pointeur sur la carte flottante.
  const note = hero.querySelector(".art-note");
  if (!note || !window.matchMedia(FINE_POINTER).matches) return cleanup;
  const xTo = gsap.quickTo(note, "x", { duration: 0.9, ease: "power3.out" });
  const yTo = gsap.quickTo(note, "y", { duration: 0.9, ease: "power3.out" });
  const onMove = (e) => {
    const r = hero.getBoundingClientRect();
    xTo(((e.clientX - r.left) / r.width - 0.5) * 16);
    yTo(((e.clientY - r.top) / r.height - 0.5) * 12);
  };
  const onLeave = () => {
    xTo(0);
    yTo(0);
  };
  hero.addEventListener("pointermove", onMove);
  hero.addEventListener("pointerleave", onLeave);
  cleanups.push(() => {
    hero.removeEventListener("pointermove", onMove);
    hero.removeEventListener("pointerleave", onLeave);
  });
  return cleanup;
}

function scrollReveals() {
  const startedAt = performance.now();
  // Laisse l’intro respirer pour ce qui est déjà visible au chargement.
  const settle = () => Math.max(0, 0.65 - (performance.now() - startedAt) / 1000);

  gsap.utils.toArray(SCROLL_HEADINGS).forEach((el) =>
    splitLines(el, {
      stagger: 0.1,
      scrollTrigger: { trigger: el, start: "top 88%", once: true },
    }),
  );

  SCROLL_GROUPS.forEach((selector) => {
    const targets = gsap.utils.toArray(selector);
    if (!targets.length) return;
    gsap.set(targets, { autoAlpha: 0, y: 28 });
    ScrollTrigger.batch(targets, {
      // Le pied de page touche le bas du document : il doit se déclencher dès son entrée.
      start: selector.includes(".footer") ? "top bottom" : "top 90%",
      once: true,
      onEnter: (batch) =>
        gsap.to(batch, {
          autoAlpha: 1,
          y: 0,
          duration: 0.9,
          ease: "power3.out",
          stagger: 0.08,
          delay: settle(),
          overwrite: true,
        }),
    });
  });

  // Fond du bandeau de contact : dérive lente au scroll (bureau uniquement, cf. CSS).
  const band = document.querySelector(".contact-band");
  if (band) {
    band.classList.add("is-parallax");
    gsap.fromTo(
      band,
      { "--band-y": "-6%" },
      {
        "--band-y": "6%",
        ease: "none",
        scrollTrigger: {
          trigger: band,
          start: "top bottom",
          end: "bottom top",
          scrub: true,
        },
      },
    );
    return () => band.classList.remove("is-parallax");
  }
}

function magneticButtons() {
  if (!window.matchMedia(FINE_POINTER).matches) return;
  const cleanups = gsap.utils
    .toArray(".button")
    .map((el) => {
      const xTo = gsap.quickTo(el, "x", { duration: 0.5, ease: "power3.out" });
      const yTo = gsap.quickTo(el, "y", { duration: 0.5, ease: "power3.out" });
      const onMove = (e) => {
        const r = el.getBoundingClientRect();
        xTo((e.clientX - (r.left + r.width / 2)) * 0.14);
        yTo((e.clientY - (r.top + r.height / 2)) * 0.28);
      };
      const onLeave = () => {
        xTo(0);
        yTo(0);
      };
      el.addEventListener("pointermove", onMove);
      el.addEventListener("pointerleave", onLeave);
      return () => {
        el.removeEventListener("pointermove", onMove);
        el.removeEventListener("pointerleave", onLeave);
      };
    });
  return () => cleanups.forEach((fn) => fn());
}

function methodProgress() {
  gsap.utils.toArray(".method-grid").forEach((grid) => {
    const steps = grid.querySelectorAll(".method-step");
    const nodes = grid.querySelectorAll(".method-node");
    gsap.set(grid, { "--method-progress": 0 });
    gsap.set(nodes, { "--reached": 0 });
    const timeline = gsap.timeline({
      scrollTrigger: { trigger: grid, start: "top 82%", once: true },
    });
    timeline.from(steps, { opacity: 0, y: 16, duration: 0.65, stagger: 0.12, ease: "power2.out" }, 0);
    nodes.forEach((node, index) => {
      const arrival = 0.35 + index * 0.95;
      if (index > 0) {
        timeline.to(grid, {
          "--method-progress": index / 3,
          duration: 0.85,
          ease: "power2.inOut",
        }, arrival - 0.85);
      }
      timeline.to(node, { "--reached": 1, duration: 0.4, ease: "back.out(2)" }, arrival);
      timeline.fromTo(node, { "--bloom": 0 }, {
        "--bloom": 1, duration: 0.85, ease: "power2.out",
      }, arrival);
      timeline.fromTo(steps[index].querySelector(".step-index"),
        { opacity: 0.45, y: 5 },
        { opacity: 1, y: 0, duration: 0.5, ease: "power3.out" }, arrival);
    });
  });
}

/**
 * Orchestration des animations d’une page. À appeler une fois, sous le routeur :
 * tout est recréé à chaque changement de route et nettoyé automatiquement.
 * Sans mouvement si l’utilisateur a demandé à le réduire.
 */
export function usePageMotion(pathname) {
  useGSAP(
    () => {
      // Avant de créer les déclencheurs : ils mesurent la page depuis le haut.
      window.scrollTo({ top: 0, behavior: "instant" });

      // État de l’en-tête au scroll (simple état visuel, indépendant du mouvement).
      const header = document.querySelector(".header");
      header?.classList.remove("is-scrolled");
      ScrollTrigger.create({
        start: 12,
        end: "max",
        onToggle: (self) => header?.classList.toggle("is-scrolled", self.isActive),
      });

      const mm = gsap.matchMedia();
      mm.add(MOTION_OK, () => {
        intro();
        methodProgress();
        const cleanups = [heroDepth(), scrollReveals(), magneticButtons()];

        // La hauteur de page évolue (images, filtres, formulaire) : on recale les déclencheurs.
        const main = document.getElementById("main");
        const refresh = gsap.delayedCall(0.2, () => ScrollTrigger.refresh()).pause();
        const observer = new ResizeObserver(() => refresh.restart(true));
        if (main) observer.observe(main);

        return () => {
          observer.disconnect();
          cleanups.forEach((fn) => fn?.());
        };
      });
    },
    { dependencies: [pathname], revertOnUpdate: true },
  );
}
