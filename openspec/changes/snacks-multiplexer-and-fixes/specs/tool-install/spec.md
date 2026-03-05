## MODIFIED Requirements

### Requirement: Tools bundled in repo
neph.nvim SHALL include `tools/core/shim.py` (Python) and `tools/pi/pi.ts` (TypeScript) as checked-in files in the repository `tools/` directory. `tools/core/nvim-shim` (bash) is no longer part of the documented or bundled tool set.

#### Scenario: Tools present after clone
- **WHEN** a user clones or installs neph.nvim via a plugin manager
- **THEN** `tools/core/shim.py` and `tools/pi/pi.ts` are present on disk under the plugin's install directory

### Requirement: Auto-symlink on setup
neph.nvim's `M.setup()` SHALL symlink `tools/core/shim.py` to `~/.local/bin/shim` and `tools/pi/pi.ts` to `~/.pi/agent/extensions/nvim.ts`, creating parent directories as needed.

#### Scenario: Symlinks created on first setup
- **WHEN** `require("neph").setup()` is called and the tool files exist
- **THEN** `~/.local/bin/shim` is a symlink pointing to `tools/core/shim.py`
- **THEN** `~/.pi/agent/extensions/nvim.ts` is a symlink pointing to `tools/pi/pi.ts`

#### Scenario: Symlinks are force-updated
- **WHEN** `require("neph").setup()` is called and symlinks already exist
- **THEN** the existing symlinks are replaced (`ln -sf`) without error

#### Scenario: Missing tool file is skipped with warning
- **WHEN** `require("neph").setup()` is called but a tool file is not found
- **THEN** no symlink is created for that file
- **THEN** a `vim.notify` warning is emitted indicating the missing file

## REMOVED Requirements

### Requirement: nvim-shim is not symlinked
**Reason**: `tools/core/nvim-shim` (bash wrapper) has been removed from the repo. There is no longer anything to symlink or document.
**Migration**: Use `shim.py` (auto-symlinked to `~/.local/bin/shim`) for all Neovim msgpack-rpc integration.
