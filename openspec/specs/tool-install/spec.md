## ADDED Requirements

### Requirement: Tools bundled in repo
neph.nvim SHALL include `tools/nvim-shim` (bash), `tools/shim.py` (Python), and `tools/pi.ts` (TypeScript) as checked-in files in the repository root `tools/` directory.

#### Scenario: Tools present after clone
- **WHEN** a user clones or installs neph.nvim via a plugin manager
- **THEN** `tools/nvim-shim`, `tools/shim.py`, and `tools/pi.ts` are present on disk under the plugin's install directory

### Requirement: Auto-symlink on setup
neph.nvim's `M.setup()` SHALL symlink `tools/shim.py` to `~/.local/bin/shim` and `tools/pi.ts` to `~/.pi/agent/extensions/nvim.ts`, creating parent directories as needed.

#### Scenario: Symlinks created on first setup
- **WHEN** `require("neph").setup()` is called and the tool files exist in the plugin's `tools/` directory
- **THEN** `~/.local/bin/shim` is a symlink pointing to `tools/shim.py`
- **THEN** `~/.pi/agent/extensions/nvim.ts` is a symlink pointing to `tools/pi.ts`

#### Scenario: Symlinks are force-updated
- **WHEN** `require("neph").setup()` is called and symlinks already exist at the target paths
- **THEN** the existing symlinks are replaced (`ln -sf`) without error

#### Scenario: Missing tool file is skipped with warning
- **WHEN** `require("neph").setup()` is called but a tool file is not found in the plugin's `tools/` directory
- **THEN** no symlink is created for that file
- **THEN** a `vim.notify` warning is emitted indicating the missing file

### Requirement: nvim-shim is not symlinked
`tools/nvim-shim` SHALL be bundled for reference and direct use but neph SHALL NOT automatically symlink it, as it is typically managed by the user's own PATH configuration.

#### Scenario: nvim-shim not auto-installed
- **WHEN** `require("neph").setup()` is called
- **THEN** no symlink to `tools/nvim-shim` is created automatically
