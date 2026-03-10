## MODIFIED Requirements

### Requirement: Bus channel registry
`neph.internal.bus` SHALL maintain a table mapping agent names to Neovim RPC channel IDs. Extension agents register by calling the `bus.register` RPC method with their name and channel ID.

#### Scenario: Agent registers successfully
- **WHEN** an extension agent calls `bus.register({name = "pi", channel = 5})`
- **THEN** the bus SHALL store channel ID 5 for agent "pi"
- **AND** the call SHALL return `{ok = true}`

#### Scenario: Agent re-registers after reconnect
- **WHEN** agent "pi" was previously registered with channel 3
- **AND** pi calls `bus.register({name = "pi", channel = 9})`
- **THEN** the bus SHALL update the stored channel to 9

#### Scenario: Unknown agent rejects registration
- **WHEN** an agent calls `bus.register({name = "unknown", channel = 5})`
- **AND** "unknown" is not a registered agent with `type = "extension"`
- **THEN** the call SHALL return `{ok = false, error = "unknown agent"}`

#### Scenario: Gemini companion registers as extension agent
- **WHEN** the gemini companion sidecar calls `bus.register({name = "gemini", channel = 7})`
- **AND** the gemini agent definition has `type = "extension"`
- **THEN** the bus SHALL store channel ID 7 for agent "gemini"

### Requirement: Connection health monitoring
The bus SHALL detect dead channels and clean up stale registrations. The bus SHALL NOT modify `vim.g` state — session.lua owns that responsibility.

#### Scenario: Dead channel detected and cleaned up
- **WHEN** agent "pi" is registered with channel 5
- **AND** channel 5 is no longer valid (agent process died)
- **THEN** the bus SHALL remove pi from the registry

#### Scenario: Health check is non-blocking
- **WHEN** the health check timer fires
- **THEN** it SHALL NOT block the Neovim event loop
- **AND** it SHALL complete in under 1ms for up to 10 registered agents

#### Scenario: Health check failure is logged

- **WHEN** `vim.rpcnotify()` fails for a registered channel
- **THEN** the bus SHALL log the failure at debug level via `log.debug("bus", ...)`
- **AND** the agent SHALL be unregistered from the bus

### Requirement: Bus cleanup on VimLeavePre
The bus SHALL clean up all registered channels on VimLeavePre. The bus SHALL NOT clear `vim.g` state — session.lua owns that responsibility.

#### Scenario: Neovim exit clears all registrations
- **WHEN** VimLeavePre fires
- **THEN** the bus SHALL clear all stored channel IDs
