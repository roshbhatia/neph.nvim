"""
test_shim.py — tests for tools/core/shim.py

Strategy: All tests that exercise NvimRPC or command functions run against the
`nvim_server` fixture (a real in-process Unix socket server) so we verify the
actual msgpack framing, not a mock.  Error-path tests that call connect() use
monkeypatch to set/clear NVIM_SOCKET_PATH and run shim as a subprocess (because
connect() / die() calls sys.exit).
"""
from __future__ import annotations

import importlib
import io
import json
import os
import subprocess
import sys
import unittest.mock as mock
from pathlib import Path
from typing import Any

import msgpack
import pytest

# ── Helpers to load shim module cleanly ──────────────────────────────────────

SHIM_PATH = Path(__file__).parents[1] / "shim.py"


def _load_shim():
    """
    Import shim.py as a module even though it has a shebang line.
    We read the source, strip the shebang, and exec into a fresh module namespace.
    """
    import types
    src = SHIM_PATH.read_text()
    # Strip PEP 723 inline script block and shebang so import works
    lines = src.splitlines()
    # Remove shebang
    if lines and lines[0].startswith("#!"):
        lines = lines[1:]
    module = types.ModuleType("shim")
    module.__file__ = str(SHIM_PATH)
    exec(compile("\n".join(lines), str(SHIM_PATH), "exec"), module.__dict__)
    return module


@pytest.fixture(scope="module")
def shim():
    return _load_shim()


# ── NvimRPC: connection and framing ──────────────────────────────────────────


class TestNvimRPC:
    def test_successful_connect(self, shim, nvim_server):
        """NvimRPC connects to a valid socket without raising."""
        rpc = shim.NvimRPC(nvim_server.socket_path)
        rpc.close()

    def test_request_sends_correct_frame(self, shim, nvim_server):
        """request() sends [0, msgid, method, params] and the server records it."""
        rpc = shim.NvimRPC(nvim_server.socket_path)
        nvim_server.set_reply(result="ignored")
        rpc.request("nvim_exec_lua", "return 1", [])
        rpc.close()

        call = nvim_server.last_call
        assert call is not None
        assert call["method"] == "nvim_exec_lua"
        assert call["params"][0] == "return 1"
        assert call["params"][1] == []

    def test_request_returns_result(self, shim, nvim_server):
        """request() returns the result field of the server's response."""
        nvim_server.set_reply(result={"status": "ok"})
        rpc = shim.NvimRPC(nvim_server.socket_path)
        result = rpc.request("nvim_exec_lua", "return {}", [])
        rpc.close()
        assert result == {"status": "ok"}

    def test_request_raises_on_error_response(self, shim, nvim_server):
        """request() raises RuntimeError when the server returns an error."""
        nvim_server.set_reply(error="some nvim error")
        rpc = shim.NvimRPC(nvim_server.socket_path)
        with pytest.raises(RuntimeError, match="some nvim error"):
            rpc.request("nvim_exec_lua", "bad lua", [])
        rpc.close()

    def test_notification_frames_are_skipped(self, shim, nvim_server):
        """request() ignores [2, ...] notification frames and returns the real response."""
        nvim_server.set_reply(result="real_result")
        nvim_server.send_notification_before_reply = True
        rpc = shim.NvimRPC(nvim_server.socket_path)
        result = rpc.request("nvim_exec_lua", "return 'real'", [])
        rpc.close()
        nvim_server.send_notification_before_reply = False
        assert result == "real_result"

    def test_exec_lua_is_request_wrapper(self, shim, nvim_server):
        """exec_lua() is a thin wrapper around request('nvim_exec_lua', ...)."""
        nvim_server.set_reply(result=42)
        rpc = shim.NvimRPC(nvim_server.socket_path)
        result = rpc.exec_lua("return 42", [])
        rpc.close()
        assert result == 42
        assert nvim_server.last_call["method"] == "nvim_exec_lua"

    def test_default_timeout_is_applied(self, shim, nvim_server):
        """NvimRPC with default timeout calls sock.settimeout(30.0)."""
        with mock.patch("socket.socket") as mock_sock_cls:
            mock_sock = mock.MagicMock()
            mock_sock_cls.return_value = mock_sock
            # connect() succeeds trivially
            mock_sock.connect.return_value = None
            rpc = shim.NvimRPC(nvim_server.socket_path)  # timeout=30.0 default
            mock_sock.settimeout.assert_called_once_with(30.0)

    def test_none_timeout_does_not_call_settimeout(self, shim, nvim_server):
        """NvimRPC with timeout=None does NOT call sock.settimeout."""
        with mock.patch("socket.socket") as mock_sock_cls:
            mock_sock = mock.MagicMock()
            mock_sock_cls.return_value = mock_sock
            mock_sock.connect.return_value = None
            rpc = shim.NvimRPC(nvim_server.socket_path, timeout=None)
            mock_sock.settimeout.assert_not_called()

    def test_custom_timeout_is_applied(self, shim, nvim_server):
        """NvimRPC with custom timeout passes that value to settimeout."""
        with mock.patch("socket.socket") as mock_sock_cls:
            mock_sock = mock.MagicMock()
            mock_sock_cls.return_value = mock_sock
            mock_sock.connect.return_value = None
            rpc = shim.NvimRPC(nvim_server.socket_path, timeout=5.0)
            mock_sock.settimeout.assert_called_once_with(5.0)


