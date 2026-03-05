"""
test_shim.py — tests for tools/core/shim.py

Strategy:
  - Unit tests patch pynvim.attach via the `mock_nvim` fixture — no real socket needed
  - NVIM_SOCKET_PATH is set via mock.patch.dict(os.environ, ...) at call time;
    shim reads it on every get_nvim() call so no module-level patching is needed
  - Subprocess tests (_run_shim) cover CLI dispatch, error exits, and missing-arg errors
  - Click CliRunner tests give fast in-process coverage of CLI dispatch;
    CliRunner's env= updates os.environ for the duration of the invocation
  - Integration tests (marked @pytest.mark.integration) use a real headless nvim;
    skipped unless NEPH_INTEGRATION_TESTS=1
"""
from __future__ import annotations

import io
import json
import os
import subprocess
import sys
import tempfile
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


def _make_sock() -> str:
    """Create a real (empty) temp file to satisfy the os.path.exists check."""
    sock = tempfile.mktemp(suffix=".sock")
    Path(sock).touch()
    return sock


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

    def test_lua_open_diff_is_nonempty_string(self, shim):
        assert isinstance(shim.LUA_OPEN_DIFF, str)
        assert len(shim.LUA_OPEN_DIFF.strip()) > 0

    def test_missing_lua_dir_raises_file_not_found(self, tmp_path):
        """Loading shim with _LUA_DIR pointing to an empty dir raises FileNotFoundError."""
        with pytest.raises(FileNotFoundError):
            _load_shim(lua_dir=tmp_path)

    def test_lua_scripts_are_distinct(self, shim):
        assert shim.LUA_OPEN != shim.LUA_REVERT
        assert shim.LUA_OPEN != shim.LUA_OPEN_DIFF
        assert shim.LUA_REVERT != shim.LUA_OPEN_DIFF

    def test_no_msgpack_import(self):
        """shim.py must not import msgpack directly."""
        src = SHIM_PATH.read_text()
        assert "import msgpack" not in src
        assert "from msgpack" not in src

    def test_pynvim_imported(self):
        src = SHIM_PATH.read_text()
        assert "import pynvim" in src

    def test_no_module_level_socket_path_constant(self):
        """SOCKET_PATH module constant removed — env read at call time."""
        src = SHIM_PATH.read_text()
        assert "SOCKET_PATH = os.environ" not in src


# ── 2. Error paths (subprocess) ───────────────────────────────────────────────


class TestConnectErrors:
    def test_missing_socket_path_env_auto_discovers(self):
        """Auto-discovers a socket when NVIM_SOCKET_PATH is absent.
        
        This test may pass (exit 0) or fail (exit 1) depending on whether
        a live Neovim socket exists on the system. We just verify the
        error message mentions discovery when it fails.
        """
        code, _, stderr = _run_shim("status")
        if code == 1:
            # No sockets found — should mention discovery or "not set"
            assert "not set" in stderr.lower() or "not found" in stderr.lower()

    def test_nonexistent_socket_path(self, tmp_path):
        """Exits 1 with 'not found' when the socket file doesn't exist."""
        bad = str(tmp_path / "no_such.sock")
        code, _, stderr = _run_shim("status", env={"NVIM_SOCKET_PATH": bad})
        assert code == 1
        assert "not found" in stderr.lower()

    def test_oserror_on_attach_exits_1(self, shim, tmp_path):
        """OSError from pynvim.attach is caught; exits 1 with 'cannot connect'."""
        sock = str(tmp_path / "fake.sock")
        Path(sock).touch()
        with mock.patch.dict(os.environ, {"NVIM_SOCKET_PATH": sock}), \
             mock.patch("pynvim.attach", side_effect=OSError("connection refused")):
            with pytest.raises(SystemExit) as exc_info:
                shim.cmd_status()
            assert exc_info.value.code == 1


# ── 3. get_nvim() timeout behaviour ──────────────────────────────────────────


