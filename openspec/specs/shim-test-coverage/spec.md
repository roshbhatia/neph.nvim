## ADDED Requirements

### Requirement: Unit tests mock pynvim.attach, require no socket server
All unit tests for `cmd_*` functions SHALL use `unittest.mock.patch("pynvim.attach")`
and SHALL NOT require a running Neovim instance or a fake msgpack socket server.
`conftest.py` SHALL provide a `mock_nvim` pytest fixture that returns a
`MagicMock` pre-wired as the return value of `pynvim.attach`.

#### Scenario: mock_nvim fixture patches pynvim.attach
- **WHEN** a test uses the `mock_nvim` fixture
- **THEN** calls to `pynvim.attach` inside the test return the mock object
- **AND** `mock_nvim.exec_lua` is a `MagicMock` that can be asserted on

#### Scenario: unit tests run without Neovim installed
- **WHEN** `uv run pytest tests/ -m "not integration"` is run in an environment without nvim
- **THEN** all non-integration tests pass

### Requirement: Every cmd_* function has unit test coverage
Every command function (`cmd_open`, `cmd_preview`, `cmd_revert`, `cmd_close_tab`,
`cmd_checktime`, `cmd_set`, `cmd_unset`, `cmd_status`) SHALL have at least one
unit test verifying the correct `exec_lua` call is made with the correct arguments.

#### Scenario: cmd_open test verifies LUA_OPEN sent with path
- **WHEN** `cmd_open("/tmp/test.py")` is called with `mock_nvim`
- **THEN** `mock_nvim.exec_lua.assert_called_once_with(LUA_OPEN, ["/tmp/test.py"])` passes

#### Scenario: cmd_preview test verifies LUA_PREVIEW sent with path and stdin
- **WHEN** `cmd_preview("/tmp/test.py")` is called with stdin providing "new content"
- **THEN** `mock_nvim.exec_lua` is called with `LUA_PREVIEW` and `["/tmp/test.py", "new content"]`

#### Scenario: cmd_set test verifies lua expression and name sent
- **WHEN** `cmd_set("pi_active", "true")` is called
- **THEN** `mock_nvim.exec_lua` is called with args list containing `"pi_active"`

#### Scenario: cmd_unset test verifies nil assignment
- **WHEN** `cmd_unset("pi_active")` is called
- **THEN** `mock_nvim.exec_lua` is called with a script containing `nil`

### Requirement: Error paths covered — missing socket, connection failure
Tests SHALL cover the error paths where `NVIM_SOCKET_PATH` is missing, the
socket file does not exist, and where `pynvim.attach` raises `OSError`.

#### Scenario: Missing NVIM_SOCKET_PATH exits 1 with diagnostic
- **WHEN** shim is invoked as a subprocess with `NVIM_SOCKET_PATH` unset
- **THEN** exit code is 1 and stderr contains "not set"

#### Scenario: Nonexistent socket path exits 1 with diagnostic
- **WHEN** shim is invoked with `NVIM_SOCKET_PATH=/nonexistent/path.sock`
- **THEN** exit code is 1 and stderr contains "not found"

#### Scenario: pynvim.attach OSError exits 1 with diagnostic
- **WHEN** `pynvim.attach` raises `OSError("connection refused")`
- **THEN** `get_nvim()` calls `die()` and exits 1 with "cannot connect" in stderr

### Requirement: Timeout behaviour tested via mock
Tests SHALL verify that `get_nvim()` calls `socket.setdefaulttimeout` with the
correct value, and that `cmd_preview` calls `get_nvim(timeout=None)`.

#### Scenario: Default timeout applied for non-preview commands
- **WHEN** `cmd_open` is called
- **THEN** `socket.setdefaulttimeout` is called with `30.0` before `pynvim.attach`

#### Scenario: No timeout applied for preview command
- **WHEN** `cmd_preview` is called
- **THEN** `socket.setdefaulttimeout` is called with `None` before `pynvim.attach`

### Requirement: CLI dispatch tested via Click test runner
The Click CLI SHALL be tested using `click.testing.CliRunner` in addition to
subprocess tests, enabling fast in-process CLI coverage without spawning a child.

#### Scenario: CliRunner invokes correct cmd_* for each subcommand
- **WHEN** `CliRunner().invoke(cli, ["status"])` is called with `mock_nvim`
- **THEN** `cmd_status()` is called and the runner exit code is 0

#### Scenario: CliRunner reports missing argument for open with no FILE
- **WHEN** `CliRunner().invoke(cli, ["open"])` is called
- **THEN** exit code is non-zero and output contains "Missing argument"

### Requirement: Lua script content tests verify correct script dispatched
Tests SHALL verify that each command sends the correct pre-loaded Lua script
constant (`LUA_OPEN`, `LUA_REVERT`, `LUA_PREVIEW`) to `nvim.exec_lua`.

#### Scenario: cmd_open sends LUA_OPEN (not LUA_REVERT or LUA_PREVIEW)
- **WHEN** `cmd_open` is called with `mock_nvim`
- **THEN** the first positional arg to `exec_lua` equals `shim.LUA_OPEN`

#### Scenario: cmd_revert sends LUA_REVERT
- **WHEN** `cmd_revert` is called with `mock_nvim`
- **THEN** the first positional arg to `exec_lua` equals `shim.LUA_REVERT`

#### Scenario: cmd_preview sends LUA_PREVIEW
- **WHEN** `cmd_preview` is called with `mock_nvim` and stdin text
- **THEN** the first positional arg to `exec_lua` equals `shim.LUA_PREVIEW`

### Requirement: Integration test fixture with headless Neovim (opt-in)
An optional `@pytest.mark.integration` fixture SHALL start a real headless
`nvim --headless --listen <socket>` subprocess and provide it as a fixture.
These tests SHALL be skipped unless `NEPH_INTEGRATION_TESTS=1` is set.

#### Scenario: Integration tests skipped without env var
- **WHEN** `uv run pytest tests/` is run without `NEPH_INTEGRATION_TESTS=1`
- **THEN** all `@pytest.mark.integration` tests are skipped, not failed

#### Scenario: Integration test connects to real headless nvim
- **WHEN** `NEPH_INTEGRATION_TESTS=1 uv run pytest tests/ -m integration` is run
- **AND** `nvim` is available in PATH
- **THEN** the headless_nvim fixture provides a real socket path
- **AND** `cmd_status()` connects and prints "connected: <path>"
