# Release image for the `backend` service. python:*-slim ships bash, so
# `just sh backend` gives a real shell.
FROM docker.io/library/python:3.12-slim

WORKDIR /app
COPY app.py .

ENV PORT=8000
EXPOSE 8000

CMD ["python", "app.py"]
