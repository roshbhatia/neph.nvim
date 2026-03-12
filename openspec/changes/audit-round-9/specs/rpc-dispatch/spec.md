## MODIFIED Requirements

### Requirement: RPC notify calls protected against invalid channels

All `vim.rpcnotify()` calls SHALL be wrapped in `pcall` to prevent crashes from invalid or stale channel IDs.

#### Scenario: Agent disconnects, stale channel_id used

- **GIVEN** an agent connected with channel_id 5
- **WHEN** the agent disconnects
- **AND** a UI response tries to notify channel_id 5
- **THEN** the pcall catches the error
- **AND** Neovim does not crash
