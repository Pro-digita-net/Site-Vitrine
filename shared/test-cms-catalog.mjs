import assert from "node:assert/strict";
import {
  formQuestionsFor,
  loadCatalog,
  mapEntry,
  mapFormEntry,
  parseContent,
} from "./cmsCatalog.js";

assert.deepEqual(parseContent('{"name":"A"}'), { name: "A" });
assert.deepEqual(parseContent({ name: "B" }), { name: "B" });
assert.deepEqual(parseContent("nope"), {});

const service = mapEntry({
  slug: "creation-web",
  content: { name: "Création web", icon: "monitor", tags: ["Sites"], teaser: "T" },
});
assert.equal(service.id, "creation-web");
assert.deepEqual(service.tags, ["Sites"]);
assert.deepEqual(service.deliverables, []);

assert.equal(mapEntry({ slug: "", content: {} }), null);

const form = mapFormEntry({
  slug: "creation-web",
  content: {
    title: "Projet CMS",
    hint: "Depuis Studio",
    fields: [
      { id: "goal", label: "Objectif", type: "text", required: true },
      { name: "bad" },
      { id: "kind", label: "Type", type: "select", options: ["A", "B"] },
    ],
  },
});
assert.equal(form.fields.length, 2);
assert.equal(form.fields[0].required, true);
assert.deepEqual(form.fields[1].options, ["A", "B"]);

const catalog = {
  services: [{ id: "creation-web", name: "Création web" }],
  formations: [],
  products: [],
};
const forms = [form];
assert.equal(formQuestionsFor("Création web", forms, catalog).title, "Projet CMS");
assert.equal(formQuestionsFor("Inconnu", forms, catalog), null);

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
    return {
      ok: true,
      json: async () => ({
        data: [{ slug: "cms-f", content: { name: "Formation CMS", category: "Web", features: ["a"] } }],
      }),
    };
  }
  if (path.endsWith("/services")) return { ok: false, status: 503, json: async () => ({}) };
  if (path.endsWith("/realisations")) return { ok: true, json: async () => ({ data: [] }) };
  if (path.endsWith("/forms")) return { ok: true, json: async () => ({ data: [] }) };
  throw new Error(`unexpected ${path}`);
};

const loaded = await loadCatalog({
  base: "https://core.test",
  org: "prodigital",
  staticCatalog,
});
assert.equal(loaded.source, "cms");
assert.deepEqual(loaded.products, []); // volontairement vide
assert.equal(loaded.formations[0].name, "Formation CMS");
assert.equal(loaded.services[0].name, "Static S"); // échec → repli
assert.deepEqual(loaded.projects, []); // volontairement vide
assert.deepEqual(loaded.forms, []); // volontairement vide (pas null)

const offline = await loadCatalog({ base: "", org: "", staticCatalog });
assert.equal(offline.source, "static");
assert.equal(offline.forms, null);

globalThis.fetch = originalFetch;
console.log("cmsCatalog : vide volontaire, repli sur erreur et forms OK.");
