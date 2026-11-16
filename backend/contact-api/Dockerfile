# API du formulaire de contact ProDigital (Node, non-root, port 8788).
# Contexte de build : la racine du dépôt (shared/ est partagé avec le site).

ARG NODE_VERSION=22
FROM node:${NODE_VERSION}-alpine

ENV NODE_ENV=production
WORKDIR /app/backend/contact-api

# Dépendances d'abord : couche mise en cache tant que le lockfile ne change pas.
COPY backend/contact-api/package.json backend/contact-api/package-lock.json ./
RUN npm ci --omit=dev --no-audit --no-fund

COPY backend/contact-api/src ./src
COPY backend/contact-api/migrations ./migrations
COPY backend/contact-api/assets ./assets
# Sujets et champs complémentaires : la même définition que le formulaire du site.
COPY shared/package.json shared/contactQuestions.js shared/data.js /app/shared/

USER node
EXPOSE 8788

HEALTHCHECK --interval=30s --timeout=5s --start-period=15s --retries=3 \
  CMD wget -q -O /dev/null http://127.0.0.1:8788/api/health || exit 1

CMD ["node", "src/index.js"]
