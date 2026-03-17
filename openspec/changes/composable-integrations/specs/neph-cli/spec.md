## ADDED Requirements

### Requirement: Integration subcommands
The neph CLI SHALL expose `integration` and `deps` subcommands.

#### Scenario: Integration command exists
- **WHEN** the user runs `neph integration --help`
- **THEN** the CLI SHALL list supported integration operations (toggle/status)

#### Scenario: Dependency command exists
- **WHEN** the user runs `neph deps status`
- **THEN** the CLI SHALL report dependency status for the current environment
