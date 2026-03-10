## ADDED Requirements

### Requirement: Structured error results
The system SHALL return structured error objects containing error code, message, and remediation steps for all install operations.

#### Scenario: Symlink creation failure
- **WHEN** symlink creation fails due to permission error
- **THEN** result contains `{ ok: false, error: "EPERM", message: "Permission denied", remedy: "Run with appropriate permissions or change target directory" }`

#### Scenario: Build failure with npm error
- **WHEN** npm build exits with non-zero code
- **THEN** result contains `{ ok: false, error: "BUILD_FAILED", message: "<npm stderr>", remedy: "Check package.json and node_modules" }`

### Requirement: Enhanced :NephTools status output
The system SHALL display colored status indicators and detailed diagnostics in `:NephTools status` output.

#### Scenario: Status shows color-coded symlink state
- **WHEN** `:NephTools status` is run
- **THEN** output shows "✓ pi symlink: ok" (green) or "✗ pi symlink: broken" (red)

#### Scenario: Status shows build staleness
- **WHEN** source files are newer than build artifacts
- **THEN** output shows "⚠ neph-cli build: stale (rebuild needed)" (yellow)

#### Scenario: Status suggests remediation
- **WHEN** any check fails
- **THEN** output includes "→ Fix: <command>" line with remediation

### Requirement: Verbose install mode
The system SHALL support a `--verbose` flag that logs all install operations in real-time to neph debug log.

#### Scenario: Verbose mode logs symlink creation
- **WHEN** `:NephTools install all --verbose` is run
- **THEN** debug log contains entries for each symlink: "tools: creating symlink <src> → <dst>"

#### Scenario: Verbose mode logs build steps
- **WHEN** npm build runs in verbose mode
- **THEN** debug log contains npm output and timing info

### Requirement: Actionable error messages
The system SHALL provide specific next steps for common failure modes (missing deps, permission errors, stale state).

#### Scenario: Missing node dependency
- **WHEN** install fails due to missing `node` binary
- **THEN** error message is "node not found. Install Node.js from https://nodejs.org or use system package manager"

#### Scenario: Permission denied on symlink
- **WHEN** symlink creation fails with EPERM
- **THEN** error message is "Permission denied creating symlink at <path>. Ensure <dir> is writable or run with sudo"

#### Scenario: Stale stamp detected
- **WHEN** plugin version changes but stamp is outdated
- **THEN** warning message is "Tools out of date. Run :NephTools reinstall all to update"
