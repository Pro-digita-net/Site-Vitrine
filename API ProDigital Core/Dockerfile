# Une image, trois processus : core-api, core-iam, core-worker (commande choisie dans docker-compose.yml).
FROM node:24-alpine AS build
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci
COPY tsconfig.json tsconfig.build.json ./
COPY src ./src
RUN npm run build

FROM node:24-alpine
ENV NODE_ENV=production PORT=8080
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci --omit=dev && npm cache clean --force
COPY --from=build /app/dist ./dist
COPY db ./db
# Compte non privilégié, système de fichiers applicatif en lecture seule.
USER node
EXPOSE 8080
HEALTHCHECK --interval=30s --timeout=5s --start-period=15s --retries=3 \
  CMD node -e "fetch('http://127.0.0.1:'+process.env.PORT+'/readyz').then(r=>process.exit(r.ok?0:1),()=>process.exit(1))"
CMD ["node", "dist/core/server.js"]
