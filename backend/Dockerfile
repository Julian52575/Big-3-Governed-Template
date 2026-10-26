# Release image: npm ci and `prisma generate` in a build stage, then only
# runtime files, run as the unprivileged `node` user. Migrations are applied
# on start so the schema matches before the first request.
FROM docker.io/library/node:24-slim AS build
WORKDIR /app
RUN apt-get update \
 && apt-get install -y --no-install-recommends openssl \
 && rm -rf /var/lib/apt/lists/*
COPY package.json package-lock.json ./
RUN npm ci
COPY prisma.config.ts ./
COPY prisma ./prisma
RUN npx prisma generate \
 && npm prune --omit=dev

FROM docker.io/library/node:24-slim
WORKDIR /app
# Prisma's query engine links against OpenSSL.
RUN apt-get update \
 && apt-get install -y --no-install-recommends openssl \
 && rm -rf /var/lib/apt/lists/*
ENV NODE_ENV=production
COPY --from=build /app/node_modules ./node_modules
COPY package.json prisma.config.ts ./
COPY prisma ./prisma
COPY src ./src
USER node
EXPOSE 3000
CMD ["sh", "-c", "node_modules/.bin/prisma migrate deploy && exec node src/server.js"]
