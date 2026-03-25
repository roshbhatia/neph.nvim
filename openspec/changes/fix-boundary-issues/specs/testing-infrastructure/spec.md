## MODIFIED Requirements

### Requirement: Lua unit tests

The system SHALL provide unit tests for all Lua API modules using plenary/busted in nvim --headless.

#### Scenario: Review engine tests
- **WHEN** running `tests/api/review/engine_spec.lua`
- **THEN** tests SHALL verify hunk computation, decision application, and envelope construction
- **AND** run without any UI interaction

#### Scenario: RPC dispatch tests
- **WHEN** running `tests/rpc_spec.lua`
- **THEN** tests SHALL verify method routing, unknown method error, and pcall error handling

#### Scenario: API module tests
- **WHEN** running `tests/api/status_spec.lua` and `tests/api/buffers_spec.lua`
- **THEN** tests SHALL verify vim.g manipulation and buffer commands

### Requirement: CLI unit tests

The system SHALL provide vitest unit tests for the neph CLI using injected fake transport.

#### Scenario: Test commands with fake transport
- **WHEN** running `tools/neph-cli/tests/commands.test.ts`
- **THEN** tests SHALL use FakeTransport (no Neovim process)
- **AND** verify correct executeLua calls per command
- **AND** verify stdout JSON output shape

#### Scenario: Test review protocol
- **WHEN** running review command tests
- **THEN** tests SHALL verify request_id generation, notification handling, and envelope output
- **AND** test dry-run/offline auto-accept path
- **AND** test timeout behavior

### Requirement: Contract tests

The system SHALL validate that Lua dispatch and TS client agree on the RPC method catalog. TypeScript contract tests SHALL validate ALL methods defined in protocol.json.

#### Scenario: Lua contract test
- **WHEN** running `tests/contract_spec.lua`
- **THEN** test SHALL load `protocol.json`
- **AND** assert every method exists in `rpc.lua` dispatch table
- **AND** assert no extra methods exist in dispatch table

#### Scenario: TS contract test completeness
- **WHEN** running `tools/neph-cli/tests/contract.test.ts`
- **THEN** test SHALL load `protocol.json`
- **AND** assert every method in protocol.json is validated in the test
- **AND** test SHALL fail if any method from protocol.json is missing from expected methods list
- **AND** SHALL include all methods: review.open, status.set, status.unset, status.get, buffers.check, tab.close, ui.select, ui.input, ui.notify, bus.register, review.pending

#### Scenario: TS contract test CLI mapping
- **WHEN** running `tools/neph-cli/tests/contract.test.ts`
- **THEN** test SHALL verify every CLI command maps to a known method in protocol.json
- **AND** SHALL verify parameter lists match protocol.json definitions

### Requirement: CLI integration tests

The system SHALL provide a small number of integration tests using real headless Neovim.

#### Scenario: End-to-end RPC
- **WHEN** running `tools/neph-cli/tests/integration/rpc.test.ts`
- **THEN** test SHALL spawn `nvim --headless --listen <socket>`
- **AND** test `neph status`, `neph set`, `neph unset` via real socket
- **AND** clean up Neovim process after test

### Requirement: Flake-first Dagger CI

The CI pipeline SHALL use `nix develop` from the flake for all build/test/lint steps.

#### Scenario: Dagger uses nix develop
- **WHEN** `.fluentci/ci.ts` runs in Dagger
- **THEN** container SHALL use `nixos/nix` base image
- **AND** set `NIX_CONFIG="experimental-features = nix-command flakes"`
- **AND** run all tasks via `nix develop --no-write-lock-file -c task <target>`

#### Scenario: Full pipeline passes locally
- **WHEN** developer runs `task ci` locally
- **THEN** Dagger SHALL run lint + test (Lua + TS + contract)
- **AND** pipeline SHALL pass before any push

### Requirement: Test organization

Tests SHALL be organized by layer matching the architecture.

#### Scenario: Directory structure
- **WHEN** browsing test directories
- **THEN** Lua tests SHALL be in `tests/` with `_spec.lua` suffix
- **AND** CLI unit tests SHALL be in `tools/neph-cli/tests/` with `.test.ts` suffix
- **AND** CLI integration tests SHALL be in `tools/neph-cli/tests/integration/`
- **AND** pi adapter tests SHALL remain in `tools/pi/tests/`

#### Scenario: Taskfile targets
- **WHEN** running tests via Taskfile
- **THEN** `task test` SHALL run all test layers
- **AND** `task test:lua` SHALL run plenary/busted Lua tests
- **AND** `task test:cli` SHALL run neph-cli vitest
- **AND** `task test:pi` SHALL run pi adapter vitest

### Requirement: Boundary and edge case test coverage

The test suite SHALL include comprehensive coverage for boundary interactions and edge cases.

#### Scenario: Bus health check tests
- **WHEN** running boundary tests
- **THEN** tests SHALL verify bus health timer iteration safety
- **AND** test ping failures and automatic unregistration
- **AND** test timer cleanup when no channels remain

#### Scenario: Review queue concurrency tests
- **WHEN** running boundary tests
- **THEN** tests SHALL verify concurrent review enqueue operations
- **AND** test state consistency under concurrent access
- **AND** test queue ordering guarantees

#### Scenario: Socket discovery edge case tests
- **WHEN** running boundary tests
- **THEN** tests SHALL verify ambiguous socket discovery cases
- **AND** test monorepo scenarios
- **AND** test fallback behavior when no clear match