## ADDED Requirements

### Requirement: Pure Lua API modules

The system SHALL provide pure Lua API modules for status and buffer operations, callable from `rpc.lua` dispatch.

#### Scenario: Set vim.g global
- **WHEN** `require("neph.api.status").set({ name = "pi_active", value = "true" })` is called
- **THEN** `vim.g[name]` SHALL be set to the value
- **AND** function SHALL return `{ set = true }`

#### Scenario: Unset vim.g global
- **WHEN** `require("neph.api.status").unset({ name = "pi_active" })` is called
- **THEN** `vim.g[name]` SHALL be set to nil

#### Scenario: Checktime
- **WHEN** `require("neph.api.buffers").checktime()` is called
- **THEN** `vim.cmd("checktime")` SHALL be executed to reload buffers from disk

#### Scenario: Close agent tab
- **WHEN** `require("neph.api.buffers").close_tab()` is called
- **AND** `vim.g.agent_tab` is set
- **THEN** the tab SHALL be closed
- **AND** `vim.g.agent_tab` SHALL be set to nil

### Requirement: Protocol independence

The API modules SHALL NOT depend on any transport mechanism.

#### Scenario: Callable from plenary tests
- **WHEN** API functions are called from busted test suite in nvim --headless
- **THEN** they SHALL execute without requiring Node, Python, or network services

#### Scenario: Serializable types only
- **WHEN** examining API function signatures and return values
- **THEN** they SHALL only use msgpack-safe types (string, number, boolean, table)
