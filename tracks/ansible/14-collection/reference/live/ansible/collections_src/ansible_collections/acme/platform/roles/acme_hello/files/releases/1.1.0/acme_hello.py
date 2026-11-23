#!/usr/bin/env python3
"""acme-hello, the Ansible track's demo app. Python standard library only.

Release 1.1.0: every response carries an X-Acme-Version header. Otherwise as 1.0.0.
Configuration comes from the environment (the systemd unit sets it):
  APP_PORT      port on 127.0.0.1 (default 8080); nginx proxies to it
  APP_ENV       environment shown on the page (dev, prod)
  APP_GREETING  a secret from Key Vault (/etc/acme/app.env); never shown, only whether it is set
Endpoints:
  /health  200 "ok <version>"
  /        200 "acme-hello <version> on <hostname> (<env>), app.env loaded|missing"
"""
import os
import socket
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

VERSION = "1.1.0"
HOSTNAME = socket.gethostname()


class Handler(BaseHTTPRequestHandler):
    server_version = "acme-hello/" + VERSION

    def _send(self, status, body):
        data = body.encode()
        self.send_response(status)
        self.send_header("Content-Type", "text/plain; charset=utf-8")
        self.send_header("Content-Length", str(len(data)))
        self.send_header("X-Acme-Version", VERSION)
        self.end_headers()
        if self.command != "HEAD":
            self.wfile.write(data)

    def do_GET(self):
        if self.path == "/health":
            self._send(200, f"ok {VERSION}\n")
        elif self.path == "/":
            env = os.environ.get("APP_ENV", "unknown")
            config = "loaded" if os.environ.get("APP_GREETING") else "missing"
            self._send(200, f"acme-hello {VERSION} on {HOSTNAME} ({env}), app.env {config}\n")
        else:
            self._send(404, "not found\n")

    do_HEAD = do_GET


def main():
    port = int(os.environ.get("APP_PORT", "8080"))
    ThreadingHTTPServer(("127.0.0.1", port), Handler).serve_forever()


if __name__ == "__main__":
    main()
