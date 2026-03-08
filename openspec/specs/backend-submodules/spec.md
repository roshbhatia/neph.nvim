## ADDED Requirements

### Requirement: Backend submodules
neph.nvim SHALL provide backend implementations as standalone Lua modules under `lua/neph/backends/`. Each module SHALL implement the full backend interface: `setup`, `open`, `focus`, `hide`, `is_visible`, `kill`, `cleanup_all`.

#### Scenario: Require snacks backend
- **WHEN** `require("neph.backends.snacks")` is called
- **THEN** it SHALL return a module table with all required backend methods
- **AND** the module SHALL pass `contracts.validate_backend()`

#### Scenario: Require wezterm backend
- **WHEN** `require("neph.backends.wezterm")` is called
- **THEN** it SHALL return a module table with all required backend methods
- **AND** the module SHALL pass `contracts.validate_backend()`

#### Scenario: Snacks backend uses Snacks.terminal
- **WHEN** `snacks_backend.open(termname, agent_config, cwd)` is called
- **THEN** it SHALL open a terminal via `Snacks.terminal.open()` with a right-split layout
- **AND** it SHALL pass `NVIM_SOCKET_PATH` and user-configured env vars to the terminal

#### Scenario: Backends are relocatable
- **WHEN** backends are moved from `lua/neph/internal/backends/` to `lua/neph/backends/`
- **THEN** all existing backend behavior SHALL be preserved
- **AND** `session.lua` SHALL use the injected backend reference, not a hardcoded require path
