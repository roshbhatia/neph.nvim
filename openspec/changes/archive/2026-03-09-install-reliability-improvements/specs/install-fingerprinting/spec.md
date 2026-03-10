## ADDED Requirements

### Requirement: Content-based fingerprinting for build artifacts
The system SHALL compute SHA256 hashes of source files to detect when builds are stale, replacing the current git-hash stamp system.

#### Scenario: Detect stale build after source file change
- **WHEN** a source file (e.g., `tools/pi/pi.ts`) is modified
- **THEN** the fingerprint check detects the mismatch and triggers rebuild

#### Scenario: Skip rebuild when source unchanged
- **WHEN** source files have not changed since last build
- **THEN** the fingerprint check passes and no rebuild occurs

### Requirement: Per-file hash manifest
The system SHALL maintain a manifest file (`~/.local/state/neph/fingerprints.json`) mapping artifact paths to their source file hashes.

#### Scenario: Manifest persists across Neovim restarts
- **WHEN** Neovim restarts after successful install
- **THEN** the manifest file exists and contains valid hash entries

#### Scenario: Manifest update on successful install
- **WHEN** an agent's tools are installed successfully
- **THEN** the manifest is updated with new hashes for that agent's artifacts

### Requirement: Symlink target verification
The system SHALL verify symlink targets match expected paths and are readable, detecting broken or mispointed links.

#### Scenario: Detect broken symlink
- **WHEN** a symlink points to a nonexistent target
- **THEN** verification fails with a "broken symlink" error

#### Scenario: Detect wrong target
- **WHEN** a symlink points to an incorrect target path
- **THEN** verification fails with a "wrong target" error

### Requirement: Incremental fingerprint updates
The system SHALL update fingerprints only for agents being installed, leaving other agents' fingerprints untouched.

#### Scenario: Install single agent preserves others
- **WHEN** `:NephTools install pi` is run
- **THEN** only pi's fingerprints are updated, claude/goose/etc remain unchanged
