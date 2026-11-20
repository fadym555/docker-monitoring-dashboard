"""Tiny demo API (standard library only) that gives the dashboard real CPU and network activity."""
import hashlib
import json
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == "/healthz":
            body = {"status": "ok"}
        elif self.path.startswith("/work"):
            digest = b"seed"
            for _ in range(20_000):
                digest = hashlib.sha256(digest).digest()
            body = {"hash": digest.hex()}
        else:
            body = {"service": "demo-api", "time": time.time()}

        payload = json.dumps(body).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(payload)))
        self.end_headers()
        self.wfile.write(payload)

    def log_message(self, *args):
        pass


if __name__ == "__main__":
    ThreadingHTTPServer(("0.0.0.0", 8000), Handler).serve_forever()
