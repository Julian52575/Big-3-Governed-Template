# Release image: `vite build` in a build stage, then only the static dist/
# served by `serve` on :3000 as the unprivileged `node` user.
FROM docker.io/library/node:24-slim AS build
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci
COPY . .
RUN npm run build

FROM docker.io/library/node:24-slim
WORKDIR /app
RUN npm install -g serve@14.2.6 \
 && npm cache clean --force
# NO_UPDATE_CHECK: serve would otherwise phone npm and write a cache file.
ENV NODE_ENV=production \
    NO_UPDATE_CHECK=1
COPY --from=build /app/dist ./dist
USER node
EXPOSE 3000
CMD ["serve", "-s", "dist", "-l", "3000", "--no-clipboard"]
