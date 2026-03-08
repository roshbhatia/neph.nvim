## MODIFIED Requirements

### Requirement: Tools bundled in repo
neph.nvim SHALL include agent-specific tool files in the `tools/` directory. Each agent's tool manifest references paths relative to this directory. The `tools/neph-cli/` directory contains the universal neph CLI.

#### Scenario: Tools present after clone
- **WHEN** a user clones or installs neph.nvim via a plugin manager
- **THEN** the `tools/` directory SHALL contain agent-specific subdirectories referenced by agent manifests

### Requirement: Auto-symlink on setup
neph.nvim's `M.setup()` SHALL defer tool installation to a UIEnter autocmd. The install SHALL check a stamp file first and skip entirely if the plugin directory has not changed. When install runs, it SHALL iterate injected agents' `tools` manifests and process symlinks, merges, builds, and files generically. All filesystem operations SHALL execute in background jobs via `vim.fn.jobstart()`.

#### Scenario: Symlinks created from agent manifests
- **WHEN** `tools.install_async()` runs and agents have `tools.symlinks` manifests
- **THEN** symlinks are created asynchronously for each agent's declared symlinks
- **AND** the executor does NOT reference any agent by name

#### Scenario: Merges processed from agent manifests
- **WHEN** `tools.install_async()` runs and agents have `tools.merges` manifests
- **THEN** JSON merges are performed for each agent's declared merges

#### Scenario: Builds processed from agent manifests
- **WHEN** `tools.install_async()` runs and agents have `tools.builds` manifests
- **THEN** npm builds are triggered only when source is newer than the check file

#### Scenario: Files created from agent manifests
- **WHEN** `tools.install_async()` runs and agents have `tools.files` manifests
- **THEN** files are created according to the declared mode (create_only or overwrite)

#### Scenario: Stamp-based skip on subsequent startups
- **WHEN** `require("neph").setup()` is called and the stamp file is newer than the tools/ directory
- **THEN** no installation work is performed

#### Scenario: tools.lua contains zero agent names
- **WHEN** `lua/neph/tools.lua` is read
- **THEN** it SHALL NOT contain any hardcoded agent names (pi, claude, cursor, amp, opencode, gemini, etc.)
- **AND** the only hardcoded tool path SHALL be `neph-cli` (universal)

## REMOVED Requirements

### Requirement: nvim-shim is not symlinked
**Reason**: Already removed in previous change. No further action.
**Migration**: N/A
