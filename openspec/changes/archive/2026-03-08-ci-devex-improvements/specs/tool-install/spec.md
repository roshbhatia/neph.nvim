## MODIFIED Requirements

### Requirement: Settings merge behavior
The `tools.install()` function SHALL use additive merging for JSON settings files (claude, gemini) instead of key replacement. The merge SHALL preserve all existing configuration while ensuring neph's hooks are present.

#### Scenario: First install creates settings
- **WHEN** the destination settings file does not exist
- **AND** `tools.install()` runs
- **THEN** the full source settings content SHALL be written to the destination

#### Scenario: Subsequent installs preserve existing config
- **WHEN** the destination settings file exists with user configuration
- **AND** `tools.install()` runs
- **THEN** existing configuration SHALL be preserved and neph's hooks SHALL be additively merged
