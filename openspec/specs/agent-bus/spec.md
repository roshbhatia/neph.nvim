## ADDED Requirements

### Requirement: Bus channel registry
`neph.internal.bus` SHALL maintain a table mapping agent names to Neovim RPC channel IDs. Extension agents register by calling the `bus.register` RPC method with their name and channel ID.

#### Scenario: Agent registers successfully
- **WHEN** an extension agent calls `bus.register({name = "pi", channel = 5})`
- **THEN** the bus SHALL store channel ID 5 for agent "pi"
- **AND** `vim.g.pi_active` SHALL be set to `true`
- **AND** the call SHALL return `{ok = true}`

#### Scenario: Agent re-registers after reconnect
- **WHEN** agent "pi" was previously registered with channel 3
- **AND** pi calls `bus.register({name = "pi", channel = 9})`
- **THEN** the bus SHALL update the stored channel to 9
- **AND** `vim.g.pi_active` SHALL remain `true`

#### Scenario: Unknown agent rejects registration
- **WHEN** an agent calls `bus.register({name = "unknown", channel = 5})`
- **AND** "unknown" is not a registered agent with `type = "extension"`
- **THEN** the call SHALL return `{ok = false, error = "unknown agent"}`

#### Scenario: Gemini companion registers as extension agent
- **WHEN** the gemini companion sidecar calls `bus.register({name = "gemini", channel = 7})`
- **AND** the gemini agent definition has `type = "extension"`
- **THEN** the bus SHALL store channel ID 7 for agent "gemini"
- **AND** `vim.g.gemini_active` SHALL be set to `true`

### Requirement: Push-based prompt delivery
The bus SHALL deliver prompts to extension agents via `vim.rpcnotify(channel_id, "neph:prompt", text, opts)`. Delivery SHALL be instant (no polling, no process spawn).

#### Scenario: Prompt delivered to connected agent
- **WHEN** agent "pi" is registered with channel 5
- **AND** `bus.send_prompt("pi", "fix the bug", {submit = true})` is called
- **THEN** `vim.rpcnotify(5, "neph:prompt", "fix the bug\n")` SHALL be called

#### Scenario: Prompt to unconnected agent returns false
- **WHEN** agent "pi" is not registered (no channel stored)
- **AND** `bus.send_prompt("pi", "hello", {submit = true})` is called
- **THEN** the function SHALL return `false`
- **AND** no notification SHALL be sent

#### Scenario: Submit flag appends newline
- **WHEN** `bus.send_prompt("pi", "hello", {submit = true})` is called
- **THEN** the text delivered via notification SHALL be `"hello\n"`

#### Scenario: No submit flag sends raw text
- **WHEN** `bus.send_prompt("pi", "hello", {})` is called
- **THEN** the text delivered via notification SHALL be `"hello"`

### Requirement: Connection health monitoring
The bus SHALL detect dead channels and clean up stale registrations.

#### Scenario: Dead channel detected and cleaned up
- **WHEN** agent "pi" is registered with channel 5
- **AND** channel 5 is no longer valid (agent process died)
- **THEN** the bus SHALL remove pi from the registry
- **AND** `vim.g.pi_active` SHALL be set to `nil`

#### Scenario: Health check is non-blocking
- **WHEN** the health check timer fires
- **THEN** it SHALL NOT block the Neovim event loop
- **AND** it SHALL complete in under 1ms for up to 10 registered agents

### Requirement: Bus query helpers
The bus SHALL expose `is_connected(name)` to check if an agent has a live channel.

#### Scenario: Check connected agent
- **WHEN** agent "pi" is registered with a valid channel
- **THEN** `bus.is_connected("pi")` SHALL return `true`

#### Scenario: Check unconnected agent
- **WHEN** agent "pi" is not registered
- **THEN** `bus.is_connected("pi")` SHALL return `false`

### Requirement: Bus cleanup on VimLeavePre
The bus SHALL clean up all registered channels and clear vim.g state on VimLeavePre.

#### Scenario: Neovim exit clears all registrations
- **WHEN** VimLeavePre fires
- **THEN** the bus SHALL clear all stored channel IDs
- **AND** `vim.g.{name}_active` SHALL be set to nil for each registered agent
