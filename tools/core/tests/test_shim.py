"""
test_shim.py — tests for tools/core/shim.py

Strategy:
  - Unit tests patch pynvim.attach via the `mock_nvim` fixture — no real socket needed
  - Subprocess tests (_run_shim) cover CLI dispatch, error exits, and missing-arg errors
  - Click CliRunner tests give fast in-process coverage of CLI dispatch
  - Integration tests (marked @pytest.mark.integration) use a real headless nvim;
    skipped unless NEPH_INTEGRATION_TESTS=1
"""
from __future__ import annotations

import io
import json
import os
import subprocess
import sys
import types
import unittest.mock as mock
from pathlib import Path

import pytest
from click.testing import CliRunner

SHIM_PATH = Path(__file__).parents[1] / "shim.py"
RUNNER = [sys.executable, str(SHIM_PATH)]


# ── Module loader (strips shebang for exec) ───────────────────────────────────


def _load_shim(lua_dir: Path | None = None) -> types.ModuleType:
    """Load shim.py into a fresh module, optionally overriding _LUA_DIR."""
    src = SHIM_PATH.read_text()
    lines = src.splitlines()
    if lines and lines[0].startswith("#!"):
        lines = lines[1:]
    if lua_dir is not None:
        joined = "\n".join(lines)
        joined = joined.replace(
            '_LUA_DIR = Path(__file__).resolve().parent / "lua"',
            f'_LUA_DIR = Path("{lua_dir}")',
        )
        lines = joined.splitlines()
    module = types.ModuleType("shim")
    module.__file__ = str(SHIM_PATH)
    exec(compile("\n".join(lines), str(SHIM_PATH), "exec"), module.__dict__)
    return module


@pytest.fixture(scope="module")
def shim():
    return _load_shim()


# ── Subprocess helper ─────────────────────────────────────────────────────────


def _run_shim(*args: str, env: dict | None = None, stdin: str | None = None):
    """Run shim.py as a subprocess; returns (returncode, stdout, stderr)."""
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


# ── 1. Lua script loading ─────────────────────────────────────────────────────


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

    def test_missing_lua_dir_raises_file_not_found(self, tmp_path):
        """Loading shim with _LUA_DIR pointing to an empty dir raises FileNotFoundError."""
        with pytest.raises(FileNotFoundError):
            _load_shim(lua_dir=tmp_path)

    def test_lua_scripts_are_distinct(self, shim):
        """The three Lua constants must be different scripts."""
        assert shim.LUA_OPEN != shim.LUA_REVERT
        assert shim.LUA_OPEN != shim.LUA_PREVIEW
        assert shim.LUA_REVERT != shim.LUA_PREVIEW

    def test_no_msgpack_import(self):
        """shim.py must not import msgpack directly."""
        src = SHIM_PATH.read_text()
        assert "import msgpack" not in src
        assert "from msgpack" not in src

    def test_pynvim_imported(self):
        """shim.py must import pynvim."""
        src = SHIM_PATH.read_text()
        assert "import pynvim" in src


# ── 2. Error paths (subprocess) ───────────────────────────────────────────────


class TestConnectErrors:
    def test_missing_socket_path_env(self):
        """Exits 1 with 'not set' when NVIM_SOCKET_PATH is absent."""
        code, _, stderr = _run_shim("status")
        assert code == 1
        assert "not set" in stderr.lower()

    def test_nonexistent_socket_path(self, tmp_path):
        """Exits 1 with 'not found' when the socket file doesn't exist."""
        bad = str(tmp_path / "no_such.sock")
        code, _, stderr = _run_shim("status", env={"NVIM_SOCKET_PATH": bad})
        assert code == 1
        assert "not found" in stderr.lower()

    def test_oserror_on_attach_exits_1(self, shim, tmp_path):
        """OSError from pynvim.attach is caught; exits 1 with 'cannot connect'."""
        sock = str(tmp_path / "fake.sock")
        # Create the file so the existence check passes
        Path(sock).touch()
        old_path = shim.SOCKET_PATH
        shim.SOCKET_PATH = sock
        try:
            with mock.patch("pynvim.attach", side_effect=OSError("connection refused")):
                with pytest.raises(SystemExit) as exc_info:
                    shim.cmd_status()
                assert exc_info.value.code == 1
        finally:
            shim.SOCKET_PATH = old_path


