#!/usr/bin/env python3
"""Tiny LAN file server for the Godot Web build; standard library only."""

from __future__ import annotations

import argparse
import json
import os
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path


class GameRequestHandler(SimpleHTTPRequestHandler):
    server_version = "ChaosStickHTTP/1.0"

    def do_GET(self) -> None:  # noqa: N802 - inherited HTTP API
        if self.path.rstrip("/") == "/status":
            payload = json.dumps(
                {
                    "server": "online",
                    "players": None,
                    "maxPlayers": 4,
                    "state": "available",
                }
            ).encode("utf-8")
            self.send_response(200)
            self.send_header("Content-Type", "application/json; charset=utf-8")
            self.send_header("Content-Length", str(len(payload)))
            self.end_headers()
            self.wfile.write(payload)
            return
        super().do_GET()

    def end_headers(self) -> None:
        # Safe defaults for current and future threaded Godot Web exports.
        self.send_header("Cross-Origin-Opener-Policy", "same-origin")
        self.send_header("Cross-Origin-Embedder-Policy", "require-corp")
        self.send_header("Cross-Origin-Resource-Policy", "same-origin")
        self.send_header("Cache-Control", "no-cache")
        super().end_headers()

    def log_message(self, message: str, *args: object) -> None:
        print("HTTP " + (message % args), flush=True)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Serve the Chaos Stick Arena Web build on the LAN.")
    parser.add_argument("--port", type=int, default=8080)
    parser.add_argument("--directory", type=Path, default=Path("web_build"))
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    directory = args.directory.resolve()
    if not (directory / "index.html").is_file():
        raise SystemExit(f"Web build not found: {directory / 'index.html'}")
    os.chdir(directory)
    server = ThreadingHTTPServer(("0.0.0.0", args.port), GameRequestHandler)
    print(f"CHAOS_HTTP_READY port={args.port} directory={directory}", flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()


if __name__ == "__main__":
    main()