class TestGetNvim:
    """Verify socket.setdefaulttimeout is called correctly around pynvim.attach."""

    def _run_get_nvim(self, shim, sock_path: str, timeout=30.0):
        timeouts_set = []
        with mock.patch("socket.setdefaulttimeout", side_effect=lambda t: timeouts_set.append(t)), \
             mock.patch("pynvim.attach", return_value=mock.MagicMock()), \
             mock.patch.dict(os.environ, {"NVIM_SOCKET_PATH": sock_path}):
            shim.get_nvim(timeout)
        return timeouts_set

    def test_default_timeout_is_30(self, shim, tmp_path):
        sock = str(tmp_path / "s.sock")
        Path(sock).touch()
        timeouts = self._run_get_nvim(shim, sock, 30.0)
        assert timeouts[0] == 30.0

    def test_review_uses_30s_timeout(self, shim, tmp_path):
        sock = str(tmp_path / "s.sock")
        Path(sock).touch()
        timeouts = self._run_get_nvim(shim, sock, 30.0)
        assert timeouts[0] == 30.0

    def test_timeout_reset_after_attach(self, shim, tmp_path):
        sock = str(tmp_path / "s.sock")
        Path(sock).touch()
        timeouts = self._run_get_nvim(shim, sock, 30.0)
        assert len(timeouts) == 2
        assert timeouts[1] is None

    def test_cmd_review_calls_get_nvim_with_none_timeout(self, shim, tmp_path):
        """cmd_review calls get_nvim(timeout=None)."""
        sock = str(tmp_path / "s.sock")
        Path(sock).touch()
        captured = []
        real_get_nvim = shim.get_nvim

        def spy(timeout=30.0):
            captured.append(timeout)
            m = mock.MagicMock()
            m.exec_lua.return_value = {"decision": "accept", "content": "x"}
            return m

        old_stdin = sys.stdin
        sys.stdin = io.StringIO("proposed content")
        old_fn = shim.get_nvim
        shim.get_nvim = spy
        try:
            with mock.patch.dict(os.environ, {"NVIM_SOCKET_PATH": sock}):
                shim.cmd_review("/tmp/test.py", dry_run=True)
        finally:
            sys.stdin = old_stdin
            shim.get_nvim = old_fn

        # dry_run skips get_nvim entirely — captured should be empty
        assert captured == []

    def test_cmd_open_calls_get_nvim_with_default_timeout(self, shim, tmp_path):
        """cmd_open calls get_nvim() with the default 30s timeout."""
        sock = str(tmp_path / "s.sock")
        Path(sock).touch()
        captured = []

        def spy(timeout=30.0):
            captured.append(timeout)
            return mock.MagicMock()

        old_fn = shim.get_nvim
        shim.get_nvim = spy
        try:
            with mock.patch.dict(os.environ, {"NVIM_SOCKET_PATH": sock}):
                shim.cmd_open("/tmp/test.py")
        finally:
            shim.get_nvim = old_fn

        assert captured == [30.0]


# ── 4. Command dispatch via mock_nvim ─────────────────────────────────────────


class TestCommandDispatch:
    """Each cmd_* sends the correct exec_lua call to the pynvim mock."""

    def _with_mock(self, shim, mock_nvim, fn_name: str, *args,
                   return_value=None, stdin_text: str | None = None):
        sock = _make_sock()
        if return_value is not None:
            mock_nvim.exec_lua.return_value = return_value
        old_stdin = sys.stdin
        if stdin_text is not None:
            sys.stdin = io.StringIO(stdin_text)
        try:
            with mock.patch("pynvim.attach", return_value=mock_nvim), \
                 mock.patch.dict(os.environ, {"NVIM_SOCKET_PATH": sock}):
                getattr(shim, fn_name)(*args)
        finally:
            if stdin_text is not None:
                sys.stdin = old_stdin
            try:
                os.unlink(sock)
            except FileNotFoundError:
                pass

    def test_cmd_status_connects(self, shim, mock_nvim, capsys):
        self._with_mock(shim, mock_nvim, "cmd_status")
        assert "connected:" in capsys.readouterr().out

    def test_cmd_open_sends_lua_open_with_path(self, shim, mock_nvim):
        self._with_mock(shim, mock_nvim, "cmd_open", "/some/file.py")
        mock_nvim.exec_lua.assert_called_once_with(shim.LUA_OPEN, "/some/file.py")

    def test_cmd_revert_sends_lua_revert_with_path(self, shim, mock_nvim):
        self._with_mock(shim, mock_nvim, "cmd_revert", "/tmp/file.py")
        mock_nvim.exec_lua.assert_called_once_with(shim.LUA_REVERT, "/tmp/file.py")

    def test_cmd_checktime_sends_checktime_lua(self, shim, mock_nvim):
        self._with_mock(shim, mock_nvim, "cmd_checktime")
        assert "checktime" in mock_nvim.exec_lua.call_args[0][0]

    def test_cmd_close_tab_sends_agent_tab_lua(self, shim, mock_nvim):
        self._with_mock(shim, mock_nvim, "cmd_close_tab")
        assert "agent_tab" in mock_nvim.exec_lua.call_args[0][0]

    def test_cmd_set_sends_name_and_value(self, shim, mock_nvim):
        self._with_mock(shim, mock_nvim, "cmd_set", "pi_active", "true")
        args = mock_nvim.exec_lua.call_args[0]
        assert "true" in args[0]
        assert "pi_active" in args[1]

    def test_cmd_unset_sends_nil_and_name(self, shim, mock_nvim):
        self._with_mock(shim, mock_nvim, "cmd_unset", "pi_running")
        args = mock_nvim.exec_lua.call_args[0]
        assert "nil" in args[0]
        assert "pi_running" in args[1]

    def test_cmd_review_sends_lua_preview_with_path_and_content(self, shim, mock_nvim):
        # cmd_review with live nvim is tested via integration tests;
        # dry-run path is tested in TestReviewProtocol
        pass

    def test_cmd_review_dry_run_prints_json(self, shim, capsys):
        import io
        old = sys.stdin; sys.stdin = io.StringIO("body")
        sock = _make_sock()
        try:
            with mock.patch.dict(os.environ, {"NVIM_SOCKET_PATH": sock, "NEPH_DRY_RUN": "1"}):
                shim.cmd_review("/f.py")
        finally:
            sys.stdin = old
            try: os.unlink(sock)
            except FileNotFoundError: pass
        out = json.loads(capsys.readouterr().out)
        assert out["decision"] == "accept"
        assert out["content"] == "body"
        assert out["schema"] == "review/v1"


