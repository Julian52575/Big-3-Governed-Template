# Static front-end. nginx:alpine has a shell (busybox sh), so `just sh web`
# works. Swap this for your framework's build once you have one.
FROM docker.io/library/nginx:alpine

COPY index.html /usr/share/nginx/html/index.html
