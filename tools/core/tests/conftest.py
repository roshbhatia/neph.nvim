"""
conftest.py — pytest fixtures for shim.py tests.

Provides:
  mock_nvim        — patches pynvim.attach to return a MagicMock; use in unit tests
  nvim_socket_path — sets shim.SOCKET_PATH to a fake path; for subprocess error tests
  headless_nvim    — starts a real `nvim --headless --listen` process;
                     requires NEPH_INTEGRATION_TESTS=1 and nvim in PATH
"""
from __future__ import annotations

import os
import shutil
import subprocess
import tempfile
import time
import unittest.mock as mock

import pytest


@pytest.fixture
def mock_nvim(monkeypatch):
    """
    Patch pynvim.attach to return a MagicMock.

    The mock has:
      .exec_lua   — MagicMock (assert calls on it)
      .command    — MagicMock

    Usage::

        def test_cmd_open(mock_nvim):
            import shim
            shim.cmd_open("/tmp/foo.py")
            mock_nvim.exec_lua.assert_called_once_with(shim.LUA_OPEN, "/tmp/foo.py")
    """
    nvim_mock = mock.MagicMock(name="pynvim.Nvim")
    with mock.patch("pynvim.attach", return_value=nvim_mock) as _patch:
        yield nvim_mock


@pytest.fixture
def nvim_socket_path(tmp_path, monkeypatch):
    """
    Set shim.SOCKET_PATH (and the env var) to a plausible-looking but
    nonexistent socket path inside tmp_path.

    This keeps subprocess-level tests isolated without a real server.
    Returns the fake path string.
    """
    import sys
    from pathlib import Path

    # We set the env var so subprocesses see it too
    fake = str(tmp_path / "fake.sock")
    monkeypatch.setenv("NVIM_SOCKET_PATH", fake)

    # Also patch the module-level constant for in-process tests
    shim_path = Path(__file__).parents[1] / "shim.py"
    # Import shim if already loaded; otherwise just set env
    if "shim" in sys.modules:
        monkeypatch.setattr(sys.modules["shim"], "SOCKET_PATH", fake)

    yield fake


@pytest.fixture(scope="session")
def headless_nvim():
    """
    Start a real headless Neovim process listening on a temp Unix socket.

    Skips automatically unless NEPH_INTEGRATION_TESTS=1 is set and nvim is
    available in PATH.

    Yields the socket path string. The process is killed on teardown.
    """
    if not os.environ.get("NEPH_INTEGRATION_TESTS"):
        pytest.skip("set NEPH_INTEGRATION_TESTS=1 to run integration tests")

    if not shutil.which("nvim"):
        pytest.skip("nvim not found in PATH")

    sock = tempfile.mktemp(prefix="neph_test_", suffix=".sock", dir=tempfile.gettempdir())
    proc = subprocess.Popen(
        ["nvim", "--headless", "--listen", sock],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )

    # Wait up to 3s for the socket to appear
    deadline = time.monotonic() + 3.0
    while not os.path.exists(sock):
        if time.monotonic() > deadline:
            proc.kill()
            pytest.skip("headless nvim socket did not appear in time")
        time.sleep(0.05)

    yield sock

    proc.kill()
    proc.wait(timeout=3)
    try:
        os.unlink(sock)
    except FileNotFoundError:
        pass
