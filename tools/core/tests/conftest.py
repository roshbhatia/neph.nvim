"""
conftest.py — pytest fixtures for shim.py tests.

Provides `nvim_server`: a real Unix socket server that speaks the msgpack-rpc
request/response protocol.  Tests can inspect received calls and pre-configure
what the server should reply.

Protocol (msgpack-rpc):
  Request:  [0, msgid, method, params]
  Response: [1, msgid, error, result]
  Notification: [2, method, params]   (sent by server to skip test)
"""
from __future__ import annotations

import os
import socketserver
import tempfile
import threading
from typing import Any

import msgpack
import pytest


class _FakeNvimHandler(socketserver.BaseRequestHandler):
    """Handle one connection: read one request, reply, close."""

    def handle(self) -> None:
        server: FakeNvimServer = self.server  # type: ignore[assignment]
        buf = msgpack.Unpacker(raw=False, strict_map_key=False)

        # Read until we get a full request frame
        while True:
            data = self.request.recv(65536)
            if not data:
                return
            buf.feed(data)
            for msg in buf:
                if msg[0] == 0:  # request
                    msgid = msg[1]
                    method = msg[2]
                    params = msg[3]

                    # Record for assertions
                    server.last_call = {
                        "method": method,
                        "params": params,
                    }
                    server.calls.append(server.last_call.copy())

                    # Optionally send a notification first (to test skip logic)
                    if server.send_notification_before_reply:
                        notif = msgpack.packb([2, "some_event", []], use_bin_type=True)
                        self.request.sendall(notif)

                    # Build response
                    if server.reply_error is not None:
                        response = msgpack.packb(
                            [1, msgid, server.reply_error, None],
                            use_bin_type=True,
                        )
                    else:
                        response = msgpack.packb(
                            [1, msgid, None, server.reply_result],
                            use_bin_type=True,
                        )
                    self.request.sendall(response)
                    return  # one request per connection in shim.py


class FakeNvimServer(socketserver.UnixStreamServer):
    """Minimal msgpack-rpc server for testing shim.py."""

    allow_reuse_address = True

    def __init__(self, socket_path: str) -> None:
        super().__init__(socket_path, _FakeNvimHandler)
        self.socket_path = socket_path
        # Configurable reply
        self.reply_result: Any = "ok"
        self.reply_error: Any = None
        self.send_notification_before_reply: bool = False
        # Recorded calls
        self.last_call: dict[str, Any] | None = None
        self.calls: list[dict[str, Any]] = []

    def set_reply(self, result: Any = "ok", error: Any = None) -> None:
        self.reply_result = result
        self.reply_error = error


@pytest.fixture
def nvim_server():
    """
    Spin up a fake Neovim msgpack-rpc server on a temp Unix socket.

    Uses a short path in the system temp dir to stay within macOS's
    104-char AF_UNIX socket path limit.

    Yields the FakeNvimServer so tests can inspect .last_call and configure
    .reply_result / .reply_error before making calls.
    """
    # tempfile.mktemp is fine here: we create and immediately bind in the
    # constructor, so the race window is negligible for test sockets.
    socket_path = tempfile.mktemp(prefix="nv", suffix=".s", dir=tempfile.gettempdir())
    server = FakeNvimServer(socket_path)

    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()

    yield server

    server.shutdown()
    thread.join(timeout=2)
    try:
        os.unlink(socket_path)
    except FileNotFoundError:
        pass

