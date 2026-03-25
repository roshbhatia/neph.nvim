## ADDED Requirements

### Requirement: Comprehensive boundary test coverage
All system boundaries SHALL have test coverage.
Tests SHALL exercise edge cases at boundaries between subsystems.

#### Scenario: Bus health check tests
- **WHEN** running the test suite
- **THEN** there SHALL be tests for bus health timer functionality
- **AND** SHALL test ping failures and automatic unregistration
- **AND** SHALL test timer cleanup when no channels remain
- **AND** SHALL test iteration safety (no table modification during iteration)

#### Scenario: Review queue concurrency tests
- **WHEN** running the test suite
- **THEN** there SHALL be tests for concurrent review enqueue operations
- **AND** SHALL test state consistency under concurrent access
- **AND** SHALL test cancellation and cleanup scenarios
- **AND** SHALL test queue ordering guarantees

#### Scenario: Socket discovery edge case tests
- **WHEN** running the test suite
- **THEN** there SHALL be tests for ambiguous socket discovery cases
- **AND** SHALL test monorepo scenarios
- **AND** SHALL test fallback behavior when no clear match
- **AND** SHALL test all OS-specific temporary path patterns

#### Scenario: Protocol contract validation tests
- **WHEN** running the test suite
- **THEN** TypeScript contract tests SHALL validate all methods in protocol.json
- **AND** SHALL fail if any method is missing from tests
- **AND** SHALL validate parameter lists match protocol.json

### Requirement: Integration test coverage
End-to-end workflows SHALL have integration test coverage.
Integration tests SHALL verify cross-boundary interactions.

#### Scenario: CLI review workflow integration test
- **WHEN** running integration tests
- **THEN** there SHALL be a test for CLI → Neovim → Review → Result flow
- **AND** SHALL test file fallback when notification fails
- **AND** SHALL test error handling and recovery

#### Scenario: Extension agent lifecycle integration test
- **WHEN** running integration tests
- **THEN** there SHALL be a test for extension agent registration → prompt delivery → review cycle
- **AND** SHALL test persistent connection maintenance
- **AND** SHALL test reconnection scenarios

#### Scenario: Multiple agent concurrency test
- **WHEN** running integration tests
- **THEN** there SHALL be a test for multiple agents operating concurrently
- **AND** SHALL test resource isolation
- **AND** SHALL test state separation between agents

### Requirement: Error recovery test coverage
Error recovery paths SHALL have test coverage.
Tests SHALL simulate failure scenarios.

#### Scenario: Neovim crash/reconnect test
- **WHEN** running error recovery tests
- **THEN** there SHALL be tests for Neovim crash and reconnection scenarios
- **AND** SHALL test state recovery after reconnect
- **AND** SHALL test cleanup of orphaned resources

#### Scenario: File system edge case tests
- **WHEN** running error recovery tests
- **THEN** there SHALL be tests for symlink resolution failures
- **AND** SHALL test permission denied scenarios
- **AND** SHALL test full disk conditions
- **AND** SHALL test network filesystem timeouts