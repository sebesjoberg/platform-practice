#!/usr/bin/env python3
"""acme-hello, the Ansible track's demo app. Python standard library only.

Release "broken": a deliberately bad build. It starts and listens like the others, but every
request, /health included, answers 500. Deploying it must fail the health check; an-18 builds
the automatic rollback around exactly that.
"""
import os
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

VERSION = "broken"


class Handler(BaseHTTPRequestHandler):
    server_version = "acme-hello/" + VERSION

    def _send(self, status, body):
        data = body.encode()
        self.send_response(status)
        self.send_header("Content-Type", "text/plain; charset=utf-8")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        if self.command != "HEAD":
            self.wfile.write(data)

    def do_GET(self):
        self._send(500, f"error {VERSION}: cannot reach the orders database\n")

    do_HEAD = do_GET


def main():
    port = int(os.environ.get("APP_PORT", "8080"))
    ThreadingHTTPServer(("127.0.0.1", port), Handler).serve_forever()


if __name__ == "__main__":
    main()
