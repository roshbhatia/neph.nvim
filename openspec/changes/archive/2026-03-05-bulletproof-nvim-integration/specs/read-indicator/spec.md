## ADDED Requirements

### Requirement: Agent file reads set a non-intrusive indicator
When the agent calls the `read` tool, `pi.ts` SHALL NOT open any Neovim buffer or switch tabs. Instead it SHALL set `vim.g.pi_reading` to the short file path string and update the pi footer status.

#### Scenario: Read triggers vim.g.pi_reading
- **WHEN** `tool_call` fires with `toolName === "read"` and a valid `path`
- **THEN** `shim set pi_reading <quoted-path>` is called (sets the global)
- **AND** `ctx.ui.setStatus` is called with the short path string

#### Scenario: shim open is never called
- **WHEN** `tool_call` fires with `toolName === "read"`
- **THEN** `shim open` is NOT spawned

#### Scenario: Reading indicator clears after agent turn
- **WHEN** `agent_end` fires
- **THEN** `shim unset pi_reading` is called
- **AND** `ctx.ui.setStatus` clears the reading indicator

### Requirement: vim.g.pi_reading is accessible from Neovim statusline
The `vim.g.pi_reading` global SHALL contain either `nil` (no active read) or a string (the short file path being read), so users can reference it in their statusline configuration.

#### Scenario: Global is nil between reads
- **WHEN** `agent_end` fires
- **THEN** `vim.g.pi_reading` is set to `nil` via `shim unset`

#### Scenario: Global holds short path during read
- **WHEN** a read tool call is in flight
- **THEN** `vim.g.pi_reading` holds a non-empty string (the short path)
