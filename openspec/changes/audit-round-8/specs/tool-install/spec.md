## ADDED Requirements

### Requirement: Install lock prevents concurrent builds

The tool installation system SHALL use per-agent advisory lock files to prevent multiple Neovim instances from building the same tool simultaneously.

#### Scenario: Lock acquired before build

- **WHEN** `install_async()` determines a tool needs building
- **THEN** it SHALL attempt to create `<state_dir>/neph/install-<name>.lock` with exclusive create
- **AND** the lock file SHALL contain the current process PID
- **AND** only if the lock is acquired SHALL the build proceed

#### Scenario: Lock already held by live process

- **WHEN** the lock file exists
- **AND** the PID in the lock file corresponds to a running process
- **THEN** the current instance SHALL skip the build for that tool
- **AND** the current instance SHALL NOT modify the fingerprint manifest for that tool

#### Scenario: Lock released after build

- **WHEN** a build completes (success or failure)
- **THEN** the lock file SHALL be removed
- **AND** removal failure SHALL be logged but SHALL NOT crash the plugin
