## 1. Dependencies

- [ ] 1.1 Replace `msgpack>=1.0` with `pynvim>=0.5` in `pyproject.toml` dependencies
- [ ] 1.2 Replace `msgpack>=1.0` with `pynvim>=0.5` in `pyproject.toml` dev group
- [ ] 1.3 Run `uv sync` and verify pynvim is installed; verify msgpack is no longer a direct dep
- [ ] 1.4 Verify `import pynvim` works in the uv venv

## 2. shim.py — remove NvimRPC, add get_nvim()

- [ ] 2.1 Remove `import msgpack` and the entire `NvimRPC` class from `shim.py`
- [ ] 2.2 Add `import pynvim` and `import socket` (already present but confirm)
- [ ] 2.3 Rename `connect(timeout)` → `get_nvim(timeout: float | None = 30.0) -> pynvim.Nvim`
- [ ] 2.4 Implement `get_nvim`: validate `SOCKET_PATH`, call `socket.setdefaulttimeout(timeout)`,
         call `pynvim.attach("socket", path=SOCKET_PATH)`, reset timeout to `None`, return nvim
- [ ] 2.5 Wrap `pynvim.attach` in try/except `OSError` → call `die("cannot connect to nvim: …")`
- [ ] 2.6 Remove `close()` calls from all `cmd_*` functions (pynvim manages its own lifecycle)

## 3. shim.py — update cmd_* functions

- [ ] 3.1 Update `cmd_status`: call `get_nvim()`, print connected message, no explicit close needed
- [ ] 3.2 Update `cmd_open`: call `get_nvim()`, call `nvim.exec_lua(LUA_OPEN, [file_path])`
- [ ] 3.3 Update `cmd_preview`: call `get_nvim(timeout=None)`, call `nvim.exec_lua(LUA_PREVIEW, [file_path, proposed_content])`, print JSON result
- [ ] 3.4 Update `cmd_revert`: call `get_nvim()`, call `nvim.exec_lua(LUA_REVERT, [file_path])`
- [ ] 3.5 Update `cmd_close_tab`: call `get_nvim()`, call `nvim.exec_lua(close_tab_lua)`
- [ ] 3.6 Update `cmd_checktime`: call `get_nvim()`, call `nvim.exec_lua("vim.cmd('checktime')")`
- [ ] 3.7 Update `cmd_set`: call `get_nvim()`, call `nvim.exec_lua(set_lua, [name])`
- [ ] 3.8 Update `cmd_unset`: call `get_nvim()`, call `nvim.exec_lua(unset_lua, [name])`
- [ ] 3.9 Verify `flake8 core/shim.py` passes with zero errors

## 4. conftest.py — replace FakeNvimServer with mock_nvim fixture

- [ ] 4.1 Remove `FakeNvimServer` class and all msgpack socket server code from `conftest.py`
- [ ] 4.2 Add `mock_nvim` fixture: patches `pynvim.attach` to return a `MagicMock`; yields the mock
- [ ] 4.3 Add `nvim_socket_path` fixture: sets `shim.SOCKET_PATH` to a fake path for subprocess tests
- [ ] 4.4 Add `headless_nvim` fixture (scope=session): starts `nvim --headless --listen <tmp_sock>`,
         skips if `NEPH_INTEGRATION_TESTS` not set or `nvim` not in PATH; yields socket path; kills process on teardown
- [ ] 4.5 Register `integration` pytest mark in `pyproject.toml` `[tool.pytest.ini_options]`

## 5. test_shim.py — rewrite test suite

- [ ] 5.1 Remove all `TestNvimRPC` tests (class no longer exists)
- [ ] 5.2 Rewrite `TestConnectErrors` using subprocess `_run_shim` — verify exits 1 + stderr for missing socket path, nonexistent path, and pynvim OSError (mock pynvim.attach to raise)
- [ ] 5.3 Add `TestGetNvim` class: unit-test `get_nvim()` timeout behaviour using `mock.patch("socket.setdefaulttimeout")` + `mock.patch("pynvim.attach")` — verify 30.0 default, None for preview, reset after attach
- [ ] 5.4 Rewrite `TestCommandDispatch` using `mock_nvim` fixture — one test per `cmd_*` verifying correct `exec_lua` call (method, script constant, args list)
- [ ] 5.5 Add `TestLuaScriptDispatch` — verify `cmd_open` sends `LUA_OPEN`, `cmd_revert` sends `LUA_REVERT`, `cmd_preview` sends `LUA_PREVIEW`
- [ ] 5.6 Rewrite `TestCmdPreview` — mock stdin + `mock_nvim`; verify `exec_lua` args; verify JSON printed to stdout
- [ ] 5.7 Add `TestClickCLIRunner` using `click.testing.CliRunner` — test each subcommand dispatch, missing-argument errors, and `--help` output in-process
- [ ] 5.8 Rewrite `TestLuaScriptLoading` — verify `LUA_OPEN`, `LUA_REVERT`, `LUA_PREVIEW` are non-empty strings; verify missing lua dir raises `FileNotFoundError`
- [ ] 5.9 Add `TestIntegration` class marked `@pytest.mark.integration` — `cmd_status` connects to headless_nvim and prints "connected"

## 6. Verify & clean up

- [ ] 6.1 Run `uv run pytest tests/ -m "not integration" -v` — all tests pass
- [ ] 6.2 Run `uv run pytest tests/ -m integration -v` (requires `NEPH_INTEGRATION_TESTS=1` and nvim in PATH) — verify headless fixture works
- [ ] 6.3 Run `flake8 core/shim.py` — zero errors
- [ ] 6.4 Run full `task lint` and `task tools:test` — all green
- [ ] 6.5 Commit: `feat: migrate shim.py to pynvim, rewrite test suite`
