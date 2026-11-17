import assert from "node:assert/strict";
import {
  formQuestionsFor,
  loadCatalog,
  mapEntry,
  mapFormEntry,
  parseContent,
} from "./cmsCatalog.js";

assert.deepEqual(parseContent({ name: "B" }), { name: "B" });
assert.equal(mapEntry({ slug: "x", content: { name: "X" } }).id, "x");

const form = mapFormEntry({
  slug: "creation-web",
  content: {
    title: "Projet CMS",
    fields: [
      { id: "goal", label: "Objectif", type: "text", required: true },
      { id: "kind", label: "Type", type: "select", options: ["A", "B"] },
    ],
  },
});
assert.equal(formQuestionsFor("Création web", [form], {
  services: [{ id: "creation-web", name: "Création web" }],
  formations: [],
  products: [],
}).title, "Projet CMS");

const staticCatalog = {
  products: [{ id: "static-p", name: "Static P" }],
  formations: [{ id: "static-f", name: "Static F" }],
  services: [{ id: "static-s", name: "Static S" }],
  projects: [{ id: "static-r", name: "Static R" }],
};

const originalFetch = globalThis.fetch;
globalThis.fetch = async (url) => {
  const path = String(url);
  if (path.endsWith("/saas")) return { ok: true, json: async () => ({ data: [] }) };
  if (path.endsWith("/formations")) {
    return { ok: true, json: async () => ({ data: [{ slug: "cms-f", content: { name: "Formation CMS", category: "Web" } }] }) };
  }
  if (path.endsWith("/realisations")) {
    return { ok: true, json: async () => ({ data: [{ slug: "cms-p", content: { name: "Projet CMS", description: "D", image: "/x.webp" } }] }) };
  }
  if (path.endsWith("/forms")) return { ok: true, json: async () => ({ data: [] }) };
  if (path.includes("/services")) throw new Error(`ne doit pas appeler ${path}`);
  throw new Error(`unexpected ${path}`);
};

const loaded = await loadCatalog({ base: "https://core.test", org: "prodigital", staticCatalog });
assert.equal(loaded.source, "cms");
// Collection publiée mais vide → contenu statique conservé (aucune card ne disparaît).
assert.equal(loaded.products[0].name, "Static P");
assert.equal(loaded.formations[0].name, "Formation CMS");
assert.equal(loaded.projects[0].name, "Projet CMS");
assert.equal(loaded.services[0].name, "Static S");
assert.equal(loaded.forms, null);

const offline = await loadCatalog({ base: "", org: "", staticCatalog });
assert.equal(offline.source, "static");
assert.equal(offline.forms, null);

globalThis.fetch = originalFetch;
console.log("cmsCatalog : SaaS/formations/projets/forms dynamiques ; expertises statiques.");
