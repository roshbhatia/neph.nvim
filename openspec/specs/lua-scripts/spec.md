## ADDED Requirements

### Requirement: Lua scripts stored as external files
`shim.py` SHALL load its Lua scripts from `tools/core/lua/open.lua`, `tools/core/lua/revert.lua`, and `tools/core/lua/preview.lua` at module import time. The scripts SHALL NOT be embedded as inline string literals inside `shim.py`.

#### Scenario: Lua files present — load succeeds
- **WHEN** `shim.py` is imported and all three `lua/*.lua` files exist alongside it
- **THEN** `LUA_OPEN`, `LUA_REVERT`, and `LUA_PREVIEW` are populated with the file contents and all commands work normally

#### Scenario: Lua file missing — clear error
- **WHEN** a `lua/*.lua` file is absent at import time
- **THEN** `shim.py` raises a `FileNotFoundError` with a message indicating the expected path

### Requirement: Lua script contents unchanged after extraction
The content of each extracted Lua script SHALL be functionally identical to the previously inlined string. No logic, variable names, or RPC calls SHALL change as part of this extraction.

#### Scenario: Behavior parity
- **WHEN** any `cmd_*` function is called after extraction
- **THEN** the RPC calls made to Neovim are identical to those made by the previous inline version

### Requirement: Lua scripts are independently testable
Each extracted Lua script SHALL have at least one pytest test that exercises it via `FakeNvimServer` and asserts the expected `nvim_exec_lua` calls.

#### Scenario: open.lua tested in isolation
- **WHEN** `cmd_open(path)` is called against a `FakeNvimServer`
- **THEN** the server receives an `nvim_exec_lua` request whose first param matches the contents of `open.lua`

#### Scenario: revert.lua tested in isolation
- **WHEN** `cmd_revert(path)` is called against a `FakeNvimServer`
- **THEN** the server receives an `nvim_exec_lua` request whose first param matches the contents of `revert.lua`

#### Scenario: preview.lua tested in isolation
- **WHEN** `cmd_preview(path, content)` is called against a `FakeNvimServer`
- **THEN** the server receives an `nvim_exec_lua` request whose first param matches the contents of `preview.lua`