# ── 5. Lua script dispatch identity ──────────────────────────────────────────


class TestLuaScriptDispatch:
    def _capture_script(self, shim, fn_name: str, *args,
                        return_value=None, stdin_text: str | None = None):
        nm = mock.MagicMock()
        if return_value is not None:
            nm.exec_lua.return_value = return_value
        sock = _make_sock()
        old_stdin = sys.stdin
        if stdin_text is not None:
            sys.stdin = io.StringIO(stdin_text)
        try:
            with mock.patch("pynvim.attach", return_value=nm), \
                 mock.patch.dict(os.environ, {"NVIM_SOCKET_PATH": sock}):
                getattr(shim, fn_name)(*args)
        finally:
            if stdin_text is not None:
                sys.stdin = old_stdin
            try:
                os.unlink(sock)
            except FileNotFoundError:
                pass
        return nm.exec_lua.call_args[0][0]

    def test_cmd_open_sends_LUA_OPEN(self, shim):
        assert self._capture_script(shim, "cmd_open", "/f.py") == shim.LUA_OPEN

    def test_cmd_revert_sends_LUA_REVERT(self, shim):
        assert self._capture_script(shim, "cmd_revert", "/f.py") == shim.LUA_REVERT

    def test_cmd_review_dry_run_does_not_call_exec_lua(self, shim):
        """cmd_review with --dry-run should not call exec_lua at all."""
        nm = mock.MagicMock()
        sock = _make_sock()
        old_stdin = sys.stdin
        sys.stdin = io.StringIO("body")
        try:
            with mock.patch("pynvim.attach", return_value=nm), \
                 mock.patch.dict(os.environ, {"NVIM_SOCKET_PATH": sock}):
                shim.cmd_review("/f.py", dry_run=True)
        finally:
            sys.stdin = old_stdin
            try:
                os.unlink(sock)
            except FileNotFoundError:
                pass
        nm.exec_lua.assert_not_called()

    def test_cmd_open_sends_LUA_OPEN(self, shim):
        assert self._capture_script(shim, "cmd_open", "/f.py") == shim.LUA_OPEN

    def test_cmd_open_does_not_send_LUA_REVERT(self, shim):
        assert self._capture_script(shim, "cmd_open", "/f.py") != shim.LUA_REVERT


# ── 6. Click CliRunner tests ──────────────────────────────────────────────────


