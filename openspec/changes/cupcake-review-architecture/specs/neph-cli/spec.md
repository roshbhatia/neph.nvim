## ADDED Requirements

### Requirement: Review subcommand speaks neph protocol only

The neph CLI SHALL provide a `review` subcommand that reads `{ path, content }` from stdin, opens an interactive vimdiff review in Neovim, and returns `{ decision, content, reason? }` on stdout. The command SHALL have no agent awareness — no `--agent` flag, no per-agent normalizers, no per-agent response formatters.

#### Scenario: Review command invocation
- **WHEN** `neph-cli review` is invoked with `{ "path": "/foo.lua", "content": "new" }` on stdin
- **THEN** the CLI SHALL connect to Neovim, open a review, and return `{ "decision": "...", "content": "...", "reason?": "..." }` on stdout

#### Scenario: Review with timeout flag
- **WHEN** `neph-cli review --timeout 120` is invoked
- **THEN** the review SHALL use 120 seconds as the timeout instead of the default 300

#### Scenario: Review prints only neph protocol to stdout
- **WHEN** `neph-cli review` completes
- **THEN** stdout SHALL contain ONLY `{ decision, content, reason? }` JSON
- **AND** all diagnostic output SHALL go to stderr
- **AND** no agent-specific fields (e.g. `hookSpecificOutput`) SHALL appear in stdout

## MODIFIED Requirements

### Requirement: Universal CLI bridge

The system SHALL provide a single Node/TS CLI (`neph`) that bridges external programs to Neovim's Lua API via msgpack-rpc. The `gate` subcommand SHALL be removed. The `review` subcommand SHALL speak one protocol with no agent awareness.

#### Scenario: Cupcake signal calls neph-cli review
- **WHEN** Cupcake's `neph_review` signal invokes `neph-cli review`
- **THEN** neph SHALL connect to Neovim via `$NVIM` or `$NVIM_SOCKET_PATH`
- **AND** dispatch the `review.open` method via `lua/neph/rpc.lua`
- **AND** print neph protocol JSON (`{ decision, content }`) to stdout
- **AND** exit 0 on accept/partial, exit 2 on reject, exit 3 on timeout

#### Scenario: Interactive UI commands
- **WHEN** caller invokes `neph ui-select`, `neph ui-input`, or `neph ui-notify`
- **THEN** neph SHALL dispatch to the corresponding `ui.*` RPC endpoint
- **AND** for `ui-select` and `ui-input`, wait for a notification response before exiting
- **AND** print the result to stdout

#### Scenario: Fire-and-forget commands
- **WHEN** caller invokes `neph set <key> <value>` or `neph checktime`
- **THEN** neph SHALL dispatch via rpc.lua, print nothing to stdout, exit 0

## REMOVED Requirements

### Requirement: Gate timeout uses distinct exit code
**Reason**: The `gate` subcommand is removed. The `review` subcommand uses exit codes 0/2/3.
**Migration**: Replace `neph gate --agent X` with Cupcake hooks that invoke `cupcake eval`.

### Requirement: NephClient.review timeout
**Reason**: NephClient SDK removed entirely.
**Migration**: N/A — NephClient is deleted.

### Requirement: NephClient UI dialog timeout
**Reason**: NephClient SDK removed.
**Migration**: UI dialogs retain their own timeouts in the CLI.

### Requirement: Gate decision field validation
**Reason**: Gate subcommand removed.
**Migration**: Decision validation in `review.ts` response handler.

### Requirement: Gate async handler errors are not silently lost
**Reason**: Gate removed. Review uses notification-based result, no async fs.watch handlers.
**Migration**: Error handling simplified.

### Requirement: File watcher error resilience
**Reason**: No more fs.watch for result polling.
**Migration**: N/A.

### Requirement: Edit reconstruction replaces all occurrences
**Reason**: Edit reconstruction moves to Cupcake signals/harnesses, not neph-cli.
**Migration**: Same logic, lives in Cupcake layer.

### Requirement: Dry-run / offline mode
**Reason**: Preserved in `neph-cli review` via `NEPH_DRY_RUN=1`.
**Migration**: Same behavior, new command.

### Requirement: Transport notification listeners are cleaned up on close
**Reason**: Review uses notification + cleanup. Preserved.
**Migration**: N/A.

### Requirement: readStdin rejections are caught
**Reason**: Preserved — `neph-cli review` still reads stdin.
**Migration**: Same behavior.
