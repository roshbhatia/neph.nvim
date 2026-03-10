## ADDED Requirements

### Requirement: Interactive UI CLI commands
The `neph` CLI SHALL provide commands to trigger interactive Neovim UI prompts from the command line.

#### Scenario: neph ui-select
- **WHEN** user runs `neph ui-select <title> <option1> <option2> ...`
- **THEN** Neovim SHALL display `vim.ui.select`
- **AND** the CLI SHALL wait for the user's choice
- **AND** print the selected option to stdout upon completion

#### Scenario: neph ui-input
- **WHEN** user runs `neph ui-input <title> [default]`
- **THEN** Neovim SHALL display `vim.ui.input`
- **AND** the CLI SHALL wait for the user's input
- **AND** print the input text to stdout upon completion

#### Scenario: neph ui-notify
- **WHEN** user runs `neph ui-notify <message> [level]`
- **THEN** Neovim SHALL display a notification via `vim.notify`
- **AND** the CLI SHALL exit 0 immediately
