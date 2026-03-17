## MODIFIED Requirements

### Requirement: neph-cli is agent-independent

The neph-cli build and install SHALL remain universal infrastructure not associated with any single agent. Integration installation SHALL be driven by the neph CLI, not Neovim startup.

#### Scenario: Neovim startup does not install integrations
- **WHEN** Neovim starts with neph.nvim loaded
- **THEN** it SHALL NOT perform integration installs or symlink creation

#### Scenario: CLI creates neph-cli symlink
- **WHEN** the user runs `neph integration toggle neph-cli` (or enables an integration that requires it)
- **THEN** the symlink from `tools/neph-cli/dist/index.js` to `~/.local/bin/neph` SHALL be created if missing

#### Scenario: Integration artifacts installed by CLI
- **WHEN** the user enables an integration via `neph integration toggle <agent>`
- **THEN** the CLI SHALL deploy the required artifacts for that agent (hook configs, plugins, or policy assets)
