## MODIFIED Requirements

### Requirement: Contract validation module
neph.nvim SHALL provide `lua/neph/internal/contracts.lua` with validation functions for agent definitions, backend modules, and tool manifests. Validation SHALL run at setup time and throw on invalid input.

#### Scenario: Valid agent definition passes validation
- **WHEN** `contracts.validate_agent({ name = "claude", label = "Claude", icon = " ", cmd = "claude" })` is called
- **THEN** it SHALL return without error

#### Scenario: Agent missing required field throws
- **WHEN** `contracts.validate_agent({ name = "claude", label = "Claude" })` is called (missing `cmd`)
- **THEN** it SHALL throw an error containing "agent 'claude' missing required field 'cmd'"

#### Scenario: Agent with wrong field type throws
- **WHEN** `contracts.validate_agent({ name = "claude", label = "Claude", icon = " ", cmd = 42 })` is called
- **THEN** it SHALL throw an error containing "agent 'claude' field 'cmd' must be string"

#### Scenario: Optional type field is accepted
- **WHEN** `contracts.validate_agent({ name = "pi", label = "Pi", icon = " ", cmd = "pi", type = "extension" })` is called
- **THEN** it SHALL return without error

#### Scenario: Invalid type value throws
- **WHEN** `contracts.validate_agent({ name = "pi", label = "Pi", icon = " ", cmd = "pi", type = "invalid" })` is called
- **THEN** it SHALL throw an error containing "agent 'pi' field 'type' must be one of: extension, hook"

#### Scenario: send_adapter field is rejected
- **WHEN** `contracts.validate_agent({ name = "pi", label = "Pi", icon = " ", cmd = "pi", send_adapter = function() end })` is called
- **THEN** it SHALL throw an error containing "send_adapter is no longer supported" or similar guidance

#### Scenario: integration field is rejected
- **WHEN** `contracts.validate_agent({ name = "pi", label = "Pi", icon = " ", cmd = "pi", integration = { type = "extension" } })` is called
- **THEN** it SHALL throw an error containing "integration is no longer supported" or similar guidance

#### Scenario: Valid backend module passes validation
- **WHEN** `contracts.validate_backend(mod, "snacks")` is called with a module implementing all required methods
- **THEN** it SHALL return without error

#### Scenario: Tool manifest validation
- **WHEN** `contracts.validate_tools(agent)` is called with a valid tools manifest
- **THEN** it SHALL return without error