# ── 3. get_nvim() timeout behaviour ──────────────────────────────────────────


class TestGetNvim:
    """Verify socket.setdefaulttimeout is called correctly around pynvim.attach."""

    def _run_get_nvim(self, shim, sock_path: str, timeout=30.0):
        """Call get_nvim with a patched pynvim.attach and spy on setdefaulttimeout."""
        timeouts_set = []
        real_sdt = mock.MagicMock(side_effect=lambda t: timeouts_set.append(t))
        nvim_mock = mock.MagicMock()

        old_path = shim.SOCKET_PATH
        shim.SOCKET_PATH = sock_path
        try:
            with mock.patch("socket.setdefaulttimeout", real_sdt), \
                 mock.patch("pynvim.attach", return_value=nvim_mock):
                shim.get_nvim(timeout)
        finally:
            shim.SOCKET_PATH = old_path

        return timeouts_set

    def test_default_timeout_is_30(self, shim, tmp_path):
        sock = str(tmp_path / "s.sock")
        Path(sock).touch()
        timeouts = self._run_get_nvim(shim, sock, 30.0)
        assert timeouts[0] == 30.0, "setdefaulttimeout(30.0) not called before attach"

    def test_none_timeout_for_preview(self, shim, tmp_path):
        sock = str(tmp_path / "s.sock")
        Path(sock).touch()
        timeouts = self._run_get_nvim(shim, sock, None)
        assert timeouts[0] is None, "setdefaulttimeout(None) not called for preview"

    def test_timeout_reset_after_attach(self, shim, tmp_path):
        """setdefaulttimeout(None) is called after attach to restore the global default."""
        sock = str(tmp_path / "s.sock")
        Path(sock).touch()
        timeouts = self._run_get_nvim(shim, sock, 30.0)
        assert len(timeouts) == 2
        assert timeouts[1] is None, "setdefaulttimeout not reset to None after attach"

    def test_cmd_preview_calls_get_nvim_with_none_timeout(self, shim, tmp_path):
        """cmd_preview calls get_nvim(timeout=None) — no deadline for interactive diff."""
        sock = str(tmp_path / "s.sock")
        Path(sock).touch()
        captured = []

        def spy_get_nvim(timeout=30.0):
            captured.append(timeout)
            m = mock.MagicMock()
            m.exec_lua.return_value = {"decision": "accept", "content": "x"}
            return m

        old_path = shim.SOCKET_PATH
        shim.SOCKET_PATH = sock
        old_stdin = sys.stdin
        sys.stdin = io.StringIO("proposed content")
        old_fn = shim.get_nvim
        shim.get_nvim = spy_get_nvim
        try:
            shim.cmd_preview("/tmp/test.py")
        finally:
            sys.stdin = old_stdin
            shim.SOCKET_PATH = old_path
            shim.get_nvim = old_fn

        assert captured == [None], f"cmd_preview called get_nvim with {captured}, want [None]"

    def test_cmd_open_calls_get_nvim_with_default_timeout(self, shim, tmp_path):
        """cmd_open calls get_nvim() with the default 30s timeout."""
        sock = str(tmp_path / "s.sock")
        Path(sock).touch()
        captured = []

        def spy_get_nvim(timeout=30.0):
            captured.append(timeout)
            return mock.MagicMock()

        old_path = shim.SOCKET_PATH
        shim.SOCKET_PATH = sock
        old_fn = shim.get_nvim
        shim.get_nvim = spy_get_nvim
        try:
            shim.cmd_open("/tmp/test.py")
        finally:
            shim.SOCKET_PATH = old_path
            shim.get_nvim = old_fn

        assert captured == [30.0], f"cmd_open called get_nvim with {captured}, want [30.0]"


# ── 4. Command dispatch via mock_nvim ─────────────────────────────────────────


