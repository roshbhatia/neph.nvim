## MODIFIED Requirements

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
