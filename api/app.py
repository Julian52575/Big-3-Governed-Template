"""Minimal JSON API for the template. Standard library only -- no deps."""

import json
import os
import socket
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

PORT = int(os.environ.get("PORT", "8000"))


class Handler(BaseHTTPRequestHandler):
    def _json(self, code, payload):
        body = json.dumps(payload, indent=2).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        if self.path.rstrip("/") in ("/health", "/healthz"):
            return self._json(200, {"status": "ok"})
        self._json(200, {
            "service": "api",
            "hostname": socket.gethostname(),
            "method": self.command,
            "path": self.path,
        })

    def log_message(self, fmt, *args):  # to stdout so `just logs` shows it
        print("api %s - %s" % (self.address_string(), fmt % args), flush=True)


if __name__ == "__main__":
    print(f"api listening on :{PORT}", flush=True)
    ThreadingHTTPServer(("", PORT), Handler).serve_forever()
