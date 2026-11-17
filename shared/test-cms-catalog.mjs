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
};

const originalFetch = globalThis.fetch;
globalThis.fetch = async (url) => {
  const path = String(url);
  if (path.endsWith("/saas")) return { ok: true, json: async () => ({ data: [] }) };
  if (path.endsWith("/formations")) {
    return { ok: true, json: async () => ({ data: [{ slug: "cms-f", content: { name: "Formation CMS", category: "Web" } }] }) };
  }
  if (path.endsWith("/forms")) return { ok: true, json: async () => ({ data: [] }) };
  if (path.includes("/services") || path.includes("/realisations")) throw new Error(`ne doit pas appeler ${path}`);
  throw new Error(`unexpected ${path}`);
};

const loaded = await loadCatalog({ base: "https://core.test", org: "prodigital", staticCatalog });
assert.equal(loaded.source, "cms");
assert.deepEqual(loaded.products, []);
assert.equal(loaded.formations[0].name, "Formation CMS");
assert.equal(loaded.services[0].name, "Static S");
assert.equal(loaded.forms, null);
assert.equal(loaded.projects, undefined);

const offline = await loadCatalog({ base: "", org: "", staticCatalog });
assert.equal(offline.source, "static");
assert.equal(offline.forms, null);

globalThis.fetch = originalFetch;
console.log("cmsCatalog : SaaS/formations/forms dynamiques ; Projets retirés.");
