## ADDED Requirements

### Requirement: Native UI RPC API
The system SHALL provide RPC endpoints to trigger native Neovim UI components and return the user's response asynchronously.

#### Scenario: UI Select
- **WHEN** `ui.select` is called via RPC with a list of options
- **THEN** Neovim SHALL present `vim.ui.select` to the user
- **AND** the selected option SHALL be sent back via an RPC notification

#### Scenario: UI Input
- **WHEN** `ui.input` is called via RPC with a prompt string
- **THEN** Neovim SHALL present `vim.ui.input` to the user
- **AND** the user's input SHALL be sent back via an RPC notification

#### Scenario: UI Notify
- **WHEN** `ui.notify` is called via RPC with a message and level
- **THEN** Neovim SHALL call `vim.notify`
- **AND** return immediately
