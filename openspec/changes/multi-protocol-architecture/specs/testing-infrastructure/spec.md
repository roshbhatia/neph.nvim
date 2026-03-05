## ADDED Requirements

### Requirement: Unit test coverage for Lua API

The system SHALL provide comprehensive unit tests for the pure Lua API layer using plenary.nvim.

#### Scenario: Test write operation
- **WHEN** running `tests/unit/api/write_spec.lua`
- **THEN** tests SHALL verify file creation without external dependencies
- **AND** use mocked filesystem or temporary test directories

#### Scenario: Test edit operation
- **WHEN** running edit operation unit tests
- **THEN** tests SHALL verify exact match logic
- **AND** verify error cases (file not found, match not found)

#### Scenario: Test path validation
- **WHEN** running path validation tests
- **THEN** tests SHALL verify rejection of invalid paths
- **AND** verify normalization of path separators

#### Scenario: Achieve 70% code coverage for Lua code
- **WHEN** running test suite with coverage reporting
- **THEN** Lua code in `lua/neph/api/` SHALL have ≥ 70% line coverage
- **AND** all public functions SHALL be tested

### Requirement: Integration tests for protocol adapters

The system SHALL provide integration tests that verify protocols work with real Neovim instances.

#### Scenario: Test RPC protocol with headless Neovim
- **WHEN** running `tests/integration/rpc-protocol.test.ts`
- **THEN** test SHALL spawn headless Neovim instance
- **AND** connect via `@neovim/node-client`
- **AND** verify file operations complete successfully

#### Scenario: Test WebSocket protocol
- **WHEN** running WebSocket integration tests
- **THEN** test SHALL start WebSocket server in Neovim
- **AND** connect external WebSocket client
- **AND** verify JSON-RPC message exchange

#### Scenario: Test Script protocol
- **WHEN** running Script protocol integration tests
- **THEN** test SHALL create temporary executable scripts
- **AND** verify describe and execute actions work
- **AND** clean up temporary files

#### Scenario: Achieve 25% integration test coverage
- **WHEN** measuring test distribution
- **THEN** integration tests SHALL cover ≥ 25% of testing effort
- **AND** all protocol adapters SHALL have integration tests

### Requirement: End-to-end tests with real agents

The system SHALL provide end-to-end tests that verify complete workflows with real agent executables.

#### Scenario: Test pi agent workflow
- **WHEN** running `tests/e2e/pi-agent.sh`
- **THEN** test SHALL start real pi agent
- **AND** send test prompts
- **AND** verify expected file modifications

#### Scenario: Test multiple protocol agents
- **WHEN** running multi-agent e2e test
- **THEN** test SHALL start agents with different protocols concurrently
- **AND** verify no interference between protocols

#### Scenario: Limit e2e test runtime
- **WHEN** running full e2e test suite
- **THEN** total runtime SHALL be < 5 minutes
- **AND** each test SHALL have timeout of 60 seconds

### Requirement: Mock infrastructure

The system SHALL provide reusable mocks for testing without external dependencies.

#### Scenario: Mock Neovim instance
- **WHEN** unit tests need Neovim API
- **THEN** mock SHALL provide stub implementations
- **AND** record function calls for verification

#### Scenario: Mock filesystem operations
- **WHEN** testing file operations
- **THEN** mock SHALL provide in-memory filesystem
- **AND** allow tests to run without touching real filesystem

#### Scenario: Mock protocol adapters
- **WHEN** testing Lua API without protocols
- **THEN** mocks SHALL provide protocol adapter interface
- **AND** record tool calls for verification

### Requirement: Test organization

The system SHALL organize tests by layer matching the architecture.

#### Scenario: Unit tests in tests/unit/
- **WHEN** browsing test directory
- **THEN** unit tests SHALL be in `tests/unit/api/`, `tests/unit/protocols/`
- **AND** match structure of `lua/neph/` directory

#### Scenario: Integration tests in tests/integration/
- **WHEN** browsing test directory
- **THEN** integration tests SHALL be in `tests/integration/`
- **AND** be organized by protocol (rpc-protocol.test.ts, websocket-protocol.test.ts)

#### Scenario: E2E tests in tests/e2e/
- **WHEN** browsing test directory
- **THEN** e2e tests SHALL be in `tests/e2e/`
- **AND** be organized by agent (pi-agent.sh, goose-agent.sh)

### Requirement: CI integration

The system SHALL run all test layers in continuous integration pipeline.

#### Scenario: Run tests in Dagger pipeline
- **WHEN** CI pipeline executes
- **THEN** pipeline SHALL run `task test:unit`, `task test:integration`, `task test:e2e`
- **AND** fail build if any test layer fails

#### Scenario: Parallel test execution
- **WHEN** running tests in CI
- **THEN** unit tests and integration tests SHALL run in parallel
- **AND** e2e tests SHALL run sequentially

#### Scenario: Test coverage reporting
- **WHEN** CI pipeline completes
- **THEN** pipeline SHALL generate coverage report
- **AND** fail if coverage drops below thresholds (70% unit, 25% integration)
