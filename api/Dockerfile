# Minimal API image. python:*-slim is Debian-based and ships bash, so
# `just sh api` gives you a real shell (unlike the scratch-based whoami).
FROM docker.io/library/python:3.12-slim

WORKDIR /app
COPY app.py .

ENV PORT=8000
EXPOSE 8000

CMD ["python", "app.py"]
