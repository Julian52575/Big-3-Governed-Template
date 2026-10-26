# Dev image for ./web: docker-compose.yml bind-mounts the folder as the
# document root, so edits show on reload with no rebuild.
# Releases use ./Dockerfile, which copies the files in.
FROM docker.io/library/nginx:alpine
