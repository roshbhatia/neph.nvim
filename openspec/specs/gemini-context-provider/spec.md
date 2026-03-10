## ADDED Requirements

### Requirement: Context update notifications
The companion SHALL send `ide/contextUpdate` notifications to Gemini CLI with current workspace state from Neovim.

#### Scenario: Context sent on buffer focus
- **WHEN** the user switches to a different buffer in Neovim (BufEnter)
- **THEN** neph SHALL collect the workspace context and push it to the companion sidecar
- **AND** the companion SHALL send an `ide/contextUpdate` notification to Gemini CLI

#### Scenario: Context sent on cursor movement (debounced)
- **WHEN** the user moves their cursor (CursorHold, debounced ~50ms)
- **THEN** neph SHALL send updated cursor position to the companion
- **AND** the companion SHALL send an `ide/contextUpdate` notification

#### Scenario: Context sent on text selection
- **WHEN** the user makes a visual selection in Neovim
- **AND** CursorHold fires after the selection
- **THEN** the context SHALL include the `selectedText` field with the selection content

### Requirement: Workspace state payload
The context update payload SHALL conform to the IdeContext schema from the companion spec.

#### Scenario: Open files list
- **WHEN** a context update is sent
- **THEN** `workspaceState.openFiles` SHALL contain entries for loaded buffers with file paths
- **AND** each entry SHALL include `path` (absolute), `timestamp` (last focused), and `isActive` (currently focused)

#### Scenario: Cursor position included
- **WHEN** the active buffer has a cursor position
- **THEN** the active file's entry SHALL include `cursor` with `line` and `character` (1-based)

#### Scenario: Selected text included
- **WHEN** the user has an active visual selection
- **THEN** the active file's entry SHALL include `selectedText` with the selected content
- **AND** `selectedText` SHALL be truncated to 16KB if larger

#### Scenario: Maximum 10 files reported
- **WHEN** more than 10 buffers are loaded
- **THEN** `openFiles` SHALL contain at most 10 entries, sorted by most recently focused

### Requirement: Context push via RPC notification
Neovim SHALL push context updates to the companion sidecar via `vim.rpcnotify` on the registered bus channel.

#### Scenario: Context delivered via bus channel
- **WHEN** a context update is triggered
- **AND** the gemini agent is registered on the bus
- **THEN** neph SHALL call `vim.rpcnotify(channel, "neph:context", context_data)`

#### Scenario: No context sent when companion disconnected
- **WHEN** a context update is triggered
- **AND** the gemini agent is NOT registered on the bus
- **THEN** neph SHALL NOT attempt to send context
- **AND** SHALL NOT raise an error

### Requirement: Companion debounce timer stop is crash-safe

The companion module SHALL handle invalid timer handles gracefully when stopping debounce timers.

#### Scenario: Invalid timer handle caught silently

- **WHEN** the debounce timer stop is called with an invalid or already-closed timer handle
- **THEN** the error SHALL be caught silently (pcall or equivalent)
- **AND** no uncaught exception SHALL propagate to the caller
