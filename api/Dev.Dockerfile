# Dev image for ./api: the source is bind-mounted by docker-compose.yml and
# watchfiles restarts the server on every save -- no rebuild while coding.
# Releases use ./Dockerfile (see release-to-ghcr.yml).
FROM docker.io/library/python:3.12-slim

RUN pip install --no-cache-dir watchfiles==1.3.0

WORKDIR /app
ENV PORT=8000 PYTHONUNBUFFERED=1
EXPOSE 8000

CMD ["watchfiles", "--filter", "python", "python app.py", "/app"]
