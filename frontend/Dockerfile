# Site vitrine ProDigital (pro-digital.net) — SPA React/Vite servie par Nginx non-root.
# Contexte de build : la racine du dépôt (shared/ est partagé avec l'API du formulaire).

ARG NODE_VERSION=22
ARG NGINX_VERSION=1.28
ARG VITE_CMS_URL=
ARG VITE_CMS_ORG=

# --- 1. Build -----------------------------------------------------------------
FROM node:${NODE_VERSION}-alpine AS build
WORKDIR /app/frontend

ARG VITE_CMS_URL
ARG VITE_CMS_ORG
ENV VITE_CMS_URL=$VITE_CMS_URL
ENV VITE_CMS_ORG=$VITE_CMS_ORG

# Dépendances d'abord : couche mise en cache tant que le lockfile ne change pas.
COPY frontend/package.json frontend/package-lock.json ./
RUN npm ci --no-audit --no-fund

COPY frontend/index.html frontend/vite.config.js ./
COPY frontend/public ./public
COPY frontend/src ./src
COPY frontend/scripts/prerender.mjs ./scripts/prerender.mjs
# Contenu du site et définition du formulaire : les mêmes fichiers que l'API.
COPY shared /app/shared
RUN npm run build

# --- 2. Runtime ---------------------------------------------------------------
# Image Nginx officielle non-root (uid 101), écoute sur 8080.
FROM nginxinc/nginx-unprivileged:${NGINX_VERSION}-alpine AS runtime

COPY --chown=root:root frontend/nginx/default.conf /etc/nginx/conf.d/default.conf
COPY --chown=root:root frontend/nginx/security-headers.conf /etc/nginx/security-headers.conf
COPY --from=build --chown=root:root /app/frontend/dist /usr/share/nginx/html

EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD wget -q -O /dev/null http://127.0.0.1:8080/healthz || exit 1
