## ADDED Requirements

### Requirement: Pi extension as Cupcake harness

The system SHALL provide a Pi coding agent extension that bridges Pi's `tool_call` events to Cupcake's evaluation protocol, replacing the current NephClient-based Pi extension.

#### Scenario: Intercept write tool call
- **WHEN** Pi's agent proposes a `write` tool call with `{ path, content }`
- **THEN** the harness SHALL serialize the event as `{ hook_event_name: "PreToolUse", tool_name: "write", tool_input: { file_path, content }, session_id, cwd }`
- **AND** spawn `cupcake eval --harness pi` with the JSON on stdin
- **AND** read the decision from stdout

#### Scenario: Intercept edit tool call
- **WHEN** Pi's agent proposes an `edit` tool call with `{ path, old_text, new_text }`
- **THEN** the harness SHALL read the current file content
- **AND** reconstruct the full new content by applying the edit
- **AND** serialize as `{ hook_event_name: "PreToolUse", tool_name: "edit", tool_input: { file_path, content: <reconstructed> }, session_id, cwd }`
- **AND** spawn `cupcake eval --harness pi`

#### Scenario: Cupcake returns allow
- **WHEN** Cupcake returns `{ decision: "allow" }`
- **THEN** the harness SHALL call Pi's native tool implementation to execute the write/edit
- **AND** return the native tool's result to the agent

#### Scenario: Cupcake returns deny
- **WHEN** Cupcake returns `{ decision: "deny", reason: "..." }`
- **THEN** the harness SHALL return a ToolResult with `{ content: [{ type: "text", text: "Write rejected: <reason>" }] }`
- **AND** SHALL NOT call the native tool

#### Scenario: Cupcake returns modify with updated content
- **WHEN** Cupcake returns `{ decision: "allow", updated_input: { content: "..." } }`
- **THEN** the harness SHALL call Pi's native write tool with the modified content
- **AND** return the result to the agent with a note that content was modified by review

#### Scenario: Cupcake is not installed
- **WHEN** the harness initializes
- **AND** `cupcake` CLI is not found on PATH
- **THEN** the harness SHALL log a warning to stderr
- **AND** SHALL fall back to calling `neph-cli review` directly (without Cupcake policy evaluation)

### Requirement: Pi harness lifecycle management

The Pi Cupcake harness SHALL handle session lifecycle events and status updates.

#### Scenario: Session start
- **WHEN** Pi emits a `session_start` event
- **THEN** the harness SHALL set agent status in Neovim via `neph-cli set pi_active true`

#### Scenario: Session shutdown
- **WHEN** Pi emits a `session_shutdown` event
- **THEN** the harness SHALL unset agent status via `neph-cli set pi_active ""`

#### Scenario: Non-mutation tools pass through
- **WHEN** Pi proposes a tool call that is not `write` or `edit` (e.g., `read`, `bash`)
- **THEN** the harness SHALL NOT invoke Cupcake
- **AND** SHALL call the native tool implementation directly

### Requirement: Pi harness installation

The Pi Cupcake harness SHALL be installed by `neph setup` to Pi's extension directory.

#### Scenario: Install harness extension
- **WHEN** `neph setup` runs with Pi agent configured
- **THEN** it SHALL build the harness TypeScript to `tools/pi/dist/`
- **AND** symlink to `~/.pi/agent/extensions/nvim/`

#### Scenario: Replace old Pi extension
- **WHEN** `neph setup` runs
- **AND** an old NephClient-based Pi extension exists at `~/.pi/agent/extensions/nvim/`
- **THEN** the old extension SHALL be overwritten by the new Cupcake harness
