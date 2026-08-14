#!/usr/bin/env python3
"""Integration tests for the dependency-free LAN HTTP/WebSocket gateway."""

from __future__ import annotations

import base64
import hashlib
import socket
import socketserver
import tempfile
import threading
import unittest
import urllib.error
import urllib.request
from functools import partial
from pathlib import Path

from lan_http_server import GameHTTPServer, GameRequestHandler


WEBSOCKET_GUID = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"


def receive_until(sock: socket.socket, marker: bytes) -> bytes:
    payload = bytearray()
    while marker not in payload:
        chunk = sock.recv(4096)
        if not chunk:
            raise ConnectionError(f"connection closed before {marker!r}")
        payload.extend(chunk)
    return bytes(payload)


def receive_exactly(sock: socket.socket, size: int) -> bytes:
    payload = bytearray()
    while len(payload) < size:
        chunk = sock.recv(size - len(payload))
        if not chunk:
            raise ConnectionError("connection closed before the expected payload")
        payload.extend(chunk)
    return bytes(payload)


class EchoWebSocketHandler(socketserver.BaseRequestHandler):
    def handle(self) -> None:
        handshake = receive_until(self.request, b"\r\n\r\n")
        self.server.last_handshake = handshake  # type: ignore[attr-defined]
        headers: dict[str, str] = {}
        for line in handshake.decode("iso-8859-1").split("\r\n")[1:]:
            if ":" in line:
                name, value = line.split(":", 1)
                headers[name.lower()] = value.strip()
        accept = base64.b64encode(
            hashlib.sha1((headers["sec-websocket-key"] + WEBSOCKET_GUID).encode()).digest()
        ).decode()
        self.request.sendall(
            (
                "HTTP/1.1 101 Switching Protocols\r\n"
                "Upgrade: websocket\r\n"
                "Connection: Upgrade\r\n"
                f"Sec-WebSocket-Accept: {accept}\r\n"
                "\r\n"
            ).encode("ascii")
        )
        while True:
            data = self.request.recv(65536)
            if not data:
                return
            self.request.sendall(data)


class ThreadingTCPServer(socketserver.ThreadingTCPServer):
    allow_reuse_address = True
    daemon_threads = True


class LanHTTPServerTests(unittest.TestCase):
    def setUp(self) -> None:
        self.web_directory = tempfile.TemporaryDirectory()
        root = Path(self.web_directory.name)
        (root / "index.html").write_text("<h1>Chaos Stick Arena</h1>", encoding="utf-8")
        (root / "index.js").write_text("console.log('ok');", encoding="utf-8")
        (root / "index.wasm").write_bytes(b"\x00asm")
        (root / "index.pck").write_bytes(b"PCK")

        self.upstream = ThreadingTCPServer(("127.0.0.1", 0), EchoWebSocketHandler)
        self.upstream.last_handshake = b""
        self.upstream_thread = threading.Thread(
            target=self.upstream.serve_forever, daemon=True
        )
        self.upstream_thread.start()

        handler = partial(GameRequestHandler, directory=self.web_directory.name)
        self.gateway = GameHTTPServer(
            ("127.0.0.1", 0), handler, self.upstream.server_address
        )
        self.gateway_thread = threading.Thread(
            target=self.gateway.serve_forever, daemon=True
        )
        self.gateway_thread.start()
        self.gateway_port = self.gateway.server_address[1]

    def tearDown(self) -> None:
        self.gateway.shutdown()
        self.gateway.server_close()
        self.upstream.shutdown()
        self.upstream.server_close()
        self.gateway_thread.join(timeout=2)
        self.upstream_thread.join(timeout=2)
        self.web_directory.cleanup()

    def test_serves_status_and_web_build_files(self) -> None:
        with urllib.request.urlopen(
            f"http://127.0.0.1:{self.gateway_port}/status", timeout=2
        ) as response:
            self.assertEqual(response.status, 200)
            self.assertIn(b'"server": "online"', response.read())

        for name in ("index.html", "index.js", "index.wasm", "index.pck"):
            with urllib.request.urlopen(
                f"http://127.0.0.1:{self.gateway_port}/{name}", timeout=2
            ) as response:
                self.assertEqual(response.status, 200, name)
                self.assertGreater(int(response.headers["Content-Length"]), 0, name)

    def test_websocket_handshake_and_bytes_are_tunneled_transparently(self) -> None:
        key = base64.b64encode(b"0123456789abcdef").decode()
        request = (
            "GET /ws?client=integration HTTP/1.1\r\n"
            f"Host: 127.0.0.1:{self.gateway_port}\r\n"
            "Connection: keep-alive, Upgrade\r\n"
            "Upgrade: websocket\r\n"
            "Origin: http://127.0.0.1\r\n"
            f"Sec-WebSocket-Key: {key}\r\n"
            "Sec-WebSocket-Version: 13\r\n"
            "\r\n"
        ).encode("ascii")

        with socket.create_connection(("127.0.0.1", self.gateway_port), timeout=2) as client:
            client.sendall(request)
            response = receive_until(client, b"\r\n\r\n")
            self.assertTrue(response.startswith(b"HTTP/1.1 101"), response)

            opaque_websocket_bytes = b"\x82\x05input\x80\x00"
            client.sendall(opaque_websocket_bytes)
            self.assertEqual(
                receive_exactly(client, len(opaque_websocket_bytes)),
                opaque_websocket_bytes,
            )

        upstream_request = self.upstream.last_handshake.decode("iso-8859-1")
        self.assertIn("GET /ws?client=integration HTTP/1.1\r\n", upstream_request)
        self.assertIn(f"Sec-WebSocket-Key: {key}\r\n", upstream_request)
        self.assertIn("Origin: http://127.0.0.1\r\n", upstream_request)

    def test_ws_path_requires_an_upgrade(self) -> None:
        with self.assertRaises(urllib.error.HTTPError) as context:
            urllib.request.urlopen(
                f"http://127.0.0.1:{self.gateway_port}/ws", timeout=2
            )
        self.assertEqual(context.exception.code, 426)


if __name__ == "__main__":
    unittest.main(verbosity=2)
