## ADDED Requirements

### Requirement: Pre-flight dependency checks
The system SHALL verify required tools (node, npm) are available before attempting install operations.

#### Scenario: Missing node binary
- **WHEN** `node` is not on PATH
- **THEN** install fails immediately with error "node not found (required for tool builds)"

#### Scenario: Missing npm binary
- **WHEN** `npm` is not on PATH
- **THEN** install fails immediately with error "npm not found (required for tool builds)"

### Requirement: Post-install validation
The system SHALL validate all installed artifacts (symlinks, builds, merges) are functional after installation.

#### Scenario: Validate symlink is readable
- **WHEN** a symlink is created during install
- **THEN** post-install validation confirms the target exists and is readable

#### Scenario: Validate build artifact exists
- **WHEN** a build completes
- **THEN** post-install validation confirms the expected output file (e.g., `dist/index.js`) exists

#### Scenario: Validate merged JSON is parseable
- **WHEN** a JSON merge operation completes
- **THEN** post-install validation confirms the destination file is valid JSON

### Requirement: Agent executable verification
The system SHALL verify agent binaries are executable and return non-zero exit codes for invalid invocations.

#### Scenario: Agent binary responds to --help
- **WHEN** post-install runs `<agent> --help`
- **THEN** the command exits with code 0 or 1 (not 127/command-not-found)

### Requirement: Health check integration
The system SHALL surface verification failures in `:checkhealth neph` output with actionable remediation steps.

#### Scenario: Broken symlink shown in health
- **WHEN** `:checkhealth neph` is run and a symlink is broken
- **THEN** output shows "ERROR: pi symlink broken at ~/.pi/agent/extensions/nvim/dist → Run :NephTools reinstall pi"

#### Scenario: Missing build shown in health
- **WHEN** `:checkhealth neph` is run and a build artifact is missing
- **THEN** output shows "WARN: neph-cli build artifact missing → Run :NephTools install all"