class TestCommandDispatch:
    """Each cmd_* sends the correct exec_lua call to the pynvim mock."""

    def _with_mock(self, shim, mock_nvim, fn_name: str, *args,
                   return_value=None, stdin_text: str | None = None):
        """Call shim.<fn_name>(*args) with get_nvim patched to return mock_nvim."""
        if return_value is not None:
            mock_nvim.exec_lua.return_value = return_value
        old_path = shim.SOCKET_PATH
        # Point to a real-looking path that passes the existence check
        import tempfile
        sock = tempfile.mktemp(suffix=".sock")
        Path(sock).touch()
        shim.SOCKET_PATH = sock
        old_stdin = sys.stdin
        if stdin_text is not None:
            sys.stdin = io.StringIO(stdin_text)
        try:
            with mock.patch("pynvim.attach", return_value=mock_nvim):
                getattr(shim, fn_name)(*args)
        finally:
            if stdin_text is not None:
                sys.stdin = old_stdin
            shim.SOCKET_PATH = old_path
            try:
                os.unlink(sock)
            except FileNotFoundError:
                pass

    def test_cmd_status_connects(self, shim, mock_nvim, capsys):
        self._with_mock(shim, mock_nvim, "cmd_status")
        captured = capsys.readouterr()
        assert "connected:" in captured.out

    def test_cmd_open_sends_lua_open_with_path(self, shim, mock_nvim):
        self._with_mock(shim, mock_nvim, "cmd_open", "/some/file.py")
        mock_nvim.exec_lua.assert_called_once_with(shim.LUA_OPEN, "/some/file.py")

    def test_cmd_revert_sends_lua_revert_with_path(self, shim, mock_nvim):
        self._with_mock(shim, mock_nvim, "cmd_revert", "/tmp/file.py")
        mock_nvim.exec_lua.assert_called_once_with(shim.LUA_REVERT, "/tmp/file.py")

    def test_cmd_checktime_sends_checktime_lua(self, shim, mock_nvim):
        self._with_mock(shim, mock_nvim, "cmd_checktime")
        code = mock_nvim.exec_lua.call_args[0][0]
        assert "checktime" in code

    def test_cmd_close_tab_sends_agent_tab_lua(self, shim, mock_nvim):
        self._with_mock(shim, mock_nvim, "cmd_close_tab")
        code = mock_nvim.exec_lua.call_args[0][0]
        assert "agent_tab" in code

    def test_cmd_set_sends_name_and_value(self, shim, mock_nvim):
        self._with_mock(shim, mock_nvim, "cmd_set", "pi_active", "true")
        args = mock_nvim.exec_lua.call_args[0]
        assert "true" in args[0]       # lua_value interpolated into script
        assert "pi_active" in args[1]  # name passed as vararg

    def test_cmd_unset_sends_nil_and_name(self, shim, mock_nvim):
        self._with_mock(shim, mock_nvim, "cmd_unset", "pi_running")
        args = mock_nvim.exec_lua.call_args[0]
        assert "nil" in args[0]
        assert "pi_running" in args[1]

    def test_cmd_preview_sends_lua_preview_with_path_and_content(self, shim, mock_nvim, capsys):
        mock_nvim.exec_lua.return_value = {"decision": "accept", "content": "final"}
        self._with_mock(shim, mock_nvim, "cmd_preview", "/f.py",
                        return_value={"decision": "accept", "content": "final"},
                        stdin_text="proposed content")
        mock_nvim.exec_lua.assert_called_once_with(
            shim.LUA_PREVIEW, "/f.py", "proposed content"
        )

    def test_cmd_preview_prints_json(self, shim, mock_nvim, capsys):
        payload = {"decision": "accept", "content": "final"}
        mock_nvim.exec_lua.return_value = payload
        self._with_mock(shim, mock_nvim, "cmd_preview", "/f.py",
                        return_value=payload, stdin_text="body")
        out = capsys.readouterr().out
        assert json.loads(out) == payload


# ── 5. Lua script dispatch identity ──────────────────────────────────────────


