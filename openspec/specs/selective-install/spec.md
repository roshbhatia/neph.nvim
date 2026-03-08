## MODIFIED Requirements

### Requirement: Config agents key controls which agents are active
`neph.Config` SHALL accept an `agents` key — an array of `AgentDef` tables (not strings). When provided, only these agents are registered. When omitted or nil, no agents are registered and a warning is emitted.

#### Scenario: Explicit agent injection
- **WHEN** `require("neph").setup({ agents = { require("neph.agents.claude"), require("neph.agents.pi") }, backend = ... })` is called
- **THEN** only claude and pi are available via `agents.get_all()` (if their executables exist on PATH)

#### Scenario: No agents provided
- **WHEN** `require("neph").setup({ backend = ... })` is called without an `agents` key
- **THEN** `agents.get_all()` returns an empty array
- **AND** a `vim.notify` warning is emitted

#### Scenario: Agent in list but not on PATH
- **WHEN** an agent with `cmd = "nonexistent"` is injected
- **THEN** `agents.get_all()` excludes it
- **AND** a `vim.notify` warning is emitted naming the agent and missing command

### Requirement: tools.install() is selective
`tools.install()` SHALL only install bridge tooling for agents that are registered via injection. The neph CLI bridge is always installed as it is universal.

#### Scenario: Only claude registered
- **WHEN** `agents = { require("neph.agents.claude") }` is configured
- **THEN** neph CLI is symlinked, claude-specific tooling is installed
- **AND** pi extension is NOT symlinked

## REMOVED Requirements

### Requirement: Config agents key controls which agents are active
**Reason**: The old requirement defined `agents` as an optional list of agent name strings with fallback to "all agents on PATH". This is replaced by direct injection of AgentDef tables.
**Migration**: Change `agents = {"claude", "pi"}` to `agents = { require("neph.agents.claude"), require("neph.agents.pi") }`.
