## ADDED Requirements

### Requirement: Editor-agnostic review command

The system SHALL provide a `neph-cli review` command that reads `{ path, content }` on stdin, opens an interactive vimdiff review in Neovim, blocks until the user decides, and returns `{ decision, content, reason? }` on stdout. The command SHALL have no agent awareness — it speaks one protocol.

#### Scenario: Accept all hunks
- **WHEN** `neph-cli review` is invoked with `{ "path": "/foo.lua", "content": "new" }` on stdin
- **AND** the user accepts all hunks in the vimdiff UI
- **THEN** stdout SHALL contain `{ "decision": "accept", "content": "new" }`
- **AND** exit code SHALL be 0

#### Scenario: Reject all hunks
- **WHEN** the user rejects all hunks
- **THEN** stdout SHALL contain `{ "decision": "reject", "content": "", "reason": "..." }`
- **AND** exit code SHALL be 2

#### Scenario: Partial accept
- **WHEN** the user accepts some hunks and rejects others
- **THEN** stdout SHALL contain `{ "decision": "partial", "content": "<merged>" }`
- **AND** exit code SHALL be 0

#### Scenario: Review timeout
- **WHEN** the review is not completed within the configured timeout (default 300s)
- **THEN** exit code SHALL be 3
- **AND** stderr SHALL contain "Review timed out"

#### Scenario: Neovim unreachable
- **WHEN** neither `$NVIM` nor `$NVIM_SOCKET_PATH` is set or connectable
- **THEN** the command SHALL exit with code 0 (fail-open)
- **AND** stdout SHALL contain `{ "decision": "accept", "content": "<original>" }`
- **AND** stderr SHALL contain a warning

### Requirement: No agent awareness

The review command SHALL NOT accept an `--agent` flag and SHALL NOT contain any agent-specific normalization or response formatting logic.

#### Scenario: Stdin is always neph protocol
- **WHEN** `neph-cli review` receives stdin
- **THEN** it SHALL parse `{ "path": "...", "content": "..." }` only
- **AND** SHALL NOT attempt to parse Claude, Gemini, or any agent-specific JSON

#### Scenario: Stdout is always neph protocol
- **WHEN** `neph-cli review` returns a result
- **THEN** it SHALL output `{ "decision": "...", "content": "...", "reason?": "..." }` only
- **AND** SHALL NOT format agent-specific response shapes

### Requirement: Neovim RPC connection

The review command SHALL connect to the running Neovim instance via RPC.

#### Scenario: Connect via $NVIM
- **WHEN** `$NVIM` environment variable is set
- **THEN** the command SHALL connect to that socket path

#### Scenario: Connect via $NVIM_SOCKET_PATH
- **WHEN** `$NVIM` is not set but `$NVIM_SOCKET_PATH` is
- **THEN** the command SHALL connect to `$NVIM_SOCKET_PATH`

### Requirement: Dry-run mode for testing

#### Scenario: NEPH_DRY_RUN=1
- **WHEN** `NEPH_DRY_RUN=1` is set
- **THEN** the command SHALL output accept with original content
- **AND** SHALL NOT attempt Neovim connection