class TestLuaScriptDispatch:
    """Verify each command sends the right script constant, not another one."""

    def _capture_exec_lua(self, shim, fn_name: str, *args,
                          return_value=None, stdin_text: str | None = None):
        nvim_mock = mock.MagicMock()
        if return_value is not None:
            nvim_mock.exec_lua.return_value = return_value
        import tempfile
        sock = tempfile.mktemp(suffix=".sock")
        Path(sock).touch()
        old_path = shim.SOCKET_PATH
        shim.SOCKET_PATH = sock
        old_stdin = sys.stdin
        if stdin_text is not None:
            sys.stdin = io.StringIO(stdin_text)
        try:
            with mock.patch("pynvim.attach", return_value=nvim_mock):
                getattr(shim, fn_name)(*args)
        finally:
            if stdin_text is not None:
                sys.stdin = old_stdin
            shim.SOCKET_PATH = old_path
            try:
                os.unlink(sock)
            except FileNotFoundError:
                pass
        return nvim_mock.exec_lua.call_args[0][0]  # first positional arg = script

    def test_cmd_open_sends_LUA_OPEN(self, shim):
        script = self._capture_exec_lua(shim, "cmd_open", "/f.py")
        assert script == shim.LUA_OPEN

    def test_cmd_revert_sends_LUA_REVERT(self, shim):
        script = self._capture_exec_lua(shim, "cmd_revert", "/f.py")
        assert script == shim.LUA_REVERT

    def test_cmd_preview_sends_LUA_PREVIEW(self, shim):
        script = self._capture_exec_lua(
            shim, "cmd_preview", "/f.py",
            return_value={"decision": "accept", "content": "x"},
            stdin_text="body",
        )
        assert script == shim.LUA_PREVIEW

    def test_cmd_open_does_not_send_LUA_REVERT(self, shim):
        script = self._capture_exec_lua(shim, "cmd_open", "/f.py")
        assert script != shim.LUA_REVERT

    def test_cmd_open_does_not_send_LUA_PREVIEW(self, shim):
        script = self._capture_exec_lua(shim, "cmd_open", "/f.py")
        assert script != shim.LUA_PREVIEW


# ── 6. Click CliRunner tests ──────────────────────────────────────────────────


class TestClickCLIRunner:
    """Fast in-process CLI tests using click.testing.CliRunner."""

    def _invoke(self, shim, args: list[str], mock_nvim_fixture=None,
                stdin: str | None = None, sock: str | None = None):
        """Invoke the CLI inside the process, patching pynvim.attach if needed."""
        if sock is None:
            import tempfile
            sock = tempfile.mktemp(suffix=".sock")
            Path(sock).touch()
        runner = CliRunner()
        env = {"NVIM_SOCKET_PATH": sock}
        if mock_nvim_fixture is not None:
            nm = mock_nvim_fixture
        else:
            nm = mock.MagicMock()
            nm.exec_lua.return_value = {"decision": "accept", "content": "x"}
        with mock.patch("pynvim.attach", return_value=nm):
            result = runner.invoke(shim.cli, args, env=env, input=stdin, catch_exceptions=False)
        try:
            os.unlink(sock)
        except FileNotFoundError:
            pass
        return result

    def test_status_exits_0(self, shim):
        result = self._invoke(shim, ["status"])
        assert result.exit_code == 0
        assert "connected:" in result.output

    def test_open_calls_cmd_open(self, shim):
        nm = mock.MagicMock()
        result = self._invoke(shim, ["open", "/tmp/f.py"], mock_nvim_fixture=nm)
        assert result.exit_code == 0
        nm.exec_lua.assert_called_once_with(shim.LUA_OPEN, "/tmp/f.py")

    def test_revert_calls_cmd_revert(self, shim):
        nm = mock.MagicMock()
        result = self._invoke(shim, ["revert", "/tmp/f.py"], mock_nvim_fixture=nm)
        assert result.exit_code == 0
        nm.exec_lua.assert_called_once_with(shim.LUA_REVERT, "/tmp/f.py")

    def test_checktime_exits_0(self, shim):
        result = self._invoke(shim, ["checktime"])
        assert result.exit_code == 0

    def test_close_tab_exits_0(self, shim):
        result = self._invoke(shim, ["close-tab"])
        assert result.exit_code == 0

    def test_set_exits_0(self, shim):
        result = self._invoke(shim, ["set", "pi_active", "true"])
        assert result.exit_code == 0

    def test_unset_exits_0(self, shim):
        result = self._invoke(shim, ["unset", "pi_active"])
        assert result.exit_code == 0

    def test_preview_prints_json(self, shim):
        nm = mock.MagicMock()
        nm.exec_lua.return_value = {"decision": "accept", "content": "final"}
        result = self._invoke(shim, ["preview", "/tmp/f.py"],
                              mock_nvim_fixture=nm, stdin="proposed body")
        assert result.exit_code == 0
        assert json.loads(result.output) == {"decision": "accept", "content": "final"}

    def test_open_missing_file_arg_exits_nonzero(self, shim):
        runner = CliRunner()
        result = runner.invoke(shim.cli, ["open"], env={"NVIM_SOCKET_PATH": "/dev/null"})
        assert result.exit_code != 0
        assert "missing argument" in (result.output + (result.stderr or "")).lower()

    def test_set_missing_args_exits_nonzero(self, shim):
        runner = CliRunner()
        result = runner.invoke(shim.cli, ["set"], env={"NVIM_SOCKET_PATH": "/dev/null"})
        assert result.exit_code != 0

    def test_unset_missing_arg_exits_nonzero(self, shim):
        runner = CliRunner()
        result = runner.invoke(shim.cli, ["unset"], env={"NVIM_SOCKET_PATH": "/dev/null"})
        assert result.exit_code != 0

    def test_unknown_command_exits_nonzero(self, shim):
        runner = CliRunner()
        result = runner.invoke(shim.cli, ["bogus-command"])
        assert result.exit_code != 0

    def test_help_exits_0(self, shim):
        runner = CliRunner()
        result = runner.invoke(shim.cli, ["--help"])
        assert result.exit_code == 0
        assert "usage" in result.output.lower()

    def test_preview_help_exits_0(self, shim):
        runner = CliRunner()
        result = runner.invoke(shim.cli, ["preview", "--help"])
        assert result.exit_code == 0


