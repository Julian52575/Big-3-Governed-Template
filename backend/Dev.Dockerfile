# Dev image: docker-compose.yml bind-mounts the source and nodemon restarts
# on every save. node_modules stays in the image (a named volume in compose).
FROM docker.io/library/node:24-slim
WORKDIR /app
RUN apt-get update \
 && apt-get install -y --no-install-recommends openssl \
 && rm -rf /var/lib/apt/lists/*
COPY package.json package-lock.json ./
RUN npm ci
COPY prisma.config.ts ./
COPY prisma ./prisma
RUN npx prisma generate
EXPOSE 3000
CMD ["sh", "-c", "npx prisma migrate deploy && exec npm run dev"]
