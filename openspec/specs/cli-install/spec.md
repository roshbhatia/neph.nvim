## MODIFIED Requirements

### Requirement: CLI symlink is managed by the build step, not only setup()

The `~/.local/bin/neph` symlink SHALL be created by `scripts/build.sh` (and thus by the lazy `build` hook and `:NephBuild`). The `setup()` auto-repair SHALL remain as a safety net but SHALL be demoted to a silent fallback that only fires when the symlink is missing.

#### Scenario: Build hook creates symlink

- **WHEN** the lazy `build` hook or `:NephBuild` runs to completion
- **THEN** `~/.local/bin/neph` SHALL point to `tools/neph-cli/dist/index.js`
- **AND** no notification SHALL be shown (build output covers it)

#### Scenario: setup() repairs missing symlink silently

- **WHEN** `setup()` runs and `~/.local/bin/neph` is absent
- **THEN** the symlink SHALL be created silently (no notification unless install_cli fails)
- **AND** the auto-repair SHALL NOT duplicate the build step (it symlinks the existing dist, does not compile)

#### Scenario: checkhealth surfaces missing symlink

- **WHEN** `checkhealth neph` runs and `~/.local/bin/neph` does not exist
- **THEN** the health check SHALL report ERROR: "neph CLI not installed at ~/.local/bin/neph"
- **AND** the hint SHALL include "Run :NephBuild or :NephInstall"

#### Scenario: PATH visibility warning

- **WHEN** `~/.local/bin/neph` exists but `~/.local/bin` is not on `$PATH`
- **THEN** the health check SHALL report WARN: "~/.local/bin not on $PATH — agent plugins cannot spawn the CLI"