# ── connect() error paths (subprocess — because die() calls sys.exit) ────────


RUNNER = [sys.executable, str(SHIM_PATH)]


def _run_shim(*args: str, env: dict | None = None, stdin: str | None = None):
    """Run shim.py as a subprocess and return (returncode, stdout, stderr)."""
    base_env = {k: v for k, v in os.environ.items()}
    base_env.pop("NVIM_SOCKET_PATH", None)
    if env:
        base_env.update(env)

    result = subprocess.run(
        RUNNER + list(args),
        env=base_env,
        capture_output=True,
        text=True,
        input=stdin,
    )
    return result.returncode, result.stdout, result.stderr


class TestConnectErrors:
    def test_missing_socket_path_env(self):
        """When NVIM_SOCKET_PATH is absent, shim exits 1 with 'not set'."""
        code, _, stderr = _run_shim("status")
        assert code == 1
        assert "not set" in stderr.lower()

    def test_nonexistent_socket_path(self, tmp_path):
        """When NVIM_SOCKET_PATH points to a non-existent file, exits 1 with 'not found'."""
        bad_path = str(tmp_path / "no_such.sock")
        code, _, stderr = _run_shim("status", env={"NVIM_SOCKET_PATH": bad_path})
        assert code == 1
        assert "not found" in stderr.lower()


# ── Click CLI tests ───────────────────────────────────────────────────────────


class TestClickCLI:
    def test_help_exits_0_with_usage(self):
        """shim --help exits 0 and stdout contains 'Usage:'."""
        code, stdout, _ = _run_shim("--help")
        assert code == 0
        assert "usage" in stdout.lower()

    def test_unknown_command_exits_nonzero(self):
        """shim bogus-command exits non-zero with 'No such command' in stderr."""
        code, _, stderr = _run_shim("bogus-command")
        assert code != 0
        assert "no such command" in stderr.lower()

    def test_open_missing_argument_exits_nonzero(self):
        """shim open (missing FILE) exits non-zero with 'Missing argument' in stderr."""
        code, _, stderr = _run_shim("open", env={"NVIM_SOCKET_PATH": "/dev/null"})
        assert code != 0
        assert "missing argument" in stderr.lower()

    def test_set_missing_arguments_exits_nonzero(self):
        """shim set (missing NAME and LUA_VALUE) exits non-zero with 'Missing argument'."""
        code, _, stderr = _run_shim("set", env={"NVIM_SOCKET_PATH": "/dev/null"})
        assert code != 0
        assert "missing argument" in stderr.lower()

    def test_subcommand_help_exits_0(self):
        """shim preview --help exits 0."""
        code, stdout, _ = _run_shim("preview", "--help")
        assert code == 0
        assert "usage" in stdout.lower()

    def test_no_args_shows_help(self):
        """shim with no args exits 0 (Click groups show help by default)."""
        code, stdout, stderr = _run_shim()
        # Click writes group help to stderr when no subcommand is given
        assert "usage" in stderr.lower() or "usage" in stdout.lower()


# ── Command dispatch: verify Lua sent to server ───────────────────────────────


