## ADDED Requirements

### Requirement: Gate subcommand exists
The `neph` CLI SHALL support a `gate` subcommand that reads agent hook JSON from stdin, normalizes it to a file path and content, runs the existing review flow, and exits with a code indicating the review decision.

#### Scenario: Gate command is callable
- **WHEN** `neph gate --agent claude` is invoked
- **THEN** it SHALL read JSON from stdin, process the review, and exit

### Requirement: Gate exits 0 on accept
When the review decision is "accept" or "partial", `neph gate` SHALL exit with code 0 (allow the agent's tool call to proceed).

#### Scenario: Review accepted
- **WHEN** `neph gate` receives a write tool input and the review returns `decision: "accept"`
- **THEN** the process SHALL exit with code 0

#### Scenario: Review partial accepted
- **WHEN** `neph gate` receives a write tool input and the review returns `decision: "partial"`
- **THEN** the process SHALL exit with code 0

### Requirement: Gate exits 2 on reject
When the review decision is "reject", `neph gate` SHALL exit with code 2 (block the agent's tool call) and write the rejection reason to stderr.

#### Scenario: Review rejected
- **WHEN** `neph gate` receives a write tool input and the review returns `decision: "reject"`
- **THEN** the process SHALL exit with code 2
- **AND** the rejection reason SHALL be written to stderr

### Requirement: Gate normalizes agent-specific stdin formats
The `--agent` flag SHALL select a parser that normalizes the agent-specific JSON stdin format to `{ filePath, content }` before calling the review flow.

#### Scenario: Claude stdin normalized
- **WHEN** `neph gate --agent claude` receives stdin with `{ tool_input: { file_path: "/a.ts", content: "new" } }`
- **THEN** it SHALL normalize to `filePath="/a.ts"` and `content="new"`

#### Scenario: Claude edit stdin normalized
- **WHEN** `neph gate --agent claude` receives stdin with `{ tool_input: { file_path: "/a.ts", old_string: "old", new_string: "new" } }`
- **THEN** it SHALL read the current file at `/a.ts`, apply the replacement, and use the full resulting content

#### Scenario: Unknown agent rejected
- **WHEN** `neph gate --agent unknown` is invoked
- **THEN** it SHALL exit with code 0 (auto-accept) and write a warning to stderr

### Requirement: Gate manages vim.g state for passive autoattach
`neph gate` SHALL call `neph set <agent>_active true` before starting the review and `neph unset <agent>_active` after the review completes, enabling statusline visibility for agents running outside neovim.

#### Scenario: Agent state set and cleared
- **WHEN** `neph gate --agent claude` processes a review
- **THEN** it SHALL call `status.set` with `{name: "claude_active", value: "true"}` before the review
- **AND** call `status.unset` with `{name: "claude_active"}` after the review completes

### Requirement: Gate auto-accepts when no neovim socket
When `NVIM_SOCKET_PATH` is not set and no socket can be discovered, `neph gate` SHALL auto-accept (exit 0) silently.

#### Scenario: No socket auto-accepts
- **WHEN** `neph gate` runs without `NVIM_SOCKET_PATH` and no discoverable socket
- **THEN** it SHALL exit 0 immediately without attempting a review

### Requirement: Gate auto-accepts in dry-run mode
When `NEPH_DRY_RUN=1` is set, `neph gate` SHALL auto-accept (exit 0).

#### Scenario: Dry-run auto-accepts
- **WHEN** `neph gate` runs with `NEPH_DRY_RUN=1`
- **THEN** it SHALL exit 0 immediately

### Requirement: Gate handles review timeout
When the review does not complete within 300 seconds, `neph gate` SHALL exit with code 2 (fail closed).

#### Scenario: Timeout blocks
- **WHEN** `neph gate` starts a review and it does not complete within 300 seconds
- **THEN** it SHALL exit with code 2
- **AND** write "Review timed out" to stderr
