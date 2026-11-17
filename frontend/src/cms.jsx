import React, { createContext, useContext, useEffect, useState } from "react";
import {
  products as staticProducts,
  formations as staticFormations,
  services as staticServices,
  projects as staticProjects,
} from "../../shared/data.js";
import { loadCatalog, mediaUrl } from "../../shared/cmsCatalog.js";

const STATIC = {
  products: staticProducts,
  formations: staticFormations,
  services: staticServices,
  projects: staticProjects,
  forms: null,
  source: "static",
};

const CMS_BASE = String(import.meta.env.VITE_CMS_URL ?? "").replace(/\/$/, "");
const CMS_ORG = String(import.meta.env.VITE_CMS_ORG ?? "").trim();

export function cmsMediaUrl(id) {
  return mediaUrl(CMS_BASE, CMS_ORG, id);
}

export async function loadPublishedCatalog(signal) {
  return loadCatalog({
    base: CMS_BASE,
    org: CMS_ORG,
    staticCatalog: STATIC,
    signal,
  });
}

const CatalogContext = createContext(STATIC);

export function ContentProvider({ children }) {
  const [catalog, setCatalog] = useState(STATIC);
  useEffect(() => {
    if (!CMS_BASE || !CMS_ORG) return undefined;
    const ac = new AbortController();
    loadPublishedCatalog(ac.signal)
      .then((next) => { if (!ac.signal.aborted) setCatalog(next); })
      .catch(() => { /* conserve le catalogue statique */ });
    return () => ac.abort();
  }, []);
  return <CatalogContext.Provider value={catalog}>{children}</CatalogContext.Provider>;
}

export function useCatalog() {
  return useContext(CatalogContext);
}
