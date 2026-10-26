# Dev image: docker-compose.yml bind-mounts the source and the Vite dev
# server hot-reloads on save. node_modules stays in the image (a named
# volume in compose).
FROM docker.io/library/node:24-slim
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci
EXPOSE 3000
CMD ["npx", "vite"]