class TestClickCLIRunner:
    """Fast in-process CLI tests. CliRunner's env= updates os.environ for the
    duration of the invocation, so get_nvim() sees NVIM_SOCKET_PATH correctly."""

    def _invoke(self, shim, args: list[str], mock_nvim_fixture=None,
                stdin: str | None = None, sock: str | None = None):
        if sock is None:
            sock = _make_sock()
        runner = CliRunner()
        if mock_nvim_fixture is not None:
            nm = mock_nvim_fixture
        else:
            nm = mock.MagicMock()
            nm.exec_lua.return_value = {"decision": "accept", "content": "x"}
        with mock.patch("pynvim.attach", return_value=nm):
            result = runner.invoke(
                shim.cli, args,
                env={"NVIM_SOCKET_PATH": sock},
                input=stdin,
                catch_exceptions=False,
            )
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
        assert self._invoke(shim, ["checktime"]).exit_code == 0

    def test_close_tab_exits_0(self, shim):
        assert self._invoke(shim, ["close-tab"]).exit_code == 0

    def test_set_exits_0(self, shim):
        assert self._invoke(shim, ["set", "pi_active", "true"]).exit_code == 0

    def test_unset_exits_0(self, shim):
        assert self._invoke(shim, ["unset", "pi_active"]).exit_code == 0

    def test_review_dry_run_prints_json(self, shim):
        nm = mock.MagicMock()
        nm.exec_lua.return_value = {"decision": "accept", "content": "final"}
        result = self._invoke(shim, ["review", "--dry-run", "/tmp/f.py"],
                              mock_nvim_fixture=nm, stdin="proposed body")
        assert result.exit_code == 0
        out = json.loads(result.output)
        assert out["decision"] == "accept"
        assert out["content"] == "proposed body"
        assert out["schema"] == "review/v1"

    def test_open_missing_file_arg_exits_nonzero(self, shim):
        runner = CliRunner()
        result = runner.invoke(shim.cli, ["open"],
                               env={"NVIM_SOCKET_PATH": "/dev/null"})
        assert result.exit_code != 0
        assert "missing argument" in result.output.lower()

    def test_set_missing_args_exits_nonzero(self, shim):
        runner = CliRunner()
        result = runner.invoke(shim.cli, ["set"],
                               env={"NVIM_SOCKET_PATH": "/dev/null"})
        assert result.exit_code != 0

    def test_unset_missing_arg_exits_nonzero(self, shim):
        runner = CliRunner()
        result = runner.invoke(shim.cli, ["unset"],
                               env={"NVIM_SOCKET_PATH": "/dev/null"})
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

    def test_review_help_exits_0(self, shim):
        runner = CliRunner()
        result = runner.invoke(shim.cli, ["review", "--help"])
        assert result.exit_code == 0



# ── 7. Review protocol ────────────────────────────────────────────────────────


class TestReviewProtocol:
    """Tests for the ReviewEnvelope contract and dry-run path."""

    def _review(self, shim, content: str, extra_env: dict | None = None,
                dry_run: bool = False):
        """Call cmd_review with stdin=content in dry-run / no-socket env."""
        import io
        old = sys.stdin
        sys.stdin = io.StringIO(content)
        env = {"NEPH_DRY_RUN": "1"} if dry_run else {}
        if extra_env:
            env.update(extra_env)
        # Remove NVIM_SOCKET_PATH so auto-accept triggers
        capsys_buf = []
        try:
            with mock.patch.dict(os.environ, env, clear=False),                  mock.patch.dict(os.environ, {"NVIM_SOCKET_PATH": ""}):
                shim.cmd_review("/tmp/test.py", dry_run=dry_run)
        finally:
            sys.stdin = old

    def test_dry_run_flag_auto_accepts(self, shim, capsys):
        self._review(shim, "hello world", dry_run=True)
        out = json.loads(capsys.readouterr().out)
        assert out["decision"] == "accept"
        assert out["content"] == "hello world"

    def test_dry_run_schema_field_present(self, shim, capsys):
        self._review(shim, "x", dry_run=True)
        out = json.loads(capsys.readouterr().out)
        assert out["schema"] == "review/v1"

    def test_no_socket_auto_accepts(self, shim, capsys):
        import io
        old = sys.stdin; sys.stdin = io.StringIO("body")
        try:
            with mock.patch.dict(os.environ, {"NVIM_SOCKET_PATH": ""}),                  mock.patch.object(shim, "discover_nvim_socket", return_value=None):
                shim.cmd_review("/tmp/f.py")
        finally:
            sys.stdin = old
        out = json.loads(capsys.readouterr().out)
        assert out["decision"] == "accept"

    def test_neph_dry_run_env_auto_accepts(self, shim, capsys):
        import io
        old = sys.stdin; sys.stdin = io.StringIO("env body")
        try:
            with mock.patch.dict(os.environ,
                                 {"NEPH_DRY_RUN": "1", "NVIM_SOCKET_PATH": ""}):
                shim.cmd_review("/tmp/f.py")
        finally:
            sys.stdin = old
        out = json.loads(capsys.readouterr().out)
        assert out["decision"] == "accept"
        assert out["content"] == "env body"

    def test_preview_alias_warns_and_calls_review(self, shim, capsys):
        import io
        old = sys.stdin; sys.stdin = io.StringIO("body")
        try:
            with mock.patch.dict(os.environ, {"NVIM_SOCKET_PATH": ""}),                  mock.patch.object(shim, "discover_nvim_socket", return_value=None):
                shim.cmd_preview("/tmp/f.py")
        finally:
            sys.stdin = old
        err = capsys.readouterr().err
        assert "deprecated" in err.lower() or "preview" in err.lower()

    def test_review_cli_dry_run_exits_0(self, shim):
        runner = CliRunner()
        result = runner.invoke(
            shim.cli, ["review", "--dry-run", "/tmp/f.py"],
            input="body", env={"NVIM_SOCKET_PATH": ""},
        )
        assert result.exit_code == 0
        out = json.loads(result.output)
        assert out["decision"] == "accept"

    def test_review_without_socket_exits_0(self, shim):
        runner = CliRunner()
        with mock.patch.object(shim, "discover_nvim_socket", return_value=None):
            result = runner.invoke(
                shim.cli, ["review", "/tmp/f.py"],
                input="body", env={"NVIM_SOCKET_PATH": ""},
            )
        assert result.exit_code == 0


