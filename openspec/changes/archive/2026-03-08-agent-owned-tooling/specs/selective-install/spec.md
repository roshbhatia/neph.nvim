## MODIFIED Requirements

### Requirement: Config agents key controls which agents are active
`neph.Config` SHALL accept an `agents` key — an array of `AgentDef` tables. When provided, only these agents are registered. Tool installation is driven by the `tools` manifests on injected agents — no separate selection mechanism needed.

#### Scenario: Explicit agent injection with tools
- **WHEN** `require("neph").setup({ agents = { require("neph.agents.claude"), require("neph.agents.pi") }, backend = ... })` is called
- **THEN** only claude and pi tools are installed (based on their `tools` manifests)
- **AND** no other agent's tools are installed

#### Scenario: Agent without tools field
- **WHEN** an agent with no `tools` field is injected (e.g., goose, codex)
- **THEN** no tool installation occurs for that agent
- **AND** the agent still functions for terminal management

#### Scenario: No agents provided
- **WHEN** `require("neph").setup({ backend = ... })` is called without an `agents` key
- **THEN** no agent-specific tools are installed
- **AND** only the universal neph-cli is installed

### Requirement: tools.install() is selective
`tools.install()` SHALL only install bridge tooling for agents that are registered via injection, by reading their `tools` manifests. The neph CLI bridge is always installed as it is universal.

#### Scenario: Only claude registered
- **WHEN** `agents = { require("neph.agents.claude") }` is configured
- **THEN** neph CLI is symlinked, claude's hooks are merged (from claude's `tools.merges` manifest)
- **AND** pi extension is NOT symlinked (pi not injected)

## REMOVED Requirements

### Requirement: Config agents key controls which agents are active
**Reason**: The old string-based `agents` key was replaced by AgentDef injection in composable-di-architecture. This change further removes any separate "enabled" check in tools — selection is now purely by injection.
**Migration**: Already handled by composable-di-architecture change.
