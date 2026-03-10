## ADDED Requirements

### Requirement: Universal CLI bridge

The system SHALL provide a single Node/TS CLI (`neph`) that bridges external programs to Neovim's Lua API via msgpack-rpc.

#### Scenario: RPC agent spawns neph as subprocess
- **WHEN** pi extension calls `spawn("neph", ["review", path], { stdin: content })`
- **THEN** neph SHALL connect to Neovim via `NVIM_SOCKET_PATH`
- **AND** dispatch the review method via `lua/neph/rpc.lua`
- **AND** print ReviewEnvelope JSON to stdout
- **AND** exit 0 on success

#### Scenario: Interactive UI commands
- **WHEN** caller invokes `neph ui-select`, `neph ui-input`, or `neph ui-notify`
- **THEN** neph SHALL dispatch to the corresponding `ui.*` RPC endpoint
- **AND** for `ui-select` and `ui-input`, wait for a notification response before exiting
- **AND** print the result to stdout

#### Scenario: PATH agent discovers neph on PATH
- **WHEN** an agent calls `neph review <path>` with content on stdin
- **THEN** neph SHALL behave identically to subprocess invocation
- **AND** print only JSON to stdout, logs to stderr

#### Scenario: Fire-and-forget commands
- **WHEN** caller invokes `neph set <key> <value>` or `neph checktime`
- **THEN** neph SHALL dispatch via rpc.lua, print nothing to stdout, exit 0

#### Scenario: Self-describing tool schema
- **WHEN** caller invokes `neph spec`
- **THEN** neph SHALL print JSON tool schema describing available commands
- **AND** include input/output shapes for PATH agent discovery

### Requirement: Transport interface injection

The CLI SHALL use an injected transport interface for Neovim communication.

#### Scenario: Production transport
- **WHEN** neph runs normally
- **THEN** it SHALL use SocketTransport wrapping `@neovim/node-client`
- **AND** connect via Unix socket at `NVIM_SOCKET_PATH`

#### Scenario: Test transport
- **WHEN** unit tests instantiate neph commands
- **THEN** they SHALL inject FakeTransport
- **AND** FakeTransport SHALL record calls and return scripted responses
- **AND** no Neovim process SHALL be required

### Requirement: Dry-run / offline mode

The CLI SHALL auto-accept reviews when no Neovim connection is available.

#### Scenario: NEPH_DRY_RUN=1
- **WHEN** `NEPH_DRY_RUN=1` is set
- **THEN** `neph review` SHALL print accept envelope with stdin content
- **AND** SHALL NOT attempt Neovim connection

#### Scenario: No socket available
- **WHEN** `NVIM_SOCKET_PATH` is unset and no socket auto-discovered
- **THEN** `neph review` SHALL auto-accept
- **AND** other commands SHALL exit 1 with error on stderr

### Requirement: Single Lua dispatch string

The CLI SHALL use exactly one Lua expression for all RPC calls.

#### Scenario: All commands use same Lua string
- **WHEN** any command dispatches to Neovim
- **THEN** it SHALL call `nvim.executeLua('return require("neph.rpc").request(...)', [method, params])`
- **AND** SHALL NOT contain any other inline Lua strings

### Requirement: Gate timeout uses distinct exit code

The gate command SHALL use exit code 3 for timeout, distinct from exit code 2 for user rejection.

#### Scenario: User rejects review

- **WHEN** the user explicitly rejects all hunks
- **THEN** the gate SHALL exit with code 2

#### Scenario: Review times out

- **WHEN** the review is not completed within 300 seconds
- **THEN** the gate SHALL exit with code 3
- **AND** the timeout envelope SHALL include `{ decision: "timeout", reason: "Review timed out (300s)" }`

#### Scenario: Review accepted

- **WHEN** the user accepts all hunks
- **THEN** the gate SHALL exit with code 0

### Requirement: NephClient.review timeout

The `NephClient.review()` method SHALL include a timeout to prevent indefinite hangs.

#### Scenario: Review completes within timeout

- **WHEN** `NephClient.review()` is called
- **AND** the Lua side sends `neph:review_done` within 300 seconds
- **THEN** the method SHALL resolve with the review envelope

#### Scenario: Review exceeds timeout

- **WHEN** `NephClient.review()` is called
- **AND** no `neph:review_done` is received within 300 seconds
- **THEN** the method SHALL reject with a timeout error
- **AND** the pending request SHALL be cleaned up

### Requirement: Edit reconstruction replaces all occurrences

The `reconstructEdit` function and equivalent edit handlers SHALL replace ALL occurrences of the old string, not just the first.

#### Scenario: Old string appears multiple times

- **WHEN** the file contains multiple occurrences of `oldStr`
- **THEN** all occurrences SHALL be replaced with `newStr`

### Requirement: File watcher error resilience

The `fs.watch()` calls in gate and review commands SHALL handle watcher errors without crashing.

#### Scenario: Watcher emits error

- **WHEN** the filesystem watcher emits an error event
- **THEN** the error SHALL be logged to stderr
- **AND** the process SHALL NOT crash

### Requirement: NephClient UI dialog timeout

The `uiSelect()` and `uiInput()` methods SHALL include a timeout to prevent indefinite hangs.

#### Scenario: Dialog not answered within 60 seconds

- **WHEN** `uiSelect()` or `uiInput()` is called
- **AND** no response is received within 60 seconds
- **THEN** the method SHALL resolve with `undefined`
- **AND** the pending request SHALL be cleaned up

### Requirement: Gate decision field validation

The gate SHALL validate the decision field from review results before using it.

#### Scenario: Decision field is undefined or non-string

- **WHEN** the review result JSON is parsed
- **AND** the `decision` field is undefined or not a string
- **THEN** the gate SHALL treat it as "accept" (exit 0, fail-open)

### Requirement: Async notification handlers are error-safe

Async notification handlers SHALL catch and log errors rather than leaving promises unhandled.

#### Scenario: handleResult throws during notification callback

- **WHEN** an async notification handler throws or its promise rejects
- **THEN** the error SHALL be logged to stderr
- **AND** the process SHALL NOT hang from unhandled rejection

### Requirement: Gate async handler errors are not silently lost

When `handleResult()` is called from synchronous callbacks (notification handler, fs.watch), its returned Promise must have error handling attached so rejections are logged rather than silently swallowed.

#### Scenario: handleResult throws inside notification handler
- **WHEN** the notification handler calls `handleResult()`
- **AND** the async function rejects
- **THEN** the error is written to stderr

#### Scenario: handleResult throws inside fs.watch callback
- **WHEN** the fs.watch callback calls `handleResult()`
- **AND** the async function rejects
- **THEN** the error is written to stderr

### Requirement: Transport notification listeners are cleaned up on close

#### Scenario: Transport is closed
- **WHEN** `transport.close()` is called
- **THEN** all notification listeners registered via `onNotification()` are removed

### Requirement: readStdin rejections are caught

The `readStdin()` Promise SHALL have a `.catch()` handler so that stream errors are logged and cause the process to exit.

#### Scenario: stdin stream errors

- **WHEN** `readStdin()` is called
- **AND** the stdin stream emits an error (e.g., broken pipe)
- **THEN** the error SHALL be logged to stderr
- **AND** the process SHALL exit with code 1
