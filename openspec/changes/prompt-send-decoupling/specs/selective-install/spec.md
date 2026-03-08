## ADDED Requirements

### Requirement: Config agents key controls which agents are active
`neph.Config` SHALL accept an optional `agents` key — a list of agent name strings. When provided, only agents in this list are registered. When omitted, all agents whose executable is found on PATH are registered (preserving current default behavior).

#### Scenario: Explicit agent list
- **GIVEN** config `{ agents = {"claude", "pi"} }`
- **WHEN** `agents.get_all()` is called
- **THEN** only claude and pi are returned (if their executables exist on PATH)

#### Scenario: Default behavior (no agents key)
- **GIVEN** config `{}` (no agents key)
- **WHEN** `agents.get_all()` is called
- **THEN** all agents whose executables are on PATH are returned (same as current behavior)

#### Scenario: Agent in list but not on PATH
- **GIVEN** config `{ agents = {"claude", "nonexistent"} }`
- **WHEN** `agents.get_all()` is called
- **THEN** only claude is returned (nonexistent is silently skipped)

### Requirement: tools.install() is selective
`tools.install()` SHALL only install bridge tooling (symlinks, config merges, extension copies) for agents that are active according to `config.agents`. The neph CLI bridge is always installed as it is universal.

#### Scenario: Only claude enabled
- **GIVEN** config `{ agents = {"claude"} }`
- **WHEN** `tools.install()` runs
- **THEN** neph CLI is symlinked, claude settings.json is merged
- **AND** pi extension is NOT symlinked, copilot hooks are NOT installed

#### Scenario: All agents enabled (default)
- **GIVEN** config `{}` (default)
- **WHEN** `tools.install()` runs
- **THEN** all available agent tooling is installed (same as current behavior)
