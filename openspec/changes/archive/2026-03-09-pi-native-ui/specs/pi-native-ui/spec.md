## ADDED Requirements

### Requirement: Pi UI Context Wrapping
The `pi` extension SHALL intercept the `ctx.ui` object provided by the `pi-mono` SDK during `session_start` and replace its methods with calls to the Neovim RPC bridge.

#### Scenario: Agent calls ctx.ui.select
- **WHEN** a `pi` extension calls `ctx.ui.select(title, options)`
- **THEN** the wrapper SHALL call `NephClient.uiSelect`
- **AND** return the resolved promise when the user makes a choice in Neovim

#### Scenario: Agent calls ctx.ui.input
- **WHEN** a `pi` extension calls `ctx.ui.input(title, defaultText)`
- **THEN** the wrapper SHALL call `NephClient.uiInput`
- **AND** return the resolved promise with the text the user types in Neovim

#### Scenario: Agent calls ctx.ui.confirm
- **WHEN** a `pi` extension calls `ctx.ui.confirm(title, message)`
- **THEN** the wrapper SHALL call `NephClient.uiSelect` with "Yes" and "No" options
- **AND** return a boolean representing the user's choice

#### Scenario: Agent calls ctx.ui.notify
- **WHEN** a `pi` extension calls `ctx.ui.notify(message, type)`
- **THEN** the wrapper SHALL call `NephClient.uiNotify`
- **AND** resolve immediately
