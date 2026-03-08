## ADDED Requirements

### Requirement: Backend contract conformance tests
Tests SHALL verify that actual backend modules pass contract validation.

#### Scenario: Snacks backend passes validation
- **WHEN** `contracts.validate_backend(require("neph.backends.snacks"), "snacks")` is called
- **THEN** it SHALL return without error

#### Scenario: Wezterm backend passes validation
- **WHEN** `contracts.validate_backend(require("neph.backends.wezterm"), "wezterm")` is called
- **THEN** it SHALL return without error

### Requirement: Tool manifest contract tests
Tests SHALL verify that tool manifest validation catches malformed manifests and accepts valid ones.

#### Scenario: Valid manifest with all fields passes
- **WHEN** `contracts.validate_tools(agent)` is called with an agent whose `tools` has valid symlinks, merges, builds, and files
- **THEN** it SHALL return without error

#### Scenario: Manifest with missing src in symlink throws
- **WHEN** `contracts.validate_tools(agent)` is called with `tools = { symlinks = { { dst = "~/.foo" } } }`
- **THEN** it SHALL throw an error about missing `src` field

#### Scenario: Manifest with invalid files mode throws
- **WHEN** `contracts.validate_tools(agent)` is called with `tools = { files = { { dst = "~/.foo", content = "x", mode = "invalid" } } }`
- **THEN** it SHALL throw an error about invalid mode

#### Scenario: Agent without tools field passes
- **WHEN** `contracts.validate_tools(agent)` is called with an agent that has no `tools` field
- **THEN** it SHALL return without error

### Requirement: Full setup wiring smoke test
A test SHALL verify the complete setup chain wires correctly.

#### Scenario: Setup with real agents and stub backend
- **WHEN** `require("neph").setup({ agents = require("neph.agents.all"), backend = stub_backend })` is called
- **THEN** `agents.get_all()` SHALL return agents whose executables are on PATH
- **AND** no errors SHALL be thrown

### Requirement: Setup negative path tests
Tests SHALL verify setup error handling for invalid inputs.

#### Scenario: Setup without backend throws
- **WHEN** `require("neph").setup({ agents = { agent } })` is called without a backend
- **THEN** it SHALL throw containing "no backend registered"

#### Scenario: Setup with invalid agent throws
- **WHEN** `require("neph").setup({ agents = { { name = "bad" } }, backend = valid_backend })` is called
- **THEN** it SHALL throw about the missing required field

#### Scenario: Setup with invalid backend throws
- **WHEN** `require("neph").setup({ agents = { valid_agent }, backend = {} })` is called
- **THEN** it SHALL throw about missing backend methods
