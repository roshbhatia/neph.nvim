## ADDED Requirements

### Requirement: pynvim used as sole Neovim RPC transport
`shim.py` SHALL use `pynvim.attach("socket", path=SOCKET_PATH)` as its only
mechanism for communicating with Neovim. The hand-rolled `NvimRPC` class and
direct `msgpack` usage SHALL be removed entirely.

#### Scenario: get_nvim returns a pynvim.Nvim object
- **WHEN** `NVIM_SOCKET_PATH` points to a valid Neovim socket
- **THEN** `get_nvim()` returns a `pynvim.Nvim` instance without error

#### Scenario: get_nvim raises on missing socket path
- **WHEN** `NVIM_SOCKET_PATH` is empty or unset
- **THEN** `get_nvim()` calls `die()` and exits with code 1 with "not set" in stderr

#### Scenario: get_nvim raises on nonexistent socket file
- **WHEN** `NVIM_SOCKET_PATH` is set to a path that does not exist on disk
- **THEN** `get_nvim()` calls `die()` and exits with code 1 with "not found" in stderr

### Requirement: All commands use pynvim exec_lua
Every `cmd_*` function SHALL call `nvim.exec_lua(script, args)` on the
`pynvim.Nvim` object returned by `get_nvim()`. No raw socket operations
SHALL remain in any command function.

#### Scenario: cmd_open calls exec_lua with LUA_OPEN
- **WHEN** `cmd_open("/some/file.py")` is called with a valid socket
- **THEN** `nvim.exec_lua` is called with `LUA_OPEN` as the script and `["/some/file.py"]` as args

#### Scenario: cmd_set calls exec_lua with name and value
- **WHEN** `cmd_set("pi_active", "true")` is called
- **THEN** `nvim.exec_lua` is called with a script setting `vim.g[...]` and args `["pi_active"]`

#### Scenario: cmd_unset calls exec_lua with nil
- **WHEN** `cmd_unset("pi_reading")` is called
- **THEN** `nvim.exec_lua` is called with a script assigning `nil` and args `["pi_reading"]`

#### Scenario: cmd_checktime calls exec_lua
- **WHEN** `cmd_checktime()` is called
- **THEN** `nvim.exec_lua` is called with a script containing "checktime"

#### Scenario: cmd_close_tab calls exec_lua
- **WHEN** `cmd_close_tab()` is called
- **THEN** `nvim.exec_lua` is called with a script referencing `agent_tab`

### Requirement: pynvim replaces msgpack in dependencies
`pyproject.toml` SHALL list `pynvim>=0.5` as a runtime dependency and SHALL NOT
list `msgpack` as a direct dependency (pynvim manages its own transport).

#### Scenario: pynvim importable in shim environment
- **WHEN** `uv run shim.py status` is executed
- **THEN** pynvim is importable and no ModuleNotFoundError is raised for pynvim

#### Scenario: msgpack not directly imported in shim.py
- **WHEN** `shim.py` source is read
- **THEN** there is no `import msgpack` or `from msgpack` statement at the module level
