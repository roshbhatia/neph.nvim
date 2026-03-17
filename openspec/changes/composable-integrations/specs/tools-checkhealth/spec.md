## MODIFIED Requirements

### Requirement: checkhealth provider for neph

The plugin SHALL provide a checkhealth module at `lua/neph/health.lua` that Neovim auto-discovers for `:checkhealth neph`. It SHALL report on integration status and dependencies using the neph CLI.

#### Scenario: Healthy installation
- **WHEN** the user runs `:checkhealth neph`
- **AND** `neph deps status` reports required dependencies present
- **AND** `neph integration status` reports at least one enabled integration
- **THEN** the output shows OK for dependencies and integration status

#### Scenario: Missing neph CLI
- **WHEN** `:checkhealth neph` runs
- **AND** the `neph` CLI is not available on PATH
- **THEN** checkhealth shows WARN indicating integration checks cannot run

#### Scenario: Missing required dependency
- **WHEN** `neph deps status` reports missing `neovim` or `cupcake`
- **THEN** checkhealth shows ERROR with the missing dependency