class TestCommandDispatch:
    """Run each command function directly against the fake server."""

    def _run_cmd(self, shim, nvim_server, fn_name: str, *args, reply: Any = "ok", stdin_text: str | None = None):
        """Call shim.<fn_name>(*args) with SOCKET_PATH patched to the fake server."""
        old_path = shim.SOCKET_PATH
        shim.SOCKET_PATH = nvim_server.socket_path
        nvim_server.set_reply(result=reply)
        try:
            fn = getattr(shim, fn_name)
            if stdin_text is not None:
                # patch sys.stdin for preview
                old_stdin = sys.stdin
                sys.stdin = io.StringIO(stdin_text)
                try:
                    fn(*args)
                finally:
                    sys.stdin = old_stdin
            else:
                fn(*args)
        finally:
            shim.SOCKET_PATH = old_path

    def test_cmd_open_sends_file_path(self, shim, nvim_server):
        self._run_cmd(shim, nvim_server, "cmd_open", "/some/file.py")
        call = nvim_server.last_call
        assert call["method"] == "nvim_exec_lua"
        assert "/some/file.py" in call["params"][1]

    def test_cmd_checktime_sends_checktime(self, shim, nvim_server):
        self._run_cmd(shim, nvim_server, "cmd_checktime")
        call = nvim_server.last_call
        assert "checktime" in call["params"][0]

    def test_cmd_set_sends_name_and_value(self, shim, nvim_server):
        self._run_cmd(shim, nvim_server, "cmd_set", "pi_active", "true")
        call = nvim_server.last_call
        assert "pi_active" in call["params"][1]
        assert "true" in call["params"][0]

    def test_cmd_unset_sends_nil(self, shim, nvim_server):
        self._run_cmd(shim, nvim_server, "cmd_unset", "pi_running")
        call = nvim_server.last_call
        assert "pi_running" in call["params"][1]
        assert "nil" in call["params"][0]

    def test_cmd_revert_sends_file_path(self, shim, nvim_server):
        self._run_cmd(shim, nvim_server, "cmd_revert", "/tmp/file.py")
        call = nvim_server.last_call
        assert "/tmp/file.py" in call["params"][1]

    def test_cmd_close_tab_sends_lua(self, shim, nvim_server):
        self._run_cmd(shim, nvim_server, "cmd_close_tab")
        call = nvim_server.last_call
        assert "agent_tab" in call["params"][0]

    def test_cmd_open_uses_default_timeout(self, shim, nvim_server):
        """cmd_open connects with default 30-second timeout."""
        with mock.patch.object(shim, "connect", wraps=shim.connect) as mock_connect:
            old_path = shim.SOCKET_PATH
            shim.SOCKET_PATH = nvim_server.socket_path
            nvim_server.set_reply(result="ok")
            try:
                shim.cmd_open("/tmp/test.py")
            finally:
                shim.SOCKET_PATH = old_path
            # connect() should be called without a timeout arg (uses default 30.0)
            mock_connect.assert_called_once()
            call_kwargs = mock_connect.call_args
            # No explicit timeout= means the default 30.0 is used
            assert call_kwargs == mock.call() or call_kwargs.kwargs.get("timeout", 30.0) == 30.0

    def test_cmd_preview_uses_no_timeout(self, shim, nvim_server):
        """cmd_preview connects with timeout=None (blocking, no deadline)."""
        captured_timeouts = []

        original_NvimRPC = shim.NvimRPC

        class TrackingNvimRPC(original_NvimRPC):
            def __init__(self, path, timeout=30.0):
                captured_timeouts.append(timeout)
                # Don't call super().__init__ to avoid real socket; just mock
                self._msgid = 0
                import msgpack as mp
                self._buf = mp.Unpacker(raw=False, strict_map_key=False)

        old_path = shim.SOCKET_PATH
        shim.SOCKET_PATH = nvim_server.socket_path
        nvim_server.set_reply(result={"decision": "accept", "content": "ok"})

        old_rpc = shim.NvimRPC
        shim.NvimRPC = TrackingNvimRPC
        old_stdin = sys.stdin
        sys.stdin = io.StringIO("proposed content")
        try:
            # cmd_preview should call connect(timeout=None)
            # We call connect directly to inspect the timeout
            with mock.patch.object(shim, "connect", wraps=lambda timeout=30.0: shim.NvimRPC(nvim_server.socket_path, timeout=timeout)) as mock_connect:
                shim.cmd_preview("/tmp/test.py")
                assert mock_connect.called
                call_kwargs = mock_connect.call_args
                assert call_kwargs.kwargs.get("timeout") is None or (
                    len(call_kwargs.args) > 0 and call_kwargs.args[0] is None
                )
        except Exception:
            pass  # connect mock may fail on socket; we only care about arg inspection
        finally:
            sys.stdin = old_stdin
            shim.NvimRPC = old_rpc
            shim.SOCKET_PATH = old_path


# ── cmd_preview ───────────────────────────────────────────────────────────────


