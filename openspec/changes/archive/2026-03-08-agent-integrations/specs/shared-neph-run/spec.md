## ADDED Requirements

### Requirement: Shared neph-run module exists
A shared TypeScript module SHALL exist at `tools/lib/neph-run.ts` providing `nephRun()`, `review()`, and fire-and-forget `neph()` functions for use by all TypeScript agent adapters.

#### Scenario: Module is importable
- **WHEN** a TypeScript adapter imports `{ nephRun, review, neph } from '../lib/neph-run'`
- **THEN** all three functions SHALL be available and typed

### Requirement: nephRun spawns neph CLI subprocess
`nephRun(args, stdin?, timeoutMs?)` SHALL spawn the `neph` CLI as a child process, pipe optional stdin, and return stdout as a string. It SHALL reject on non-zero exit or timeout.

#### Scenario: Successful command
- **WHEN** `nephRun(["set", "foo", "bar"], undefined, 5000)` is called
- **THEN** it SHALL spawn `neph set foo bar`, wait for exit 0, and resolve with stdout

#### Scenario: Command timeout
- **WHEN** `nephRun(["review", "file.ts"], "content", 100)` is called and the process does not exit within 100ms
- **THEN** it SHALL kill the child process with SIGTERM and reject with a timeout error

#### Scenario: Command failure
- **WHEN** `nephRun(["bogus"])` is called and the process exits with non-zero
- **THEN** it SHALL reject with an error containing stderr output

### Requirement: review function calls neph review and parses envelope
`review(filePath, content)` SHALL call `nephRun(["review", filePath], content)` with no timeout (interactive), parse the stdout as JSON, and return a typed `ReviewEnvelope`.

#### Scenario: Review returns envelope
- **WHEN** `review("/path/file.ts", "new content")` is called
- **THEN** it SHALL return a `ReviewEnvelope` with `schema`, `decision`, `content`, `hunks`, and optional `reason`

#### Scenario: Review failure returns reject envelope
- **WHEN** `review("/path/file.ts", "content")` is called and neph fails
- **THEN** it SHALL return a reject envelope with `decision: "reject"` and reason "Review failed or timed out"

### Requirement: neph function is fire-and-forget with serial queue
`neph(...args)` SHALL enqueue a neph CLI command for serial execution. Commands SHALL execute in dispatch order. Errors SHALL be swallowed silently. Each command SHALL have the configured timeout.

#### Scenario: Commands execute in order
- **WHEN** `neph("set", "foo", "true")` then `neph("set", "bar", "true")` are called
- **THEN** the `set foo true` command SHALL complete before `set bar true` starts

#### Scenario: Errors are swallowed
- **WHEN** `neph("bogus")` is called and the command fails
- **THEN** no error SHALL be thrown and subsequent commands SHALL still execute

### Requirement: pi.ts imports from shared module
`tools/pi/pi.ts` SHALL be refactored to import `nephRun`, `review`, and `neph` from `tools/lib/neph-run.ts` instead of defining them inline. Behavior SHALL be identical.

#### Scenario: Pi behavior unchanged
- **WHEN** the pi extension is loaded after the refactor
- **THEN** all existing pi tests SHALL pass without modification