# ── 7. Subprocess CLI tests (error paths + argument validation) ───────────────


class TestSubprocessCLI:
    def test_help_exits_0(self):
        code, stdout, _ = _run_shim("--help")
        assert code == 0
        assert "usage" in stdout.lower()

    def test_unknown_command_exits_nonzero(self):
        code, _, stderr = _run_shim("bogus-command")
        assert code != 0
        assert "no such command" in stderr.lower()

    def test_open_missing_argument(self):
        code, _, stderr = _run_shim("open", env={"NVIM_SOCKET_PATH": "/dev/null"})
        assert code != 0
        assert "missing argument" in stderr.lower()

    def test_set_missing_arguments(self):
        code, _, stderr = _run_shim("set", env={"NVIM_SOCKET_PATH": "/dev/null"})
        assert code != 0
        assert "missing argument" in stderr.lower()

    def test_no_args_shows_usage(self):
        code, stdout, stderr = _run_shim()
        combined = (stdout + stderr).lower()
        assert "usage" in combined or code == 0

    def test_subcommand_help_exits_0(self):
        code, stdout, _ = _run_shim("preview", "--help")
        assert code == 0
        assert "usage" in stdout.lower()


# ── 8. Integration tests (require NEPH_INTEGRATION_TESTS=1 + nvim in PATH) ───


@pytest.mark.integration
class TestIntegration:
    def test_status_connects_to_headless_nvim(self, headless_nvim, shim, capsys):
        """cmd_status connects to a real headless nvim and prints 'connected:'."""
        old_path = shim.SOCKET_PATH
        shim.SOCKET_PATH = headless_nvim
        try:
            shim.cmd_status()
        finally:
            shim.SOCKET_PATH = old_path
        captured = capsys.readouterr()
        assert "connected:" in captured.out
        assert headless_nvim in captured.out

    def test_checktime_runs_against_real_nvim(self, headless_nvim, shim):
        """cmd_checktime calls nvim_exec_lua on a real Neovim without error."""
        old_path = shim.SOCKET_PATH
        shim.SOCKET_PATH = headless_nvim
        try:
            shim.cmd_checktime()  # should not raise
        finally:
            shim.SOCKET_PATH = old_path

    def test_set_and_unset_global(self, headless_nvim, shim):
        """cmd_set and cmd_unset round-trip a vim.g variable on a real Neovim."""
        old_path = shim.SOCKET_PATH
        shim.SOCKET_PATH = headless_nvim
        try:
            shim.cmd_set("neph_test_var", "42")
            shim.cmd_unset("neph_test_var")
        finally:
            shim.SOCKET_PATH = old_path
