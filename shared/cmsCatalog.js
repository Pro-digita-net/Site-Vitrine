/**
 * Lecture publique CMS Core → catalogues du Site Vitrine.
 * Contrat : GET /api/v1/public/cms/{org}/{collection} → { data: [{ id, slug, sort_order, content, published_at }] }
 * Une réponse 200 avec data: [] est une collection volontairement vide (pas de repli statique).
 */

export const CMS_COLLECTIONS = {
  products: "saas",
  formations: "formations",
  services: "services",
  projects: "realisations",
  forms: "forms",
};

export function parseContent(raw) {
  if (raw && typeof raw === "object" && !Array.isArray(raw)) return raw;
  if (typeof raw === "string") {
    try {
      const parsed = JSON.parse(raw);
      if (parsed && typeof parsed === "object" && !Array.isArray(parsed)) return parsed;
    } catch {
      /* ignore */
    }
  }
  return {};
}

export function mediaUrl(base, org, id) {
  if (!base || !org || !id) return "";
  return `${String(base).replace(/\/$/, "")}/api/v1/public/cms/${org}/media/${encodeURIComponent(id)}`;
}

export function mapEntry(entry, { base = "", org = "" } = {}) {
  const content = parseContent(entry?.content);
  const id = content.id || entry?.slug;
  if (!id) return null;
  const item = { ...content, id, slug: entry?.slug || id };
  if (!Array.isArray(item.tags)) item.tags = Array.isArray(content.tags) ? content.tags : [];
  if (!Array.isArray(item.features)) item.features = [];
  if (!Array.isArray(item.deliverables)) item.deliverables = [];
  if (!Array.isArray(item.questions)) item.questions = [];
  if (content.media_id && !item.image) {
    const url = mediaUrl(base, org, content.media_id);
    if (url) item.image = url;
  }
  return item;
}

/** Normalise une entrée `forms` : questions du sujet (slug = id sujet ou name). */
export function mapFormEntry(entry) {
  const content = parseContent(entry?.content);
  const slug = entry?.slug || content.id || content.subject_id || "";
  const fields = Array.isArray(content.fields) ? content.fields.map(normalizeField).filter(Boolean) : [];
  if (!slug && !fields.length && !content.title) return null;
  return {
    id: content.id || slug,
    slug,
    subject: content.subject || content.name || "",
    title: content.title || "",
    hint: content.hint || "",
    fields,
  };
}

function normalizeField(field) {
  if (!field || typeof field !== "object") return null;
  const id = String(field.id || field.name || "").trim();
  const label = String(field.label || "").trim();
  if (!id || !label) return null;
  const type = ["select", "text", "tel"].includes(field.type) ? field.type : (Array.isArray(field.options) ? "select" : "text");
  const out = {
    id,
    label,
    type,
    required: Boolean(field.required),
  };
  if (type === "select") out.options = (Array.isArray(field.options) ? field.options : []).map(String);
  if (field.placeholder) out.placeholder = String(field.placeholder);
  return out;
}

/**
 * @returns {{ ok: true, items: any[] } | { ok: false, items: null, reason: string }}
 */
export async function fetchCollection(base, org, collection, { signal, map = mapEntry } = {}) {
  const url = `${String(base).replace(/\/$/, "")}/api/v1/public/cms/${encodeURIComponent(org)}/${collection}`;
  try {
    const res = await fetch(url, { signal, headers: { Accept: "application/json" } });
    if (!res.ok) return { ok: false, items: null, reason: `http_${res.status}` };
    const body = await res.json();
    const rows = Array.isArray(body?.data) ? body.data : [];
    const items = rows.map((row) => map(row, { base, org })).filter(Boolean);
    return { ok: true, items };
  } catch (error) {
    if (error?.name === "AbortError") throw error;
    return { ok: false, items: null, reason: "network" };
  }
}

/**
 * Assemble le catalogue. Repli statique uniquement si CMS non configuré ou si la collection a échoué.
 * Une collection OK et vide reste [].
 */
export async function loadCatalog({ base, org, staticCatalog, signal } = {}) {
  const fallback = {
    products: staticCatalog.products,
    formations: staticCatalog.formations,
    services: staticCatalog.services,
    projects: staticCatalog.projects,
    forms: null,
    source: "static",
  };
  if (!base || !org) return fallback;

  const [saas, formations, services, realisations, forms] = await Promise.all([
    fetchCollection(base, org, CMS_COLLECTIONS.products, { signal }),
    fetchCollection(base, org, CMS_COLLECTIONS.formations, { signal }),
    fetchCollection(base, org, CMS_COLLECTIONS.services, { signal }),
    fetchCollection(base, org, CMS_COLLECTIONS.projects, { signal }),
    fetchCollection(base, org, CMS_COLLECTIONS.forms, { signal, map: (row) => mapFormEntry(row) }),
  ]);

  const anyOk = [saas, formations, services, realisations, forms].some((r) => r.ok);
  return {
    products: saas.ok ? saas.items : staticCatalog.products,
    formations: formations.ok ? formations.items : staticCatalog.formations,
    services: services.ok ? services.items : staticCatalog.services,
    projects: realisations.ok ? realisations.items : staticCatalog.projects,
    forms: forms.ok ? forms.items : null,
    source: anyOk ? "cms" : "static",
  };
}

/** Questions CMS pour un sujet, ou null si absentes. */
export function formQuestionsFor(subject, forms, catalog) {
  if (!subject || !Array.isArray(forms) || !forms.length) return null;
  const services = catalog?.services || [];
  const formations = catalog?.formations || [];
  const products = catalog?.products || [];
  const item = [...services, ...formations, ...products].find((x) => x.name === subject);
  const hit = forms.find((f) =>
    f.subject === subject
    || f.name === subject
    || f.slug === subject
    || (item && (f.slug === item.id || f.id === item.id || f.slug === item.slug)),
  );
  if (!hit || !hit.fields?.length) return null;
  return { title: hit.title || "", hint: hit.hint || "", fields: hit.fields };
}
