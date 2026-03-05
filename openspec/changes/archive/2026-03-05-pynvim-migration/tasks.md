## 1. Dependencies

- [x] 1.1 Replace `msgpack>=1.0` with `pynvim>=0.5` in `pyproject.toml` dependencies
- [x] 1.2 Replace `msgpack>=1.0` with `pynvim>=0.5` in `pyproject.toml` dev group
- [x] 1.3 Run `uv sync` and verify pynvim is installed; verify msgpack is no longer a direct dep
- [x] 1.4 Verify `import pynvim` works in the uv venv

## 2. shim.py — remove NvimRPC, add get_nvim()

- [x] 2.1 Remove `import msgpack` and the entire `NvimRPC` class from `shim.py`
- [x] 2.2 Add `import pynvim` and `import socket` (already present but confirm)
- [x] 2.3 Rename `connect(timeout)` → `get_nvim(timeout: float | None = 30.0) -> pynvim.Nvim`
- [x] 2.4 Implement `get_nvim`: validate `SOCKET_PATH`, call `socket.setdefaulttimeout(timeout)`,
         call `pynvim.attach("socket", path=SOCKET_PATH)`, reset timeout to `None`, return nvim
- [x] 2.5 Wrap `pynvim.attach` in try/except `OSError` → call `die("cannot connect to nvim: …")`
- [x] 2.6 Remove `close()` calls from all `cmd_*` functions (pynvim manages its own lifecycle)

## 3. shim.py — update cmd_* functions

- [x] 3.1 Update `cmd_status`: call `get_nvim()`, print connected message, no explicit close needed
- [x] 3.2 Update `cmd_open`: call `get_nvim()`, call `nvim.exec_lua(LUA_OPEN, [file_path])`
- [x] 3.3 Update `cmd_preview`: call `get_nvim(timeout=None)`, call `nvim.exec_lua(LUA_PREVIEW, [file_path, proposed_content])`, print JSON result
- [x] 3.4 Update `cmd_revert`: call `get_nvim()`, call `nvim.exec_lua(LUA_REVERT, [file_path])`
- [x] 3.5 Update `cmd_close_tab`: call `get_nvim()`, call `nvim.exec_lua(close_tab_lua)`
- [x] 3.6 Update `cmd_checktime`: call `get_nvim()`, call `nvim.exec_lua("vim.cmd('checktime')")`
- [x] 3.7 Update `cmd_set`: call `get_nvim()`, call `nvim.exec_lua(set_lua, [name])`
- [x] 3.8 Update `cmd_unset`: call `get_nvim()`, call `nvim.exec_lua(unset_lua, [name])`
- [x] 3.9 Verify `flake8 core/shim.py` passes with zero errors

## 4. conftest.py — replace FakeNvimServer with mock_nvim fixture

- [x] 4.1 Remove `FakeNvimServer` class and all msgpack socket server code from `conftest.py`
- [x] 4.2 Add `mock_nvim` fixture: patches `pynvim.attach` to return a `MagicMock`; yields the mock
- [x] 4.3 Add `nvim_socket_path` fixture: sets `shim.SOCKET_PATH` to a fake path for subprocess tests
- [x] 4.4 Add `headless_nvim` fixture (scope=session): starts `nvim --headless --listen <tmp_sock>`,
         skips if `NEPH_INTEGRATION_TESTS` not set or `nvim` not in PATH; yields socket path; kills process on teardown
- [x] 4.5 Register `integration` pytest mark in `pyproject.toml` `[tool.pytest.ini_options]`

## 5. test_shim.py — rewrite test suite

- [x] 5.1 Remove all `TestNvimRPC` tests (class no longer exists)
- [x] 5.2 Rewrite `TestConnectErrors` using subprocess `_run_shim` — verify exits 1 + stderr for missing socket path, nonexistent path, and pynvim OSError (mock pynvim.attach to raise)
- [x] 5.3 Add `TestGetNvim` class: unit-test `get_nvim()` timeout behaviour using `mock.patch("socket.setdefaulttimeout")` + `mock.patch("pynvim.attach")` — verify 30.0 default, None for preview, reset after attach
- [x] 5.4 Rewrite `TestCommandDispatch` using `mock_nvim` fixture — one test per `cmd_*` verifying correct `exec_lua` call (method, script constant, args list)
- [x] 5.5 Add `TestLuaScriptDispatch` — verify `cmd_open` sends `LUA_OPEN`, `cmd_revert` sends `LUA_REVERT`, `cmd_preview` sends `LUA_PREVIEW`
- [x] 5.6 Rewrite `TestCmdPreview` — mock stdin + `mock_nvim`; verify `exec_lua` args; verify JSON printed to stdout
- [x] 5.7 Add `TestClickCLIRunner` using `click.testing.CliRunner` — test each subcommand dispatch, missing-argument errors, and `--help` output in-process
- [x] 5.8 Rewrite `TestLuaScriptLoading` — verify `LUA_OPEN`, `LUA_REVERT`, `LUA_PREVIEW` are non-empty strings; verify missing lua dir raises `FileNotFoundError`
- [x] 5.9 Add `TestIntegration` class marked `@pytest.mark.integration` — `cmd_status` connects to headless_nvim and prints "connected"

## 6. Verify & clean up

- [x] 6.1 Run `uv run pytest tests/ -m "not integration" -v` — all tests pass
- [x] 6.2 Run `uv run pytest tests/ -m integration -v` (requires `NEPH_INTEGRATION_TESTS=1` and nvim in PATH) — verify headless fixture works
- [x] 6.3 Run `flake8 core/shim.py` — zero errors
- [x] 6.4 Run full `task lint` and `task tools:test` — all green
- [x] 6.5 Commit: `feat: migrate shim.py to pynvim, rewrite test suite`
