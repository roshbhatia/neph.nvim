## ADDED Requirements

### Requirement: Agent installation for testing
The project SHALL provide a mechanism to install agent binaries needed for e2e testing. Installation SHALL be automated in CI and optional locally.

#### Scenario: CI installs required agents
- **WHEN** the CI pipeline runs e2e tests
- **THEN** the following agents SHALL be installed in the CI container: pi (via npm), claude (via npm)

#### Scenario: Local tests skip missing agents
- **WHEN** e2e tests run locally and an agent binary is not on PATH
- **THEN** tests for that agent SHALL be skipped with a warning, not fail

### Requirement: Neph CLI available for testing
The `neph` CLI binary SHALL be built and available on PATH before e2e tests run, since agent integrations depend on it.

#### Scenario: Neph CLI built and linked
- **WHEN** e2e tests are about to run
- **THEN** `tools/neph-cli/dist/index.js` SHALL exist and `neph` SHALL be executable on PATH

### Requirement: Pi extension built for testing
The pi extension bundle SHALL be built before e2e tests run, since pi loads from `dist/pi.js`.

#### Scenario: Pi bundle is current
- **WHEN** e2e tests are about to run
- **THEN** `tools/pi/dist/pi.js` SHALL exist and be newer than or equal to `tools/pi/pi.ts` in mtime
