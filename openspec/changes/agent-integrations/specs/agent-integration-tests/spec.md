## ADDED Requirements

### Requirement: Hook config syntax validation tests
Each agent hook config file SHALL have a vitest test that validates it parses correctly as JSON and contains the expected hook structure.

#### Scenario: All JSON hook configs parse
- **WHEN** the test suite validates JSON hook config files
- **THEN** every JSON config under `tools/claude/`, `tools/copilot/`, `tools/cursor/`, and `tools/gemini/` SHALL parse without errors

#### Scenario: Hook configs reference neph gate
- **WHEN** the test suite inspects each hook config's command field
- **THEN** every command SHALL reference `neph gate --agent <name>` where `<name>` matches the agent

### Requirement: Gate command unit tests
The `neph gate` command SHALL have vitest tests using FakeTransport that validate behavior for each edge case.

#### Scenario: Accept decision exits 0
- **WHEN** the gate command receives mock stdin with a claude write tool input
- **AND** the FakeTransport returns a review accept decision
- **THEN** the process SHALL exit 0

#### Scenario: Reject decision exits 2
- **WHEN** the gate command receives mock stdin with a claude write tool input
- **AND** the FakeTransport returns a review reject decision
- **THEN** the process SHALL exit 2

#### Scenario: Missing socket auto-accepts
- **WHEN** the gate command runs without any discoverable neovim socket
- **THEN** the process SHALL exit 0

#### Scenario: Dry-run auto-accepts
- **WHEN** the gate command runs with NEPH_DRY_RUN=1
- **THEN** the process SHALL exit 0

#### Scenario: Each agent format normalizes correctly
- **WHEN** the gate command receives stdin in claude, copilot, cursor, and gemini formats
- **THEN** each SHALL correctly extract the file path and content

### Requirement: Shared neph-run module tests
The `tools/lib/neph-run.ts` module SHALL have vitest tests validating nephRun, review, and neph functions with mocked child_process.

#### Scenario: nephRun resolves on success
- **WHEN** nephRun is called and the mock process exits 0 with stdout
- **THEN** it SHALL resolve with the stdout string

#### Scenario: nephRun rejects on failure
- **WHEN** nephRun is called and the mock process exits non-zero
- **THEN** it SHALL reject with an error containing stderr

#### Scenario: nephRun rejects on timeout
- **WHEN** nephRun is called with a timeout and the process does not exit in time
- **THEN** it SHALL kill the process and reject with a timeout error

#### Scenario: review returns typed envelope
- **WHEN** review is called and neph returns valid JSON
- **THEN** it SHALL return a typed ReviewEnvelope object

#### Scenario: neph fire-and-forget executes in order
- **WHEN** multiple neph() calls are made
- **THEN** they SHALL execute serially in dispatch order

### Requirement: TypeScript adapter compile tests
Both `tools/amp/neph-plugin.ts` and `tools/opencode/neph-write.ts` SHALL compile without type errors.

#### Scenario: TypeScript plugins compile
- **WHEN** `tsc --noEmit` is run on the adapter files
- **THEN** both SHALL compile without errors

### Requirement: Neph CLI contract tests cover gate command
Contract tests SHALL be extended to include the `gate` command, ensuring it routes to the correct RPC methods.

#### Scenario: Gate command methods in protocol
- **WHEN** the contract test suite runs
- **THEN** the gate command's usage of `review.open`, `status.set`, and `status.unset` SHALL be validated against `protocol.json`

### Requirement: Pi regression test
Pi's existing test suite SHALL pass without modification after the refactor to use `lib/neph-run.ts`.

#### Scenario: Pi test suite passes
- **WHEN** `task tools:test:pi` runs
- **THEN** all existing pi tests SHALL pass

#### Scenario: Pi install flow works
- **WHEN** `tools.install()` runs
- **THEN** pi symlinks SHALL still point to `tools/pi/` sources

### Requirement: All tests run without agent binaries
All integration tests SHALL run without requiring any agent CLI binaries installed.

#### Scenario: CI passes without agent CLIs
- **WHEN** `task test` runs in a CI environment with no agent CLIs
- **THEN** all tests SHALL pass
