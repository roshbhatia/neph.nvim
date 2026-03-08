## ADDED Requirements

### Requirement: Contract validation module
neph.nvim SHALL provide `lua/neph/internal/contracts.lua` with validation functions for agent definitions and backend modules. Validation SHALL run at setup time and throw on invalid input.

#### Scenario: Valid agent definition passes validation
- **WHEN** `contracts.validate_agent({ name = "claude", label = "Claude", icon = " ", cmd = "claude" })` is called
- **THEN** it SHALL return without error

#### Scenario: Agent missing required field throws
- **WHEN** `contracts.validate_agent({ name = "claude", label = "Claude" })` is called (missing `cmd`)
- **THEN** it SHALL throw an error containing "agent 'claude' missing required field 'cmd'"

#### Scenario: Agent with wrong field type throws
- **WHEN** `contracts.validate_agent({ name = "claude", label = "Claude", icon = " ", cmd = 42 })` is called
- **THEN** it SHALL throw an error containing "agent 'claude' field 'cmd' must be string"

#### Scenario: Valid backend module passes validation
- **WHEN** `contracts.validate_backend(mod, "snacks")` is called with a module implementing all required methods
- **THEN** it SHALL return without error

#### Scenario: Backend missing required method throws
- **WHEN** `contracts.validate_backend({ setup = fn, open = fn }, "snacks")` is called (missing `focus`, `hide`, `is_visible`, `kill`, `cleanup_all`)
- **THEN** it SHALL throw an error containing "backend 'snacks' missing required method 'focus'"

#### Scenario: Optional agent fields are accepted
- **WHEN** `contracts.validate_agent({ name = "pi", label = "Pi", icon = " ", cmd = "pi", args = {"--continue"}, send_adapter = function() end, integration = { type = "extension", capabilities = {"review"} } })` is called
- **THEN** it SHALL return without error

### Requirement: Setup wires injected dependencies
`require("neph").setup()` SHALL accept `agents` (array of AgentDef tables) and `backend` (a backend module table) and wire them into the internal modules.

#### Scenario: Agents and backend are injected
- **WHEN** `require("neph").setup({ agents = { agent1, agent2 }, backend = backend_mod })` is called
- **THEN** `neph.internal.agents` SHALL serve `agent1` and `agent2` via `get_all()` and `get_by_name()`
- **AND** `neph.internal.session` SHALL use `backend_mod` for all terminal operations

#### Scenario: Missing backend throws at setup
- **WHEN** `require("neph").setup({ agents = { agent1 } })` is called without a `backend` key
- **THEN** setup SHALL throw an error containing "no backend registered"

#### Scenario: Empty agents warns
- **WHEN** `require("neph").setup({ agents = {}, backend = backend_mod })` is called
- **THEN** setup SHALL emit a `vim.notify` warning that no agents are registered
- **AND** setup SHALL continue without error

#### Scenario: Each agent is validated
- **WHEN** `require("neph").setup({ agents = { valid_agent, invalid_agent }, backend = backend_mod })` is called
- **THEN** setup SHALL throw when it reaches the invalid agent definition

#### Scenario: Backend is validated
- **WHEN** `require("neph").setup({ agents = { agent1 }, backend = incomplete_mod })` is called
- **THEN** setup SHALL throw when backend validation fails
