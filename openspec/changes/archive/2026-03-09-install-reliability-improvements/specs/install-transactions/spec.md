## ADDED Requirements

### Requirement: Atomic install operations
The system SHALL track all install operations (symlinks, merges, builds) in a transaction log and rollback on failure.

#### Scenario: Rollback symlinks on build failure
- **WHEN** symlinks are created but subsequent build fails
- **THEN** all symlinks created in that transaction are removed

#### Scenario: Rollback JSON merge on validation failure
- **WHEN** a JSON merge produces invalid JSON
- **THEN** the destination file is restored to its pre-merge state

### Requirement: Transaction state persistence
The system SHALL persist transaction state to disk so interrupted installs can be rolled back on next startup.

#### Scenario: Resume rollback after Neovim crash
- **WHEN** Neovim crashes mid-install
- **THEN** next startup detects incomplete transaction and rolls back partial changes

#### Scenario: Clean transaction log after success
- **WHEN** an install completes successfully
- **THEN** the transaction log for that agent is cleared

### Requirement: Per-agent transaction isolation
The system SHALL isolate transactions per agent so one agent's failure does not affect others.

#### Scenario: Pi install failure does not affect Claude
- **WHEN** `:NephTools install all` runs and pi install fails
- **THEN** claude's tools remain installed and functional

### Requirement: Backup creation before destructive operations
The system SHALL create backups of existing files before overwriting (JSON merges, config files).

#### Scenario: Backup existing settings.json before merge
- **WHEN** merging hooks into `~/.claude/settings.json`
- **THEN** a backup at `~/.claude/settings.json.bak-<timestamp>` is created first

#### Scenario: Restore from backup on merge failure
- **WHEN** a JSON merge fails validation
- **THEN** the system restores from the backup file