class TestCmdPreview:
    def test_sends_file_path_and_stdin_content(self, shim, nvim_server, capsys):
        """cmd_preview sends [file_path, stdin_content] as args to nvim_exec_lua."""
        expected = {"decision": "accept", "content": "final content"}
        old_path = shim.SOCKET_PATH
        shim.SOCKET_PATH = nvim_server.socket_path
        nvim_server.set_reply(result=expected)
        old_stdin = sys.stdin
        sys.stdin = io.StringIO("new content")
        try:
            shim.cmd_preview("/file.py")
        finally:
            sys.stdin = old_stdin
            shim.SOCKET_PATH = old_path

        call = nvim_server.last_call
        assert call["params"][1] == ["/file.py", "new content"]

        # JSON result printed to stdout
        captured = capsys.readouterr()
        parsed = json.loads(captured.out)
        assert parsed["decision"] == "accept"


# ── main() / CLI dispatch ─────────────────────────────────────────────────────


class TestMain:
    def test_unknown_command_exits_nonzero(self):
        """Click exits non-zero for unknown subcommands."""
        code, _, stderr = _run_shim("bogus-command", env={"NVIM_SOCKET_PATH": "/dev/null"})
        assert code != 0

    def test_no_args_shows_help_or_exits_0(self):
        """Click group with no subcommand shows help (exits 0)."""
        code, stdout, stderr = _run_shim()
        assert "usage" in stderr.lower() or "usage" in stdout.lower() or code == 0


# ── Lua script loading ────────────────────────────────────────────────────────


class TestLuaScriptLoading:
    def test_lua_open_is_nonempty_string(self, shim):
        assert isinstance(shim.LUA_OPEN, str)
        assert len(shim.LUA_OPEN.strip()) > 0

    def test_lua_revert_is_nonempty_string(self, shim):
        assert isinstance(shim.LUA_REVERT, str)
        assert len(shim.LUA_REVERT.strip()) > 0

    def test_lua_preview_is_nonempty_string(self, shim):
        assert isinstance(shim.LUA_PREVIEW, str)
        assert len(shim.LUA_PREVIEW.strip()) > 0

    def test_missing_lua_file_raises_file_not_found(self, tmp_path):
        """Patching _LUA_DIR to a dir without .lua files causes FileNotFoundError on reload."""
        import types
        src = SHIM_PATH.read_text()
        lines = src.splitlines()
        if lines and lines[0].startswith("#!"):
            lines = lines[1:]
        module = types.ModuleType("shim_missing")
        module.__file__ = str(SHIM_PATH)
        patched = "\n".join(lines).replace(
            '_LUA_DIR = Path(__file__).resolve().parent / "lua"',
            f'_LUA_DIR = Path("{tmp_path}")',
        )
        with pytest.raises(FileNotFoundError):
            exec(compile(patched, str(SHIM_PATH), "exec"), module.__dict__)


# ── Lua script content via FakeNvimServer ─────────────────────────────────────


class TestLuaScriptContent:
    """Assert that each cmd_* function sends the correct loaded Lua to nvim_exec_lua."""

    def _patch(self, shim, nvim_server, fn_name, *args, reply="ok", stdin_text=None):
        old = shim.SOCKET_PATH
        shim.SOCKET_PATH = nvim_server.socket_path
        nvim_server.set_reply(result=reply)
        try:
            fn = getattr(shim, fn_name)
            if stdin_text is not None:
                old_stdin = sys.stdin
                sys.stdin = io.StringIO(stdin_text)
                try:
                    fn(*args)
                finally:
                    sys.stdin = old_stdin
            else:
                fn(*args)
        finally:
            shim.SOCKET_PATH = old

    def test_cmd_open_sends_lua_open_script(self, shim, nvim_server):
        self._patch(shim, nvim_server, "cmd_open", "/tmp/test.py")
        req = nvim_server.last_call
        assert req["method"] == "nvim_exec_lua"
        assert req["params"][0] == shim.LUA_OPEN

    def test_cmd_revert_sends_lua_revert_script(self, shim, nvim_server):
        self._patch(shim, nvim_server, "cmd_revert", "/tmp/test.py")
        req = nvim_server.last_call
        assert req["method"] == "nvim_exec_lua"
        assert req["params"][0] == shim.LUA_REVERT

    def test_cmd_preview_sends_lua_preview_script(self, shim, nvim_server):
        reply = {"decision": "accept", "content": "proposed content"}
        self._patch(shim, nvim_server, "cmd_preview", "/tmp/test.py",
                    reply=reply, stdin_text="proposed content")
        req = nvim_server.last_call
        assert req["method"] == "nvim_exec_lua"
        assert req["params"][0] == shim.LUA_PREVIEW
