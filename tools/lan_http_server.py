#!/usr/bin/env python3
"""Serve the Web build and proxy multiplayer through one public LAN port."""

from __future__ import annotations

import argparse
import json
import os
import select
import socket
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import urlsplit


MAX_HANDSHAKE_BYTES = 64 * 1024
TUNNEL_BUFFER_BYTES = 64 * 1024


class GameHTTPServer(ThreadingHTTPServer):
    """HTTP server carrying static files and the transparent WebSocket tunnel."""

    daemon_threads = True

    def __init__(
        self,
        server_address: tuple[str, int],
        handler_class: type[SimpleHTTPRequestHandler],
        websocket_upstream: tuple[str, int],
    ) -> None:
        super().__init__(server_address, handler_class)
        self.websocket_upstream = websocket_upstream


class GameRequestHandler(SimpleHTTPRequestHandler):
    server_version = "ChaosStickHTTP/2.0"

    def do_GET(self) -> None:  # noqa: N802 - inherited HTTP API
        request_path = urlsplit(self.path).path
        if request_path == "/ws":
            if not self._is_websocket_upgrade():
                self.send_error(426, "WebSocket upgrade required")
                return
            self._proxy_websocket()
            return
        if request_path.rstrip("/") == "/status":
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

    def _is_websocket_upgrade(self) -> bool:
        upgrade = self.headers.get("Upgrade", "")
        connection_tokens = {
            token.strip().lower()
            for token in self.headers.get("Connection", "").split(",")
        }
        return upgrade.lower() == "websocket" and "upgrade" in connection_tokens

    def _proxy_websocket(self) -> None:
        server = self.server
        if not isinstance(server, GameHTTPServer):
            self.send_error(500, "WebSocket proxy is not configured")
            return

        upstream_host, upstream_port = server.websocket_upstream
        try:
            upstream = socket.create_connection((upstream_host, upstream_port), timeout=3.0)
        except OSError as error:
            print(
                f"WS UPSTREAM_UNAVAILABLE client={self.client_address[0]} "
                f"upstream={upstream_host}:{upstream_port} error={error}",
                flush=True,
            )
            self.send_error(502, "Internal Godot WebSocket server is unavailable")
            return

        self.close_connection = True
        try:
            upstream.settimeout(None)
            upstream.sendall(self._serialize_request())
            response = self._read_upstream_handshake(upstream)
            self.connection.sendall(response)
            if not self._is_switching_protocols(response):
                print(
                    f"WS HANDSHAKE_REJECTED client={self.client_address[0]} "
                    f"upstream={upstream_host}:{upstream_port}",
                    flush=True,
                )
                return

            print(
                f"WS OPEN client={self.client_address[0]} "
                f"upstream={upstream_host}:{upstream_port}",
                flush=True,
            )
            self._tunnel(self.connection, upstream)
            print(f"WS CLOSED client={self.client_address[0]}", flush=True)
        except ConnectionResetError:
            print(f"WS CLOSED client={self.client_address[0]}", flush=True)
        except (ConnectionError, OSError) as error:
            print(f"WS CLOSED client={self.client_address[0]} error={error}", flush=True)
        finally:
            try:
                upstream.shutdown(socket.SHUT_RDWR)
            except OSError:
                pass
            upstream.close()

    def _serialize_request(self) -> bytes:
        request = bytearray(
            f"{self.command} {self.path} {self.request_version}\r\n".encode("iso-8859-1")
        )
        for name, value in self.headers.raw_items():
            request.extend(f"{name}: {value}\r\n".encode("iso-8859-1"))
        request.extend(b"\r\n")
        return bytes(request)

    @staticmethod
    def _read_upstream_handshake(upstream: socket.socket) -> bytes:
        response = bytearray()
        while b"\r\n\r\n" not in response:
            chunk = upstream.recv(4096)
            if not chunk:
                raise ConnectionError("upstream closed during WebSocket handshake")
            response.extend(chunk)
            if len(response) > MAX_HANDSHAKE_BYTES:
                raise ConnectionError("upstream WebSocket handshake is too large")
        return bytes(response)

    @staticmethod
    def _is_switching_protocols(response: bytes) -> bool:
        status_line = response.split(b"\r\n", 1)[0].split()
        return len(status_line) >= 2 and status_line[1] == b"101"

    @staticmethod
    def _tunnel(client: socket.socket, upstream: socket.socket) -> None:
        peers = (client, upstream)
        while True:
            readable, _, exceptional = select.select(peers, [], peers)
            if exceptional:
                return
            for source in readable:
                data = source.recv(TUNNEL_BUFFER_BYTES)
                if not data:
                    return
                destination = upstream if source is client else client
                destination.sendall(data)

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
    parser.add_argument("--websocket-upstream-host", default="127.0.0.1")
    parser.add_argument("--websocket-upstream-port", type=int, default=9000)
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    directory = args.directory.resolve()
    if not (directory / "index.html").is_file():
        raise SystemExit(f"Web build not found: {directory / 'index.html'}")
    os.chdir(directory)
    upstream = (args.websocket_upstream_host, args.websocket_upstream_port)
    server = GameHTTPServer(("0.0.0.0", args.port), GameRequestHandler, upstream)
    print(
        f"CHAOS_HTTP_READY public=0.0.0.0:{args.port} "
        f"websocket=/ws upstream={upstream[0]}:{upstream[1]} directory={directory}",
        flush=True,
    )
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()


if __name__ == "__main__":
    main()

