## ADDED Requirements

### Requirement: pytest suite exists for shim.py
`tools/core/tests/test_shim.py` and `tools/core/tests/conftest.py` SHALL exist and be runnable via `uv run pytest tests/` from `tools/core/`.

#### Scenario: Tests discoverable
- **WHEN** `uv run pytest tests/ --collect-only` is run from `tools/core/`
- **THEN** at least 10 test items are collected with no errors

### Requirement: Fake NvimRPC server fixture
`conftest.py` SHALL provide a `nvim_server` pytest fixture that starts a real Unix socket server responding to msgpack-rpc `nvim_exec_lua` requests, exposes the last received request for assertion, and is torn down after each test.

#### Scenario: Fixture provides socket path
- **WHEN** a test function accepts `nvim_server` as a parameter
- **THEN** `nvim_server.socket_path` is a string path to an existing Unix socket
- **THEN** the server is ready to accept connections

#### Scenario: Fixture records received calls
- **WHEN** `NvimRPC(nvim_server.socket_path).exec_lua("return 1")` is called
- **THEN** `nvim_server.last_call` contains the Lua code string `"return 1"`

### Requirement: NvimRPC connect and request
Tests SHALL cover the `NvimRPC` class connect and request lifecycle.

#### Scenario: Successful connection
- **WHEN** `NvimRPC(path)` is constructed with a valid socket path
- **THEN** no exception is raised

#### Scenario: Request sends correct msgpack-rpc frame
- **WHEN** `nvim.request("nvim_exec_lua", "return 42", [])` is called
- **THEN** the server receives a msgpack array `[0, <msgid>, "nvim_exec_lua", ["return 42", []]]`

#### Scenario: Response is returned
- **WHEN** the server replies with `[1, <msgid>, nil, "result_value"]`
- **THEN** `nvim.request(...)` returns `"result_value"`

#### Scenario: Error response raises RuntimeError
- **WHEN** the server replies with `[1, <msgid>, "some error", nil]`
- **THEN** `nvim.request(...)` raises `RuntimeError` containing `"some error"`

#### Scenario: Notification frames are skipped
- **WHEN** the server sends `[2, "some_event", []]` before the response
- **THEN** `nvim.request(...)` ignores the notification and returns the actual response

### Requirement: connect() error handling
`connect()` SHALL fail fast with a message written to stderr and exit code 1 when the socket is not available.

#### Scenario: Missing NVIM_SOCKET_PATH
- **WHEN** `NVIM_SOCKET_PATH` env var is not set and `connect()` is called
- **THEN** the process exits with code 1 and stderr contains "not set"

#### Scenario: Socket path does not exist
- **WHEN** `NVIM_SOCKET_PATH` points to a non-existent path and `connect()` is called
- **THEN** the process exits with code 1 and stderr contains "not found"

### Requirement: Command dispatch tests
Each CLI command SHALL have at least one test verifying the correct Lua code is sent to the fake server.

#### Scenario: cmd_open sends LUA_OPEN
- **WHEN** `cmd_open("/some/file.py")` is called against the fake server
- **THEN** the server receives a request containing `"nvim_exec_lua"` with the file path as an arg

#### Scenario: cmd_checktime sends checktime Lua
- **WHEN** `cmd_checktime()` is called against the fake server
- **THEN** the server receives a request containing `"checktime"`

#### Scenario: cmd_set sends set Lua
- **WHEN** `cmd_set("pi_active", "true")` is called against the fake server
- **THEN** the server receives a request containing `"pi_active"` and `"true"`

#### Scenario: cmd_unset sends unset Lua
- **WHEN** `cmd_unset("pi_running")` is called against the fake server
- **THEN** the server receives a request containing `"pi_running"` and `"nil"`

#### Scenario: cmd_preview sends LUA_PREVIEW with stdin content
- **WHEN** `cmd_preview("/file.py")` is called with stdin set to `"new content"`
- **THEN** the server receives a request with args `["/file.py", "new content"]`
- **THEN** the JSON result from the server is printed to stdout

### Requirement: main() dispatch
`main()` SHALL correctly route CLI args to command functions.

#### Scenario: Unknown command exits with error
- **WHEN** `main()` is called with `sys.argv = ["shim", "bogus"]`
- **THEN** the process exits with code 1 and stderr contains `"unknown command"`

#### Scenario: No args prints usage
- **WHEN** `main()` is called with `sys.argv = ["shim"]`
- **THEN** the process exits with code 1 and stderr contains `"usage"`
