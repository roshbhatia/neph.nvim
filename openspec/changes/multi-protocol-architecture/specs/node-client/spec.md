## ADDED Requirements

### Requirement: Node client package structure

The system SHALL provide a TypeScript client library package at `tools/client/` for direct RPC communication with Neovim.

#### Scenario: Package exports NephClient class
- **WHEN** TypeScript code imports `@neph/client`
- **THEN** package SHALL export `NephClient` class
- **AND** class SHALL accept `@neovim/node-client` instance in constructor

#### Scenario: Package provides type definitions
- **WHEN** using client in TypeScript project
- **THEN** package SHALL include `.d.ts` type definition files
- **AND** provide full type safety for all API methods

#### Scenario: Package is independently testable
- **WHEN** running package tests with vitest
- **THEN** tests SHALL execute without requiring full neph.nvim plugin
- **AND** use mocked Neovim instance

### Requirement: File operation methods

The client SHALL provide methods for all file operations that map to Lua API.

#### Scenario: Write file method
- **WHEN** calling `client.writeFile(path, content)`
- **THEN** method SHALL invoke Neovim RPC call to `lua require("neph.api.write").file(...)`
- **AND** return Promise resolving to success status

#### Scenario: Edit file method
- **WHEN** calling `client.editFile(path, oldText, newText)`
- **THEN** method SHALL invoke Neovim RPC call to `lua require("neph.api.edit").file(...)`
- **AND** return Promise resolving to edit result

#### Scenario: Delete file method
- **WHEN** calling `client.deleteFile(path)`
- **THEN** method SHALL invoke Neovim RPC call to `lua require("neph.api.delete").file(...)`
- **AND** return Promise resolving to success status

#### Scenario: Read file method
- **WHEN** calling `client.readFile(path)`
- **THEN** method SHALL invoke Neovim RPC call to `lua require("neph.api.read").file(...)`
- **AND** return Promise resolving to file content string

### Requirement: Connection management

The client SHALL manage Neovim connection lifecycle and handle reconnection.

#### Scenario: Connect to Neovim via socket
- **WHEN** constructing NephClient with socket path
- **THEN** client SHALL establish connection using `@neovim/node-client`
- **AND** verify neph plugin is loaded
- **AND** throw error if plugin not found

#### Scenario: Auto-discover Neovim socket
- **WHEN** constructing NephClient without socket path
- **THEN** client SHALL check `$NVIM` environment variable
- **OR** search standard socket locations (`/tmp/nvim.*/0`)
- **AND** connect to first available socket

#### Scenario: Handle connection loss
- **WHEN** Neovim connection is lost
- **THEN** client SHALL emit `disconnected` event
- **AND** attempt reconnection after 1 second delay
- **AND** retry up to 3 times

### Requirement: Error handling

The client SHALL provide structured error types for all failure modes.

#### Scenario: Throw NephNotFoundError
- **WHEN** neph plugin is not loaded in Neovim
- **THEN** client SHALL throw `NephNotFoundError` with descriptive message
- **AND** suggest installation steps

#### Scenario: Throw FileNotFoundError
- **WHEN** file operation fails because file doesn't exist
- **THEN** client SHALL throw `FileNotFoundError` with path
- **AND** NOT wrap in generic error

#### Scenario: Throw PermissionError
- **WHEN** file operation fails due to permissions
- **THEN** client SHALL throw `PermissionError` with path and operation
- **AND** include system error code

### Requirement: Event subscription

The client SHALL allow subscribing to Neovim events from Lua API.

#### Scenario: Subscribe to file change events
- **WHEN** calling `client.on('file_changed', handler)`
- **THEN** client SHALL register Neovim autocmd for FileChangedShellPost
- **AND** invoke handler when event fires
- **AND** provide file path in event data

#### Scenario: Unsubscribe from events
- **WHEN** calling `client.off('file_changed', handler)`
- **THEN** client SHALL remove handler from event listeners
- **AND** unregister autocmd if no more listeners

#### Scenario: Subscribe to diagnostic events
- **WHEN** calling `client.on('diagnostics_updated', handler)`
- **THEN** client SHALL register handler for vim.diagnostic updates
- **AND** provide diagnostic list in event data
