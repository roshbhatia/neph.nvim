## ADDED Requirements

### Requirement: Integration field on agent definitions
Each agent definition in `agents.lua` SHALL support an optional `integration` field with `type` and `capabilities` properties.

#### Scenario: Hook agent with review gating has integration metadata
- **WHEN** the claude agent definition is inspected
- **THEN** it SHALL have `integration = { type = "hook", capabilities = { "review", "status", "checktime" } }`

#### Scenario: Post-write-only hook agent has limited capabilities
- **WHEN** the cursor agent definition is inspected
- **THEN** it SHALL have `integration = { type = "hook", capabilities = { "status", "checktime" } }` (no "review" — cursor hooks are informational only)

#### Scenario: Extension agent has integration metadata
- **WHEN** the pi agent definition is inspected
- **THEN** it SHALL have `integration = { type = "extension", capabilities = { "review", "status", "checktime", "read_indicator", "lifecycle" } }`

#### Scenario: Terminal-only agent has no integration
- **WHEN** the goose agent definition is inspected
- **THEN** it SHALL have `integration = nil` (or the field omitted)

### Requirement: Session.lua uses integration type for state management
`session.lua` SHALL check the agent's `integration.type` to decide whether to manage `vim.g.<agent>_active` state.

#### Scenario: Terminal-only agent state managed by session.lua
- **WHEN** `session.open("goose")` is called and goose has `integration = nil`
- **THEN** session.lua SHALL set `vim.g.goose_active = true`

#### Scenario: Hook agent state NOT managed by session.lua
- **WHEN** `session.open("claude")` is called and claude has `integration.type = "hook"`
- **THEN** session.lua SHALL NOT set `vim.g.claude_active` (neph gate manages this)

#### Scenario: Extension agent state NOT managed by session.lua
- **WHEN** `session.open("pi")` is called and pi has `integration.type = "extension"`
- **THEN** session.lua SHALL NOT set `vim.g.pi_active` (pi.ts manages this)

### Requirement: Terminal-only agent state cleared on kill
When a terminal-only agent is killed, `session.lua` SHALL clear `vim.g.<agent>_active`.

#### Scenario: Terminal agent state cleared
- **WHEN** `session.kill_session("goose")` is called
- **THEN** `vim.g.goose_active` SHALL be `nil`

### Requirement: All terminal-only states cleared on VimLeavePre
When Neovim exits, `session.lua` SHALL clear `vim.g.<agent>_active` for all tracked terminal-only agents.

#### Scenario: States cleared on exit
- **WHEN** the `VimLeavePre` autocmd fires
- **THEN** all tracked `vim.g.<agent>_active` globals SHALL be set to `nil`

### Requirement: Integration metadata is optional and backward-compatible
The `integration` field SHALL be optional. Agents without it SHALL behave as terminal-only (same as `integration = nil`). User-provided agent definitions via `config.agents` SHALL work with or without the field.

#### Scenario: User agent without integration field
- **WHEN** a user adds `{ name = "myagent", cmd = "myagent", args = {} }` via config
- **THEN** it SHALL be treated as terminal-only with session.lua managing state
