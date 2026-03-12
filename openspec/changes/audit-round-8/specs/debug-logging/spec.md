## MODIFIED Requirements

### Requirement: Lua log module

The system SHALL provide a `neph.internal.log` module with a `log.debug(module, message, ...)` function that appends a timestamped line to `/tmp/neph-debug-<PID>.log` (where `<PID>` is the Neovim process ID) when `vim.g.neph_debug` is truthy.

#### Scenario: Logging when debug enabled

- **WHEN** `vim.g.neph_debug` is `true` and `log.debug("session", "opened %s", "pi")` is called
- **THEN** a line like `[12:34:56.789] [lua] [session] opened pi` SHALL be appended to `/tmp/neph-debug-<PID>.log`

#### Scenario: No-op when debug disabled

- **WHEN** `vim.g.neph_debug` is `nil` and `log.debug(...)` is called
- **THEN** no file I/O SHALL occur and the function SHALL return immediately

### Requirement: TypeScript log module

The system SHALL provide a `tools/lib/log.ts` module with a `debug(module, message)` function that appends a timestamped line to `/tmp/neph-debug-<PPID>.log` (where `<PPID>` is the parent process ID, i.e. the Neovim instance that spawned the CLI) when `process.env.NEPH_DEBUG` is set.

#### Scenario: Logging when NEPH_DEBUG set

- **WHEN** `NEPH_DEBUG=1` is in the environment and `debug("pi-poll", "got prompt: hello")` is called
- **THEN** a line like `[12:34:56.789] [ts] [pi-poll] got prompt: hello` SHALL be appended to `/tmp/neph-debug-<PPID>.log`

#### Scenario: No-op when NEPH_DEBUG unset

- **WHEN** `NEPH_DEBUG` is not in the environment and `debug(...)` is called
- **THEN** no file I/O SHALL occur

### Requirement: NephDebug user command

The system SHALL register a `:NephDebug` user command with subcommands `on`, `off`, and `tail`.

#### Scenario: Toggle on

- **WHEN** `:NephDebug on` is executed
- **THEN** `vim.g.neph_debug` SHALL be set to `true` and `/tmp/neph-debug-<PID>.log` SHALL be truncated

#### Scenario: Toggle off

- **WHEN** `:NephDebug off` is executed
- **THEN** `vim.g.neph_debug` SHALL be set to `nil`

#### Scenario: Toggle without args

- **WHEN** `:NephDebug` is executed with no arguments
- **THEN** `vim.g.neph_debug` SHALL be toggled (nil→true, true→nil)

#### Scenario: Tail log

- **WHEN** `:NephDebug tail` is executed
- **THEN** `/tmp/neph-debug-<PID>.log` SHALL be opened in a horizontal split
