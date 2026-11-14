# Site vitrine ProDigital (pro-digital.net) — SPA React/Vite servie par Nginx non-root.

ARG NODE_VERSION=22
ARG NGINX_VERSION=1.28

# --- 1. Build -----------------------------------------------------------------
FROM node:${NODE_VERSION}-alpine AS build
WORKDIR /app

# Dépendances d'abord : couche mise en cache tant que le lockfile ne change pas.
COPY package.json package-lock.json ./
RUN npm ci --no-audit --no-fund

COPY index.html vite.config.js ./
COPY public ./public
COPY src ./src
COPY scripts/prerender.mjs ./scripts/prerender.mjs
RUN npm run build

# --- 2. Runtime ---------------------------------------------------------------
# Image Nginx officielle non-root (uid 101), écoute sur 8080.
FROM nginxinc/nginx-unprivileged:${NGINX_VERSION}-alpine AS runtime

COPY --chown=root:root nginx/default.conf /etc/nginx/conf.d/default.conf
COPY --chown=root:root nginx/security-headers.conf /etc/nginx/security-headers.conf
COPY --from=build --chown=root:root /app/dist /usr/share/nginx/html

EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD wget -q -O /dev/null http://127.0.0.1:8080/healthz || exit 1