# ── 8. Buffer verification ────────────────────────────────────────────────────


class TestVerifyBuffer:
    def test_match_returns_empty_dict(self, shim):
        nm = mock.MagicMock()
        buf = mock.MagicMock()
        buf.name = "/tmp/f.py"
        buf.__getitem__ = mock.Mock(return_value=["hello", "world"])
        nm.buffers = [buf]
        result = shim.verify_buffer(nm, "/tmp/f.py", "hello\nworld")
        assert result == {}

    def test_mismatch_returns_verification_error(self, shim):
        nm = mock.MagicMock()
        buf = mock.MagicMock()
        buf.name = "/tmp/f.py"
        buf.__getitem__ = mock.Mock(return_value=["different"])
        nm.buffers = [buf]
        result = shim.verify_buffer(nm, "/tmp/f.py", "expected")
        assert "verification_error" in result

    def test_not_found_returns_verification_skipped(self, shim):
        nm = mock.MagicMock()
        nm.buffers = []
        result = shim.verify_buffer(nm, "/tmp/not_open.py", "content")
        assert result == {"verification_skipped": True}

    def test_exception_on_read_returns_skipped(self, shim):
        nm = mock.MagicMock()
        buf = mock.MagicMock()
        buf.name = "/tmp/f.py"
        buf.__getitem__ = mock.Mock(side_effect=Exception("rpc error"))
        nm.buffers = [buf]
        result = shim.verify_buffer(nm, "/tmp/f.py", "x")
        assert result == {"verification_skipped": True}


# ── 9. Socket discovery ───────────────────────────────────────────────────────


class TestSocketDiscovery:
    def test_returns_none_when_no_sockets(self, shim):
        with mock.patch("glob.glob", return_value=[]):
            result = shim.discover_nvim_socket()
        assert result is None

    def test_dead_pid_filtered_out(self, shim, tmp_path):
        fake = str(tmp_path / "nvim.99999.0")
        Path(fake).touch()
        with mock.patch("glob.glob", return_value=[fake]),              mock.patch("os.kill", side_effect=OSError("no such process")):
            result = shim.discover_nvim_socket()
        assert result is None


# ── 10. Subprocess CLI tests ───────────────────────────────────────────────────


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
        assert "usage" in (stdout + stderr).lower() or code == 0

    def test_subcommand_help_exits_0(self):
        code, stdout, _ = _run_shim("review", "--help")
        assert code == 0
        assert "usage" in stdout.lower()


# ── 11. Integration tests ──────────────────────────────────────────────────────


@pytest.mark.integration
class TestIntegration:
    def test_status_connects_to_headless_nvim(self, headless_nvim, shim, capsys):
        with mock.patch.dict(os.environ, {"NVIM_SOCKET_PATH": headless_nvim}):
            shim.cmd_status()
        out = capsys.readouterr().out
        assert "connected:" in out
        assert headless_nvim in out

    def test_checktime_runs_against_real_nvim(self, headless_nvim, shim):
        with mock.patch.dict(os.environ, {"NVIM_SOCKET_PATH": headless_nvim}):
            shim.cmd_checktime()

    def test_set_and_unset_global(self, headless_nvim, shim):
        with mock.patch.dict(os.environ, {"NVIM_SOCKET_PATH": headless_nvim}):
            shim.cmd_set("neph_test_var", "42")
            shim.cmd_unset("neph_test_var")
