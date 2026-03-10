## ADDED Requirements

### Requirement: OpenCode SDK persistent plugin
The system SHALL provide a persistent bridge plugin for OpenCode (`tools/opencode/opencode.ts`) that uses the OpenCode SDK to intercept agent events and tool calls.

#### Scenario: OpenCode session start
- **WHEN** OpenCode starts a session
- **THEN** the bridge plugin SHALL connect to Neovim via `NephClient`
- **AND** register as the `opencode` agent
- **AND** set `vim.g.opencode_active` to `true`

#### Scenario: Turn status mapping
- **WHEN** OpenCode triggers a `session.busy` event
- **THEN** the bridge SHALL call `setStatus("opencode_running", "true")` in Neovim
- **AND** when `session.idle` is triggered, it SHALL call `unsetStatus("opencode_running")`

#### Scenario: Shell tool interception
- **WHEN** OpenCode attempts to execute the `shell` tool
- **THEN** the bridge SHALL intercept the call in `tool.execute.before`
- **AND** trigger a `uiSelect` prompt in Neovim for user approval
- **AND** throw an error if the user denies, preventing execution

#### Scenario: Native prompt receiving
- **WHEN** Neovim sends a `neph:prompt` notification to the bridge
- **THEN** the bridge SHALL forward the prompt to OpenCode using `pi.sendUserMessage` (or equivalent SDK call)
