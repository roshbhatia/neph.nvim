## ADDED Requirements

### Requirement: Fast local lint task
The Taskfile SHALL provide a `check` task that runs only linting (no tests, no builds) and completes in under 2 seconds on a warm system.

#### Scenario: task check runs linters only
- **WHEN** `task check` is executed
- **THEN** stylua and luacheck SHALL run against lua/ and tests/ directories

#### Scenario: task check skips tests
- **WHEN** `task check` is executed
- **THEN** no test suites (plenary, vitest, e2e) SHALL be invoked

#### Scenario: task check completes quickly
- **WHEN** `task check` is executed on a system with stylua and luacheck installed
- **THEN** it SHALL complete in under 2 seconds
