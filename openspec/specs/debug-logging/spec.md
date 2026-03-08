## ADDED Requirements

### Requirement: Lua log module
The system SHALL provide a `neph.internal.log` module with a `log.debug(module, message, ...)` function that appends a timestamped line to `/tmp/neph-debug.log` when `vim.g.neph_debug` is truthy.

#### Scenario: Logging when debug enabled
- **WHEN** `vim.g.neph_debug` is `true` and `log.debug("session", "opened %s", "pi")` is called
- **THEN** a line like `[12:34:56.789] [lua] [session] opened pi` SHALL be appended to `/tmp/neph-debug.log`

#### Scenario: No-op when debug disabled
- **WHEN** `vim.g.neph_debug` is `nil` and `log.debug(...)` is called
- **THEN** no file I/O SHALL occur and the function SHALL return immediately

### Requirement: TypeScript log module
The system SHALL provide a `tools/lib/log.ts` module with a `debug(module, message)` function that appends a timestamped line to `/tmp/neph-debug.log` when `process.env.NEPH_DEBUG` is set.

#### Scenario: Logging when NEPH_DEBUG set
- **WHEN** `NEPH_DEBUG=1` is in the environment and `debug("pi-poll", "got prompt: hello")` is called
- **THEN** a line like `[12:34:56.789] [ts] [pi-poll] got prompt: hello` SHALL be appended to `/tmp/neph-debug.log`

#### Scenario: No-op when NEPH_DEBUG unset
- **WHEN** `NEPH_DEBUG` is not in the environment and `debug(...)` is called
- **THEN** no file I/O SHALL occur

### Requirement: Send adapter logging
The pi send_adapter in `lua/neph/agents/pi.lua` SHALL log when it sets `vim.g.neph_pending_prompt`.

#### Scenario: Prompt set logged
- **WHEN** `send_adapter` is called with text "hello" and submit=true
- **THEN** a debug log line SHALL be written containing the prompt text and submit flag

### Requirement: Session lifecycle logging
`lua/neph/internal/session.lua` SHALL log open, focus, hide, kill_session, and send events.

#### Scenario: Session open logged
- **WHEN** `session.open("pi")` is called
- **THEN** a debug log line SHALL be written containing "open" and the terminal name

#### Scenario: Session send logged
- **WHEN** `session.send("pi", "hello", {submit=true})` is called
- **THEN** a debug log line SHALL be written containing "send", the terminal name, and whether an adapter was used

### Requirement: Pi poll loop logging
`tools/pi/pi.ts` SHALL log each poll cycle result when `NEPH_DEBUG` is set.

#### Scenario: Poll finds prompt
- **WHEN** the poll loop receives a non-nil prompt value
- **THEN** a debug log line SHALL be written containing "prompt found" and the prompt text

#### Scenario: Poll finds no prompt
- **WHEN** the poll loop receives a nil/empty result
- **THEN** a debug log line SHALL be written containing "poll: no prompt"

#### Scenario: Poll error logged
- **WHEN** the poll loop catches an error
- **THEN** a debug log line SHALL be written containing the error message instead of silently swallowing it

### Requirement: CLI spawn logging
`tools/lib/neph-run.ts` SHALL log CLI command and exit status when `NEPH_DEBUG` is set.

#### Scenario: Successful CLI spawn
- **WHEN** `nephRun("get", "neph_pending_prompt")` completes successfully
- **THEN** debug log lines SHALL be written for the spawn and the result

#### Scenario: Failed CLI spawn
- **WHEN** `nephRun(...)` fails with a non-zero exit code
- **THEN** a debug log line SHALL be written containing the exit code and stderr

### Requirement: NephDebug user command
The system SHALL register a `:NephDebug` user command with subcommands `on`, `off`, and `tail`.

#### Scenario: Toggle on
- **WHEN** `:NephDebug on` is executed
- **THEN** `vim.g.neph_debug` SHALL be set to `true` and `/tmp/neph-debug.log` SHALL be truncated

#### Scenario: Toggle off
- **WHEN** `:NephDebug off` is executed
- **THEN** `vim.g.neph_debug` SHALL be set to `nil`

#### Scenario: Toggle without args
- **WHEN** `:NephDebug` is executed with no arguments
- **THEN** `vim.g.neph_debug` SHALL be toggled (nil→true, true→nil)

#### Scenario: Tail log
- **WHEN** `:NephDebug tail` is executed
- **THEN** `/tmp/neph-debug.log` SHALL be opened in a horizontal split

### Requirement: RPC dispatch logging
`lua/neph/rpc.lua` SHALL log incoming RPC method calls and their results when debug is enabled.

#### Scenario: RPC call logged
- **WHEN** an RPC method `status.get` is dispatched with params `{name="pi_active"}`
- **THEN** a debug log line SHALL be written containing the method name and params
