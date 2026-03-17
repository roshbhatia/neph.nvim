## ADDED Requirements

### Requirement: neph-cli protocol unit tests

The system SHALL provide vitest unit tests for the neph-cli review command that validate the neph protocol (`{ path, content }` in, `{ decision, content, reason? }` out).

#### Scenario: Accept flow test
- **WHEN** running review tests
- **THEN** tests SHALL verify that accept returns `{ decision: "accept", content: "..." }` on stdout and exit code 0

#### Scenario: Reject flow test
- **WHEN** running review tests
- **THEN** tests SHALL verify that reject returns `{ decision: "reject", reason: "..." }` and exit code 2

#### Scenario: Fail-open when no socket
- **WHEN** running review tests with null transport
- **THEN** tests SHALL verify auto-accept with warning on stderr

#### Scenario: Timeout test
- **WHEN** review times out
- **THEN** tests SHALL verify exit code 3

#### Scenario: No agent-specific fields in output
- **WHEN** running any review test
- **THEN** stdout SHALL contain ONLY `{ decision, content, reason? }` — no `hookSpecificOutput` or other agent fields

### Requirement: Cupcake signal integration tests

The system SHALL provide integration tests that verify the `neph_review` signal works correctly with Cupcake's evaluation pipeline.

#### Scenario: Signal invocation with mock Neovim
- **WHEN** integration tests run
- **THEN** they SHALL spawn `neph-cli review` with `{ path, content }` JSON on stdin
- **AND** mock the Neovim RPC to return a scripted review envelope
- **AND** verify the signal output JSON matches neph protocol for Rego policy consumption

#### Scenario: Signal timeout behavior
- **WHEN** the mock Neovim RPC does not respond
- **THEN** `neph-cli review` SHALL exit with code 3 after the configured timeout

### Requirement: Per-agent E2E review tests

The system SHALL provide end-to-end tests that exercise the full hook-to-review-to-response cycle for each supported agent.

#### Scenario: Claude Code E2E test
- **WHEN** the E2E test runs
- **THEN** it SHALL spawn headless Neovim with neph configured
- **AND** invoke `cupcake eval --harness claude` with a Claude PreToolUse Write JSON
- **AND** verify the response is in Claude's expected format (Cupcake harness formats it)

#### Scenario: Gemini CLI E2E test
- **WHEN** the E2E test runs
- **THEN** it SHALL invoke `cupcake eval --harness gemini` with Gemini BeforeTool write_file JSON
- **AND** verify the response is in Gemini's expected format

#### Scenario: neph-cli protocol E2E test
- **WHEN** the E2E test runs
- **THEN** it SHALL spawn headless Neovim
- **AND** invoke `neph-cli review` with `{ path, content }` on stdin
- **AND** programmatically accept all hunks via Neovim RPC
- **AND** verify stdout contains `{ decision: "accept", content: "..." }`

### Requirement: Cupcake harness contract tests

The system SHALL provide contract tests that validate stdin/stdout JSON schemas for Cupcake harnesses.

#### Scenario: Pi harness contract
- **WHEN** running contract tests
- **THEN** the test SHALL validate that the Pi Cupcake harness serializes events matching Cupcake's expected format
- **AND** correctly deserializes Cupcake's response format

### Requirement: Rego policy unit tests

The system SHALL provide OPA test files for each Rego policy.

#### Scenario: Review policy accepts on signal accept
- **WHEN** running `opa test` against the review-triggering policy
- **AND** input includes `signals.neph_review.decision = "accept"`
- **THEN** the policy SHALL emit an `allow` decision

#### Scenario: Dangerous command policy blocks rm -rf
- **WHEN** running `opa test`
- **AND** input includes `tool_input.command = "rm -rf /"`
- **THEN** the policy SHALL emit a `deny` decision

## MODIFIED Requirements

### Requirement: CLI unit tests

The system SHALL provide vitest unit tests for the neph CLI using injected fake transport. Tests SHALL cover the `review` command with neph protocol only — no agent-specific tests.

#### Scenario: Test review command with fake transport
- **WHEN** running `tools/neph-cli/tests/review.test.ts`
- **THEN** tests SHALL use FakeTransport (no Neovim process)
- **AND** verify stdin is parsed as `{ path, content }`
- **AND** verify stdout is always `{ decision, content, reason? }`
- **AND** test timeout behavior (exit code 3)
- **AND** test dry-run/offline auto-accept path
- **AND** test fail-open when no socket

### Requirement: Test organization

Tests SHALL be organized by layer matching the architecture.

#### Scenario: Directory structure
- **WHEN** browsing test directories
- **THEN** Lua tests SHALL be in `tests/` with `_spec.lua` suffix
- **AND** CLI unit tests SHALL be in `tools/neph-cli/tests/` with `.test.ts` suffix
- **AND** Pi harness tests SHALL be in `tools/pi/tests/`
- **AND** Rego policy tests SHALL be in `.cupcake/policies/neph/*_test.rego`
- **AND** E2E tests SHALL be in `tests/e2e/`

#### Scenario: Taskfile targets
- **WHEN** running tests via Taskfile
- **THEN** `task test` SHALL run all test layers
- **AND** `task test:lua` SHALL run plenary/busted Lua tests
- **AND** `task test:cli` SHALL run neph-cli vitest
- **AND** `task test:pi` SHALL run Pi harness vitest
- **AND** `task test:rego` SHALL run OPA policy tests
- **AND** `task test:e2e` SHALL run end-to-end tests
