## ADDED Requirements

### Requirement: E2E test task in Taskfile
The Taskfile SHALL include a `test:e2e` task that runs the e2e test suite.

#### Scenario: Task runs e2e tests
- **WHEN** `task test:e2e` is executed
- **THEN** the e2e test runner SHALL execute and report results

#### Scenario: CI task includes e2e
- **WHEN** `task test` is executed (the full test suite)
- **THEN** e2e tests SHALL run after unit tests

### Requirement: Dagger CI pipeline includes e2e
The `.fluentci/ci.ts` Dagger pipeline SHALL include an e2e test stage that installs agents, builds tools, and runs e2e tests.

#### Scenario: E2E stage runs in CI
- **WHEN** the Dagger CI pipeline executes
- **THEN** an e2e test stage SHALL run after the existing lint and unit test stages

#### Scenario: E2E failure fails the pipeline
- **WHEN** any e2e test fails
- **THEN** the CI pipeline SHALL exit with a non-zero code

### Requirement: Agent binaries cached in CI
The CI pipeline SHOULD cache agent binary installations to avoid re-downloading on every run.

#### Scenario: Cached installs reused
- **WHEN** the CI pipeline runs and agent binaries are already cached
- **THEN** the installation step SHALL skip downloading and use cached binaries
