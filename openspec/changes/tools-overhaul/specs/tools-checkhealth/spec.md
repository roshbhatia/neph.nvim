## ADDED Requirements

### Requirement: checkhealth provider for neph

The plugin SHALL provide a checkhealth module at `lua/neph/health.lua` that Neovim auto-discovers for `:checkhealth neph`. It SHALL report on tool installation state, dependencies, and symlink validity.

#### Scenario: Healthy installation

- **WHEN** the user runs `:checkhealth neph`
- **AND** neph-cli is built and symlinked correctly, and claude hooks are merged
- **THEN** the output shows OK for neph-cli symlink, OK for neph-cli build, OK for claude hooks
- **AND** agents not on PATH are shown as INFO (not errors)

#### Scenario: Missing npm

- **WHEN** npm is not on PATH
- **AND** agents with builds are registered
- **THEN** checkhealth shows WARN for npm not found
- **AND** explains that npm is needed for building neph-cli and agent extensions

#### Scenario: Broken symlink

- **WHEN** a symlink exists but points to a nonexistent target
- **THEN** checkhealth shows ERROR for that symlink with the broken target path

#### Scenario: Missing build artifact

- **WHEN** `tools/neph-cli/dist/index.js` does not exist
- **THEN** checkhealth shows WARN for neph-cli with suggestion to run `:NephTools install all`

#### Scenario: Agent not on PATH

- **WHEN** pi is registered but `pi` executable is not on PATH
- **THEN** checkhealth shows INFO: "pi: not on PATH (tools not installed)"
- **AND** this is NOT shown as an error
