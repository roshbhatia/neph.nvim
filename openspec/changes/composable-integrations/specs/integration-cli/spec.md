## ADDED Requirements

### Requirement: Integration toggle command
The CLI SHALL provide `neph integration toggle [name]` to enable or disable integrations.

#### Scenario: Toggle without name
- **WHEN** the user runs `neph integration toggle` without a name
- **THEN** the CLI SHALL prompt interactively to select a supported integration
- **AND** toggle the selected integration

#### Scenario: Toggle with name
- **WHEN** the user runs `neph integration toggle gemini`
- **THEN** the CLI SHALL enable the integration if disabled, or disable it if enabled

### Requirement: Integration status with config inspection
The CLI SHALL provide `neph integration status [name]` with optional config inspection.

#### Scenario: Status without name
- **WHEN** the user runs `neph integration status`
- **THEN** the CLI SHALL report validation status for all supported integrations

#### Scenario: Status with config display
- **WHEN** the user runs `neph integration status gemini --show-config`
- **THEN** the CLI SHALL print the resolved config file with neph-managed lines highlighted
- **AND** SHALL fall back to plain text when color output is unavailable

### Requirement: Dependency status command
The CLI SHALL provide `neph deps status` to validate required and optional dependencies.

#### Scenario: Required dependencies
- **WHEN** `neph deps status` runs
- **THEN** it SHALL report `neovim` and `cupcake` as required dependencies

#### Scenario: Optional dependencies
- **WHEN** `neph deps status` runs
- **THEN** it SHALL report `bat` as optional
- **AND** SHALL report CLI agents as optional but require at least one supported agent to be installed

### Requirement: Preserve non-neph configuration
Integration enable/disable operations SHALL preserve non-neph configuration entries.

#### Scenario: Existing hooks in config file
- **WHEN** the CLI modifies an integration config file
- **THEN** it SHALL retain pre-existing non-neph entries unchanged
