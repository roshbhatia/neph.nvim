## ADDED Requirements

### Requirement: CLI socket discovery determinism

When multiple Neovim instances are running, the CLI SHALL deterministically select the correct instance or refuse to guess. The CLI SHALL NOT silently connect to the wrong instance.

#### Scenario: Single Neovim instance running

- **WHEN** exactly one Neovim instance is detected via socket glob
- **THEN** the CLI SHALL return that instance's socket path without a cwd check

#### Scenario: Multiple instances with exact cwd match

- **WHEN** multiple Neovim instances are running
- **AND** one instance's cwd matches the CLI's cwd exactly
- **THEN** the CLI SHALL return that instance's socket path

#### Scenario: Multiple instances with same git root

- **WHEN** multiple Neovim instances are running
- **AND** two or more instances share the same git root as the CLI
- **AND** no exact cwd match exists
- **THEN** the CLI SHALL return null (no match)
- **AND** the caller SHALL require explicit `NVIM_SOCKET_PATH`

#### Scenario: Multiple instances with unique git root match

- **WHEN** multiple Neovim instances are running
- **AND** exactly one instance's git root matches the CLI's git root
- **AND** no exact cwd match exists
- **THEN** the CLI SHALL return that instance's socket path

### Requirement: Tool install inter-process locking

Concurrent `install_async()` or `install()` calls from multiple Neovim instances SHALL NOT corrupt build artifacts or the fingerprint manifest.

#### Scenario: Two instances start tool install simultaneously

- **WHEN** instance A acquires the install lock for agent "neph-cli"
- **AND** instance B attempts to install "neph-cli"
- **THEN** instance B SHALL detect the active lock and skip the build
- **AND** instance B SHALL NOT modify the manifest

#### Scenario: Lock file left by crashed instance

- **WHEN** an install lock file exists at `<state_dir>/neph/install-<name>.lock`
- **AND** the PID recorded in the lock file is no longer running
- **THEN** the lock SHALL be treated as stale
- **AND** the current instance SHALL remove the stale lock and proceed with installation

#### Scenario: Lock file contains invalid content

- **WHEN** an install lock file exists but contains non-numeric or empty content
- **THEN** the lock SHALL be treated as stale and removed
